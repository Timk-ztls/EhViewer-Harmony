/*
 * 上游：app/src/main/java/com/hippo/ehviewer/ui/SetSecurityActivity.java
 *       （inventory S0269，上游 122 行；清单登记 109 行）
 * 目标：harmony/entry/src/main/ets/hippo/ehviewer/ui/SetSecurityActivity.ets
 *
 * 背景：**设置/修改手势安全码**页面。一个 LockPatternView + 取消/设置两个按钮 + 指纹勾选框。
 * 点"设置"把手势串写进 Settings，并按规则决定是否启用指纹。
 *
 * ── ⚠️ 依赖状态（开工前查过，如实记录）────────────────────────────────────────
 * `PatternLockView`（上游 `com.hippo.widget.lockpattern.LockPatternView`）**本仓不存在**
 * （全仓 `git grep -i PatternLock` 在 .ets 下 0 命中；`ui-widget` 的 64 控件清单里也没有它）。
 * ↳ 本文件因此**只落"页面逻辑 + 依赖接口"**，图案锁视图本体由 `ui-widget` 交付（Lead 已知情并已派工）。
 * 本仓**已有**的同类件：
 *   · `LockPatternUtils`（`stringToPattern` / `patternToString` / `isPatternVaild`）✅
 *   · `SecurityScene`（手势锁校验/摇一摇解锁，已由 ui-widget 落地）✅
 *
 * ── 上游行为逐条对照 ────────────────────────────────────────────────────────
 * 字段：`mPatternView` / `mCancel` / `mSet` / `mFingerprint`（**全部可空**）
 * `onCreate`：
 *   ① 布局 `activity_set_security` + 返回图标 `v_arrow_left_dark_x24`
 *   ② 取四个控件
 *   ③ **`pattern = Settings.getSecurity()`；`!TextUtils.isEmpty(pattern)`** →
 *      `mPatternView.setPattern(DisplayMode.Correct, LockPatternUtils.stringToPattern(pattern))`
 *      —— 即"已设过安全码就把手势**回显**出来"（`Correct` 模式 = 绿色）
 *   ④ 指纹：**API 23+ 且 `hasEnrolledFingerprints(...)`** →
 *      `mFingerprint.VISIBLE` + `setChecked(Settings.getEnableFingerprint())`
 *   ⑤ `mCancel` / `mSet` 绑 `onClick`
 * `hasEnrolledFingerprints(fm)`：`isHardwareDetected() && hasEnrolledFingerprints()`，
 *   **catch (Throwable) → false**（某些设备会抛）
 * `onDestroy`：`mPatternView = null`
 * `onOptionsItemSelected(home)` → `finish()` + **true**
 * `onClick(v)`：
 *   · `v == mCancel` → `finish()`
 *   · `v == mSet`：
 *     **`mPatternView != null && mFingerprint != null`** 才处理：
 *     ① **`mPatternView.getCellSize() <= 1` → `security = ""`**；否则 `security = getPatternString()`
 *        （**"至少连两个点"才算有效手势** —— 只点一个点 = 清空安全码）
 *     ② `Settings.putSecurity(security)`
 *     ③ `Settings.putEnableFingerprint(mFingerprint.VISIBLE && isChecked() && **!security.isEmpty()**)`
 *        —— 三个条件**同时**成立才启用指纹；安全码为空时**强制关指纹**（空安全码下指纹无意义）
 *     ④ `finish()`（**无论是否处理都 finish**）
 *
 * ── 关键行为（照搬，别"顺手修"）──────────────────────────────────────────────
 * 1. **`getCellSize() <= 1` → 空串**：单元格尺寸 ≤1 表示"视图还没布局/没有有效手势"，
 *    上游借此把"没连成手势"当成"清空安全码"。**不是"少于 2 个点"**，是**单元格尺寸**。
 * 2. **指纹启用是三条与**：可见 && 勾选 && **security 非空**。第三条最容易被漏。
 * 3. **`finish()` 在 if 之外** —— `mPatternView`/`mFingerprint` 为 null 时**不写设置但仍然退出**。
 * 4. **回显用 `DisplayMode.Correct`**（已正确的绿态），不是正常态。
 * 5. **`hasEnrolledFingerprints` 吞掉 Throwable** —— 硬件探测在各家 ROM 上不可靠。
 * 6. **`onDestroy` 只把 `mPatternView` 置 null**（`mCancel`/`mSet`/`mFingerprint` 不动）。
 *
 * ── 平台差异 ────────────────────────────────────────────────────────────────
 * 1. `LockPatternView` 不存在 → `PatternViewPort`（只钉上游用到的三个方法：
 *    `setPattern(mode, cells)` / `getCellSize()` / `getPatternString()`）。**视图本体归 ui-widget**。
 * 2. `FingerprintManager`（Android 硬件指纹）→ `SecurityHost.hasEnrolledFingerprints()`；
 *    HarmonyOS 侧用 `@ohos.userIAM.userAuth`，由页面层实现（本文件只依赖布尔结果）。
 * 3. `Settings.getSecurity/putSecurity/getEnableFingerprint/putEnableFingerprint` →
 *    `SecuritySettings`（与 `SecurityScene` 已用的 `SecuritySettings` 同形状）。
 * 4. `ToolbarActivity` → `SecurityHost.finish()` + `setNavigationIcon()`。
 * 5. `TextUtils.isEmpty` → `s === null || s.length === 0`。
 *
 * ── 依赖实测（本仓已存在）──────────────────────────────────────────────────
 * `LockPatternUtils.stringToPattern` / `patternToString`、`hippo/ui/layout/activity_set_security.ets`、
 * 字符串 `webview_unavailable_*`（本文件不用，`MyTagsActivity` 用）。
 */

