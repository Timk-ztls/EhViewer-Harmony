/*
 * Licensed under the Apache License, Version 2.0 (the "License");
 *
 * ── HarmonyOS 移植记录 ──────────────────────────────────────────────────────
 * 条目   : S0508   上游: com/hippo/util/TimeUtils.kt（13 行）
 * 目标   : harmony/entry/src/main/ets/hippo/util/TimeUtils.ets
 *
 * 平台差异：
 *   **`SimpleDateFormat("yyyy-MM-dd HH:mm:ss a")` → 手写格式化**。
 *   与 ReadableTime 同口径（D-036 相关）：`Intl.DateTimeFormat` 的输出随系统语言变化，
 *   会破坏上游固定格式；`a`（AM/PM 标记）在 `Intl` 里是 `dayPeriod`，不同引擎输出不同
 *   （`AM`/`am`/`上午`），故**手写为 "AM"/"PM"**（Java 默认 Locale.US 下的行为）。
 *   若将来要本地化，应作为独立决策（改对外输出 = 改契约）。
 */

export class TimeUtils {

  /** 对应上游 `TimeUtils.timeNow`：`yyyy-MM-dd HH:mm:ss a`（24h 的时:分:秒 + AM/PM 标记） */
  static getTimeNow(): string {
    const d: Date = new Date();
    return `${TimeUtils.pad4(d.getFullYear())}-${TimeUtils.pad2(d.getMonth() + 1)}`
      + `-${TimeUtils.pad2(d.getDate())}`
      + ` ${TimeUtils.pad2(d.getHours())}:${TimeUtils.pad2(d.getMinutes())}`
      + `:${TimeUtils.pad2(d.getSeconds())}`
      + ` ${d.getHours() < 12 ? 'AM' : 'PM'}`;
  }

  private static pad2(v: number): string {
    return v < 10 ? `0${v}` : `${v}`;
  }

  private static pad4(v: number): string {
    if (v < 10) {
      return `000${v}`;
    }
    if (v < 100) {
      return `00${v}`;
    }
    if (v < 1000) {
      return `0${v}`;
    }
    return `${v}`;
  }
}