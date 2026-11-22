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

import { image } from '@kit.ImageKit';
import { RectF } from '../util/RectF';
import { Rect } from '../util/Rect';
import { GLPaint } from './GLPaint';
import { GLId } from './GLId';
import { BasicTexture } from './BasicTexture';
import { RawTexture } from './RawTexture';

/**
 * `com.hippo.lib.glview.glrenderer.GLCanvas` 的 ArkTS 等价实现。
 *
 * ## 为什么从 interface 改成 abstract class
 * 上游是 `interface` 且带 3 个 `int` 常量（`SAVE_FLAG_ALL/ALPHA/MATRIX`）。
 * ArkTS 的 interface 不能声明静态常量，而调用点写的是 `GLCanvas.SAVE_FLAG_MATRIX`。
 * 改为 abstract class 后静态常量可挂在类上，调用点**逐字不变**；
 * 抽象方法语义与 interface 一致（唯一实现是 `GLES20Canvas`，无多继承需求）。
 *
 * ## 重载处理（DEVIATIONS §5 第 7 条：ArkTS 无重载解析）
 * 上游 4 组重载：`translate(x,y,z)`/`translate(x,y)`、`save()`/`save(flags)`、
 * `drawTexture(...)` ×3、`drawMixed(...)` ×2。统一用"可选参数 + 联合类型 + 运行时分派"，
 * 方法名与调用点写法不变。
 *
 * ## 坐标系
 * 与上游一致：矩形表示 `[x, x+width) × [y, y+height)`，原点左上、y 向下
 * （`setSize` 内用 `translate(0,height)` + `scale(1,-1,1)` 翻到 GL 的 y 向上）。
 */
export abstract class GLCanvas {
  static readonly SAVE_FLAG_ALL: number = 0xFFFFFFFF;
  static readonly SAVE_FLAG_ALPHA: number = 0x01;
  static readonly SAVE_FLAG_MATRIX: number = 0x02;

  abstract getGLId(): GLId;

  /** 告知底层 GL surface 尺寸；首次绘制前与尺寸变化时由 `GLRoot` 调用。 */
  abstract setSize(width: number, height: number): void;

  /** 清屏为黑色（上游 `clearBuffer()` 即 alpha=1 的黑）。 */
  abstract clearBuffer(): void;

  /** 清屏为指定颜色，参数顺序是 **ARGB**（上游 `clearBuffer(float[] argb)`）。 */
  abstract clearBufferArgb(argb: number[]): void;

  abstract setAlpha(alpha: number): void;

  abstract getAlpha(): number;

  /** `alpha = getAlpha() * alpha`。 */
  abstract multiplyAlpha(alpha: number): void;

  /** `translate(x, y, z)`；`z` 省略时按 0 处理（上游快速路径）。 */
  abstract translate(x: number, y: number, z?: number): void;

  abstract scale(sx: number, sy: number, sz: number): void;

  /** 绕轴 (x,y,z) 旋转 angle 度。 */
  abstract rotate(angle: number, x: number, y: number, z: number): void;

  /** 左乘外部 4x4 矩阵（列主序，offset 起 16 个 float）。 */
  abstract multiplyMatrix(mMatrix: number[], offset: number): void;

  /** 保存当前状态；`saveFlags` 省略时等价 `SAVE_FLAG_ALL`。 */
  abstract save(saveFlags?: number): void;

  /** 出栈恢复。 */
  abstract restore(): void;

  abstract drawLine(x1: number, y1: number, x2: number, y2: number, paint: GLPaint): void;

  abstract drawRect(x: number, y: number, width: number, height: number, paint: GLPaint): void;

  abstract drawOval(cx: number, cy: number, radiusX: number, radiusY: number, paint: GLPaint): void;

  abstract drawArc(cx: number, cy: number, radiusX: number, radiusY: number, sweepAngle: number,
    paint: GLPaint): void;

  abstract fillRect(x: number, y: number, width: number, height: number, color: number): void;

  abstract fillOval(cx: number, cy: number, radiusX: number, radiusY: number, color: number): void;

  abstract fillSector(cx: number, cy: number, radiusX: number, radiusY: number, sweepAngle: number,
    color: number): void;

