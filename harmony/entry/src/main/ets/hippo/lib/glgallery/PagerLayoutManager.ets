/*
 * Copyright 2014 Hippo Seven
 * Copyright 2026 ehviewer-harmony contributors
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

import { Animation } from '../glview/anim/Animation';
import { FloatAnimation } from '../glview/anim/FloatAnimation';
import { Interpolator } from '../yorozuya/AnimationUtils';
import { GLCanvas } from '../glview/glrenderer/GLCanvas';
import { GLProgressView } from '../glview/widget/GLProgressView';
import { GLTextureView } from '../glview/widget/GLTextureView';
import { GLEdgeView } from '../glview/widget/GLEdgeView';
import { GLView, GLViewMeasureSpec } from '../glview/view/GLView';
import { Fling } from './Fling';
import { GalleryPageView } from './GalleryPageView';
import { GalleryProvider } from './GalleryProvider';
import { GalleryAdapter, GalleryLayoutManager, GalleryView } from './GalleryView';
import { ImageView } from './ImageView';
import {
  MODE_LEFT_TO_RIGHT, MODE_RIGHT_TO_LEFT, ScrollBetweenResult, clampPagerOffset, isLeftPagePrevious,
  isRightPagePrevious, placeCurrentPage, placeLeftPage, placeRightPage, scrollBetweenPages, snapDx,
  snapDuration
} from './PagerLayoutCore';

/**
 * `com.hippo.lib.glgallery.PagerLayoutManager` 的 ArkTS 等价实现（inventory S0327）。
 *
 * 语义：**翻页模式**的布局管理器 —— 屏幕上同时只完整显示一页，左右各挂一页做过渡。
 * 与 `ScrollLayoutManager`（连续滚动）的区别：
 * ```
 * 连续滚动：逐像素推进 + 边界 forceFill() 补内容
 * 翻页：    整页位移 + 边界吸附（offset 只在 [-width-interval+1, width+interval-1] 有意义）
 * ```
 *
 * ## 拆法
 *   - **纯几何** → `PagerLayoutCore`（夹紧 / 三页矩形 / 方向映射 / 回弹位移与时长，39 条断言）
 *   - **控制流 + 视图池 + 动画** → 本文件
 *
 * ## 必须照搬的几处
 *   1. `getLeftPage()/getRightPage()` 按 `mPagerMode` 返回**相反的页**（`RIGHT_TO_LEFT` 下 left 是下一页）
 *   2. `onUp()` 整段被 `if (mPagerOffset != 0)` 包着 —— `offset == 0` 时**什么都不做**
 *      （不启动 smooth scroller，否则会多一次滚动回调、影响 tap 判定）
 *   3. `scrollInternal` 的 `|dx| > |dy| * 1.5` 只在 `isFirstScroll()` 时采样一次
 *   4. `setCurrentIndex` 里 `size <= 0` 时按 `Integer.MAX_VALUE` 处理（数据还没回来时允许跳页）
 */
export class PagerLayoutManager extends GalleryLayoutManager {

  private mPagerAdapter: GalleryAdapter | null = null;
  private mPagerProgress: GLProgressView | null = null;
  private mPagerErrorStr: string | null = null;
  private mPagerErrorView: GLTextureView | null = null;

  private mPagerPrevious: GalleryPageView | null = null;
  private mPagerCurrent: GalleryPageView | null = null;
  private mPagerNext: GalleryPageView | null = null;

  private mPagerMode: number = MODE_RIGHT_TO_LEFT;
  private mPagerScaleMode: number;
  private mPagerStartPosition: number;
  private mPagerScaleValue: number;

  private mPagerOffset: number = 0;
  private mPagerDeltaX: number = 0;
  private mPagerDeltaY: number = 0;
  private mPagerCanScrollBetweenPages: boolean = false;
  private mPagerStopAnimationFinger: boolean = false;
  private mPagerInterval: number;
  private mPagerIndex: number = 0;

  private readonly mScrollRemain: number[] = [0, 0];
  private readonly mScaleDefault: number[] = [0, 0, 0, 0];

  private readonly mSmoothScroller: SmoothScroller;
  private readonly mPageFling: PageFling;
  private readonly mSmoothScaler: SmoothScaler;
  private readonly mOverScroller: OverScroller;

