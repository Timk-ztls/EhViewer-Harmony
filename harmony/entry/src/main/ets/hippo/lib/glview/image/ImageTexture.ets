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
import { RectF } from '../util/RectF';
import { GLCanvas } from '../glrenderer/GLCanvas';
import { Texture } from '../glrenderer/Texture';
import { NativeTexture } from '../glrenderer/NativeTexture';
import { GLRoot, GLRootOnGLIdleListener } from '../view/GLRoot';
import { Animation } from '../anim/Animation';
import { ImageWrapper } from './ImageWrapper';

const TAG = 'ImageTexture';
const DOMAIN = 0x0000;

/**
 * `com.hippo.lib.glview.image.ImageTexture` 的 ArkTS 等价实现。
 *
 * 一张大图按 **254/508 内容区 + 1/2 像素边框**切成 tile 网格（2 次幂纹理块），
 * 逐块上传，避免一次 `glTexImage2D` 超长阻塞（1244 行里最核心的设计）。
 *
 * ## 为什么分块（上游注释的量化依据）
 * 目标 60fps → 每帧 16ms；其中留给 tile 上传的预算 **4ms**（`UPLOAD_TILE_LIMIT`）。
 * 一次传完整张 4K 图会卡住一两帧，滚动时肉眼可见；分块后每帧最多传几块。
 *
 * ## 尺寸表（AOSP EhViewer 原值，不许自己调）
 * | 项 | 小 tile | 大 tile |
 * |---|---:|---:|
 * | 内容边长 | 254 | 508 |
 * | 边框 | 1 | 2 |
 * | 纹理边长（2 次幂） | 256 | 512 |
 *
 * ## 线程模型的平台差异（**本文件最大改动**）
 * | 上游 | 本实现 |
 * |---|---|
 * | `InfiniteThreadExecutor` + `PVLock` 跑 `AnimateRunnable` 无限循环 | `setTimeout` 自链式驱动（单 VM，无阻塞线程） |
 * | `Thread.sleep(delay)` 阻塞等待 GIF 帧间隔 | 定时器 `delay` 后触发下一帧（不阻塞渲染） |
 * | `AtomicBoolean` ×5 | 普通 boolean（单 VM 串行，无竞态） |
 * | `synchronized (mImage)` | 去掉（同上） |
 *
 * 语义等价点：`start()/stop()/isRunning()`、`mFrameDirty` 的"帧脏则重传"、
 * `recycle()` 的"忙碌则延迟释放"（`mNeedRelease`）全部保留。
 */
export class ImageTexture implements Texture {
  private static readonly TILE_SMALL: number = 0;
  private static readonly TILE_LARGE: number = 1;
  private static readonly SMALL_CONTENT_SIZE: number = 254;
  private static readonly SMALL_BORDER_SIZE: number = 1;
  private static readonly SMALL_TILE_SIZE: number =
    ImageTexture.SMALL_CONTENT_SIZE + 2 * ImageTexture.SMALL_BORDER_SIZE;
  private static readonly LARGE_CONTENT_SIZE: number = ImageTexture.SMALL_CONTENT_SIZE * 2;
  private static readonly LARGE_BORDER_SIZE: number = ImageTexture.SMALL_BORDER_SIZE * 2;
  private static readonly LARGE_TILE_SIZE: number =
    ImageTexture.LARGE_CONTENT_SIZE + 2 * ImageTexture.LARGE_BORDER_SIZE;
  private static readonly INIT_CAPACITY: number = 8;

  /** 每帧允许用于 tile 上传的毫秒数（60fps 下 16ms 里给 4ms）。 */
  private static readonly UPLOAD_TILE_LIMIT: number = 4;

  /** 空闲 tile 池（上游是两条链表头；这里用数组，语义相同）。 */
  private static sSmallFreeTiles: ImageTextureTile[] = [];
  private static sLargeFreeTiles: ImageTextureTile[] = [];

  private readonly mImage: ImageWrapper;
  private readonly mTiles: ImageTextureTile[];
  private readonly mWidth: number;
  private readonly mHeight: number;
  private readonly mOpaque: boolean;
  private readonly mSrcRect: RectF = new RectF();
  private readonly mDestRect: RectF = new RectF();

  private mRunning: boolean = false;
  private mRequestAnimation: boolean = false;
  private mFrameDirty: boolean = false;
  private mNeedRelease: boolean = false;
  private mReleased: boolean = false;
  private mImageBusy: boolean = false;
  private mUploadIndex: number = 0;

