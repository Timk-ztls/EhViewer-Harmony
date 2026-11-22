/*
 * Copyright 2024 Hippo Seven
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

import { hilog } from '@kit.PerformanceAnalysisKit';
import { displaySync } from '@kit.ArkGraphics2D';
import { GLView } from './GLView';
import { GLRootView } from './GLRootView';
import { GLES20Canvas } from '../glrenderer/GLES20Canvas';
import { GLNative, GLErr } from '../native/GLNativeBridge';
import { registerGLBackend } from '../../../../native/GLNativeBackendImpl';
import { GLTexImageBridge } from '../native/GLTexImageBridge';

const TAG = 'GLRootViewController';
const DOMAIN = 0x0000;

/**
 * `XComponent` 与 `GLRootView` 之间的薄控制器（**本项目新增，上游无对应物**）。
 *
 * ## 为什么需要它（而不是把 GLRootView 写成 ArkUI 组件）
 * 上游 `GLRootView extends GLSurfaceView`，而 `GLSurfaceView extends SurfaceView extends View`。
 * 鸿蒙的 `@Component struct` **不能被继承**，若把 `GLRootView` 写成 struct，
 * 就保不住 `GLRootView extends GLView`（1367 行的视图树基类）这条继承链。
 * 因此：`GLRootView` 保持普通类，ArkUI 侧只放一个 `XComponent`，
 * 由本控制器把 XComponent 的 surface 生命周期与帧循环桥接到 `GLRootView`。
 *
 * ## 帧循环：为什么用 displaySync 而不是 setInterval
 * 上游 `RENDERMODE_WHEN_DIRTY` 的语义是"**只在有变化时**渲染，由 vsync 对齐上屏"。
 * 两种候选实现：
 * | 方案 | 语义 | 代价 |
 * |---|---|---|
 * | `setInterval(fn, 16)` | 固定间隔轮询，每个间隔都唤醒一次 | 空闲时也唤醒 → 耗电；且与 vsync 不对齐，抖动 |
 * | `displaySync`（本实现） | **vsync 帧回调**，`start()/stop()` 精确控制 | 空闲时 `stop()`，零唤醒 |
 *
 * 因此本实现的做法是：
 * 1. `start()` 时创建 `DisplaySync` 并注册 `on('frame')`
 * 2. 帧回调里检查 `rootView.isRenderRequested()`：
 *    - 有请求 → `onDrawFrame()`；若画完还有请求（如纹理限流、动画未结束）则继续
 *    - 无请求 → `stop()` 关闭帧回调（**这就是 WHEN_DIRTY 的等价点**，不是"每帧空转"）
 * 3. 任何 `requestRender()` 都会让 `GLRootView` 置脏标记；控制器在下次
 *    `ensureRunning()` 时重新 `start()`
 *
 * 需要 `requestRender()` 之后**立即**唤醒帧回调：`GLView.invalidate()` → `GLRoot.requestRender()`，
 * 而 `requestRender` 只是置位。为了让置位后能被及时检测，控制器注册一个轻量的
 * `onDirty` 回调（`GLRootView` 在 `requestRender` 里调用），用于 `ensureRunning()`。
 *
 * ## 与 native 的分工
 * EGL 上下文与 surface 的配对由 **native** 负责（`OH_NativeXComponent_RegisterCallback`
 * 在 `libraryname` 触发的 `Init()` 里注册）。ArkTS 侧只做两件事：
 * 1. 在 `nativeInit()` 返回非 `NOT_READY` 后创建 `GLES20Canvas`（它的构造会触发 `init()`）
 * 2. 通过 `notifySurfaceSize(w, h)` 把像素尺寸告诉 `GLRootView`
 */
export class GLRootViewController {
  private readonly mRootView: GLRootView;
  private mSync: displaySync.DisplaySync | null = null;
  private mRunning: boolean = false;
  private mStarted: boolean = false;
  private mCanvas: GLES20Canvas | null = null;
  private mConsecutiveErrors: number = 0;
  private mPreferredRefreshRateHz: number = 0;
  private mOnRenderErrorListener: ((err: GLErr, consecutiveCount: number) => void) | null = null;

