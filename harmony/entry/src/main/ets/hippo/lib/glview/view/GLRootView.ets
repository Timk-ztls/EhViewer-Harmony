/*
 * Copyright (C) 2010 The Android Open Source Project
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

import { hilog } from '@kit.PerformanceAnalysisKit';
import { Matrix } from '../util/Matrix';
import { MotionEvent } from '../util/MotionEvent';
import { MotionEventHelper } from '../util/MotionEventHelper';
import { GLCanvas } from '../glrenderer/GLCanvas';
import { GLView, GLViewMeasureSpec } from './GLView';
import { GLRoot, GLRootOnGLIdleListener } from './GLRoot';
import { CanvasAnimation } from '../anim/CanvasAnimation';
import { AnimationTime } from './AnimationTime';
import { Animation } from '../anim/Animation';
import { OrientationSource } from './OrientationSource';
import { BasicTexture } from '../glrenderer/BasicTexture';
import { UploadedTexture } from '../glrenderer/UploadedTexture';
import { GalleryUtils } from '../util/GalleryUtils';
import { SparseArrayParcelable } from './GLView';

const TAG = 'GLRootView';
const DOMAIN = 0x0000;

/**
 * `com.hippo.lib.glview.view.GLRootView` 的 ArkTS 等价实现。
 *
 * 所有 `GLView` 的根。上游继承 `GLSurfaceView` 并实现 `GLRoot`：
 * 渲染在 GL 线程、事件在主线程，两侧用 `ReentrantLock` 同步。
 *
 * ## 鸿蒙侧的线程模型（与上游不同，登记为平台差异）
 * ArkTS 侧只有 UI 线程一个 VM 上下文；`GLES20Canvas` 的绘制是**录制命令流**，
 * 真正的 GL 调用在 native（`nativeReplay`）里、由 UI 线程同步触发。
 * 因此**没有第二线程**需要用锁保护：
 * - `lockRenderThread()` / `unlockRenderThread()` 保留为空实现（接口兼容），
 *   文件头注明"鸿蒙单线程，无需加锁"；
 * - `mFreeze` 仍然是布尔标志：冻结期间 `onDrawFrame()` 直接返回（上游是
 *   `Condition.awaitUninterruptibly()` 阻塞 GL 线程）。
 *
 * 如果将来把 `nativeReplay` 挪到独立渲染线程，这两个方法必须变成真锁 ——
 * 这是本文件唯一的"行为依赖实现细节"的假设，写在这里防止后人误改。
 *
 * ## 与 `GLSurfaceView` 的对应关系
 * | 上游 | 本实现 |
 * |---|---|
 * | `setRenderer(...)` + `RENDERMODE_WHEN_DIRTY` | `GLRootViewController` 用 `displaySync` 的帧回调驱动 `onDrawFrame()` |
 * | `surfaceCreated/Changed/Destroyed` | native 侧注册 `OH_NativeXComponent` 回调；ArkTS 由 controller 转发尺寸 |
 * | `onDrawFrame(gl)` | `onDrawFrame()`（无 GL 参数，GL 状态在 native） |
 * | `queueEvent(runnable)` | 不需要（单线程） |
 *
 * ## 布局与补偿
 * `layoutContentPane()` 按 `OrientationSource` 的补偿角决定内容宽高是否交换，
 * 并维护 `mCompensationMatrix`（触摸坐标换算用）。这段是横竖屏旋转正确性的关键。
 */
export class GLRootView implements GLRoot {
  private static readonly FLAG_INITIALIZED: number = 1;
  private static readonly FLAG_NEED_LAYOUT: number = 2;

  private static readonly DEBUG_FPS: boolean = false;

  private mFrameCount: number = 0;
  private mFrameCountingStart: number = 0;

  private mCanvas: GLCanvas | null = null;
  private mContentView: GLView | null = null;

  private mOrientationSource: OrientationSource | null = null;
  /** GLCanvas 朝向与框架朝向之差（0/90/180/270）。 */
  private mCompensation: number = 0;
  /** 触摸坐标换算矩阵，与 `mCompensation` 保持同步。 */
  private readonly mCompensationMatrix: Matrix = new Matrix();
  private mDisplayRotation: number = 0;

  private mFlags: number = GLRootView.FLAG_NEED_LAYOUT;
  private mRenderRequested: boolean = false;
  private mRenderForced: boolean = false;