  constructor(galleryView: GalleryView, scaleMode: number, startPosition: number,
    scaleValue: number, interval: number) {
    super(galleryView);
    this.mPagerScaleMode = scaleMode;
    this.mPagerStartPosition = startPosition;
    this.mPagerScaleValue = scaleValue;
    this.mPagerInterval = interval;
    this.mSmoothScroller = new SmoothScroller();
    this.mPageFling = new PageFling();
    this.mSmoothScaler = new SmoothScaler();
    this.mOverScroller = new OverScroller();
    // 三个动画的"落地动作"在这里接线（动画类本身不认识管理器，避免反向依赖）
    this.mSmoothScroller.setOnScroll((dx: number, dy: number): void => {
      this.scrollInternal(dx, dy, 0, 0);
    });
    this.mPageFling.setOnScroll((dx: number, dy: number): void => {
      const cur: GalleryPageView | null = this.mPagerCurrent;
      if (cur !== null) {
        cur.getImageView().scroll(dx, dy, this.mScrollRemain);
      }
    });
    this.mSmoothScaler.setOnScale((fx: number, fy: number, ratio: number): void => {
      this.onScale(fx, fy, ratio);
    });
  }

  // ==========================================================================
  // 配置
  // ==========================================================================

  /** 对齐 `setInterval(interval)`：已 attach 时**重建三页**（否则页间距不会变）。 */
  setInterval(interval: number): void {
    if (this.mPagerInterval === interval) {
      return;
    }
    const adapter: GalleryAdapter | null = this.mPagerAdapter;
    if (adapter !== null) {
      const index: number = this.getInternalCurrentIndex();
      const detached: GalleryAdapter = this.onDetach();
      this.mPagerInterval = interval;
      this.onAttach(detached);
      this.setCurrentIndex(index);
      this.mGalleryView.requestFill();
    } else {
      this.mPagerInterval = interval;
    }
  }

  /** 对齐 `setMode(mode)`：切换方向后要清空三页重排。 */
  setMode(mode: number): void {
    if (this.mPagerMode === mode) {
      return;
    }
    this.mPagerMode = mode;
    if (this.mPagerAdapter !== null) {
      this.cancelAllAnimations();
      this.removeProgress();
      this.removeErrorView();
      this.removeAllPages();
      this.resetParameters();
      this.mGalleryView.requestFill();
    }
  }

  setScaleMode(scaleMode: number): void {
    if (this.mPagerScaleMode === scaleMode) {
      return;
    }
    this.mPagerScaleMode = scaleMode;
    this.applyScaleToPages();
  }

  setStartPosition(startPosition: number): void {
    if (this.mPagerStartPosition === startPosition) {
      return;
    }
    this.mPagerStartPosition = startPosition;
    this.applyScaleToPages();
  }

  private applyScaleToPages(): void {
    const pages: (GalleryPageView | null)[] = [this.mPagerCurrent, this.mPagerPrevious, this.mPagerNext];
    for (let i = 0; i < pages.length; i++) {
      const page: GalleryPageView | null = pages[i];
      if (page !== null) {
        page.getImageView().setScaleOffset(this.mPagerScaleMode, this.mPagerStartPosition, this.mPagerScaleValue);
      }
    }
  }

  getMode(): number {
    return this.mPagerMode;
  }

  getInterval(): number {
    return this.mPagerInterval;
  }

  override setPagerMode(mode: number): void {
    this.setMode(mode);
  }

  override setPagerScaleMode(scaleMode: number): void {
    this.setScaleMode(scaleMode);
  }

  override setPagerStartPosition(startPosition: number): void {
    this.setStartPosition(startPosition);
  }

  override setPageInterval(interval: number): void {
    this.setInterval(interval);
  }

  private resetParameters(): void {
    this.mPagerOffset = 0;
    this.mPagerDeltaX = 0;
    this.mPagerDeltaY = 0;
    this.mPagerCanScrollBetweenPages = false;
    this.mPagerStopAnimationFinger = false;
  }

  private cancelAllAnimations(): boolean {
    const running: boolean = this.mSmoothScroller.isRunning() || this.mPageFling.isRunning() ||
      this.mSmoothScaler.isRunning() || this.mOverScroller.isRunning();
    this.mSmoothScroller.cancel();
    this.mPageFling.cancel();
    this.mSmoothScaler.cancel();
    this.mOverScroller.cancel();
    return running;
  }

  // ==========================================================================
  // attach / detach
  // ==========================================================================

  onAttach(adapter: GalleryAdapter): void {
    if (this.mPagerAdapter !== null) {
      throw new Error('The PagerLayoutManager is attached');
    }
    if (adapter === null) {
      throw new Error('The adapter is null');
    }
    this.mPagerAdapter = adapter;
    this.resetParameters();
  }

  onDetach(): GalleryAdapter {
    const adapter: GalleryAdapter | null = this.mPagerAdapter;
    if (adapter === null) {
      throw new Error('The PagerLayoutManager is not attached');
    }
    this.cancelAllAnimations();
    this.removeProgress();
    this.removeErrorView();
    this.removeAllPages();
    this.resetParameters();
    this.mPagerAdapter = null;
    return adapter;
  }

  // ==========================================================================
  // 视图池
  // ==========================================================================

