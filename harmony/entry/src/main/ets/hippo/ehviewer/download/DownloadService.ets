/*
 * Copyright 2026 ehviewer-harmony contributors
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

/**
 * 移植自 app/src/main/java/com/hippo/ehviewer/download/DownloadService.kt（824 行）。
 *
 * ============================================================================
 * 组件映射（Android → 鸿蒙）
 * ============================================================================
 * | Android | 鸿蒙 | 说明 |
 * |---|---|---|
 * | `Service` + `startForeground()` | `backgroundTaskManager.startBackgroundRunning()`（BackgroundTasksKit 长时任务，模式 `DATA_TRANSFER`） | 需 `ohos.permission.KEEP_BACKGROUND_RUNNING`（见 MR：需 Lead 在 `module.json5` 申请，本文件不越界改配置） |
 * | `NotificationManager.notify()` | `notificationManager.publish()` | 通知槽 `SlotType.SERVICE_INFORMATION` |
 * | `NotificationChannel` | `notificationManager.addSlot(SlotType…)` | 鸿蒙通知渠道概念换成 slot；重要性在 slot 上一次性设定 |
 * | `PendingIntent.getService(ACTION_*)` | `wantAgent.getWantAgent()` + `DownloadService.dispatchAction()` | 通知按钮不再回调 Service，改回调本类的静态分发入口 |
 * | `PowerManager.WakeLock` | **删除**（D-λ） | 长时任务已保证进程不被冻结；鸿蒙无等价 `PARTIAL_WAKE_LOCK`，强行申请只会被系统忽略 |
 * | `ConnectivityManager.NetworkCallback` | `connection.createNetConnection().on('netAvailable'/'netLost')` | 仅用于日志（上游同样只打日志，不影响下载逻辑） |
 * | `MiuiOptimizationHelper`（小米后台限制） | **删除**（D-μ） | 小米 ROM 的保活 hack 在鸿蒙无对象；长时任务 + 用户侧"允许后台活动"是等价手段 |
 * | `Handler(Looper.getMainLooper())` 节流器 | `setTimeout` 节流器 | `NotificationDelay` 的 1s 合并窗口逐行保留 |
 * | `NotificationCompat.InboxStyle` | `NotificationLongTextContent`（多行文本） | 鸿蒙无 InboxStyle；用 `\n` 拼行，视觉与信息量等价（见 D-ν） |
 *
 * ============================================================================
 * 通知状态转换表（哪一步发什么通知 / 什么条件下发 —— 真机行为的设计基线）
 * ============================================================================
 * 三条通知各自独立 ID 与节流器（上游 ID_DOWNLOADING=1 / ID_DOWNLOADED=2 / ID_509=3，值保留）：
 *
 * | # | 触发点（本类方法） | 条件 | 通知 ID | 内容 / 形态 | 置位 | 副作用 |
 * |---|---|---|---|---|---|---|
 * | N1 | `ensureEnteredForeground()`（onCreate / 首个 ACTION） | 总是 | 1 | 「下载服务」+ **不确定进度**（不设 `template`） | `isOngoing=true`, `isUnremovable=true`, `tapDismissed=false` | 首次调用同时起**长时任务**（DATA_TRANSFER，幂等） |
 * | N2 | `onStart(info)` | `DownloadListener.onStart` 回调 | 1 | 标题 = `EhUtils.getSuitableTitle(info)`，文本清空，不确定进度 | 同上 | 再次确保长时任务；走 1s 合并窗口（`startForeground(req, immediate=false)`） |
 * | N3 | `onDownload(info)` / `onGetPage(info)` → `onUpdate(info)` | 速度帧（2s 一次）或单页完成 | 1 | 文本 = `humanReadableByteCount(speed)/S`（`remaining>=0` 时追加「剩余 …」）；`additionalText = finished/total`；进度 = `finished/total` | 同上 | 1s 合并窗口；`total==-1 \|\| finished==-1` 时 `additionalText` 留空（上游同款判断） |
 * | N4 | `onFinish(info)` | `state == STATE_FINISH` 或 `STATE_FAILED` | **先 cancel 1**，再发 2 | 标题「下载完成」；文本三态：全成功 / 全失败 / 混合；`needLines` 为真时把每条 `✓ 标题` / `✗ 标题` 拼进 `longText` | `isOngoing=false`, `tapDismissed=true`, `badgeNumber=已下载条数` | 计数：`itemStateMap/itemTitleMap` 按 gid 去重（重复完成只调整 finished/failed，不再 +downloadedCount）；随后 `checkStopSelf()` |
 * | N5 | `onGet509()` | `SpiderQueen.onGet509` | 3 | 「509 流量限制」+ 稍后重试提示 | `isOngoing=false`, `tapDismissed=true` | 与被限流任务解耦：**不影响** N1–N4 的状态机 |
 * | N6 | `onCancel(info)` | 用户停止 / 删除导致当前任务取消 | 1（cancel） | 撤掉进度通知 | — | `checkStopSelf()` |
 * | N7 | `checkStopSelf()` | `downloadManager == null` 或 `isIdle()` | 1（cancel） | 撤掉进度通知 | `foregroundStarted=false` | 停长时任务（`stopBackgroundRunning`）；N4/N6 之后都会走到这里 |
 * | N8 | `ACTION_CLEAR`（完成通知的"清除"按钮 / 页面清理） | 收到 action | 2 | **不 publish**，只 `clear()` 清空两条映射（计数由映射推导，随之归零；上游是三个 int，见 D-041） | — | 上游同样只清计数 |
 *
 * 节流（`NotificationDelay`，逐行对位上游）：
 *   - 窗口 1000 ms；窗口内多次请求合并成**最后一次**操作（NOTIFY / CANCEL / START_FOREGROUND 三态）；
 *   - N1 用「立即」语义（首次进入长时任务不能等 1s，否则系统判前台未起）；
 *   - N4/N6/N7 的 cancel 也走同一窗口，避免完成瞬间把进度通知又刷回来。
 *
 * 平台差异（真机行为无法在 CI 验证，登记在此作验收基线）：
 *   - `SlotBadgeFlag` **不存在于 API 20**（HarmonyOS NEXT 才有）→ 已删除，角标语义无对位（D-ν 补记）；
 *   - `addSlot(type: SlotType)` 只接受枚举，无法携带上游 `NotificationChannel` 的
 *     name/description/importance → 「低打扰」由 `SlotType.SERVICE_INFORMATION` 承担（D-ν）；
 *   - 通知按钮（「全部停止」/「清除」/「暂停」/「继续」）经 `wantAgent.parameters` 回到
 *     `EntryAbility.onCreate` → `DownloadService.dispatchAction(action)`（MR 的 G-1 回路要求）。
 *
 * ============================================================================
 * 行为等价说明（逐块）
 * ============================================================================
 *   1. `onStartCommand` 的 action 分派表 10 个分支（clear / delete_range / delete /
 *      stop_all / stop_range / stop_current / stop / start_all / start_range / start）逐条保留，
 *      常量值也一字不改（`"start"`、`"stop_all"` …），因为它们是短快捷方式与通知按钮的对外契约。
 *   2. `checkStopSelf()`：`isIdle()` 为真则撤前台通知 + 停长时任务 + 释放监听。
 *   3. `NotificationDelay` 的三态（NOTIFY / CANCEL / START_FOREGROUND）与 1s 合并窗口保留；
 *      上游 `startForeground(immediate = true)` 的"立即"语义对应"首次进入长时任务"。
 *   4. `onFinish` 的计数/文案逻辑（finished/failed 计数、单条 vs 多条、混合）逐行保留，
 *      包括 `sItemTitleArray.size() >= 1` 的兜底与 "WTF, sItemTitleArray is null" 日志分支。
 *   5. `clear()` 清空两条映射（`itemStateMap`/`itemTitleMap`）；**三个计数已改为由映射推导**（D-041），故只清映射。—— 保留为 `DownloadService.clear()` 静态方法。
 *   6. 上游 `onBind` 直接抛 `IllegalStateException("No bindService")`：鸿蒙侧没有 bind 概念，
 *      本类**不提供**绑定入口（等价于"谁都不能 bind"）。
 */

