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
import { GLCanvas } from './GLCanvas';
import { GLId } from './GLId';
import { BasicTexture } from './BasicTexture';
import { GLConst } from '../native/GLConst';

const TAG = 'RawTexture';
const DOMAIN = 0x0000;

/**
 * `com.hippo.lib.glview.glrenderer.RawTexture` 的 ArkTS 等价实现。
 *
 * 用途：渲染目标（`beginRenderTarget` 把内容画进这块纹理）与直接由外部像素填充的纹理。
 * 关键差异（上游注释就写了）：`yield()` **不释放**资源 —— 因为内容没有备份，
 * 释放后无法重建。这意味着 Surface 重建后这类纹理的内容会丢，上游同样如此。
 *
 * 上游 `GL11.GL_RGBA` / `GL11.GL_UNSIGNED_BYTE` 常量来自 GLES1 头；这里统一用
 * `GLConst`（值与原常量完全一致，见 `native/GLConst.ets`）。
 */
export class RawTexture extends BasicTexture {
  private readonly mOpaque: boolean;
  private mIsFlipped: boolean = false;

  constructor(width: number, height: number, opaque: boolean) {
    super(null, 0, BasicTexture.STATE_UNLOADED);
    this.mOpaque = opaque;
    this.setSize(width, height);
  }

  isOpaque(): boolean {
    return this.mOpaque;
  }

  isFlippedVertically(): boolean {
    return this.mIsFlipped;
  }

  setIsFlippedVertically(isFlipped: boolean): void {
    this.mIsFlipped = isFlipped;
  }

  /** 由 `GLCanvas.beginRenderTarget()` 调用：生成纹理 id 并按尺寸分配 GL 存储。 */
  prepare(canvas: GLCanvas): void {
    const glId: GLId = canvas.getGLId();
    this.mId = glId.generateTexture();
    canvas.initializeTextureSize(this, GLConst.GL_RGBA, GLConst.GL_UNSIGNED_BYTE);
    canvas.setTextureParameters(this);
    this.mState = BasicTexture.STATE_LOADED;
    this.setAssociatedCanvas(canvas);
  }

  onBind(_canvas: GLCanvas): boolean {
    if (this.isLoaded()) {
      return true;
    }
    hilog.warn(DOMAIN, TAG, 'lost the content due to context change');
    return false;
  }

  /**
   * 与上游一致：**不释放**（无内容备份，释放即永久丢失）。
   * 方法名从上游的 `yield` 改为 `releaseTemporarily`（`yield` 是 ES 保留字，ArkTS 拒绝）。
   */
  releaseTemporarily(): void {
  }

  getTarget(): number {
    return GLConst.GL_TEXTURE_2D;
  }
}
