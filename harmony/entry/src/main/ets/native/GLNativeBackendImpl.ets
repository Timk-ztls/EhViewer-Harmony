/*
 * Copyright 2024 Hippo Seven
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
import {
  nativeInit,
  nativeSetSurface,
  nativeDestroySurface,
  nativeReplay,
  nativePresent,
  nativeGenTexture,
  nativeDeleteTexture,
  nativeTexImage2D,
  nativeTexSubImage2D,
  nativeTexSubImage2DFill,
  nativeGenBuffer,
  nativeBufferDataF32,
  nativeBufferDataU8,
  nativeDeleteBuffer,
  nativeGenFramebuffer,
  nativeUnbindFramebuffer,
  nativeDeleteFramebuffer,
  nativeGlGetError,
  nativeGetString,
  nativeTexImageRegion
} from 'libnative-lib.so';
import { GLErr, GLNative, GLNativeBackend, TexRegionUploader }
  from '../hippo/lib/glview/native/GLNativeBridge';

/**
 * `GLNativeBackend` 的 NAPI 实现（**本项目新增，上游无对应物**）。
 *
 * 把 gl-render 的 19 个后端方法转发到 `libnative-lib.so` 的 19 个 `native*` 导出
 * （符号清单见 `ets/native/index.d.ts` 的 C-1 段）。
 *
 * ## 为什么这个文件存在（一个静默失败的故事）
 * 在它出现之前：`GLNative.register()` **从未被调用** → `GLNative.backend()` 抛 `NOT_READY`
 * → `GLRootViewController.ensureCanvas()` 恒返回 false → 画布永不创建 →
 * **首帧永远黑屏，不崩、不报错，只有一行 warn**。
 * 符号审计（19 个接口方法 ↔ 21 个 native 导出，映射 0 缺失，但没人实现接口）才暴露它。
 * 所以本文件的核心不是"转发"，而是**注册**：`registerGLBackend()`。
 *
 * ## 谁调用 `registerGLBackend()`
 * `GLRootViewController` 的构造函数（第一次创建控制器时）。幂等：重复调用只注册一次。
 *
 * ## 语义细节（这些只有 gl-render 侧知道，native-image 不该猜）
 * 1. `replay()` 只执行不上屏；`present()` 单独 swap —— 一帧内 `flushPending()` 会多次
 *    `replay()`，若其中任何一次 swap 就会撕裂。
 * 2. `texSubImage2DFill` 的第 8 参在 native 声明里叫 `argb`，语义 **0xAARRGGBB**
 *    （我传 0 = 全透明；非零时 native 按 a,r,g,b 拆，落盘字节序 r,g,b,a，不预乘）。
 * 3. `genBuffer(target)` 的 target 由 native 记录，`bufferDataF32/U8` 内部据此绑回，
 *    调用方不需要自己 bind。
 * 4. `getErrorCode()` / `getString(what)` 分别对应 `nativeGlGetError()` / `nativeGetString()`。
 *
 * ## 错误处理
 * 全部转发返回值**原样透传**（native 返回 `GLErr` 数值 0..6，与 ArkTS 侧 `GLErr` 枚举同值）。
 * 这里不做"错误码翻译"，避免两层映射漂移；只对 `gen*` 类返回 -1 的情况保持原样。
 */
class GLNativeBackendImpl implements GLNativeBackend {
  init(): GLErr {
    return nativeInit() as GLErr;
  }

  setSurface(width: number, height: number): GLErr {
    return nativeSetSurface(width, height) as GLErr;
  }

  destroySurface(): GLErr {
    return nativeDestroySurface() as GLErr;
  }

  replay(cmds: Float32Array): GLErr {
    return nativeReplay(cmds) as GLErr;
  }

  present(): GLErr {
    return nativePresent() as GLErr;
  }

  genTexture(): number {
    return nativeGenTexture();
  }

  deleteTexture(id: number): GLErr {
    return nativeDeleteTexture(id) as GLErr;
  }

