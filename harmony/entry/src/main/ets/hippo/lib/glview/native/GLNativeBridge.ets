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

/**
 * gl-render ↔ native GL 的边界契约（ArkTS 侧定义）。
 *
 * ## 为什么是这个形状
 *
 * 上游 `GLES20Canvas` 直接调 `android.opengl.GLES20`（进程内静态绑定，零跨界成本）。
 * 鸿蒙上 ArkTS 拿不到 GL 上下文（API 20 SDK 无 `@ohos.webgl`，实测见 MR），
 * 必须把 GL 调用打到 native（XComponent + EGL/GLES3，DEVIATIONS D-007 方案 A）。
 * 若逐条 GL 调用跨界，一帧 300 个 quad × 约 20 次调用 ≈ 6000 次 NAPI 往返，
 * 按每次 5µs 估 30ms+，滚动必然掉帧。因此采用**命令流 + 每帧一次 replay**：
 *
 *  - ArkTS 侧（`GLES20Canvas`）保持 1:1 的方法结构与状态机，把每条 GL 调用编码成
 *    命令字写入 `Float32Array`；
 *  - native 侧 `nativeReplay()` 一次遍历执行。
 *
 * ## 命令流编码（必须在 CONTRACTS.md 与 native 实现对齐）
 *
 * 单缓冲 `Float32Array`，每条记录：`[opcode, argc, arg0, arg1, ...]`。
 * 整数参数（纹理 id、program handle、attrib location、GL 枚举值）以 float 承载，
 * 精确上限 2^24 = 16,777,216，远大于任何 GL 句柄，无精度损失。
 * 命令严格按提交顺序执行（GL 是状态机，顺序即语义）。
 *
 * 每个 opcode 都标注它的上游对应调用，见 `GLCommand` 枚举注释。
 *
 * ## 谁实现谁
 * - 本文件（`glview/native/`）：ArkTS 侧契约 + 注册表，属 gl-render 写作用域
 * - `cpp/gl/`（native EGL/GLES3 实现）：native-image 写作用域
 * - `ets/native/GLNativeBackendImpl.ets`：NAPI 胶水，把 `libnative-lib.so`（module `native-lib`）的导出
 *   接到 `GLNativeBackend` 接口，并在 `EntryAbility` 启动时 `GLNative.register()`
 */

/** 统一返回码。禁止 native 侧返回裸 bool（契约要求，见 Lead 裁决 A）。 */
export enum GLErr {
  OK = 0,
  /** 上下文/EGLSurface 未就绪（Surface 尚未 create，或已 destroy）。 */
  NOT_READY = 1,
  /** 纹理/缓冲/framebuffer 句柄非法。 */
  BAD_ID = 2,
  /** glGenTextures / glGenBuffers 返回 0。 */
  OUT_OF_RESOURCES = 3,
  /** shader 编译或 program 链接失败（native 侧应把 info log 打到 hilog）。 */
  PROGRAM_FAILED = 4,
  /** GL 调用后 glGetError() != GL_NO_ERROR。 */
  GL_ERROR = 5,
  /** 参数非法（尺寸 <= 0、PixelMap 格式不支持等）。 */
  BAD_ARGUMENT = 6
}

/**
 * 命令字。**枚举值是协议的一部分**，改动等于改协议，必须同步 native 与 CONTRACTS.md。
 */
