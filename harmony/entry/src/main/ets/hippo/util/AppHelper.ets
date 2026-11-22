/*
 * Licensed under the Apache License, Version 2.0 (the "License");
 *
 * ── HarmonyOS 移植记录 ──────────────────────────────────────────────────────
 * 条目   : S0481   上游: com/hippo/util/AppHelper.kt（150 行）
 * 目标   : harmony/entry/src/main/ets/hippo/util/AppHelper.ets
 *
 * 8 个成员，按"可移植性"分两类：
 *
 * **纯逻辑（已移植、可断言）**
 *  · `compareVersion(v1, v2)` —— 点分段逐段比数值，长度不齐补 0
 *  · `isWifiProxy(...)`      —— 判 `http.proxyHost` 非空 **且** `http.proxyPort != -1`
 *  · `checkVPN(...)`         —— **返回取反**（`!isVpn`：true = 可用）
 *  · `copyPlainText(...)`    —— `ClipData.newPlainText(null, data)`（**不看空串**，上游没有 isEmpty 判断）
 *  · `mailtoUri(address)` / `buildMailtoRequest(...)` —— `mailto:<address>` + 可选 subject/text
 *
 * **平台动作（不移植，归 ui-scene/ui-widget）**
 *  · `sendEmail` / `share`   —— `Intent.ACTION_SENDTO` / `ACTION_SEND` + `startActivity` + Toast
 *  · `showSoftInput` / `hideSoftInput` —— `InputMethodManager`（ArkUI 用 `focusControl` / `TextInput` 自带行为）
 *
 * ## 两个必须照搬的坑
 * 1. **`compareVersion` 的 `toInt()` 会抛**：上游 `parts1[i].toInt()` 对 `"2-beta"` 直接
 *    `NumberFormatException`。**不是**"当成 0 继续比"。本实现同样**抛错**（`parseStrictInt`），
 *    因为静默返回 0 会让"版本号格式错误"变成"版本相等"，进而**静默不提示更新**。
 * 2. **`isWifiProxy` 的 `portStr.toInt()` 同样会抛**（`"abc"` → NumberFormatException）；
 *    且 **`proxyHost` 为空串时短路**（`TextUtils.isEmpty` 而非仅判 null）→ `""` 视为没有代理。
 * 3. `checkVPN` 的返回值是 **`!result`** —— 名字叫 checkVPN，**true 表示"没有 VPN"**。
 *    调用方若按字面理解会写反，这里在方法名后加注释并在断言里钉住。
 */

import { Clipboard } from '../ehviewer/util/ClipboardUtil';
import hilog from '@ohos.hilog';

/** 邮件意图的可移植部分（`Intent.ACTION_SENDTO` + `mailto:` + 两个可选 extra） */
export class MailtoRequest {
  address: string;
  subject: string | null;
  text: string | null;

  constructor(address: string, subject: string | null, text: string | null) {
    this.address = address;
    this.subject = subject;
    this.text = text;
  }

  /** 对应上游 `i.setData(Uri.parse("mailto:$address"))` */
  getUri(): string {
    return 'mailto:' + this.address;
  }

  /** 对应上游两个 `if (… != null) i.putExtra(...)` —— null 时**不放这个 extra** */
  hasSubject(): boolean {
    return this.subject !== null;
  }

  hasText(): boolean {
    return this.text !== null;
  }
}

export class AppHelper {

  static readonly TAG: string = 'AppHelper';

  /**
   * 对应上游 `isWifiProxy(context)`（**注意：方法名带 WiFi，实际只看 HTTP 代理系统属性**，
   * `context` 在方法体里**完全没用到** —— 上游就是这样）。
   * @param proxyHost `System.getProperty("http.proxyHost")`；null = 未设置
   * @param portStr   `System.getProperty("http.proxyPort")`；null = 未设置
   * @returns 有代理 → true
   */
  static isWifiProxy(proxyHost: string | null, portStr: string | null): boolean {
    // 上游：proxyPort = (portStr != null ? portStr : "-1").toInt()  ← 非数字会抛
    const proxyPort: number = AppHelper.parseStrictInt((portStr !== null) ? portStr : '-1');
    // 上游：!TextUtils.isEmpty(proxyAddress) && proxyPort != -1   ← 空串视为"无代理"
    return (!AppHelper.isEmpty(proxyHost)) && proxyPort !== -1;
  }

  /** 对应上游 `TextUtils.isEmpty(CharSequence)`：null 或长度 0 */
  static isEmpty(s: string | null): boolean {
    return s === null || s.length === 0;
  }

  /**
   * 对应 Java/Kotlin `String.toInt()`：**非数字直接抛错**（不返回默认值）。
   * 这是故意的 —— 见文件头坑 1。允许前导 `-`（上游 `"-1"` 就是负数字面量）。
   */
  static parseStrictInt(s: string): number {
    if (!/^-?[0-9]+$/.test(s)) {
      throw new Error(`For input string: "${s}"`);
    }
    const v: number = Number(s);
    if (!Number.isSafeInteger(v)) {
      throw new Error(`For input string: "${s}"`);
    }
    return v;
  }

  /** 对应上游 `sendEmail` 的意图构造部分；发送动作归 ui-scene */
  static buildMailtoRequest(address: string, subject: string | null, text: string | null): MailtoRequest {
    return new MailtoRequest(address, subject, text);
  }

  /**
   * 对应上游 `copyPlainText(data, context)`：
   * `ClipData.newPlainText(null, data)` + `setPrimaryClip`。
   * ⚠️ **上游没有 null/空串判断**（与 `ClipboardUtil.copyText` 不同）→ 传 null 也会写进剪贴板。
   */
  static copyPlainText(data: string | null, clipboard: Clipboard): void {
    clipboard.setPrimaryClipText((data === null) ? 'null' : data);
  }

  /**
   * 对应上游 `checkVPN(context)`：
   * @param isVpnNetwork 当前活动网络是否为 `TYPE_VPN`
   * @returns **true = 没有 VPN（可用）** —— 上游 `return !result`，名字与实际相反
   */
  static checkVpn(isVpnNetwork: boolean): boolean {
    return !isVpnNetwork;
  }

  /**
   * 对应上游 `compareVersion(version1, version2)`：
   * 按 `.` 分段逐段比数值，缺段补 0；任一段非数字 → **抛错**（上游 `toInt()` 行为）。
   * @returns -1 / 0 / 1
   */
  static compareVersion(version1: string, version2: string): number {
    const parts1: string[] = version1.split('.');
    const parts2: string[] = version2.split('.');
    const length: number = Math.max(parts1.length, parts2.length);
    for (let i = 0; i < length; i++) {
      const part1: number = (i < parts1.length) ? AppHelper.parseStrictInt(parts1[i]) : 0;
      const part2: number = (i < parts2.length) ? AppHelper.parseStrictInt(parts2[i]) : 0;
      if (part1 < part2) {
        return -1;
      } else if (part1 > part2) {
        return 1;
      }
    }
    return 0;
  }
}