  /** 动画定时器句柄（ArcTS `setTimeout` 返回 number）。 */
  private mTimerId: number = -1;
  private mLastFrameTime: number = 0;
  private mLastDelay: number = -1;

  private mCallback: ImageTextureCallback | null = null;

  /** 构造前必须先调用 `image.obtain()`（上游契约）。 */
  constructor(image: ImageWrapper) {
    this.mImage = image;
    this.mWidth = image.getWidth();
    this.mHeight = image.getHeight();
    this.mOpaque = image.isOpaque();

    const list: ImageTextureTile[] = [];
    const width = this.mWidth;
    const height = this.mHeight;

    for (let x = 0; x < width; x += ImageTexture.LARGE_CONTENT_SIZE) {
      for (let y = 0; y < height; y += ImageTexture.LARGE_CONTENT_SIZE) {
        const w = Math.min(ImageTexture.LARGE_CONTENT_SIZE, width - x);
        const h = Math.min(ImageTexture.LARGE_CONTENT_SIZE, height - y);

        if (w <= ImageTexture.SMALL_CONTENT_SIZE) {
          const tile = ImageTexture.obtainSmallTile();
          tile.offsetX = x;
          tile.offsetY = y;
          tile.image = image;
          tile.setTileSize(ImageTexture.TILE_SMALL, w,
            Math.min(ImageTexture.SMALL_CONTENT_SIZE, h));
          tile.setOpaque(this.mOpaque);
          list.push(tile);

          const nextHeight = h - ImageTexture.SMALL_CONTENT_SIZE;
          if (nextHeight > 0) {
            const nextTile = ImageTexture.obtainSmallTile();
            nextTile.offsetX = x;
            nextTile.offsetY = y + ImageTexture.SMALL_CONTENT_SIZE;
            nextTile.image = image;
            nextTile.setTileSize(ImageTexture.TILE_SMALL, w, nextHeight);
            nextTile.setOpaque(this.mOpaque);
            list.push(nextTile);
          }
        } else if (h <= ImageTexture.SMALL_CONTENT_SIZE) {
          const tile = ImageTexture.obtainSmallTile();
          tile.offsetX = x;
          tile.offsetY = y;
          tile.image = image;
          tile.setTileSize(ImageTexture.TILE_SMALL,
            Math.min(ImageTexture.SMALL_CONTENT_SIZE, w), h);
          tile.setOpaque(this.mOpaque);
          list.push(tile);

          const nextWidth = w - ImageTexture.SMALL_CONTENT_SIZE;
          if (nextWidth > 0) {
            const nextTile = ImageTexture.obtainSmallTile();
            nextTile.offsetX = x + ImageTexture.SMALL_CONTENT_SIZE;
            nextTile.offsetY = y;
            nextTile.image = image;
            nextTile.setTileSize(ImageTexture.TILE_SMALL, nextWidth, h);
            nextTile.setOpaque(this.mOpaque);
            list.push(nextTile);
          }
        } else {
          const tile = ImageTexture.obtainLargeTile();
          tile.offsetX = x;
          tile.offsetY = y;
          tile.image = image;
          tile.setTileSize(ImageTexture.TILE_LARGE, w, h);
          tile.setOpaque(this.mOpaque);
          list.push(tile);
        }
      }
    }

    this.mTiles = list;
  }

  /** tile 归还到小尺寸池（`ImageTextureTile.free()` 调用）。 */
  static smallPoolPush(tile: ImageTextureTile): void {
    ImageTexture.sSmallFreeTiles.push(tile);
  }

  /** tile 归还到大尺寸池。 */
  static largePoolPush(tile: ImageTextureTile): void {
    ImageTexture.sLargeFreeTiles.push(tile);
  }

  private static obtainSmallTile(): ImageTextureTile {
    const pool = ImageTexture.sSmallFreeTiles;
    if (pool.length === 0) {
      return new ImageTextureTile();
    }
    const tile = pool.pop() as ImageTextureTile;
    tile.nextFree = false;
    return tile;
  }

  private static obtainLargeTile(): ImageTextureTile {
    const pool = ImageTexture.sLargeFreeTiles;
    if (pool.length === 0) {
      return new ImageTextureTile();
    }
    const tile = pool.pop() as ImageTextureTile;
    tile.nextFree = false;
    return tile;
  }