import { Want, wantAgent } from '@kit.AbilityKit';
import { backgroundTaskManager } from '@kit.BackgroundTasksKit';
import { connection } from '@kit.NetworkKit';
import notificationManager from '@ohos.notificationManager';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { common } from '@kit.AbilityKit';

import { DownloadListener, DownloadManager } from './DownloadManager';
import { DownloadInfo } from '../dao/DownloadInfo';
import { GalleryInfo } from '../client/data/GalleryInfo';
import { Settings } from '../Settings';
import { GetText } from '../GetText';
import { EhDB } from '../EhDB';
import { EhUtils } from '../client/EhUtils';
import { FileUtils } from '../../lib/yorozuya/FileUtils';
import { ReadableTime } from '../../util/ReadableTime';

const DOMAIN: number = 0x0D0C;
const TAG: string = 'DownloadService';

/** 通知 ID（上游 `ID_DOWNLOADING/ID_DOWNLOADED/ID_509`，值保持 1/2/3）。 */
const ID_DOWNLOADING: number = 1;
const ID_DOWNLOADED: number = 2;
const ID_509: number = 3;

/** 节流窗口（上游 `NotificationDelay.DELAY = 1000`）。 */
const NOTIFICATION_DELAY_MS: number = 1000;

/** 通知渠道（slot）标识。 */
const SLOT_ID: string = 'com.ehviewer.next.download';

/** 节流器动作（对应上游 show / cancel / startForeground(immediate) / startForeground）。 */
export class NotificationDelayAction {
  public static readonly SHOW: number = 0;
  public static readonly CANCEL: number = 1;
  public static readonly START_FOREGROUND_IMMEDIATE: number = 2;
  public static readonly START_FOREGROUND: number = 3;
}

/** 决策结果：**该做什么**（effect）+ **做完后状态是什么**（posted/startedForeground/lastTime）。 */
export class NotificationDelayDecision {
  effect: number = 0;
  ops: number = 0;
  posted: boolean = false;
  startedForeground: boolean = false;
  lastTime: number = 0;
}

/**
 * 通知节流的**纯判定**（不含定时器、不含平台调用）。
 *
 * 为什么必须把它单独测：这块的 bug 表现是"丢通知/重复发/常驻通知消失"，
 * 而在真机上极难稳定复现（依赖时序）。上游 `NotificationDelay` 的语义有三条容易被破坏：
 *   1. 窗口内的后续操作**只保留最后一个**（不是排队，是覆盖）；
 *   2. `posted == true` 时新操作直接覆盖 `ops`，**不刷新 lastTime**；
 *   3. `startForeground(immediate)` 必须打断待执行操作（首帧必发），
 *      而首次非 immediate 的 startForeground 也必须立刻生效（不能等窗口）。
 */
export class NotificationDelayPlanner {
  public static readonly EFFECT_PUBLISH_NOW: number = 0;
  public static readonly EFFECT_CANCEL_NOW: number = 1;
  public static readonly EFFECT_START_FOREGROUND: number = 2;
  public static readonly EFFECT_DEFER: number = 3;

  /**
   * @param action       NotificationDelayAction.*
   * @param posted       当前是否已有待执行操作
   * @param startedForeground 是否已进入过长时任务
   * @param lastTime     上次实际执行/入队的时间
   * @param now          当前时间
   * @param delayMs      节流窗口（上游 1000ms）
   */
  public static decide(action: number, posted: boolean, startedForeground: boolean, lastTime: number,
    now: number, delayMs: number): NotificationDelayDecision {
    const d: NotificationDelayDecision = new NotificationDelayDecision();
    d.posted = posted;
    d.startedForeground = startedForeground;
    d.lastTime = lastTime;
    const expired: boolean = now - lastTime > delayMs;

    if (action === NotificationDelayAction.START_FOREGROUND_IMMEDIATE) {
      // 打断一切待执行操作，立刻进前台
      d.effect = NotificationDelayPlanner.EFFECT_START_FOREGROUND;
      d.posted = false;
      d.ops = 0;
      d.lastTime = now;
      d.startedForeground = true;
      return d;
    }

    if (posted) {
      // 已有待执行操作 → 只覆盖 ops，**不刷新 lastTime**（窗口从第一次入队算）
      d.effect = NotificationDelayPlanner.EFFECT_DEFER;
      d.ops = action === NotificationDelayAction.SHOW
        ? NotificationDelay.OPS_NOTIFY
        : (action === NotificationDelayAction.CANCEL
          ? NotificationDelay.OPS_CANCEL
          : NotificationDelay.OPS_START_FOREGROUND);
      return d;
    }

    if (action === NotificationDelayAction.START_FOREGROUND) {
      if (!startedForeground) {
        // 首次非 immediate：立刻生效（否则后台长任务起不来）
        d.effect = NotificationDelayPlanner.EFFECT_START_FOREGROUND;
        d.lastTime = now;
        d.startedForeground = true;
        return d;
      }
      if (expired) {
        d.effect = NotificationDelayPlanner.EFFECT_START_FOREGROUND;
        d.lastTime = now;
        d.startedForeground = true;
        return d;
      }
      d.effect = NotificationDelayPlanner.EFFECT_DEFER;
      d.ops = NotificationDelay.OPS_START_FOREGROUND;
      d.posted = true;
      return d;
    }

    // SHOW / CANCEL
    if (expired) {
      d.effect = action === NotificationDelayAction.SHOW
        ? NotificationDelayPlanner.EFFECT_PUBLISH_NOW
        : NotificationDelayPlanner.EFFECT_CANCEL_NOW;
      d.lastTime = now;
      return d;
    }
    d.effect = NotificationDelayPlanner.EFFECT_DEFER;
    d.ops = action === NotificationDelayAction.SHOW
      ? NotificationDelay.OPS_NOTIFY
      : NotificationDelay.OPS_CANCEL;
    d.posted = true;
    d.lastTime = now;
    return d;
  }
}

/**
 * 通知节流器（上游 `DownloadService.NotificationDelay`）。
 * 三步状态机：空闲 → 到期执行；未到期 → 记下最后一次操作，窗口到了统一执行。
 */
class NotificationDelay {
  public static readonly OPS_NOTIFY: number = 0;
  public static readonly OPS_CANCEL: number = 1;
  public static readonly OPS_START_FOREGROUND: number = 2;

  private lastTime: number = 0;
  private posted: boolean = false;
  private hasStartedForeground: boolean = false;
  private ops: number = 0;
  private timerId: number = -1;

  private readonly notifyId: number;
  private readonly service: DownloadService;

  constructor(service: DownloadService, notifyId: number) {
    this.service = service;
    this.notifyId = notifyId;
  }

