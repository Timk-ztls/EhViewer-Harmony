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
import { MathUtils } from '../yorozuya/MathUtils';
import { AnimationUtils } from '../yorozuya/AnimationUtils';
import { Animation } from '../glview/anim/Animation';
import { FloatAnimation } from '../glview/anim/FloatAnimation';
import { GLViewMeasureSpec, GLViewLayoutParams } from '../glview/view/GLView';
import { GLEdgeView } from '../glview/widget/GLEdgeView';
import { GLProgressView } from '../glview/widget/GLProgressView';
import { GLTextureView } from '../glview/widget/GLTextureView';
import { Fling } from './Fling';
import { GalleryProvider } from './GalleryProvider';
import { GalleryPageView } from './GalleryPageView';
import { GalleryAdapter, GalleryLayoutManager, GalleryView } from './GalleryView';
import { ImageView } from './ImageView';
import { bottomLimit, canScrollUp, reservation, topLimit } from './ScrollLayoutCore';

const TAG = 'ScrollLayoutManager';
const DOMAIN = 0x0000;

/**
 * `com.hippo.lib.glgallery.ScrollLayoutManager` 的 ArkTS 等价实现（1095 行）。
 *
 * 纵向连续滚动的布局管理器：页面按 `[mOffsetY + Σ(高度 + interval)]` 纵向排布，
 * 支持双指缩放（页宽 = `width * mScale`）、惯性滑动（`PageFling`）、边界回弹（`OverScroller`）。
 *
 * ## 与 `ScrollLayoutCore` 的关系（Lead 判据：不为复用而变形上游）
 * `ScrollLayoutCore` 提供 6 个纯函数 + 3 个值对象（net-parse 的 44 条断言）。
 * 本文件**能用则用**，但对不上的地方**整段保留上游形状并注明原因**：
 * | 位置 | 是否用 Core | 原因 |
 * |---|---|---|
 * | `scrollInternal` 横向 clamp | **用** `MathUtils.clamp`（Core 的 `scrollHorizontal` 返回值对象，形状多一层） | 语义完全相同，直接 clamp 更贴近上游 |
 * | `scrollInternal` 双向钳制 + 逐像素推进 | **不用** | `forceFill()` 与 `mOffsetY` 的相互依赖是「循环内改状态再重排」，
 *   Core 的 `tryScrollY` 是纯函数（一次推进），套进来会把 `forceFill` 折成立即重排 → **改变帧内行为** |
 * | `getBottomState` | **不用** | 上游这里只算 `bottom`/`hasNext` 两个状态字段；limit 的修正（`min(bottom, limit)`）在 `scrollInternal` 里，拆开更清楚 |
 * | `topLimit` / `bottomLimit` / `canScrollUp` / `reservation` | **用**（审计 V-03 裁定 a） | 只借用**判定与 limit 值**，`forceFill`/`requestFill`/`overScrollEdge`/`mDelta*` 全部留在本类 → **帧内行为零变化** |
 * | `clampUp` / `tryScrollY` | **不用** | 它们把"被挡住之后的处理"也一起返回；本类的 `while` 循环要在处理中调 `forceFill()` 再进下一轮，控制流必须留在本类 |
 *
 * ## ⚠️ 三个「注释里已给出原因，绝不能改」的地方（Lead 陷阱库）
 * 1. **`obtainPage()` 强制 `START_POSITION_TOP_RIGHT`**：滚动模式页宽 = `width * mScale`
 *    （初始 `mScale = 0.5`），页比屏幕窄，靠右对齐才与翻页模式的视觉中心一致。
 *    改成 `CENTER` 会让横向位置偏移半页。
 * 2. **`scrollInternal` 的 「±1 像素偏移 + `forceFill()`」**：上游注释
 *    `Offset one pixel to avoid infinite loop` ——
 *    **这不是防御性代码，是 `while (remainY != 0)` 的终止条件的一部分**。删掉会死循环。
 * 3. **`fillPages` 的三处修补**：顶部补空（首屏可见页 `top > 0` 时整体上移）、
 *    底部补空（末页可见高度不足时**从顶部拉页并把已有页整体下移**）、末尾 `mIndex`/`mOffsetY` 回写。
 *    省任一处 → 短页/末页出现空白或跳位。
 */
export class ScrollLayoutManager extends GalleryLayoutManager {
  /** 预排版倍率（上游 `RESERVATION = 1f`）：上下各多排一屏。 */
  private static readonly RESERVATION: number = 1.0;
  private static readonly MAX_SCALE: number = 2.0;
  private static readonly MIN_SCALE: number = 1.0;
  private static readonly SCALE_ERROR: number = 0.01;
  /** 「无 keepTop」哨兵（上游 `INVALID_TOP = Integer.MAX_VALUE`）。 */
  private static readonly INVALID_TOP: number = 2147483647;

  private mAdapter: GalleryAdapter | null = null;

  private mProgress: GLProgressView | null = null;
  private mErrorStr: string | null = null;
  private mErrorView: GLTextureView | null = null;

  private mPages: GalleryPageView[] = [];
  private mTempPages: GalleryPageView[] = [];

  private mScale: number = 0.5;
  private mOffsetX: number = 0;
  private mOffsetY: number = 0;
  private mDeltaX: number = 0;
  private mDeltaY: number = 0;

  private mKeepTopPageIndex: number = GalleryPageView.INVALID_INDEX;
  private mKeepTop: number = ScrollLayoutManager.INVALID_TOP;
  private mFirstShownPageIndex: number = GalleryPageView.INVALID_INDEX;

  private mScrollUp: boolean = false;
  private mFlingUp: boolean = false;
  private mStopAnimationFinger: boolean = false;

  private mInterval: number;

  private readonly mPageFling: ScrollPageFling;
  private readonly mSmoothScaler: ScrollSmoothScaler;
  private readonly mOverScroller: ScrollOverScroller;

  private mIndex: number = 0;
  private mBottomStateBottom: number = 0;
  private mBottomStateHasNext: boolean = false;

  constructor(galleryView: GalleryView, interval: number) {
    super(galleryView);
    this.mInterval = interval;
    this.mPageFling = new ScrollPageFling(this, galleryView);
    this.mSmoothScaler = new ScrollSmoothScaler(this, galleryView);
    this.mOverScroller = new ScrollOverScroller(this, galleryView);
  }

  setInterval(interval: number): void {
    if (this.mInterval === interval) {
      return;
    }
    if (this.mAdapter !== null) {
      const index = this.getInternalCurrentIndex();
      const adapter = this.onDetach();
      this.mInterval = interval;
      this.onAttach(adapter);
      this.setCurrentIndex(index);
      this.mGalleryView.requestFill();
    } else {
      this.mInterval = interval;
    }
  }