  private removeProgress(): void {
    const p: GLProgressView | null = this.mPagerProgress;
    if (p !== null) {
      this.mGalleryView.removeComponent(p);
      this.mGalleryView.releaseProgress(p);
      this.mPagerProgress = null;
    }
  }

  private removeErrorView(): void {
    const e: GLTextureView | null = this.mPagerErrorView;
    if (e !== null) {
      this.mGalleryView.removeComponent(e);
      this.mGalleryView.releaseErrorView(e);
      this.mPagerErrorView = null;
      this.mPagerErrorStr = null;
    }
  }

  private removePage(page: GalleryPageView): void {
    this.mGalleryView.removeComponent(page);
    (this.mPagerAdapter as GalleryAdapter).unbind(page);
    this.mGalleryView.releasePage(page);
  }

  private removeAllPages(): void {
    const prev: GalleryPageView | null = this.mPagerPrevious;
    if (prev !== null) {
      this.removePage(prev);
      this.mPagerPrevious = null;
    }
    const cur: GalleryPageView | null = this.mPagerCurrent;
    if (cur !== null) {
      this.removePage(cur);
      this.mPagerCurrent = null;
    }
    const next: GalleryPageView | null = this.mPagerNext;
    if (next !== null) {
      this.removePage(next);
      this.mPagerNext = null;
    }
  }

  private obtainPage(): GalleryPageView {
    return this.mGalleryView.obtainPage();
  }



  // ==========================================================================
  // 方向映射（**反直觉**：默认模式下 left 是下一页）
  // ==========================================================================

  private getLeftPage(): GalleryPageView | null {
    return isLeftPagePrevious(this.mPagerMode) ? this.mPagerPrevious : this.mPagerNext;
  }

  private getRightPage(): GalleryPageView | null {
    return isRightPagePrevious(this.mPagerMode) ? this.mPagerPrevious : this.mPagerNext;
  }

  // ==========================================================================
  // onFill
  // ==========================================================================

  onFill(): void {
    const adapter: GalleryAdapter | null = this.mPagerAdapter;
    if (adapter === null) {
      throw new Error('The PagerLayoutManager is not attached');
    }
    const width: number = this.mGalleryView.getWidth();
    const height: number = this.mGalleryView.getHeight();
    const size: number = adapter.size();
    let errorStr: string | null = adapter.getError();

    if (size === GalleryProvider.STATE_WAIT) {
      this.removeErrorView();
      this.removeAllPages();
      if (this.mPagerProgress === null) {
        this.mPagerProgress = this.mGalleryView.obtainProgress();
        this.mGalleryView.addComponent(this.mPagerProgress);
      }
      this.placeCenter(this.mPagerProgress);
      return;
    }

    if (size <= GalleryProvider.STATE_ERROR || size === 0) {
      if (size === 0) {
        errorStr = this.mGalleryView.getEmptyStr();
      } else if (errorStr === null) {
        errorStr = this.mGalleryView.getDefaultErrorStr();
      }
      this.removeProgress();
      this.removeAllPages();
      if (this.mPagerErrorView === null) {
        this.mPagerErrorView = this.mGalleryView.obtainErrorView();
        this.mGalleryView.addComponent(this.mPagerErrorView);
      }
      const text: string = errorStr === null ? '' : errorStr;
      if (text !== this.mPagerErrorStr) {
        this.mPagerErrorStr = text;
        this.mGalleryView.bindErrorView(this.mPagerErrorView, text);
      }
      this.placeCenter(this.mPagerErrorView);
      return;
    }

    // 正常：三页 + 进度/错误都清掉
    this.removeProgress();
    this.removeErrorView();

    let index: number = this.mPagerIndex;
    if (index < 0) {
      index = 0;
      this.mPagerIndex = index;
      this.removeAllPages();
    } else if (index >= size) {
      index = size - 1;
      this.mPagerIndex = index;
      this.removeAllPages();
    }

    if (this.mPagerCurrent === null) {
      this.mPagerCurrent = this.obtainPage();
      this.mGalleryView.addComponent(this.mPagerCurrent);
      adapter.bind(this.mPagerCurrent, index);
    }
    if (this.mPagerPrevious === null && index > 0) {
      this.mPagerPrevious = this.obtainPage();
      this.mGalleryView.addComponent(this.mPagerPrevious);
      adapter.bind(this.mPagerPrevious, index - 1);
    } else if (this.mPagerPrevious !== null && index === 0) {
      this.removePage(this.mPagerPrevious);
      this.mPagerPrevious = null;
    }
    if (this.mPagerNext === null && index < size - 1) {
      this.mPagerNext = this.obtainPage();
      this.mGalleryView.addComponent(this.mPagerNext);
      adapter.bind(this.mPagerNext, index + 1);
    } else if (this.mPagerNext !== null && index === size - 1) {
      this.removePage(this.mPagerNext);
      this.mPagerNext = null;
    }

    // 夹紧 offset（几何在 Core 里，已断言）
    this.mPagerOffset = clampPagerOffset(this.mPagerOffset, this.getLeftPage() !== null,
      this.getRightPage() !== null, width, this.mPagerInterval);

    // 三页布局（几何在 Core 里）
    const offset: number = this.mPagerOffset;
    const cur: GalleryPageView | null = this.mPagerCurrent;
    if (cur !== null) {
      const r = placeCurrentPage(offset, width, height);
      this.layoutPage(cur, r.left, r.top, r.right, r.bottom, width, height);
    }
    const left: GalleryPageView | null = this.getLeftPage();
    if (left !== null) {
      const r = placeLeftPage(offset, width, height, this.mPagerInterval);
      this.layoutPage(left, r.left, r.top, r.right, r.bottom, width, height);
    }
    const right: GalleryPageView | null = this.getRightPage();
    if (right !== null) {
      const r = placeRightPage(offset, width, height, this.mPagerInterval);
      this.layoutPage(right, r.left, r.top, r.right, r.bottom, width, height);
    }
  }