import { LockPatternUtils } from '../../widget/lockpattern/LockPatternUtils';

/** 上游 `R.layout.activity_set_security` / 返回图标 */
export const LAYOUT_ACTIVITY_SET_SECURITY: string = 'activity_set_security';
export const DRAWABLE_BACK: string = 'v_arrow_left_dark_x24';
/** 上游 `LockPatternView.DisplayMode.Correct`（回显已设手势时用绿态） */
export const DISPLAY_MODE_CORRECT: number = 2;

/** 上游 `LockPatternView` 的最小端口（见「平台差异」1：视图本体归 ui-widget） */
export interface PatternViewPort {
  /** 上游 `setPattern(DisplayMode, List<Cell>)` */
  setPattern(mode: number, cells: Object | null): void;
  /** 上游 `getCellSize()` —— ★`<= 1` 表示无有效手势（见「关键行为」1） */
  getCellSize(): number;
  /** 上游 `getPatternString()` */
  getPatternString(): string;
}

/** 安全码/指纹设置的读写（与 `SecurityScene` 同形状） */
export interface SecuritySettings {
  getSecurity(): string | null;
  putSecurity(security: string): void;
  getEnableFingerprint(): boolean;
  putEnableFingerprint(enabled: boolean): void;
}

/** 宿主能力 */
export interface SecurityHost {
  /** 上游 `FingerprintManager` 可用性 + 已录入（见「关键行为」5） */
  hasEnrolledFingerprints(): boolean;
  /** 上游 `mFingerprint.setVisibility(VISIBLE/GONE)` */
  setFingerprintVisible(visible: boolean): void;
  /** 上游 `mFingerprint.setChecked(...)` */
  setFingerprintChecked(checked: boolean): void;
  /** 上游 `mFingerprint.getVisibility() == VISIBLE` */
  isFingerprintVisible(): boolean;
  /** 上游 `mFingerprint.isChecked()` */
  isFingerprintChecked(): boolean;
  /** 上游 `mPatternView.setPattern(...)`（转给 PatternViewPort） */
  getPatternView(): PatternViewPort | null;
  setNavigationIcon(icon: string): void;
  /** 上游 `finish()` */
  finish(): void;
}