  override setPageInterval(interval: number): void {
    this.setInterval(interval);
  }

  private resetParameters(): void {
    this.mScale = 1.0;
    this.mOffsetX = 0;
    this.mOffsetY = 0;
    this.mDeltaX = 0;
    this.mDeltaY = 0;
    this.mKeepTopPageIndex = GalleryPageView.INVALID_INDEX;
    this.mKeepTop = ScrollLayoutManager.INVALID_TOP;
    this.mFirstShownPageIndex = GalleryPageView.INVALID_INDEX;
    this.mScrollUp = false;
    this.mFlingUp = false;
    this.mStopAnimationFinger = false;
  }

  /** @return 是否有动画在跑（上游同名方法的返回值被 `cancelAllAnimations()` 的调用者忽略） */
  private cancelAllAnimations(): boolean {
    const running = this.mPageFling.isRunning() || this.mSmoothScaler.isRunning()
      || this.mOverScroller.isRunning();
    this.mPageFling.cancel();
    this.mSmoothScaler.cancel();
    this.mOverScroller.cancel();
    return running;
  }

  onAttach(adapter: GalleryAdapter): void {
    if (this.mAdapter !== null) {
      hilog.error(DOMAIN, TAG, 'onAttach: already attached');
    }
    if (adapter === null) {
      hilog.error(DOMAIN, TAG, 'onAttach: adapter is null');
      return;
    }
    this.mAdapter = adapter;
    this.resetParameters();
  }

  private removeProgress(): void {
    const progress = this.mProgress;
    if (progress !== null) {
      this.mGalleryView.removeComponent(progress);
      this.mGalleryView.releaseProgress(progress);
      this.mProgress = null;
    }
  }

  private removeErrorView(): void {
    const errorView = this.mErrorView;
    if (errorView !== null) {
      this.mGalleryView.removeComponent(errorView);
      this.mGalleryView.releaseErrorView(errorView);
      this.mErrorView = null;
      this.mErrorStr = null;
    }
  }

  private removePage(page: GalleryPageView): void {
    this.mGalleryView.removeComponent(page);
    const adapter = this.mAdapter;
    if (adapter !== null) {
      adapter.unbind(page);
    }
    this.mGalleryView.releasePage(page);
  }

  private removeAllPages(): void {
    for (let i = 0; i < this.mPages.length; i++) {
      this.removePage(this.mPages[i]);
    }
    this.mPages.length = 0;
  }

  onDetach(): GalleryAdapter {
    const adapter = this.mAdapter;
    if (adapter === null) {
      // 上游 `AssertUtils.assertNotNull("The PagerLayoutManager is not attached", mAdapter)`
      throw new Error('The ScrollLayoutManager is not attached');
    }

    this.cancelAllAnimations();
    this.removeProgress();
    this.removeErrorView();
    this.removeAllPages();

    this.mAdapter = null;
    return adapter;
  }

  private obtainPage(): GalleryPageView {
    const page = this.mGalleryView.obtainPage();
    // ★ 见类注释第 1 条：不是 typo，滚动模式页窄，靠右对齐才与翻页模式视觉中心一致
    page.getImageView().setScaleOffset(ImageView.SCALE_FIT,
      ImageView.START_POSITION_TOP_RIGHT, 1.0);
    return page;
  }

  /**
   * 从列表里找指定索引的页（`remove = true` 时**同时移出列表**）。
   * 上游用 `iterator.remove()`；ArkTS 用 `splice`。
   */
  private getPageForIndex(pages: GalleryPageView[], index: number,
    remove: boolean): GalleryPageView | null {
    const pos = ScrollLayoutManager.indexOfPage(pages, index);
    if (pos < 0) {
      return null;
    }
    const page = pages[pos];
    if (remove) {
      pages.splice(pos, 1);
    }
    return page;
  }

  /**
   * 在页列表里找 `index` 的位置。
   * @return 位置；未找到 `-1`
   *
   * 提为 `static` 以便断言"不存在时**不改动集合**"这条移除语义的真判据。
   */
  static indexOfPage(pages: GalleryPageView[], index: number): number {
    for (let i = 0; i < pages.length; i++) {
      if (pages[i].getIndex() === index) {
        return i;
      }
    }
    return -1;
  }

  /**
   * 页与屏幕相交的**判定本体**（三种情况，上游逐字）：
   * 1. 页顶在屏内（`0 <= top < height`）
   * 2. 页底在屏内（`0 < bottom <= height`）
   * 3. 页完全覆盖屏幕（`top < 0 && bottom > height`）
   *
   * 提为 `static` 是为了能在 Node 里逐条断言（三个条件各自都能单独让结果变 false）；
   * 实例方法只是把 `page.bounds()` 拆开传进来。
   */
  static isInScreenRect(pageTop: number, pageBottom: number, viewHeight: number): boolean {
    return (pageTop >= 0 && pageTop < viewHeight)
      || (pageBottom > 0 && pageBottom <= viewHeight)
      || (pageTop < 0 && pageBottom > viewHeight);
  }

  /** 页与屏幕相交（委托 `isInScreenRect`）。 */
  private isInScreen(page: GalleryPageView): boolean {
    const bound: Rect = page.bounds();
    return ScrollLayoutManager.isInScreenRect(bound.top, bound.bottom,
      this.mGalleryView.getHeight());
  }

  /**
   * 预排版区（随缩放增大：页越窄，越要预留更多纵向内容）。
   * **公式唯一来源 = `ScrollLayoutCore.reservation()`**（审计 V-01：初版把 `RESERVATION` 当成
   * 预留倍率本身、漏掉外层 `getReservation()`，`mScale=2` 时少留 1.5 屏；net-parse 已在 Core 修，两边共用）。
   */
  private getReservation(): number {
    return reservation(this.mScale);
  }

