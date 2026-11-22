import { GLPaint } from '../../main/ets/hippo/lib/glview/glrenderer/GLPaint';
import { UploadedTexture } from '../../main/ets/hippo/lib/glview/glrenderer/UploadedTexture';
import { GLES20Canvas } from '../../main/ets/hippo/lib/glview/glrenderer/GLES20Canvas';
import { BasicTexture } from '../../main/ets/hippo/lib/glview/glrenderer/BasicTexture';
import { GLCanvas } from '../../main/ets/hippo/lib/glview/glrenderer/GLCanvas';
import { GLCommandBuffer, GLCommandRecord } from '../../main/ets/hippo/lib/glview/native/GLCommandBuffer';
import { GLErr, GLCommand, GLNative, GLNativeBackend } from '../../main/ets/hippo/lib/glview/native/GLNativeBridge';
import { GLConst } from '../../main/ets/hippo/lib/glview/native/GLConst';
import { Rect } from '../../main/ets/hippo/lib/glview/util/Rect';
import { RectF } from '../../main/ets/hippo/lib/glview/util/RectF';

let pass = 0; const fails: string[] = [];
function eq(name: string, got: unknown, want: unknown): void {
  const g = typeof got === 'number' ? got.toFixed(6) : JSON.stringify(got);
  const w = typeof want === 'number' ? (want as number).toFixed(6) : JSON.stringify(want);
  if (g === w) pass++; else fails.push(`${name}: got ${g} want ${w}`);
}
function ok(name: string, cond: boolean): void { if (cond) pass++; else fails.push(name); }

// ---------- mock backend ----------
class MockBackend implements GLNativeBackend {
  lastReplay: Float32Array | null = null;
  replayCount = 0;
  surfaceW = 0; surfaceH = 0;
  boxBuffer: Float32Array | null = null;
  initCalls = 0;
  nextTextureId = 100;
  init(): GLErr { this.initCalls++; return GLErr.OK; }
  setSurface(w: number, h: number): GLErr { this.surfaceW = w; this.surfaceH = h; return GLErr.OK; }
  destroySurface(): GLErr { return GLErr.OK; }
  replay(cmds: Float32Array): GLErr { this.lastReplay = cmds; this.replayCount++; return GLErr.OK; }
  presentCalls = 0;
  present(): GLErr { this.presentCalls++; return GLErr.OK; }
  texSubImage2DFill(): GLErr { return GLErr.OK; }
  genTexture(): number { return this.nextTextureId++; }
  deleteTexture(_id: number): GLErr { return GLErr.OK; }
  texImage2D(): GLErr { return GLErr.OK; }
  texSubImage2D(): GLErr { return GLErr.OK; }
  genBuffer(_target: number): number { return 7; }
  bufferDataF32(_id: number, data: Float32Array): GLErr { this.boxBuffer = data; return GLErr.OK; }
  bufferDataU8(): GLErr { return GLErr.OK; }
  deleteBuffer(_id: number): GLErr { return GLErr.OK; }
  genFramebuffer(): number { return 3; }
  unbindFramebuffer(): GLErr { return GLErr.OK; }
  deleteFramebuffer(_id: number): GLErr { return GLErr.OK; }
  getErrorCode(): number { return 0; }
  getString(_what: number): string { return 'mock'; }
}

class FakeTexture extends BasicTexture {
  constructor(w: number, h: number) { super(null, 0, BasicTexture['STATE_UNLOADED']); this.setSize(w, h); this.mId = 42; }
  onBind(_c: GLCanvas): boolean { return true; }
  getTarget(): number { return GLConst.GL_TEXTURE_2D; }
  isOpaque(): boolean { return true; }
}

const backend = new MockBackend();
GLNative.register(backend);

// ---------- 构造：命令流缓冲 + BOX_COORDINATES 上传 ----------
const canvas = new GLES20Canvas();
eq('init called once', backend.initCalls, 1);
ok('box buffer uploaded', backend.boxBuffer !== null);
// OFFSET_LAST = 0+4+2+4+1+120+1 = 132 个顶点，每顶点 2 float
eq('BOX_COORDINATES float count', backend.boxBuffer!.length, 132 * 2);
// 圆心顶点 = (0.5, 0.5) 位于 OFFSET_FILL_CIRCLE*2 = 10*2=20
eq('box circle center', [backend.boxBuffer![20], backend.boxBuffer![21]], [0.5, 0.5]);

// ---------- 第一帧：setSize + clear + fillRect ----------
canvas.beginFrame();
canvas.setSize(100, 200);
canvas.clearBuffer();
canvas.fillRect(10, 20, 30, 40, 0xFF00FF00 | 0);
canvas.flush();

