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
import { Color } from '../util/Color';
import { Rect } from '../util/Rect';
import { MotionEvent } from '../util/MotionEvent';
import { GLPaint } from '../glrenderer/GLPaint';
import { GLCanvas } from '../glrenderer/GLCanvas';
import { GLRoot } from './GLRoot';
import { CanvasAnimation } from '../anim/CanvasAnimation';
import { AnimationTime } from './AnimationTime';
import { Animation } from '../anim/Animation';
import { TouchHelper } from './TouchHelper';
import { TouchOwner } from './TouchOwner';
import { Gravity } from './Gravity';

const TAG = 'GLView';
const DOMAIN = 0x0000;

/** 视图状态持久化的载荷基类（等价 `android.os.Parcelable`，`GLView` 只当不透明句柄用）。 */
export interface Parcelable {
}

/**
 * 等价 `android.util.SparseArray<T>` 的最小接口（`GLView` 只用到 put/get）。
 * 用 `Map<number, T>` 实现：鸿蒙无 SparseArray，而 key 全是 int id，`Map` 语义一致。
 */
export type SparseArrayParcelable = Map<number, Parcelable>;

/**
 * `com.hippo.lib.glview.view.GLView` 的 ArkTS 等价实现。
 *
 * GLView 是一个 UI 组件：能渲染到 GLCanvas、能接收触摸事件。可以有 0..N 个 GLView 子节点，
 * 构成树；渲染与事件分发都走这棵树。
 *
 * 生命周期：GLView 树必须先 attach 到 `GLRoot`（`attachToRoot`）才会分发事件与渲染；
 * GLView 通过 `requestRender()` / `requestLayoutContentPane()` 请求重绘/重排。
 *
 * 线程：`render()` 在渲染线程调用；`dispatchTouchEvent()` 与 `layout()` 之前 `GLRoot`
 * 会加锁避免渲染线程并发运行。若子类还有其他主线程入口（如 Handler），需要自行
 * `lockRendering()`。
 *
 * ## ArkTS 适配（逐条，均不改变行为）
 * 1. `@IntDef` 注解 → 注释 + 常量类（`VISIBLE/INVISIBLE/GONE`）
 * 2. 方法重载（`addComponent` ×4、`getX` 等）→ 可选参数 + 联合类型，在方法内分派
 *    （DEVIATIONS §5 第 7 条：ArkTS 无重载解析）
 * 3. `SparseArray<Parcelable>` → `Map<number, Parcelable>`（见 `SparseArrayParcelable`）
 * 4. `SystemClock.uptimeMillis()` → `Animation.uptimeMillis()`（单调时钟，不用墙钟）
 * 5. `MotionEvent.obtain(event)` → `MotionEvent.obtainCopy(event)`
 * 6. `IllegalStateException` / `IllegalArgumentException` / `ArrayIndexOutOfBoundsException`
 *    → `Error`（DEVIATIONS §5 第 8 条），消息文本保留
 * 7. `getClass().getSimpleName()` → 固定名 `'GLView'`（ArkTS 无运行时类名反射）
 * 8. `DEBUG_DRAW_BOUNDS` 保留为常量 `false`；打开后每个视图画红框（上游同语义）
 */
export class GLView implements TouchOwner {
  private static readonly DEBUG_DRAW_BOUNDS: boolean = false;

  // ---- 可见性 ----
  static readonly VISIBLE: number = 0b00000000;
  static readonly INVISIBLE: number = 0b00000001;
  static readonly GONE: number = 0b00000010;
  static readonly VISIBILITY_INVALID: number = 0b00000011;

  private static readonly FLAG_INVISIBLE: number = 0b00000011;
  private static readonly FLAG_SET_MEASURED_SIZE: number = 0b00000100;
  private static readonly FLAG_LAYOUT_REQUESTED: number = 0b00001000;

  /** 无 id。 */
  static readonly NO_ID: number = -1;

  /** 调试用：画视图边界。 */
  protected static readonly mDrawBoundsPaint: GLPaint = GLView.createBoundsPaint();

  private static createBoundsPaint(): GLPaint {
    const paint = new GLPaint();
    paint.setColor(Color.RED);
    paint.setLineWidth(2);
    return paint;
  }

  /** 相对父容器的位置（对应 `android.view.View` 的 left/top/right/bottom）。 */
  protected readonly mBounds: Rect = new Rect();
  /** 相对根容器的位置。 */
  private readonly mPositionInRoot: number[] = new Array<number>(2).fill(0);
  protected readonly mPaddings: Rect = new Rect();
  private readonly mTempRect: Rect = new Rect();

  private mRoot: GLRoot | null = null;
  protected mParent: GLView | null = null;
  private mComponents: GLView[] | null = null;
  private mMotionTarget: GLView | null = null;

  private mAnimation: CanvasAnimation | null = null;

  private mViewFlags: number = 0;

  protected mMeasuredWidth: number = 0;
  protected mMeasuredHeight: number = 0;

  private mLastWidthSpec: number = -1;
  private mLastHeightSpec: number = -1;

