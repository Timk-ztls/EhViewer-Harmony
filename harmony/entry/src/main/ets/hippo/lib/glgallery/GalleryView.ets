/*
 * Copyright 2016 Hippo Seven
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
import { Rect } from '../glview/util/Rect';
import { Color } from '../glview/util/Color';
import { MotionEvent } from '../glview/util/MotionEvent';
import { GLCanvas } from '../glview/glrenderer/GLCanvas';
import { Texture } from '../glview/glrenderer/Texture';
import { BasicTexture } from '../glview/glrenderer/BasicTexture';
import { OffscreenCanvasLike } from '../glview/glrenderer/CanvasTexture';
import { StringTexture, TextPaintFactoryLike } from '../glview/glrenderer/StringTexture';
import { ImageMovableTextTexture } from '../glview/image/ImageMovableTextTexture';
import { GLView, GLViewLayoutParams, GLViewMeasureSpec } from '../glview/view/GLView';
import { GLRoot } from '../glview/view/GLRoot';
import { AnimationTime } from '../glview/view/AnimationTime';
import { GLEdgeView } from '../glview/widget/GLEdgeView';
import { GLProgressView } from '../glview/widget/GLProgressView';
import { GLTextureView } from '../glview/widget/GLTextureView';
import { GalleryUtils } from '../glview/util/GalleryUtils';
import { MathUtils } from '../yorozuya/MathUtils';
import { Pool } from '../yorozuya/Pool';
import { GestureRecognizer, GestureRecognizerListener } from './GestureRecognizer';
import { GalleryPageView, GalleryPageErrorHost } from './GalleryPageView';
import { ImageView } from './ImageView';

const TAG = 'GalleryView';
const DOMAIN = 0x0000;

/** 布局管理器工厂（**注入点**，见 `GalleryView.setLayoutManagerFactory`）。 */
export interface GalleryLayoutManagerFactory {
  createPagerLayoutManager(galleryView: GalleryView, scaleMode: number, startPosition: number,
    pagerInterval: number): GalleryLayoutManager;

  createScrollLayoutManager(galleryView: GalleryView, scrollInterval: number): GalleryLayoutManager;
}

/**
 * `com.hippo.lib.glgallery.GalleryView.Adapter`：页数据源。
 */
export abstract class GalleryAdapter {
  protected mGalleryView: GalleryView | null = null;

  /** 由 `GalleryView` 构造时调用（上游 `setGalleryView`）。 */
  setGalleryView(galleryView: GalleryView): void {
    this.mGalleryView = galleryView;
  }

  getGalleryView(): GalleryView | null {
    return this.mGalleryView;
  }

  bind(view: GalleryPageView, index: number): void {
    this.onBind(view, index);
    view.setIndex(index);
  }

  unbind(view: GalleryPageView): void {
    this.onUnbind(view, view.getIndex());
    view.setIndex(GalleryPageView.INVALID_INDEX);
  }

  abstract onBind(view: GalleryPageView, index: number): void;

  abstract onUnbind(view: GalleryPageView, index: number): void;

  /** @return null 表示无错误 */
  abstract getError(): string | null;

  abstract size(): number;

  /** 数据变化（`SimpleAdapter` 覆盖后转给 `GalleryView`）。 */
  onDataChanged(): void {
  }
}

/**
 * `com.hippo.lib.glgallery.GalleryView.LayoutManager`：布局管理器抽象基类。
 *
 * `PagerLayoutManager`(960) / `ScrollLayoutManager`(1095) 由 net-parse 并行移植（在途）。
 * 这里保留完整抽象面（21 个方法，与上游一一对应），并额外提供
 * `GalleryView.setLayoutManagerFactory()` 注入点 —— 两个管理器落地后一行接线即可。
 */
export abstract class GalleryLayoutManager {
  protected mGalleryView: GalleryView;

  constructor(galleryView: GalleryView) {
    this.mGalleryView = galleryView;
  }

  abstract onAttach(adapter: GalleryAdapter): void;

  abstract onDetach(): GalleryAdapter;

  abstract onFill(): void;

  abstract onDown(): void;

  abstract onUp(): void;

  abstract onDoubleTapConfirmed(x: number, y: number): void;

  abstract onLongPress(x: number, y: number): void;

  abstract onScroll(dx: number, dy: number, totalX: number, totalY: number, x: number,
    y: number): void;

  abstract onFling(velocityX: number, velocityY: number): void;

  abstract canScale(): boolean;

  abstract onScale(focusX: number, focusY: number, scale: number): void;

  abstract onUpdateAnimation(time: number): boolean;

  abstract onDataChanged(): void;

  abstract onPageLeft(): void;

  abstract onPageRight(): void;

  abstract isTapOrPressEnable(): boolean;

  abstract findPageByIndex(index: number): GalleryPageView | null;

  /** @return `GalleryPageView.INVALID_INDEX` 表示无当前页 */
  abstract getCurrentIndex(): number;

  abstract setCurrentIndex(index: number): void;

  abstract getIndexUnder(x: number, y: number): number;

  /** 内部索引（不触发动画/吸附）。 */
  abstract getInternalCurrentIndex(): number;

  /** 可选配置同步方法（Pager/Scroll 子类按需覆写，保持 mock 兼容性）。 */
  setPagerMode(_mode: number): void {
  }

  setPagerScaleMode(_scaleMode: number): void {
  }

  setPagerStartPosition(_startPosition: number): void {
  }

  setPageInterval(_interval: number): void {
  }

  /** 把视图居中放入 `GalleryView`（上游 `placeCenter`）。 */
  protected placeCenter(view: GLView): void {
    const spec = GLViewMeasureSpec.makeMeasureSpec(GLViewLayoutParams.WRAP_CONTENT,
      GLViewLayoutParams.WRAP_CONTENT);
    view.measure(spec, spec);
    const viewWidth = view.getMeasuredWidth();
    const viewHeight = view.getMeasuredHeight();
    const viewLeft = Math.trunc(this.mGalleryView.getWidth() / 2) - Math.trunc(viewWidth / 2);
    const viewTop = Math.trunc(this.mGalleryView.getHeight() / 2) - Math.trunc(viewHeight / 2);
    view.layout(viewLeft, viewTop, viewLeft + viewWidth, viewTop + viewHeight);
  }
}

/**
 * `com.hippo.lib.glgallery.GalleryView.Listener`：事件回调。
 */
export interface GalleryViewListener {
  onUpdateCurrentIndex(index: number): void;

  onTapSliderArea(): void;

  onTapMenuArea(): void;

  onTapErrorText(index: number): void;

  onLongPressPage(index: number): void;

  onAutoTransferDone(): void;
}

