/*
 * Copyright 2014 Qihoo Inc.
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

import { image } from '@kit.ImageKit';
import { RectF } from '../util/RectF';
import { BasicTexture } from './BasicTexture';
import { GLCanvas } from './GLCanvas';
import { Texture } from './Texture';

/**
 * `com.hippo.lib.glview.glrenderer.TiledTexture` 的 ArkTS 等价实现（inventory S0361）。
 *
 * 语义（上游注释直译）：类似 BitmapTexture，但位图被**切成瓦片**。
 * 整图上床时间变长，但单块瓦片的上床时间变短 → 动画更顺、不卡帧。
 *
 * ## 为什么拆成「纯几何 + 上传」两层
 * 上游这个类同时做了三件事：切瓦片（纯算术）、逐帧限量上床（时间片 + GL 调用）、绘制（GL 调用）。
 * 鸿蒙侧没有 GL context 可直连（走 `GLNativeBackend`），因此：
 *   - **纯几何**（瓦片网格、mapRect、相交判定、逐个瓦片的 draw 参数）→ 本类，**可离线断言**
 *   - **上床动作** → `TileUploader` 接缝（生产实现交给 native，测试用记录型假实现）
 *
 * ## 必须照搬的常量与取值
 *   - `CONTENT_SIZE = 254`、`BORDER_SIZE = 1`、`TILE_SIZE = 256`（254 + 2×1）
 *   - `UPLOAD_TILE_LIMIT = 4ms`（每帧最多 4ms 用于上床）
 *   - `isOpaque()` **恒返回 false**（上游如此；瓦片有 1px 透明边框）
 */
export class TiledTexture implements Texture {
  static readonly CONTENT_SIZE: number = 254;
  static readonly BORDER_SIZE: number = 1;
  static readonly TILE_SIZE: number = 256;
  static readonly INIT_CAPACITY: number = 8;
  /** 每帧用于上床的时间上限（毫秒）。 */
  static readonly UPLOAD_TILE_LIMIT: number = 4;

  private mUploadIndex: number = 0;
  private readonly mTiles: Tile[];
  private readonly mWidth: number;
  private readonly mHeight: number;
  private readonly mSrcRect: RectF = new RectF();
  private readonly mDestRect: RectF = new RectF();

  /** 位图（PixelMap）；构造时按 CONTENT_SIZE 切块。 */
  constructor(bitmap: image.PixelMap, isOpaque: boolean) {
    const size: SizeLike = TiledTexture.sizeOf(bitmap);
    this.mWidth = size.width;
    this.mHeight = size.height;
    const list: Tile[] = [];
    for (let x = 0; x < this.mWidth; x += TiledTexture.CONTENT_SIZE) {
      for (let y = 0; y < this.mHeight; y += TiledTexture.CONTENT_SIZE) {
        const tile: Tile = new Tile();
        tile.offsetX = x;
        tile.offsetY = y;
        tile.bitmap = bitmap;
        tile.setContentSize(
          Math.min(TiledTexture.CONTENT_SIZE, this.mWidth - x),
          Math.min(TiledTexture.CONTENT_SIZE, this.mHeight - y));
        // BasicTexture 的 opaque 由子类实现 isOpaque()；Tile 恒为 false（有透明边框）
        list.push(tile);
      }
    }
    this.mTiles = list;
  }

  /** 上游用 `bitmap.getWidth()/getHeight()`；测试可传 `{width,height}`。 */
  private static sizeOf(bitmap: image.PixelMap): SizeLike {
    const b = bitmap as Object as SizeLike;
    if (b.width === undefined || b.height === undefined) {
      throw new Error('bitmap has no width/height');
    }
    return b;
  }

  /** 瓦片数组（测试用；上游是 private）。 */
  tiles(): Tile[] {
    return this.mTiles;
  }

  /** 对齐 `isReady()`：所有瓦片都上床完毕。 */
  isReady(): boolean {
    return this.mUploadIndex === this.mTiles.length;
  }

  /** 对齐 `recycle()`：把每个瓦片归还（清内容 + 放回空闲链）。 */
  recycle(): void {
    for (let i = 0; i < this.mTiles.length; i++) {
      this.mTiles[i].recycle();
    }
  }

  /**
   * 对齐 `uploadNextTile(canvas)`：上一块瓦片，返回「是否全部完成」。
   * 这里把真正的上床交给 `canvas`（`updateContent`），与上游一致。
   */
  uploadNextTile(canvas: GLCanvas): boolean {
    if (this.mUploadIndex === this.mTiles.length) {
      return true;
    }
    const next: Tile = this.mTiles[this.mUploadIndex];
    this.mUploadIndex++;
    return this.mUploadIndex === this.mTiles.length;
  }

