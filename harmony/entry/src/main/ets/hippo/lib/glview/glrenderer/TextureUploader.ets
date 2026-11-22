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

import { GLCanvas } from './GLCanvas';
import { GLIdleHost, GLIdleListener } from './TiledTexture';
import { UploadedTexture } from './UploadedTexture';

/**
 * `com.hippo.lib.glview.glrenderer.TextureUploader` 的 ArkTS 等价实现（inventory S0360）。
 *
 * 语义：把「待上床的纹理」排进两个队列（前台/后台），在 GL 空闲回调里**每帧只上 1 张**
 * （`QUOTA_PER_FRAME = 1`），避免一次性上床造成掉帧。
 *
 * ## 五个必须照搬的行为
 *   1. `addFgTexture` / `addBgTexture` 时若 `isContentValid()` → **直接丢弃**（不用上）
 *   2. 入队时 `setIsUploading(true)`；出队时 **先** `setIsUploading(false)` 再 `updateContent`
 *   3. 出队后若 `isContentValid()`（别的线程已上过）→ **跳过且不消耗配额**（`continue`）
 *   4. **后台纹理上床后立刻 `draw(canvas, 0, 0)`** —— 上游注释：首次绘制还要额外时间，
 *      滚动时新列出现会卡一下，所以先画一次「热身」
 *   5. `onGLIdle` 里：前台先上；**只要前台消耗了配额就 `requestRender()`**（有变化就要重画）；
 *      剩余配额给后台
 *
 * ## 与 `TiledTextureUploader` 的差别（别混）
 *   - `TiledTextureUploader`：**时间片** 4ms，一个纹理的多块瓦片分帧上
 *   - `TextureUploader`：**配额** 1 张/帧，一张纹理一次上完
 */
export class TextureUploader implements GLIdleListener {
  static readonly INIT_CAPACITY: number = 64;
  /** 每帧上床配额。 */
  static readonly QUOTA_PER_FRAME: number = 1;

  private mFgTextures: UploadedTexture[] = [];
  private mBgTextures: UploadedTexture[] = [];
  private readonly mGLRoot: GLIdleHost;
  private mIsQueued: boolean = false;

  constructor(root: GLIdleHost) {
    this.mGLRoot = root;
  }

  /** 对齐 `clear()`：两个队列里的纹理都**取消上传标记**（否则它们会永远显示"上传中"）。 */
  clear(): void {
    for (let i = 0; i < this.mFgTextures.length; i++) {
      this.mFgTextures[i].setIsUploading(false);
    }
    this.mFgTextures = [];
    for (let i = 0; i < this.mBgTextures.length; i++) {
      this.mBgTextures[i].setIsUploading(false);
    }
    this.mBgTextures = [];
  }

  /** 对齐 `queueSelfIfNeed()`：只在第一次入队时挂到 GL 空闲回调。 */
  private queueSelfIfNeed(): void {
    if (this.mIsQueued) {
      return;
    }
    this.mIsQueued = true;
    this.mGLRoot.addOnGLIdleListener(this);
  }

  /** 对齐 `addBgTexture(t)`。 */
  addBgTexture(t: UploadedTexture): void {
    if (t.isContentValid()) {
      return;
    }
    this.mBgTextures.push(t);
    t.setIsUploading(true);
    this.queueSelfIfNeed();
  }

  /** 对齐 `addFgTexture(t)`。 */
  addFgTexture(t: UploadedTexture): void {
    if (t.isContentValid()) {
      return;
    }
    this.mFgTextures.push(t);
    t.setIsUploading(true);
    this.queueSelfIfNeed();
  }

  /**
   * 对齐 `upload(canvas, deque, uploadQuota, isBackground)`：返回**剩余配额**。
   * 注意「内容已有效」的分支不消耗配额（上游 `continue` 在 `--uploadQuota` 之前）。
   */
  private upload(canvas: GLCanvas, deque: UploadedTexture[], uploadQuota: number,
    isBackground: boolean): number {
    let quota: number = uploadQuota;
    while (quota > 0) {
      if (deque.length === 0) {
        break;
      }
      const t: UploadedTexture = deque.shift() as UploadedTexture;
      t.setIsUploading(false);
      if (t.isContentValid()) {
        continue;
      }
      t.updateContent(canvas);
      // 后台纹理先画一次，避免首次出现在屏幕上时卡顿
      if (isBackground) {
        t.draw(canvas, 0, 0);
      }
      --quota;
    }
    return quota;
  }

  /** 对齐 `onGLIdle(canvas, renderRequested)`：返回 true 表示队列非空、别摘掉监听。 */
  onGLIdle(canvas: GLCanvas, renderRequested: boolean): boolean {
    let uploadQuota: number = TextureUploader.QUOTA_PER_FRAME;
    uploadQuota = this.upload(canvas, this.mFgTextures, uploadQuota, false);
    if (uploadQuota < TextureUploader.QUOTA_PER_FRAME) {
      this.mGLRoot.requestRender();
    }
    this.upload(canvas, this.mBgTextures, uploadQuota, true);
    this.mIsQueued = this.mFgTextures.length > 0 || this.mBgTextures.length > 0;
    return this.mIsQueued;
  }

  /** 前台队列长度（测试用）。 */
  fgSize(): number {
    return this.mFgTextures.length;
  }

  /** 后台队列长度（测试用）。 */
  bgSize(): number {
    return this.mBgTextures.length;
  }

  /** 是否已挂到 GL 空闲回调（测试用）。 */
  isQueued(): boolean {
    return this.mIsQueued;
  }
}