const recs1 = GLCommandBuffer.decode(backend.lastReplay!);
const ops1 = recs1.map((r: GLCommandRecord) => r.op);
eq('frame1 cmd sequence', ops1,
  [GLCommand.SET_VIEWPORT, GLCommand.CLEAR, GLCommand.USE_PROGRAM, GLCommand.BLEND_ENABLE,
   GLCommand.UNIFORM_COLOR, GLCommand.BIND_ARRAY_BUFFER, GLCommand.VERTEX_ATTRIB_POINTER,
   GLCommand.BIND_ARRAY_BUFFER, GLCommand.UNIFORM_MATRIX, GLCommand.ENABLE_ATTRIB,
   GLCommand.DRAW_ARRAYS, GLCommand.DISABLE_ATTRIB, GLCommand.END_FRAME]);
eq('viewport args', recs1[0].args, [100, 200]);
eq('clear args', recs1[1].args, [0, 0, 0, 1]);
eq('use_program draw', recs1[2].args, [GLES20Canvas.PROGRAM_DRAW]);
// 绿色不透明 -> blending disabled, 无 BLEND_COLOR 命令
eq('blend disabled', recs1[3].args, [0]);
eq('uniform color premultiplied', recs1[4].args, [0, 0, 1, 0, 1]);
eq('bind box vbo', recs1[5].args, [7]);
eq('attrib pointer offset 0 (fill rect)', recs1[6].args, [0, 0, 2, 0]);
// 矩阵：ortho(0..100, 0..200) * translate(10,20) * scale(30,40)
const M = recs1[8].args.slice(1);
eq('matrix x scale', M[0], 2 / 100 * 30);
// 屏幕路径会把当前矩阵 y 翻转为 T(0,h)*S(1,-1,1)，故 y 缩放与平移取负
eq('matrix y scale (flipped)', M[5], -(2 / 200) * 40);
eq('matrix tx', M[12], (10 / 100) * 2 - 1);
eq('matrix ty (flipped)', M[13], 1 - (20 / 200) * 2);
eq('draw arrays', recs1[10].args, [GLConst.GL_TRIANGLE_STRIP, 0, 4]);

// ---------- save/restore 与 alpha 栈 ----------
canvas.beginFrame();
canvas.save(GLCanvas.SAVE_FLAG_ALPHA);
canvas.multiplyAlpha(0.5);
canvas.fillRect(0, 0, 10, 10, 0xFF0000FF | 0);
canvas.restore();
eq('alpha restored', canvas.getAlpha(), 1);
canvas.flush();
const recs2 = GLCommandBuffer.decode(backend.lastReplay!);
const useProgram2 = recs2.filter((r: GLCommandRecord) => r.op === GLCommand.USE_PROGRAM);
ok('draw issued with alpha', useProgram2.length === 1);
const blendEnable2 = recs2.find((r: GLCommandRecord) => r.op === GLCommand.BLEND_ENABLE);
eq('semi-transparent enables blending', blendEnable2!.args, [1]);
const blendColor2 = recs2.find((r: GLCommandRecord) => r.op === GLCommand.BLEND_COLOR);
ok('blend color emitted when blending', blendColor2 !== undefined);

// ---------- 纹理绘制路径 ----------
const tex = new FakeTexture(64, 32);
canvas.beginFrame();
canvas.setSize(100, 200);
canvas.drawTexture(tex, 5, 6, 20, 10);
canvas.flush();
const recs3 = GLCommandBuffer.decode(backend.lastReplay!);
const ops3 = recs3.map((r: GLCommandRecord) => r.op);
ok('texture path uses PROGRAM_TEXTURE',
  recs3.some((r: GLCommandRecord) => r.op === GLCommand.USE_PROGRAM && r.args[0] === GLES20Canvas.PROGRAM_TEXTURE));
ok('texture bound', recs3.some((r: GLCommandRecord) => r.op === GLCommand.BIND_TEXTURE && r.args[0] === GLConst.GL_TEXTURE_2D && r.args[1] === 42));
ok('sampler uniform set', recs3.some((r: GLCommandRecord) => r.op === GLCommand.UNIFORM_SAMPLER && r.args[1] === 0));
ok('alpha uniform set', recs3.some((r: GLCommandRecord) => r.op === GLCommand.UNIFORM_ALPHA));
const texMatrixRec = recs3.find((r: GLCommandRecord) => r.op === GLCommand.UNIFORM_TEXTURE_MATRIX);
// 源矩形 (0,0,64,32) 归一化到纹理尺寸 (64,32) => scale 1,1 / offset 0,0
eq('texture matrix', [texMatrixRec!.args[1], texMatrixRec!.args[6], texMatrixRec!.args[13], texMatrixRec!.args[14]], [1, 1, 0, 0]);
ok('texture draw is triangle strip', recs3.some((r: GLCommandRecord) => r.op === GLCommand.DRAW_ARRAYS && r.args[0] === GLConst.GL_TRIANGLE_STRIP));

// ---------- getBounds ----------
const b = new Rect();
canvas.beginFrame();
canvas.setSize(100, 200);
canvas.getBounds(b, 10, 20, 30, 40);
// y 翻转后：top=200-60=140, bottom=200-20=180
eq('getBounds (flipped)', [b.left, b.top, b.right, b.bottom], [10, 140, 40, 180]);