  protected mScrollY: number = 0;
  protected mScrollX: number = 0;
  protected mScrollWidth: number = 0;
  protected mScrollHeight: number = 0;

  private mID: number = GLView.NO_ID;
  private mMinHeight: number = 0;
  private mMinWidth: number = 0;

  private mLayoutParams: GLViewLayoutParams | null = null;

  private mBackgroundColor: number = Color.TRANSPARENT;

  private mTouchHelper: TouchHelper | null = null;

  private mHotspotX: number = 0;
  private mHotspotY: number = 0;

  private mPressed: boolean = false;

  private mOnClickListener: GLViewOnClickListener | null = null;
  private mOnLongClickListener: GLViewOnLongClickListener | null = null;

  // ==========================================================================
  // 动画
  // ==========================================================================

  /**
   * 启动一个画布动画。
   * @param atOnce true 表示立即从当前帧开始（不登记到 GLRoot），否则登记后由每帧推进
   */
  startAnimation(animation: CanvasAnimation | null, atOnce: boolean): void {
    const root = this.getGLRoot();
    if (root === null) {
      throw new Error('GLView is not attached to GLRoot');
    }
    this.mAnimation = animation;
    const anim = this.mAnimation;
    if (anim !== null) {
      anim.start();
      if (atOnce) {
        anim.setStartTime(AnimationTime.get());
      } else {
        root.registerLaunchedAnimation(anim);
      }
    }
    this.invalidate();
  }

  // ==========================================================================
  // 可见性
  // ==========================================================================

  setVisibility(visibility: number): void {
    const oldVisibility = this.getVisibility();
    if (visibility === oldVisibility) {
      return;
    }

    this.mViewFlags &= ~GLView.FLAG_INVISIBLE;
    this.mViewFlags |= visibility;

    this.onVisibilityChanged(this, visibility);

    if (oldVisibility === GLView.GONE || visibility === GLView.GONE) {
      this.requestLayout();
    } else {
      this.invalidate();
    }
  }

  getVisibility(): number {
    let visibility = this.mViewFlags & GLView.FLAG_INVISIBLE;

    if (visibility === GLView.VISIBILITY_INVALID) {
      visibility = GLView.VISIBLE;
      this.mViewFlags &= ~GLView.FLAG_INVISIBLE;
      this.mViewFlags |= visibility;
    }

    return visibility;
  }

  // ==========================================================================
  // 挂载到根
  // ==========================================================================

  /** 只应对内容面板（最顶层 GLView）调用。 */
  attachToRoot(root: GLRoot): void {
    if (!(this.mParent === null && this.mRoot === null)) {
      throw new Error('attachToRoot: view already has parent or root');
    }
    this.onAttachToRoot(root);
  }

  /** 只应对内容面板调用。 */
  detachFromRoot(): void {
    if (!(this.mParent === null && this.mRoot !== null)) {
      throw new Error('detachFromRoot: view is not attached');
    }
    this.onDetachFromRoot();
  }

  /** 只应对内容面板调用。 */
  pause(): void {
    this.onPause();
  }

  /** 只应对内容面板调用。 */
  resume(): void {
    this.onResume();
  }

  isAttachedToRoot(): boolean {
    return this.mRoot !== null;
  }

  // ==========================================================================
  // 子视图管理
  // ==========================================================================

  getComponentCount(): number {
    return this.mComponents === null ? 0 : this.mComponents.length;
  }

  getComponent(index: number): GLView {
    const components = this.mComponents;
    if (components === null || index < 0 || index >= components.length) {
      throw new Error(`Index: ${index}, Size: ${components === null ? 0 : components.length}`);
    }
    return components[index];
  }

  /**
   * 添加子视图。四种上游重载合一：
   * `addComponent(c)` / `(c, index)` / `(c, params)` / `(c, index, params)`。
   */
  addComponent(component: GLView, indexOrParams?: number | GLViewLayoutParams,
    params?: GLViewLayoutParams): void {
    if (component === null || component === undefined) {
      throw new Error('Cannot add a null child view to a ViewGroup');
    }
    if (component.mParent !== null) {
      throw new Error('Component being added, but it already has a parent');
    }

    let index = -1;
    let layoutParams: GLViewLayoutParams | null = null;
    if (indexOrParams !== undefined) {
      if (typeof indexOrParams === 'number') {
        index = indexOrParams;
        layoutParams = params === undefined ? null : params;
      } else {
        layoutParams = indexOrParams;
      }
    }

    if (index < 0) {
      index = this.getComponentCount();
    }

    if (layoutParams === null) {
      layoutParams = this.generateDefaultLayoutParams();
    } else if (!this.checkLayoutParams(layoutParams)) {
      layoutParams = this.generateLayoutParams(layoutParams);
    }

    if (this.mComponents === null) {
      this.mComponents = [];
    }
    this.mComponents.splice(index, 0, component);
    component.mParent = this;
    component.setLayoutParams(layoutParams);

    if (this.mRoot !== null) {
      component.onAttachToRoot(this.mRoot);
    }
  }

