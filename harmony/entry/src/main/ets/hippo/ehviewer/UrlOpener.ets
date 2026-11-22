/*
 * Licensed under the Apache License, Version 2.0 (the "License");
 *
 * ── HarmonyOS 移植记录 ──────────────────────────────────────────────────────
 * 条目   : S0278   上游: com/hippo/ehviewer/UrlOpener.java（64 行）
 * 目标   : harmony/entry/src/main/ets/hippo/ehviewer/UrlOpener.ets
 *
 * 上游 `openUrl(context, url, ehUrl)` 的判断顺序（**这是可移植的全部内容**）：
 * ```
 * 1. TextUtils.isEmpty(url) → 直接返回（什么都不做）
 * 2. ehUrl == true 时先试 EhUrlOpener.parseUrl(url)
 *      → 解析出目标就用**应用内**页面打开（Announcer + StageActivity），然后 return
 * 3. 否则一律用系统浏览器打开（Intent.ACTION_VIEW），失败 Toast
 * ```
 * 三个要点：
 *  · **`ehUrl` 为 false 时完全不尝试应用内**（即使 URL 是 EH 链接）—— 调用方决定
 *  · 应用内解析**失败**时才降级到浏览器（不是"两边都开"）
 *  · 空串/`null` 在**最前面**短路，连解析都不做
 *
 * ## 一处上游怪癖（照搬）
 * ```java
 * try { if (TextUtils.isEmpty(url)) return; } catch (VerifyError ignore) { return; }
 * ```
 * 一个 `TextUtils.isEmpty` 被包在 `catch (VerifyError)` 里 —— 这是**旧版本 Android 的兼容兜底**
 * （`TextUtils` 在极老 API 上缺失会触发 `VerifyError`）。鸿蒙无此问题 → 不移植 try/catch，
 * 但**保留"空串直接返回"的短路行为**。
 *
 * ## 平台差异
 *  · `Intent(ACTION_VIEW)` + `Browser.EXTRA_APPLICATION_ID` → 注入 `openExternal(url, packageName)`
 *    （鸿蒙用 `@ohos.app.ability.common.UIAbilityContext.openLink` 或 want 启动浏览器）
 *  · `Intent(MainActivity)` + `StageActivity.KEY_SCENE_*` → 已在 `OpenTarget`（EhUrlOpener 的产物）里
 *    表达为 `kind/action/gid/token/pToken/page`，由 ui-scene 的路由层消费
 *  · `Toast` → 调用方渲染
 */

import { EhUrlOpener, OpenTarget } from './client/EhUrlOpener';

/** 打开决策（对应上游三条分支） */
export enum UrlOpenDecision {
  /** 什么都不做（空 URL） */
  NONE = 0,
  /** 用应用内页面打开（`ehUrl` 且解析成功） */
  IN_APP = 1,
  /** 用系统浏览器打开 */
  EXTERNAL = 2
}

export class UrlOpener {

  /**
   * 对应上游 `openUrl` 的**决策部分**（不含实际启动动作）。
   * @param ehUrl 是否尝试应用内打开（上游第三个参数）
   * @returns NONE / IN_APP / EXTERNAL
   */
  static decide(url: string | null, ehUrl: boolean): UrlOpenDecision {
    // 1. 空 URL 最前面短路（连解析都不做）
    if (url === null || url.length === 0) {
      return UrlOpenDecision.NONE;
    }
    // 2. 只有 ehUrl 为 true 才尝试应用内
    if (ehUrl) {
      const target: OpenTarget | null = EhUrlOpener.parseUrl(url);
      if (target !== null) {
        return UrlOpenDecision.IN_APP;
      }
    }
    // 3. 其余一律外部浏览器
    return UrlOpenDecision.EXTERNAL;
  }

  /**
   * 对应上游 `openUrl` 的完整编排（启动动作注入）。
   * @param openInApp 应用内路由（`OpenTarget` 非空时调用）
   * @param openExternal 外部浏览器（`url` + `packageName`）
   * @returns 实际走了哪条分支
   */
  static openUrl(url: string | null, ehUrl: boolean, packageName: string,
    openInApp: (target: OpenTarget) => void,
    openExternal: (url: string, packageName: string) => void): UrlOpenDecision {
    const decision: UrlOpenDecision = UrlOpener.decide(url, ehUrl);
    if (decision === UrlOpenDecision.NONE) {
      return decision;
    }
    if (decision === UrlOpenDecision.IN_APP) {
      const target: OpenTarget | null = EhUrlOpener.parseUrl(url as string);
      if (target !== null) {
        openInApp(target);
        return UrlOpenDecision.IN_APP;
      }
      // 理论上不会到这里（decide 已经解析成功过）；保守降级到外部
      openExternal(url as string, packageName);
      return UrlOpenDecision.EXTERNAL;
    }
    openExternal(url as string, packageName);
    return UrlOpenDecision.EXTERNAL;
  }
}