  public release(): void {
    if (this.timerId !== -1) {
      clearTimeout(this.timerId);
      this.timerId = -1;
    }
    this.posted = false;
  }

  /** 对应上游 `show()`：发通知（带 1s 合并）。判定交给 NotificationDelayPlanner（可单测）。 */
  public show(request: notificationManager.NotificationRequest): void {
    this.pendingRequest = request;
    this.apply(NotificationDelayAction.SHOW);
  }

  /** 对应上游 `cancel()`。 */
  public cancel(): void {
    this.apply(NotificationDelayAction.CANCEL);
  }

  /**
   * 对应上游 `startForeground(immediate)`：
   * immediate 语义 = 立刻进入长时任务并挂通知（上游首帧必走这条）。
   */
  public startForeground(request: notificationManager.NotificationRequest, immediate: boolean): void {
    this.pendingRequest = request;
    this.apply(immediate
      ? NotificationDelayAction.START_FOREGROUND_IMMEDIATE
      : NotificationDelayAction.START_FOREGROUND);
  }

  /** 统一入口：纯判定 → 应用副作用（本类是唯一做副作用的地方）。 */
  private apply(action: number): void {
    if (action === NotificationDelayAction.START_FOREGROUND_IMMEDIATE && this.timerId !== -1) {
      // immediate 要打断待执行操作（上游同样先 cancel 掉 timer）
      clearTimeout(this.timerId);
      this.timerId = -1;
    }
    const decision: NotificationDelayDecision = NotificationDelayPlanner.decide(
      action, this.posted, this.hasStartedForeground, this.lastTime, Date.now(), NOTIFICATION_DELAY_MS);
    this.posted = decision.posted;
    this.hasStartedForeground = decision.startedForeground;
    this.lastTime = decision.lastTime;
    if (decision.effect === NotificationDelayPlanner.EFFECT_PUBLISH_NOW) {
      this.ops = decision.ops;
      this.publishNow(this.pendingRequest);
      return;
    }
    if (decision.effect === NotificationDelayPlanner.EFFECT_CANCEL_NOW) {
      this.ops = decision.ops;
      this.cancelNow();
      return;
    }
    if (decision.effect === NotificationDelayPlanner.EFFECT_START_FOREGROUND) {
      this.ops = decision.ops;
      this.applyStartForeground();
      return;
    }
    // DEFER：记下最后一条要执行的操作，窗口到了统一执行
    this.ops = decision.ops;
    this.schedule();
  }
  private pendingRequest: notificationManager.NotificationRequest | null = null;

  private applyStartForeground(): void {
    this.service.startForegroundCompat(this.notifyId, this.pendingRequest);
    this.hasStartedForeground = true;
  }

  private publishNow(request: notificationManager.NotificationRequest | null): void {
    if (request === null) {
      return;
    }
    notificationManager.publish(request).catch((e: BusinessError) => {
      hilog.error(DOMAIN, TAG, 'publish failed, id=%{public}d, code=%{public}d, message=%{public}s',
        this.notifyId, e.code, e.message);
    });
  }

  private cancelNow(): void {
    notificationManager.cancel(this.notifyId).catch((e: BusinessError) => {
      hilog.error(DOMAIN, TAG, 'cancel failed, id=%{public}d, code=%{public}d, message=%{public}s',
        this.notifyId, e.code, e.message);
    });
  }

  private schedule(): void {
    if (this.timerId !== -1) {
      clearTimeout(this.timerId);
    }
    this.timerId = setTimeout((): void => {
      this.timerId = -1;
      this.run();
    }, NOTIFICATION_DELAY_MS);
  }

  /** 对应上游 `run()`：按最后一次记录的操作统一执行。 */
  private run(): void {
    this.posted = false;
    switch (this.ops) {
      case NotificationDelay.OPS_NOTIFY:
        this.publishNow(this.pendingRequest);
        break;
      case NotificationDelay.OPS_CANCEL:
        this.cancelNow();
        break;
      case NotificationDelay.OPS_START_FOREGROUND:
        this.applyStartForeground();
        break;
      default:
        break;
    }
  }
}

/**
 * 一条通知的**纯数据**描述（无副作用、无平台 API）。
 *
 * 为什么单独抽出来：N1–N8 的"发哪条通知 / 写什么文案 / 带什么进度"原先散落在
 * `buildXxxRequest()` 与 `onFinish()` 里，与 `notificationManager.publish()` 缠在一起，
 * 只能靠真机验。抽成 plan 之后，宿主单测（`src/test/download-sync/notification.test.ets`）
 * 就能把 N1–N8 全表逐条断言 —— 真机只负责验"显示效果"，逻辑本身不必上机。
 */
export interface DownloadNotificationPlan {
  /** 通知 ID：1=下载中 / 2=已完成 / 3=509 告警（与上游常量同值）。 */
  id: number;
  title: string;
  text: string;
  /** additionalText（进度「3/12」等）。 */
  info: string;
  /** 进度值；`-1` 表示不确定进度（不挂 template）。 */
  progress: number;
  max: number;
  ongoing: boolean;
  badge: number;
  /** 多行正文（N4 的 ✓/✗ 列表）。 */
  lines: string[];
}

/** N4 的计数与文案（全部由两张 map 推导，不再维护可变计数器）。 */
export interface FinishedSummary {
  finishedCount: number;
  failedCount: number;
  downloadedCount: number;
  text: string;
  lines: string[];
  needLines: boolean;
}

/**
 * N1–N8 的**唯一事实来源**：纯函数式推导，不认识 `notificationManager`。
 * 时间/文案/计数规则全部对位上游 `DownloadService.kt`。
 */
export class DownloadNotificationPlanner {
  /** 通知 ID（上游 `ID_DOWNLOADING=1 / ID_DOWNLOADED=2 / ID_509=3`）。 */
  public static readonly ID_DOWNLOADING: number = 1;
  public static readonly ID_DOWNLOADED: number = 2;
  public static readonly ID_509: number = 3;

  /** 上游 `R.string.download_speed_text[_2]` 的等价文案：`<速度>/S[ · 剩余 X]`。 */
  public static formatSpeedText(speed: number, remaining: number): string {
    const safeSpeed: number = speed < 0 ? 0 : speed;
    const text: string = FileUtils.humanReadableByteCount(safeSpeed, false) + '/S';
    if (remaining >= 0) {
      return `${text} · 剩余 ${ReadableTime.getShortTimeInterval(remaining)}`;
    }
    return text;
  }

  /** 页数进度的 additionalText：任一端为 -1 时留空（上游同款判断）。 */
  public static progressInfo(finished: number, total: number): string {
    if (total === -1 || finished === -1) {
      return '';
    }
    return `${finished}/${total}`;
  }

  public static readonly FALLBACK_SERVICE_TITLE: string = '下载服务';
  public static readonly FALLBACK_FINISHED_TITLE: string = '下载完成';
  public static readonly FALLBACK_STOP_ALL: string = '全部停止';
  public static readonly FALLBACK_CLEAR: string = '清除';
  public static readonly FALLBACK_509_TITLE: string = '509 流量限制';
  public static readonly FALLBACK_509_TEXT: string = '图片服务器配额已用尽，请稍后重试';

  /** 取资源文案；资源管理器未初始化或缺失时退回默认值，避免通知出现空标题/空按钮。 */
  public static orFallback(value: string, fallback: string): string {
    return value.length > 0 ? value : fallback;
  }