  /**
   * 从 `(startIndex, startOffset)` 起重排可见页 + 预排版页（**190 行，本类最核心**）。
   *
   * 步骤（顺序不能换）：
   * 1. 修正起点的索引/偏移（越界、超出预排版区）
   * 2. 把当前页搬到 `mTempPages`，清空 `mPages`（复用旧页）
   * 3. 横向偏移 clamp（页宽 vs 屏宽）
   * 4. 排起始页 → 向上补（`addFirst`）→ 顶部防空白 → 向下补（`addLast`）→ 底部防空白
   * 5. 移除没被复用的页、回写 `mIndex`/`mOffsetY`
   */
  private fillPages(startIndex: number, startOffset: number): void {
    const adapter = this.mAdapter;
    if (adapter === null) {
      return;
    }
    const galleryView = this.mGalleryView;
    const pages = this.mPages;
    const tempPages = this.mTempPages;
    const width = galleryView.getWidth();
    const height = galleryView.getHeight();
    const pageWidth = Math.trunc(width * this.mScale);
    const size = adapter.size();
    const interval = this.mInterval;
    const reservation = this.getReservation();
    const minY = Math.trunc(-height * reservation);
    const maxY = Math.trunc(height * (1 + reservation));
    const widthSpec = GLViewMeasureSpec.makeMeasureSpec(pageWidth, GLViewMeasureSpec.EXACTLY);
    const heightSpec = GLViewMeasureSpec.makeMeasureSpec(height, GLViewMeasureSpec.UNSPECIFIED);

    // ---- 1) Fix start index and start offset ----
    if (startIndex < 0) {
      startIndex = 0;
      startOffset = 0;
    } else if (startIndex >= size) {
      startIndex = size - 1;
      startOffset = 0;
    } else if (startOffset < minY) {
      // 起点在预排版区之上：向下找，直到页底进入 minY
      while (true) {
        const page = this.getPageForIndex(pages, startIndex, false);
        if (page === null) {
          startOffset = minY;
          break;
        }
        page.measure(widthSpec, heightSpec);
        if (startOffset + page.getHeight() > minY) {
          break;
        } else if (size - 1 === startIndex) {
          startOffset = 0;
          break;
        } else {
          startIndex++;
          startOffset += page.getHeight() + interval;
          if (startOffset >= minY) {
            break;
          }
        }
      }
    } else if (startOffset >= maxY) {
      // 起点在预排版区之下：向上找
      if (0 === startIndex) {
        startOffset = 0;
      } else {
        startIndex--;
        let startBottomOffset = startOffset - interval;
        while (true) {
          const page = this.getPageForIndex(pages, startIndex, false);
          if (page === null) {
            startOffset = maxY - 1;
            break;
          }
          page.measure(widthSpec, heightSpec);
          startOffset = startBottomOffset - page.getHeight();
          if (startOffset < maxY) {
            break;
          } else if (0 === startIndex) {
            startOffset = 0;
            break;
          } else {
            startIndex--;
            startBottomOffset = startOffset - interval;
          }
        }
      }
    }

    // ---- 2) Put page to temp list ----
    for (let i = 0; i < pages.length; i++) {
      tempPages.push(pages[i]);
    }
    pages.length = 0;

    // ---- 3) Sanitize offsetX ----
    const margin = pageWidth - width;
    if (margin >= 0) {
      this.mOffsetX = MathUtils.clamp(this.mOffsetX, -margin, 0);
    } else {
      this.mOffsetX = Math.trunc(-margin / 2);
    }

    // ---- 4a) Layout start page ----
    let page = this.getPageForIndex(tempPages, startIndex, true);
    if (page === null) {
      page = this.obtainPage();
      galleryView.addComponent(page);
      adapter.bind(page, startIndex);
    }
    pages.push(page);
    page.measure(widthSpec, heightSpec);
    page.layout(this.mOffsetX, startOffset, this.mOffsetX + pageWidth,
      startOffset + page.getMeasuredHeight());

    // ---- 4b) Check up ----
    let bottomOffset = startOffset - interval;
    let topOffset = startOffset + page.getMeasuredHeight() + interval;

    let index = startIndex - 1;
    while (bottomOffset > minY && index >= 0) {
      let upPage = this.getPageForIndex(tempPages, index, true);
      if (upPage === null) {
        upPage = this.obtainPage();
        galleryView.addComponent(upPage);
        adapter.bind(upPage, index);
      }
      pages.unshift(upPage);
      upPage.measure(widthSpec, heightSpec);
      upPage.layout(this.mOffsetX, bottomOffset - upPage.getMeasuredHeight(),
        this.mOffsetX + pageWidth, bottomOffset);
      bottomOffset -= upPage.getMeasuredHeight() + interval;
      index--;
    }

    // ---- 4c) Avoid space in top（首屏第一页顶部留白 → 整体上移）----
    page = pages[0];
    if (0 === page.getIndex() && page.bounds().top > 0) {
      const offset = -page.bounds().top;
      for (let i = 0; i < pages.length; i++) {
        pages[i].offsetTopAndBottom(offset);
      }
      topOffset += offset;
    }

    // ---- 4d) Check down ----
    index = startIndex + 1;
    while (topOffset < maxY && index < size) {
      let downPage = this.getPageForIndex(tempPages, index, true);
      if (downPage === null) {
        downPage = this.obtainPage();
        galleryView.addComponent(downPage);
        adapter.bind(downPage, index);
      }
      pages.push(downPage);
      downPage.measure(widthSpec, heightSpec);
      downPage.layout(this.mOffsetX, topOffset, this.mOffsetX + pageWidth,
        topOffset + downPage.getMeasuredHeight());
      topOffset += downPage.getMeasuredHeight() + interval;
      index++;
    }

    // ---- 4e) Avoid space in bottom（末页可见高度不足 → 从顶部拉页并整体下移）----
    if (size - 1 === pages[pages.length - 1].getIndex()) {
      while (true) {
        let last = pages[pages.length - 1];
        const pagesBottom = last.bounds().bottom;
        if (pagesBottom >= height) {
          break;
        }
        last = pages[0];
        let firstIndex = last.getIndex();
        if (0 === firstIndex) {
          break;
        }
        firstIndex--;
        const pagesTop = last.bounds().top;

        let pullPage = this.getPageForIndex(tempPages, firstIndex, true);
        if (pullPage === null) {
          pullPage = this.obtainPage();
          galleryView.addComponent(pullPage);
          adapter.bind(pullPage, firstIndex);
        }
        pages.unshift(pullPage);
        pullPage.measure(widthSpec, heightSpec);

        const offset = Math.min(height - pagesBottom, pullPage.getMeasuredHeight());
        for (let i = 0; i < pages.length; i++) {
          pages[i].offsetTopAndBottom(offset);
        }
        const bottom = pagesTop - interval + offset;
        pullPage.layout(this.mOffsetX, bottom - pullPage.getMeasuredHeight(),
          this.mOffsetX + pageWidth, bottom);
      }
    }

    // ---- 5) Remove remain page ----
    for (let i = 0; i < tempPages.length; i++) {
      this.removePage(tempPages[i]);
    }
    tempPages.length = 0;

    // ---- Update state ----
    if (pages.length > 0) {
      page = pages[0];
      this.mIndex = page.getIndex();
      this.mOffsetY = page.bounds().top;
    }
  }
// ==========================================================================
  // onFill：三态（等待 / 错误或空 / 正常）
  // ==========================================================================