  /** XComponent `onLoad` 传来的 ctx（`XComponentController` 或 surfaceId 容器），仅作锚点。 */
  private readonly mCtx: object | null;

  constructor(ctx: object | null, rootView?: GLRootView) {
    this.mCtx = ctx;
    this.mRootView = rootView === undefined ? new GLRootView() : rootView;
    this.mRootView.setOnDirtyListener((): void => {
      this.ensureRunning();
    });
    // 注册 NAPI 后端（幂等）。不注册的话 GLNative.backend() 永远抛 NOT_READY，
    // 表现是"画布永不创建、首帧黑屏且不崩"——见 GLNativeBackendImpl 类注释。
    registerGLBackend();
  }

  setOnRenderErrorListener(listener: ((err: GLErr, consecutiveCount: number) => void) | null): void {
    this.mOnRenderErrorListener = listener;
  }

  setPreferredRefreshRateHz(hz: number): void {
    this.mPreferredRefreshRateHz = hz;
  }

  probeBackend(): GLErr {
    if (!GLNative.isReady()) {
      return GLErr.NOT_READY;
    }
    return GLNative.backend().init();
  }

  getRootView(): GLRootView {
    return this.mRootView;
  }

  setContentPane(view: GLView | null): void {
    this.mRootView.setContentPane(view);
    this.ensureRunning();
  }

  /**
   * 启动：创建画布 + 打开帧回调。
   *
   * 画布构造会调用 `GLNative.backend().init()`，因此这里必须先探活：
   * `nativeInit()` 未就绪时返回 `NOT_READY`，此时**不创建画布**，
   * 等 `notifySurfaceSize()`（surface 真正就绪后由页面调用）再试 —— 不崩溃、不黑屏占位。
   */
  start(): void {
    if (this.mStarted) {
      return;
    }
    this.mStarted = true;
    hilog.info(DOMAIN, TAG, 'start: ctx=%{public}s', this.mCtx === null ? 'null' : 'present');

    if (!this.ensureCanvas()) {
      hilog.warn(DOMAIN, TAG, 'start: GL backend not ready, defer canvas creation');
      return;
    }
    this.ensureRunning();
  }

  /** 停止：关帧回调、卸载纹理、清理画布与纹理桥（对应上游 onPause + surfaceDestroyed）。 */
  stop(): void {
    this.mStarted = false;
    this.stopSync();
    this.mRootView.onSurfaceDestroyed();
    this.mCanvas = null;
    GLTexImageBridge.getInstance().setCanvas(null);
    hilog.info(DOMAIN, TAG, 'stop');
  }

  /** XComponent Surface 销毁回调：释放 EGL/纹理并允许后续重建。 */
  onSurfaceDestroyed(): void {
    this.mConsecutiveErrors = 0;
    this.stop();
  }

  private mPendingWidth: number = 0;
  private mPendingHeight: number = 0;

  /**
   * 通知 surface 像素尺寸（**必须是 px，不是 vp**；取自
   * `XComponentController.getXComponentSurfaceRect()`）。
   * 同时重试创建画布（`start()` 时后端可能还没就绪）。
   */
  notifySurfaceSize(width: number, height: number): void {
    if (width <= 0 || height <= 0) {
      return;
    }
    this.mPendingWidth = width;
    this.mPendingHeight = height;
    if (!this.ensureCanvas()) {
      hilog.warn(DOMAIN, TAG, 'notifySurfaceSize: backend still not ready (%{public}dx%{public}d)',
        width, height);
      return;
    }
    this.mRootView.onSurfaceChanged(width, height);
    if (this.mStarted) {
      this.ensureRunning();
    }
  }

  /** 触摸事件直接转发给 `GLRootView`（调用方已把 ArkUI `TouchEvent` 换算成 px）。 */
  dispatchTouchEvent(event: import('../util/MotionEvent').MotionEvent): boolean {
    return this.mRootView.dispatchTouchEvent(event);
  }

  /**
   * 强制渲染一帧（调试/首帧用）。
   *
   * 与同文件 `start()` / `init()` 的形态保持一致：**检查 `ensureCanvas()` 的返回值**。
   * 忽略返回值时，若 GL backend 尚未就绪（`GLNative.isReady() === false`），
   * `requestRenderForced()` 仍会跑，随后在无画布的情况下渲染 → 表现为「首帧黑屏且无日志」。
   */
  renderNow(): void {
    if (!this.ensureCanvas()) {
      hilog.warn(DOMAIN, TAG, 'renderNow: GL backend not ready, skip forced frame');
      return;
    }
    this.mRootView.requestRenderForced();
    this.ensureRunning();
  }