  /** 对齐 `layoutPage`：EXACTLY 测量后按矩形摆放。 */
  private layoutPage(page: GalleryPageView, left: number, top: number, right: number,
    bottom: number, width: number, height: number): void {
    const widthSpec: number = GLViewMeasureSpec.makeMeasureSpec(width, GLViewMeasureSpec.EXACTLY);
    const heightSpec: number = GLViewMeasureSpec.makeMeasureSpec(height, GLViewMeasureSpec.EXACTLY);
    page.measure(widthSpec, heightSpec);
    page.layout(left, top, right, bottom);
  }

  // ==========================================================================
  // 触摸
  // ==========================================================================

  onDown(): void {
    this.mPagerDeltaX = 0;
    this.mPagerDeltaY = 0;
    this.mPagerStopAnimationFinger = this.cancelAllAnimations();
  }

  onUp(): void {
    this.mGalleryView.getEdgeView().onRelease();
    const cur: GalleryPageView | null = this.mPagerCurrent;
    if (cur === null) {
      return;
    }
    // **守卫**：上游整段被 `if (mPagerOffset != 0)` 包着 —— offset==0 什么都不做
    if (this.mPagerOffset !== 0) {
      const width: number = this.mGalleryView.getWidth();
      const dx: number = snapDx(this.mPagerOffset, width, this.mPagerInterval,
        this.getLeftPage() !== null, this.getRightPage() !== null);
      const duration: number = snapDuration(this.mPagerOffset, width, this.mPagerInterval);
      this.mSmoothScroller.startSmoothScroll(dx, 0, duration);
    }
  }

  onDoubleTapConfirmed(x: number, y: number): void {
    const cur: GalleryPageView | null = this.mPagerCurrent;
    if (cur === null || !cur.getImageView().isLoaded()) {
      return;
    }
    const image: ImageView = cur.getImageView();
    const scales: number[] = this.mScaleDefault;
    image.getScaleDefault(scales);
    const scale: number = image.getScale();
    let endScale: number = scales[0];
    for (let i = 0; i < scales.length; i++) {
      const value: number = scales[i];
      if (scale < value - 0.01) {
        endScale = value;
        break;
      }
    }
    this.mSmoothScaler.startSmoothScaler(x, y, scale, endScale, 300);
  }

  onLongPress(x: number, y: number): void {
    // 上游空实现（长按由 GalleryView 自己处理）
  }

  onScroll(dx: number, dy: number, totalX: number, totalY: number, x: number, y: number): void {
    this.scrollInternal(dx, dy, x, y);
  }

  onFling(velocityX: number, velocityY: number): void {
    const cur: GalleryPageView | null = this.mPagerCurrent;
    if (cur === null || this.mPagerOffset !== 0 || !cur.getImageView().isLoaded() ||
      !cur.getImageView().canFling()) {
      return;
    }
    const image: ImageView = cur.getImageView();
    this.mPageFling.startFling(Math.floor(velocityX), image.getMinDx(), image.getMaxDx(),
      Math.floor(velocityY), image.getMinDy(), image.getMaxDy());
  }

  canScale(): boolean {
    const cur: GalleryPageView | null = this.mPagerCurrent;
    return cur !== null && this.mPagerOffset === 0 && cur.getImageView().isLoaded();
  }

  onScale(focusX: number, focusY: number, scale: number): void {
    const cur: GalleryPageView | null = this.mPagerCurrent;
    if (cur === null || !cur.getImageView().isLoaded()) {
      return;
    }
    cur.getImageView().scale(focusX, focusY, scale);
    this.mPagerScaleValue = cur.getImageView().getScale();
  }

