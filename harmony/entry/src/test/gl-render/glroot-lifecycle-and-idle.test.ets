/*
 * GLRootView dirty listener / onGLIdle 排空 / GLES20Canvas 帧错误追踪单测（Stage C Track P5）。
 */

import { GLCanvas } from '../../main/ets/hippo/lib/glview/glrenderer/GLCanvas';
import { GLES20Canvas } from '../../main/ets/hippo/lib/glview/glrenderer/GLES20Canvas';
import { GLErr, GLNative, GLNativeBackend } from '../../main/ets/hippo/lib/glview/native/GLNativeBridge';
import { GLRootOnGLIdleListener } from '../../main/ets/hippo/lib/glview/view/GLRoot';
import { GLRootView } from '../../main/ets/hippo/lib/glview/view/GLRootView';
import { GLView } from '../../main/ets/hippo/lib/glview/view/GLView';

let pass = 0;
const fails: string[] = [];

function eq(name: string, got: unknown, want: unknown): void {
  const g = JSON.stringify(got);
  const w = JSON.stringify(want);
  if (g === w) {
    pass++;
  } else {
    fails.push(`${name}: got ${g} want ${w}`);
  }
}

function ok(name: string, cond: boolean): void {
  if (cond) {
    pass++;
  } else {
    fails.push(name);
  }
}

class FaultyBackend implements GLNativeBackend {
  nextReplayErr: GLErr = GLErr.OK;
  nextPresentErr: GLErr = GLErr.OK;

  init(): GLErr { return GLErr.OK; }
  setSurface(_w: number, _h: number): GLErr { return GLErr.OK; }
  destroySurface(): GLErr { return GLErr.OK; }
  replay(_cmds: Float32Array): GLErr { return this.nextReplayErr; }
  present(): GLErr { return this.nextPresentErr; }
  genTexture(): number { return 1; }
  deleteTexture(_id: number): GLErr { return GLErr.OK; }
  texImage2D(): GLErr { return GLErr.OK; }
  texSubImage2D(): GLErr { return GLErr.OK; }
  texSubImage2DFill(): GLErr { return GLErr.OK; }
  genBuffer(): number { return 1; }
  bufferDataF32(): GLErr { return GLErr.OK; }
  bufferDataU8(): GLErr { return GLErr.OK; }
  deleteBuffer(): GLErr { return GLErr.OK; }
  genFramebuffer(): number { return 1; }
  unbindFramebuffer(): GLErr { return GLErr.OK; }
  deleteFramebuffer(): GLErr { return GLErr.OK; }
  getErrorCode(): number { return 0; }
  getString(_what: number): string { return ''; }
}

class IdleCounterListener implements GLRootOnGLIdleListener {
  calls: number = 0;
  keepAliveFrames: number;

  constructor(keepAliveFrames: number) {
    this.keepAliveFrames = keepAliveFrames;
  }

  onGLIdle(_canvas: GLCanvas, _renderRequested: boolean): boolean {
    this.calls++;
    return this.calls < this.keepAliveFrames;
  }
}

// 1) dirty listener 与 onGLIdle 在 onDrawFrame 中的排空调度
{
  const backend = new FaultyBackend();
  GLNative.register(backend);
  const canvas = new GLES20Canvas();
  const root = new GLRootView();
  let dirtyCount = 0;
  root.setOnDirtyListener((): void => {
    dirtyCount++;
  });

  const pane = new GLView();
  root.setContentPane(pane);
  root.onSurfaceCreated(canvas);
  root.onSurfaceChanged(1080, 1920);
  // 消耗初始化产生的脏标志
  ok('initial draw frame', root.onDrawFrame());
  eq('render requested false after clean frame', root.isRenderRequested(), false);

  const dirtyBeforeIdle = dirtyCount;
  const idle = new IdleCounterListener(2);
  root.addOnGLIdleListener(idle);
  ok('addOnGLIdleListener notifies dirty', dirtyCount > dirtyBeforeIdle);
  ok('idle listener marks isRenderRequested=true', root.isRenderRequested());

  // 第 1 帧：listener 返回 true（继续保留）
  ok('frame 1 with idle runs', root.onDrawFrame());
  eq('idle called once', idle.calls, 1);
  ok('still requested while idle active', root.isRenderRequested());

  // 第 2 帧：listener 返回 false（退订）
  ok('frame 2 with idle runs', root.onDrawFrame());
  eq('idle called twice', idle.calls, 2);
  eq('no longer requested once idle drained', root.isRenderRequested(), false);

  // requestRender / requestRenderForced 均通知 dirty
  const beforeReq = dirtyCount;
  root.requestRender();
  ok('requestRender triggers dirty', dirtyCount === beforeReq + 1);
  root.requestRenderForced();
  ok('requestRenderForced triggers dirty', dirtyCount === beforeReq + 2);

  // freeze 期间 requestRender 不唤醒，unfreeze 后立刻唤醒
  root.freeze();
  const duringFreeze = dirtyCount;
  root.requestRender();
  eq('frozen skips dirty notify', dirtyCount, duringFreeze);
  root.unfreeze();
  ok('unfreeze wakes dirty notify', dirtyCount > duringFreeze);

  root.onSurfaceDestroyed();
}

// 2) GLES20Canvas.getLastFrameError() 逐帧错误状态与恢复
{
  const backend = new FaultyBackend();
  GLNative.register(backend);
  const canvas = new GLES20Canvas();
  eq('initial lastFrameError OK', canvas.getLastFrameError(), GLErr.OK);

  backend.nextReplayErr = GLErr.GL_ERROR;
  canvas.beginFrame();
  canvas.clearBuffer();
  canvas.flush();
  eq('replay error recorded in lastFrameError', canvas.getLastFrameError(), GLErr.GL_ERROR);

  backend.nextReplayErr = GLErr.OK;
  backend.nextPresentErr = GLErr.NOT_READY;
  canvas.beginFrame();
  canvas.clearBuffer();
  canvas.flush();
  eq('present error recorded in lastFrameError', canvas.getLastFrameError(), GLErr.NOT_READY);

  backend.nextPresentErr = GLErr.OK;
  canvas.beginFrame();
  canvas.clearBuffer();
  canvas.flush();
  eq('clean frame resets lastFrameError to OK', canvas.getLastFrameError(), GLErr.OK);
}

if (fails.length > 0) {
  console.log(`\n${fails.length} 个断言失败：`);
  for (const f of fails) {
    console.log(`  ✗ ${f}`);
  }
  console.log(`\n通过 ${pass}，失败 ${fails.length}`);
  process.exit(1);
}
console.log(`全部通过：${pass} 个断言`);
