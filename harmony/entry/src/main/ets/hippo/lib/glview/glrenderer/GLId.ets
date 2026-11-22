/*
 * Copyright (C) 2012 The Android Open Source Project
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

/**
 * `com.hippo.lib.glview.glrenderer.GLId` 的 ArkTS 等价实现。
 *
 * 上游签名带 `javax.microedition.khronos.opengles.GL11` / `GL11ExtensionPack` 参数，
 * 那是 GLES1 的上下文对象；GLES20 实现（`GLES20IdImpl`）根本不读这两个参数。
 * 鸿蒙侧没有 GLES1 概念（`GLES11Canvas` 是否移植见后续 MR），因此：
 * - 保留完整的 5 个方法名与语义（GL 资源 ID 的生成/删除）；
 * - 去掉两个无用的上下文参数，改由实现类内部持有的 native 后端处理。
 *
 * 这是**签名级差异**，登记在 MR 的"上游 → 鸿蒙"对照表里。
 */
export abstract class GLId {
  /** 等价 `glGenTextures(1, &id, 0)`。 */
  abstract generateTexture(): number;

  /** 等价 `glGenBuffers(n, buffers, offset)`。 */
  abstract glGenBuffers(n: number, buffers: number[], offset: number): void;

  /** 等价 `glDeleteTextures(n, textures, offset)`。 */
  abstract glDeleteTextures(n: number, textures: number[], offset: number): void;

  /** 等价 `glDeleteBuffers(n, buffers, offset)`。 */
  abstract glDeleteBuffers(n: number, buffers: number[], offset: number): void;

  /** 等价 `glDeleteFramebuffers(n, buffers, offset)`。 */
  abstract glDeleteFramebuffers(n: number, buffers: number[], offset: number): void;
}