export enum GLCommand {
  /** `glViewport(0,0,w,h)` —— 上游 `GLES20Canvas.setSize` 首行。argc=2 */
  SET_VIEWPORT = 1,
  /** `glClearColor(r,g,b,a)` + `glClear(GL_COLOR_BUFFER_BIT)` —— `clearBuffer`。argc=4 */
  CLEAR = 2,
  /** `glUseProgram(p)`，p 由 kind 决定：0=draw 1=texture 2=oes 3=mesh —— 各 draw 路径。argc=1 */
  USE_PROGRAM = 3,
  /** `glEnable/glDisable(GL_BLEND)` —— `enableBlending`。argc=1 */
  BLEND_ENABLE = 4,
  /** `glBlendColor(r,g,b,a)` —— `prepareDraw` 半透明分支。argc=4 */
  BLEND_COLOR = 5,
  /** `glLineWidth(w)` —— `prepareDraw`。argc=1 */
  LINE_WIDTH = 6,
  /** `glUniform4fv(uColor, 1, rgba)` —— `prepareDraw`。argc=4 */
  UNIFORM_COLOR = 7,
  /** `glUniformMatrix4fv(uMatrix, 1, false, m)` —— `setMatrix`。argc=16 */
  UNIFORM_MATRIX = 8,
  /** `glUniformMatrix4fv(uTextureMatrix, 1, false, m)` —— `drawTextureRect`。argc=16 */
  UNIFORM_TEXTURE_MATRIX = 9,
  /** `glBindBuffer(GL_ARRAY_BUFFER, id)` —— `setPosition`。argc=1 */
  BIND_ARRAY_BUFFER = 10,
  /**
   * `glVertexAttribPointer(loc, 2, GL_FLOAT, false, 8, offset)` —— `setPosition`。argc=4
   *
   * args = `[programKind, attrSlot, size(F=2), offsetBytes]`。
   * **stride 恒为 `size * sizeof(float)` = 8**（不是参数！），第 4 个参数是**偏移字节**。
   * 5 条绘制路径的起始顶点与偏移（BOX_COORDINATES，每顶点 2 float）：
   * | 路径 | 顶点下标 | offsetBytes |
   * |---|---:|---:|
   * | fillRect | 0 | 0 |
   * | drawLine | 4 | 32 |
   * | drawRect | 6 | 48 |
   * | fillOval / fillSector | 10 | 80 |
   * | drawOval（圆环外径） | 11 | 88 |
   * native 侧若把该参数当 stride 用，fillRect 因 offset=0 恰好正确，
   * 其余四条会读错顶点集（画错形状而不是报错）—— 单测已按此表逐条固定。
   */
  VERTEX_ATTRIB_POINTER = 11,
  /** `glActiveTexture(GL_TEXTURE0)` + `glBindTexture(target, id)` —— `prepareTexture`。argc=2 */
  BIND_TEXTURE = 12,
  /** `glUniform1i(uTextureSampler, 0)` —— `prepareTexture`。argc=2 */
  UNIFORM_SAMPLER = 13,
  /** `glUniform1f(uAlpha, alpha)` —— `prepareTexture`。argc=2 */
  UNIFORM_ALPHA = 14,
  /** `glEnableVertexAttribArray(loc)` —— `draw`。argc=1 */
  ENABLE_ATTRIB = 15,
  /** `glDisableVertexAttribArray(loc)` —— `draw`。argc=1 */
  DISABLE_ATTRIB = 16,
  /** `glDrawArrays(mode, first, count)` —— `draw`。argc=3 */
  DRAW_ARRAYS = 17,
  /** `glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, id)` —— `drawMesh`。argc=1 */
  BIND_ELEMENT_ARRAY_BUFFER = 18,
  /** `glDrawElements(mode, count, GL_UNSIGNED_BYTE, offset)` —— `drawMesh`。argc=4 */
  DRAW_ELEMENTS = 19,
  /** `glBindFramebuffer(GL_FRAMEBUFFER, id)` —— `beginRenderTarget`/`endRenderTarget`。argc=1 */
  BIND_FRAMEBUFFER = 20,
  /** `glFramebufferTexture2D(...)` —— `beginRenderTarget` 挂载纹理。argc=4 */
  ATTACH_TEXTURE = 21,
  /** `glTexParameteri(target, name, value)` —— `setTextureParameters`。argc=3 */
  TEX_PARAMETER = 23,
  /** `glTexImage2D(target, 0, fmt, w, h, 0, fmt, type, null)` —— `initializeTextureSize`。argc=6 */
  TEX_IMAGE_2D = 24,
  /** `glBlendFunc(src, dst)` —— `recoverFromLightCycle`。argc=2 */
  BLEND_FUNC = 25,
  /** 帧结束标记，native 侧据此做一致性校验（可选的防御性检查）。argc=0 */
  END_FRAME = 22
}

/**
 * native GL 后端。实现方：`ets/native/GLNativeBackendImpl.ets`（NAPI → **`libnative-lib.so`**，
 * module 名 `native-lib`，与 native-image 的 CMake 产物一致；不是 `libglrenderer.so`）。
 * 调用方：`GLES20Canvas` / `GLES20IdImpl` / `GLRootView`。
 *
 * ## EGL 生命周期归属（与 native-image 对齐后的拍板）
 * XComponent 的 native 回调由 **native 侧**注册（`OH_NativeXComponent_RegisterCallback`，
 * 在 `libraryname: 'native-lib'` 触发的 `Init()` 里通过 `__NATIVE_XCOMPONENT_OBJ__` 拿到
 * component）。ArkTS 侧只声明 XComponent 并持有 `XComponentController`，**不**传 surfaceId。
 * 因此 EGL context/surface 的配对全程在 native，不存在跨语言乱序。
 *
 * ## 调用时序约束（ArkTS 侧必须遵守）
 * 1. `init()` 只能在 EGL context 就绪后调用 → `GLES20Canvas` 的构造推迟到
 *    `onSurfaceCreated` 之后（由 `GLRootView` 保证）
 * 2. `init()` **不建** `BOX_COORDINATES` 的 VBO：顶点表在 ArkTS 侧生成，
 *    经 `genBuffer()` + `bufferDataF32()` 上传（264 个 float），避免两处各建一份
 * 3. `replay()` 应可重入：`flushPending()` 会在一帧内多次调用它（纹理上传前冲刷）
 */