// ---------- 未注册后端的行为 ----------
GLNative.unregister();
ok('not ready without backend', !GLNative.isReady());
try { GLNative.backend(); fails.push('backend() should throw when unregistered'); } catch { pass++; }





// ---------- UploadedTexture：上传顺序 + 页边填充 + 节流配额 ----------
{
  const calls: string[] = [];
  class ProbeTexture extends UploadedTexture {
    constructor(w: number, h: number, border: boolean) { super(border); this.w = w; this.h = h; }
    w: number; h: number;
    protected onGetBitmap(): any {
      return { getImageInfoSync: () => ({ size: { width: this.w, height: this.h } }) } as any;
    }
    protected onFreeBitmap(): void { calls.push('free'); }
  }
  const tex = new ProbeTexture(100, 60, true);   // 带 1px 边框 => 内容 102x62 => 纹理 128x64
  const recordingCanvas: any = {
    getGLId: () => ({ generateTexture: () => 77 }),
    setTextureParameters: () => calls.push('setTextureParameters'),
    initializeTexture: () => calls.push('initializeTexture'),
    initializeTextureSize: (t: any, f: number, ty: number) => calls.push(`initializeTextureSize(${t.getTextureWidth()}x${t.getTextureHeight()},${f.toString(16)},${ty.toString(16)})`),
    texSubImage2D: (t: any, x: number, y: number) => calls.push(`texSubImage2D(${x},${y})`),
    texSubImage2DFill: (t: any, x: number, y: number, w: number, h: number) => calls.push(`fill(${x},${y},${w},${h})`)
  };
  tex.onBind(recordingCanvas);
  eq('upload seq', calls.join(' | '),
    'setTextureParameters | initializeTextureSize(128x64,1908,1401) | texSubImage2D(1,1) | fill(0,0,1,64) | fill(0,0,128,1) | fill(101,0,1,64) | fill(0,61,128,1) | free');
  eq('texture id', tex.getId(), 77);
  ok('content valid after upload', tex.isContentValid());
  ok('texture is opaque by default', tex.isOpaque());

  // 节流：只有 throttled 纹理才消耗配额，且超过 100 次后不再上传
  UploadedTexture.resetUploadLimit();
  let uploads = 0;
  class ThrottledProbe extends ProbeTexture {
    constructor() { super(4, 4, false); this.setThrottled(true); }
    protected onGetBitmap(): any { uploads++; return { getImageInfoSync: () => ({ size: { width: 4, height: 4 } }) } as any; }
  }
  const t2 = new ThrottledProbe();
  t2.onBind(recordingCanvas);
  ok('throttled upload counted', UploadedTexture.uploadLimitReached() === false);
}

// ---------- 顶点属性 offset 回归：4 条绘制路径各自的 BOX_COORDINATES 起始顶点 ----------
// 上游 OFFSET_FILL_RECT=0 / OFFSET_DRAW_LINE=4 / OFFSET_DRAW_RECT=6 / OFFSET_FILL_CIRCLE=10，
// 每顶点 2 float => 偏移字节 = 顶点下标 * 8。native 侧若把该参数当 stride 用，
// fillRect 恰好 offset=0 看不出来，drawLine/drawRect/fillOval 会画错顶点集。
{
  GLNative.register(backend);   // 上一段测试故意解绑过后端，这里恢复
  const paint = new GLPaint();
  paint.setColor(0xFFFF0000 | 0);
  paint.setLineWidth(2);
  const cases: { name: string; want: number; act: () => void }[] = [
    { name: 'fillRect', want: 0 * 8, act: () => canvas.fillRect(0, 0, 1, 1, 0xFFFFFFFF | 0) },
    { name: 'drawLine', want: 4 * 8, act: () => canvas.drawLine(0, 0, 1, 1, paint) },
    { name: 'drawRect', want: 6 * 8, act: () => canvas.drawRect(0, 0, 1, 1, paint) },
    { name: 'fillOval', want: 10 * 8, act: () => canvas.fillOval(5, 5, 2, 2, 0xFFFFFFFF | 0) }
  ];
  for (const c of cases) {
    canvas.beginFrame();
    canvas.setSize(100, 200);
    c.act();
    canvas.flush();
    const recs = GLCommandBuffer.decode(backend.lastReplay!);
    const vp = recs.find((r: GLCommandRecord) => r.op === GLCommand.VERTEX_ATTRIB_POINTER);
    eq(`attrib offset ${c.name}`, vp!.args[3], c.want);
    eq(`attrib size ${c.name}`, vp!.args[2], 2);   // 2 float/顶点 => stride = 2*4 = 8 恒定
    eq(`attrib slot ${c.name}`, vp!.args[1], 0);
    eq(`attrib kind ${c.name}`, vp!.args[0], 0);
  }
}

console.log(`PASS ${pass}  FAIL ${fails.length}`);
for (const f of fails) console.log('  x ' + f);
process.exit(fails.length === 0 ? 0 : 1);
