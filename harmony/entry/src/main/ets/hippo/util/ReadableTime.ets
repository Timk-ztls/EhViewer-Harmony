/*
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 *
 * ── HarmonyOS 移植记录 ──────────────────────────────────────────────────────
 * 条目   : S0487   上游: com/hippo/util/ReadableTime.java（约 190 行）
 * 目标   : harmony/entry/src/main/ets/hippo/util/ReadableTime.ets
 *
 * 平台差异：
 *  1. **`java.text.SimpleDateFormat` → 手写格式化**：ArkTS 无 SimpleDateFormat；
 *     `Intl.DateTimeFormat` 的输出格式随系统语言变化（会破坏上游固定格式
 *     `yy-MM-dd HH:mm` 与 `yyyy-MM-dd-HH-mm-ss-SSS`），故按上游 pattern 手工拼接，
 *     保证**逐字符可复现**（`getFilenamableTime` 的产物用于文件名，格式变了会破缓存命名）。
 *  2. **`Resources.getQuantityString(R.plurals.x, n)` → `getPluralStringByNameSync(name, n)`**
 *     （SDK 20 已确认存在该 API）；`Resources.getString` → `getStringByNameSync`。
 *     资源**按名称寻址**（与 GetText 同一口径）：`just_now` / `yesterday` / `from_the_future` /
 *     `some_days_ago` / plurals `some_minutes_ago` / `some_hours_ago` / `year` / `day` /
 *     `hour` / `minute` / `second`。资源名缺失时回退为 `<n> <name>`（不抛异常、不返回空串）。
 *  3. `Calendar` 取年份 → `new Date(t).getFullYear()`。
 *  4. `Locale.getDefault().getLanguage().equals("zh")` → 判断系统语言：用
 *     `i18n.System.getSystemLanguage()`（@ohos.i18n），缺省按英文格式。
 *  5. 四个 `SimpleDateFormat` 的 `synchronized` 锁对象 → ArkTS 无共享状态（每次调用新建
 *     格式化中间变量），故无需锁；`sCalendarLock` 同理消失。
 *  6. `long` → `number`；常量名与数值全部保留（SECOND_MILLIS … YEAR_MILLIS、SIZE=5、MULTIPLES）。
 */

import common from '@ohos.app.ability.common';
import resourceManager from '@ohos.resourceManager';
import i18n from '@ohos.i18n';

export class ReadableTime {

  static readonly SECOND_MILLIS: number = 1000;
  static readonly MINUTE_MILLIS: number = 60 * ReadableTime.SECOND_MILLIS;
  static readonly HOUR_MILLIS: number = 60 * ReadableTime.MINUTE_MILLIS;
  static readonly DAY_MILLIS: number = 24 * ReadableTime.HOUR_MILLIS;
  static readonly WEEK_MILLIS: number = 7 * ReadableTime.DAY_MILLIS;
  static readonly YEAR_MILLIS: number = 365 * ReadableTime.DAY_MILLIS;

  static readonly SIZE: number = 5;

  static readonly MULTIPLES: number[] = [
    ReadableTime.YEAR_MILLIS,
    ReadableTime.DAY_MILLIS,
    ReadableTime.HOUR_MILLIS,
    ReadableTime.MINUTE_MILLIS,
    ReadableTime.SECOND_MILLIS
  ];

  /** 对应上游 UNITS（R.plurals.*），改为资源名（见文件头差异 2） */
  static readonly UNIT_NAMES: string[] = ['year', 'day', 'hour', 'minute', 'second'];

  private static sResMgr: resourceManager.ResourceManager | null = null;

  static initialize(context: common.Context): void {
    ReadableTime.sResMgr = context.resourceManager;
  }

  static isInitialized(): boolean {
    return ReadableTime.sResMgr !== null;
  }

  // ── 资源取词 ────────────────────────────────────────────────────────────

  private static str(name: string, fallback: string): string {
    const mgr: resourceManager.ResourceManager | null = ReadableTime.sResMgr;
    if (mgr === null) {
      return fallback;
    }
    try {
      return mgr.getStringByNameSync(name);
    } catch (e) {
      return fallback;
    }
  }

  private static plural(name: string, num: number): string {
    const mgr: resourceManager.ResourceManager | null = ReadableTime.sResMgr;
    if (mgr === null) {
      return `${num} ${name}`;
    }
    try {
      return mgr.getPluralStringByNameSync(name, num);
    } catch (e) {
      return `${num} ${name}`;
    }
  }

  // ── 手写格式化（见文件头差异 1） ─────────────────────────────────────────

  private static pad2(v: number): string {
    return v < 10 ? `0${v}` : `${v}`;
  }