  private ensureCanvas(): boolean {
    if (this.mCanvas !== null) {
      return true;
    }
    if (!GLNative.isReady()) {
      return false;
    }
    try {
      const canvas = new GLES20Canvas();
      this.mCanvas = canvas;
      // 注入 Image 的纹理上传桥（`Image.texImage` 的唯一出口；不注入则 ImageTexture 不出像素）
      const texBridge = GLTexImageBridge.install();
      texBridge.setCanvas(canvas);
      this.mRootView.onSurfaceCreated(canvas);
      if (this.mPendingWidth > 0 && this.mPendingHeight > 0) {
        this.mRootView.onSurfaceChanged(this.mPendingWidth, this.mPendingHeight);
      }
      return true;
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'create GLES20Canvas failed: %{public}s', JSON.stringify(err));
      const errListener = this.mOnRenderErrorListener;
      if (errListener !== null) {
        errListener(GLErr.NOT_READY, 1);
      }
      return false;
    }
  }

  // ==========================================================================
  // 帧循环
  // ==========================================================================

  /** 若未在跑则启动 vsync 帧回调（幂等）。 */
  private ensureRunning(): void {
    if (this.mRunning || !this.mStarted || this.mCanvas === null) {
      return;
    }
    if (this.mSync === null) {
      this.mSync = displaySync.create();
      this.mSync.on('frame', (_info: displaySync.IntervalInfo) => {
        this.onFrame();
      });
      const expectedHz: number = this.mPreferredRefreshRateHz >= 30
        ? Math.min(120, Math.trunc(this.mPreferredRefreshRateHz))
        : 120;
      const minHz: number = Math.min(30, expectedHz);
      this.mSync.setExpectedFrameRateRange({ expected: expectedHz, min: minHz, max: expectedHz });
    }
    const sync = this.mSync;
    if (sync !== null) {
      sync.start();
      this.mRunning = true;
    }
  }

  /** 停止帧回调（空闲时零唤醒）。 */
  private stopSync(): void {
    const sync = this.mSync;
    if (sync !== null && this.mRunning) {
      sync.stop();
    }
    this.mRunning = false;
  }

  /**
   * 一帧：有请求才画；画完仍无请求就停掉帧回调（`RENDERMODE_WHEN_DIRTY` 的等价点）。
   */
  private onFrame(): void {
    if (!this.mRootView.isRenderRequested()) {
      this.stopSync();
      return;
    }
    const drawn = this.mRootView.onDrawFrame();
    if (!drawn) {
      // 冻结或画布丢失：停掉，等下一次 requestRender 唤醒
      this.stopSync();
      return;
    }
    const canvas = this.mCanvas;
    const frameErr: GLErr = canvas !== null ? canvas.getLastFrameError() : GLErr.OK;
    if (frameErr !== GLErr.OK) {
      this.mConsecutiveErrors++;
      const errListener = this.mOnRenderErrorListener;
      if (errListener !== null) {
        errListener(frameErr, this.mConsecutiveErrors);
      }
    } else {
      this.mConsecutiveErrors = 0;
    }
    if (!this.mRootView.isRenderRequested()) {
      this.stopSync();
    }
  }

  /** 供宿主页在 `aboutToDisappear` 调用：释放 DisplaySync。 */
  release(): void {
    this.mRootView.setOnDirtyListener(null);
    this.mOnRenderErrorListener = null;
    this.stop();
    const sync = this.mSync;
    if (sync !== null) {
      sync.off('frame');
      this.mSync = null;
    }
  }

  /** 诊断：当前是否在跑帧回调（联调时确认 WHEN_DIRTY 是否真的停下来了）。 */
  isRunning(): boolean {
    return this.mRunning;
  }

  /** 诊断：画布是否已创建（false = native 后端未就绪）。 */
  hasCanvas(): boolean {
    return this.mCanvas !== null;
  }
}
