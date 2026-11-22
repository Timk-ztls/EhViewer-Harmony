/*
 * Licensed under the Apache License, Version 2.0 (the "License");
 *
 * ── HarmonyOS 移植记录 ──────────────────────────────────────────────────────
 * 条目   : S0315   上游: com/hippo/ehviewer/widget/ShakeDetector.java（58 行）
 * 目标   : harmony/entry/src/main/ets/hippo/ehviewer/widget/ShakeDetector.ets
 *
 * 摇一摇检测：把加速度换算成"重力倍数"，超过阈值就算摇动，并用两个时间窗口做去抖与计数复位。
 * **核心是三段纯逻辑**，与 Android Sensor API 无关：
 *   ```
 *   gX = x / GRAVITY_EARTH    ...  gForce = sqrt(gX² + gY² + gZ²)
 *   if (gForce > 2.7) {
 *      if (last + 500ms > now) return;          // 500ms 内的抖动全部忽略（去抖）
 *      if (last + 3000ms < now) count = 0;      // 3s 没摇 → 计数复位
 *      last = now; count++; listener.onShake(count);
 *   }
 *   ```
 * 注意两个窗口的**比较方向相反**（`>` 与 `<`），且都是**严格**比较 —— 边界值不触发，照搬。
 *
 * 平台差异：
 * 1. `SensorEventListener` / `SensorEvent` → 本类只提供 `onSensorChanged(x, y, z)`
 *    （ui-scene 用 `@ohos.sensor` 的 `sensor.on(SensorId.ACCELEROMETER, ...)` 转发进来）。
 * 2. `System.currentTimeMillis()` → 注入 `now()`，便于断言时间窗口。
 * 3. `SensorManager.GRAVITY_EARTH = 9.80665f` 照搬为常量。
 * 4. `onAccuracyChanged` 是空实现，不移植（精度变化对摇一摇无意义）。
 */

/** 上游 `OnShakeListener` */
export interface OnShakeListener {
  onShake(count: number): void;
}

export class ShakeDetector {

  /** 上游 `SHAKE_THRESHOLD_GRAVITY = 2.7F` —— 超过 2.7 倍重力算摇动 */
  static readonly SHAKE_THRESHOLD_GRAVITY: number = 2.7;
  /** 上游 `SHAKE_SLOP_TIME_MS = 500` —— 两次摇动的最小间隔 */
  static readonly SHAKE_SLOP_TIME_MS: number = 500;
  /** 上游 `SHAKE_COUNT_RESET_TIME_MS = 3000` —— 超过该时长没摇，计数复位 */
  static readonly SHAKE_COUNT_RESET_TIME_MS: number = 3000;
  /** 上游 `SensorManager.GRAVITY_EARTH` */
  static readonly GRAVITY_EARTH: number = 9.80665;

  private listener: OnShakeListener | null = null;
  private shakeTimestamp: number = 0;
  private shakeCount: number = 0;
  private readonly now: () => number;

  /** @param now 当前毫秒时间戳来源（默认 Date.now） */
  constructor(now: () => number = () => Date.now()) {
    this.now = now;
  }

  setOnShakeListener(listener: OnShakeListener | null): void {
    this.listener = listener;
  }

  /**
   * 对应上游 `onSensorChanged(event)`。
   * @returns 是否触发了一次 onShake（**上游无返回值，这里返回布尔便于断言与调用方判断**）
   */
  onSensorChanged(x: number, y: number, z: number): boolean {
    if (this.listener === null) {
      return false;
    }
    const gX: number = x / ShakeDetector.GRAVITY_EARTH;
    const gY: number = y / ShakeDetector.GRAVITY_EARTH;
    const gZ: number = z / ShakeDetector.GRAVITY_EARTH;

    // gForce will be close to 1 when there is no movement.
    const gForce: number = Math.sqrt(gX * gX + gY * gY + gZ * gZ);

    if (!(gForce > ShakeDetector.SHAKE_THRESHOLD_GRAVITY)) {
      return false;
    }

    const now: number = this.now();
    // ignore shake events too close to each other (500ms)
    if (this.shakeTimestamp + ShakeDetector.SHAKE_SLOP_TIME_MS > now) {
      return false;
    }
    // reset the shake count after 3 seconds of no shakes
    if (this.shakeTimestamp + ShakeDetector.SHAKE_COUNT_RESET_TIME_MS < now) {
      this.shakeCount = 0;
    }
    this.shakeTimestamp = now;
    this.shakeCount++;
    (this.listener as OnShakeListener).onShake(this.shakeCount);
    return true;
  }

  /** 当前摇动计数（诊断/测试用；上游无此 getter） */
  getShakeCount(): number {
    return this.shakeCount;
  }
}