  removeComponent(component: GLView): boolean {
    const components = this.mComponents;
    if (components === null) {
      return false;
    }
    const index = components.indexOf(component);
    if (index >= 0) {
      components.splice(index, 1);
      this.removeOneComponent(component);
      return true;
    }
    return false;
  }

  removeComponentAt(index: number): boolean {
    const components = this.mComponents;
    if (components === null) {
      return false;
    }
    if (index >= 0 && index < components.length) {
      const component = components[index];
      components.splice(index, 1);
      this.removeOneComponent(component);
      return true;
    }
    return false;
  }

  removeAllComponents(): void {
    const components = this.mComponents;
    if (components === null) {
      return;
    }
    for (let i = 0, n = components.length; i < n; ++i) {
      this.removeOneComponent(components[i]);
    }
    this.mComponents = [];
  }

  /**
   * 摘除一个子视图；若它正是当前触摸目标，先给它合成 `ACTION_CANCEL`
   * （否则子视图会一直以为自己还在被按着，长按/拖动状态残留）。
   */
  private removeOneComponent(component: GLView): void {
    if (this.mMotionTarget === component) {
      const now = Animation.uptimeMillis();
      const cancelEvent = MotionEvent.obtainSimple(now, now, MotionEvent.ACTION_CANCEL, 0, 0, 0);
      this.dispatchTouchEvent(cancelEvent);
      cancelEvent.recycle();
    }
    component.onDetachFromRoot();
    component.mParent = null;
  }

  // ==========================================================================
  // id / bounds / hotspot / 点击态
  // ==========================================================================

  setId(id: number): void {
    this.mID = id;
  }

  getId(): number {
    return this.mID;
  }

  bounds(): Rect {
    return this.mBounds;
  }

  setHotspot(x: number, y: number): void {
    this.mHotspotX = x;
    this.mHotspotY = y;
  }

  getHotspotX(): number {
    return this.mHotspotX;
  }

  getHotspotY(): number {
    return this.mHotspotY;
  }

  /** 上游恒返回 true（源码 `return true; // TODO`），保持一致。 */
  isEnabled(): boolean {
    return true;
  }

  isPressed(): boolean {
    return this.mPressed;
  }

  setPressed(pressed: boolean): void {
    this.mPressed = pressed;
  }

  isClickable(): boolean {
    return this.mOnClickListener !== null;
  }

  isLongClickable(): boolean {
    return this.mOnLongClickListener !== null;
  }

  performClick(): boolean {
    const listener = this.mOnClickListener;
    if (listener !== null) {
      return listener.onClick(this);
    }
    return false;
  }

  performLongClick(): boolean {
    const listener = this.mOnLongClickListener;
    if (listener !== null) {
      return listener.onLongClick(this);
    }
    return false;
  }

  setOnClickListener(listener: GLViewOnClickListener | null): void {
    this.mOnClickListener = listener;
  }

  setOnLongClickListener(listener: GLViewOnLongClickListener | null): void {
    this.mOnLongClickListener = listener;
  }

  getWidth(): number {
    return this.mBounds.right - this.mBounds.left;
  }

  getHeight(): number {
    return this.mBounds.bottom - this.mBounds.top;
  }

  offsetTopAndBottom(offset: number): void {
    if (offset !== 0) {
      this.mBounds.offset(0, offset);
      this.dispatchNotifyPositionInRoot();
      this.invalidate();
    }
  }

  offsetLeftAndRight(offset: number): void {
    if (offset !== 0) {
      this.mBounds.offset(offset, 0);
      this.dispatchNotifyPositionInRoot();
      this.invalidate();
    }
  }

  // ==========================================================================
  // 渲染请求
  // ==========================================================================

  getGLRoot(): GLRoot | null {
    return this.mRoot;
  }

  /** 请求重绘（动画/内容变化时）。 */
  invalidate(): void {
    const root = this.getGLRoot();
    if (root !== null) {
      root.requestRender();
    }
  }

  /** 请求重新布局。 */
  requestLayout(): void {
    this.mViewFlags |= GLView.FLAG_LAYOUT_REQUESTED;
    this.mLastWidthSpec = -1;
    this.mLastHeightSpec = -1;
    const parent = this.mParent;
    if (parent !== null) {
      parent.requestLayout();
    } else {
      // 自己就是内容面板
      const root = this.getGLRoot();
      if (root !== null) {
        root.requestLayoutContentPane();
      }
    }
  }

  // ==========================================================================
  // 渲染
  // ==========================================================================

  render(canvas: GLCanvas): void {
    // 背景
    if (Color.alpha(this.mBackgroundColor) !== 0) {
      canvas.fillRect(0, 0, this.getWidth(), this.getHeight(), this.mBackgroundColor);
    }

    // 自身内容
    this.onRender(canvas);

    // 子视图
    canvas.save();
    for (let i = 0, n = this.getComponentCount(); i < n; ++i) {
      this.renderChild(canvas, this.getComponent(i));
    }
    canvas.restore();

    // 调试边界
    if (GLView.DEBUG_DRAW_BOUNDS) {
      canvas.drawRect(0, 0, this.getWidth(), this.getHeight(), GLView.mDrawBoundsPaint);
    }
  }