  private readonly mAnimations: CanvasAnimation[] = [];
  private readonly mIdleListeners: GLRootOnGLIdleListener[] = [];

  private mFreeze: boolean = false;
  private mInDownState: boolean = false;
  private mOnDirtyListener: (() => void) | null = null;

  /** 0 表示尚未收到 surface 尺寸。 */
  private mWidth: number = 0;
  private mHeight: number = 0;

  setOnDirtyListener(listener: (() => void) | null): void {
    this.mOnDirtyListener = listener;
  }

  private notifyDirty(): void {
    const listener = this.mOnDirtyListener;
    if (listener !== null) {
      listener();
    }
  }

  // ==========================================================================
  // 生命周期 / surface
  // ==========================================================================

  /**
   * Surface 就绪：创建画布。
   * 上游在 `GLRootRenderer.onSurfaceCreated` 里做（此时 EGL context 已就绪），
   * 鸿蒙侧由 `GLRootViewController` 在 native 回调转发的 `NOT_READY` 消失后调用。
   */
  onSurfaceCreated(canvas: GLCanvas): void {
    GalleryUtils.setRenderThread();
    this.mCanvas = canvas;
    if (this.mWidth > 0 && this.mHeight > 0) {
      canvas.setSize(this.mWidth, this.mHeight);
    }
    BasicTexture.invalidateAllTextures();
    this.mFlags |= GLRootView.FLAG_INITIALIZED;
    this.requestLayoutContentPane();
  }

  /** Surface 尺寸变化（像素）。 */
  onSurfaceChanged(width: number, height: number): void {
    this.mWidth = width;
    this.mHeight = height;
    const canvas = this.mCanvas;
    if (canvas !== null) {
      canvas.setSize(width, height);
    }
    this.requestLayoutContentPane();
  }

  /** Surface 销毁：卸载全部纹理，保留视图树以便重建后重传。 */
  onSurfaceDestroyed(): void {
    GalleryUtils.setRenderThread();
    this.unfreeze();
    BasicTexture.yieldAllTextures();
    this.mCanvas = null;
    GalleryUtils.resetRenderThread();
  }

  getWidth(): number {
    return this.mWidth;
  }

  getHeight(): number {
    return this.mHeight;
  }

  getCanvas(): GLCanvas | null {
    return this.mCanvas;
  }

  // ==========================================================================
  // GLRoot 接口
  // ==========================================================================

  registerLaunchedAnimation(animation: CanvasAnimation): void {
    // 首次渲染通常慢得多，因此在"渲染完成时"再把动画起点对齐到当前帧时间
    this.mAnimations.push(animation);
  }

  addOnGLIdleListener(listener: GLRootOnGLIdleListener): void {
    this.mIdleListeners.push(listener);
    if (!this.mFreeze) {
      this.notifyDirty();
    }
  }

  setContentPane(content: GLView | null): void {
    const old = this.mContentView;
    if (old === content) {
      return;
    }
    if (old !== null) {
      if (this.mInDownState) {
        const now = Animation.uptimeMillis();
        const cancelEvent = MotionEvent.obtainSimple(now, now, MotionEvent.ACTION_CANCEL, 0, 0, 0);
        old.dispatchTouchEvent(cancelEvent);
        cancelEvent.recycle();
        this.mInDownState = false;
      }
      old.detachFromRoot();
      BasicTexture.yieldAllTextures();
    }
    this.mContentView = content;
    if (content !== null) {
      content.attachToRoot(this);
      this.requestLayoutContentPane();
    }
  }

  getContentPane(): GLView | null {
    return this.mContentView;
  }

  requestRenderForced(): void {
    this.mRenderForced = true;
    this.mRenderRequested = true;
    this.notifyDirty();
  }

  requestRender(): void {
    this.mRenderRequested = true;
    if (!this.mFreeze) {
      this.notifyDirty();
    }
  }

  requestLayoutContentPane(): void {
    const content = this.mContentView;
    if (content === null || (this.mFlags & GLRootView.FLAG_NEED_LAYOUT) !== 0) {
      return;
    }
    if ((this.mFlags & GLRootView.FLAG_INITIALIZED) === 0) {
      return;
    }
    this.mFlags |= GLRootView.FLAG_NEED_LAYOUT;
    this.requestRender();
  }

  /** 当前是否需要渲染（controller 的帧回调据此决定画或停）。 */
  isRenderRequested(): boolean {
    return this.mRenderRequested
      || (this.mFlags & GLRootView.FLAG_NEED_LAYOUT) !== 0
      || this.mIdleListeners.length > 0;
  }