  onFill(): void {
    const adapter = this.mAdapter;
    if (adapter === null) {
      // 上游 `AssertUtils.assertNotNull("The PagerLayoutManager is not attached", adapter)`
      throw new Error('The ScrollLayoutManager is not attached');
    }
    const galleryView = this.mGalleryView;
    const size = adapter.size();
    let errorStr = adapter.getError();

    if (size === GalleryProvider.STATE_WAIT) {
      // 等待数据：显示转圈
      this.removeErrorView();
      this.removeAllPages();
      if (this.mProgress === null) {
        this.mProgress = galleryView.obtainProgress();
        galleryView.addComponent(this.mProgress);
      }
      this.placeCenter(this.mProgress);
      return;
    }

    if (size <= GalleryProvider.STATE_ERROR || size === 0) {
      // 错误或空：显示错误文案
      if (0 === size) {
        errorStr = galleryView.getEmptyStr();
      } else if (errorStr === null) {
        errorStr = galleryView.getDefaultErrorStr();
      }
      this.removeProgress();
      this.removeAllPages();
      if (this.mErrorView === null) {
        this.mErrorView = galleryView.obtainErrorView();
        galleryView.addComponent(this.mErrorView);
      }
      if (errorStr !== this.mErrorStr) {
        this.mErrorStr = errorStr;
        galleryView.bindErrorView(this.mErrorView, errorStr);
      }
      this.placeCenter(this.mErrorView);
      return;
    }

    // ---- 正常：排页 ----
    const pages = this.mPages;
    this.removeProgress();
    this.removeErrorView();

    // Ensure index in range
    let index = this.mIndex;
    if (index < 0) {
      hilog.error(DOMAIN, TAG, 'index < 0, index = %{public}d', index);
      index = 0;
      this.mIndex = index;
      this.removeAllPages();
    } else if (index >= size) {
      hilog.error(DOMAIN, TAG, 'index >= size, index = %{public}d, size = %{public}d', index, size);
      index = size - 1;
      this.mIndex = index;
      this.removeAllPages();
    }

    // Find keep index and keep top
    let keepTop = ScrollLayoutManager.INVALID_TOP;
    let keepTopIndex: number;
    if (GalleryPageView.INVALID_INDEX !== this.mKeepTopPageIndex) {
      keepTopIndex = this.mKeepTopPageIndex;
      keepTop = this.mKeepTop;
    } else if (GalleryPageView.INVALID_INDEX !== this.mFirstShownPageIndex) {
      keepTopIndex = this.mFirstShownPageIndex;
    } else {
      keepTopIndex = GalleryPageView.INVALID_INDEX;
    }
    if (GalleryPageView.INVALID_INDEX !== keepTopIndex
      && ScrollLayoutManager.INVALID_TOP === keepTop) {
      // 用第一页的 top 累加，推出目标页的 top
      keepTop = this.mOffsetY;
      for (let i = 0; i < pages.length; i++) {
        if (keepTopIndex === pages[i].getIndex()) {
          break;
        }
        keepTop += pages[i].getHeight() + this.mInterval;
      }
    }

    let startIndex: number;
    let startOffset: number;
    if (GalleryPageView.INVALID_INDEX !== keepTopIndex) {
      startIndex = keepTopIndex;
      startOffset = keepTop;
    } else {
      startIndex = this.mIndex;
      startOffset = this.mOffsetY;
    }
    this.fillPages(startIndex, startOffset);

    // Get first shown image
    this.mFirstShownPageIndex = GalleryPageView.INVALID_INDEX;
    for (let i = 0; i < this.mPages.length; i++) {
      const page = this.mPages[i];
      // 向上滑/上抛时，跳过还没加载出来的页（否则会把"上一页的角"当成当前页）
      if ((this.mScrollUp || this.mFlingUp) && !page.isLoaded()) {
        continue;
      }
      if (this.isInScreen(page)) {
        this.mFirstShownPageIndex = page.getIndex();
        this.mKeepTopPageIndex = page.getIndex();
        break;
      }
    }
  }

  // ==========================================================================
  // 手势回调
  // ==========================================================================

  onDown(): void {
    this.mDeltaX = 0;
    this.mDeltaY = 0;
    this.mScrollUp = false;
    this.mFlingUp = false;
    this.mStopAnimationFinger = this.cancelAllAnimations();
    this.mKeepTopPageIndex = GalleryPageView.INVALID_INDEX;
    this.mKeepTop = ScrollLayoutManager.INVALID_TOP;
  }

  onUp(): void {
    this.mStopAnimationFinger = false;
  }

  onDoubleTapConfirmed(x: number, y: number): void {
    if (this.mPages.length === 0) {
      return;
    }
    let targetScale = this.mScale;
    if (this.mScale < ScrollLayoutManager.MAX_SCALE - ScrollLayoutManager.SCALE_ERROR) {
      targetScale = ScrollLayoutManager.MAX_SCALE;
    } else if (this.mScale > ScrollLayoutManager.MIN_SCALE + ScrollLayoutManager.SCALE_ERROR) {
      targetScale = ScrollLayoutManager.MIN_SCALE;
    } else {
      return;
    }
    // 上游时长 = 300 * |目标/当前 - 1|（缩放幅度越大越慢）
    const duration = Math.trunc(300
      * Math.abs(targetScale / this.mScale - 1));
    this.mSmoothScaler.startSmoothScaler(x, y, this.mScale, targetScale, duration);
  }

  onLongPress(x: number, y: number): void {
    // 上游空实现（长按在 `GalleryView` 里已转成 `Listener.onLongPressPage`）
  }

  // ==========================================================================
  // 边缘效果
  // ==========================================================================