  /**
   * 把"源矩形"线性映射到"画布目标矩形"。
   * 上游注释里那幅 ASCII 图说的就是这件事：`output = x + (src - x0) * scale`。
   */
  private static mapRect(output: RectF, src: RectF, x0: number, y0: number, x: number, y: number,
    scaleX: number, scaleY: number): void {
    output.set(x + (src.left - x0) * scaleX, y + (src.top - y0) * scaleY,
      x + (src.right - x0) * scaleX, y + (src.bottom - y0) * scaleY);
  }

  getCallback(): ImageTextureCallback | null {
    return this.mCallback;
  }

  setCallback(cb: ImageTextureCallback | null): void {
    this.mCallback = cb;
  }

  invalidateSelf(): void {
    const callback = this.mCallback;
    if (callback !== null) {
      callback.invalidateImageTexture(this);
    }
  }

  // ==========================================================================
  // 动画（GIF 播放）—— 上游是阻塞线程，这里是定时器链
  // ==========================================================================

  start(): void {
    if (!this.mImageBusy) {
      this.mImageBusy = true;
    } else {
      this.mRequestAnimation = true;
      return;
    }

    const end = this.mReleased || this.mImage.isImageRecycled()
      || this.mNeedRelease || (!this.mImage.getAnimated()) || this.mRunning;

    this.mImageBusy = false;

    if (end) {
      return;
    }

    this.mRunning = true;
    this.scheduleNextFrame(0);
  }

  stop(): void {
    this.mRunning = false;
    this.mRequestAnimation = false;
    this.cancelTimer();
  }

  isRunning(): boolean {
    return this.mRunning;
  }

  private cancelTimer(): void {
    if (this.mTimerId >= 0) {
      clearTimeout(this.mTimerId);
      this.mTimerId = -1;
    }
  }

  /**
   * 定时器驱动的帧循环（替代上游 `AnimateRunnable.doRun()` 的 `for(;;) + Thread.sleep`）。
   *
   * 时间补偿与上游一致：`delay -= (now - lastTime) - lastDelay`，抵消定时器/渲染的抖动，
   * 保证 GIF 播放速度不随掉帧漂移。
   */
  private scheduleNextFrame(delay: number): void {
    this.mTimerId = setTimeout(() => {
      this.mTimerId = -1;
      this.animateTick();
    }, Math.max(0, delay));
  }

  private animateTick(): void {
    if (this.mReleased || this.mImage.isImageRecycled() || this.mNeedRelease) {
      this.mRunning = false;
      return;
    }
    if (!this.mRunning) {
      return;
    }

    if (!this.mImage.getAnimated()) {
      this.mRunning = false;
      return;
    }

    this.mImageBusy = true;
    this.mImage.start();
    let delay = this.mImage.getDelay();
    const now = Animation.uptimeMillis();
    if (this.mLastDelay !== -1) {
      delay -= (now - this.mLastFrameTime) - this.mLastDelay;
    }
    this.mLastFrameTime = now;
    this.mLastDelay = delay;
    this.mFrameDirty = true;
    this.invalidateSelf();
    this.mImageBusy = false;

    this.scheduleNextFrame(delay);
  }

  // ==========================================================================
  // 上传 / 绘制
  // ==========================================================================

  /** 上传下一块 tile；返回是否全部传完。 */
  uploadNextTile(canvas: GLCanvas): boolean {
    if (this.mUploadIndex === this.mTiles.length) {
      return true;
    }

    const next = this.mTiles[this.mUploadIndex++];

    // 可能已被 recycle（onGLIdle 与 recycle 的竞态，上游注释同一处理）
    if (next.image !== null) {
      next.updateContent(canvas);
    }
    return this.mUploadIndex === this.mTiles.length;
  }

  getWidth(): number {
    return this.mWidth;
  }

  getHeight(): number {
    return this.mHeight;
  }

  /** 帧脏时把全部 tile 标记为内容失效（下一帧重传）。 */
  private syncFrame(): void {
    if (this.mFrameDirty) {
      this.mFrameDirty = false;
      for (let i = 0; i < this.mTiles.length; i++) {
        this.mTiles[i].invalidateContent();
      }
    }
  }