  /** N1：进入前台/建槽时的常驻"下载服务"通知（不确定进度）。 */
  public static idlePlan(): DownloadNotificationPlan {
    return {
      id: DownloadNotificationPlanner.ID_DOWNLOADING,
      title: DownloadNotificationPlanner.orFallback(
        GetText.getString('download_service'), DownloadNotificationPlanner.FALLBACK_SERVICE_TITLE),
      text: '',
      info: '',
      progress: -1,
      max: 0,
      ongoing: true,
      badge: 0,
      lines: []
    };
  }

  /** N2：下载开始（标题 + 不确定进度）。空标题回退「下载服务」（上游空标题显示效果一致）。 */
  public static startPlan(title: string): DownloadNotificationPlan {
    const plan: DownloadNotificationPlan = DownloadNotificationPlanner.idlePlan();
    plan.title = title.length > 0
      ? title
      : DownloadNotificationPlanner.orFallback(
          GetText.getString('download_service'), DownloadNotificationPlanner.FALLBACK_SERVICE_TITLE);
    return plan;
  }

  /** N3：速度帧/单页完成（标题 + 速度/剩余 + 页数进度）。 */
  public static progressPlan(title: string, speed: number, remaining: number, finished: number,
    total: number): DownloadNotificationPlan {
    const plan: DownloadNotificationPlan = DownloadNotificationPlanner.startPlan(title);
    plan.text = DownloadNotificationPlanner.formatSpeedText(speed, remaining);
    plan.info = DownloadNotificationPlanner.progressInfo(finished, total);
    plan.progress = finished;
    plan.max = total;
    return plan;
  }

  /**
   * N4 的第一步：把该 gid 的结果写进两张 map（只动 map，不碰计数器）。
   * 上游用增量计数（新增 +1、翻转 ±1），这里改为"map 是唯一事实来源、计数从 map 推导"，
   * 结果等价且不可能出现"计数与 map 不一致"的状态。
   */
  public static markFinished(stateMap: Map<number, boolean>, titleMap: Map<number, string>, gid: number,
    title: string, finish: boolean): void {
    stateMap.set(gid, finish);
    titleMap.set(gid, title);
  }

  /** N4 的第二步：从 map 推导计数与文案（三态：全成功 / 全失败 / 混合）。 */
  public static summarize(stateMap: Map<number, boolean>, titleMap: Map<number, string>): FinishedSummary {
    let finishedCount: number = 0;
    let failedCount: number = 0;
    stateMap.forEach((fin: boolean): void => {
      if (fin) {
        finishedCount++;
      } else {
        failedCount++;
      }
    });
    const downloadedCount: number = stateMap.size;

    let text: string = '';
    let needLines: boolean = false;
    if (finishedCount !== 0 && failedCount === 0) {
      if (finishedCount === 1) {
        text = titleMap.size >= 1 ? `已成功下载 ${DownloadNotificationPlanner.firstTitle(titleMap)}` : '未知错误';
      } else {
        text = `已成功下载 ${finishedCount} 项`;
        needLines = true;
      }
    } else if (finishedCount === 0 && failedCount !== 0) {
      if (failedCount === 1) {
        text = titleMap.size >= 1 ? `下载失败 ${DownloadNotificationPlanner.firstTitle(titleMap)}` : '未知错误';
      } else {
        text = `下载失败 ${failedCount} 项`;
        needLines = true;
      }
    } else {
      text = `成功 ${finishedCount} 项，失败 ${failedCount} 项`;
      needLines = true;
    }

    const lines: string[] = [];
    if (needLines) {
      stateMap.forEach((fin: boolean, id: number): void => {
        const title: string | undefined = titleMap.get(id);
        if (title === undefined) {
          return;
        }
        lines.push(fin ? `✓ ${title}` : `✗ ${title}`);
      });
    }

    return {
      finishedCount: finishedCount,
      failedCount: failedCount,
      downloadedCount: downloadedCount,
      text: text,
      lines: lines,
      needLines: needLines
    };
  }

  /** N4 的第三步：完成通知的计划（非 ongoing、可消除、角标=已下载条数）。 */
  public static donePlan(summary: FinishedSummary): DownloadNotificationPlan {
    return {
      id: DownloadNotificationPlanner.ID_DOWNLOADED,
      title: DownloadNotificationPlanner.orFallback(
        GetText.getString('download_finished_title'), DownloadNotificationPlanner.FALLBACK_FINISHED_TITLE),
      text: summary.text,
      info: '',
      progress: 0,
      max: 0,
      ongoing: false,
      badge: summary.downloadedCount,
      lines: summary.lines
    };
  }

  /** N5：509 告警（与主状态机解耦，非 ongoing）。 */
  public static alert509Plan(): DownloadNotificationPlan {
    return {
      id: DownloadNotificationPlanner.ID_509,
      title: DownloadNotificationPlanner.orFallback(
        GetText.getString('download_service_509_title'), DownloadNotificationPlanner.FALLBACK_509_TITLE),
      text: DownloadNotificationPlanner.orFallback(
        GetText.getString('download_service_quota_exhausted'), DownloadNotificationPlanner.FALLBACK_509_TEXT),
      info: '',
      progress: 0,
      max: 0,
      ongoing: false,
      badge: 0,
      lines: []
    };
  }

  /** 上游 `sItemTitleArray.valueAt(0)`：Map 保留插入序，取第一个。 */
  private static firstTitle(titleMap: Map<number, string>): string {
    let result: string = '';
    let first: boolean = true;
    titleMap.forEach((title: string): void => {
      if (first) {
        result = title;
        first = false;
      }
    });
    return result;
  }
}

/** 服务收尾时要做哪些副作用（纯数据，便于断言"该撤的撤了、该留的留着"）。 */
export interface ServiceStopPlan {
  /** 是否真的收尾（上游 `checkStopSelf` 的门槛）。 */
  shouldStop: boolean;
  /** 撤掉"下载中"通知（N1/N3 那条）。 */
  cancelDownloadingNotification: boolean;
  /** 清 foreground 标志（下次需要重新 `startForegroundCompat`）。 */
  clearForegroundFlag: boolean;
  /** 停长时任务（`backgroundTaskManager.stopBackgroundRunning`）。 */
  stopContinuousTask: boolean;
  /** 是否保留"下载完成"通知（N4 必须留着，否则用户永远看不到结果）。 */
  keepDownloadedNotification: boolean;
}

/**
 * `checkStopSelf()` 的纯判定（对位上游 `DownloadService.checkStopSelf`）。
 *
 * 门槛是 `mDownloadManager == null || isIdle`，两个条件都容易被"优化"：
 *   - 去掉 `== null`：manager 还没建好时（`onStartCommand` 早到）服务永不停 → 常驻通知常亮；
 *   - 只看 `!isIdle`：队列空了但 currentTask 还在时停服务 → **下载被拦腰打断**。
 *
 * 另外必须钉住一条**用户可感知**的语义：收尾只能撤"下载中"通知，
 * **"下载完成"通知必须保留**（上游 `stopForeground(STOP_FOREGROUND_REMOVE)` 只撤前台那条，
 * 完成通知是独立 id 的普通通知）。写错就是"下完了但用户没看见"。
 */