  /** 子类覆写绘制自身内容。 */
  onRender(canvas: GLCanvas): void {
  }

  setBackgroundColor(color: number): void {
    this.mBackgroundColor = color;
  }

  /**
   * 绘制子视图：不可见或裁剪后为空则跳过；按子视图 bounds 平移画布，
   * 若子视图有动画则先 save(动画声明的标志位) → 推进动画 → apply → 渲染 → restore。
   */
  protected renderChild(canvas: GLCanvas, component: GLView): void {
    if (component.getVisibility() !== GLView.VISIBLE) {
      return;
    }

    this.getValidRect(this.mTempRect);
    if (this.mTempRect.isEmpty()) {
      return;
    }

    const xOffset = component.mBounds.left - this.mScrollX;
    const yOffset = component.mBounds.top - this.mScrollY;

    canvas.translate(xOffset, yOffset);

    const anim = component.mAnimation;
    if (anim !== null) {
      canvas.save(anim.getCanvasSaveFlags());
      if (anim.calculate(AnimationTime.get())) {
        this.invalidate();
      } else {
        component.mAnimation = null;
      }
      anim.apply(canvas);
    }
    component.render(canvas);
    if (anim !== null) {
      canvas.restore();
    }
    canvas.translate(-xOffset, -yOffset);
  }

  // ==========================================================================
  // 触摸
  // ==========================================================================

  protected onTouch(event: MotionEvent): boolean {
    if (this.mTouchHelper === null) {
      this.mTouchHelper = new TouchHelper(this);
    }
    return this.mTouchHelper.onTouch(event);
  }

  /** 把事件坐标平移到子视图局部坐标系后交给它；返回是否被消费。 */
  protected dispatchTouchEventTo(event: MotionEvent, x: number, y: number, component: GLView,
    checkBounds: boolean): boolean {
    const rect = component.mBounds;
    const left = rect.left;
    const top = rect.top;
    if (!checkBounds || rect.contains(x, y)) {
      event.offsetLocation(-left, -top);
      if (component.dispatchTouchEvent(event)) {
        event.offsetLocation(left, top);
        return true;
      }
      event.offsetLocation(left, top);
    }
    return false;
  }

  /**
   * 事件分发：已有触摸目标时独占（含 ACTION_UP/CANCEL 后释放）；
   * 否则在 ACTION_DOWN 时按**渲染逆序**找命中子视图，最后兜底给自己。
   */
  dispatchTouchEvent(event: MotionEvent): boolean {
    const x = Math.trunc(event.getX());
    const y = Math.trunc(event.getY());
    const action = event.getAction();
    const target = this.mMotionTarget;
    if (target !== null) {
      if (action === MotionEvent.ACTION_DOWN) {
        const cancel = MotionEvent.obtainCopy(event);
        cancel.setAction(MotionEvent.ACTION_CANCEL);
        this.dispatchTouchEventTo(cancel, x, y, target, false);
        this.mMotionTarget = null;
      } else {
        this.dispatchTouchEventTo(event, x, y, target, false);
        if (action === MotionEvent.ACTION_CANCEL || action === MotionEvent.ACTION_UP) {
          this.mMotionTarget = null;
        }
        return true;
      }
    }
    if (action === MotionEvent.ACTION_DOWN) {
      // 逆渲染顺序：后画的在上层，先命中
      for (let i = this.getComponentCount() - 1; i >= 0; --i) {
        const component = this.getComponent(i);
        if (component.getVisibility() !== GLView.VISIBLE) {
          continue;
        }
        if (this.dispatchTouchEventTo(event, x, y, component, true)) {
          this.mMotionTarget = component;
          return true;
        }
      }
    }
    return this.onTouch(event);
  }

  // ==========================================================================
  // 状态持久化
  // ==========================================================================

  saveHierarchyState(container: SparseArrayParcelable): void {
    this.dispatchSaveInstanceState(container);
  }

  protected dispatchSaveInstanceState(container: SparseArrayParcelable): void {
    if (this.mID !== GLView.NO_ID) {
      const state = this.onSaveInstanceState();
      if (state !== null) {
        container.set(this.mID, state);
      }
    }
    for (let i = 0, n = this.getComponentCount(); i < n; ++i) {
      this.getComponent(i).dispatchSaveInstanceState(container);
    }
  }

  protected onSaveInstanceState(): Parcelable | null {
    return null;
  }

  restoreHierarchyState(container: SparseArrayParcelable): void {
    this.dispatchRestoreInstanceState(container);
  }

  protected dispatchRestoreInstanceState(container: SparseArrayParcelable): void {
    if (this.mID !== GLView.NO_ID) {
      const state = container.get(this.mID);
      if (state !== undefined && state !== null) {
        this.onRestoreInstanceState(state);
      }
    }
    for (let i = 0, n = this.getComponentCount(); i < n; ++i) {
      this.getComponent(i).dispatchRestoreInstanceState(container);
    }
  }