/** `GalleryView.Builder`：参数多，ArkTS 无命名参数 → 用链式 Builder 保持上游写法。 */
export class GalleryViewBuilder {
  private readonly mAdapter: GalleryAdapter;
  private mListener: GalleryViewListener | null = null;

  private mLayoutMode: number = GalleryView.LAYOUT_LEFT_TO_RIGHT;
  private mScaleMode: number = ImageView.SCALE_FIT;
  private mStartPosition: number = ImageView.START_POSITION_TOP_LEFT;
  private mStartPage: number = 0;

  private mBackgroundColor: number = Color.BLACK;
  private mEdgeColor: number = Color.WHITE;
  private mPagerInterval: number = 48;
  private mScrollInterval: number = 24;
  private mPageMinHeight: number = 256;
  private mPageInfoInterval: number = 24;
  private mProgressColor: number = Color.WHITE;
  private mProgressSize: number = 56;
  private mPageTextColor: number = Color.WHITE;
  private mPageTextSize: number = 56;
  private mErrorTextColor: number = Color.RED;
  private mErrorTextSize: number = 24;
  private mDefaultErrorString: string = 'Error';
  private mEmptyString: string = 'Empty';

  constructor(adapter: GalleryAdapter) {
    this.mAdapter = adapter;
  }

  setListener(listener: GalleryViewListener | null): GalleryViewBuilder {
    this.mListener = listener;
    return this;
  }

  setLayoutMode(layoutMode: number): GalleryViewBuilder {
    this.mLayoutMode = layoutMode;
    return this;
  }

  setScaleMode(scaleMode: number): GalleryViewBuilder {
    this.mScaleMode = scaleMode;
    return this;
  }

  setStartPosition(startPosition: number): GalleryViewBuilder {
    this.mStartPosition = startPosition;
    return this;
  }

  setStartPage(startPage: number): GalleryViewBuilder {
    this.mStartPage = startPage;
    return this;
  }

  setBackgroundColor(color: number): GalleryViewBuilder {
    this.mBackgroundColor = color;
    return this;
  }

  setEdgeColor(color: number): GalleryViewBuilder {
    this.mEdgeColor = color;
    return this;
  }

  setPagerInterval(interval: number): GalleryViewBuilder {
    this.mPagerInterval = interval;
    return this;
  }

  setScrollInterval(interval: number): GalleryViewBuilder {
    this.mScrollInterval = interval;
    return this;
  }

  setPageMinHeight(height: number): GalleryViewBuilder {
    this.mPageMinHeight = height;
    return this;
  }

  setPageInfoInterval(interval: number): GalleryViewBuilder {
    this.mPageInfoInterval = interval;
    return this;
  }

  setProgressColor(color: number): GalleryViewBuilder {
    this.mProgressColor = color;
    return this;
  }

  setProgressSize(size: number): GalleryViewBuilder {
    this.mProgressSize = size;
    return this;
  }

  setPageTextColor(color: number): GalleryViewBuilder {
    this.mPageTextColor = color;
    return this;
  }

  setPageTextSize(size: number): GalleryViewBuilder {
    this.mPageTextSize = size;
    return this;
  }

  setErrorTextColor(color: number): GalleryViewBuilder {
    this.mErrorTextColor = color;
    return this;
  }

  setErrorTextSize(size: number): GalleryViewBuilder {
    this.mErrorTextSize = size;
    return this;
  }

  setDefaultErrorString(s: string): GalleryViewBuilder {
    this.mDefaultErrorString = s;
    return this;
  }

  setEmptyString(s: string): GalleryViewBuilder {
    this.mEmptyString = s;
    return this;
  }

  build(): GalleryView {
    return new GalleryView(this);
  }

  // ---- Builder 的字段读取（GalleryView 构造用；ArkTS 无包内可见性，用 getter） ----
  getAdapter(): GalleryAdapter { return this.mAdapter; }
  getListener(): GalleryViewListener | null { return this.mListener; }
  getLayoutMode(): number { return this.mLayoutMode; }
  getScaleMode(): number { return this.mScaleMode; }
  getStartPosition(): number { return this.mStartPosition; }
  getStartPage(): number { return this.mStartPage; }
  getBackgroundColor(): number { return this.mBackgroundColor; }
  getEdgeColor(): number { return this.mEdgeColor; }
  getPagerInterval(): number { return this.mPagerInterval; }
  getScrollInterval(): number { return this.mScrollInterval; }
  getPageMinHeight(): number { return this.mPageMinHeight; }
  getPageInfoInterval(): number { return this.mPageInfoInterval; }
  getProgressColor(): number { return this.mProgressColor; }
  getProgressSize(): number { return this.mProgressSize; }
  getPageTextColor(): number { return this.mPageTextColor; }
  getPageTextSize(): number { return this.mPageTextSize; }
  getErrorTextColor(): number { return this.mErrorTextColor; }
  getErrorTextSize(): number { return this.mErrorTextSize; }
  getDefaultErrorString(): string { return this.mDefaultErrorString; }
  getEmptyString(): string { return this.mEmptyString; }
}

/**
 * `com.hippo.lib.glgallery.GalleryView` 的 ArkTS 等价实现。
 *
 * 画廊的主视图：手势 → 方法队列 → 渲染线程应用 → 布局管理器排布页面。
 *
 * ## 方法队列（`postMethod` / `dispatchMethod`）—— 这是整个类的骨架
 * 上游从 **UI 线程**收到所有手势/外部调用，但布局操作只能在**渲染线程**执行。
 * 于是每个入口都只是 `postMethod(...)` 入队 + `invalidate()`，
 * 真正的实现（`xxxInternal`）在 `render()` 开头的 `dispatchMethod()` 里按序执行。
 *
 * 鸿蒙侧只有单 VM（无渲染线程），但**队列照搬**：
 * - 语义上"同一帧内多次手势只应用一次布局"仍然成立（`dispatchMethod` 攒这么多条一起处理）
 * - 若改成直接执行，`onScroll` 会在两次 `onUpdateAnimation` 之间改状态，
 *   动画与手势的交错顺序会变 → 拖动时页面"顿"一下
 *
 * ## 23 个 method 常量 = 上游的 23 个入口
 * 手势 14 个（`onSingleTapUp` … `onPointerUp`）+ 外部调用 9 个
 * （`setLayoutMode` / `setCurrentPage` / `pageLeft` / `pageRight` / `setScaleMode` /
 * `setStartPosition` / `onAttachToRoot` / `setPagerInterval` / `setScrollInterval`）。
 *
 * ## 布局管理器在途
 * `PagerLayoutManager`(960) / `ScrollLayoutManager`(1095) 由 net-parse 并行移植。
 * 本类保留完整抽象面 + `setLayoutManagerFactory()` 注入点；未注入时
 * `attachLayoutManager()` 只记 warn 并保持 `mLayoutManager = null`
 * （所有 `xxxInternal` 都对 null 做了判空，与上游"还没 attach"的分支一致）。
 */
