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

/**
 * 平台删除说明（不是代码，是判定记录）—— `GLES11Canvas`
 *
 *   inventory S0344  lib/glview/glrenderer/GLES11Canvas.java  (904 行) → **na**
 *
 * ## 它在上游做什么
 * OpenGL **ES 1.1** 的画布实现：固定管线（`glMatrixMode` / `glLoadMatrixf` /
 * `glDrawArrays` + 顶点数组状态机）、`GLState` 管理 `mAlpha` 与颜色模式、
 * 用 `BOX_COORDINATES` 预烘焙 9 类几何（填充矩形/线段/矩形边框/圆）的顶点。
 *
 * ## 为什么本层不做等价移植（三条独立证据）
 *
 * **证据 1：上游只在「没有 ES2 的设备」上才用它**
 * ```java
 * // GLRootView.java（onSurfaceCreated）
 * mCanvas = mEGLContextClientVersion == 2 ? new GLES20Canvas() : new GLES11Canvas(gl);
 * // ConfigChooser.chooseConfig
 * if ((renderableType & EGL_OPENGL_ES2_BIT) == EGL_OPENGL_ES2_BIT) {
 *     mEGLContextClientVersion = 2;
 * } else {
 *     mEGLContextClientVersion = 1;      // ← 只有这里才会走 ES1.1 分支
 * }
 * ```
 * 它是**老硬件兜底**，不是功能路径。
 *
 * **证据 2：鸿蒙侧只有一条画布通道**
 * `GLRootViewController.ets:170` 只有 `const canvas = new GLES20Canvas();`（无条件），
 * 全仓无任何 `GLES11Canvas` 引用（只有 `GLId.ets:22` 的一句注释提到「鸿蒙侧没有 GLES1 概念」）。
 *
 * **证据 3：native 后端没有 ES1 固定管线 API**
 * `native/GLNativeBridge.ets` 的命令集里没有 `glMatrixMode` / `glLoadMatrixf` /
 * `glEnableClientState` / `glVertexPointer`；只有 `glEnable(GL_BLEND)`、`glDrawArrays(mode, first, count)`
 * 这类 **ES2 用法**（配合已编译的 shader + `drawMesh`）。
 * 也就是说：即使把 904 行逐字翻过来，**也没有任何 API 能让它真正画出东西**。
 *
 * ## 影响评估（为什么删除是安全的）
 * - `GLCanvas` 是抽象类，唯一实现是 `GLES20Canvas`（已交付、已测、已被 `GLRootViewController` 使用）
 * - 所有渲染类（`ImageView` / `GalleryView` / 三个 LayoutManager / `NinePatchTexture` …）
 *   都只依赖 `GLCanvas` 接口，**不依赖具体画布类型**
 * - 上游 ES1 分支的价值是「让 2013 年的老设备能跑」；鸿蒙目标设备全部支持 ES3.0
 *
 * ## 若将来要恢复
 * 需要同时具备：① native 侧暴露固定管线命令（不现实，Harmony 的 GL 绑定是 ES2/3）
 * 或 ② 用 ES2 重写一份「差量实现」——但那时它与 `GLES20Canvas` 的差别只剩
 * `OPAQUE_ALPHA = 0.95` 与 `BOX_COORDINATES` 顶点预烘焙，属于实现细节而非行为差异。
 *
 * 登记：DEVIATIONS 表 `na`（平台删除）+ inventory S0344 置 `na`。
 */

/** 本文件不含实现；导出常量仅供引用方断言「该平台删除项已登记」。 */
export const GLES11_CANVAS_PLATFORM_DELETED: boolean = true;