export interface GLNativeBackend {
  /**
   * 建立 EGL context 相关的一次性 GL 资源：编译 4 个 program（draw/texture/oes/mesh）、
   * 缓存 uniform/attrib location、设置 `glBlendFunc(GL_ONE, GL_ONE_MINUS_SRC_ALPHA)`。
   * 对应上游 `GLES20Canvas` 构造函数的 shader 装配部分（VBO 由 ArkTS 侧上传，见类注释）。
   */
  init(): GLErr;

  /**
   * 显式尺寸修正：`onSurfaceChanged` 之外由 ArkTS 调用（`GLES20Canvas.setSize` 的屏幕路径）。
   * native 侧用 `OH_NativeXComponent_GetXComponentSize` 兜底比对。
   */
  setSurface(width: number, height: number): GLErr;

  /** Surface 销毁：释放 EGLSurface，保留 program 与 VBO 之外的资源待重建。 */
  destroySurface(): GLErr;

  /**
   * 执行一段命令流，**不** present。
   * 拆出 `present()` 的原因：纹理上传（`texImage2D`/`texSubImage2D`）必须携带
   * PixelMap 走独立 NAPI，无法编码进命令流；为了让"先 BIND_TEXTURE 再上传"的顺序
   * 不被打乱，ArkTS 侧在上传前调用 `replay()` 把已录制的命令先执行掉（`flushPending`）。
   * 此时绝不能 swap，否则一帧会被切成多次上屏，出现撕裂。
   */
  replay(cmds: Float32Array): GLErr;

  /** `eglSwapBuffers`，一帧结束上屏。 */
  present(): GLErr;

  /** `glGenTextures(1, &id)`；失败返回 -1。 */
  genTexture(): number;

  /** `glDeleteTextures`。 */
  deleteTexture(id: number): GLErr;

  /**
   * `GLUtils.texImage2D(target, level, format, bitmap, border)` 等价：
   * 从 PixelMap 取像素并 `glTexImage2D`。
   * native 侧不得假设 stride —— 必须按 PixelMap 的 rowBytes 逐行拷。
   */
  texImage2D(id: number, width: number, height: number, format: number, type: number,
    pixelMap: image.PixelMap): GLErr;

  /** `glTexSubImage2D` 等价，用于 `UploadedTexture` 的局部更新路径。 */
  texSubImage2D(id: number, xOffset: number, yOffset: number, width: number, height: number,
    format: number, type: number, pixelMap: image.PixelMap): GLErr;

  /**
   * 用单一颜色填充纹理的一块矩形（内部 memset 成 RGBA 常量后 `glTexSubImage2D`）。
   * 对应上游 `UploadedTexture` 用 `Bitmap.createBitmap(1,length)` 生成**全零**边框线
   * 再 `texSubImage2D` 的做法 —— 上游那条路每帧要分配/缓存位图，这里直接填零，
   * 像素结果完全相同（全零 RGBA = 全透明），少一次 PixelMap 分配与拷贝。
   */
  texSubImage2DFill(id: number, xOffset: number, yOffset: number, width: number, height: number,
    format: number, type: number, rgba: number): GLErr;

  /**
   * `glGenBuffers(1, &id)`，`target` 取 GL_ARRAY_BUFFER(0x8892) 或
   * GL_ELEMENT_ARRAY_BUFFER(0x8893)；失败返回 -1。
   * 拆成"生成 id"与"上传数据"两步，是为了对齐上游 `mGLId.glGenBuffers(...)`
   * + `uploadBuffer(...)` 的两段式用法（`ImageTexture` 的 mesh 缓冲）。
   */
  genBuffer(target: number): number;

  /** `glBindBuffer(target, id)` + `glBufferData(target, data, GL_STATIC_DRAW)`（float 数据）。 */
  bufferDataF32(id: number, data: Float32Array): GLErr;

  /** 同上，字节数据（元素索引缓冲）。 */
  bufferDataU8(id: number, data: Uint8Array): GLErr;

