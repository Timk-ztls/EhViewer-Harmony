/*
 * Licensed under the Apache License, Version 2.0 (the "License");
 *
 * ── HarmonyOS 移植记录 ──────────────────────────────────────────────────────
 * 条目   : S0169   上游: com/hippo/ehviewer/preference/IdentityCookiePreference.java（92 行）
 * 目标   : harmony/entry/src/main/ets/hippo/ehviewer/preference/IdentityCookiePreference.ets
 *
 * 【D-033 拆分】上游是 `MessagePreference`（UI）。本文件只保留**身份 cookie 的解析与展示串构造**：
 *   · `init()` 里遍历 E 站 + ex 站 cookie，抓 `ipb_member_id` / `ipb_pass_hash` / `igneous`
 *   · 有任一 → 构造 `KEY: value<br>KEY: value<br>KEY: value`，并用**去掉 `<br>` 的纯文本**做剪贴板内容
 *   · 全空 → "游客"文案
 * UI（对话框 / 复制按钮 / ClipboardManager / Toast）归 ui-widget。
 *
 * 平台差异：
 *  1. `okhttp3.Cookie` → 只取 `name/value` 两个字段的最小结构 `CookieLike`（注入），
 *     避免 core-runtime 依赖 okhttp 的具体实现。
 *  2. `Html.fromHtml(...)` **不移植**（D-036：fromHtml 的产物是 Spanned，鸿蒙无对应物）——
 *     本实现直接返回**HTML 片段**，由 ui-widget 用 RichText/StyledString 渲染。
 *  3. `ClipboardManager/ClipData` → 返回纯文本，由 UI 层调 `@ohos.pasteboard`。
 *  4. **上游语义保留**：同一个 key 出现多次时**后者覆盖前者**（循环里直接赋值，不判空）。
 */

/** 上游 `okhttp3.Cookie` 只用到的两个字段 */
export interface CookieLike {
  name: string;
  value: string;
}

/** 身份 cookie 三元组（任一存在即视为已登录身份） */
export class IdentityCookieInfo {
  ipbMemberId: string | null = null;
  ipbPassHash: string | null = null;
  igneous: string | null = null;

  /** 上游判定：`ipbMemberId != null || ipbPassHash != null || igneous != null` */
  hasIdentity(): boolean {
    return this.ipbMemberId !== null || this.ipbPassHash !== null || this.igneous !== null;
  }

  /** 对应上游 `message`（HTML，`<br>` 分隔；null 值原样输出 "null"，与上游字符串拼接一致） */
  toHtml(): string {
    return IdentityCookiePreference.KEY_IPD_MEMBER_ID + ': ' + IdentityCookiePreference.text(this.ipbMemberId)
      + '<br>'
      + IdentityCookiePreference.KEY_IPD_PASS_HASH + ': ' + IdentityCookiePreference.text(this.ipbPassHash)
      + '<br>'
      + IdentityCookiePreference.KEY_IGNEOUS + ': ' + IdentityCookiePreference.text(this.igneous);
  }

  /** 对应上游 `message.replace("<br>", "\n")` —— **注意：上游只替换第一处**（String.replace 非全局） */
  toPlainText(): string {
    const html: string = this.toHtml();
    const idx: number = html.indexOf('<br>');
    if (idx < 0) {
      return html;
    }
    return html.substring(0, idx) + '\n' + html.substring(idx + 4);
  }
}

export class IdentityCookiePreference {

  /** 上游 `EhCookieStore.KEY_IPD_MEMBER_ID` */
  static readonly KEY_IPD_MEMBER_ID: string = 'ipb_member_id';
  /** 上游 `EhCookieStore.KEY_IPD_PASS_HASH` */
  static readonly KEY_IPD_PASS_HASH: string = 'ipb_pass_hash';
  /** 上游 `EhCookieStore.KEY_IGNEOUS` */
  static readonly KEY_IGNEOUS: string = 'igneous';

  /**
   * 对应上游 `init()` 的解析段：把 E 站 + ex 站 cookie 合并后按名字抓三个值。
   * @param cookies 由调用方把两个 host 的 cookie 合成一个数组（上游 `new LinkedList<>(e); addAll(ex)`）
   */
  static build(cookies: CookieLike[]): IdentityCookieInfo {
    const info: IdentityCookieInfo = new IdentityCookieInfo();
    for (let i = 0; i < cookies.length; i++) {
      const c: CookieLike = cookies[i];
      // 上游 switch：同名**后者覆盖前者**
      if (c.name === IdentityCookiePreference.KEY_IPD_MEMBER_ID) {
        info.ipbMemberId = c.value;
      } else if (c.name === IdentityCookiePreference.KEY_IPD_PASS_HASH) {
        info.ipbPassHash = c.value;
      } else if (c.name === IdentityCookiePreference.KEY_IGNEOUS) {
        info.igneous = c.value;
      }
    }
    return info;
  }

  /** 上游字符串拼接里 null 会变成字面 "null" —— 逐字保留该行为 */
  static text(v: string | null): string {
    return (v === null) ? 'null' : v;
  }
}