  texImage2D(id: number, width: number, height: number, format: number, type: number,
    pixelMap: image.PixelMap): GLErr {
    // index.d.ts 声明为 object（NAPI 侧按 PixelMap 句柄解析），此处原样传递
    return nativeTexImage2D(id, width, height, format, type, pixelMap) as GLErr;
  }

  texSubImage2D(id: number, xOffset: number, yOffset: number, width: number, height: number,
    format: number, type: number, pixelMap: image.PixelMap): GLErr {
    return nativeTexSubImage2D(id, xOffset, yOffset, width, height, format, type,
      pixelMap) as GLErr;
  }

  texSubImage2DFill(id: number, xOffset: number, yOffset: number, width: number, height: number,
    format: number, type: number, rgba: number): GLErr {
    // 第 8 参语义见类注释第 2 条：0xAARRGGBB
    return nativeTexSubImage2DFill(id, xOffset, yOffset, width, height, format, type,
      rgba) as GLErr;
  }

  genBuffer(target: number): number {
    return nativeGenBuffer(target);
  }

  bufferDataF32(id: number, data: Float32Array): GLErr {
    return nativeBufferDataF32(id, data) as GLErr;
  }

  bufferDataU8(id: number, data: Uint8Array): GLErr {
    return nativeBufferDataU8(id, data) as GLErr;
  }

  deleteBuffer(id: number): GLErr {
    return nativeDeleteBuffer(id) as GLErr;
  }

  genFramebuffer(): number {
    return nativeGenFramebuffer();
  }

  unbindFramebuffer(): GLErr {
    return nativeUnbindFramebuffer() as GLErr;
  }

  deleteFramebuffer(id: number): GLErr {
    return nativeDeleteFramebuffer(id) as GLErr;
  }

  getErrorCode(): number {
    return nativeGlGetError();
  }

  getString(what: number): string {
    return nativeGetString(what);
  }
}

/**
 * `TexRegionUploader` 的 NAPI 实现：把 `ImageTexture` 的 tile 区域贴到纹理。
 *
 * native 侧语义（native-image 实现 + 26 条 C 断言）：
 * - dst 负偏移 → 裁掉并让 src **同量正向平移**（1:1 不缩放）
 * - dst 超纹理右/下 → 裁掉超出部分
 * - 源再按 pixelMap 实际尺寸裁一次
 * - 完全在纹理外 → `GLErr.OK`，**无写入但也不是错误**
 * - `init=true` → 先 `glTexImage2D(GL_RGBA, texW, texH, null)` 分配，再走同一段 blit
 */
class GLTexRegionUploaderImpl implements TexRegionUploader {
  texImageRegion(id: number, init: boolean, pixelMap: image.PixelMap, srcX: number, srcY: number,
    srcW: number, srcH: number, dstX: number, dstY: number, texW: number, texH: number): GLErr {
    return nativeTexImageRegion(id, init, pixelMap, srcX, srcY, srcW, srcH,
      dstX, dstY, texW, texH) as GLErr;
  }
}

let sRegistered: boolean = false;

/**
 * 注册 NAPI 后端（幂等）。由 `GLRootViewController` 构造函数调用一次。
 *
 * 之所以要显式注册而不是模块加载时自动注册：`GLNative` 是纯 ArkTS 契约层，
 * 让它在 import 阶段就依赖 `.so` 会让所有引用它的单测/工具链被迫加载 native。
 * 注册点放在"真正要用 GL 的地方"，边界最清楚。
 */
export function registerGLBackend(): void {
  if (sRegistered) {
    return;
  }
  GLNative.register(new GLNativeBackendImpl());
  // 区域 blit 能力（ImageTexture 分块上传依赖它）
  GLNative.registerRegionUploader(new GLTexRegionUploaderImpl());
  sRegistered = true;
}

/** 诊断：是否已注册（联调时确认"黑屏是不是因为没注册"）。 */
export function isGLBackendRegistered(): boolean {
  return sRegistered;
}