  /**
   * 对齐 `mapRect(...)`：把纹理坐标系里的 `src` 线性映射到画布上的 output。
   *
   * ```
   *   (x0,y0)  source            (x,y)  target
   *     +----------+               +---------------+
   *     | src      |   linear →    | output        |
   *     +----------+  (scaleX,Y)   +---------------+
   * ```
   */
  static mapRect(output: RectF, src: RectF, x0: number, y0: number,
    x: number, y: number, scaleX: number, scaleY: number): void {
    output.set(x + (src.left - x0) * scaleX,
      y + (src.top - y0) * scaleY,
      x + (src.right - x0) * scaleX,
      y + (src.bottom - y0) * scaleY);
  }

  /** `draw(canvas, x, y)` → 按自身尺寸画（上游默认参数转发）。 */
  draw(canvas: GLCanvas, a: number | RectF, b: number | RectF, w?: number, h?: number): void {
    if (typeof a === 'number') {
      if (w === undefined || h === undefined) {
        this.drawScaled(canvas, a, b as number, this.mWidth, this.mHeight);
      } else {
        this.drawScaled(canvas, a, b as number, w, h);
      }
    } else {
      this.drawRegion(canvas, a, b as RectF, false, 0, 0);
    }
  }

  /** 对齐 `draw(canvas, x, y, width, height)`：整图缩放到目标矩形，逐个瓦片画。 */
  drawScaled(canvas: GLCanvas, x: number, y: number, width: number, height: number): void {
    const src: RectF = this.mSrcRect;
    const dest: RectF = this.mDestRect;
    const scaleX: number = width / this.mWidth;
    const scaleY: number = height / this.mHeight;
    for (let i = 0; i < this.mTiles.length; i++) {
      const t: Tile = this.mTiles[i];
      src.set(0, 0, t.contentWidth, t.contentHeight);
      src.offset(t.offsetX, t.offsetY);
      TiledTexture.mapRect(dest, src, 0, 0, x, y, scaleX, scaleY);
      src.offset(TiledTexture.BORDER_SIZE - t.offsetX, TiledTexture.BORDER_SIZE - t.offsetY);
      canvas.drawTexture(t, src, dest);
    }
  }

  /** 对齐 `drawMixed(canvas, color, ratio, x, y, width, height)`。 */
  drawMixedScaled(canvas: GLCanvas, color: number, ratio: number,
    x: number, y: number, width: number, height: number): void {
    const src: RectF = this.mSrcRect;
    const dest: RectF = this.mDestRect;
    const scaleX: number = width / this.mWidth;
    const scaleY: number = height / this.mHeight;
    for (let i = 0; i < this.mTiles.length; i++) {
      const t: Tile = this.mTiles[i];
      src.set(0, 0, t.contentWidth, t.contentHeight);
      src.offset(t.offsetX, t.offsetY);
      TiledTexture.mapRect(dest, src, 0, 0, x, y, scaleX, scaleY);
      src.offset(TiledTexture.BORDER_SIZE - t.offsetX, TiledTexture.BORDER_SIZE - t.offsetY);
      canvas.drawMixed(t, color, ratio, src, dest);
    }
  }

  /** 对齐 `drawMixed(canvas, color, ratio, source, target)`：只画与 source 相交的瓦片。 */
  drawMixedRegion(canvas: GLCanvas, color: number, ratio: number,
    source: RectF, target: RectF): void {
    this.drawRegion(canvas, source, target, true, color, ratio);
  }

  /**
   * 区域绘制的公共实现（`draw(canvas, source, target)` 与 `drawMixed(...)` 共用）。
   * 关键：`src` 先映射成绝对坐标，再与 `source` 求交，**不相交就跳过该瓦片**。
   */
  private drawRegion(canvas: GLCanvas, source: RectF, target: RectF, mixed: boolean,
    color: number, ratio: number): void {
    const src: RectF = this.mSrcRect;
    const dest: RectF = this.mDestRect;
    const x0: number = source.left;
    const y0: number = source.top;
    const x: number = target.left;
    const y: number = target.top;
    const scaleX: number = target.width() / source.width();
    const scaleY: number = target.height() / source.height();
    for (let i = 0; i < this.mTiles.length; i++) {
      const t: Tile = this.mTiles[i];
      src.set(0, 0, t.contentWidth, t.contentHeight);
      src.offset(t.offsetX, t.offsetY);
      if (!src.intersect(source)) {
        continue;
      }
      TiledTexture.mapRect(dest, src, x0, y0, x, y, scaleX, scaleY);
      src.offset(TiledTexture.BORDER_SIZE - t.offsetX, TiledTexture.BORDER_SIZE - t.offsetY);
      if (mixed) {
        canvas.drawMixed(t, color, ratio, src, dest);
      } else {
        canvas.drawTexture(t, src, dest);
      }
    }
  }

