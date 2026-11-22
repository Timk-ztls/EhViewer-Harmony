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
import { Rect } from '../util/Rect';
import { RectF } from '../util/RectF';
import { MathUtils } from '../../yorozuya/MathUtils';
import { GLCanvas } from './GLCanvas';
import { NinePatchChunk } from './NinePatchChunk';
import { ResourceContextLike, ResourceTexture } from './ResourceTexture';

/**
 * `com.hippo.lib.glview.glrenderer.NinePatchTexture` 的 ArkTS 等价实现（inventory S0354）。
 *
 * 语义：由 **.9.png 资源**支撑的纹理。`getPaddings()` 给出内边距、`getNinePatchChunk()`
 * 给出拉伸布局数据。
 *
 * ## 拆法与 TiledTexture 一致：纯几何 + GL 提交
 *   - **纯几何**（`stretch` 拉伸段分配、`prepareVertexData` 顶点/索引生成）→ 可离线断言
 *   - **GL 提交**（`uploadBuffer` / `drawMesh` / `deleteBuffer`）→ 交给 `GLCanvas`
 *
 * ## 四处必须照搬
 *   1. `onGetBitmap()` 里若 `mBitmap != null` **直接返回**（不重复解码）
 *   2. chunk 解析失败/为空 → 抛 `RuntimeException("invalid nine-patch image: <resId>")`
 *   3. `draw()` 里 **`w == 0 || h == 0` 直接什么都不画**（上游 `if (w != 0 && h != 0)`）
 *   4. 未 loaded 时先 `mInstanceCache.clear()`（尺寸变了，旧实例作废）
 *
 * `NinePatchInstance` 的索引生成规则（上游注释原样保留语义）：
 * 3×3 时 16 个顶点、22 个索引，**每个「透明色区」额外多 2 个索引**（当前最多 1 个）。
 */
export class NinePatchTexture extends ResourceTexture {
  private mChunk: NinePatchChunk | null = null;
  private readonly mInstanceCache: SmallCache<NinePatchInstance> =
    new SmallCache<NinePatchInstance>(NinePatchTexture.CACHE_SIZE);

  /** 实例缓存容量（上游 `SmallCache.CACHE_SIZE = 16`）。 */
  static readonly CACHE_SIZE: number = 16;

  constructor(context: NinePatchResourceContextLike, resId: number) {
    super(context, resId);
  }

  protected onGetBitmap(): image.PixelMap {
    if (this.mBitmap !== null) {
      return this.mBitmap;
    }
    const bitmap: image.PixelMap = this.mContext.decode(this.mResId);
    this.mBitmap = bitmap;
    const size = NinePatchTexture.sizeOf(bitmap);
    this.setSize(size.width, size.height);
    const ctx = this.mContext as NinePatchResourceContextLike;
    const chunkData: ArrayBuffer | null = ctx.decodeNinePatchChunk(this.mResId);
    this.mChunk = chunkData === null ? null : NinePatchChunk.deserialize(chunkData);
    if (this.mChunk === null) {
      throw new Error('RuntimeException: invalid nine-patch image: ' + this.mResId);
    }
    return bitmap;
  }

  private static sizeOf(bitmap: image.PixelMap): SizeLike2 {
    const b = bitmap as Object as SizeLike2;
    if (b.width === undefined || b.height === undefined) {
      throw new Error('bitmap has no width/height');
    }
    return b;
  }

  /** 对齐 `getPaddings()`：chunk 未解析时先解码。 */
  getPaddings(): Rect {
    if (this.mChunk === null) {
      this.onGetBitmap();
    }
    return (this.mChunk as NinePatchChunk).mPaddings;
  }

  /** 对齐 `getNinePatchChunk()`。 */
  getNinePatchChunk(): NinePatchChunk {
    if (this.mChunk === null) {
      this.onGetBitmap();
    }
    return this.mChunk as NinePatchChunk;
  }

  /** 对齐 `findInstance(canvas, w, h)`：key = `(w << 16) | h`。 */
  private findInstance(canvas: GLCanvas, w: number, h: number): NinePatchInstance {
    let key: number = w;
    key = (key << 16) | h;
    let instance: NinePatchInstance | null = this.mInstanceCache.get(key);
    if (instance === null) {
      instance = new NinePatchInstance(this, w, h);
      const removed: NinePatchInstance | null = this.mInstanceCache.put(key, instance);
      if (removed !== null) {
        removed.recycle(canvas);
      }
    }
    return instance;
  }

