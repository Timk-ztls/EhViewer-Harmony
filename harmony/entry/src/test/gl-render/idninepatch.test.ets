/*
 * GLES11IdImpl + NinePatchChunk 单测
 *
 * 两个都是"错了不报错、只是数据错"的模块：
 *   1) id 分配：起始必须是 1（0 在 GL 里表示无纹理）；glGenBuffers 的倒序填充写法决定了 id 次序
 *   2) nine-patch：三个 count 是 u8、数组是 i32；divX/divY 校验偶数非 0，color 不校验
 */

import { GLES11IdImpl } from '../../main/ets/hippo/lib/glview/glrenderer/GLES11IdImpl';
import { NinePatchChunk } from '../../main/ets/hippo/lib/glview/glrenderer/NinePatchChunk';
import { GLNative, GLNativeBackend } from '../../main/ets/hippo/lib/glview/native/GLNativeBridge';

/** 只计数删除调用的假 backend。 */
class FakeIdBackend implements GLNativeBackend {
  deletedTextures: number[] = [];
  deletedBuffers: number[] = [];
  deletedFramebuffers: number[] = [];

  init(): number { return 0; }
  setSurface(width: number, height: number): number { return 0; }
  destroySurface(): number { return 0; }
  replay(cmds: Float32Array): number { return 0; }
  present(): number { return 0; }
  genTexture(): number { return 1; }
  deleteTexture(id: number): number { this.deletedTextures.push(id); return 0; }
  genBuffer(target: number): number { return 1; }
  bufferDataF32(id: number, data: Float32Array): number { return 0; }
  bufferDataU8(id: number, data: Uint8Array): number { return 0; }
  deleteBuffer(id: number): number { this.deletedBuffers.push(id); return 0; }
  genFramebuffer(): number { return 1; }
  unbindFramebuffer(): number { return 0; }
  deleteFramebuffer(id: number): number { this.deletedFramebuffers.push(id); return 0; }
  getErrorCode(): number { return 0; }
  getString(what: number): string { return ''; }
  texImage2D(id: number, width: number, height: number, format: number, type: number, pixelMap: Object): number { return 0; }
  texSubImage2D(id: number, xOffset: number, yOffset: number, width: number, height: number, format: number, type: number, pixelMap: Object): number { return 0; }
  texSubImage2DFill(id: number, xOffset: number, yOffset: number, width: number, height: number, format: number, type: number, rgba: number): number { return 0; }
  texImageRegion(id: number, init: boolean, pixelMap: Object, srcX: number, srcY: number, srcW: number, srcH: number, dstX: number, dstY: number, texW: number, texH: number): number { return 0; }
}

let pass = 0;
const fails: string[] = [];
function eq(name: string, got: unknown, want: unknown): void {
  const g = JSON.stringify(got);
  const w = JSON.stringify(want);
  if (g === w) { pass++; } else { fails.push(`${name}: got ${g} want ${w}`); }
}
function ok(name: string, cond: boolean): void {
  if (cond) { pass++; } else { fails.push(name); }
}
function throws(name: string, fn: () => void, msg: string): void {
  try {
    fn();
    fails.push(name + '（未抛异常）');
  } catch (e) {
    if ((e as Error).message === msg) { pass++; } else {
      fails.push(name + `（消息是 "${(e as Error).message}"）`);
    }
  }
}

// ---------------------------------------------------------------- 1. id 分配
{
  GLES11IdImpl.resetForTest();
  eq('id 从 1 开始（0 表示无纹理）', new GLES11IdImpl().generateTexture(), 1);
  eq('第二个 id 是 2', new GLES11IdImpl().generateTexture(), 2);

  // glGenBuffers 的倒序填充：**数组里是降序**（[5,4,3]），不是升序。
  // 上游 while (n-- > 0) { buffers[offset + n] = sNextId++; } 就是这个结果——
  // 写起来"看起来像顺序填充"，实际是降序，且不报错。这里锁住真实行为。
  const buffers: number[] = [0, 0, 0, 0, 0];
  new GLES11IdImpl().glGenBuffers(3, buffers, 1);
  eq('glGenBuffers 填入 offset=1 起的 3 个（降序，照搬上游）',
    [buffers[0], buffers[1], buffers[2], buffers[3], buffers[4]], [0, 5, 4, 3, 0]);

  // n = 0 不应改动数组，也不消耗 id
  const before: number = new GLES11IdImpl().generateTexture();
  const arr2: number[] = [7, 7];
  new GLES11IdImpl().glGenBuffers(0, arr2, 0);
  eq('n=0 不改数组', arr2, [7, 7]);
  eq('n=0 不消耗 id（下一次分配 = before+1）', new GLES11IdImpl().generateTexture(), before + 1);

  // 删除走 native backend（与 GLES20IdImpl 同形）；未注册 backend 时应抛明确错误，
  // 因此这里注册一个假 backend 并计数
  GLNative.register(new FakeIdBackend());
  const fb = GLNative.backend() as FakeIdBackend;
  new GLES11IdImpl().glDeleteTextures(2, [11, 12, 13], 1);
  eq('glDeleteTextures 按 offset/n 逐项删除', fb.deletedTextures, [12, 13]);
  new GLES11IdImpl().glDeleteBuffers(1, [21], 0);
  eq('glDeleteBuffers 删除', fb.deletedBuffers, [21]);
  new GLES11IdImpl().glDeleteFramebuffers(1, [31], 0);
  eq('glDeleteFramebuffers 删除', fb.deletedFramebuffers, [31]);
  new GLES11IdImpl().glDeleteTextures(1, [0], 0);
  eq('id=0 不删除（0 表示无纹理）', fb.deletedTextures, [12, 13]);
}