  protected onRestoreInstanceState(state: Parcelable | null): void {
    if (state !== null) {
      throw new Error('Please override onRestoreInstanceState');
    }
  }

  // ==========================================================================
  // padding
  // ==========================================================================

  setPaddings(paddingLeft: number, paddingTop: number, paddingRight: number,
    paddingBottom: number): void {
    this.mPaddings.set(paddingLeft, paddingTop, paddingRight, paddingBottom);
  }

  setPaddingLeft(paddingLeft: number): void {
    this.mPaddings.left = paddingLeft;
  }

  setPaddingTop(paddingTop: number): void {
    this.mPaddings.top = paddingTop;
  }

  setPaddingRight(paddingRight: number): void {
    this.mPaddings.right = paddingRight;
  }

  setPaddingBottom(paddingBottom: number): void {
    this.mPaddings.bottom = paddingBottom;
  }

  getPaddings(): Rect {
    return this.mPaddings;
  }

  // ==========================================================================
  // 布局
  // ==========================================================================

  /**
   * 与 `android.view.View.layout()` 略有不同：**不**在这里调 `onMeasure()`。
   * 内容面板由 `GLRootView` 先 measure 再 layout；子视图在父视图的 `onMeasure` 里 measure。
   */
  layout(left: number, top: number, right: number, bottom: number): void {
    const sizeChanged = this.setBounds(left, top, right, bottom);
    const forceLayout = (this.mViewFlags & GLView.FLAG_LAYOUT_REQUESTED)
      === GLView.FLAG_LAYOUT_REQUESTED;
    if (sizeChanged || forceLayout) {
      this.notifyPositionInRoot();
      this.onLayout(sizeChanged, left, top, right, bottom);
    } else {
      this.dispatchNotifyPositionInRoot();
    }
    this.mViewFlags &= ~GLView.FLAG_LAYOUT_REQUESTED;
  }

  /** 递归通知"相对根位置"变化（只有自身位置变了才继续往下传）。 */
  dispatchNotifyPositionInRoot(): void {
    if (this.notifyPositionInRoot()) {
      for (let i = 0, size = this.getComponentCount(); i < size; i++) {
        this.getComponent(i).dispatchNotifyPositionInRoot();
      }
    }
  }

  /**
   * 重算相对根位置；变了返回 true。
   * 有父视图时先向父要父的位置，再叠加自己的 bounds 偏移。
   */
  notifyPositionInRoot(): boolean {
    const position = this.mPositionInRoot;
    const oldX = position[0];
    const oldY = position[1];
    const parent = this.mParent;
    if (parent === null) {
      position[0] = 0;
      position[1] = 0;
    } else {
      parent.getPositionInRoot(position);
      position[0] += this.mBounds.left;
      position[1] += this.mBounds.top;
    }
    const x = position[0];
    const y = position[1];
    if (x !== oldX || y !== oldY) {
      this.onPositionInRootChanged(x, y, oldX, oldY);
      return true;
    }
    return false;
  }

  /** 设置边界；尺寸变化时触发 `onSizeChanged`。 */
  private setBounds(left: number, top: number, right: number, bottom: number): boolean {
    const bounds = this.mBounds;
    const oldW = bounds.right - bounds.left;
    const oldH = bounds.bottom - bounds.top;
    const newW = right - left;
    const newH = bottom - top;

    const sizeChanged = oldW !== newW || oldH !== newH;
    bounds.set(left, top, right, bottom);

    if (sizeChanged) {
      this.onSizeChanged(newW, newH, oldW, oldH);
    }

    return sizeChanged;
  }

  protected onSizeChanged(newW: number, newH: number, oldW: number, oldH: number): void {
  }

  protected onPositionInRootChanged(x: number, y: number, oldX: number, oldY: number): void {
  }

  getPositionInRoot(position: number[]): void {
    if (position.length !== 2) {
      throw new Error('position should be 2 length int array');
    }
    position[0] = this.mPositionInRoot[0];
    position[1] = this.mPositionInRoot[1];
  }

  /**
   * 取"被根容器裁剪后"的可见区域。
   * 注意返回的是**相对本视图**的坐标（最后一步 `offset(-x,-y)`），
   * 上游 `renderChild` 用它判断是否还需要画子视图。
   */
  getValidRect(rect: Rect): void {
    const root = this.mRoot;
    if (root === null) {
      rect.setEmpty();
      return;
    }

    const x = this.mPositionInRoot[0];
    const y = this.mPositionInRoot[1];
    rect.set(x, y, x + this.getWidth(), y + this.getHeight());
    if (!rect.intersectRect(0, 0, root.getWidth(), root.getHeight())) {
      rect.setEmpty();
      return;
    }

    rect.offset(-x, -y);
  }

  // ==========================================================================
  // 测量
  // ==========================================================================