  /** 绘制：**`w`/`h` 任一为 0 就什么都不做**（上游如此）。 */
  drawScaled(canvas: GLCanvas, x: number, y: number, w: number, h: number): void {
    if (!this.isLoaded()) {
      this.mInstanceCache.clear();
    }
    if (w !== 0 && h !== 0) {
      this.findInstance(canvas, w, h).draw(canvas, this, x, y);
    }
  }

  draw(canvas: GLCanvas, a: number | RectF, b: number | RectF, w?: number, h?: number): void {
    if (typeof a === 'number') {
      this.drawScaled(canvas, a, b as number, w as number, h as number);
    } else {
      // 上游只重写了 `draw(canvas,x,y,w,h)`；矩形形态退回父类实现
      super.draw(canvas, a, b);
    }
  }

  /** 对齐 `recycle()`：先回收自身，再把所有实例的 buffer 还给画布。 */
  recycle(): void {
    super.recycle();
    const canvas: GLCanvas | null = this.mCanvasRef;
    if (canvas === null) {
      return;
    }
    const n: number = this.mInstanceCache.size();
    for (let i = 0; i < n; i++) {
      const instance: NinePatchInstance | null = this.mInstanceCache.valueAt(i);
      if (instance !== null) {
        instance.recycle(canvas);
      }
    }
    this.mInstanceCache.clear();
  }

  /** 测试用：当前缓存条目数。 */
  cacheSize(): number {
    return this.mInstanceCache.size();
  }

  /** 测试用：仅用于构造实例（不做 GL 提交）。 */
  instanceFor(w: number, h: number): NinePatchInstance {
    return new NinePatchInstance(this, w, h);
  }
}

/** 位图尺寸的最小形状。 */
export interface SizeLike2 {
  width: number;
  height: number;
}

/**
 * nine-patch 资源上下文：比 `ResourceContextLike` 多一个「取 chunk 字节」的能力
 * （Android 是 `bitmap.getNinePatchChunk()`）。
 */
export interface NinePatchResourceContextLike extends ResourceContextLike {
  decodeNinePatchChunk(resId: number): ArrayBuffer | null;
}

/**
 * 某个目标尺寸下的 nine-patch 实例：预算好顶点/UV/索引，绘制时一次 `drawMesh`。
 *
 * 顶点布局（上游注释原样）：
 * ```
 * (0) (1) (2) (3)
 *  |  /|  /|  /|
 *  | / | / | / |
 * (4) (5) (6) (7)
 *  | \ | \ | \ |
 *  |  \|  \|  \|
 * (8) (9) (A) (B)
 *  |  /|  /|  /|
 *  | / | / | / |
 * (C) (D) (E) (F)
 *
 * index: 04152637B6A5948C9DAEBF
 * ```
 */
export class NinePatchInstance {
  /** 16 个顶点 × 2 个分量。 */
  static readonly VERTEX_BUFFER_SIZE: number = 16 * 2;
  /** 22 个索引 + 每个透明区 2 个。 */
  static readonly INDEX_BUFFER_SIZE: number = 22 + 2;

  private mXyBuffer: Float32Array | null = null;
  private mUvBuffer: Float32Array | null = null;
  private mIndexBuffer: Uint8Array | null = null;
  private mXyBufferName: number = -1;
  private mUvBufferName: number = -1;
  private mIndexBufferName: number = -1;
  private mIdxCount: number = 0;

  constructor(tex: NinePatchTexture, width: number, height: number) {
    const chunk: NinePatchChunk = tex.getNinePatchChunk();
    if (width <= 0 || height <= 0) {
      throw new Error('RuntimeException: invalid dimension');
    }
    // 上游：只处理最常见的 1 个拉伸段的 3×3 图
    if (chunk.mDivX.length !== 2 || chunk.mDivY.length !== 2) {
      throw new Error('RuntimeException: unsupported nine patch');
    }
    const divX: number[] = new Array<number>(4);
    const divY: number[] = new Array<number>(4);
    const divU: number[] = new Array<number>(4);
    const divV: number[] = new Array<number>(4);
    const nx: number = NinePatchInstance.stretch(divX, divU, chunk.mDivX, tex.getWidth(), width);
    const ny: number = NinePatchInstance.stretch(divY, divV, chunk.mDivY, tex.getHeight(), height);
    this.prepareVertexData(divX, divY, divU, divV, nx, ny, chunk.mColor);
  }