export class GalleryView extends GLView implements GestureRecognizerListener, GalleryPageErrorHost {
  static readonly LAYOUT_LEFT_TO_RIGHT: number = 0;
  static readonly LAYOUT_RIGHT_TO_LEFT: number = 1;
  static readonly LAYOUT_TOP_TO_BOTTOM: number = 2;

  static readonly SCALE_ORIGIN: number = ImageView.SCALE_ORIGIN;
  static readonly SCALE_FIT_WIDTH: number = ImageView.SCALE_FIT_WIDTH;
  static readonly SCALE_FIT_HEIGHT: number = ImageView.SCALE_FIT_HEIGHT;
  static readonly SCALE_FIT: number = ImageView.SCALE_FIT;
  static readonly SCALE_FIXED: number = ImageView.SCALE_FIXED;

  static readonly START_POSITION_TOP_LEFT: number = ImageView.START_POSITION_TOP_LEFT;
  static readonly START_POSITION_TOP_RIGHT: number = ImageView.START_POSITION_TOP_RIGHT;
  static readonly START_POSITION_BOTTOM_LEFT: number = ImageView.START_POSITION_BOTTOM_LEFT;
  static readonly START_POSITION_BOTTOM_RIGHT: number = ImageView.START_POSITION_BOTTOM_RIGHT;
  static readonly START_POSITION_CENTER: number = ImageView.START_POSITION_CENTER;

  /** 四个响应区（相对尺寸，`onLayout` 时换算成像素 `Rect`）。 */
  private static readonly LEFT_AREA: number[] = [0.0, 0.0, 1.0 / 3.0, 1.0];
  private static readonly RIGHT_AREA: number[] = [2.0 / 3.0, 0.0, 1.0, 1.0];
  private static readonly MENU_AREA: number[] = [1.0 / 3.0, 0.0, 2.0 / 3.0, 1.0 / 2.0];
  private static readonly SLIDER_AREA: number[] = [1.0 / 3.0, 1.0 / 2.0, 2.0 / 3.0, 1.0];

  // ---- 方法队列的操作码（顺序与上游一致，禁止重排） ----
  private static readonly METHOD_ON_SINGLE_TAP_UP: number = 0;
  private static readonly METHOD_ON_SINGLE_TAP_CONFIRMED: number = 1;
  private static readonly METHOD_ON_DOUBLE_TAP: number = 2;
  private static readonly METHOD_ON_DOUBLE_TAP_CONFIRMED: number = 3;
  private static readonly METHOD_ON_LONG_PRESS: number = 4;
  private static readonly METHOD_ON_SCROLL: number = 5;
  private static readonly METHOD_ON_FLING: number = 6;
  private static readonly METHOD_ON_SCALE_BEGIN: number = 7;
  private static readonly METHOD_ON_SCALE: number = 8;
  private static readonly METHOD_ON_SCALE_END: number = 9;
  private static readonly METHOD_ON_DOWN: number = 10;
  private static readonly METHOD_ON_UP: number = 11;
  private static readonly METHOD_ON_POINTER_DOWN: number = 12;
  private static readonly METHOD_ON_POINTER_UP: number = 13;
  private static readonly METHOD_SET_LAYOUT_MODE: number = 14;
  private static readonly METHOD_SET_CURRENT_PAGE: number = 15;
  private static readonly METHOD_PAGE_LEFT: number = 16;
  private static readonly METHOD_PAGE_RIGHT: number = 17;
  private static readonly METHOD_SET_SCALE_MODE: number = 18;
  private static readonly METHOD_SET_START_POSITION: number = 19;
  private static readonly METHOD_ON_ATTACH_TO_ROOT: number = 20;
  private static readonly METHOD_SET_PAGER_INTERVAL: number = 21;
  private static readonly METHOD_SET_SCROLL_INTERVAL: number = 22;

  private static sLayoutManagerFactory: GalleryLayoutManagerFactory | null = null;
  private static sTextPaintFactory: TextPaintFactoryLike | null = null;
  private static sOffscreenCanvas: OffscreenCanvasLike | null = null;

  /**
   * 注入文字渲染接缝（`StringTexture` / `MultiLineTexture` 的 `factory` + `offscreen`）。
   * 未注入时错误文案不显示（只打 warn）。
   */
  static setTextRendering(factory: TextPaintFactoryLike | null,
    offscreen: OffscreenCanvasLike | null): void {
    GalleryView.sTextPaintFactory = factory;
    GalleryView.sOffscreenCanvas = offscreen;
  }

  /** 注入布局管理器工厂（两个管理器落地后调用一次）。 */
  static setLayoutManagerFactory(factory: GalleryLayoutManagerFactory | null): void {
    GalleryView.sLayoutManagerFactory = factory;
  }

  private mAdapter: GalleryAdapter | null;
  private readonly mGestureRecognizer: GestureRecognizer;
  private readonly mListener: GalleryViewListener | null;

  private mPageTextTexture: ImageMovableTextTexture | null = null;

  private mPagerLayoutManager: GalleryLayoutManager | null = null;
  private mScrollLayoutManager: GalleryLayoutManager | null = null;
  private mLayoutManager: GalleryLayoutManager | null = null;

  private readonly mEdgeView: GLEdgeView;
  private readonly mGalleryPageViewPool: Pool<GalleryPageView> = new Pool<GalleryPageView>(5);
  private mProgressCache: GLProgressView | null = null;
  private mErrorViewCache: GLTextureView | null = null;

  /** 与 `GLView` 的私有 `mBackgroundColor` 重名，改名避让（ArkTS 不允许同名私有成员）。 */
  private readonly mGalleryBgColor: number;
  private mPagerInterval: number;
  private mScrollInterval: number;
  private readonly mPageMinHeight: number;
  private readonly mPageInfoInterval: number;
  private readonly mProgressColor: number;
  private readonly mProgressSize: number;
  private readonly mPageTextColor: number;
  private readonly mPageTextSize: number;
  private readonly mErrorTextSize: number;
  private readonly mErrorTextColor: number;

  private readonly mDefaultErrorString: string;
  private readonly mEmptyString: string;

  private mEnableRequestFill: boolean = true;
  private mRequestFill: boolean = false;
  private mWillFill: boolean = false;

  private mScale: boolean = false;
  private mScroll: boolean = false;
  private mFirstScroll: boolean = false;

  private readonly mLeftArea: Rect = new Rect();
  private readonly mRightArea: Rect = new Rect();
  private readonly mMenuArea: Rect = new Rect();
  private readonly mSliderArea: Rect = new Rect();

  private mLayoutMode: number = GalleryView.LAYOUT_RIGHT_TO_LEFT;
  private mScaleMode: number = ImageView.SCALE_FIT;
  private mStartPosition: number = ImageView.START_POSITION_TOP_LEFT;
  private mIndex: number;

