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

import { display } from '@kit.ArkUI';
import { Animation } from '../glview/anim/Animation';
import { Interpolator } from '../yorozuya/AnimationUtils';

/** 两张样条表（距离 / 时间），必须同一次二分循环产出。 */
class SplineTables {
  position: number[];
  time: number[];

  constructor(position: number[], time: number[]) {
    this.position = position;
    this.time = time;
  }
}

/**
 * `com.hippo.lib.glgallery.Fling` 的 ArkTS 等价实现。
 *
 * 惯性滑动的距离/时长模型，直接来自 AOSP `OverScroller` 的 spline 实现。
 * **所有常量都是 AOSP 原值，不许自己调**（Lead 铁律）：
 *
 * | 常量 | 值 | 含义 |
 * |---|---|---|
 * | `DECELERATION_RATE` | `ln(0.78)/ln(0.9)` ≈ 2.3582 | 减速曲线幂次 |
 * | `INFLEXION` | 0.35 | 张力线交点 |
 * | `START_TENSION` / `END_TENSION` | 0.5 / 1.0 | 三次贝塞尔控制点 |
 * | `FLING_FRICTION` | 0.015（`ViewConfiguration.getScrollFriction()`） | 滚动摩擦 |
 * | `GRAVITY_EARTH` | 9.80665 | 物理系数用 |
 * | `NB_SAMPLES` | 100 | 样条采样数 |
 *
 * 物理系数 `mPhysicalCoeff = 9.80665 * 39.37 * ppi * 0.84`（AOSP 原值），
 * `ppi = density * 160`，density 取鸿蒙 `display.getDefaultDisplaySync().densityPixels`。
 *
 * ## 为什么样条表是"惰性初始化"而不是静态字段直接算
 * 上游在 `static {}` 块里一次算出两张表。ArkTS 的静态字段按声明顺序初始化，
 * 若把 `time` 表放在被 `position` 表计算过程里引用，会读到 `undefined` 直接崩。
 * 因此改成：第一次访问时用 `ensureTables()` 一次算完两张（**同一循环**，
 * 与上游同源，保证两表一一对应），之后只读。
 */
export abstract class Fling extends Animation {
  private static readonly DECELERATION_RATE: number = Math.log(0.78) / Math.log(0.9);
  private static readonly INFLEXION: number = 0.35;
  private static readonly START_TENSION: number = 0.5;
  private static readonly END_TENSION: number = 1.0;
  private static readonly P1: number = Fling.START_TENSION * Fling.INFLEXION;
  private static readonly P2: number = 1.0 - Fling.END_TENSION * (1.0 - Fling.INFLEXION);

  /** AOSP `ViewConfiguration.getScrollFriction()`。 */
  private static readonly FLING_FRICTION: number = 0.015;

  /** AOSP `SensorManager.GRAVITY_EARTH`。 */
  private static readonly GRAVITY_EARTH: number = 9.80665;

  private static readonly NB_SAMPLES: number = 100;

  private static sTables: SplineTables | null = null;

  private static ensureTables(): SplineTables {
    const cached = Fling.sTables;
    if (cached !== null) {
      return cached;
    }
    const position = new Array<number>(Fling.NB_SAMPLES + 1).fill(0);
    const time = new Array<number>(Fling.NB_SAMPLES + 1).fill(0);

    let xMin = 0.0;
    let yMin = 0.0;
    for (let i = 0; i < Fling.NB_SAMPLES; i++) {
      const alpha = i / Fling.NB_SAMPLES;

      // 距离样条：解 x(t)=alpha
      let xMax = 1.0;
      let x = 0;
      let coef = 0;
      while (true) {
        x = xMin + (xMax - xMin) / 2.0;
        coef = 3.0 * x * (1.0 - x);
        const tx = coef * ((1.0 - x) * Fling.P1 + x * Fling.P2) + x * x * x;
        if (Math.abs(tx - alpha) < 1e-5) {
          break;
        }
        if (tx > alpha) {
          xMax = x;
        } else {
          xMin = x;
        }
      }
      position[i] = coef * ((1.0 - x) * Fling.START_TENSION + x) + x * x * x;

      // 时间样条：解 y(t)=alpha
      let yMax = 1.0;
      let y = 0;
      let coefY = 0;
      while (true) {
        y = yMin + (yMax - yMin) / 2.0;
        coefY = 3.0 * y * (1.0 - y);
        const dy = coefY * ((1.0 - y) * Fling.START_TENSION + y) + y * y * y;
        if (Math.abs(dy - alpha) < 1e-5) {
          break;
        }
        if (dy > alpha) {
          yMax = y;
        } else {
          yMin = y;
        }
      }
      time[i] = coefY * ((1.0 - y) * Fling.P1 + y * Fling.P2) + y * y * y;
    }
    position[Fling.NB_SAMPLES] = 1.0;
    time[Fling.NB_SAMPLES] = 1.0;

    const tables = new SplineTables(position, time);
    Fling.sTables = tables;
    return tables;
  }