  /**
   * 对齐 `stretch(x, u, div, source, target)`：把 nine-patch 的**固定段**按原样放、
   * **拉伸段**按比例分配。返回分段数（去掉了长度为 0 的段）。
   *
   * 两个细节照搬：
   *   - 固定段两端各留 **0.5px**（`+0.5f` / `-0.5f`），避免采样到相邻段
   *   - `u` 用 `textureSize = nextPowerOf2(source)` 归一化，并 clamp 到 `textureBound`
   */
  static stretch(x: number[], u: number[], div: number[], source: number, target: number): number {
    const textureSize: number = MathUtils.nextPowerOf2(source);
    const textureBound: number = source / textureSize;
    let stretch: number = 0;
    for (let i = 0; i < div.length; i += 2) {
      stretch += div[i + 1] - div[i];
    }
    let remaining: number = target - source + stretch;
    let lastX: number = 0;
    let lastU: number = 0;
    x[0] = 0;
    u[0] = 0;
    for (let i = 0; i < div.length; i += 2) {
      // fixed segment
      x[i + 1] = lastX + (div[i] - lastU) + 0.5;
      u[i + 1] = Math.min((div[i] + 0.5) / textureSize, textureBound);
      // stretchy segment
      const partU: number = div[i + 1] - div[i];
      const partX: number = remaining * partU / stretch;
      remaining -= partX;
      stretch -= partU;
      lastX = x[i + 1] + partX;
      lastU = div[i + 1];
      x[i + 2] = lastX - 0.5;
      u[i + 2] = Math.min((lastU - 0.5) / textureSize, textureBound);
    }
    // the last fixed segment
    x[div.length + 1] = target;
    u[div.length + 1] = textureBound;
    // remove segments with length 0
    let last: number = 0;
    for (let i = 1; i < div.length + 2; i++) {
      if ((x[i] - x[last]) < 1) {
        continue;
      }
      x[++last] = x[i];
      u[last] = u[i];
    }
    return last + 1;
  }

  private prepareVertexData(x: number[], y: number[], u: number[], v: number[],
    nx: number, ny: number, color: number[] | null): void {
    let pntCount: number = 0;
    const xy: number[] = new Array<number>(NinePatchInstance.VERTEX_BUFFER_SIZE);
    const uv: number[] = new Array<number>(NinePatchInstance.VERTEX_BUFFER_SIZE);
    for (let j = 0; j < ny; j++) {
      for (let i = 0; i < nx; i++) {
        const xIndex: number = (pntCount++) << 1;
        const yIndex: number = xIndex + 1;
        xy[xIndex] = x[i];
        xy[yIndex] = y[j];
        uv[xIndex] = u[i];
        uv[yIndex] = v[j];
      }
    }
    let idxCount: number = 1;
    let isForward: boolean = false;
    const index: number[] = new Array<number>(NinePatchInstance.INDEX_BUFFER_SIZE);
    for (let row = 0; row < ny - 1; row++) {
      --idxCount;
      isForward = !isForward;
      let start: number;
      let end: number;
      let inc: number;
      if (isForward) {
        start = 0;
        end = nx;
        inc = 1;
      } else {
        start = nx - 1;
        end = -1;
        inc = -1;
      }
      for (let col = start; col !== end; col += inc) {
        const k: number = row * nx + col;
        if (col !== start && color !== null) {
          let colorIdx: number = row * (nx - 1) + col;
          if (isForward) {
            colorIdx--;
          }
          if (color[colorIdx] === NinePatchChunk.TRANSPARENT_COLOR) {
            index[idxCount] = index[idxCount - 1];
            ++idxCount;
            index[idxCount++] = k & 0xFF;
          }
        }
        index[idxCount++] = k & 0xFF;
        index[idxCount++] = (k + nx) & 0xFF;
      }
    }
    this.mIdxCount = idxCount;
    this.mXyBuffer = new Float32Array(pntCount * 2);
    this.mUvBuffer = new Float32Array(pntCount * 2);
    this.mIndexBuffer = new Uint8Array(idxCount);
    for (let i = 0; i < pntCount * 2; i++) {
      this.mXyBuffer[i] = xy[i];
      this.mUvBuffer[i] = uv[i];
    }
    for (let i = 0; i < idxCount; i++) {
      this.mIndexBuffer[i] = index[i] & 0xFF;
    }
  }