  private readonly mMethodList: number[] = [];
  private readonly mArgsList: number[][] = [];
  private readonly mMethodListTemp: number[] = [];
  private readonly mArgsListTemp: number[][] = [];

  private mCurrentIndex: number = GalleryPageView.INVALID_INDEX;

  constructor(builder: GalleryViewBuilder) {
    super();
    const adapter = builder.getAdapter();
    this.mAdapter = adapter;
    adapter.setGalleryView(this);
    this.mListener = builder.getListener();
    this.mGestureRecognizer = new GestureRecognizer(this);
    this.mEdgeView = new GLEdgeView(builder.getEdgeColor());

    this.mLayoutMode = builder.getLayoutMode();
    this.mScaleMode = builder.getScaleMode();
    this.mStartPosition = builder.getStartPosition();
    this.mIndex = MathUtils.clamp(builder.getStartPage(), 0, Number.MAX_SAFE_INTEGER);

    this.mGalleryBgColor = builder.getBackgroundColor();
    this.mPageMinHeight = builder.getPageMinHeight();
    this.mPagerInterval = builder.getPagerInterval();
    this.mScrollInterval = builder.getScrollInterval();
    this.mPageInfoInterval = builder.getPageInfoInterval();
    this.mProgressColor = builder.getProgressColor();
    this.mProgressSize = builder.getProgressSize();
    this.mPageTextColor = builder.getPageTextColor();
    this.mPageTextSize = builder.getPageTextSize();
    this.mErrorTextColor = builder.getErrorTextColor();
    this.mErrorTextSize = builder.getErrorTextSize();

    this.mDefaultErrorString = builder.getDefaultErrorString();
    this.mEmptyString = builder.getEmptyString();

    this.setBackgroundColor(this.mGalleryBgColor);
  }

  // ==========================================================================
  // 布局管理器
  // ==========================================================================

  private ensurePagerLayoutManager(): GalleryLayoutManager | null {
    if (this.mPagerLayoutManager === null) {
      const factory = GalleryView.sLayoutManagerFactory;
      if (factory === null) {
        hilog.warn(DOMAIN, TAG, 'no layout manager factory: PagerLayoutManager unavailable');
        return null;
      }
      try {
        this.mPagerLayoutManager = factory.createPagerLayoutManager(this, this.mScaleMode,
          this.mStartPosition, this.mPagerInterval);
      } catch (err) {
        // `PagerLayoutManager` 尚未注入（net-parse 在途）：降级为"无布局管理器"，不崩。
        // 见 `GalleryLayoutFactory.PagerLayoutManagerUnavailableError`。
        hilog.warn(DOMAIN, TAG, 'createPagerLayoutManager failed: %{public}s',
          (err as Error).message);
        return null;
      }
    }
    return this.mPagerLayoutManager;
  }

  private ensureScrollLayoutManager(): GalleryLayoutManager | null {
    if (this.mScrollLayoutManager === null) {
      const factory = GalleryView.sLayoutManagerFactory;
      if (factory === null) {
        hilog.warn(DOMAIN, TAG, 'no layout manager factory: ScrollLayoutManager unavailable');
        return null;
      }
      try {
        this.mScrollLayoutManager = factory.createScrollLayoutManager(this, this.mScrollInterval);
      } catch (err) {
        hilog.warn(DOMAIN, TAG, 'createScrollLayoutManager failed: %{public}s',
          (err as Error).message);
        return null;
      }
    }
    return this.mScrollLayoutManager;
  }

  private attachLayoutManager(): void {
    if (this.mLayoutManager !== null) {
      return;
    }
    const adapter = this.mAdapter;
    if (adapter === null) {
      return;
    }

    let manager: GalleryLayoutManager | null = null;
    if (this.mLayoutMode === GalleryView.LAYOUT_TOP_TO_BOTTOM) {
      manager = this.ensureScrollLayoutManager();
    } else {
      manager = this.ensurePagerLayoutManager();
      if (manager !== null) {
        manager.setPagerMode(this.mLayoutMode);
      }
    }
    if (manager === null) {
      return;
    }
    manager.onAttach(adapter);
    manager.setCurrentIndex(this.mIndex);
    this.mAdapter = null;
    this.mLayoutManager = manager;
    this.requestFill();
  }

  private detachLayoutManager(): void {
    const manager = this.mLayoutManager;
    if (manager === null) {
      return;
    }
    this.mIndex = manager.getInternalCurrentIndex();
    this.mAdapter = manager.onDetach();
    this.mLayoutManager = null;
  }

  private onAttachToRootInternal(): void {
    if (this.mPageTextTexture === null) {
      // 页码图集：0-9 十个字符（上游 `new char[]{'0'...'9'}`）
      try {
        this.mPageTextTexture = ImageMovableTextTexture.create(this.mPageTextSize,
          this.mPageTextColor, '0123456789');
      } catch (e) {
        const msg: string = e instanceof Error ? e.message : String(e);
        hilog.warn(DOMAIN, TAG, 'ImageMovableTextTexture.create failed: %{public}s', msg);
      }
    }
    this.attachLayoutManager();
  }

  private setPagerIntervalInternal(interval: number): void {
    if (this.mPagerInterval === interval) {
      return;
    }
    this.mPagerInterval = interval;
    if (this.mPagerLayoutManager !== null) {
      this.mPagerLayoutManager.setPageInterval(interval);
    }
  }

  private setScrollIntervalInternal(interval: number): void {
    if (this.mScrollInterval === interval) {
      return;
    }
    this.mScrollInterval = interval;
    if (this.mScrollLayoutManager !== null) {
      this.mScrollLayoutManager.setPageInterval(interval);
    }
  }

  // ==========================================================================
  // 生命周期
  // ==========================================================================

  onAttachToRoot(root: GLRoot): void {
    super.onAttachToRoot(root);
    this.mEdgeView.onAttachToRoot(root);
    this.postMethod(GalleryView.METHOD_ON_ATTACH_TO_ROOT);
  }

  onDetachFromRoot(): void {
    // 上游：detach 后 render() 不再被调用，所以必须在这里清理
    this.detachLayoutManager();
    const texture = this.mPageTextTexture;
    if (texture !== null) {
      texture.recycle();
      this.mPageTextTexture = null;
    }
    super.onDetachFromRoot();
    this.mEdgeView.onDetachFromRoot();
  }

  // ==========================================================================
  // sanitize（上游三个 static 校验函数）
  // ==========================================================================