  /** `glDeleteBuffers`。 */
  deleteBuffer(id: number): GLErr;

  /** `glGenFramebuffers`；失败返回 -1。 */
  genFramebuffer(): number;

  /** `glBindFramebuffer(target, 0)` + `glDeleteFramebuffers`（`endRenderTarget` 的对称操作）。 */
  unbindFramebuffer(): GLErr;

  /** `glDeleteFramebuffers(1, &id)`。 */
  deleteFramebuffer(id: number): GLErr;

  /** `glGetError()` 的透传，`checkError()` 用。返回 GL 错误码（0 表示无错）。 */
  getErrorCode(): number;

  /** `glGetString(what)`，`GLES20IdImpl`/能力探测用。 */
  getString(what: number): string;
}

/**
 * **区域 blit 能力**（可选能力，缺省时 `ImageTexture` 的分块上传不可用）。
 *
 * 为什么单独拆出来：`ImageTexture` 把大图切成 tile，每块要上传"图片的某个区域"
 * 到"纹理的某个偏移"，且偏移**可以为负**（tile 边框）。现有 `nativeTexImage2D` /
 * `nativeTexSubImage2D` 只能"整图上传到非负偏移"，语义不够。
 *
 * 契约（待 C-1 签字后由 native 侧实现并注册）：
 * ```
 * texImageRegion(id, init, pixelMap, srcX, srcY, srcW, srcH, dstX, dstY, texW, texH)
 *   裁剪（三向）：clipLeft = max(0, -dstX), clipTop = max(0, -dstY)
 *         clipRight = min(srcW, texW - dstX), clipBottom = min(srcH, texH - dstY)
 *         实际写入 w = clipRight - clipLeft, h = clipBottom - clipTop；w<=0||h<=0 → OK（全裁掉）
 *   源/目标偏移各自加上 clipLeft/clipTop
 *   **还要裁源图边界**：srcX+srcW 超过 pixelMap 宽/高时同样收敛
 *   （tile 上传会请求 [offsetX-border, +256) 这样的越界区域，属于正常输入）
 *   init=true 时先 glTexImage2D(GL_RGBA, texW, texH, null) 分配
 *   负偏移是**正常输入**，不是错误；只有 pixelMap 空 / id<=0 / texW,texH<=0 才 BAD_ARGUMENT
 * ```
 */
export interface TexRegionUploader {
  texImageRegion(id: number, init: boolean, pixelMap: image.PixelMap, srcX: number, srcY: number,
    srcW: number, srcH: number, dstX: number, dstY: number, texW: number, texH: number): GLErr;
}

/**
 * 后端注册表。
 *
 * 为什么要有注册表而不是直接 import `.so`：`harmony/entry/src/main/cpp/**` 属
 * native-image 写作用域，`.so` 何时编出来不受 gl-render 控制。用注册表可以让
 * gl-render 的所有 `.ets` 在 native 尚未就绪时**照样通过编译与单测**
 * （未注册时 `GLNative.backend()` 抛 NOT_READY，命令流仍可完整录制并断言）。
 */
export class GLNative {
  private static sBackend: GLNativeBackend | null = null;

  /** 由 `ets/native/GLNativeBackendImpl` 在 Ability 启动时调用一次。 */
  static register(backend: GLNativeBackend): void {
    GLNative.sBackend = backend;
  }

  /** 是否已有 native 后端（未就绪时 UI 应显示降级提示而不是崩溃）。 */
  static isReady(): boolean {
    return GLNative.sBackend !== null;
  }

  /** 取后端；未注册时抛错，错误信息里带下一步动作，避免"静默黑屏"。 */
  static backend(): GLNativeBackend {
    const b = GLNative.sBackend;
    if (b === null) {
      throw new Error('GLNative backend is not registered: libnative-lib.so export GLBackend missing');
    }
    return b;
  }

  private static sRegionUploader: TexRegionUploader | null = null;

  /**
   * 注册区域 blit 能力（由 `GLNativeBackendImpl` 在 native 提供该符号后调用）。
   * 未注册时 `GLTexImageBridge` 会抛出具名错误，**不会**静默上传错位像素。
   */
  static registerRegionUploader(uploader: TexRegionUploader | null): void {
    GLNative.sRegionUploader = uploader;
  }

  /** 取区域 blit 能力；未注册返回 null（调用方自行决定降级或报错）。 */
  static regionUploader(): TexRegionUploader | null {
    return GLNative.sRegionUploader;
  }

  /** 仅测试用：解绑后端。 */
  static unregister(): void {
    GLNative.sBackend = null;
    GLNative.sRegionUploader = null;
  }
}