  overScrollEdge(dx: number, dy: number, x: number, y: number): void {
    const edgeView = this.mGalleryView.getEdgeView();

    this.mDeltaX += dx;
    this.mDeltaY += dy;

    if (this.mDeltaX < 0) {
      edgeView.onPull(-this.mDeltaX, y, GLEdgeView.LEFT);
      if (!edgeView.isFinished(GLEdgeView.RIGHT)) {
        edgeView.onRelease(GLEdgeView.RIGHT);
      }
    } else if (this.mDeltaX > 0) {
      edgeView.onPull(this.mDeltaX, y, GLEdgeView.RIGHT);
      if (!edgeView.isFinished(GLEdgeView.LEFT)) {
        edgeView.onRelease(GLEdgeView.LEFT);
      }
    }

    if (this.mDeltaY < 0) {
      edgeView.onPull(-this.mDeltaY, x, GLEdgeView.TOP);
      if (!edgeView.isFinished(GLEdgeView.BOTTOM)) {
        edgeView.onRelease(GLEdgeView.BOTTOM);
      }
    } else if (this.mDeltaY > 0) {
      edgeView.onPull(this.mDeltaY, x, GLEdgeView.BOTTOM);
      if (!edgeView.isFinished(GLEdgeView.TOP)) {
        edgeView.onRelease(GLEdgeView.TOP);
      }
    }
  }

  /**
   * `bottom` 的累加规则（上游 `getBottomState` 的循环）：从 `startTop` 起，
   * **每页之间加 `interval`**（不是"页数 × (高 + interval)"），最后得到末页底边。
   *
   * 提为 `static` 以便断言"空集合 / 单页 / 多页部分可见"三种情况。
   */
  static computeBottom(heights: number[], startTop: number, interval: number): number {
    let bottom = startTop;
    for (let i = 0; i < heights.length; i++) {
      if (i !== 0) {
        bottom += interval;
      }
      bottom += heights[i];
    }
    return bottom;
  }

  /** 底部状态：所有已排页累加出的 `bottom`，以及"后面还有没有页"。 */
  private getBottomState(): void {
    const pages = this.mPages;
    const heights: number[] = [];
    for (let i = 0; i < pages.length; i++) {
      heights.push(pages[i].getHeight());
    }
    const bottom = ScrollLayoutManager.computeBottom(heights, this.mOffsetY, this.mInterval);
    const adapter = this.mAdapter;
    const size = adapter === null ? 0 : adapter.size();
    this.mBottomStateBottom = bottom;
    this.mBottomStateHasNext = this.mIndex + pages.length < size;
  }

  // ==========================================================================
  // 滚动核心
  // ==========================================================================

  /**
   * 滚动（**本类最难的一段**）。`limit` 与"能否容纳"的**判定**来自 `ScrollLayoutCore`（审计 V-03 裁定 a），
   * 但**控制流全在本类**：`forceFill()` / `requestFill()` / `overScrollEdge()` / `mDeltaX·mDeltaY` 的
   * 调用时机与顺序一行未动 —— 这是"不把控制流交给 Core"的边界（见类注释表）。
   *
   * @return true 表示"撞到边界且已展示边缘效果"（`PageFling` 据此 `cancel()` 自己）
   */
  private scrollInternal(dx: number, dy: number, fling: boolean, x: number, y: number): boolean {
    if (this.mPages.length <= 0) {
      return false;
    }

    const galleryView = this.mGalleryView;
    const width = galleryView.getWidth();
    const height = galleryView.getHeight();
    const pageWidth = Math.trunc(width * this.mScale);
    const reservation = this.getReservation();
    let requestFill = false;
    let result = false;

    // ---- 横向 ----
    const margin = pageWidth - width;
    const dxInt = Math.trunc(dx);
    if (margin > 0 && 0 !== dxInt) {
      const oldOffsetX = this.mOffsetX;
      const exceptOffsetX = oldOffsetX - dxInt;
      this.mOffsetX = MathUtils.clamp(exceptOffsetX, -margin, 0);
      if (this.mOffsetX !== oldOffsetX) {
        requestFill = true;
      }
      // 左右不做 over scroll（上游把这段注释掉了）
    }

    // ---- 纵向：逐像素推进（循环内改状态再重排） ----
    let remainY = Math.trunc(dy);
    while (remainY !== 0) {
      if (remainY < 0) {
        // 想露出上面的内容
        // limit 与判定都走 Core（控制流一律不动，见类注释表）
        const limit: number = topLimit(this.mIndex, height, this.mInterval, reservation);

        if (canScrollUp(this.mOffsetY, remainY, limit)) {
          this.mOffsetY -= remainY;
          remainY = 0;
          requestFill = true;
          this.mDeltaX = 0;
          this.mDeltaY = 0;
        } else {
          if (this.mIndex > 0) {
            this.mOffsetY = limit;
            remainY = remainY + limit - this.mOffsetY;
            // ★ 上游注释 `Offset one pixel to avoid infinite loop`：
            //   这不是防御代码，是 while (remainY != 0) 的终止条件的一部分
            this.mOffsetY++;
            remainY++;
            galleryView.forceFill();
            requestFill = false;
            this.mDeltaX = 0;
            this.mDeltaY = 0;
          } else {
            if (this.mOffsetY !== limit) {
              this.mOffsetY = limit;
              requestFill = true;
            }
            if (!fling) {
              this.overScrollEdge(0, remainY + limit - this.mOffsetY, x, y);
            }
            remainY = 0;
            result = true;
          }
        }
      } else {
        // 想露出下面的内容
        this.getBottomState();
        const bottom = this.mBottomStateBottom;
        const hasNext = this.mBottomStateHasNext;

        // limit（含"页没铺满"的 min 修正）与判定都走 Core
        const limit: number = bottomLimit(hasNext, height, this.mInterval, bottom, reservation);

        // 向下判定按上游原样内联（Core 只提供 `canScrollUp`；不为这一行去改他的文件）
        if (bottom - remainY >= limit) {
          this.mOffsetY -= remainY;
          remainY = 0;
          requestFill = true;
          this.mDeltaX = 0;
          this.mDeltaY = 0;
        } else {
          if (hasNext) {
            this.mOffsetY -= bottom - limit;
            remainY = remainY + limit - bottom;
            // ★ 同上：±1 像素是终止条件的一部分
            this.mOffsetY--;
            remainY--;
            galleryView.forceFill();
            requestFill = false;
            this.mDeltaX = 0;
            this.mDeltaY = 0;
          } else {
            if (this.mOffsetY !== limit) {
              this.mOffsetY -= bottom - limit;
              requestFill = true;
            }
            if (!fling) {
              this.overScrollEdge(0, remainY + limit - bottom, x, y);
            }
            remainY = 0;
            result = true;
          }
        }
      }
    }

    if (requestFill) {
      this.mGalleryView.requestFill();
    }

    return result;
  }

  onScroll(dx: number, dy: number, totalX: number, totalY: number, x: number, y: number): void {
    this.mKeepTopPageIndex = GalleryPageView.INVALID_INDEX;
    this.mKeepTop = ScrollLayoutManager.INVALID_TOP;
    this.mScrollUp = dy < 0;
    this.scrollInternal(dx, dy, false, x, y);
  }