  static sanitizeLayoutMode(layoutMode: number): number {
    if (layoutMode !== GalleryView.LAYOUT_LEFT_TO_RIGHT
      && layoutMode !== GalleryView.LAYOUT_RIGHT_TO_LEFT
      && layoutMode !== GalleryView.LAYOUT_TOP_TO_BOTTOM) {
      return GalleryView.LAYOUT_LEFT_TO_RIGHT;
    }
    return layoutMode;
  }

  static sanitizeScaleMode(scaleMode: number): number {
    if (scaleMode !== GalleryView.SCALE_ORIGIN && scaleMode !== GalleryView.SCALE_FIT_WIDTH
      && scaleMode !== GalleryView.SCALE_FIT_HEIGHT && scaleMode !== GalleryView.SCALE_FIT
      && scaleMode !== GalleryView.SCALE_FIXED) {
      return GalleryView.SCALE_FIT;
    }
    return scaleMode;
  }

  static sanitizeStartPosition(startPosition: number): number {
    if (startPosition !== GalleryView.START_POSITION_TOP_LEFT
      && startPosition !== GalleryView.START_POSITION_TOP_RIGHT
      && startPosition !== GalleryView.START_POSITION_BOTTOM_LEFT
      && startPosition !== GalleryView.START_POSITION_BOTTOM_RIGHT
      && startPosition !== GalleryView.START_POSITION_CENTER) {
      return GalleryView.START_POSITION_TOP_LEFT;
    }
    return startPosition;
  }

  // ==========================================================================
  // 查询 / 请求
  // ==========================================================================

  getLayoutMode(): number {
    return this.mLayoutMode;
  }

  getCurrentIndex(): number {
    return this.mCurrentIndex;
  }

  /** 上游覆写：尺寸不会变，所以 `requestLayout` 只触发 `requestFill`。 */
  requestLayout(): void {
    this.requestFill();
  }

  requestFill(): void {
    if (this.mEnableRequestFill) {
      this.mRequestFill = true;
      if (!this.mWillFill) {
        this.invalidate();
      }
    }
  }

  /** 事件不传给子视图，全部自己处理（上游注释）。 */
  dispatchTouchEvent(event: MotionEvent): boolean {
    this.mGestureRecognizer.onTouchEvent(event);
    return true;
  }

  getEdgeView(): GLEdgeView {
    return this.mEdgeView;
  }

  getDefaultErrorStr(): string {
    return this.mDefaultErrorString;
  }

  getEmptyStr(): string {
    return this.mEmptyString;
  }

  /** 读出并清除"本次手势的第一次滑动"标记。 */
  isFirstScroll(): boolean {
    const first = this.mFirstScroll;
    this.mFirstScroll = false;
    return first;
  }

  // ==========================================================================
  // 方法队列
  // ==========================================================================

  private postMethod(method: number, args?: number[]): void {
    this.mMethodList.push(method);
    this.mArgsList.push(args === undefined ? [] : args);
    this.invalidate();
  }

  setLayoutMode(layoutMode: number): void {
    this.postMethod(GalleryView.METHOD_SET_LAYOUT_MODE, [layoutMode]);
  }

  setCurrentPage(page: number): void {
    this.postMethod(GalleryView.METHOD_SET_CURRENT_PAGE, [page]);
  }

  pageLeft(): void {
    this.postMethod(GalleryView.METHOD_PAGE_LEFT);
  }

  pageRight(): void {
    this.postMethod(GalleryView.METHOD_PAGE_RIGHT);
  }

  setScaleMode(scaleMode: number): void {
    this.postMethod(GalleryView.METHOD_SET_SCALE_MODE, [scaleMode]);
  }

  setStartPosition(startPosition: number): void {
    this.postMethod(GalleryView.METHOD_SET_START_POSITION, [startPosition]);
  }

  setPagerInterval(interval: number): void {
    this.postMethod(GalleryView.METHOD_SET_PAGER_INTERVAL, [interval]);
  }

  setScrollInterval(interval: number): void {
    this.postMethod(GalleryView.METHOD_SET_SCROLL_INTERVAL, [interval]);
  }

  // ==========================================================================
  // GestureRecognizerListener（全部只入队）
  // ==========================================================================

  onSingleTapUp(x: number, y: number): boolean {
    this.postMethod(GalleryView.METHOD_ON_SINGLE_TAP_UP, [x, y]);
    return true;
  }

  onSingleTapConfirmed(x: number, y: number): boolean {
    this.postMethod(GalleryView.METHOD_ON_SINGLE_TAP_CONFIRMED, [x, y]);
    return true;
  }

  onDoubleTap(x: number, y: number): boolean {
    this.postMethod(GalleryView.METHOD_ON_DOUBLE_TAP, [x, y]);
    return true;
  }

  onDoubleTapConfirmed(x: number, y: number): boolean {
    this.postMethod(GalleryView.METHOD_ON_DOUBLE_TAP_CONFIRMED, [x, y]);
    return true;
  }

  onLongPress(x: number, y: number): void {
    const manager = this.mLayoutManager;
    if (manager !== null && !manager.isTapOrPressEnable()) {
      return;
    }
    this.postMethod(GalleryView.METHOD_ON_LONG_PRESS, [x, y]);
  }

  onScroll(dx: number, dy: number, totalX: number, totalY: number, x: number, y: number): boolean {
    this.postMethod(GalleryView.METHOD_ON_SCROLL, [dx, dy, totalX, totalY, x, y]);
    return true;
  }

  onFling(e1: MotionEvent, e2: MotionEvent, velocityX: number, velocityY: number): boolean {
    this.postMethod(GalleryView.METHOD_ON_FLING, [velocityX, velocityY]);
    return true;
  }

  onScaleBegin(focusX: number, focusY: number): boolean {
    this.postMethod(GalleryView.METHOD_ON_SCALE_BEGIN, [focusX, focusY]);
    return true;
  }

  onScale(focusX: number, focusY: number, scale: number): boolean {
    this.postMethod(GalleryView.METHOD_ON_SCALE, [focusX, focusY, scale]);
    return true;
  }

  onScaleEnd(): void {
    this.postMethod(GalleryView.METHOD_ON_SCALE_END);
  }

  onDown(x: number, y: number): void {
    this.postMethod(GalleryView.METHOD_ON_DOWN, [x, y]);
  }

  onUp(): void {
    this.postMethod(GalleryView.METHOD_ON_UP);
  }

  onPointerDown(x: number, y: number): void {
    this.postMethod(GalleryView.METHOD_ON_POINTER_DOWN, [x, y]);
  }

  onPointerUp(): void {
    this.postMethod(GalleryView.METHOD_ON_POINTER_UP);
  }

  // ==========================================================================
  // 布局
  // ==========================================================================

