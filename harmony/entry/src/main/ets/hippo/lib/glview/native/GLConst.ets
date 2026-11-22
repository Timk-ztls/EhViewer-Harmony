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

/**
 * GL 常量表（ArkTS 侧唯一来源）。
 *
 * 为什么需要它：上游直接从 `android.opengl.GLES20` / `javax.microedition.khronos.opengles.GL11`
 * 读 `GLES20.GL_TEXTURE_2D` 这类编译期常量。ArkTS 没有这两个包；而 `@ohos` 也没有
 * 暴露 GL 常量（无 webgl，实测见 MR）。因此这里按 Khronos 规范抄一份**数值完全相同**的常量，
 * 保证传到 native 的枚举值与 GLES3 头文件里的一致。
 *
 * 数值来源：`GLES2/gl2.h` 与 `GLES2/gl2ext.h`（NDK sysroot：
 * `<SDK>\20\native\sysroot\usr\include\GLES2\`）。写错一个值 = native 侧行为错乱，
 * 因此每个常量后面都带原始宏名，便于逐条核对。
 */
export class GLConst {
  // ---- 错误码 ----
  static readonly GL_NO_ERROR: number = 0;              // GL_NO_ERROR
  static readonly GL_INVALID_ENUM: number = 0x0500;     // GL_INVALID_ENUM
  static readonly GL_INVALID_VALUE: number = 0x0501;    // GL_INVALID_VALUE
  static readonly GL_INVALID_OPERATION: number = 0x0502;// GL_INVALID_OPERATION
  static readonly GL_OUT_OF_MEMORY: number = 0x0505;    // GL_OUT_OF_MEMORY

  // ---- 数据类型 ----
  static readonly GL_BYTE: number = 0x1400;
  static readonly GL_UNSIGNED_BYTE: number = 0x1401;
  static readonly GL_SHORT: number = 0x1402;
  static readonly GL_UNSIGNED_SHORT: number = 0x1403;
  static readonly GL_INT: number = 0x1404;
  static readonly GL_UNSIGNED_INT: number = 0x1405;
  static readonly GL_FLOAT: number = 0x1406;

  // ---- 像素格式 ----
  static readonly GL_DEPTH_COMPONENT: number = 0x1902;
  static readonly GL_ALPHA: number = 0x1906;
  static readonly GL_RGB: number = 0x1907;
  static readonly GL_RGBA: number = 0x1908;
  static readonly GL_LUMINANCE: number = 0x1909;

  // ---- 开关 ----
  static readonly GL_BLEND: number = 0x0BE2;            // GL_BLEND
  static readonly GL_DEPTH_TEST: number = 0x0B71;       // GL_DEPTH_TEST
  static readonly GL_SCISSOR_TEST: number = 0x0C11;     // GL_SCISSOR_TEST
  static readonly GL_CULL_FACE: number = 0x0B44;        // GL_CULL_FACE

  // ---- 混合 ----
  static readonly GL_ZERO: number = 0;
  static readonly GL_ONE: number = 1;
  static readonly GL_SRC_ALPHA: number = 0x0302;
  static readonly GL_ONE_MINUS_SRC_ALPHA: number = 0x0303;

  // ---- 缓冲 ----
  static readonly GL_ARRAY_BUFFER: number = 0x8892;
  static readonly GL_ELEMENT_ARRAY_BUFFER: number = 0x8893;
  static readonly GL_STATIC_DRAW: number = 0x88E4;
  static readonly GL_DYNAMIC_DRAW: number = 0x88E8;

  // ---- 纹理 ----
  static readonly GL_TEXTURE_2D: number = 0x0DE1;
  static readonly GL_TEXTURE_EXTERNAL_OES: number = 0x8D65; // GL_TEXTURE_EXTERNAL_OES
  static readonly GL_TEXTURE0: number = 0x84C0;
  static readonly GL_TEXTURE_MAG_FILTER: number = 0x2800;
  static readonly GL_TEXTURE_MIN_FILTER: number = 0x2801;
  static readonly GL_TEXTURE_WRAP_S: number = 0x2802;
  static readonly GL_TEXTURE_WRAP_T: number = 0x2803;
  static readonly GL_TEXTURE_WIDTH: number = 0x1000;
  static readonly GL_TEXTURE_HEIGHT: number = 0x1001;
  static readonly GL_LINEAR: number = 0x2601;
  static readonly GL_NEAREST: number = 0x2600;
  static readonly GL_CLAMP_TO_EDGE: number = 0x812F;
  static readonly GL_REPEAT: number = 0x2901;

  // ---- 绘制图元 ----
  static readonly GL_POINTS: number = 0x0000;
  static readonly GL_LINES: number = 0x0001;
  static readonly GL_LINE_LOOP: number = 0x0002;
  static readonly GL_LINE_STRIP: number = 0x0003;
  static readonly GL_TRIANGLES: number = 0x0004;
  static readonly GL_TRIANGLE_STRIP: number = 0x0005;
  static readonly GL_TRIANGLE_FAN: number = 0x0006;

  // ---- 清屏位 ----
  static readonly GL_COLOR_BUFFER_BIT: number = 0x00004000;
  static readonly GL_DEPTH_BUFFER_BIT: number = 0x00000100;
  static readonly GL_STENCIL_BUFFER_BIT: number = 0x00000400;

  // ---- Shader ----
  static readonly GL_FRAGMENT_SHADER: number = 0x8B30;
  static readonly GL_VERTEX_SHADER: number = 0x8B31;
  static readonly GL_COMPILE_STATUS: number = 0x8B81;
  static readonly GL_LINK_STATUS: number = 0x8B82;
  static readonly GL_TRUE: number = 1;

  // ---- 帧缓冲 ----
  static readonly GL_FRAMEBUFFER: number = 0x8D40;
  static readonly GL_COLOR_ATTACHMENT0: number = 0x8CE0;
  static readonly GL_FRAMEBUFFER_COMPLETE: number = 0x8CD5;

  // ---- glGetString ----
  static readonly GL_VENDOR: number = 0x1F00;
  static readonly GL_RENDERER: number = 0x1F01;
  static readonly GL_VERSION: number = 0x1F02;
  static readonly GL_EXTENSIONS: number = 0x1F03;
  static readonly GL_MAX_TEXTURE_SIZE: number = 0x0D33;

  /** `GL_TEXTURE_EXTERNAL_OES` 是否需要 OES 扩展着色器（`ExtTexture` 用）。 */
  static isOesTarget(target: number): boolean {
    return target === GLConst.GL_TEXTURE_EXTERNAL_OES;
  }
}
