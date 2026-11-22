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

import { RectF } from '../util/RectF';
import { GLMath } from '../util/GLMath';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { GLCanvas } from './GLCanvas';
import { Texture } from './Texture';

const TAG = 'BasicTexture';
const DOMAIN = 0x0000;

/**
 * `com.hippo.lib.glview.glrenderer.BasicTexture` 的 ArkTS 等价实现。
 *
 * 一个 BasicTexture 就是一块真实的 GL 纹理，`mState` 记录它的数据是否已在 GL 内存里。
 *
 * ## 与上游的两处必要差异（都在 MR 对照表登记）
 *
 * 1. **没有 `finalize()`**：上游靠 Java 终结器在对象被 GC 时调 `recycle()` 释放 GL 资源。
 *    ArkTS 无终结器（`FinalizationRegistry` 在 API 20 的 d.ts 中不存在，已实测），
 *    因此资源释放时机改为**显式生命周期**：
 *    - `GLRootView.onSurfaceDestroyed` → `BasicTexture.yieldAllTextures()`
 *    - 页面销毁 → 各 Texture 的 `recycle()`
 *    同时 `sAllTextures` 从 `WeakHashMap` 改为强引用 `Set`：宁可短暂多占内存，
 *    也绝不能让 GC 在渲染线程不知情的情况下把纹理对象收走（那会造成 use-after-free
 *    语义的错乱而不是内存泄漏，代价更大）。
 *
 * 2. **`inFinalizer()` 恒返回 false**：没有终结器就没有"正在终结"的状态。
 *    上游用它决定能否安全调 `Bitmap.recycle()`；鸿蒙侧 PixelMap 释放走
 *    `release()`，且全部由显式路径调用，不依赖这个标志。
 */
export abstract class BasicTexture implements Texture {
  protected static readonly UNSPECIFIED: number = -1;

  protected static readonly STATE_UNLOADED: number = 0;
  protected static readonly STATE_LOADED: number = 1;
  protected static readonly STATE_ERROR: number = -1;

  /** 单边超过 4096 会告警：上游同阈值（部分 GPU 的 GL_MAX_TEXTURE_SIZE 就是 4096）。 */
  private static readonly MAX_TEXTURE_SIZE: number = 4096;

  protected mId: number = -1;
  protected mState: number = BasicTexture.STATE_UNLOADED;
  protected mWidth: number = BasicTexture.UNSPECIFIED;
  protected mHeight: number = BasicTexture.UNSPECIFIED;
  protected mTextureWidth: number = 0;
  protected mTextureHeight: number = 0;
  private mHasBorder: boolean = false;
  protected mCanvasRef: GLCanvas | null = null;

  /** 上游 `WeakHashMap<BasicTexture, Object>`；理由见类注释第 1 条。 */
  private static readonly sAllTextures: Set<BasicTexture> = new Set<BasicTexture>();

  /**
   * 上游构造器 `BasicTexture(GLCanvas, int id, int state)`。
   * ArkTS 无重载，`BasicTexture()` 的等价调用是 `super(null, 0, STATE_UNLOADED)`。
   */
  protected constructor(canvas: GLCanvas | null, id: number, state: number) {
    this.setAssociatedCanvas(canvas);
    this.mId = id;
    this.mState = state;
    BasicTexture.sAllTextures.add(this);
  }

  protected setAssociatedCanvas(canvas: GLCanvas | null): void {
    this.mCanvasRef = canvas;
  }

  /**
   * 设置内容尺寸。GL 纹理尺寸必须是 2 的幂，而内容尺寸可以更小。
   * 注意 `nextPowerOf2` 的入参检查：宽高 <= 0 时直接置 0，不抛错（上游三元表达式）。
   */
  setSize(width: number, height: number): void {
    this.mWidth = width;
    this.mHeight = height;
    this.mTextureWidth = width > 0 ? GLMath.nextPowerOf2(width) : 0;
    this.mTextureHeight = height > 0 ? GLMath.nextPowerOf2(height) : 0;
    if (this.mTextureWidth > BasicTexture.MAX_TEXTURE_SIZE
      || this.mTextureHeight > BasicTexture.MAX_TEXTURE_SIZE) {
      hilog.warn(DOMAIN, TAG, 'texture is too large: %{public}d x %{public}d',
        this.mTextureWidth, this.mTextureHeight);
    }
  }

