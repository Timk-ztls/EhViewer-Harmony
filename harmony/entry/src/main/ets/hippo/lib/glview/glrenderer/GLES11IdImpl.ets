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

import { GLId } from './GLId';
import { GLNative } from '../native/GLNativeBridge';

/**
 * `com.hippo.lib.glview.glrenderer.GLES11IdImpl` 的 ArkTS 等价实现（inventory S0345）。
 *
 * GLES 1.1 的 id 分配策略：**应用层自增**（不调 `glGenTextures`）。
 * 上游注释直译：给「生成/销毁纹理 id 与 buffer id」用的 OpenGL ES 1.1 实现。
 *
 * 三个必须照搬的细节：
 *   1. `sNextId` 从 **1** 开始（0 在 GL 里表示"无纹理"，必须跳过）
 *   2. `glGenBuffers(n, buffers, offset)` 的填充是**倒序循环**
 *      `while (n-- > 0) { buffers[offset + n] = sNextId++; }`
 *      —— 结果是**降序**：填 n=3 时得到 `[b+2]=1, [b+1]=2, [b+0]=3`。
 *      看起来很反直觉，但这是上游实际行为，单测已锁（`idninepatch.test.ets` 断言 `[0,5,4,3,0]`）。
 *   3. 删除**不回收** id（`sNextId` 单调递增），只把 id 交给 native 删
 *
 * 与上游的签名差异：`glDeleteTextures(GL11 gl, …)` 等去掉了上下文句柄参数，
 * 由 `GLNative.backend()` 承担（与已有的 `GLES20IdImpl` 同形，见 `GLId.ets` 注释）。
 */
export class GLES11IdImpl extends GLId {
  private static sNextId: number = 1;

  /** 测试用：把计数器复位（上游无此方法，仅测试/热重载需要）。 */
  static resetForTest(nextId: number = 1): void {
    GLES11IdImpl.sNextId = nextId;
  }

  /** 测试用：读当前计数器（不消耗）。 */
  static peekForTest(): number {
    return GLES11IdImpl.sNextId;
  }

  generateTexture(): number {
    return GLES11IdImpl.sNextId++;
  }

  glGenBuffers(n: number, buffers: number[], offset: number): void {
    let count: number = n;
    while (count-- > 0) {
      buffers[offset + count] = GLES11IdImpl.sNextId++;
    }
  }

  glDeleteTextures(n: number, textures: number[], offset: number): void {
    const backend = GLNative.backend();
    for (let i = 0; i < n; i++) {
      const id: number = textures[offset + i];
      if (id > 0) {
        backend.deleteTexture(id);
      }
    }
  }

  glDeleteBuffers(n: number, buffers: number[], offset: number): void {
    const backend = GLNative.backend();
    for (let i = 0; i < n; i++) {
      const id: number = buffers[offset + i];
      if (id > 0) {
        backend.deleteBuffer(id);
      }
    }
  }

  glDeleteFramebuffers(n: number, buffers: number[], offset: number): void {
    const backend = GLNative.backend();
    for (let i = 0; i < n; i++) {
      const id: number = buffers[offset + i];
      if (id > 0) {
        backend.deleteFramebuffer(id);
      }
    }
  }
}