  /**
   * 三种重载合一（按第二参数类型运行时分派）：
   * 1. `drawTexture(t, x, y, w, h)`
   * 2. `drawTexture(t, source: RectF, target: RectF)`
   * 3. `drawTexture(t, textureTransform: number[], x, y, w, h)`
   */
  abstract drawTexture(texture: BasicTexture, a: number | RectF | number[], b?: number | RectF,
    c?: number, d?: number, e?: number, f?: number): void;

  /** 用外部 xy/uv/index 缓冲绘制网格（`ImageTexture` 分块渲染用）。 */
  abstract drawMesh(tex: BasicTexture, x: number, y: number, xyBuffer: number, uvBuffer: number,
    indexBuffer: number, indexCount: number): void;

  /**
   * 两种重载合一：
   * 1. `drawMixed(from, toColor, ratio, x, y, w, h)`
   * 2. `drawMixed(from, toColor, ratio, src: RectF, target: RectF)`
   */
  abstract drawMixed(from: BasicTexture, toColor: number, ratio: number, a: number | RectF,
    b: number | RectF, c?: number, d?: number): void;

  /** 卸载纹理的 GL 资源；只应由 `BasicTexture` 及其子类调用。 */
  abstract unloadTexture(texture: BasicTexture): boolean;

  abstract deleteBuffer(bufferId: number): void;

  /** GL 线程内执行累积的回收动作（纹理/缓冲删除）。 */
  abstract deleteRecycledResources(): void;

  /** 打印并清零统计计数器（调试用）。 */
  abstract dumpStatisticsAndClear(): void;

  abstract beginRenderTarget(texture: RawTexture): void;

  abstract endRenderTarget(): void;

  /** `GL_CLAMP_TO_EDGE` × 2 + `GL_LINEAR` × 2；调用前必须已 bindTexture。 */
  abstract setTextureParameters(texture: BasicTexture): void;

  /** `glTexImage2D` 分配指定尺寸的空纹理。 */
  abstract initializeTextureSize(texture: BasicTexture, format: number, type: number): void;

  /** `glTexImage2D` 用位图内容初始化纹理。 */
  abstract initializeTexture(texture: BasicTexture, pixelMap: image.PixelMap): void;

  /** `glTexSubImage2D` 局部更新。 */
  abstract texSubImage2D(texture: BasicTexture, xOffset: number, yOffset: number,
    pixelMap: image.PixelMap, format: number, type: number): void;

  /**
   * 用常量 RGBA 填充纹理矩形区（对应上游用全零 `Bitmap` 画边框线的做法，见
   * `UploadedTexture.uploadToCanvas` 的 Left/Top/Right/Bottom border 四段）。
   */
  abstract texSubImage2DFill(texture: BasicTexture, xOffset: number, yOffset: number,
    width: number, height: number, format: number, type: number, rgba: number): void;

  /** 上传 float 顶点缓冲，返回 buffer id。 */
  abstract uploadBufferFloat(data: Float32Array): number;

  /** 上传字节索引缓冲，返回 buffer id。 */
  abstract uploadBufferByte(data: Uint8Array): number;

  /** 第三方 GL 调用（如外部插件）后恢复 GLCanvas 期望的 GL 状态。 */
  abstract recoverFromLightCycle(): void;

  /** 按当前矩阵把 (x,y,width,height) 变换后的包围盒写入 bounds。 */
  abstract getBounds(bounds: Rect, x: number, y: number, width: number, height: number): void;

  // ---- 帧边界钩子 ----
  // 这几个不是上游 `GLCanvas` 的成员，是为"命令流"实现（`GLES20Canvas`）加的帧边界：
  // `GLRootView` 每帧调用 beginFrame()/flush()，非命令流实现保持空实现即可。
  // 上游对应物是 `GLSurfaceView` 的 onDrawFrame/swap 时机，不在 GLCanvas 接口里。

  /**
   * 立即绑定纹理，并**冲刷已录制的命令**，用于"紧接着由外部 NAPI 上传像素"的场景
   * （`NativeTexture` 的 `texImage` 由 `Image.texImage` 直接推像素，不经过命令流）。
   *
   * 非命令流实现可以是空实现（它们没有延迟执行的问题）。
   */
  bindTextureForUpload(texture: BasicTexture): void {
  }

  /** 开始一帧（清空上一帧录制缓冲）。 */
  beginFrame(): void {
  }

  /** 提交本帧并上屏。 */
  flush(): void {
  }
}