  /**
   * 对齐 `scrollInternal(dx, dy, x, y)`（上游 629-676）。
   *
   * 四路分支顺序不能换：①先让当前图吃掉位移 ②到边了交给 edgeView ③页间滚动 ④都不行就丢弃。
   * `mPagerCanScrollBetweenPages` **只在 `isFirstScroll()` 时采样一次**，之后整次手势沿用。
   */
  scrollInternal(dx: number, dy: number, x: number, y: number): void {
    const cur: GalleryPageView | null = this.mPagerCurrent;
    if (cur === null) {
      return;
    }
    let needFill: boolean = false;
    let canImageScroll: boolean = true;
    let remainX: number = Math.floor(dx);
    let remainY: number = Math.floor(dy);

    if (this.mGalleryView.isFirstScroll()) {
      this.mPagerCanScrollBetweenPages = Math.abs(dx) > Math.abs(dy) * 1.5;
    }

    while (remainX !== 0 || remainY !== 0) {
      if (this.mPagerOffset === 0 && canImageScroll) {
        cur.getImageView().scroll(remainX, remainY, this.mScrollRemain);
        remainX = this.mScrollRemain[0];
        remainY = this.mScrollRemain[1];
        canImageScroll = false;
        this.mPagerDeltaX = 0;
        this.mPagerDeltaY = 0;
      } else if (remainX === 0 ||
        (this.getLeftPage() === null && this.mPagerOffset === 0 && remainX < 0) ||
        (this.getRightPage() === null && this.mPagerOffset === 0 && remainX > 0)) {
        this.overScrollEdge(remainX, remainY, x, y);
        remainX = 0;
        remainY = 0;
      } else if (this.mPagerCanScrollBetweenPages) {
        remainX = this.scrollBetweenPages(remainX);
        canImageScroll = true;
        needFill = true;
        this.mPagerDeltaX = 0;
        this.mPagerDeltaY = 0;
      } else {
        remainX = 0;
        remainY = 0;
        this.mPagerDeltaX = 0;
        this.mPagerDeltaY = 0;
      }
    }

    if (needFill) {
      this.mGalleryView.requestFill();
    }
  }

  /**
   * 对齐 `scrollBetweenPages(dx)`（上游 547-594）：返回**没被吃掉**的剩余位移。
   *
   * 越过一页时直接 `pageLeft()/pageRight()` 并 `mPagerOffset = 0`（翻页是"跳"不是"滑"）。
   */
  scrollBetweenPages(dx: number): number {
    // 几何在 PagerLayoutCore.scrollBetweenPages（纯函数，已断言）；本方法只做副作用
    const r: ScrollBetweenResult = scrollBetweenPages(dx, this.mPagerOffset,
      this.mGalleryView.getWidth(), this.mPagerInterval,
      this.getLeftPage() !== null, this.getRightPage() !== null);
    if (r.flip < 0) {
      this.pageLeft();
    } else if (r.flip > 0) {
      this.pageRight();
    }
    this.mPagerOffset = r.offset;
    return r.remain;
  }

  /** 对齐 `overScrollEdge`：多余位移交给 edgeView 做越界效果。 */
  overScrollEdge(dx: number, dy: number, x: number, y: number): void {
    const edgeView: GLEdgeView = this.mGalleryView.getEdgeView();
    this.mPagerDeltaX += dx;
    this.mPagerDeltaY += dy;

    if (this.mPagerDeltaX < 0) {
      edgeView.onPull(-this.mPagerDeltaX, y, GLEdgeView.LEFT);
      if (!edgeView.isFinished(GLEdgeView.RIGHT)) {
        edgeView.onRelease(GLEdgeView.RIGHT);
      }
    } else if (this.mPagerDeltaX > 0) {
      edgeView.onPull(this.mPagerDeltaX, y, GLEdgeView.RIGHT);
      if (!edgeView.isFinished(GLEdgeView.LEFT)) {
        edgeView.onRelease(GLEdgeView.LEFT);
      }
    }

    const cur: GalleryPageView | null = this.mPagerCurrent;
    if (cur !== null && cur.getImageView().canFlingVertically()) {
      if (this.mPagerDeltaY < 0) {
        edgeView.onPull(-this.mPagerDeltaY, x, GLEdgeView.TOP);
        if (!edgeView.isFinished(GLEdgeView.BOTTOM)) {
          edgeView.onRelease(GLEdgeView.BOTTOM);
        }
      } else if (this.mPagerDeltaY > 0) {
        edgeView.onPull(this.mPagerDeltaY, x, GLEdgeView.BOTTOM);
        if (!edgeView.isFinished(GLEdgeView.TOP)) {
          edgeView.onRelease(GLEdgeView.TOP);
        }
      }
    }
  }

