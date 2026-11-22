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
import { BasicTexture } from './BasicTexture';
import { GLConst } from '../native/GLConst';

const TAG = 'NativeTexture';
const DOMAIN = 0x0000;

/**
 * `com.hippo.lib.glview.glrenderer.NativeTexture` 的 ArkTS 等价实现。
 *
 * 与 `UploadedTexture` 的区别：内容不是通过 `PixelMap` 上传，而是由子类在
 * `texImage(init)` 里**直接**把像素推给已知的纹理 id（上游靠 JNI 的
 * `nativeTexImage`，本项目的 `Image.texImage` 走 `setTexImageBridge` 注入的 NAPI）。
 *
 * `init=true` 表示首次分配（`glTexImage2D`，会用满 2 次幂的 tile 尺寸），
 * `init=false` 表示局部更新（`glTexSubImage2D`，只覆盖内容区 + 边框）。
 * 这个区分是 `ImageTexture.Tile` 的分块上传关键：首次要分配整块 tile，之后只更新脏区。
 */
export abstract class NativeTexture extends BasicTexture {
  /** 上游无显式构造器（隐式 super()），ArkTS 必须显式转发给 `BasicTexture(canvas,id,state)`。 */
  constructor() {
    super(null, 0, BasicTexture.STATE_UNLOADED);
  }

  private mContentValid: boolean = true;
  private mOpaque: boolean = true;

  invalidateContent(): void {
    this.mContentValid = false;
  }

  /** 等价上游 `GLES20.glGetError()` 检查；本项目经 `GLNative.getErrorCode()`。 */
  static checkError(): void {
    // 逐命令查错会让 NAPI 往返翻倍，这里只在显式调用时查（上游也是显式调用）
    // 具体实现见 GLCanvas.checkError()；本方法保留调用点
  }

  /** 子类实现：把像素推给当前绑定的纹理。 */
  protected abstract texImage(init: boolean): void;

  private uploadToCanvas(canvas: GLCanvas): void {
    // 生成 id
    this.mId = canvas.getGLId().generateTexture();

    // 纹理参数
    canvas.setTextureParameters(this);

    // 首次分配：glTexImage2D（子类内部按 init=true 用满 tile 尺寸）
    this.bindTexture(canvas);
    this.texImage(true);

    this.setAssociatedCanvas(canvas);
    this.mState = BasicTexture.STATE_LOADED;
    this.mContentValid = true;
  }

  updateContent(canvas: GLCanvas): void {
    if (!this.isLoaded()) {
      this.uploadToCanvas(canvas);
    } else if (!this.mContentValid) {
      // 局部更新：glTexSubImage2D
      this.bindTexture(canvas);
      this.texImage(false);
      this.mContentValid = true;
    }
  }

  /**
   * 绑当前纹理（上游 `glBindTexture(getTarget(), mId)`）。
   *
   * 顺序陷阱：`texImage()` 是由 `Image.texImage` 经 NAPI **立即**推像素的，
   * 而 BIND_TEXTURE 是命令流里的延迟命令。若不先冲刷，就会"上传像素→绑纹理"，
   * 像素传到上一块纹理上。`bindTextureForUpload` 就是为此加的：录制 bind + 立即执行。
   */
  private bindTexture(canvas: GLCanvas): void {
    canvas.bindTextureForUpload(this);
  }

  /** GPU 内容是否有效。 */
  isContentValid(): boolean {
    return this.isLoaded() && this.mContentValid;
  }

  onBind(canvas: GLCanvas): boolean {
    this.updateContent(canvas);
    return this.isContentValid();
  }

  getTarget(): number {
    return GLConst.GL_TEXTURE_2D;
  }

  setOpaque(isOpaque: boolean): void {
    this.mOpaque = isOpaque;
  }

  isOpaque(): boolean {
    return this.mOpaque;
  }

  /** 供子类读取 GL 错误（调试用）。 */
  protected logGlError(): void {
    hilog.error(DOMAIN, TAG, 'GL error detected in NativeTexture subclass');
  }
}