// ---------------------------------------------------------------- 2. NinePatchChunk 反序列化
{
  // 构造一个合法 chunk：divX=2, divY=2, color=1
  // 布局：u8 wasSer | u8 divX | u8 divY | u8 color | i32 skip×2 | 4×pad | i32 skip | divX,divY,color
  const total = 4 + 8 + 16 + 4 + (2 + 2 + 1) * 4;
  const buf = new ArrayBuffer(total);
  const dv = new DataView(buf);
  let o = 0;
  dv.setUint8(o++, 1);          // wasSerialized
  dv.setUint8(o++, 2);          // divXCount
  dv.setUint8(o++, 2);          // divYCount
  dv.setUint8(o++, 1);          // colorCount
  dv.setInt32(o, 0, true); o += 4;   // skip
  dv.setInt32(o, 0, true); o += 4;   // skip
  dv.setInt32(o, 10, true); o += 4;  // padLeft
  dv.setInt32(o, 20, true); o += 4;  // padRight
  dv.setInt32(o, 30, true); o += 4;  // padTop
  dv.setInt32(o, 40, true); o += 4;  // padBottom
  dv.setInt32(o, 0, true); o += 4;   // skip
  dv.setInt32(o, 100, true); o += 4; // divX[0]
  dv.setInt32(o, 200, true); o += 4; // divX[1]
  dv.setInt32(o, 300, true); o += 4; // divY[0]
  dv.setInt32(o, 400, true); o += 4; // divY[1]
  dv.setInt32(o, 0xFF00FF00, true); o += 4; // color[0]

  const chunk = NinePatchChunk.deserialize(buf);
  ok('deserialize 返回非 null', chunk !== null);
  const c = chunk as NinePatchChunk;
  eq('mDivX', c.mDivX, [100, 200]);
  eq('mDivY', c.mDivY, [300, 400]);
  // Java int[] 是有符号的：0xFF00FF00 读出来是 -16711936（不是 4278255360）
  eq('mColor（有符号 int）', c.mColor, [0xFF00FF00 | 0]);
  eq('paddings.left', c.mPaddings.left, 10);
  eq('paddings.right', c.mPaddings.right, 20);
  eq('paddings.top', c.mPaddings.top, 30);
  eq('paddings.bottom', c.mPaddings.bottom, 40);

  // wasSerialized = 0 → null（不抛）
  const none = new ArrayBuffer(4);
  new DataView(none).setUint8(0, 0);
  eq('wasSerialized=0 → null', NinePatchChunk.deserialize(none), null);

  // 常量值
  eq('NO_COLOR = 1', NinePatchChunk.NO_COLOR, 1);
  eq('TRANSPARENT_COLOR = 0', NinePatchChunk.TRANSPARENT_COLOR, 0);
}

// ---------------------------------------------------------------- 3. 校验：divX/divY 必须偶数非 0
{
  const make = (divX: number, divY: number): ArrayBuffer => {
    const buf = new ArrayBuffer(64);
    const dv = new DataView(buf);
    dv.setUint8(0, 1);
    dv.setUint8(1, divX);
    dv.setUint8(2, divY);
    dv.setUint8(3, 0);
    return buf;
  };
  throws('divX 为奇数 → invalid nine-patch', () => { NinePatchChunk.deserialize(make(3, 2)); },
    'invalid nine-patch: 3');
  throws('divX 为 0 → invalid nine-patch', () => { NinePatchChunk.deserialize(make(0, 2)); },
    'invalid nine-patch: 0');
  throws('divY 为奇数 → invalid nine-patch', () => { NinePatchChunk.deserialize(make(2, 5)); },
    'invalid nine-patch: 5');
}

console.log(`\n=== 结果：${pass} passed, ${fails.length} failed ===`);
if (fails.length > 0) {
  for (const f of fails) {
    console.log('  FAIL ' + f);
  }
  throw new Error('idimpl/ninepatchchunk 断言失败：' + fails.length);
}
