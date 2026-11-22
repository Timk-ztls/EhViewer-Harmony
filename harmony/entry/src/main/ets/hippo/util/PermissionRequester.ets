/*
 * Licensed under the Apache License, Version 2.0 (the "License");
 *
 * ── HarmonyOS 移植记录 ──────────────────────────────────────────────────────
 * 条目   : S0498   上游: com/hippo/util/PermissionRequester.java（92 行）
 * 目标   : harmony/entry/src/main/ets/hippo/util/PermissionRequester.ets
 *
 * 上游是"申请权限"的三分支状态机，两个重载只差**是否带回调**：
 * ```
 * if (已授权)            → (有回调则 callback.agree(code)) → 返回 true
 * else if (需解释理由)   → 弹 AlertDialog（确定 → requestPermissions）→ 返回 false
 * else                  → 直接 requestPermissions            → 返回 false
 * ```
 * 返回值语义（上游注释原文）：**true = 无需申请，现在就可以干活**；
 * **false = 去 onRequestPermissionsResult 里等结果**。这个语义必须保留 —— 它决定了调用点
 * 是"立刻继续"还是"挂起等回调"。
 *
 * 平台差异：
 *  1. `ActivityCompat.checkSelfPermission` → 注入 `isGranted(permission)`
 *     （鸿蒙 `abilityAccessCtrl.checkAccessTokenSync`）。
 *  2. `shouldShowRequestPermissionRationale` → 注入（鸿蒙没有同名 API，可用"上次拒绝过且未选不再询问"
 *     自行推导；注入后本类逻辑不变）。
 *  3. `AlertDialog`（理由说明）→ **不弹窗**，返回决策让调用方渲染（ArkUI 声明式）。
 *  4. `ActivityCompat.requestPermissions(...)` → 注入 `requestPermissions(permissions, code)`。
 *  5. **`private static PermissionCallBack callback`（全局单例）照搬**：上游是静态字段，
 *     同时只保存**最后一次**注册的回调 —— 并发申请会互相覆盖。这是上游设计，本实现保留，
 *     并在 `getCallback()` 里暴露以便调用方/测试观察。
 *  6. `IllegalStateException("The Activity must implement ...")` 的**前置校验**在鸿蒙无对应
 *     （没有"Activity 必须实现某接口"的概念）→ 不移植；取而代之的是**显式注入**，
 *     缺失能力在编译期就暴露。
 */

import { PermissionCallBack } from '../ehviewer/callBack/PermissionCallBack';
import { PermissionRequesterIo } from './PermissionRequesterIo';

/** 权限申请的三个决策结果（对应上游三个分支） */
export enum PermissionDecision {
  /** 已授权：调用方可以立刻继续 */
  ALREADY_GRANTED = 0,
  /** 需要先向用户解释理由，再申请 */
  NEED_RATIONALE = 1,
  /** 直接申请 */
  REQUEST = 2
}

export class PermissionRequester {

  /** 上游 `private static PermissionCallBack callback`（全局单例，last-wins） */
  private static callback: PermissionCallBack | null = null;

  /**
   * 对应上游 `request(activity, permission, rationale, requestCode)`（**不带回调**的重载）。
   * @returns true = 已授权无需申请；false = 已发起申请（或需要先解释），结果走 onRequestPermissionsResult
   */
  static request(permission: string, requestCode: number, io: PermissionRequesterIo): boolean {
    return PermissionRequester.requestInternal(permission, requestCode, io, false);
  }

  /**
   * 对应上游 `request(activity, permission, rationale, requestCode, permissionCallBack)`。
   * **与无回调版的关键差异**：已授权时会**立即调用 `callback.agree(requestCode)`**。
   */
  static requestWithCallback(permission: string, requestCode: number,
    io: PermissionRequesterIo, callBack: PermissionCallBack): boolean {
    PermissionRequester.callback = callBack;
    return PermissionRequester.requestInternal(permission, requestCode, io, true);
  }

  /**
   * 对应上游的决策段（两个重载共用的部分）。
   * @param withCallback true 时"已授权"分支要回调 `agree`
   */
  private static requestInternal(permission: string, requestCode: number,
    io: PermissionRequesterIo, withCallback: boolean): boolean {
    const decision: PermissionDecision = PermissionRequester.decide(io, permission);
    if (decision === PermissionDecision.ALREADY_GRANTED) {
      if (withCallback && PermissionRequester.callback !== null) {
        PermissionRequester.callback.agree(requestCode);
      }
      return true;
    }
    if (decision === PermissionDecision.NEED_RATIONALE) {
      // 上游弹 AlertDialog；这里交回给调用方（ArkUI 声明式），确定后再调 confirmRequest
      return false;
    }
    io.requestPermissions([permission], requestCode);
    return false;
  }

  /**
   * 用户在"解释理由"对话框里点了确定 → 发起申请（对应上游 `setPositiveButton` 的回调体）。
   * 单独暴露，是因为弹窗在 ArkUI 侧由调用方渲染。
   */
  static confirmRequest(permission: string, requestCode: number, io: PermissionRequesterIo): void {
    io.requestPermissions([permission], requestCode);
  }

  /** 纯决策（无副作用），便于调用方在渲染前先判断要不要弹框 */
  static decide(io: PermissionRequesterIo, permission: string): PermissionDecision {
    if (io.isGranted(permission)) {
      return PermissionDecision.ALREADY_GRANTED;
    }
    if (io.shouldShowRationale(permission)) {
      return PermissionDecision.NEED_RATIONALE;
    }
    return PermissionDecision.REQUEST;
  }

  /** 上游静态字段的观察口（上游无 getter，仅为测试与诊断） */
  static getCallback(): PermissionCallBack | null {
    return PermissionRequester.callback;
  }

  /** 清空回调（上游无此方法；进程内多次申请时避免持有已销毁页面的引用） */
  static clearCallback(): void {
    PermissionRequester.callback = null;
  }
}