  protected onLayout(changeSize: boolean, left: number, top: number, right: number,
    bottom: number): void {
    this.mEdgeView.layout(left, top, right, bottom);

    this.fill();

    if (changeSize) {
      const width = right - left;
      const height = bottom - top;
      GalleryView.setArea(this.mLeftArea, GalleryView.LEFT_AREA, width, height);
      GalleryView.setArea(this.mRightArea, GalleryView.RIGHT_AREA, width, height);
      GalleryView.setArea(this.mMenuArea, GalleryView.MENU_AREA, width, height);
      GalleryView.setArea(this.mSliderArea, GalleryView.SLIDER_AREA, width, height);
    }
  }

  private static setArea(area: Rect, ratios: number[], width: number, height: number): void {
    area.set(Math.trunc(ratios[0] * width), Math.trunc(ratios[1] * height),
      Math.trunc(ratios[2] * width), Math.trunc(ratios[3] * height));
  }

  // ==========================================================================
  // 各 Internal 实现（由 dispatchMethod 调用）
  // ==========================================================================

  /** 上游空实现（保留调用形状）。 */
  private onSingleTapUpInternal(x: number, y: number): void {
  }

  private onSingleTapConfirmedInternal(x: number, y: number): void {
    const manager = this.mLayoutManager;
    if (manager === null || !manager.isTapOrPressEnable()) {
      return;
    }

    const page = this.findPageUnder(x, y);
    if (page !== null && page.getIndex() !== GalleryPageView.INVALID_INDEX && page.isError()
      && page.isUnderInfo(x - page.bounds().left, y - page.bounds().top)) {
      const listener = this.mListener;
      if (listener !== null) {
        listener.onTapErrorText(page.getIndex());
      }
    } else if (this.mSliderArea.contains(Math.trunc(x), Math.trunc(y))) {
      const listener = this.mListener;
      if (listener !== null) {
        listener.onTapSliderArea();
      }
    } else if (this.mMenuArea.contains(Math.trunc(x), Math.trunc(y))) {
      const listener = this.mListener;
      if (listener !== null) {
        listener.onTapMenuArea();
      }
    } else if (this.mLeftArea.contains(Math.trunc(x), Math.trunc(y))) {
      manager.onPageLeft();
    } else if (this.mRightArea.contains(Math.trunc(x), Math.trunc(y))) {
      manager.onPageRight();
    }
  }

  /** 上游空实现。 */
  private onDoubleTapInternal(x: number, y: number): void {
  }

  private onDoubleTapConfirmedInternal(x: number, y: number): void {
    if (this.mScale) {
      return;
    }
    const manager = this.mLayoutManager;
    if (manager !== null) {
      manager.onDoubleTapConfirmed(x, y);
    }
  }

  private onLongPressInternal(x: number, y: number): void {
    if (this.mScale) {
      return;
    }
    const manager = this.mLayoutManager;
    if (manager === null) {
      return;
    }
    const index = manager.getIndexUnder(x, y);
    if (index === GalleryPageView.INVALID_INDEX) {
      return;
    }
    const listener = this.mListener;
    if (listener !== null) {
      listener.onLongPressPage(index);
    }
  }

  private onScrollInternal(dx: number, dy: number, totalX: number, totalY: number, x: number,
    y: number): void {
    if (this.mScale) {
      return;
    }
    this.mScroll = true;
    const manager = this.mLayoutManager;
    if (manager !== null) {
      manager.onScroll(dx, dy, totalX, totalY, x, y);
    }
  }

  private onFlingInternal(velocityX: number, velocityY: number): void {
    const manager = this.mLayoutManager;
    if (manager !== null) {
      manager.onFling(velocityX, velocityY);
    }
  }

  /** 上游：`onScaleBegin` 直接转成 `onScale(x, y, 1.0)`。 */
  private onScaleBeginInternal(focusX: number, focusY: number): void {
    this.onScaleInternal(focusX, focusY, 1.0);
  }

  private onScaleInternal(focusX: number, focusY: number, scale: number): void {
    const manager = this.mLayoutManager;
    if (this.mScroll || (manager !== null && !manager.canScale())) {
      return;
    }
    this.mScale = true;
    if (manager !== null) {
      manager.onScale(focusX, focusY, scale);
    }
  }

  /** 上游空实现。 */
  private onScaleEndInternal(): void {
  }

  private onDownInternal(x: number, y: number): void {
    this.mScale = false;
    this.mScroll = false;
    this.mFirstScroll = true;
    const manager = this.mLayoutManager;
    if (manager !== null) {
      manager.onDown();
    }
  }

  private onUpInternal(): void {
    const manager = this.mLayoutManager;
    if (manager !== null) {
      manager.onUp();
    }
  }

  private onPointerDownInternal(x: number, y: number): void {
    const manager = this.mLayoutManager;
    if (!this.mScroll && (manager !== null && manager.canScale())) {
      this.mScale = true;
    }
  }

  /** 上游空实现。 */
  private onPointerUpInternal(): void {
  }

  private setLayoutModeInternal(layoutMode: number): void {
    if (this.mLayoutMode === layoutMode) {
      return;
    }
    this.mLayoutMode = layoutMode;

    const manager = this.mLayoutManager;
    if (manager === null) {
      return;
    }

    // 目标管理器与当前不同 → 迁移；若已经在 Pager 下做 LTR/RTL 切换则直接更新模式
    if (layoutMode === GalleryView.LAYOUT_TOP_TO_BOTTOM) {
      const scrollManager = this.ensureScrollLayoutManager();
      if (scrollManager === null) {
        return;
      }
      if (manager !== scrollManager) {
        const index = manager.getInternalCurrentIndex();
        scrollManager.onAttach(manager.onDetach());
        scrollManager.setCurrentIndex(index);
        this.mLayoutManager = scrollManager;
      }
    } else {
      const pagerManager = this.ensurePagerLayoutManager();
      if (pagerManager === null) {
        return;
      }
      pagerManager.setPagerMode(layoutMode);
      if (manager !== pagerManager) {
        const index = manager.getInternalCurrentIndex();
        pagerManager.onAttach(manager.onDetach());
        pagerManager.setCurrentIndex(index);
        this.mLayoutManager = pagerManager;
      }
    }

    this.requestFill();
  }

  private setCurrentPageInternal(page: number): void {
    const manager = this.mLayoutManager;
    if (manager !== null) {
      manager.setCurrentIndex(page);
    } else {
      this.mIndex = page;
    }
  }

  private pageLeftInternal(): void {
    const manager = this.mLayoutManager;
    if (manager !== null) {
      manager.onPageLeft();
    }
  }

  private pageRightInternal(): void {
    const manager = this.mLayoutManager;
    if (manager !== null) {
      manager.onPageRight();
    }
  }

  private setScaleModeInternal(scaleMode: number): void {
    if (this.mScaleMode === scaleMode) {
      return;
    }
    this.mScaleMode = scaleMode;
    if (this.mPagerLayoutManager !== null) {
      this.mPagerLayoutManager.setPagerScaleMode(scaleMode);
    }
  }