  onFling(velocityX: number, velocityY: number): void {
    if (this.mPages.length <= 0) {
      return;
    }

    this.mKeepTopPageIndex = GalleryPageView.INVALID_INDEX;
    this.mKeepTop = ScrollLayoutManager.INVALID_TOP;
    this.mFlingUp = velocityY > 0;

    const width = this.mGalleryView.getWidth();
    const pageWidth = Math.trunc(width * this.mScale);
    const margin = pageWidth - width;

    let maxX: number;
    let minX: number;
    if (margin > 0) {
      maxX = -this.mOffsetX;
      minX = -margin + this.mOffsetX;
    } else {
      maxX = 0;
      minX = 0;
    }

    let maxY: number;
    if (this.mIndex > 0) {
      maxY = Number.MAX_SAFE_INTEGER;
    } else {
      maxY = -this.mOffsetY;
    }

    this.getBottomState();
    const bottom = this.mBottomStateBottom;
    const hasNext = this.mBottomStateHasNext;

    let minY: number;
    if (hasNext) {
      minY = -Number.MAX_SAFE_INTEGER;
    } else {
      minY = this.mGalleryView.getHeight() - bottom;
    }

    this.mPageFling.startFling(Math.trunc(velocityX), minX, maxX, Math.trunc(velocityY), minY,
      maxY);
  }

  canScale(): boolean {
    return this.mPages.length > 0;
  }

  /**
   * 缩放：以 `focusX/focusY` 为锚点等比缩放，并保持"焦点上方那一页"的 top 位置。
   */
  onScale(focusX: number, focusY: number, scale: number): void {
    if (this.mPages.length === 0) {
      return;
    }

    const oldScale = this.mScale;
    this.mScale = MathUtils.clamp(oldScale * scale, ScrollLayoutManager.MIN_SCALE,
      ScrollLayoutManager.MAX_SCALE);
    scale = this.mScale / oldScale;

    if (oldScale === this.mScale) {
      return;
    }

    // 找焦点上方最后一页（其 top < focusY）
    let page: GalleryPageView | null = null;
    for (let i = 0; i < this.mPages.length; i++) {
      const p = this.mPages[i];
      if (p.bounds().top < focusY) {
        page = p;
      } else {
        break;
      }
    }

    if (page !== null) {
      this.mKeepTopPageIndex = page.getIndex();
      this.mKeepTop = page.bounds().top;

      this.mGalleryView.forceFill();
      const oldKeepTop = this.mKeepTop;
      this.mKeepTop = ScrollLayoutManager.INVALID_TOP;

      // 应用滚动：让焦点处的页内相对位置保持不变
      const newOffsetX = Math.trunc(focusX - ((focusX - this.mOffsetX) * scale));
      let newKeepTop: number;
      if (page.isLoaded()) {
        newKeepTop = Math.trunc(focusY - ((focusY - oldKeepTop) * scale));
      } else {
        newKeepTop = oldKeepTop;
      }
      this.scrollInternal(this.mOffsetX - newOffsetX, oldKeepTop - newKeepTop, false, focusX,
        focusY);
    } else {
      hilog.error(DOMAIN, TAG, 'Can\'t find target page');
      this.mKeepTopPageIndex = GalleryPageView.INVALID_INDEX;
      this.mKeepTop = ScrollLayoutManager.INVALID_TOP;
      this.mGalleryView.forceFill();
    }
  }

  onUpdateAnimation(time: number): boolean {
    let invalidate = this.mPageFling.calculate(time);
    invalidate = this.mSmoothScaler.calculate(time) || invalidate;
    invalidate = this.mOverScroller.calculate(time) || invalidate;
    return invalidate;
  }

  onDataChanged(): void {
    if (this.mAdapter === null) {
      throw new Error('The ScrollLayoutManager is not attached');
    }
    this.cancelAllAnimations();
    this.removeProgress();
    this.removeErrorView();
    this.removeAllPages();
    this.resetParameters();
    this.mGalleryView.requestFill();
  }

  // ==========================================================================
  // 翻页（点击左右/上下区域）
  // ==========================================================================

  /** 「上一页」= 向上滚（`GalleryView` 的 LEFT 区）。 */
  onPageLeft(): void {
    const adapter = this.mAdapter;
    if (adapter === null || this.mPages.length === 0) {
      return;
    }
    const size = adapter.size();
    if (size <= 0) {
      return;
    }

    const galleryView = this.mGalleryView;
    if (this.mIndex === 0 && this.mOffsetY >= 0) {
      // 已在顶部：回弹效果 + 通知"自动翻页结束"
      this.mOverScroller.overScroll(GLEdgeView.TOP);
      this.mGalleryView.onTransferEnd();
      return;
    }

    this.cancelAllAnimations();

    // 找第一个可见页与它前一页
    let previousPage: GalleryPageView | null = null;
    let firstShownPage: GalleryPageView | null = null;
    for (let i = 0; i < this.mPages.length; i++) {
      const p = this.mPages[i];
      if (this.isInScreen(p)) {
        firstShownPage = p;
        break;
      }
      previousPage = p;
    }

    const height = galleryView.getHeight();
    const maxOffset = height - this.mInterval;
    if (firstShownPage === null) {
      hilog.error(DOMAIN, TAG, 'Can\'t find first shown page when paging left');
      this.mOffsetY += Math.trunc(height / 2);
    } else {
      const firstShownTop = firstShownPage.bounds().top;
      if (firstShownTop >= 0) {
        if (previousPage === null) {
          hilog.error(DOMAIN, TAG, 'Can\'t find previous page when paging left and offsetY == 0');
          this.mOffsetY += Math.trunc(height / 2);
        } else {
          this.mOffsetY += Math.min(maxOffset, -previousPage.bounds().top);
        }
      } else {
        this.mOffsetY += Math.min(maxOffset, -firstShownTop);
      }
    }

    this.mGalleryView.requestFill();
  }