  /** `draw(canvas,x,y)` 与 `draw(canvas,x,y,w,h)` 与 `draw(canvas,src,dst)` 三合一。 */
  draw(canvas: GLCanvas, a: number | RectF, b: number | RectF, w?: number, h?: number): void {
    if (typeof a === 'number') {
      const x = a;
      const y = b as number;
      const width = w === undefined ? this.mWidth : w;
      const height = h === undefined ? this.mHeight : h;
      this.drawScaled(canvas, x, y, width, height);
      return;
    }
    this.drawSub(canvas, a, b as RectF);
  }

  private drawScaled(canvas: GLCanvas, x: number, y: number, w: number, h: number): void {
    const src = this.mSrcRect;
    const dest = this.mDestRect;
    const scaleX = w / this.mWidth;
    const scaleY = h / this.mHeight;

    this.syncFrame();
    for (let i = 0; i < this.mTiles.length; i++) {
      const t = this.mTiles[i];
      src.set(0, 0, t.contentWidth, t.contentHeight);
      src.offset(t.offsetX, t.offsetY);
      ImageTexture.mapRect(dest, src, 0, 0, x, y, scaleX, scaleY);
      src.offset(t.borderSize - t.offsetX, t.borderSize - t.offsetY);
      canvas.drawTexture(t, src, dest);
    }
  }

  private drawSub(canvas: GLCanvas, source: RectF, target: RectF): void {
    const src = this.mSrcRect;
    const dest = this.mDestRect;
    const x0 = source.left;
    const y0 = source.top;
    const x = target.left;
    const y = target.top;
    const scaleX = target.width() / source.width();
    const scaleY = target.height() / source.height();

    this.syncFrame();
    for (let i = 0; i < this.mTiles.length; i++) {
      const t = this.mTiles[i];
      src.set(0, 0, t.contentWidth, t.contentHeight);
      src.offset(t.offsetX, t.offsetY);
      if (!src.intersect(source)) {
        continue;
      }
      ImageTexture.mapRect(dest, src, x0, y0, x, y, scaleX, scaleY);
      src.offset(t.borderSize - t.offsetX, t.borderSize - t.offsetY);
      canvas.drawTexture(t, src, dest);
    }
  }

  /** 混合色绘制（`from * (1-ratio) + to * ratio`），两个重载合一。 */
  drawMixed(canvas: GLCanvas, color: number, ratio: number, a: number | RectF,
    b: number | RectF, width?: number, height?: number): void {
    const src = this.mSrcRect;
    const dest = this.mDestRect;
    this.syncFrame();

    if (typeof a === 'number') {
      const x = a;
      const y = b as number;
      const w = width === undefined ? this.mWidth : width;
      const h = height === undefined ? this.mHeight : height;
      const scaleX = w / this.mWidth;
      const scaleY = h / this.mHeight;
      for (let i = 0; i < this.mTiles.length; i++) {
        const t = this.mTiles[i];
        src.set(0, 0, t.contentWidth, t.contentHeight);
        src.offset(t.offsetX, t.offsetY);
        ImageTexture.mapRect(dest, src, 0, 0, x, y, scaleX, scaleY);
        src.offset(t.borderSize - t.offsetX, t.borderSize - t.offsetY);
        canvas.drawMixed(t, color, ratio, src, dest);
      }
      return;
    }

    const source = a;
    const target = b as RectF;
    const x0 = source.left;
    const y0 = source.top;
    const x = target.left;
    const y = target.top;
    const scaleX = target.width() / source.width();
    const scaleY = target.height() / source.height();
    for (let i = 0; i < this.mTiles.length; i++) {
      const t = this.mTiles[i];
      src.set(0, 0, t.contentWidth, t.contentHeight);
      src.offset(t.offsetX, t.offsetY);
      if (!src.intersect(source)) {
        continue;
      }
      ImageTexture.mapRect(dest, src, x0, y0, x, y, scaleX, scaleY);
      src.offset(t.borderSize - t.offsetX, t.borderSize - t.offsetY);
      canvas.drawMixed(t, color, ratio, src, dest);
    }
  }

  isOpaque(): boolean {
    return this.mOpaque;
  }

  /** 是否所有 tile 已上传完（`Uploader` 据此决定是否续帧）。 */
  isReady(): boolean {
    return this.mUploadIndex === this.mTiles.length;
  }