  /** 鸿蒙单线程：render 与触摸在同一 VM 上下文，无需加锁（见类注释）。 */
  lockRenderThread(): void {
  }

  unlockRenderThread(): void {
  }

  setOrientationSource(source: OrientationSource | null): void {
    this.mOrientationSource = source;
  }

  getDisplayRotation(): number {
    return this.mDisplayRotation;
  }

  getCompensation(): number {
    return this.mCompensation;
  }

  getCompensationMatrix(): Matrix {
    return this.mCompensationMatrix;
  }

  freeze(): void {
    this.mFreeze = true;
  }

  unfreeze(): void {
    this.mFreeze = false;
    this.requestRender();
  }

  /**
   * Lights-out 模式。上游改 `View.setSystemUiVisibility`；
   * 鸿蒙由宿主页/Ability 调 `window.setWindowLayoutFullScreen` 实现，
   * 本方法只记录意图并请求重绘（见 `ApiHelper.HAS_SET_SYSTEM_UI_VISIBILITY = false`）。
   */
  private mLightsOut: boolean = false;

  setLightsOutMode(enabled: boolean): void {
    if (this.mLightsOut === enabled) {
      return;
    }
    this.mLightsOut = enabled;
    this.requestRender();
  }

  getLightsOutMode(): boolean {
    return this.mLightsOut;
  }

  // ==========================================================================
  // 布局
  // ==========================================================================

  private layoutContentPane(): void {
    this.mFlags &= ~GLRootView.FLAG_NEED_LAYOUT;

    let w = this.mWidth;
    let h = this.mHeight;
    let displayRotation: number;
    let compensation: number;

    const source = this.mOrientationSource;
    if (source !== null) {
      displayRotation = source.getDisplayRotation();
      compensation = source.getCompensation();
    } else {
      displayRotation = 0;
      compensation = 0;
    }

    if (this.mCompensation !== compensation) {
      this.mCompensation = compensation;
      const matrix = this.mCompensationMatrix;
      if (this.mCompensation % 180 !== 0) {
        matrix.setRotate(this.mCompensation, 0, 0);
        // 先把中心移到原点再旋转
        matrix.preTranslate(-w / 2, -h / 2);
        // 旋转后对齐到新原点
        matrix.postTranslate(h / 2, w / 2);
      } else {
        matrix.setRotate(this.mCompensation, w / 2, h / 2);
      }
    }
    this.mDisplayRotation = displayRotation;

    // 补偿角非 180 倍数时，内容的宽高互换
    if (this.mCompensation % 180 !== 0) {
      const tmp = w;
      w = h;
      h = tmp;
    }
    hilog.info(DOMAIN, TAG, 'layout content pane %{public}dx%{public}d (compensation %{public}d)',
      w, h, this.mCompensation);
    const content = this.mContentView;
    if (content !== null && w !== 0 && h !== 0) {
      content.measure(GLRootView.exactly(w), GLRootView.exactly(h));
      content.layout(0, 0, w, h);
    }
  }

  private static exactly(size: number): number {
    return GLViewMeasureSpec.makeMeasureSpec(size, GLViewMeasureSpec.EXACTLY);
  }

  // ==========================================================================
  // 渲染
  // ==========================================================================

  /**
   * 渲染一帧。由 `GLRootViewController` 的帧回调调用（对应上游 `onDrawFrame`）。
   * @return 本帧是否真的画了（false 表示未就绪/冻结，调用方应停止帧循环）
   */
  onDrawFrame(): boolean {
    const canvas = this.mCanvas;
    if (canvas === null || this.mFreeze) {
      return false;
    }

    AnimationTime.update();
    this.outputFps();

    // 回收未绑定的纹理与已删除的缓冲
    canvas.deleteRecycledResources();

    // 重置纹理上传限额（每帧一次，节流窗口）
    UploadedTexture.resetUploadLimit();

    this.mRenderRequested = false;
    this.mRenderForced = false;

    const source = this.mOrientationSource;
    if ((source !== null && this.mDisplayRotation !== source.getDisplayRotation())
      || (this.mFlags & GLRootView.FLAG_NEED_LAYOUT) !== 0) {
      this.layoutContentPane();
    }

    // 开始本帧命令录制（GLCanvas 基类提供空实现，GLES20Canvas 覆写为真实录制）
    canvas.beginFrame();

    canvas.save(GLCanvas.SAVE_FLAG_ALL);
    this.rotateCanvas(-this.mCompensation);
    const content = this.mContentView;
    if (content !== null) {
      content.render(canvas);
    } else {
      // 保证至少画点东西，避免显示垃圾数据
      canvas.clearBuffer();
    }
    canvas.restore();

    // 动画起点对齐到本帧时间
    if (this.mAnimations.length > 0) {
      const now = AnimationTime.get();
      for (let i = 0, n = this.mAnimations.length; i < n; i++) {
        this.mAnimations[i].setStartTime(now);
      }
      this.mAnimations.length = 0;
    }

    // 纹理上传被限流时继续请求下一帧，直到传完
    if (UploadedTexture.uploadLimitReached()) {
      this.requestRender();
    }

    canvas.flush();
    this.runIdleListeners(canvas);
    return true;
  }