export class SetSecurityActivity {
  private host: SecurityHost;
  private settings: SecuritySettings;
  /** 上游 `mPatternView != null && mFingerprint != null` 的等价 */
  private viewsReady: boolean = false;

  constructor(host: SecurityHost, settings: SecuritySettings) {
    this.host = host;
    this.settings = settings;
  }

  /**
   * 上游 `onCreate` 的装配：
   * ① 返回图标 ② **回显已有安全码**（`Correct` 模式）③ 指纹区可见性 + 勾选
   * @returns 是否回显了手势
   */
  onCreate(): boolean {
    this.host.setNavigationIcon(DRAWABLE_BACK);
    const pv: PatternViewPort | null = this.host.getPatternView();
    const fingerprintAvailable: boolean = this.hasEnrolledFingerprints();
    // 上游：`mPatternView != null && mFingerprint != null` 才认为控件齐了
    this.viewsReady = pv !== null;

    let echoed: boolean = false;
    // ③ 已设过安全码 → 回显（`TextUtils.isEmpty(pattern)` 的否定）
    const pattern: string | null = this.settings.getSecurity();
    if (pattern !== null && pattern.length > 0 && pv !== null) {
      pv.setPattern(DISPLAY_MODE_CORRECT, LockPatternUtils.stringToPattern(pattern));
      echoed = true;
    }

    // ④ 指纹：只有"硬件可用且已录入"才显示，并按设置勾选
    if (fingerprintAvailable) {
      this.host.setFingerprintVisible(true);
      this.host.setFingerprintChecked(this.settings.getEnableFingerprint());
    }
    return echoed;
  }

  /**
   * 上游 `hasEnrolledFingerprints(fm)`：`isHardwareDetected() && hasEnrolledFingerprints()`，
   * **catch Throwable → false**。本仓由宿主实现硬件探测，这里只做"吞异常"的等价包装。
   */
  hasEnrolledFingerprints(): boolean {
    try {
      return this.host.hasEnrolledFingerprints();
    } catch (e) {
      return false;   // 上游：catch (Throwable e) { return false; }
    }
  }

  /** 上游 `onDestroy`：**只把 patternView 置 null**（见「关键行为」6） */
  onDestroy(): void {
    this.viewsReady = false;
  }

  /** 上游 `onOptionsItemSelected(home)` → finish + true */
  onOptionsItemSelected(itemId: string): boolean {
    if (itemId === 'android.R.id.home') {
      this.host.finish();
      return true;
    }
    return false;
  }

  /** 上游 `onClick(v == mCancel)` → finish */
  onCancel(): void {
    this.host.finish();
  }

  /**
   * 上游 `onClick(v == mSet)`：
   * ① **`getCellSize() <= 1 → security = ""`** ② `putSecurity` ③ 三条与决定指纹 ④ **无条件 finish**
   * @returns 写入的 security（未写设置时返回 null）
   */
  onSet(): string | null {
    const pv: PatternViewPort | null = this.host.getPatternView();
    // 上游：if (null != mPatternView && null != mFingerprint) { ... }
    if (pv !== null && this.viewsReady) {
      let security: string = '';
      // ★ 单元格尺寸 <= 1 → 视为"没有有效手势" = 清空安全码（见「关键行为」1）
      if (pv.getCellSize() <= 1) {
        security = '';
      } else {
        security = pv.getPatternString();
      }
      this.settings.putSecurity(security);
      // ★ 三条与：可见 && 勾选 && security 非空（见「关键行为」2）
      const enableFingerprint: boolean = this.host.isFingerprintVisible()
        && this.host.isFingerprintChecked()
        && security.length > 0;
      this.settings.putEnableFingerprint(enableFingerprint);
      // 上游：finish() 在 if 之外
      this.host.finish();
      return security;
    }
    this.host.finish();
    return null;
  }
}