  /**
   * 回收：停动画 → 归还全部 tile → 释放 Image 引用。
   * 上游用 `mNeedRelease` 处理"动画线程正在用图"的延迟释放；本实现是定时器，
   * 只需取消定时器后立即释放（`mImageBusy` 保留以维持状态机形状）。
   */
  recycle(): void {
    this.mRunning = false;
    this.cancelTimer();

    for (let i = 0; i < this.mTiles.length; i++) {
      this.mTiles[i].free();
    }

    if (!this.mImageBusy) {
      this.mImageBusy = true;
      if (!this.mReleased) {
        this.mImage.release();
        this.mReleased = true;
      }
      this.mImageBusy = false;
    } else {
      this.mNeedRelease = true;
    }
  }

}

/** `ImageTexture.Callback`。 */
export interface ImageTextureCallback {
  invalidateImageTexture(who: ImageTexture): void;
}

/** `ImageTexture.Uploader` 的具名类（ArkTS 不支持 `export class X { static readonly Y = ... }` 里再声明类）。 */
export class ImageTextureUploader implements GLRootOnGLIdleListener {
  private mTextures: ImageTexture[] = [];
  private readonly mGlRoot: GLRoot;
  private mIsQueued: boolean = false;

  constructor(glRoot: GLRoot) {
    this.mGlRoot = glRoot;
  }

  clear(): void {
    this.mTextures = [];
  }

  addTexture(t: ImageTexture): void {
    if (t.isReady()) {
      return;
    }
    this.mTextures.push(t);

    if (this.mIsQueued) {
      return;
    }
    this.mIsQueued = true;
    this.mGlRoot.addOnGLIdleListener(this);
  }

  onGLIdle(canvas: GLCanvas, renderRequested: boolean): boolean {
    let now = Animation.uptimeMillis();
    const dueTime = now + 4;   // UPLOAD_TILE_LIMIT
    let uploadedAny: boolean = false;
    while (now < dueTime && this.mTextures.length > 0) {
      const t = this.mTextures[0];
      uploadedAny = true;
      if (t.uploadNextTile(canvas)) {
        this.mTextures.shift();
      }
      now = Animation.uptimeMillis();
    }
    if (uploadedAny) {
      this.mGlRoot.requestRender();
    }
    this.mIsQueued = this.mTextures.length > 0;
    // 返回 true 表示"继续留在队列里"
    return this.mIsQueued;
  }
}

/**
 * 一块 tile。继承 `NativeTexture`（内容由 `Image.texImage` 直接推给纹理 id），
 * 尺寸规则见 `ImageTexture` 类注释的表。
 */
export class ImageTextureTile extends NativeTexture {
  offsetX: number = 0;
  offsetY: number = 0;
  image: ImageWrapper | null = null;
  nextFree: boolean = false;
  contentWidth: number = 0;
  contentHeight: number = 0;
  borderSize: number = 0;

  private mTileType: number = 0;

  setTileSize(tileType: number, width: number, height: number): void {
    this.mTileType = tileType;
    let tileSize: number;
    if (tileType === 0) {
      this.borderSize = 1;
      tileSize = 256;
    } else if (tileType === 1) {
      this.borderSize = 2;
      tileSize = 512;
    } else {
      throw new Error(`Not support tile type: ${tileType}`);
    }
    this.contentWidth = width;
    this.contentHeight = height;

    this.mWidth = width + 2 * this.borderSize;
    this.mHeight = height + 2 * this.borderSize;
    this.mTextureWidth = tileSize;
    this.mTextureHeight = tileSize;
  }

  /**
   * 把像素推给纹理。`init=true` 用满 tile 尺寸（分配整块），
   * `init=false` 只用内容+边框尺寸（局部更新）。
   */
  protected texImage(init: boolean): void {
    const image = this.image;
    if (image !== null && !image.isRecycled()) {
      let w: number;
      let h: number;
      if (init) {
        w = this.mTextureWidth;
        h = this.mTextureHeight;
      } else {
        w = this.mWidth;
        h = this.mHeight;
      }
      image.texImage(init, this.offsetX - this.borderSize, this.offsetY - this.borderSize, w, h);
    }
  }

  /** 内容失效并解绑 image（归还池时用）。 */
  invalidateTile(): void {
    this.invalidateContent();
    this.image = null;
  }

  /** 归还到对应尺寸的空闲池。 */
  free(): void {
    if (this.mTileType === 0) {
      this.invalidateTile();
      ImageTexture.smallPoolPush(this);
    } else if (this.mTileType === 1) {
      this.invalidateTile();
      ImageTexture.largePoolPush(this);
    } else {
      throw new Error(`Not support tile type: ${this.mTileType}`);
    }
  }
}