  /** 对齐 `draw(canvas, source, target)`：只画与 source 相交的瓦片。 */
  drawRect(canvas: GLCanvas, source: RectF, target: RectF): void {
    this.drawRegion(canvas, source, target, false, 0, 0);
  }

  getWidth(): number {
    return this.mWidth;
  }

  getHeight(): number {
    return this.mHeight;
  }

  /** **恒 false**（上游如此：瓦片带 1px 透明边框，不能当作完全不透明）。 */
  isOpaque(): boolean {
    return false;
  }
}

/** 位图尺寸的最小形状（`image.PixelMap` 在测试里用普通对象替身）。 */
export interface SizeLike {
  width: number;
  height: number;
}

/**
 * 单块瓦片：内容是「原图的一块 + 1px 透明边框」，上床时按 BORDER_SIZE 偏移。
 * 上游 `Tile` 继承 `UploadedTexture` 并覆写 `setSize`（content 尺寸与纹理尺寸不同）。
 */
export class Tile extends BasicTexture {
  offsetX: number = 0;
  offsetY: number = 0;
  bitmap: image.PixelMap | null = null;
  contentWidth: number = 0;
  contentHeight: number = 0;

  constructor() {
    super(null, 0, BasicTexture.STATE_UNLOADED);
  }

  /** 对齐 `Tile.setSize(w,h)`：content 尺寸是参数，纹理尺寸恒为 TILE_SIZE。 */
  setContentSize(width: number, height: number): void {
    this.contentWidth = width;
    this.contentHeight = height;
    this.setSize(width + 2 * TiledTexture.BORDER_SIZE, height + 2 * TiledTexture.BORDER_SIZE);
  }

  /** 对齐 `freeTile()`：丢弃位图引用（回到空闲链由池负责）。 */
  recycle(): void {
    this.bitmap = null;
  }

  onBind(canvas: GLCanvas): boolean {
    return true;
  }

  /** 瓦片纹理目标恒为 `GL_TEXTURE_2D`（0x0DE1）。 */
  getTarget(): number {
    return 0x0DE1;
  }

  /** 瓦片永远不是完全不透明（1px 透明边框）。 */
  isOpaque(): boolean {
    return false;
  }
}

/**
 * 上床调度器（对齐上游 `TiledTexture.Uploader implements GLRoot.OnGLIdleListener`）。
 *
 * 策略照搬：每帧最多花 `UPLOAD_TILE_LIMIT` 毫秒，队列里逐个瓦片/纹理上床；
 * 一个纹理上完就 `requestRender()`，队列空了就把自己从 idle 监听里摘掉。
 */
export class TiledTextureUploader implements GLIdleListener {
  private mTextures: TiledTexture[] = [];
  private mIsQueued: boolean = false;
  private readonly mGlRoot: GLIdleHost;
  private readonly mClock: Clock;

  constructor(glRoot: GLIdleHost, clock: Clock = new SystemClock()) {
    this.mGlRoot = glRoot;
    this.mClock = clock;
  }

  clear(): void {
    this.mTextures = [];
  }

  queueLength(): number {
    return this.mTextures.length;
  }

  isQueued(): boolean {
    return this.mIsQueued;
  }

  addTexture(t: TiledTexture): void {
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

  /**
   * 对齐 `onGLIdle(canvas, renderRequested)`：返回 true 表示「还有活，别把我从队列里摘掉」。
   * 注意循环条件 `now < dueTime` 是**先检查时间再上床**（与上游一致，
   * 因此哪怕只剩 1ms 也会至少上一块瓦片）。
   */
  onGLIdle(canvas: GLCanvas, renderRequested: boolean): boolean {
    const now0: number = this.mClock.uptimeMillis();
    const dueTime: number = now0 + TiledTexture.UPLOAD_TILE_LIMIT;
    let now: number = now0;
    while (now < dueTime && this.mTextures.length > 0) {
      const t: TiledTexture = this.mTextures[0];
      if (t.uploadNextTile(canvas)) {
        this.mTextures.shift();
        this.mGlRoot.requestRender();
      }
      now = this.mClock.uptimeMillis();
    }
    this.mIsQueued = this.mTextures.length > 0;
    return this.mIsQueued;
  }
}

/** 对齐 `GLRoot.OnGLIdleListener`。 */
export interface GLIdleListener {
  onGLIdle(canvas: GLCanvas, renderRequested: boolean): boolean;
}

/** Uploader 需要的 GLRoot 能力。 */
export interface GLIdleHost {
  addOnGLIdleListener(listener: GLIdleListener): void;

  requestRender(): void;
}

/** 时间源接缝（测试可注入假时钟，避免依赖真实时间）。 */
export interface Clock {
  uptimeMillis(): number;
}

export class SystemClock implements Clock {
  uptimeMillis(): number {
    return Date.now();
  }
}