  /** 「下一页」= 向下滚（`GalleryView` 的 RIGHT 区）。 */
  onPageRight(): void {
    const adapter = this.mAdapter;
    if (adapter === null || this.mPages.length === 0) {
      return;
    }
    if (adapter.size() <= 0) {
      return;
    }

    const galleryView = this.mGalleryView;
    this.getBottomState();
    const bottom = this.mBottomStateBottom;
    const hasNext = this.mBottomStateHasNext;
    if (!hasNext && bottom <= galleryView.getHeight()) {
      // 已在底部
      this.mOverScroller.overScroll(GLEdgeView.BOTTOM);
      this.mGalleryView.onTransferEnd();
      return;
    }

    this.cancelAllAnimations();

    // 找最后一个可见页与它后一页
    let lastShownPage: GalleryPageView | null = null;
    let nextPage: GalleryPageView | null = null;
    for (let i = 0; i < this.mPages.length; i++) {
      const p = this.mPages[i];
      if (this.isInScreen(p)) {
        lastShownPage = p;
      } else if (lastShownPage !== null) {
        nextPage = p;
        break;
      }
    }

    const height = galleryView.getHeight();
    const maxOffset = height - this.mInterval;
    if (lastShownPage === null) {
      hilog.error(DOMAIN, TAG, 'Can\'t find last shown page when paging right');
      this.mOffsetY -= Math.trunc(height / 2);
    } else {
      const lastShownBottom = lastShownPage.bounds().bottom;
      if (lastShownBottom <= height) {
        if (nextPage === null) {
          hilog.error(DOMAIN, TAG, 'Can\'t find next page when paging right and at bottom');
          this.mOffsetY -= Math.trunc(height / 2);
        } else {
          this.mOffsetY -= Math.min(maxOffset, nextPage.bounds().bottom - height);
        }
      } else {
        this.mOffsetY -= Math.min(maxOffset, lastShownBottom - height);
      }
    }

    this.mGalleryView.requestFill();
  }

  // ==========================================================================
  // 查询
  // ==========================================================================

  isTapOrPressEnable(): boolean {
    return !this.mStopAnimationFinger;
  }

  findPageByIndex(index: number): GalleryPageView | null {
    for (let i = 0; i < this.mPages.length; i++) {
      if (this.mPages[i].getIndex() === index) {
        return this.mPages[i];
      }
    }
    return null;
  }

  getCurrentIndex(): number {
    for (let i = 0; i < this.mPages.length; i++) {
      if (this.isInScreen(this.mPages[i])) {
        return this.mPages[i].getIndex();
      }
    }
    return GalleryPageView.INVALID_INDEX;
  }

  setCurrentIndex(index: number): void {
    const adapter = this.mAdapter;
    if (adapter === null) {
      return;
    }
    let size = adapter.size();
    if (size <= 0) {
      // 尺寸还未知：按"无限大"处理（上游同一处置）
      size = Number.MAX_SAFE_INTEGER;
    }
    if (index < 0 || index >= size) {
      return;
    }

    this.mKeepTopPageIndex = index;
    this.mKeepTop = ScrollLayoutManager.INVALID_TOP;

    if (this.mPages.length === 0) {
      this.mIndex = index;
      return;
    }

    // 目标页已在列表里 → 直接对齐
    let targetPage: GalleryPageView | null = null;
    for (let i = 0; i < this.mPages.length; i++) {
      if (this.mPages[i].getIndex() === index) {
        targetPage = this.mPages[i];
        break;
      }
    }

    if (targetPage !== null) {
      this.cancelAllAnimations();
      this.mOffsetY -= targetPage.bounds().top;
      this.mGalleryView.requestFill();
    } else {
      this.mIndex = index;
      this.mOffsetY = 0;
      this.cancelAllAnimations();
      this.removeProgress();
      this.removeErrorView();
      this.removeAllPages();
      this.mGalleryView.requestFill();
    }
  }

  getIndexUnder(x: number, y: number): number {
    if (this.mPages.length === 0) {
      return GalleryPageView.INVALID_INDEX;
    }
    const intX = Math.trunc(x);
    const intY = Math.trunc(y);
    for (let i = 0; i < this.mPages.length; i++) {
      if (this.mPages[i].bounds().contains(intX, intY)) {
        return this.mPages[i].getIndex();
      }
    }
    return GalleryPageView.INVALID_INDEX;
  }

  getInternalCurrentIndex(): number {
    let currentIndex = this.getCurrentIndex();
    if (currentIndex === GalleryPageView.INVALID_INDEX) {
      currentIndex = this.mIndex;
    }
    return currentIndex;
  }

  // ==========================================================================
  // 诊断/单测入口
  // ==========================================================================

  getScale(): number {
    return this.mScale;
  }

  /** 诊断/单测：`getReservation()` 的当前值（随 `mScale` 变化）。 */
  getReservationValue(): number {
    return this.getReservation();
  }

  /**
   * 诊断/单测：直接设置缩放（`onScale` 需要页集合非空才能生效，单测里没有真实页）。
   * **生产代码不要调用**。
   */
  setScaleForTest(scale: number): void {
    this.mScale = scale;
  }

  /** 诊断/单测：直接设置 `mOffsetY`（生产由滚动手势改）。 */
  setOffsetYForTest(offsetY: number): void {
    this.mOffsetY = offsetY;
  }

  /** 诊断/单测：取一个页视图（走 `GalleryView` 的池化，与生产同一条路径）。 */
  obtainPageViewForTest(): GalleryPageView {
    return this.obtainPage();
  }

  /** 诊断/单测：暴露 `getPageForIndex`（生产内部用）。 */
  pageForIndexOfTest(pages: GalleryPageView[], index: number,
    remove: boolean): GalleryPageView | null {
    return this.getPageForIndex(pages, index, remove);
  }

  getOffsetY(): number {
    return this.mOffsetY;
  }

  getIndex(): number {
    return this.mIndex;
  }

  getPageCount(): number {
    return this.mPages.length;
  }

  /** 供内部动画类调用（ArkTS 无包内可见性，用 internal 方法暴露给同文件其他类）。 */
  scrollForFling(dx: number, dy: number): boolean {
    return this.scrollInternal(dx, dy, true, 0, 0);
  }

  scaleForAnimation(focusX: number, focusY: number, scale: number): void {
    this.onScale(focusX, focusY, scale);
  }

  onFlingFinish(): void {
    this.mFlingUp = false;
  }

  bottomState(): ScrollBottomState {
    this.getBottomState();
    return new ScrollBottomState(this.mBottomStateBottom, this.mBottomStateHasNext);
  }

  intervalValue(): number {
    return this.mInterval;
  }

  indexValue(): number {
    return this.mIndex;
  }

  offsetYValue(): number {
    return this.mOffsetY;
  }
}

/** `getBottomState()` 的结果（避免两次读字段之间状态变化）。 */
export class ScrollBottomState {
  bottom: number;
  hasNext: boolean;

  constructor(bottom: number, hasNext: boolean) {
    this.bottom = bottom;
    this.hasNext = hasNext;
  }
}

