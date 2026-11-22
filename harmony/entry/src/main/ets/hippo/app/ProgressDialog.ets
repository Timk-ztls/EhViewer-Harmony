/*
 * Licensed under the Apache License, Version 2.0 (the "License");
 *
 * ── HarmonyOS 移植记录 ──────────────────────────────────────────────────────
 * 条目   : S0005   上游: com/hippo/app/ProgressDialog.kt（306 行，AOSP 派生）
 * 目标   : harmony/entry/src/main/ets/hippo/app/ProgressDialog.ets
 *
 * 【**部分移植**：状态机（"视图未创建时的延迟值"）+ 文案格式化；AlertDialog 本身归 ui-widget】
 *
 * 上游整个类是在 `AlertDialog` 外面包了一层**延迟应用**逻辑：
 *   每个 setter 都写成 `if (mProgress != null) { 直接设视图 } else { 存到 mXxx 字段 }`，
 *   然后在 `onCreate` 里按固定顺序把存下来的值**回放**给视图。
 *   这套状态机（哪些值要延迟、回放顺序、getter 该读视图还是读缓存）是**纯逻辑**，可完全断言；
 *   而 `AlertDialog`/`ProgressBar`/`TextView`/`Handler`/`Drawable` 全部是 Android UI。
 *
 * 移植：
 *   · `ProgressStyle` 常量（SPINNER=0 / HORIZONTAL=1）
 *   · `ProgressDialogState` —— 状态机：setter 延迟 / getter 读哪边 / `applyPending()` 回放顺序
 *   · `formatProgressNumber(progress, max, format)` —— 上游 `String.format("%1d/%2d", ...)`
 *   · `formatProgressPercent(progress, max)` —— 上游 `NumberFormat.getPercentInstance()`（**0 位小数**）
 *   · `ProgressDialog.show(...)` 的参数装配顺序（`setTitle → setMessage → setIndeterminate → ...`）
 *
 * 不移植（Android UI）：
 *   `AlertDialog` 继承、`onCreate/onStart/onStop`、`LayoutInflater`、`findViewById`、
 *   `Handler(Looper.getMainLooper())`、`SpannableString/StyleSpan`、`Drawable`、`NumberFormat`
 */

/** 上游 companion 的两个样式常量 */
export enum ProgressStyle {
  /** 圆形旋转进度（默认） */
  STYLE_SPINNER = 0,
  /** 横向进度条 */
  STYLE_HORIZONTAL = 1
}

/** `NumberFormat.getPercentInstance()` 默认行为在 `initFormats` 里被改成 **0 位小数** */
export class ProgressDialogState {

  progressStyle: ProgressStyle = ProgressStyle.STYLE_SPINNER;
  /** 上游 `mProgressNumberFormat = "%1d/%2d"` */
  progressNumberFormat: string | null = '%1d/%2d';
  /** 上游 `mProgressPercentFormat != null`（默认非 null） */
  progressPercentFormatEnabled: boolean = true;

  /** 视图是否已创建（上游 `mProgress != null` 的等价物） */
  private viewReady: boolean = false;
  /** 上游 `mHasStarted`（决定 `setProgress` 是即时生效还是延迟） */
  private hasStarted: boolean = false;

  // 延迟值（视图未创建时存这里）
  private max: number = 0;
  private progressVal: number = 0;
  private secondaryProgressVal: number = 0;
  private incrementBy: number = 0;
  private incrementSecondaryBy: number = 0;
  private indeterminate: boolean = false;
  private message: string | null = null;

  // 已生效值（视图创建后由 setters 直接改这里）
  private appliedMax: number = 0;
  private appliedProgress: number = 0;
  private appliedSecondaryProgress: number = 0;
  private appliedIndeterminate: boolean = false;

  /** 对应上游 `onCreate` 里"视图已就绪"那一刻 */
  markViewReady(): void {
    this.viewReady = true;
  }

  /** 对应上游 `onStart` */
  markStarted(): void {
    this.hasStarted = true;
  }

  /** 对应上游 `onStop` */
  markStopped(): void {
    this.hasStarted = false;
  }

  /**
   * 对应上游 `onCreate` 的**回放顺序**（`if (mMax > 0) setMax(mMax)` … `setIndeterminate(mIndeterminate)`）：
   * 注意上游的回放条件各不相同 —— `max/progress/secondary/increment*` 只在 **> 0** 时回放，
   * 而 `indeterminate`/`message` 无条件回放。这个不对称是上游原样。
   */
  applyPending(): void {
    this.viewReady = true;
    if (this.max > 0) {
      this.appliedMax = this.max;
    }
    if (this.progressVal > 0) {
      this.appliedProgress = this.progressVal;
    }
    if (this.secondaryProgressVal > 0) {
      this.appliedSecondaryProgress = this.secondaryProgressVal;
    }
    if (this.incrementBy > 0) {
      this.appliedProgress = this.appliedProgress + this.incrementBy;
    }
    if (this.incrementSecondaryBy > 0) {
      this.appliedSecondaryProgress = this.appliedSecondaryProgress + this.incrementSecondaryBy;
    }
    this.appliedIndeterminate = this.indeterminate;
  }

  setMax(max: number): void {
    if (this.viewReady) {
      this.appliedMax = max;
    } else {
      this.max = max;
    }
  }

  /**
   * 上游 `setProgress` 用的是 **`mHasStarted`**（不是 `mProgress != null`）：
   * 视图已建但还没 `onStart` 时，值仍然被**延迟**。这是上游唯一用 hasStarted 的 setter。
   */
  setProgress(value: number): void {
    if (this.hasStarted) {
      this.appliedProgress = value;
    } else {
      this.progressVal = value;
    }
  }