  private static sInterpolator: Interpolator | null = null;

  /** 距离样条插值器：归一化时间 → 归一化距离。 */
  private static flingInterpolator(): Interpolator {
    const cached = Fling.sInterpolator;
    if (cached !== null) {
      return cached;
    }
    // ArkTS 禁止无类型对象字面量（arkts-no-untyped-obj-literals），
    // 即使目标类型是 interface 也不行 —— 必须用一个显式类实现。
    const impl = new FlingSplineInterpolator();
    Fling.sInterpolator = impl;
    return impl;
  }

  private readonly mPhysicalCoeff: number;

  constructor(densityPixels?: number) {
    super();
    const density = densityPixels === undefined ? Fling.resolveDensity() : densityPixels;
    const ppi = density * 160.0;
    this.mPhysicalCoeff = Fling.GRAVITY_EARTH // g (m/s^2)
      * 39.37 // inch/meter
      * ppi
      * 0.84; // look and feel tuning
    this.setInterpolator(Fling.flingInterpolator());
  }

  /** 鸿蒙等价 `context.getResources().getDisplayMetrics().density`。 */
  private static resolveDensity(): number {
    try {
      return display.getDefaultDisplaySync().densityPixels;
    } catch (err) {
      // 取不到时按 1.0（等价 mdpi）；调用方可显式传 densityPixels 覆盖
      return 1.0;
    }
  }

  private getSplineDeceleration(velocity: number): number {
    return Math.log(Fling.INFLEXION * Math.abs(velocity)
      / (Fling.FLING_FRICTION * this.mPhysicalCoeff));
  }

  /** fling 总时长（毫秒）。 */
  protected getSplineFlingDuration(velocity: number): number {
    const l = this.getSplineDeceleration(velocity);
    const decelMinusOne = Fling.DECELERATION_RATE - 1.0;
    return Math.trunc(1000.0 * Math.exp(l / decelMinusOne));
  }

  /** fling 总距离（像素）。 */
  protected getSplineFlingDistance(velocity: number): number {
    const l = this.getSplineDeceleration(velocity);
    const decelMinusOne = Fling.DECELERATION_RATE - 1.0;
    return Fling.FLING_FRICTION * this.mPhysicalCoeff
      * Math.exp(Fling.DECELERATION_RATE / decelMinusOne * l);
  }

  /**
   * 目标位置改变时按时间样条把时长从"到旧终点"修正为"到新终点"。
   * `ScrollLayoutManager` 的边界吸附（越界回弹）依赖它。
   */
  protected adjustDuration(start: number, oldFinal: number, newFinal: number,
    duration: number): number {
    const oldDistance = oldFinal - start;
    const newDistance = newFinal - start;
    const x = Math.abs(newDistance / oldDistance);
    const index = Math.trunc(Fling.NB_SAMPLES * x);
    if (index < Fling.NB_SAMPLES) {
      const tables = Fling.ensureTables();
      const time = tables.time;
      const xInf = index / Fling.NB_SAMPLES;
      const xSup = (index + 1) / Fling.NB_SAMPLES;
      const tInf = time[index];
      const tSup = time[index + 1];
      const timeCoef = tInf + (x - xInf) / (xSup - xInf) * (tSup - tInf);
      duration *= timeCoef;
    }
    return duration;
  }

  /** 诊断/单测：物理系数（上游 private，这里只读暴露以验证密度换算）。 */
  getPhysicalCoeff(): number {
    return this.mPhysicalCoeff;
  }

  /** 诊断/单测：距离样条表（只读）。 */
  static getSplinePositionTable(): number[] {
    return Fling.ensureTables().position;
  }

  /** 诊断/单测：时间样条表（只读）。 */
  static getSplineTimeTable(): number[] {
    return Fling.ensureTables().time;
  }

  /** 诊断/单测：单调性检查用（样条表必须严格递增）。 */
  static isTableMonotonic(table: number[]): boolean {
    for (let i = 1; i < table.length; i++) {
      if (table[i] < table[i - 1]) {
        return false;
      }
    }
    return true;
  }
}

/**
 * 距离样条插值器。上游是匿名内部类，ArkTS 禁止无类型对象字面量，故提为具名类。
 */
class FlingSplineInterpolator implements Interpolator {
  getInterpolation(input: number): number {
    const position = Fling.getSplinePositionTable();
    const index = Math.trunc(100 * input);
    let distanceCoef = 1.0;
    if (index < 100) {
      const tInf = index / 100;
      const tSup = (index + 1) / 100;
      const dInf = position[index];
      const dSup = position[index + 1];
      const velocityCoef = (dSup - dInf) / (tSup - tInf);
      distanceCoef = dInf + (input - tInf) * velocityCoef;
    }
    return distanceCoef;
  }
}