/**
 * 惯性滑动（上游内部类 `PageFling extends Fling`）。
 *
 * 与上游一致的三点：
 * 1. 距离用 `Fling` 的样条（`getSplineFlingDistance`），并用 `adjustDuration` 把时长改到"到边界"为止
 * 2. `onCalculate` 里调 `scrollInternal(..., fling=true)`，**返回 true（撞边界）就自我 cancel**
 * 3. `onFinish` 里按顶/底边缘触发 `edgeView.onAbsorb(velocity)` —— 这就是"滑到底部有回弹"的来源
 */
class ScrollPageFling extends Fling {
  private readonly mOwner: ScrollLayoutManager;
  private readonly mGalleryView: GalleryView;

  private mVelocityY: number = 0;
  private mDx: number = 0;
  private mDy: number = 0;
  private mLastX: number = 0;
  private mLastY: number = 0;

  constructor(owner: ScrollLayoutManager, galleryView: GalleryView) {
    super();
    this.mOwner = owner;
    this.mGalleryView = galleryView;
  }

  startFling(velocityX: number, minX: number, maxX: number, velocityY: number, minY: number,
    maxY: number): void {
    this.mVelocityY = velocityY;
    this.mDx = Math.trunc(this.getSplineFlingDistance(velocityX) * Math.sign(velocityX));
    this.mDy = Math.trunc(this.getSplineFlingDistance(velocityY) * Math.sign(velocityY));
    this.mLastX = 0;
    this.mLastY = 0;
    let durationX = this.getSplineFlingDuration(velocityX);
    let durationY = this.getSplineFlingDuration(velocityY);

    if (this.mDx < minX) {
      durationX = this.adjustDuration(0, this.mDx, minX, durationX);
      this.mDx = minX;
    }
    if (this.mDx > maxX) {
      durationX = this.adjustDuration(0, this.mDx, maxX, durationX);
      this.mDx = maxX;
    }
    if (this.mDy < minY) {
      durationY = this.adjustDuration(0, this.mDy, minY, durationY);
      this.mDy = minY;
    }
    if (this.mDy > maxY) {
      durationY = this.adjustDuration(0, this.mDy, maxY, durationY);
      this.mDy = maxY;
    }

    if (this.mDx === 0 && this.mDy === 0) {
      return;
    }

    this.setDuration(Math.max(durationX, durationY));
    this.start();
    this.mGalleryView.invalidate();
  }

  protected onCalculate(progress: number): void {
    const x = Math.trunc(this.mDx * progress);
    const y = Math.trunc(this.mDy * progress);
    const offsetX = x - this.mLastX;
    const offsetY = y - this.mLastY;
    if (this.mOwner.scrollForFling(-offsetX, -offsetY)) {
      this.cancel();
      this.onFinish();
    }
    this.mLastX = x;
    this.mLastY = y;
  }

  protected onFinish(): void {
    this.mOwner.onFlingFinish();

    const index = this.mOwner.indexValue();
    const offsetY = this.mOwner.offsetYValue();

    const topEdge = index <= 0 && offsetY >= 0;

    const state = this.mOwner.bottomState();
    const bottomEdge = !state.hasNext && state.bottom <= this.mGalleryView.getHeight();

    if (topEdge && bottomEdge) {
      return;
    }

    const edgeView = this.mGalleryView.getEdgeView();
    if (topEdge && edgeView.isFinished(GLEdgeView.TOP)) {
      edgeView.onAbsorb(this.mVelocityY, GLEdgeView.TOP);
    } else if (bottomEdge && edgeView.isFinished(GLEdgeView.BOTTOM)) {
      edgeView.onAbsorb(-this.mVelocityY, GLEdgeView.BOTTOM);
    }
  }
}

/** 平滑缩放（上游内部类 `SmoothScaler extends Animation`，双击缩放用）。 */
class ScrollSmoothScaler extends Animation {
  private readonly mOwner: ScrollLayoutManager;
  private readonly mGalleryView: GalleryView;

  private mFocusX: number = 0;
  private mFocusY: number = 0;
  private mStartScale: number = 1;
  private mEndScale: number = 1;
  private mLastScale: number = 1;

  constructor(owner: ScrollLayoutManager, galleryView: GalleryView) {
    super();
    this.mOwner = owner;
    this.mGalleryView = galleryView;
    this.setInterpolator(AnimationUtils.FAST_SLOW_INTERPOLATOR);
  }

  startSmoothScaler(focusX: number, focusY: number, startScale: number, endScale: number,
    duration: number): void {
    this.mFocusX = focusX;
    this.mFocusY = focusY;
    this.mStartScale = startScale;
    this.mEndScale = endScale;
    this.mLastScale = startScale;
    this.setDuration(duration);
    this.start();
    this.mGalleryView.invalidate();
  }

  protected onCalculate(progress: number): void {
    if (this.mOwner.getPageCount() <= 0) {
      return;
    }
    const scale = MathUtils.lerp(this.mStartScale, this.mEndScale, progress);
    this.mOwner.scaleForAnimation(this.mFocusX, this.mFocusY, scale / this.mLastScale);
    this.mLastScale = scale;
  }
}

/** 边界回弹（上游内部类 `OverScroller extends FloatAnimation`，翻页到底时用）。 */
class ScrollOverScroller extends FloatAnimation {
  private readonly mGalleryView: GalleryView;
  private mDirection: number = GLEdgeView.TOP;
  private mPosition: number = 0;

  constructor(owner: ScrollLayoutManager, galleryView: GalleryView) {
    super();
    this.mGalleryView = galleryView;
    this.setDuration(300);
  }

  overScroll(direction: number): void {
    this.mDirection = direction;
    let range: number;
    if (direction === GLEdgeView.LEFT || direction === GLEdgeView.RIGHT) {
      range = Math.trunc(this.mGalleryView.getWidth() / 7);
      this.mPosition = Math.trunc(this.mGalleryView.getHeight() / 2);
    } else if (direction === GLEdgeView.TOP || direction === GLEdgeView.BOTTOM) {
      range = Math.trunc(this.mGalleryView.getHeight() / 7);
      this.mPosition = Math.trunc(this.mGalleryView.getWidth() / 2);
    } else {
      return;
    }
    this.setRange(0, range);
    this.start();
    this.mGalleryView.invalidate();
  }

  protected onCalculate(progress: number): void {
    super.onCalculate(progress);
    this.mGalleryView.getEdgeView().onPull(this.get(), this.mPosition, this.mDirection);
  }

  protected onFinish(): void {
    this.mGalleryView.getEdgeView().onRelease(this.mDirection);
  }
}