  setSecondaryProgress(value: number): void {
    if (this.viewReady) {
      this.appliedSecondaryProgress = value;
    } else {
      this.secondaryProgressVal = value;
    }
  }

  incrementProgressBy(diff: number): void {
    if (this.viewReady) {
      this.appliedProgress = this.appliedProgress + diff;
    } else {
      this.incrementBy += diff;
    }
  }

  incrementSecondaryProgressBy(diff: number): void {
    if (this.viewReady) {
      this.appliedSecondaryProgress = this.appliedSecondaryProgress + diff;
    } else {
      this.incrementSecondaryBy += diff;
    }
  }

  setIndeterminate(v: boolean): void {
    if (this.viewReady) {
      this.appliedIndeterminate = v;
    } else {
      this.indeterminate = v;
    }
  }

  setMessage(message: string | null): void {
    if (this.viewReady) {
      // 水平样式走 AlertDialog.setMessage，其它样式改内部 TextView —— 两者都只是"显示"
      this.message = message;
    } else {
      this.message = message;
    }
  }

  /** 对应上游 `getProgress()`：视图就绪前读缓存。**注意它不看 hasStarted**（与 setter 不对称，上游原样） */
  getProgress(): number {
    return this.viewReady ? this.appliedProgress : this.progressVal;
  }

  getSecondaryProgress(): number {
    return this.viewReady ? this.appliedSecondaryProgress : this.secondaryProgressVal;
  }

  getMax(): number {
    return this.viewReady ? this.appliedMax : this.max;
  }

  isIndeterminate(): boolean {
    return this.viewReady ? this.appliedIndeterminate : this.indeterminate;
  }

  getMessage(): string | null {
    return this.message;
  }

  setProgressStyle(style: ProgressStyle): void {
    this.progressStyle = style;
  }
}

export class ProgressDialogHelper {

  static readonly STYLE_SPINNER: number = 0;
  static readonly STYLE_HORIZONTAL: number = 1;

  /**
   * 对应上游 `onCreate` 里 `String.format(mProgressNumberFormat, progress, max)`：
   * 只支持 `%1d`（当前）与 `%2d`（最大）两个占位符；**format 为 null → 空串**（上游 else 分支）。
   */
  static formatProgressNumber(progress: number, max: number, format: string | null): string {
    if (format === null) {
      return '';
    }
    return format.split('%1d').join(`${progress}`).split('%2d').join(`${max}`);
  }

  /**
   * 对应上游 `NumberFormat.getPercentInstance()` + `setMaximumFractionDigits(0)`：
   * 上游原文**没有任何守卫**，直接算 `val percent = progress.toDouble() / max.toDouble()`：
   * ```
   * progress=0, max=0 → 0.0/0.0 = NaN       → DecimalFormat 输出 "NaN"
   * progress=5, max=0 → 5.0/0.0 = +Infinity → DecimalFormat 输出 "∞"（U+221E）
   * progress=-5,max=0 → -Infinity           → "-∞"
   * 其它              → p/max*100，按 **HALF_EVEN**（Java DecimalFormat 默认）取 0 位小数，加 '%'
   * ```
   * ⚠️ **更正**：本实现的第一版写成 `max <= 0 → 'NaN'`，把 `progress>0, max=0` 也当成 NaN ——
   * 那是错的（Java 里 5.0/0.0 是 Infinity，不是 NaN）。已在断言里区分三条路径。
   * @param enabled 对应上游 `mProgressPercentFormat != null`；false → 空串
   */
  static formatProgressPercent(progress: number, max: number, enabled: boolean): string {
    if (!enabled) {
      return '';
    }
    const ratio: number = progress / max; // JS 与 Java double 语义一致：0/0=NaN，±x/0=±Infinity
    if (Number.isNaN(ratio)) {
      return 'NaN';
    }
    if (!Number.isFinite(ratio)) {
      return ratio > 0 ? '\u221E' : '-\u221E';
    }
    return `${ProgressDialogHelper.roundHalfEven(ratio * 100)}%`;
  }

  /**
   * Java `DecimalFormat` 的**默认舍入模式是 HALF_EVEN**（不是 HALF_UP / JS 的 `Math.round`）。
   * 差异只在"恰好 .5"时出现：`1/8 = 12.5% → 12`（HALF_UP 会给 13）。
   */
  static roundHalfEven(v: number): number {
    const f: number = Math.floor(v);
    const diff: number = v - f;
    if (diff > 0.5) {
      return f + 1;
    }
    if (diff < 0.5) {
      return f;
    }
    // 恰好 .5 → 取偶数
    return (f % 2 === 0) ? f : f + 1;
  }

  /**
   * 对应上游 companion `show(context, title, message, indeterminate, cancelable, listener)` 的
   * **调用顺序**（`setTitle → setMessage → setIndeterminate → setCancelable → setOnCancelListener → show`）。
   * 返回被调用的方法名序列，供 UI 层按序执行 / 供测试断言顺序。
   */
  static buildShowSequence(indeterminate: boolean, cancelable: boolean,
    hasCancelListener: boolean): string[] {
    const seq: string[] = ['setTitle', 'setMessage', `setIndeterminate(${indeterminate})`,
      `setCancelable(${cancelable})`];
    if (hasCancelListener) {
      seq.push('setOnCancelListener');
    }
    seq.push('show');
    return seq;
  }
}