  measure(widthSpec: number, heightSpec: number): void {
    const forceLayout = (this.mViewFlags & GLView.FLAG_LAYOUT_REQUESTED)
      === GLView.FLAG_LAYOUT_REQUESTED;
    const isExactly = GLViewMeasureSpec.getMode(widthSpec) === GLViewMeasureSpec.EXACTLY
      && GLViewMeasureSpec.getMode(heightSpec) === GLViewMeasureSpec.EXACTLY;
    const matchingSize = isExactly
      && this.getMeasuredWidth() === GLViewMeasureSpec.getSize(widthSpec)
      && this.getMeasuredHeight() === GLViewMeasureSpec.getSize(heightSpec);
    if (forceLayout || (!matchingSize
      && (widthSpec !== this.mLastWidthSpec || heightSpec !== this.mLastHeightSpec))) {
      this.mLastWidthSpec = widthSpec;
      this.mLastHeightSpec = heightSpec;

      this.mViewFlags &= ~GLView.FLAG_SET_MEASURED_SIZE;
      this.onMeasure(widthSpec, heightSpec);
      if ((this.mViewFlags & GLView.FLAG_SET_MEASURED_SIZE) === 0) {
        throw new Error('GLView should call setMeasuredSize() in onMeasure()');
      }
    }
  }

  protected onMeasure(widthSpec: number, heightSpec: number): void {
    this.setMeasuredSize(
      GLView.getDefaultSize(this.getSuggestedMinimumWidth(), widthSpec),
      GLView.getDefaultSize(this.getSuggestedMinimumHeight(), heightSpec));
  }

  protected getSuggestedMinimumHeight(): number {
    return this.getMinimumHeight() + this.mPaddings.top + this.mPaddings.bottom;
  }

  protected getSuggestedMinimumWidth(): number {
    return this.getMinimumWidth() + this.mPaddings.left + this.mPaddings.right;
  }

  getMinimumHeight(): number {
    return this.mMinHeight;
  }

  setMinimumHeight(minHeight: number): void {
    this.mMinHeight = minHeight;
    this.requestLayout();
  }

  getMinimumWidth(): number {
    return this.mMinWidth;
  }

  setMinimumWidth(minWidth: number): void {
    this.mMinWidth = minWidth;
    this.requestLayout();
  }

  protected setMeasuredSize(width: number, height: number): void {
    this.mViewFlags |= GLView.FLAG_SET_MEASURED_SIZE;
    this.mMeasuredWidth = width;
    this.mMeasuredHeight = height;
  }

  getMeasuredWidth(): number {
    return this.mMeasuredWidth;
  }

  getMeasuredHeight(): number {
    return this.mMeasuredHeight;
  }

  protected onLayout(changeSize: boolean, left: number, top: number, right: number,
    bottom: number): void {
  }

  /** 按 BEGIN/CENTER/FINISH 计算子视图在一个方向上的起点。 */
  static getDefaultBegin(size: number, specSize: number, paddingBegin: number,
    paddingFinish: number, position: number): number {
    if (position === Gravity.POSITION_FINISH) {
      return size - paddingFinish - specSize;
    } else if (position === Gravity.POSITION_CENTER) {
      return ((size - paddingBegin - paddingFinish) / 2) - (specSize / 2) + paddingBegin;
    } else {
      return paddingBegin;
    }
  }

  /**
   * 默认尺寸。与 `android.view.View.getDefaultSize()` **不同**（上游注释明确说明）：
   * AT_MOST 模式下，若建议尺寸非 0 则取 `min(size, specSize)`，否则取 specSize。
   */
  static getDefaultSize(size: number, measureSpec: number): number {
    const specMode = GLViewMeasureSpec.getMode(measureSpec);
    const specSize = GLViewMeasureSpec.getSize(measureSpec);

    switch (specMode) {
      case GLViewMeasureSpec.UNSPECIFIED:
        return size;
      case GLViewMeasureSpec.EXACTLY:
        return specSize;
      case GLViewMeasureSpec.AT_MOST:
        return size === 0 ? specSize : Math.min(size, specSize);
      default:
        return size;
    }
  }

  /** 最大尺寸（同 `android.view.View.getDefaultSize()` 语义）。 */
  static getMaxSize(size: number, measureSpec: number): number {
    const specMode = GLViewMeasureSpec.getMode(measureSpec);
    const specSize = GLViewMeasureSpec.getSize(measureSpec);

    switch (specMode) {
      case GLViewMeasureSpec.UNSPECIFIED:
        return size;
      case GLViewMeasureSpec.EXACTLY:
      case GLViewMeasureSpec.AT_MOST:
        return specSize;
      default:
        return size;
    }
  }