  isFlippedVertically(): boolean {
    return false;
  }

  getId(): number {
    return this.mId;
  }

  getWidth(): number {
    return this.mWidth;
  }

  getHeight(): number {
    return this.mHeight;
  }

  /** 向上取整到 2 的幂的宽度。 */
  getTextureWidth(): number {
    return this.mTextureWidth;
  }

  /** 向上取整到 2 的幂的高度。 */
  getTextureHeight(): number {
    return this.mTextureHeight;
  }

  /**
   * 是否有一圈 1px 透明边框。
   * 原因（上游注释）：ES 没有 GL_CLAMP，只能 `GL_CLAMP_TO_EDGE`，
   * 边缘 texel 会被拉伸；加一圈透明边后混合结果正确，且缩略图可在关闭混合时绘制。
   */
  hasBorder(): boolean {
    return this.mHasBorder;
  }

  protected setBorder(hasBorder: boolean): void {
    this.mHasBorder = hasBorder;
  }

  /** `draw(canvas, x, y)`。 */
  draw(canvas: GLCanvas, a: number | RectF, b: number | RectF, w?: number, h?: number): void {
    if (typeof a === 'number') {
      if (w === undefined || h === undefined) {
        canvas.drawTexture(this, a, b as number, this.getWidth(), this.getHeight());
      } else {
        canvas.drawTexture(this, a, b as number, w, h);
      }
    } else {
      canvas.drawTexture(this, a, b as RectF);
    }
  }

  /** 绑定前回调，必须保证数据已上传到 GL 内存。返回 false 表示失败（画不出东西）。 */
  abstract onBind(canvas: GLCanvas): boolean;

  /** 该纹理的 GL target（`GL_TEXTURE_2D` 或 `GL_TEXTURE_EXTERNAL_OES`）。 */
  abstract getTarget(): number;

  abstract isOpaque(): boolean;

  isLoaded(): boolean {
    return this.mState === BasicTexture.STATE_LOADED;
  }

  /** 该纹理不再被使用时调用，释放全部资源。 */
  recycle(): void {
    BasicTexture.sAllTextures.delete(this);
    this.freeResource();
  }

  /**
   * 暂时不使用时调用，释放部分资源（上游 `yield()`）。
   *
   * **方法名不叫 `yield`**：`yield` 是 ES 保留字，ArkTS 解析器直接拒绝把它当标识符
   * （报 `'yield' is not allowed`），这与"生成器函数"无关 —— 上游这里是普通方法，
   * 只是名字撞了保留字。改名 `releaseTemporarily` 后语义更明确：
   * 临时让出 GPU 资源、之后可重新上传；永久释放走 `recycle()`。
   * 调用点由 `yieldAllTextures()` 内部改为 `t.releaseTemporarily()`，其余不变。
   */
  releaseTemporarily(): void {
    this.freeResource();
  }

  private freeResource(): void {
    const canvas = this.mCanvasRef;
    if (canvas !== null && this.mId !== -1) {
      canvas.unloadTexture(this);
      this.mId = -1; // 不要再释放第二次
    }
    this.mState = BasicTexture.STATE_UNLOADED;
    this.setAssociatedCanvas(null);
  }

  /** 上游靠终结器判断；ArkTS 无终结器，恒 false（见类注释第 2 条）。 */
  static inFinalizer(): boolean {
    return false;
  }

  /** surface 销毁 / 应用切后台时调用：全部卸载，但保留对象以便重建。 */
  static yieldAllTextures(): void {
    BasicTexture.sAllTextures.forEach((t: BasicTexture) => {
      t.releaseTemporarily();
    });
  }

  /** GL 上下文丢失（Surface 重建）：置为未加载并解绑 canvas，下次绘制时重新上传。 */
  static invalidateAllTextures(): void {
    BasicTexture.sAllTextures.forEach((t: BasicTexture) => {
      t.mState = BasicTexture.STATE_UNLOADED;
      t.setAssociatedCanvas(null);
    });
  }

  /** 已登记纹理数量（单测/泄漏排查用，上游无此 API）。 */
  static trackedCount(): number {
    return BasicTexture.sAllTextures.size;
  }

  /** 清空登记表（单测用）。 */
  static clearTracking(): void {
    BasicTexture.sAllTextures.clear();
  }
}