  /** 顶点坐标（测试用）。 */
  xy(): Float32Array | null {
    return this.mXyBuffer;
  }

  /** 纹理坐标（测试用）。 */
  uv(): Float32Array | null {
    return this.mUvBuffer;
  }

  /** 索引（测试用）。 */
  indices(): Uint8Array | null {
    return this.mIndexBuffer;
  }

  /** 索引个数（测试用）。 */
  indexCount(): number {
    return this.mIdxCount;
  }

  private prepareBuffers(canvas: GLCanvas): void {
    this.mXyBufferName = canvas.uploadBufferFloat(this.mXyBuffer as Float32Array);
    this.mUvBufferName = canvas.uploadBufferFloat(this.mUvBuffer as Float32Array);
    this.mIndexBufferName = canvas.uploadBufferByte(this.mIndexBuffer as Uint8Array);
    // These buffers are never used again.
    this.mXyBuffer = null;
    this.mUvBuffer = null;
    this.mIndexBuffer = null;
  }

  draw(canvas: GLCanvas, tex: NinePatchTexture, x: number, y: number): void {
    if (this.mXyBufferName === -1) {
      this.prepareBuffers(canvas);
    }
    canvas.drawMesh(tex, x, y, this.mXyBufferName, this.mUvBufferName,
      this.mIndexBufferName, this.mIdxCount);
  }

  recycle(canvas: GLCanvas): void {
    if (this.mXyBuffer === null) {
      canvas.deleteBuffer(this.mXyBufferName);
      canvas.deleteBuffer(this.mUvBufferName);
      canvas.deleteBuffer(this.mIndexBufferName);
      this.mXyBufferName = -1;
    }
  }
}

/**
 * 极小的缓存（对齐上游 `SmallCache`）：**线性查找** + 「取用一次就前移一位」的策略。
 *
 * 两个照搬点：
 *   1. 满了之后 `put` **覆盖最后一项**并把它返回（调用方负责 recycle）
 *   2. `get` 命中时，**只有 `mCount > CACHE_SIZE/2` 且不是第 0 项**才前移一位
 *      （前移太频繁反而打乱热数据）
 */
export class SmallCache<V> {
  private readonly mKey: number[];
  private readonly mValue: (V | null)[];
  private mCount: number = 0;
  private readonly mCapacity: number;
  private readonly mStartMove: number;

  constructor(capacity: number) {
    this.mCapacity = capacity;
    this.mStartMove = Math.floor(capacity / 2);
    this.mKey = new Array<number>(capacity).fill(0);
    this.mValue = new Array<V | null>(capacity).fill(null);
  }

  put(key: number, value: V): V | null {
    if (this.mCount === this.mCapacity) {
      const old: V | null = this.mValue[this.mCapacity - 1];
      this.mKey[this.mCapacity - 1] = key;
      this.mValue[this.mCapacity - 1] = value;
      return old;
    }
    this.mKey[this.mCount] = key;
    this.mValue[this.mCount] = value;
    this.mCount++;
    return null;
  }

  get(key: number): V | null {
    for (let i = 0; i < this.mCount; i++) {
      if (this.mKey[i] === key) {
        // D-048：先取值再前移。上游 SmallCache.get 在 swap 之后 `return mValue[i]`，
        // 那时 mValue[i] 已经是「被换位上来的邻居」，不是命中的值 —— 会返回错误实例。
        // 触发条件：mCount > CACHE_SIZE/2 且命中项不是第 0 项。
        const hit: V | null = this.mValue[i];
        if (this.mCount > this.mStartMove && i > 0) {
          const tmpKey: number = this.mKey[i];
          this.mKey[i] = this.mKey[i - 1];
          this.mKey[i - 1] = tmpKey;
          const tmpValue: V | null = this.mValue[i];
          this.mValue[i] = this.mValue[i - 1];
          this.mValue[i - 1] = tmpValue;
        }
        return hit;
      }
    }
    return null;
  }

  clear(): void {
    for (let i = 0; i < this.mCount; i++) {
      this.mValue[i] = null;
    }
    this.mCount = 0;
  }

  size(): number {
    return this.mCount;
  }

  valueAt(i: number): V | null {
    return this.mValue[i];
  }

  keyAt(i: number): number {
    return this.mKey[i];
  }
}
