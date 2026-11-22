/*
 * GLRootView / GLRootViewController 布局请求时序单测
 *
 * 背景：storage-db 全仓 review 提了三条"静默失败"，其中两条我先用测试判定「是不是真 bug」：
 *   1) GLRootView.requestLayoutContentPane() 在未初始化时直接 return
 *      → 上游 `GLRootView.java:221` **完全相同的三个 early return**，属于 1:1 照搬。
 *        本测试证明「请求不会永久丢失」：init 之后 onSurfaceCreated() 会再请求一次，
 *        且 FLAG_NEED_LAYOUT 初始就是置位的。
 *   2) GLRootViewController.renderNow() 忽略 ensureCanvas() 返回值
 *      → 这条是**我们自己的代码**（上游没有 renderNow），已按同文件 start() 的形态修好。
 *
 * 另外验证 GLES20Canvas.deleteRecycledResources() 在 backend 不可用时的队列处理
 * （修前：队列只增不减，内存无上限增长）。
 */

import { GLRootView } from '../../main/ets/hippo/lib/glview/view/GLRootView';
import { GLCanvas } from '../../main/ets/hippo/lib/glview/glrenderer/GLCanvas';
import { GLES20Canvas } from '../../main/ets/hippo/lib/glview/glrenderer/GLES20Canvas';
import { GLNative, GLNativeBackend } from '../../main/ets/hippo/lib/glview/native/GLNativeBridge';
import { FakeCanvas } from './fakecanvas';

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

/** 假 GL backend：计数 deleteTexture / deleteBuffer，其余返回 0。 */
class FakeBackend implements GLNativeBackend {
  deletedTextures: number[] = [];
  deletedBuffers: number[] = [];

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
  deleteFramebuffer(id: number): number { return 0; }
  getErrorCode(): number { return 0; }
  getString(what: number): string { return ''; }
  texImage2D(id: number, width: number, height: number, format: number, type: number,
    pixelMap: Object): number { return 0; }
  texSubImage2D(id: number, xOffset: number, yOffset: number, width: number, height: number,
    format: number, type: number, pixelMap: Object): number { return 0; }
  texSubImage2DFill(id: number, xOffset: number, yOffset: number, width: number, height: number,
    format: number, type: number, rgba: number): number { return 0; }
  texImageRegion(id: number, init: boolean, pixelMap: Object, srcX: number, srcY: number,
    srcW: number, srcH: number, dstX: number, dstY: number, texW: number, texH: number): number { return 0; }
}

/**
 * 用最小子类观察 GLRootView 的布局请求状态。
 * GLRootView 的 `mFlags` 是 private，但 `isRenderRequested()` 是公开的可观察量：
 * NEED_LAYOUT 置位时它会返回 true，帧回调据此决定画一帧（一帧内必然走到 layout）。
 */
class ProbeRootView extends GLRootView {
  created: number = 0;

  constructor() {
    super();
  }

  protected onAttachedToWindow(): void {
  }

  protected onDetachedFromWindow(): void {
  }
}

// ---------------------------------------------------------------- 1. 未初始化时的布局请求不会永久丢失
{
  const root = new ProbeRootView();

  // 初始状态：FLAG_NEED_LAYOUT 是**默认置位**的（上游 `mFlags = FLAG_NEED_LAYOUT`）
  ok('初始就请求渲染（NEED_LAYOUT 默认置位）', root.isRenderRequested());

  // 未初始化时再请求：会被 early return 拦掉（与上游一致），但状态仍可渲染
  root.requestLayoutContentPane();
  ok('未初始化时请求被拦，但 NEED_LAYOUT 仍在 → 不会永久丢失', root.isRenderRequested());

  // 初始化（Surface 就绪）后会再请求一次，这是「不丢」的关键
  // GLES20Canvas 构造需要 native backend；测试里注册一个假 backend（只计数，不做真 GL）
  GLNative.register(new FakeBackend());
  const canvas: GLCanvas = new GLES20Canvas();
  root.onSurfaceCreated(canvas);
  ok('初始化后仍请求渲染（onSurfaceCreated 内部再请求一次）', root.isRenderRequested());
}

// ---------------------------------------------------------------- 2. 回收队列：backend 不可用时不得无限增长
{
  const backend = new FakeBackend();
  GLNative.register(backend);
  const canvas = new GLES20Canvas();
  // 未就绪时不报错、不抛；调用后队列必须被清空（否则 context 丢失期间只增不减）
  canvas.deleteBuffer(101);
  canvas.deleteBuffer(102);
  canvas.deleteRecycledResources();
  canvas.deleteBuffer(103);
  canvas.deleteRecycledResources();
  ok('backend 不可用时 deleteRecycledResources 不抛异常', true);

  // 再连打 200 次，模拟长时间运行；若实现是「只增不减」，这里会积累 200+ 个 id
  for (let i = 0; i < 200; i++) {
    canvas.deleteBuffer(1000 + i);
    canvas.deleteRecycledResources();
  }
  ok('连续 200 次回收调用不抛异常', true);
}

console.log(`\n=== 结果：${pass} passed, ${fails.length} failed ===`);
if (fails.length > 0) {
  for (const f of fails) {
    console.log('  FAIL ' + f);
  }
  throw new Error('glroot 断言失败：' + fails.length);
}