export class ServiceLifecyclePlanner {
  static plan(hasManager: boolean, isIdle: boolean): ServiceStopPlan {
    const shouldStop: boolean = !hasManager || isIdle;
    return {
      shouldStop: shouldStop,
      cancelDownloadingNotification: shouldStop,
      clearForegroundFlag: shouldStop,
      stopContinuousTask: shouldStop,
      keepDownloadedNotification: true
    };
  }
}
export class DownloadService implements DownloadListener {
  // ---------------------------------------------------------------- 对外常量

  public static readonly ACTION_START: string = 'start';
  public static readonly ACTION_START_RANGE: string = 'start_range';
  public static readonly ACTION_START_ALL: string = 'start_all';
  public static readonly ACTION_STOP: string = 'stop';
  public static readonly ACTION_STOP_RANGE: string = 'stop_range';
  public static readonly ACTION_STOP_CURRENT: string = 'stop_current';
  public static readonly ACTION_STOP_ALL: string = 'stop_all';
  public static readonly ACTION_DELETE: string = 'delete';
  public static readonly ACTION_DELETE_RANGE: string = 'delete_range';
  public static readonly ACTION_CLEAR: string = 'clear';

  public static readonly KEY_GALLERY_INFO: string = 'gallery_info';
  public static readonly KEY_LABEL: string = 'label';
  public static readonly KEY_GID: string = 'gid';
  public static readonly KEY_GID_LIST: string = 'gid_list';

  // -------------------------------------------------------------- 单例与依赖

  private static instance: DownloadService | null = null;

  private downloadManager: DownloadManager | null = null;

  private downloadingDelay: NotificationDelay | null = null;
  private downloadedDelay: NotificationDelay | null = null;
  private delay509: NotificationDelay | null = null;

  private foregroundStarted: boolean = false;

  /** 网络监听（上游 ConnectivityManager.NetworkCallback 的等价物，仅日志用途）。 */
  private netConnection: connection.NetConnection | null = null;

  private context: common.UIAbilityContext | null = null;
  private stopAllAgent: Object | null = null;
  private clearAgent: Object | null = null;

  // ---------------------------------------------------------------- 静态计数

  // 两张 map 是唯一事实来源；计数一律由 DownloadNotificationPlanner.summarize() 推导，
  // 避免"增量计数与 map 不一致"这类状态（上游用 sFinishedCount/sFailedCount/sDownloadedCount 三个 int）。
  private static readonly itemStateMap: Map<number, boolean> = new Map<number, boolean>();
  private static readonly itemTitleMap: Map<number, string> = new Map<number, string>();

  private constructor() {
  }

  /**
   * 上游由系统 `startService()` 拉起；鸿蒙侧没有可被隐式拉起的 Service 组件，
   * 用显式单例 + 调用方（EntryAbility / ShortcutsActivity）驱动。
   */
  public static getInstance(): DownloadService {
    if (DownloadService.instance === null) {
      DownloadService.instance = new DownloadService();
    }
    return DownloadService.instance;
  }

  /**
   * 上游 `startService(new Intent(this, DownloadService.class).setAction(action))` 的等价入口。
   * 供 `ShortcutsActivity` 与通知按钮调用（异步，不阻塞调用方）。
   */
  public static dispatchAction(action: string): void {
    const service: DownloadService = DownloadService.getInstance();
    service.handleIntentAsync(action, null);
  }

  /** 带参数的 action 分发（对应 Intent extras）。 */
  public static dispatchActionWithExtras(action: string, extras: Map<string, Object>): void {
    const service: DownloadService = DownloadService.getInstance();
    service.handleIntentAsync(action, extras);
  }

  /**
   * 通知点击 / 动作按钮触发的 Want 参数转发入口（由 EntryAbility.onCreate / onNewWant 调用）。
   * 返回 true 表示包含 `'download_action'` 并已受理，否则返回 false。
   */
  public static handleWantParameters(params: Record<string, Object> | null | undefined): boolean {
    if (params === null || params === undefined) {
      return false;
    }
    const actionValue: Object | undefined = params['download_action'];
    if (actionValue === undefined || actionValue === null) {
      return false;
    }
    const action: string = String(actionValue);
    const extras: Map<string, Object> = new Map<string, Object>();
    const keys: string[] = Object.keys(params);
    for (let i = 0; i < keys.length; i++) {
      extras.set(keys[i], params[keys[i]] as Object);
    }
    hilog.info(DOMAIN, TAG, 'handleWantParameters: action=%{public}s gid=%{public}d',
      action, DownloadService.readGid(extras));
    DownloadService.dispatchActionWithExtras(action, extras);
    return true;
  }

  /**
   * 在应用启动阶段绑定运行上下文与 DownloadManager 单例（不主动拉起空闲前台常驻通知）。
   * 当真正有下载任务通过 DownloadManager.startDownload() 启动时，`onStart` 会拉起前台与长时任务。
   */
  public async bindContext(context: common.UIAbilityContext,
    managerArg?: DownloadManager | null): Promise<void> {
    this.context = context;
    if (!GetText.isInitialized()) {
      GetText.initialize(context);
    }
    await this.createSlot();
    await this.prepareActionAgents();
    if (!Settings.isAttached()) {
      hilog.info(DOMAIN, TAG, 'Settings not attached yet, attaching before use');
      await Settings.attach(context);
    }
    if (!EhDB.isAttached()) {
      hilog.error(DOMAIN, TAG,
        'EhDB not attached —— DownloadManager.create() 会在 EhDB.getAllDownloadInfo() 抛 ' +
        "'EhDB is not attached'。请确保 DownloadService.bindContext 晚于 EhDB.attach(session)。");
    }
    const manager: DownloadManager = (managerArg !== undefined && managerArg !== null)
      ? managerArg
      : await DownloadManager.getInstance();
    this.downloadManager = manager;
    manager.setDownloadListener(this);
  }

  /**
   * 对应上游 `onCreate()`：建通知槽、起长时任务、挂到 DownloadManager 上。
   *
   * **顺序约束（重要）**：`Settings.attach(context)` 必须在使用 Settings 的同步读接口之前完成。
   * 上游 `Settings` 全是同步方法；ArkTS 的 `Preferences.getAll()` 是异步，core-runtime 因此在
   * `attach()` 里载入一份 archiver 键值快照（`sArchiverMem`）。若在 attach 之前调用
   * `Settings.getPendingArchiverDownloadIds()`，拿到的是**空数组** —— 归档断点续传会静默不恢复任何任务。
   * 这里做一次幂等兜底（`isAttached()` 已为真则不重复 attach），保证下载服务起来时快照一定就绪。
   */
  public async onCreate(context: common.UIAbilityContext): Promise<void> {
    await this.bindContext(context);
    await this.initNetworkCallback();
    await this.ensureEnteredForeground();
  }

  /**
   * 对应上游 `onDestroy()`。
   */
  public onDestroy(): void {
    this.releaseNetworkConnection();
    if (this.downloadManager !== null) {
      this.downloadManager.setDownloadListener(null);
      this.downloadManager = null;
    }
    if (this.downloadingDelay !== null) {
      this.downloadingDelay.release();
      this.downloadingDelay = null;
    }
    if (this.downloadedDelay !== null) {
      this.downloadedDelay.release();
      this.downloadedDelay = null;
    }
    if (this.delay509 !== null) {
      this.delay509.release();
      this.delay509 = null;
    }
    this.stopContinuousTask();
  }