  private runIdleListeners(canvas: GLCanvas): void {
    if (this.mIdleListeners.length === 0) {
      return;
    }
    const maxBatch = 16;
    const count = Math.min(this.mIdleListeners.length, maxBatch);
    const batch = this.mIdleListeners.splice(0, count);
    for (let i = 0; i < batch.length; i++) {
      const listener = batch[i];
      let keep = false;
      try {
        keep = listener.onGLIdle(canvas, this.mRenderRequested);
      } catch (e) {
        hilog.error(DOMAIN, TAG, 'idle listener failed: %{public}s',
          e instanceof Error ? e.message : String(e));
        keep = false;
      }
      if (keep) {
        this.mIdleListeners.push(listener);
      }
    }
    if (this.mIdleListeners.length > 0) {
      this.notifyDirty();
    }
  }

  /** 围绕画布中心旋转（补偿角用）。 */
  private rotateCanvas(degrees: number): void {
    const canvas = this.mCanvas;
    if (canvas === null || degrees === 0) {
      return;
    }
    const w = this.mWidth;
    const h = this.mHeight;
    const cx = Math.trunc(w / 2);
    const cy = Math.trunc(h / 2);
    canvas.translate(cx, cy);
    canvas.rotate(degrees, 0, 0, 1);
    if (degrees % 180 !== 0) {
      canvas.translate(-cy, -cx);
    } else {
      canvas.translate(-cx, -cy);
    }
  }

  private outputFps(): void {
    if (!GLRootView.DEBUG_FPS) {
      return;
    }
    const now = Animation.uptimeMillis();
    if (this.mFrameCountingStart === 0) {
      this.mFrameCountingStart = now;
    } else if (now - this.mFrameCountingStart > 1000) {
      hilog.debug(DOMAIN, TAG, 'fps: %{public}f',
        this.mFrameCount * 1000 / (now - this.mFrameCountingStart));
      this.mFrameCountingStart = now;
      this.mFrameCount = 0;
    }
    this.mFrameCount++;
  }

  // ==========================================================================
  // 触摸
  // ==========================================================================

  /**
   * 事件入口（主线程）。
   * 上游逻辑：UP/CANCEL 清 `mInDownState`；非 DOWN 且未处于按下态则直接丢弃
   * （防止"从别的控件滑进来"的事件被误处理）；有补偿角时先变换坐标。
   */
  dispatchTouchEvent(event: MotionEvent): boolean {
    const action = event.getAction();
    if (action === MotionEvent.ACTION_CANCEL || action === MotionEvent.ACTION_UP) {
      this.mInDownState = false;
    } else if (!this.mInDownState && action !== MotionEvent.ACTION_DOWN) {
      return false;
    }

    let e = event;
    if (this.mCompensation !== 0) {
      e = MotionEventHelper.transformEvent(event, this.mCompensationMatrix);
    }

    const content = this.mContentView;
    const handled = content !== null && content.dispatchTouchEvent(e);
    if (action === MotionEvent.ACTION_DOWN && handled) {
      this.mInDownState = true;
    }
    return handled;
  }

  // ==========================================================================
  // 状态持久化
  // ==========================================================================

  dispatchSaveInstanceState(container: SparseArrayParcelable): void {
    const content = this.mContentView;
    if (content !== null) {
      content.saveHierarchyState(container);
    }
  }

  dispatchRestoreInstanceState(container: SparseArrayParcelable): void {
    const content = this.mContentView;
    if (content !== null) {
      content.restoreHierarchyState(container);
    }
  }
}