  /** 由父的 spec 与子视图声明的 width/height 推出子视图的 spec。 */
  static getComponentSpec(spec: number, childSize: number): number {
    const specMode = GLViewMeasureSpec.getMode(spec);
    const specSize = GLViewMeasureSpec.getSize(spec);
    const size = Math.max(0, specSize);

    let resultSize = 0;
    let resultMode = 0;

    switch (specMode) {
      case GLViewMeasureSpec.EXACTLY:
        if (childSize >= 0) {
          resultSize = childSize;
          resultMode = GLViewMeasureSpec.EXACTLY;
        } else if (childSize === GLViewLayoutParams.MATCH_PARENT) {
          resultSize = size;
          resultMode = GLViewMeasureSpec.EXACTLY;
        } else if (childSize === GLViewLayoutParams.WRAP_CONTENT) {
          resultSize = size;
          resultMode = GLViewMeasureSpec.AT_MOST;
        }
        break;

      case GLViewMeasureSpec.AT_MOST:
        if (childSize >= 0) {
          resultSize = childSize;
          resultMode = GLViewMeasureSpec.EXACTLY;
        } else if (childSize === GLViewLayoutParams.MATCH_PARENT) {
          resultSize = size;
          resultMode = GLViewMeasureSpec.AT_MOST;
        } else if (childSize === GLViewLayoutParams.WRAP_CONTENT) {
          resultSize = size;
          resultMode = GLViewMeasureSpec.AT_MOST;
        }
        break;

      case GLViewMeasureSpec.UNSPECIFIED:
        if (childSize >= 0) {
          resultSize = childSize;
          resultMode = GLViewMeasureSpec.EXACTLY;
        } else if (childSize === GLViewLayoutParams.MATCH_PARENT) {
          resultSize = 0;
          resultMode = GLViewMeasureSpec.UNSPECIFIED;
        } else if (childSize === GLViewLayoutParams.WRAP_CONTENT) {
          resultSize = 0;
          resultMode = GLViewMeasureSpec.UNSPECIFIED;
        }
        break;

      default:
        break;
    }
    return GLViewMeasureSpec.makeMeasureSpec(resultSize, resultMode);
  }

  static measureComponent(component: GLView, widthSpec: number, heightSpec: number): void {
    const lp = component.getLayoutParams();
    if (lp === null) {
      throw new Error('Layout parameters cannot be null');
    }
    const componentWidthSpec = GLView.getComponentSpec(widthSpec, lp.width);
    const componentHeightSpec = GLView.getComponentSpec(heightSpec, lp.height);
    component.measure(componentWidthSpec, componentHeightSpec);
  }

  /** 测量全部子视图（跳过 GONE）。 */
  static measureAllComponents(parent: GLView, widthSpec: number, heightSpec: number): void {
    for (let i = 0, n = parent.getComponentCount(); i < n; i++) {
      const component = parent.getComponent(i);
      if (component.getVisibility() === GLView.GONE) {
        continue;
      }
      GLView.measureComponent(component, widthSpec, heightSpec);
    }
  }

  // ==========================================================================
  // LayoutParams
  // ==========================================================================

  getLayoutParams(): GLViewLayoutParams | null {
    return this.mLayoutParams;
  }

  setLayoutParams(params: GLViewLayoutParams | null): void {
    if (params === null) {
      const parent = this.mParent;
      if (parent === null) {
        throw new Error('Layout parameters cannot be null');
      }
      params = parent.generateDefaultLayoutParams();
    }
    this.mLayoutParams = params;
    this.requestLayout();
  }

  protected checkLayoutParams(p: GLViewLayoutParams | null): boolean {
    return p !== null;
  }

  protected generateDefaultLayoutParams(): GLViewLayoutParams {
    return new GLViewLayoutParams(GLViewLayoutParams.WRAP_CONTENT,
      GLViewLayoutParams.WRAP_CONTENT);
  }

  protected generateLayoutParams(p: GLViewLayoutParams): GLViewLayoutParams {
    return new GLViewLayoutParams(p);
  }

  /** 取后代相对本视图的边界（沿父链累加 bounds 左上角）。 */
  getBoundsOf(descendant: GLView, out: Rect): boolean {
    let xOffset = 0;
    let yOffset = 0;
    let view: GLView | null = descendant;
    while (view !== this) {
      if (view === null) {
        return false;
      }
      const bounds = view.mBounds;
      xOffset += bounds.left;
      yOffset += bounds.top;
      view = view.mParent;
    }
    out.set(xOffset, yOffset, xOffset + descendant.getWidth(), yOffset + descendant.getHeight());
    return true;
  }

  protected onVisibilityChanged(changedView: GLView, visibility: number): void {
    for (let i = 0, n = this.getComponentCount(); i < n; ++i) {
      this.getComponent(i).onVisibilityChanged(changedView, visibility);
    }
  }

  // ==========================================================================
  // 生命周期钩子（默认递归子视图）
  // ==========================================================================

  onAttachToRoot(root: GLRoot): void {
    this.mRoot = root;
    for (let i = 0, n = this.getComponentCount(); i < n; ++i) {
      this.getComponent(i).onAttachToRoot(root);
    }
  }

  onDetachFromRoot(): void {
    for (let i = 0, n = this.getComponentCount(); i < n; ++i) {
      this.getComponent(i).onDetachFromRoot();
    }
    this.mRoot = null;
  }

