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

import { BasicTexture } from './BasicTexture';
import { GLCanvas } from './GLCanvas';

/**
 * `com.hippo.lib.glview.glrenderer.ExtTexture` 的 ArkTS 等价实现（inventory S0339）。
 *
 * 语义（上游注释直译）：内容来自**外部纹理**（如相机/OES 纹理）。
 * 绘制前必须先 `setSize()`。
 *
 * 三处照搬：
 *   1. 构造时就用 `canvas.getGLId().generateTexture()` 拿 id —— **不走 UploadedTexture**，
 *      因为没有任何位图要上床
 *   2. `onBind` 里若未 loaded → `setTextureParameters` + 标记 `STATE_LOADED`
 *   3. `yield()` **空实现**：上游注释「we cannot free the texture because we have no backup」
 *      —— 外部纹理一旦释放就再也拿不回来
 */
export class ExtTexture extends BasicTexture {
  private readonly mTarget: number;

  constructor(canvas: GLCanvas, target: number) {
    super(null, 0, BasicTexture.STATE_UNLOADED);
    const glId = canvas.getGLId();
    this.mId = glId.generateTexture();
    this.mTarget = target;
  }

  private uploadToCanvas(canvas: GLCanvas): void {
    canvas.setTextureParameters(this);
    this.setAssociatedCanvas(canvas);
    this.mState = BasicTexture.STATE_LOADED;
  }

  onBind(canvas: GLCanvas): boolean {
    if (!this.isLoaded()) {
      this.uploadToCanvas(canvas);
    }
    return true;
  }

  getTarget(): number {
    return this.mTarget;
  }

  /** **恒 true**（外部纹理按定义就是不透明的，上游如此）。 */
  isOpaque(): boolean {
    return true;
  }

  /**
   * 空实现：没有位图备份，无法重建（照搬上游注释的语义）。
   * **注意**：yield 在 ArkTS 里是**保留字**（生成器），所以方法名改用 yieldTexture；
   * 上游调用点仅 BasicTexture.yield() 内部使用，这里同语义改名。
   */
  yieldTexture(): void {
    // we cannot free the texture because we have no backup.
  }
}
