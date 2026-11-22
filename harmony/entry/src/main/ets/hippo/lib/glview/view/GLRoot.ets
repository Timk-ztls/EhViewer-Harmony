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

import { Matrix } from '../util/Matrix';
import { CanvasAnimation } from '../anim/CanvasAnimation';
import { OrientationSource } from './OrientationSource';
import { GLView } from './GLView';
import { GLCanvas } from '../glrenderer/GLCanvas';

/**
 * `com.hippo.lib.glview.view.GLRoot` 的 ArkTS 等价实现。
 *
 * 上游 18 个方法已全部落地。中途曾以 17/18 的形式先落（只差 `setContentPane`，
 * 因为它需要 `GLView` 类型），以解除 storage-db 对 `GalleryProvider` 的阻塞；
 * `GLView.ets` 落地后补齐最后一个方法。
 *
 * 语义（上游注释直译）：`OnGLIdleListener` 在 GL 空闲且每帧渲染前被调用，
 * 主要用于上传纹理 —— 这是"UI 线程算数据、GL 线程传纹理"的解耦点。
 */
export interface GLRoot {
  /** GL 空闲且每帧渲染前回调；返回 true 表示要求立即再渲染一帧。 */
  addOnGLIdleListener(listener: GLRootOnGLIdleListener): void;

  /** 请求下一帧渲染（`RENDERMODE_WHEN_DIRTY` 语义）。 */
  requestRender(): void;

  /** 强制渲染下一帧（忽略脏标记，用于 Surface 重建后首帧）。 */
  requestRenderForced(): void;

  /** 请求重新布局内容面板（尺寸/方向变化后）。 */
  requestLayoutContentPane(): void;

  /** 锁定/解锁渲染线程状态，用于 UI 线程访问渲染状态时的临界区。 */
  lockRenderThread(): void;

  unlockRenderThread(): void;

  /** 冻结/解冻渲染（页面切换动画期间暂停绘制）。 */
  freeze(): void;

  unfreeze(): void;

  /** 登记一个活动动画；`GLRootView` 每帧推进它们并在绘制后清理。 */
  registerLaunchedAnimation(animation: CanvasAnimation): void;

  /** 设置内容面板（最顶层 GLView）。 */
  setContentPane(content: GLView | null): void;

  /** 设置屏幕方向来源（触摸坐标换算用）。 */
  setOrientationSource(source: OrientationSource | null): void;

  /** 显示旋转角度（0/90/180/270）。 */
  getDisplayRotation(): number;

  /** 方向补偿角（0/90/180/270）。 */
  getCompensation(): number;

  /** 补偿矩阵（把内容坐标转回屏幕坐标，用于命中测试/动画取反）。 */
  getCompensationMatrix(): Matrix;

  /** Lights-out 模式（沉浸阅读时把系统栏/背景压暗）。 */
  setLightsOutMode(enabled: boolean): void;

  getWidth(): number;

  getHeight(): number;
}

/**
 * `GLRoot.OnGLIdleListener`。上游是嵌套接口，ArkTS 的 interface 不能嵌套，
 * 这里提成顶层导出并在 `GLRoot` 的注释里标明对应关系；
 * 调用点写法由 `root.addOnGLIdleListener(this)` 保持不变。
 */
export interface GLRootOnGLIdleListener {
  /**
   * @param canvas 当前 GL 画布
   * @param renderRequested 上层是否已请求渲染
   * @return true 表示要求立即再渲染一帧（用于动画）
   */
  onGLIdle(canvas: GLCanvas, renderRequested: boolean): boolean;
}

/**
 * 兼容上游 `GLRoot.OnGLIdleListener` 的写法：ArkTS 里用 `GLRoot.OnGLIdleListener`
 * 这种"接口内嵌接口"语法不成立，改为导出别名，让下游 `implements GLRoot.OnGLIdleListener`
 * 可以写成 `implements OnGLIdleListener`。生成器/审查脚本按同名映射即可。
 */
export type OnGLIdleListener = GLRootOnGLIdleListener;

/** 供 `Matrix` 返回类型使用的占位导出（GLRoot.getCompensationMatrix 补齐时使用）。 */
export type GLRootMatrix = Matrix;