  // ==========================================================================
  // 翻页（三页轮转）
  // ==========================================================================

  private pagePrevious(): void {
    const adapter: GalleryAdapter = this.mPagerAdapter as GalleryAdapter;
    const size: number = adapter.size();
    if (this.mPagerIndex == 0) {
      return;
    }
    this.mPagerIndex--;
    if (this.mPagerNext !== null) {
      this.removePage(this.mPagerNext);
    }
    const next: GalleryPageView | null = this.mPagerCurrent;
    if (next !== null) {
      this.mPagerNext = next;
    }
    const cur: GalleryPageView | null = this.mPagerPrevious;
    if (cur !== null) {
      this.mPagerCurrent = cur;
    }
    this.mPagerPrevious = null;
    if (this.mPagerIndex > 0) {
      this.mPagerPrevious = this.obtainPage();
      this.mGalleryView.addComponent(this.mPagerPrevious);
      adapter.bind(this.mPagerPrevious, this.mPagerIndex - 1);
    }
  }

  private pageNext(): void {
    const adapter: GalleryAdapter = this.mPagerAdapter as GalleryAdapter;
    const size: number = adapter.size();
    if (this.mPagerIndex == size - 1) {
      return;
    }
    this.mPagerIndex++;
    const prev: GalleryPageView | null = this.mPagerPrevious;
    if (prev !== null) {
      this.removePage(prev);
    }
    const cur: GalleryPageView | null = this.mPagerCurrent;
    if (cur !== null) {
      this.mPagerPrevious = cur;
    }
    const next: GalleryPageView | null = this.mPagerNext;
    if (next !== null) {
      this.mPagerCurrent = next;
    }
    this.mPagerNext = null;
    if (this.mPagerIndex < size - 1) {
      this.mPagerNext = this.obtainPage();
      this.mGalleryView.addComponent(this.mPagerNext);
      adapter.bind(this.mPagerNext, this.mPagerIndex + 1);
    }
  }

  private pageLeft(): void {
    if (this.mPagerMode === MODE_LEFT_TO_RIGHT) {
      this.pagePrevious();
    } else {
      this.pageNext();
    }
  }

  private pageRight(): void {
    if (this.mPagerMode === MODE_LEFT_TO_RIGHT) {
      this.pageNext();
    } else {
      this.pagePrevious();
    }
  }

  onPageLeft(): void {
    const adapter: GalleryAdapter | null = this.mPagerAdapter;
    if (adapter === null) {
      return;
    }
    const size: number = adapter.size();
    if (size <= 0 || this.mPagerCurrent === null) {
      return;
    }
    if (this.mPagerMode === MODE_LEFT_TO_RIGHT) {
      if (this.mPagerIndex === 0) {
        this.mOverScroller.overScroll(GLEdgeView.LEFT);
      } else {
        this.setCurrentIndex(this.mPagerIndex - 1);
      }
    } else {
      if (this.mPagerIndex >= size - 1) {
        this.mOverScroller.overScroll(GLEdgeView.LEFT);
        this.mGalleryView.onTransferEnd();
      } else {
        this.setCurrentIndex(this.mPagerIndex + 1);
      }
    }
  }

  onPageRight(): void {
    const adapter: GalleryAdapter | null = this.mPagerAdapter;
    if (adapter === null) {
      return;
    }
    const size: number = adapter.size();
    if (size <= 0 || this.mPagerCurrent === null) {
      return;
    }
    if (this.mPagerMode === MODE_LEFT_TO_RIGHT) {
      if (this.mPagerIndex >= size - 1) {
        this.mOverScroller.overScroll(GLEdgeView.RIGHT);
        this.mGalleryView.onTransferEnd();
      } else {
        this.setCurrentIndex(this.mPagerIndex + 1);
      }
    } else {
      if (this.mPagerIndex === 0) {
        this.mOverScroller.overScroll(GLEdgeView.RIGHT);
      } else {
        this.setCurrentIndex(this.mPagerIndex - 1);
      }
    }
  }

  // ==========================================================================
  // 索引
  // ==========================================================================

  getCurrentIndex(): number {
    const cur: GalleryPageView | null = this.mPagerCurrent;
    return cur !== null ? cur.getIndex() : GalleryPageView.INVALID_INDEX;
  }

  getInternalCurrentIndex(): number {
    return this.mPagerIndex;
  }