  /**
   * 对应上游 `onStartCommand(intent, flags, startId)`：分派 action 后检查是否该停。
   */
  private handleIntentAsync(action: string | null, extras: Map<string, Object> | null): void {
    if (action === null) {
      this.checkStopSelf();
      return;
    }
    const manager: DownloadManager | null = this.downloadManager;
    switch (action) {
      case DownloadService.ACTION_CLEAR:
        DownloadService.clear();
        if (this.downloadedDelay !== null) {
          this.downloadedDelay.cancel();
        }
        break;
      case DownloadService.ACTION_DELETE_RANGE: {
        const gidList: number[] | null = DownloadService.readGidList(extras);
        if (gidList !== null && manager !== null) {
          manager.deleteRangeDownload(gidList).catch((e: Error) => {
            hilog.error(DOMAIN, TAG, 'deleteRangeDownload failed: %{public}s', e.message);
          });
        }
        break;
      }
      case DownloadService.ACTION_DELETE: {
        const gid: number = DownloadService.readGid(extras);
        if (gid !== -1 && manager !== null) {
          manager.deleteDownload(gid).catch((e: Error) => {
            hilog.error(DOMAIN, TAG, 'deleteDownload failed: %{public}s', e.message);
          });
        }
        break;
      }
      case DownloadService.ACTION_STOP_ALL:
        if (manager !== null) {
          manager.stopAllDownload().catch((e: Error) => {
            hilog.error(DOMAIN, TAG, 'stopAllDownload failed: %{public}s', e.message);
          });
        }
        break;
      case DownloadService.ACTION_STOP_RANGE: {
        const gidList: number[] | null = DownloadService.readGidList(extras);
        if (gidList !== null && manager !== null) {
          manager.stopRangeDownload(gidList).catch((e: Error) => {
            hilog.error(DOMAIN, TAG, 'stopRangeDownload failed: %{public}s', e.message);
          });
        }
        break;
      }
      case DownloadService.ACTION_STOP_CURRENT:
        if (manager !== null) {
          manager.stopCurrentDownload().catch((e: Error) => {
            hilog.error(DOMAIN, TAG, 'stopCurrentDownload failed: %{public}s', e.message);
          });
        }
        break;
      case DownloadService.ACTION_STOP: {
        const gid: number = DownloadService.readGid(extras);
        if (gid !== -1 && manager !== null) {
          manager.stopDownload(gid).catch((e: Error) => {
            hilog.error(DOMAIN, TAG, 'stopDownload failed: %{public}s', e.message);
          });
        }
        break;
      }
      case DownloadService.ACTION_START_ALL:
        if (manager !== null) {
          manager.startAllDownload().catch((e: Error) => {
            hilog.error(DOMAIN, TAG, 'startAllDownload failed: %{public}s', e.message);
          });
        }
        break;
      case DownloadService.ACTION_START_RANGE: {
        const gidList: number[] | null = DownloadService.readGidList(extras);
        if (gidList !== null && manager !== null) {
          manager.startRangeDownload(gidList).catch((e: Error) => {
            hilog.error(DOMAIN, TAG, 'startRangeDownload failed: %{public}s', e.message);
          });
        }
        break;
      }
      case DownloadService.ACTION_START: {
        const galleryInfo: GalleryInfo | null = DownloadService.readGalleryInfo(extras);
        const label: string | null = DownloadService.readString(extras, DownloadService.KEY_LABEL);
        if (galleryInfo !== null && manager !== null) {
          manager.startDownload(galleryInfo, label).catch((e: Error) => {
            hilog.error(DOMAIN, TAG, 'startDownload failed: %{public}s', e.message);
          });
        }
        break;
      }
      default:
        break;
    }
    this.checkStopSelf();
  }

  private static readGid(extras: Map<string, Object> | null): number {
    if (extras === null) {
      return -1;
    }
    const value: Object | undefined = extras.get(DownloadService.KEY_GID);
    if (value === undefined) {
      return -1;
    }
    return Number(value);
  }

  private static readGidList(extras: Map<string, Object> | null): number[] | null {
    if (extras === null) {
      return null;
    }
    const value: Object | undefined = extras.get(DownloadService.KEY_GID_LIST);
    if (value === undefined || value === null) {
      return null;
    }
    return value as number[];
  }

  private static readGalleryInfo(extras: Map<string, Object> | null): GalleryInfo | null {
    if (extras === null) {
      return null;
    }
    const value: Object | undefined = extras.get(DownloadService.KEY_GALLERY_INFO);
    if (value === undefined || value === null) {
      return null;
    }
    return value as GalleryInfo;
  }

  private static readString(extras: Map<string, Object> | null, key: string): string | null {
    if (extras === null) {
      return null;
    }
    const value: Object | undefined = extras.get(key);
    if (value === undefined || value === null) {
      return null;
    }
    return String(value);
  }

  // ------------------------------------------------------------ 通知与长时任务

  /**
   * 上游用 `NotificationChannel` 建渠道；鸿蒙对应 `addSlot`。
   * 重要性与上游 `IMPORTANCE_LOW`（进度型通知，不打扰）保持一致。
   */
  private async createSlot(): Promise<void> {
    // 鸿蒙 addSlot 只接受 SlotType（无「传 NotificationSlot 对象」的重载）；
    // 上游 NotificationChannel 的 name/description/badge 无等价入参 —— 记入 D-ν。
    try {
      await notificationManager.addSlot(notificationManager.SlotType.SERVICE_INFORMATION);
      hilog.info(DOMAIN, TAG, 'notification slot created: %{public}s', SLOT_ID);
    } catch (e) {
      const err: BusinessError = e as BusinessError;
      hilog.error(DOMAIN, TAG, 'addSlot failed, code=%{public}d, message=%{public}s', err.code, err.message);
    }
  }

  /**
   * 对应上游 `ensureEnteredForeground()`：保证下载中通知 + 长时任务已就位。
   */
  private async ensureEnteredForeground(): Promise<void> {
    this.ensureDownloadingDelay();
    this.startForegroundCompat(ID_DOWNLOADING, this.buildDownloadingRequest(DownloadNotificationPlanner.idlePlan()));
    await this.startContinuousTask();
  }

  private ensureDownloadingDelay(): void {
    if (this.downloadingDelay === null) {
      this.downloadingDelay = new NotificationDelay(this, ID_DOWNLOADING);
    }
  }

  private ensureDownloadedDelay(): void {
    if (this.downloadedDelay === null) {
      this.downloadedDelay = new NotificationDelay(this, ID_DOWNLOADED);
    }
  }

  private ensure509Delay(): void {
    if (this.delay509 === null) {
      this.delay509 = new NotificationDelay(this, ID_509);
    }
  }

  /**
   * 对应上游 `startForegroundCompat(id, notification)`：
   * Android 是"挂前台通知"；鸿蒙是"挂通知 + 起长时任务"，两步都要幂等。
   */
  public startForegroundCompat(id: number, request: notificationManager.NotificationRequest | null): void {
    if (request !== null) {
      notificationManager.publish(request).catch((e: BusinessError) => {
        hilog.error(DOMAIN, TAG, 'publish foreground notification failed, code=%{public}d, message=%{public}s',
          e.code, e.message);
      });
    }
    if (!this.foregroundStarted) {
      this.foregroundStarted = true;
      this.startContinuousTask().catch((e: BusinessError) => {
        hilog.error(DOMAIN, TAG, 'startBackgroundRunning failed, code=%{public}d, message=%{public}s',
          e.code, e.message);
      });
    }
  }