  private static pad3(v: number): string {
    if (v < 10) {
      return `00${v}`;
    }
    if (v < 100) {
      return `0${v}`;
    }
    return `${v}`;
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

  private static isZh(): boolean {
    try {
      const lang: string = i18n.System.getSystemLanguage();
      return lang.toLowerCase().startsWith('zh');
    } catch (e) {
      return false;
    }
  }

  private static monthShort(d: Date): string {
    // 对应 SimpleDateFormat("MMM")：英文三字母缩写（避免 Intl 随系统语言漂移）
    const names: string[] = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return names[d.getMonth()];
  }

  // ── 公开 API（与上游一一对应） ───────────────────────────────────────────

  /** 对应上游 getPlainTime(long)："yy-MM-dd HH:mm" */
  static getPlainTime(time: number): string {
    const d: Date = new Date(time);
    return `${ReadableTime.pad2(d.getFullYear() % 100)}-${ReadableTime.pad2(d.getMonth() + 1)}`
      + `-${ReadableTime.pad2(d.getDate())}`
      + ` ${ReadableTime.pad2(d.getHours())}:${ReadableTime.pad2(d.getMinutes())}`;
  }

  /** 对应上游 getFilenamableTime(long)："yyyy-MM-dd-HH-mm-ss-SSS"（用于文件名，格式必须逐字一致） */
  static getFilenamableTime(time: number): string {
    const d: Date = new Date(time);
    return `${ReadableTime.pad4(d.getFullYear())}-${ReadableTime.pad2(d.getMonth() + 1)}`
      + `-${ReadableTime.pad2(d.getDate())}`
      + `-${ReadableTime.pad2(d.getHours())}`
      + `-${ReadableTime.pad2(d.getMinutes())}`
      + `-${ReadableTime.pad2(d.getSeconds())}`
      + `-${ReadableTime.pad3(d.getMilliseconds())}`;
  }

  /** 对应上游 getTimeAgo(long)：相对时间（阈值逐条照搬） */
  static getTimeAgo(time: number): string {
    const now: number = Date.now();
    if (time > now + (2 * ReadableTime.MINUTE_MILLIS) || time <= 0) {
      return ReadableTime.str('from_the_future', 'From the future');
    }

    const diff: number = now - time;
    if (diff < ReadableTime.MINUTE_MILLIS) {
      return ReadableTime.str('just_now', 'Just now');
    } else if (diff < 2 * ReadableTime.MINUTE_MILLIS) {
      return ReadableTime.plural('some_minutes_ago', 1);
    } else if (diff < 50 * ReadableTime.MINUTE_MILLIS) {
      const minutes: number = Math.trunc(diff / ReadableTime.MINUTE_MILLIS);
      return ReadableTime.plural('some_minutes_ago', minutes);
    } else if (diff < 90 * ReadableTime.MINUTE_MILLIS) {
      return ReadableTime.plural('some_hours_ago', 1);
    } else if (diff < 24 * ReadableTime.HOUR_MILLIS) {
      const hours: number = Math.trunc(diff / ReadableTime.HOUR_MILLIS);
      return ReadableTime.plural('some_hours_ago', hours);
    } else if (diff < 48 * ReadableTime.HOUR_MILLIS) {
      return ReadableTime.str('yesterday', 'Yesterday');
    } else if (diff < ReadableTime.WEEK_MILLIS) {
      const days: number = Math.trunc(diff / ReadableTime.DAY_MILLIS);
      return ReadableTime.str('some_days_ago', `${days} days ago`);
    } else {
      const nowDate: Date = new Date(now);
      const timeDate: Date = new Date(time);
      const nowYear: number = nowDate.getFullYear();
      const timeYear: number = timeDate.getFullYear();
      const zh: boolean = ReadableTime.isZh();
      if (nowYear === timeYear) {
        return zh
          ? `${timeDate.getMonth() + 1}月${timeDate.getDate()}日`
          : `${ReadableTime.monthShort(timeDate)} ${timeDate.getDate()}`;
      }
      return zh
        ? `${timeDate.getFullYear()}年${timeDate.getMonth() + 1}月${timeDate.getDate()}日`
        : `${ReadableTime.monthShort(timeDate)} ${timeDate.getDate()}, ${timeDate.getFullYear()}`;
    }
  }

  /** 对应上游 getTimeInterval(long)：完整降级串（年/天/时/分/秒） */
  static getTimeInterval(time: number): string {
    const sb: string[] = [];
    let leftover: number = time;
    let start: boolean = false;

    for (let i = 0; i < ReadableTime.SIZE; i++) {
      const multiple: number = ReadableTime.MULTIPLES[i];
      const quotient: number = Math.trunc(leftover / multiple);
      const remainder: number = leftover % multiple;
      if (start || quotient !== 0 || i === ReadableTime.SIZE - 1) {
        if (start) {
          sb.push(' ');
        }
        sb.push(`${quotient}`);
        sb.push(' ');
        sb.push(ReadableTime.plural(ReadableTime.UNIT_NAMES[i], quotient));
        start = true;
      }
      leftover = remainder;
    }

    return sb.join('');
  }

  /** 对应上游 getShortTimeInterval(long)：只取第一个"够大"的单位 */
  static getShortTimeInterval(time: number): string {
    const sb: string[] = [];

    for (let i = 0; i < ReadableTime.SIZE; i++) {
      const multiple: number = ReadableTime.MULTIPLES[i];
      const quotient: number = Math.trunc(time / multiple);
      if (time > multiple * 1.5 || i === ReadableTime.SIZE - 1) {
        sb.push(`${quotient}`);
        sb.push(' ');
        sb.push(ReadableTime.plural(ReadableTime.UNIT_NAMES[i], quotient));
        break;
      }
    }

    return sb.join('');
  }
}