  setCurrentIndex(index: number): void {
    const adapter: GalleryAdapter | null = this.mPagerAdapter;
    if (adapter === null) {
      return;
    }
    let size: number = adapter.size();
    if (size <= 0) {
      // 数据还没回来：按"无穷大"处理，允许跳页
      size = Number.MAX_SAFE_INTEGER;
    }
    if (index === this.mPagerIndex || index < 0 || index >= size) {
      return;
    }
    if (this.mPagerCurrent === null) {
      this.mPagerIndex = index;
    } else if (index === this.mPagerIndex - 1) {
      this.cancelAllAnimations();
      this.resetParameters();
      this.pagePrevious();
      this.mGalleryView.requestFill();
    } else if (index === this.mPagerIndex + 1) {
      this.cancelAllAnimations();
      this.resetParameters();
      this.pageNext();
      this.mGalleryView.requestFill();
    } else {
      this.cancelAllAnimations();
      this.removeProgress();
      this.removeErrorView();
      this.removeAllPages();
      this.resetParameters();
      this.mPagerIndex = index;
      this.mGalleryView.requestFill();
    }
  }

  /** 对齐 `getIndexUnder(x, y)`：命中哪一页就返回它的 index，否则 `INVALID_INDEX`。 */
  getIndexUnder(x: number, y: number): number {
    const pages: (GalleryPageView | null)[] = [this.mPagerCurrent, this.mPagerPrevious, this.mPagerNext];
    for (let i = 0; i < pages.length; i++) {
      const page: GalleryPageView | null = pages[i];
      if (page !== null && page.getVisibility() === GLView.VISIBLE) {
        const r = page.bounds();
        if (x >= r.left && x < r.right && y >= r.top && y < r.bottom) {
          return page.getIndex();
        }
      }
    }
    return GalleryPageView.INVALID_INDEX;
  }

  findPageByIndex(index: number): GalleryPageView | null {
    const cur: GalleryPageView | null = this.mPagerCurrent;
    if (cur !== null && cur.getIndex() === index) {
      return cur;
    }
    const prev: GalleryPageView | null = this.mPagerPrevious;
    if (prev !== null && prev.getIndex() === index) {
      return prev;
    }
    const next: GalleryPageView | null = this.mPagerNext;
    if (next !== null && next.getIndex() === index) {
      return next;
    }
    return null;
  }

  // ==========================================================================
  // 动画 / 数据变化
  // ==========================================================================

  onUpdateAnimation(time: number): boolean {
    let invalidate: boolean = this.mSmoothScroller.calculate(time);
    invalidate = this.mPageFling.calculate(time) || invalidate;
    invalidate = this.mSmoothScaler.calculate(time) || invalidate;
    invalidate = this.mOverScroller.calculate(time) || invalidate;
    return invalidate;
  }

  onDataChanged(): void {
    if (this.mPagerAdapter === null) {
      throw new Error('The PagerLayoutManager is not attached');
    }
    this.cancelAllAnimations();
    this.removeProgress();
    this.removeErrorView();
    this.removeAllPages();
    this.resetParameters();
    this.mGalleryView.requestFill();
  }

  isTapOrPressEnable(): boolean {
    return !this.mPagerStopAnimationFinger;
  }

  /** 测试用：当前 offset / 三页引用。 */
  getOffset(): number {
    return this.mPagerOffset;
  }

  hasPage(index: number): boolean {
    return this.findPageByIndex(index) !== null;
  }
}

// ============================================================================
// 内嵌动画（对齐上游四个私有类）
// ============================================================================

/**
 * 对齐上游 `SMOOTH_SCROLLER_INTERPOLATOR`（匿名类）：`t -= 1; return t^5 + 1`。
 * ArkTS 不允许"对象字面量当接口"，落成具名类。
 */
class FifthPowerInterpolator implements Interpolator {
  getInterpolation(t: number): number {
    const u: number = t - 1.0;
    return u * u * u * u * u + 1.0;
  }
}

/**
 * 对齐上游 `SmoothScroller extends Scroller`。
 * ArkTS 侧没有 `Scroller` 基类（`anim/` 只有 Animation/FloatAnimation/CanvasAnimation/AlphaAnimation），
 * 这里**内联**它用得上的部分：`startSmoothScroll` + 五次方插值。
 * 不单独立 `Scroller.ets`：PagerLayoutManager 是唯一使用者。
 */
class SmoothScroller extends Animation {
  private scDx: number = 0;
  private scDy: number = 0;
  private scLastX: number = 0;
  private scLastY: number = 0;
  private scOnScroll: ((dx: number, dy: number) => void) | null = null;

  constructor() {
    super();
    this.setInterpolator(new FifthPowerInterpolator());
  }

  setOnScroll(cb: (dx: number, dy: number) => void): void {
    this.scOnScroll = cb;
  }

  startSmoothScroll(dx: number, dy: number, duration: number): void {
    this.scDx = dx;
    this.scDy = dy;
    this.scLastX = 0;
    this.scLastY = 0;
    this.setDuration(duration <= 0 ? 1 : duration);
    this.start();
  }