  onPause(): void {
    for (let i = 0, n = this.getComponentCount(); i < n; ++i) {
      this.getComponent(i).onPause();
    }
  }

  onResume(): void {
    for (let i = 0, n = this.getComponentCount(); i < n; ++i) {
      this.getComponent(i).onResume();
    }
  }

  lockRendering(): void {
    const root = this.mRoot;
    if (root !== null) {
      root.lockRenderThread();
    }
  }

  unlockRendering(): void {
    const root = this.mRoot;
    if (root !== null) {
      root.unlockRenderThread();
    }
  }

  /** 调试：把视图树打到 hilog。 */
  dumpTree(prefix: string): void {
    hilog.debug(DOMAIN, TAG, '%{public}s%{public}s', prefix, 'GLView');
    for (let i = 0, n = this.getComponentCount(); i < n; ++i) {
      this.getComponent(i).dumpTree(prefix + '....');
    }
  }
}

/** `GLView.OnClickListener`（ArkTS 不支持接口嵌套，提为顶层）。 */
export interface GLViewOnClickListener {
  onClick(v: GLView): boolean;
}

/** `GLView.OnLongClickListener`。 */
export interface GLViewOnLongClickListener {
  onLongClick(v: GLView): boolean;
}

/**
 * `GLViewMeasureSpec`：把 (size, mode) 打包进一个 32 位整数。
 * 位布局与 AOSP 完全一致（MODE 在高 2 位），因此跨模块传递 spec 的数值也一致。
 */
export class GLViewMeasureSpec {
  private static readonly MODE_SHIFT: number = 30;
  private static readonly MODE_MASK: number = 0x3 << GLViewMeasureSpec.MODE_SHIFT;

  /** 父容器未施加约束。 */
  static readonly UNSPECIFIED: number = 0 << GLViewMeasureSpec.MODE_SHIFT;

  /** 父容器给出精确尺寸。 */
  static readonly EXACTLY: number = 1 << GLViewMeasureSpec.MODE_SHIFT;

  /** 父容器给出上限，子视图可以更小。 */
  static readonly AT_MOST: number = 2 << GLViewMeasureSpec.MODE_SHIFT;

  /** 允许的最大尺寸。 */
  static readonly MAX_SIZE: number = ~GLViewMeasureSpec.MODE_MASK;

  static makeMeasureSpec(size: number, mode: number): number {
    return ((size & ~GLViewMeasureSpec.MODE_MASK) | (mode & GLViewMeasureSpec.MODE_MASK)) | 0;
  }

  static getMode(measureSpec: number): number {
    return (measureSpec & GLViewMeasureSpec.MODE_MASK) | 0;
  }

  static getSize(measureSpec: number): number {
    return (measureSpec & ~GLViewMeasureSpec.MODE_MASK) | 0;
  }

  static toString(measureSpec: number): string {
    const mode = GLViewMeasureSpec.getMode(measureSpec);
    const size = GLViewMeasureSpec.getSize(measureSpec);
    let modeName: string;
    if (mode === GLViewMeasureSpec.UNSPECIFIED) {
      modeName = 'UNSPECIFIED';
    } else if (mode === GLViewMeasureSpec.EXACTLY) {
      modeName = 'EXACTLY';
    } else if (mode === GLViewMeasureSpec.AT_MOST) {
      modeName = 'AT_MOST';
    } else {
      modeName = `${mode}`;
    }
    return `MeasureSpec: ${modeName} ${size}`;
  }
}

/** `GLView.LayoutParams`（对位 `android.view.ViewGroup.LayoutParams`）。 */
export class GLViewLayoutParams {
  /** 子视图想要和父容器一样大。 */
  static readonly MATCH_PARENT: number = -1;

  /** 子视图只想要包住自身内容。 */
  static readonly WRAP_CONTENT: number = -2;

  width: number;
  height: number;

  /** `LayoutParams(w,h)` 与拷贝构造合一。 */
  constructor(width: number | GLViewLayoutParams, height?: number) {
    if (typeof width === 'number') {
      this.width = width;
      this.height = height as number;
    } else {
      this.width = width.width;
      this.height = width.height;
    }
  }
}

/** `GLView.GravityLayoutParams`：带 gravity 的布局参数。 */
export class GLViewGravityLayoutParams extends GLViewLayoutParams {
  gravity: number = Gravity.NO_GRAVITY;

  /** `GravityLayoutParams(LayoutParams source)` 与 `(w, h)` 合一。 */
  constructor(width: number | GLViewLayoutParams, height?: number) {
    super(width, height === undefined ? 0 : height);
    if (typeof width !== 'number' && width instanceof GLViewGravityLayoutParams) {
      this.gravity = width.gravity;
    }
  }
}

// 兼容上游"嵌套类"的写法：`GLViewMeasureSpec` / `GLView.LayoutParams`
export type MeasureSpec = GLViewMeasureSpec;
export type LayoutParams = GLViewLayoutParams;