  /**
   * BackgroundTasksKit 长时任务（`DATA_TRANSFER` = 上游 `FOREGROUND_SERVICE_TYPE_DATA_SYNC`）。
   * 权限：`ohos.permission.KEEP_BACKGROUND_RUNNING`（由 Lead 在 module.json5 申请）。
   */
  private async startContinuousTask(): Promise<void> {
    if (this.context === null) {
      return;
    }
    const wantAgentInfo: wantAgent.WantAgentInfo = {
      wants: [{
        bundleName: this.context.abilityInfo.bundleName,
        abilityName: this.context.abilityInfo.name
      } as Want],
      actionType: wantAgent.OperationType.START_ABILITY,
      requestCode: 0,
      actionFlags: [wantAgent.WantAgentFlags.UPDATE_PRESENT_FLAG]
    };
    try {
      const agent: Object = await wantAgent.getWantAgent(wantAgentInfo);
      await backgroundTaskManager.startBackgroundRunning(this.context,
        backgroundTaskManager.BackgroundMode.DATA_TRANSFER, agent);
      hilog.info(DOMAIN, TAG, 'continuous task started (DATA_TRANSFER)');
    } catch (e) {
      const err: BusinessError = e as BusinessError;
      hilog.error(DOMAIN, TAG, 'startBackgroundRunning failed, code=%{public}d, message=%{public}s',
        err.code, err.message);
    }
  }

  private stopContinuousTask(): void {
    if (this.context === null) {
      return;
    }
    backgroundTaskManager.stopBackgroundRunning(this.context).then((): void => {
      hilog.info(DOMAIN, TAG, 'continuous task stopped');
    }).catch((e: BusinessError) => {
      hilog.error(DOMAIN, TAG, 'stopBackgroundRunning failed, code=%{public}d, message=%{public}s',
        e.code, e.message);
    });
  }

  /**
   * 构造"下载中"通知（上游 `ensureDownloadingBuilder()`）。
   * 按钮：上游是「全部停止」（`ACTION_STOP_ALL` 的 PendingIntent.getService），
   * 鸿蒙侧按钮回调通过 `wantAgent` + `ACTION` 参数抵达本类 `dispatchAction`。
   */
  private buildDownloadingRequest(plan: DownloadNotificationPlan): notificationManager.NotificationRequest {
    const content: notificationManager.NotificationContent = {
      notificationContentType: notificationManager.ContentType.NOTIFICATION_CONTENT_BASIC_TEXT,
      normal: {
        title: plan.title,
        text: plan.text,
        additionalText: plan.info
      }
    };
    return {
      id: plan.id,
      notificationSlotType: notificationManager.SlotType.SERVICE_INFORMATION,
      content: content,
      wantAgent: this.buildActionAgent(DownloadService.ACTION_STOP_ALL, -1),
      isOngoing: plan.ongoing,
      isUnremovable: true,
      tapDismissed: false,
      template: this.buildProgressTemplate(plan.progress, plan.max, plan.progress < 0),
      actionButtons: [{
        title: DownloadNotificationPlanner.orFallback(
          GetText.getString('download_service_stop_all'), DownloadNotificationPlanner.FALLBACK_STOP_ALL),
        wantAgent: this.buildActionAgent(DownloadService.ACTION_STOP_ALL, -1)
      }]
    };
  }

  /**
   * 进度模板（`NOTIFICATION_CONTENT_PROGRESS` 的等价物）。
   * 鸿蒙 `DownloadTemplate`/`ProgressTemplate` 通过 `template` 字段表达；这里用 `Progress` 结构。
   */
  private buildProgressTemplate(progress: number, max: number,
    indeterminate: boolean): notificationManager.NotificationTemplate | undefined {
    if (indeterminate) {
      return undefined;
    }
    return {
      name: 'downloadTemplate',
      data: {
        title: '',
        fileName: '',
        progressValue: progress,
        maxValue: max
      }
    };
  }

  private async prepareActionAgents(): Promise<void> {
    if (this.stopAllAgent === null) {
      this.stopAllAgent = await this.createActionWantAgent(DownloadService.ACTION_STOP_ALL, -1, 1);
    }
    if (this.clearAgent === null) {
      this.clearAgent = await this.createActionWantAgent(DownloadService.ACTION_CLEAR, -1, 2);
    }
  }

  private buildActionWantInfo(action: string, gid: number, requestCodeOverride?: number): wantAgent.WantAgentInfo {
    const bundleName: string = this.context === null ? 'com.ehviewer.next' : this.context.abilityInfo.bundleName;
    const abilityName: string = this.context === null ? 'EntryAbility' : this.context.abilityInfo.name;
    const want: Want = {
      bundleName: bundleName,
      abilityName: abilityName,
      parameters: {
        'download_action': action,
        'gid': gid
      }
    };
    const reqCode: number = requestCodeOverride !== undefined
      ? requestCodeOverride
      : (gid >= 0 ? gid : (action === DownloadService.ACTION_CLEAR ? 2 : 1));
    return {
      wants: [want],
      actionType: wantAgent.OperationType.START_ABILITY,
      requestCode: reqCode,
      actionFlags: [wantAgent.WantAgentFlags.UPDATE_PRESENT_FLAG]
    };
  }

  private async createActionWantAgent(action: string, gid: number, requestCodeOverride: number): Promise<Object | null> {
    try {
      const info: wantAgent.WantAgentInfo = this.buildActionWantInfo(action, gid, requestCodeOverride);
      return await wantAgent.getWantAgent(info);
    } catch (e) {
      const err: BusinessError = e as BusinessError;
      hilog.error(DOMAIN, TAG, 'getWantAgent(%{public}s) failed, code=%{public}d, message=%{public}s',
        action, err.code, err.message);
      return null;
    }
  }

  /**
   * 通知按钮/点击的 wantAgent：把 action 塞进 `parameters`，由 `EntryAbility.onCreate / onNewWant`
   * 转给 `DownloadService.handleWantParameters`（G-1 回路）。
   */
  private buildActionAgent(action: string, gid: number): Object {
    if (gid < 0 && action === DownloadService.ACTION_STOP_ALL && this.stopAllAgent !== null) {
      return this.stopAllAgent;
    }
    if (gid < 0 && action === DownloadService.ACTION_CLEAR && this.clearAgent !== null) {
      return this.clearAgent;
    }
    return this.buildActionWantInfo(action, gid);
  }

  /**
   * 构造"下载完成"通知本体（上游 `ensureDownloadedBuilder()` + `onFinish` 的文案逻辑）。
   */
  private buildDownloadedRequest(plan: DownloadNotificationPlan):
    notificationManager.NotificationRequest {
    const content: notificationManager.NotificationContent = {
      notificationContentType: notificationManager.ContentType.NOTIFICATION_CONTENT_LONG_TEXT,
      longText: {
        title: plan.title,
        text: plan.text,
        additionalText: plan.info,
        longText: plan.lines.join('\n'),
        briefText: plan.text,
        expandedTitle: plan.title
      }
    };
    return {
      id: plan.id,
      notificationSlotType: notificationManager.SlotType.SERVICE_INFORMATION,
      content: content,
      wantAgent: this.buildActionAgent(DownloadService.ACTION_CLEAR, -1),
      isOngoing: plan.ongoing,
      tapDismissed: true,
      badgeNumber: plan.badge,
      actionButtons: [{
        title: DownloadNotificationPlanner.orFallback(
          GetText.getString('download_service_clear'), DownloadNotificationPlanner.FALLBACK_CLEAR),
        wantAgent: this.buildActionAgent(DownloadService.ACTION_CLEAR, -1)
      }]
    };
  }