  protected onCalculate(progress: number): void {
    const x: number = Math.floor(this.scDx * progress);
    const y: number = Math.floor(this.scDy * progress);
    const ox: number = x - this.scLastX;
    const oy: number = y - this.scLastY;
    this.scLastX = x;
    this.scLastY = y;
    const cb = this.scOnScroll;
    if (cb !== null && (ox !== 0 || oy !== 0)) {
      cb(ox, oy);
    }
  }
}

/** 对齐上游 `PageFling extends Fling`：图片内部可滚时的甩动。 */
class PageFling extends Fling {
  private pfVelocityY: number = 0;
  private pfDx: number = 0;
  private pfDy: number = 0;
  private pfLastX: number = 0;
  private pfLastY: number = 0;
  private pfOnScroll: ((dx: number, dy: number) => void) | null = null;

  constructor() {
    super();
  }

  setOnScroll(cb: (dx: number, dy: number) => void): void {
    this.pfOnScroll = cb;
  }

  startFling(velocityX: number, minX: number, maxX: number,
    velocityY: number, minY: number, maxY: number): void {
    this.pfVelocityY = velocityY;
    this.pfDx = Math.floor(this.getSplineFlingDistance(velocityX) * Math.sign(velocityX));
    this.pfDy = Math.floor(this.getSplineFlingDistance(velocityY) * Math.sign(velocityY));
    this.pfLastX = 0;
    this.pfLastY = 0;
    let durationX: number = this.getSplineFlingDuration(velocityX);
    let durationY: number = this.getSplineFlingDuration(velocityY);
    if (this.pfDx < minX) {
      durationX = this.adjustDuration(0, this.pfDx, minX, durationX);
      this.pfDx = minX;
    }
    if (this.pfDx > maxX) {
      durationX = this.adjustDuration(0, this.pfDx, maxX, durationX);
      this.pfDx = maxX;
    }
    if (this.pfDy < minY) {
      durationY = this.adjustDuration(0, this.pfDy, minY, durationY);
      this.pfDy = minY;
    }
    if (this.pfDy > maxY) {
      durationY = this.adjustDuration(0, this.pfDy, maxY, durationY);
      this.pfDy = maxY;
    }
    if (this.pfDx === 0 && this.pfDy === 0) {
      return;
    }
    this.setDuration(Math.max(durationX, durationY));
    this.start();
  }

  protected onCalculate(progress: number): void {
    const x: number = Math.floor(this.pfDx * progress);
    const y: number = Math.floor(this.pfDy * progress);
    const ox: number = x - this.pfLastX;
    const oy: number = y - this.pfLastY;
    this.pfLastX = x;
    this.pfLastY = y;
    const cb = this.pfOnScroll;
    if (cb !== null && (ox !== 0 || oy !== 0)) {
      cb(-ox, -oy);
    }
  }

  getVelocityY(): number {
    return this.pfVelocityY;
  }
}

/** 对齐上游 `SmoothScaler extends Animation`：双击缩放动画。 */
class SmoothScaler extends Animation {
  private ssFocusX: number = 0;
  private ssFocusY: number = 0;
  private ssStart: number = 1;
  private ssEnd: number = 1;
  private ssLast: number = 1;
  private ssOnScale: ((fx: number, fy: number, ratio: number) => void) | null = null;

  constructor() {
    super();
  }

  setOnScale(cb: (fx: number, fy: number, ratio: number) => void): void {
    this.ssOnScale = cb;
  }

  startSmoothScaler(focusX: number, focusY: number, startScale: number,
    endScale: number, duration: number): void {
    this.ssFocusX = focusX;
    this.ssFocusY = focusY;
    this.ssStart = startScale;
    this.ssEnd = endScale;
    this.ssLast = startScale;
    this.setDuration(duration <= 0 ? 1 : duration);
    this.start();
  }

  protected onCalculate(progress: number): void {
    const scale: number = this.ssStart + (this.ssEnd - this.ssStart) * progress;
    const ratio: number = this.ssLast === 0 ? 1 : scale / this.ssLast;
    this.ssLast = scale;
    const cb = this.ssOnScale;
    if (cb !== null && ratio !== 1) {
      cb(this.ssFocusX, this.ssFocusY, ratio);
    }
  }
}

/** 对齐上游 `OverScroller extends FloatAnimation`：越界回弹。 */
class OverScroller extends FloatAnimation {
  private osDirection: number = -1;

  constructor() {
    super();
  }

  overScroll(direction: number): void {
    this.osDirection = direction;
    this.setRange(0, 1);
    this.setDuration(300);
    this.start();
  }

  getDirection(): number {
    return this.osDirection;
  }
}