  private setStartPositionInternal(startPosition: number): void {
    if (this.mStartPosition === startPosition) {
      return;
    }
    this.mStartPosition = startPosition;
    if (this.mPagerLayoutManager !== null) {
      this.mPagerLayoutManager.setPagerStartPosition(startPosition);
    }
  }

  // ==========================================================================
  // 填充 / 数据变化
  // ==========================================================================

  /** 数据变化（上游断言在渲染线程；单 VM 下该断言退化为空操作）。 */
  onDataChanged(): void {
    GalleryUtils.assertInRenderThread();
    const manager = this.mLayoutManager;
    if (manager !== null) {
      manager.onDataChanged();
    }
  }

  forceFill(): void {
    this.mRequestFill = true;
    this.fill();
  }

  private fill(): void {
    if (!this.mRequestFill) {
      return;
    }

    // 填充期间关闭 requestLayout，避免自我触发
    this.mEnableRequestFill = false;
    const manager = this.mLayoutManager;
    if (manager !== null) {
      manager.onFill();
    }
    this.mEnableRequestFill = true;
    this.mRequestFill = false;
  }

  // ==========================================================================
  // 渲染
  // ==========================================================================

  render(canvas: GLCanvas): void {
    this.mWillFill = true;
    const oldCurrentIndex = this.mCurrentIndex;

    // Dispatch method
    this.dispatchMethod();

    const time = AnimationTime.get();
    const manager = this.mLayoutManager;
    if (manager !== null && manager.onUpdateAnimation(time)) {
      this.invalidate();
    }

    this.fill();
    this.mWillFill = false;

    super.render(canvas);
    this.mEdgeView.render(canvas);

    const newCurrentIndex = manager !== null ? manager.getCurrentIndex()
      : GalleryPageView.INVALID_INDEX;
    this.mCurrentIndex = newCurrentIndex;

    if (oldCurrentIndex !== newCurrentIndex && this.mListener !== null) {
      this.mListener.onUpdateCurrentIndex(newCurrentIndex);
    }
  }

  private dispatchMethod(): void {
    if (this.mMethodList.length === 0) {
      return;
    }

    // 交换缓冲：把队列整体搬到 temp 再逐条执行（执行期间新入队的不在本帧处理）
    this.mMethodListTemp.length = 0;
    this.mArgsListTemp.length = 0;
    for (let i = 0; i < this.mMethodList.length; i++) {
      this.mMethodListTemp.push(this.mMethodList[i]);
      this.mArgsListTemp.push(this.mArgsList[i]);
    }
    this.mMethodList.length = 0;
    this.mArgsList.length = 0;

    for (let i = 0, n = this.mMethodListTemp.length; i < n; i++) {
      const method = this.mMethodListTemp[i];
      const args = this.mArgsListTemp[i];
      this.dispatchOne(method, args);
    }

    this.mMethodListTemp.length = 0;
    this.mArgsListTemp.length = 0;
  }

  private dispatchOne(method: number, a: number[]): void {
    switch (method) {
      case GalleryView.METHOD_ON_SINGLE_TAP_UP:
        this.onSingleTapUpInternal(a[0], a[1]);
        break;
      case GalleryView.METHOD_ON_SINGLE_TAP_CONFIRMED:
        this.onSingleTapConfirmedInternal(a[0], a[1]);
        break;
      case GalleryView.METHOD_ON_DOUBLE_TAP:
        this.onDoubleTapInternal(a[0], a[1]);
        break;
      case GalleryView.METHOD_ON_DOUBLE_TAP_CONFIRMED:
        this.onDoubleTapConfirmedInternal(a[0], a[1]);
        break;
      case GalleryView.METHOD_ON_LONG_PRESS:
        this.onLongPressInternal(a[0], a[1]);
        break;
      case GalleryView.METHOD_ON_SCROLL:
        this.onScrollInternal(a[0], a[1], a[2], a[3], a[4], a[5]);
        break;
      case GalleryView.METHOD_ON_FLING:
        this.onFlingInternal(a[0], a[1]);
        break;
      case GalleryView.METHOD_ON_SCALE_BEGIN:
        this.onScaleBeginInternal(a[0], a[1]);
        break;
      case GalleryView.METHOD_ON_SCALE:
        this.onScaleInternal(a[0], a[1], a[2]);
        break;
      case GalleryView.METHOD_ON_SCALE_END:
        this.onScaleEndInternal();
        break;
      case GalleryView.METHOD_ON_DOWN:
        this.onDownInternal(a[0], a[1]);
        break;
      case GalleryView.METHOD_ON_UP:
        this.onUpInternal();
        break;
      case GalleryView.METHOD_ON_POINTER_DOWN:
        this.onPointerDownInternal(a[0], a[1]);
        break;
      case GalleryView.METHOD_ON_POINTER_UP:
        this.onPointerUpInternal();
        break;
      case GalleryView.METHOD_SET_LAYOUT_MODE:
        this.setLayoutModeInternal(Math.trunc(a[0]));
        break;
      case GalleryView.METHOD_SET_CURRENT_PAGE:
        this.setCurrentPageInternal(Math.trunc(a[0]));
        break;
      case GalleryView.METHOD_PAGE_LEFT:
        this.pageLeftInternal();
        break;
      case GalleryView.METHOD_PAGE_RIGHT:
        this.pageRightInternal();
        break;
      case GalleryView.METHOD_SET_SCALE_MODE:
        this.setScaleModeInternal(Math.trunc(a[0]));
        break;
      case GalleryView.METHOD_SET_START_POSITION:
        this.setStartPositionInternal(Math.trunc(a[0]));
        break;
      case GalleryView.METHOD_ON_ATTACH_TO_ROOT:
        this.onAttachToRootInternal();
        break;
      case GalleryView.METHOD_SET_PAGER_INTERVAL:
        this.setPagerIntervalInternal(Math.trunc(a[0]));
        break;
      case GalleryView.METHOD_SET_SCROLL_INTERVAL:
        this.setScrollIntervalInternal(Math.trunc(a[0]));
        break;
      default:
        hilog.warn(DOMAIN, TAG, 'unknown method op %{public}d', method);
        break;
    }
  }

  // ==========================================================================
  // 页面查找 / 池化
  // ==========================================================================

  findPageByIndex(index: number): GalleryPageView | null {
    const manager = this.mLayoutManager;
    return manager !== null ? manager.findPageByIndex(index) : null;
  }

  private findPageUnder(x: number, y: number): GalleryPageView | null {
    for (let i = 0, n = this.getComponentCount(); i < n; i++) {
      const view = this.getComponent(i);
      if (view instanceof GalleryPageView && view.bounds().contains(Math.trunc(x), Math.trunc(y))) {
        return view as GalleryPageView;
      }
    }
    return null;
  }

