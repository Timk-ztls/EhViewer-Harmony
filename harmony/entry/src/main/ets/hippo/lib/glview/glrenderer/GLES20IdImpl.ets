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

import { GLId } from './GLId';
import { GLConst } from '../native/GLConst';
import { GLErr, GLNative } from '../native/GLNativeBridge';

/**
 * `com.hippo.lib.glview.glrenderer.GLES20IdImpl` 的 ArkTS 等价实现。
 *
 * 职责：把 GLES20 的 `glGenTextures` / `glGenBuffers` / `glDelete*` 包装成
 * 可复用的 ID 管理接口。鸿蒙侧这些调用全部跨到 native（`GLNativeBackend`）。
 *
 * 与上游的签名差异：`glDeleteTextures(GL11 gl, ...)` 等去掉了 GL11 上下文参数
 * （见 `GLId.ets` 注释）。
 */
export class GLES20IdImpl extends GLId {
  generateTexture(): number {
    const id = GLNative.backend().genTexture();
    if (id >= 0) {
      return id;
    }
    return -1;
  }

  glGenBuffers(n: number, buffers: number[], offset: number): void {
    const backend = GLNative.backend();
    for (let i = 0; i < n; i++) {
      const id = backend.genBuffer(GLConst.GL_ARRAY_BUFFER);
      if (offset + i < buffers.length) {
        buffers[offset + i] = id;
      }
    }
  }

  glDeleteTextures(n: number, textures: number[], offset: number): void {
    const backend = GLNative.backend();
    for (let i = 0; i < n; i++) {
      const id = textures[offset + i];
      if (id > 0) {
        backend.deleteTexture(id);
      }
    }
  }

  glDeleteBuffers(n: number, buffers: number[], offset: number): void {
    const backend = GLNative.backend();
    for (let i = 0; i < n; i++) {
      const id = buffers[offset + i];
      if (id > 0) {
        backend.deleteBuffer(id);
      }
    }
  }

  glDeleteFramebuffers(n: number, buffers: number[], offset: number): void {
    const backend = GLNative.backend();
    for (let i = 0; i < n; i++) {
      const id = buffers[offset + i];
      if (id > 0) {
        if (backend.deleteFramebuffer(id) !== GLErr.OK) {
          // 与上游一致：只在 hilog 里留痕，不抛（删除失败不阻断渲染）
          break;
        }
      }
    }
  }
}