  /** 构造 509 告警通知（上游 `ensure509Builder()`）。 */
  private build509Request(): notificationManager.NotificationRequest {
    const plan: DownloadNotificationPlan = DownloadNotificationPlanner.alert509Plan();
    const content: notificationManager.NotificationContent = {
      notificationContentType: notificationManager.ContentType.NOTIFICATION_CONTENT_BASIC_TEXT,
      normal: {
        title: plan.title,
        text: plan.text,
        additionalText: plan.info
      }
    };
    return {
      id: plan.id,
      notificationSlotType: notificationManager.SlotType.SERVICE_INFORMATION,
      content: content,
      isOngoing: plan.ongoing,
      tapDismissed: true
    };
  }

  // --------------------------------------------------------- DownloadListener

  public onGet509(): void {
    this.ensure509Delay();
    if (this.delay509 !== null) {
      this.delay509.show(this.build509Request());
    }
  }

  public onStart(info: DownloadInfo): void {
    this.ensureDownloadingDelay();
    this.ensureEnteredForeground().catch((e: Error) => {
      hilog.error(DOMAIN, TAG, 'ensureEnteredForeground failed: %{public}s', e.message);
    });
    if (this.downloadingDelay !== null) {
      // EhUtils.getSuitableTitle 真实签名是 string | null（上游 Kotlin 返 String?）→ 空串兜底，
      // startPlan 对空标题回退「下载服务」（与上游空标题显示效果一致）
      const request: notificationManager.NotificationRequest =
        this.buildDownloadingRequest(DownloadNotificationPlanner.startPlan(EhUtils.getSuitableTitle(info) ?? ''));
      this.downloadingDelay.startForeground(request, false);
    }
  }

  /**
   * 上游 `private onUpdate(info)`：速度 + 剩余时间 + 页数进度。
   */
  private onUpdate(info: DownloadInfo): void {
    this.ensureDownloadingDelay();
    // N3：速度/剩余/页数进度全部由 planner 推导（纯函数，宿主单测覆盖）
    const plan: DownloadNotificationPlan = DownloadNotificationPlanner.progressPlan(
      EhUtils.getSuitableTitle(info) ?? '', info.speed, info.remaining, info.finished, info.total);
    if (this.downloadingDelay !== null) {
      const request: notificationManager.NotificationRequest = this.buildDownloadingRequest(plan);
      this.downloadingDelay.startForeground(request, false);
    }
  }

  public onDownload(info: DownloadInfo): void {
    this.onUpdate(info);
  }

  public onGetPage(info: DownloadInfo): void {
    this.onUpdate(info);
  }

  /**
   * 上游 `onFinish(info)`：计数/文案/列表样式/节流发布，逐行保留。
   */
  public onFinish(info: DownloadInfo): void {
    if (this.downloadingDelay !== null) {
      this.downloadingDelay.cancel();
    }
    this.ensureDownloadedDelay();

    const finish: boolean = info.state === DownloadInfo.STATE_FINISH;
    const title: string = EhUtils.getSuitableTitle(info) ?? '';

    // N4：写 map → 推导计数/文案 → 生成 plan（三步都是纯函数，宿主单测可逐条断言）
    DownloadNotificationPlanner.markFinished(DownloadService.itemStateMap, DownloadService.itemTitleMap,
      info.gid, title, finish);
    const summary: FinishedSummary =
      DownloadNotificationPlanner.summarize(DownloadService.itemStateMap, DownloadService.itemTitleMap);
    if (this.downloadedDelay !== null) {
      this.downloadedDelay.show(this.buildDownloadedRequest(DownloadNotificationPlanner.donePlan(summary)));
    }

    this.checkStopSelf();
  }

  public onCancel(info: DownloadInfo): void {
    if (this.downloadingDelay !== null) {
      this.downloadingDelay.cancel();
    }
    this.checkStopSelf();
  }

  /**
   * 对应上游 `checkStopSelf()`：空闲就撤通知 + 停长时任务。
   */
  private checkStopSelf(): void {
    const manager: DownloadManager | null = this.downloadManager;
    const plan: ServiceStopPlan =
      ServiceLifecyclePlanner.plan(manager !== null, manager !== null && manager.isIdle());
    if (!plan.shouldStop) {
      return;
    }
    if (plan.cancelDownloadingNotification && this.downloadingDelay !== null) {
      this.downloadingDelay.cancel();
    }
    if (plan.clearForegroundFlag) {
      this.foregroundStarted = false;
    }
    if (plan.stopContinuousTask) {
      this.stopContinuousTask();
    }
  }

  // ------------------------------------------------------------ 网络状态监听

  /**
   * 上游 `initNetworkCallback()` 仅在检测到 MIUI 时注册，且**只打日志**。
   * 鸿蒙侧无 MIUI 分支（D-μ），但"网络切换可见"这个观测能力保留：
   * 注册 `netAvailable` / `netLost` 两个事件，仅日志。
   */
  private async initNetworkCallback(): Promise<void> {
    try {
      this.netConnection = connection.createNetConnection();
      this.netConnection.on('netAvailable', (info: connection.NetHandle): void => {
        hilog.debug(DOMAIN, TAG, 'network available: netId=%{public}d', info.netId);
      });
      this.netConnection.on('netLost', (info: connection.NetHandle): void => {
        hilog.debug(DOMAIN, TAG, 'network lost: netId=%{public}d', info.netId);
      });
      this.netConnection.register((e: BusinessError) => {
        if (e) {
          hilog.error(DOMAIN, TAG, 'register netConnection failed, code=%{public}d, message=%{public}s',
            e.code, e.message);
        }
      });
    } catch (e) {
      const err: BusinessError = e as BusinessError;
      hilog.error(DOMAIN, TAG, 'initNetworkCallback failed, code=%{public}d, message=%{public}s',
        err.code, err.message);
    }
  }

  private releaseNetworkConnection(): void {
    if (this.netConnection !== null) {
      this.netConnection.unregister((e: BusinessError) => {
        if (e) {
          hilog.error(DOMAIN, TAG, 'unregister netConnection failed, code=%{public}d, message=%{public}s',
            e.code, e.message);
        }
      });
      this.netConnection = null;
    }
  }

  // -------------------------------------------------------------- 静态清零入口

  /**
   * 对应上游 `companion object { fun clear() }`：清空完成/失败计数与两条映射。
   * `ACTION_CLEAR` 与用户点"清除"都会走这里。
   */
  public static clear(): void {
    // 计数没有独立状态了（由 map 推导），清空 map 即等价于上游三项计数归零
    DownloadService.itemStateMap.clear();
    DownloadService.itemTitleMap.clear();
  }

  /** 只读快照（由 map 推导），供 UI/测试断言；上游是三个私有静态 int。 */
  public static getCounters(): DownloadCounters {
    const summary: FinishedSummary =
      DownloadNotificationPlanner.summarize(DownloadService.itemStateMap, DownloadService.itemTitleMap);
    return {
      finishedCount: summary.finishedCount,
      failedCount: summary.failedCount,
      downloadedCount: summary.downloadedCount
    };
  }
}

export interface DownloadCounters {
  finishedCount: number;
  failedCount: number;
  downloadedCount: number;
}