  obtainPage(): GalleryPageView {
    const page = this.mGalleryPageViewPool.pop() ?? null;
    if (page === null) {
      return new ConcreteGalleryPageView(this.mPageTextTexture, this.mProgressColor,
        this.mGalleryBgColor, this.mProgressSize, this.mPageMinHeight, this.mPageInfoInterval);
    }
    return page;
  }

  releasePage(page: GalleryPageView): void {
    this.mGalleryPageViewPool.push(page);
  }

  // ==========================================================================
  // 测试装配入口（M-01 最小可交付）
  //
  // ⚠️ **生产代码不得调用**。这 4 个入口只服务 Node 侧单测：
  //   `GalleryView` 的尺寸/`adapter`/管理器都来自 `layout()`+`setAdapter()`+工厂注入，
  //   单测里没有真实布局流程，必须能直接装配。
  //
  // 为什么不接口化生产类（`IGalleryView` + `FakeGalleryView`）：
  //   两个布局管理器都按**具体类**的 21 个方法调用；接口化要改两处生产签名，
  //   而这里的 4 个入口已能达到同样的可测性。**收益真实但不该现在付**（黑屏类缺陷更紧急）。
  // ==========================================================================

  /**
   * 诊断/单测：替换 adapter（生产走 `setAdapter()` 的 attach/池化流程）。
   * **生产代码不得调用。**
   */
  replaceAdapterForTest(adapter: GalleryAdapter | null): void {
    this.mAdapter = adapter;
  }

  /**
   * 诊断/单测：直接给尺寸（生产由 `layout()` 决定）。
   * **生产代码不得调用。**
   */
  setSizeForTest(width: number, height: number): void {
    this.layout(0, 0, width, height);
  }

  /**
   * 诊断/单测：触发 `attachLayoutManager()`。
   * 生产路径是 `onDetachFromRoot/onAttachToRoot` 经命令流 dispatch（`postMethod(METHOD_ON_ATTACH_TO_ROOT)`）；
   * 单测里没有 `GLRoot`，只能直接取这一行。
   *
   * 语义与生产**完全一致**（直接调同一个私有方法）：需要 `adapter` 非空 + 工厂已注入，
   * 成功后 `adapter` 的所有权移交管理器（`mAdapter = null`）—— 断言时要按这个事实写。
   * **生产代码不得调用。**
   */
  attachLayoutManagerForTest(): void {
    this.attachLayoutManager();
  }

  /**
   * 诊断/单测：状态快照（**不用反射** —— ArkTS 禁止 `constructor.name`）。
   * 格式固定，便于断言：`adapter=<bool> layout=<bool> pager=<bool> scroll=<bool> comps=<n>`。
   * **生产代码不得调用。**
   */
  debugSnapshot(): string {
    return `adapter=${this.mAdapter !== null} layout=${this.mLayoutManager !== null} `
      + `pager=${this.mPagerLayoutManager !== null} scroll=${this.mScrollLayoutManager !== null} `
      + `comps=${this.getComponentCount()}`;
  }

  /**
   * 诊断/单测：组件在容器里的位置（**按身份比较，不用类型反射**）。
   * @return 下标；不在容器里 `-1`
   *
   * 用途：断言**画序**（后加的在上层）—— 例如"页在下、错误视图在上"必须靠下标比较而非类型名。
   * **生产代码不得调用。**
   */
  componentIndexOfTest(view: GLView): number {
    const n = this.getComponentCount();
    for (let i = 0; i < n; i++) {
      if (this.getComponent(i) === view) {
        return i;
      }
    }
    return -1;
  }

  /** 不确定进度圈（池化一个实例）。 */
  obtainProgress(): GLProgressView {
    const cached = this.mProgressCache;
    if (cached !== null) {
      this.mProgressCache = null;
      return cached;
    }
    const progress = new GLProgressView();
    progress.setColor(this.mProgressColor);
    progress.setBgColor(this.mGalleryBgColor);
    progress.setIndeterminate(true);
    progress.setMinimumWidth(this.mProgressSize);
    progress.setMinimumHeight(this.mProgressSize);
    return progress;
  }

  releaseProgress(progress: GLProgressView): void {
    this.mProgressCache = progress;
  }

  obtainErrorView(): GLTextureView {
    const cached = this.mErrorViewCache;
    if (cached !== null) {
      this.mErrorViewCache = null;
      return cached;
    }
    return new GLTextureView();
  }

  unbindErrorView(errorView: GLTextureView): void {
    const texture: Texture | null = errorView.getTexture();
    if (texture !== null) {
      errorView.setTexture(null);
      if (texture instanceof BasicTexture) {
        (texture as BasicTexture).recycle();
      }
    }
  }

  /**
   * 绑定错误文案。
   *
   * 上游直接 `StringTexture.newInstance(error, size, color)`；本项目该签名多了两个注入项
   * （文字测量工厂 + 离屏画布，见 `CanvasTexture` 的接缝说明），而**这两个实现目前不存在**。
   * 所以这里做成可注入：`setTextRendering(factory, offscreen)` 由 ui 层/native-image 提供；
   * 未注入时**只记 warn 并保持错误区为空**（不抛错 —— 错误文案缺失不该让画廊崩）。
   */
  bindErrorView(errorView: GLTextureView, error: string): void {
    this.unbindErrorView(errorView);
    const factory = GalleryView.sTextPaintFactory;
    const offscreen = GalleryView.sOffscreenCanvas;
    if (factory === null || offscreen === null) {
      hilog.warn(DOMAIN, TAG,
        'StringTexture seam not injected, error text dropped: %{public}s', error);
      return;
    }
    const texture: Texture = StringTexture.newInstance(error, this.mErrorTextSize,
      this.mErrorTextColor, factory, offscreen);
    errorView.setTexture(texture);
  }

  releaseErrorView(errorView: GLTextureView): void {
    this.unbindErrorView(errorView);
    this.mErrorViewCache = errorView;
  }

  onTransferEnd(): void {
    const listener = this.mListener;
    if (listener === null) {
      return;
    }
    listener.onAutoTransferDone();
  }
}

/**
 * `GalleryPageView` 是抽象类（保留给外部特化），但 `GalleryView` 需要能实例化它。
 * 上游直接 `new GalleryPageView(...)`；ArkTS 里抽象类不可实例化，
 * 所以给出这个最小具体子类（不覆写任何行为）。
 */
class ConcreteGalleryPageView extends GalleryPageView {
  constructor(pageTextTexture: ImageMovableTextTexture | null, progressColor: number,
    progressBgColor: number, progressSize: number, minHeight: number, infoInterval: number) {
    super(pageTextTexture, progressColor, progressBgColor, progressSize, minHeight, infoInterval);
  }
}
