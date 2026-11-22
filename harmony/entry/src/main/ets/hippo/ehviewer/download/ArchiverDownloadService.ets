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
 * 移植自 app/src/main/java/com/hippo/ehviewer/download/ArchiverDownloadService.kt（298 行含注释 / 279 逻辑行）。
 *
 * 职责：归档下载的**轻量通知壳**——只负责"进度条 + 暂停/继续按钮 + 保活"，
 * 真正的传输在 `ArchiverDownloader`。
 *
 * ============================================================================
 * 组件映射
 * ============================================================================
 * | Android | 鸿蒙 | 说明 |
 * |---|---|---|
 * | `startForeground(id, notification)` | `backgroundTaskManager.startBackgroundRunning(DATA_TRANSFER)` + `notificationManager.publish()` | 需 `ohos.permission.KEEP_BACKGROUND_RUNNING`（Lead 侧申请） |
 * | `stopForeground(STOP_FOREGROUND_REMOVE/DETACH)` | `stopBackgroundRunning()`（保留通知 / 撤通知两种收尾） | 上游两个分支语义都保留：`ACTION_STOP` 撤通知；"暂停后"只撤长时任务、通知留下 |
 * | `NotificationCompat.Builder#addAction(ic_play/ic_pause)` | `actionButtons[].wantAgent`（`parameters.download_action`） | 回调经 `EntryAbility.onCreate` → `dispatchAction()`（与 DownloadService 同一条回路） |
 * | `PendingIntent.getActivity`（跳到详情页） | `wantAgent` + `bundleName/abilityName`（页面路由由 ui-scene 决定） | 这里只带 `gid`/`token` 参数 |
 * | `NotificationChannel(IMPORTANCE_LOW)` | `addSlot(SERVICE_INFORMATION, LEVEL_LOW)` | 与上游"低打扰"一致 |
 * | `NotificationManager.notify()` | `notificationManager.publish()` | — |
 *
 * 逐条等价点：
 *   1. action 常量值一字不改（`archiver_download_start/update/stop/pause/resume`）。
 *   2. `EXTRA_*` 键名一字不改（`title/gid/token/downloaded/total/speed/remaining/paused`）。
 *   3. `onStartCommand` 的四分支（STOP / PAUSE / RESUME / 默认更新）与返回码语义：
 *      STOP → `START_NOT_STICKY`；PAUSE → `START_NOT_STICKY`；RESUME → `START_STICKY`；
 *      默认 → `START_STICKY`。鸿蒙无"重启粘性"概念，对应"是否保持长时任务"（`keepAlive` 返回值）。
 *   4. `showPausedNotification()`：先确保前台已起 → 撤长时任务但**保留通知** → 再 publish 一次。
 *   5. 进度百分比 `min(100, downloaded * 100 / total)`；`total <= 0` 时用不确定进度条。
 *   6. `formatSpeedText(speed, remaining)`：speed < 0 归零；remaining >= 0 才显示剩余时间。
 */

import { Want, wantAgent } from '@kit.AbilityKit';
import { backgroundTaskManager } from '@kit.BackgroundTasksKit';
import { common } from '@kit.AbilityKit';
import notificationManager from '@ohos.notificationManager';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

import { ArchiverDownloader } from './ArchiverDownloader';
import { FileUtils } from '../../lib/yorozuya/FileUtils';
import { ReadableTime } from '../../util/ReadableTime';

const DOMAIN: number = 0x0D0C;
const TAG: string = 'ArchiverDownloadService';

const SLOT_ID: string = 'com.ehviewer.harmony.archiver_download';
const NOTIFICATION_ID: number = 0x41524348;
const REQUEST_PAUSE: number = 0x41524349;
const REQUEST_RESUME: number = 0x4152434A;

/** 归档下载通知文案（上游 `R.string.archiver_download_*`）。 */
const LABEL_SERVICE: string = '归档下载';
const LABEL_PAUSE: string = '暂停';
const LABEL_RESUME: string = '继续';
const TEXT_PAUSED: string = '已暂停';

/**
 * 归档下载通知的**纯数据**描述（无副作用）。
 *
 * 与 `DownloadService` 的 N1–N8 同法：把"显示什么/按哪个按钮/是否可消除"从
 * `buildRequest()` 里剥出来，宿主单测可验；`buildRequest()` 只负责拼平台结构。
 */
export interface ArchiverNotificationPlan {
  title: string;
  /** 正文：暂停文案 / 速度+剩余 / 空。 */
  text: string;
  /** additionalText：`42%`，total <= 0 时为空。 */
  info: string;
  /** 进度模板的 progressValue（0..100）。 */
  percent: number;
  /** total <= 0 时不挂进度模板。 */
  hasTemplate: boolean;
  paused: boolean;
  ongoing: boolean;
  /** 按钮与整条通知点击共用的动作（ACTION_PAUSE / ACTION_RESUME）。 */
  action: string;
  /** gid < 0 时不显示按钮（上游同款判断）。 */
  hasButton: boolean;
}

/**
 * 归档下载通知的纯判定（对位上游 `ArchiverDownloadService.buildNotification`）。
 *
 * 容易被"优化"掉的两处：
 *   1. 暂停时**必须**是 ongoing=false + tapDismissed=true + 按钮变"继续"，否则用户没法恢复；
 *   2. `total <= 0`（长度未知）时**不能挂进度模板**，否则进度条会停在 0 看着像卡死。
 */
export class ArchiverNotificationPlanner {
  /** `min(100, downloaded * 100 / total)`（上游同款整数除法 + 上限）。 */
  public static percent(downloaded: number, total: number): number {
    if (total <= 0) {
      return 0;
    }
    const progress: number = downloaded * 100 / total;
    return progress > 100 ? 100 : Math.floor(progress);
  }

  /** 速度文案：负速度按 0；`remaining >= 0` 才带「剩余」。 */
  public static formatSpeedText(speed: number, remaining: number): string {
    const safeSpeed: number = speed < 0 ? 0 : speed;
    const text: string = FileUtils.humanReadableByteCount(safeSpeed, false) + '/S';
    if (remaining >= 0) {
      return `${text} · 剩余 ${ReadableTime.getShortTimeInterval(remaining)}`;
    }
    return text;
  }

  public static plan(title: string, gid: number, downloaded: number, total: number, speed: number,
    remaining: number, paused: boolean): ArchiverNotificationPlan {
    const percent: number = ArchiverNotificationPlanner.percent(downloaded, total);
    let text: string = '';
    if (paused) {
      text = TEXT_PAUSED;
    } else if (speed > 0 || downloaded > 0) {
      text = ArchiverNotificationPlanner.formatSpeedText(speed, remaining);
    }
    return {
      title: title.length > 0 ? title : LABEL_SERVICE,
      text: text,
      info: total > 0 ? `${percent}%` : '',
      percent: percent,
      hasTemplate: total > 0,
      paused: paused,
      ongoing: !paused,
      action: paused ? ArchiverDownloadService.ACTION_RESUME : ArchiverDownloadService.ACTION_PAUSE,
      hasButton: gid >= 0
    };
  }
}
/** 一个 action 该怎么处理（纯数据）。 */
export interface ArchiverCommandPlan {
  kind: number;
  /** 是否需要先进前台（非暂停态的进度更新）。 */
  needForeground: boolean;
  /** 是否走"暂停态通知"路径（撤长时任务但保留通知）。 */
  paused: boolean;
  /** 返回给系统的 keepAlive（上游 START_STICKY 语义）。 */
  keepAlive: boolean;
  gid: number;
  title: string;
  token: string;
  downloaded: number;
  total: number;
  speed: number;
  remaining: number;
}

/**
 * `onStartCommand` 的**动作分派 + extras 解析**（纯函数，不碰服务生命周期）。
 *
 * 为什么必须单独测：五个 action 只靠字符串相等分派，写错一个分支**不会编译报错**，
 * 只会"按暂停变继续"或"按停止变成刷新通知"。真机上表现为"点按钮没反应 / 点了反而开始下载"，
 * 且与通知节流混在一起极难定位。
 *
 * 语义（对位上游 `ArchiverDownloadService.onStartCommand`）：
 *   - STOP → keepAlive=false；PAUSE → false；**RESUME → true**；默认更新 → true
 *   - PAUSE/RESUME 但不带 gid（<0）→ 视为无效指令（IGNORE）
 *   - **未知 action → 走默认"刷新进度"分支**（上游 else 分支），不是忽略
 *   - action 为 null → IGNORE（上游 `if (intent == null) return`）
 */
export class ArchiverCommandPlanner {
  public static readonly KIND_IGNORE: number = 0;
  public static readonly KIND_UPDATE: number = 1;
  public static readonly KIND_PAUSE: number = 2;
  public static readonly KIND_RESUME: number = 3;
  public static readonly KIND_STOP: number = 4;

  public static plan(action: string | null, extras: Map<string, Object>): ArchiverCommandPlan {
    const gid: number = ArchiverDownloadService.readLong(extras, ArchiverDownloadService.EXTRA_GID, -1);
    const paused: boolean =
      ArchiverDownloadService.readBoolean(extras, ArchiverDownloadService.EXTRA_PAUSED, false);
    const result: ArchiverCommandPlan = {
      kind: ArchiverCommandPlanner.KIND_IGNORE,
      needForeground: false,
      paused: paused,
      keepAlive: false,
      gid: gid,
      title: ArchiverDownloadService.readString(extras, ArchiverDownloadService.EXTRA_TITLE, ''),
      token: ArchiverDownloadService.readString(extras, ArchiverDownloadService.EXTRA_TOKEN, ''),
      downloaded: ArchiverDownloadService.readLong(extras, ArchiverDownloadService.EXTRA_DOWNLOADED, 0),
      total: ArchiverDownloadService.readLong(extras, ArchiverDownloadService.EXTRA_TOTAL, 0),
      speed: ArchiverDownloadService.readLong(extras, ArchiverDownloadService.EXTRA_SPEED, 0),
      remaining: ArchiverDownloadService.readLong(extras, ArchiverDownloadService.EXTRA_REMAINING, -1)
    };

    if (action === null) {
      result.kind = ArchiverCommandPlanner.KIND_IGNORE;
      return result;
    }
    if (action === ArchiverDownloadService.ACTION_STOP) {
      result.kind = ArchiverCommandPlanner.KIND_STOP;
      return result;
    }
    if (action === ArchiverDownloadService.ACTION_PAUSE) {
      result.kind = gid >= 0 ? ArchiverCommandPlanner.KIND_PAUSE : ArchiverCommandPlanner.KIND_IGNORE;
      return result;
    }
    if (action === ArchiverDownloadService.ACTION_RESUME) {
      result.kind = gid >= 0 ? ArchiverCommandPlanner.KIND_RESUME : ArchiverCommandPlanner.KIND_IGNORE;
      result.keepAlive = true;
      return result;
    }

    // 默认分支（ACTION_START / ACTION_UPDATE / 未知 action）：刷新进度通知
    result.kind = ArchiverCommandPlanner.KIND_UPDATE;
    result.needForeground = !paused;
    result.keepAlive = !paused;
    return result;
  }
}
export class ArchiverDownloadService {
  public static readonly ACTION_START: string = 'archiver_download_start';
  public static readonly ACTION_UPDATE: string = 'archiver_download_update';
  public static readonly ACTION_STOP: string = 'archiver_download_stop';
  public static readonly ACTION_PAUSE: string = 'archiver_download_pause';
  public static readonly ACTION_RESUME: string = 'archiver_download_resume';

  public static readonly EXTRA_TITLE: string = 'title';
  public static readonly EXTRA_GID: string = 'gid';
  public static readonly EXTRA_TOKEN: string = 'token';
  public static readonly EXTRA_DOWNLOADED: string = 'downloaded';
  public static readonly EXTRA_TOTAL: string = 'total';
  public static readonly EXTRA_SPEED: string = 'speed';
  public static readonly EXTRA_REMAINING: string = 'remaining';
  public static readonly EXTRA_PAUSED: string = 'paused';

  private static instance: ArchiverDownloadService | null = null;

  /**
   * A-01 的单调点击序号（进程内自增）。
   *
   * **为什么必须有它**：上游用 `PendingIntent.getService(context, requestCode, intent, flags)`，
   * 每次点击都是一次独立投递，接收方靠 extras 区分"第几次"。
   * 鸿蒙的等价物 wantAgent 有两处差异，会让"连点第二次无效"：
   *   ① `Want.parameters` 在 `getWantAgent()` 时**固化**，`trigger()` 不修改 Want 对象
   *   ② `UPDATE_PRESENT_FLAG` 的语义是"用新的额外数据**替换已存在**的呈现项数据"
   * ⇒ 两次点击的 parameters 逐字节相同 → 接收方无法区分 → 用户视角"按钮坏了"。
   * 修法：每次构建 agent 时把 `clickSeq`（自增）+ `ts` 塞进 parameters。
   * **不改变对外契约**（接收方读不到这两个键也照旧走原分支）。
   */
  private static clickSeqCounter: number = 0;

  /** 取下一个点击序号（1..999999 回卷；单条通知的点击次数远小于回卷周期）。 */
  public static nextClickSeq(): number {
    ArchiverDownloadService.clickSeqCounter =
      (ArchiverDownloadService.clickSeqCounter + 1) % 1000000;
    if (ArchiverDownloadService.clickSeqCounter === 0) {
      ArchiverDownloadService.clickSeqCounter = 1;
    }
    return ArchiverDownloadService.clickSeqCounter;
  }

  private context: common.UIAbilityContext | null = null;
  private foregroundStarted: boolean = false;
  private slotCreated: boolean = false;
  private notificationDisabled: boolean = false;
  private backgroundRunning: boolean = false;
  private hasActiveNotification: boolean = false;

  private constructor() {
  }

  public static getInstance(): ArchiverDownloadService {
    if (ArchiverDownloadService.instance === null) {
      ArchiverDownloadService.instance = new ArchiverDownloadService();
    }
    return ArchiverDownloadService.instance;
  }

  /** 绑定上下文（等价上游 `onCreate` 拿到的 Service 上下文）。 */
  public attach(context: common.UIAbilityContext): void {
    this.context = context;
  }

  /**
   * 对应上游 `onCreate()`：建低打扰通知槽。
   */
  public async onCreate(): Promise<void> {
    if (this.slotCreated) {
      return;
    }
    // 鸿蒙 addSlot 只接受 SlotType（没有「传 NotificationSlot 对象建槽」的重载），
    // 上游 NotificationChannel 的 name/description/badge 没有等价入参 —— 记入 D-ν。
    try {
      await notificationManager.addSlot(notificationManager.SlotType.SERVICE_INFORMATION);
      this.slotCreated = true;
    } catch (e) {
      const err: BusinessError = e as BusinessError;
      hilog.error(DOMAIN, TAG, 'addSlot failed, code=%{public}d, message=%{public}s', err.code, err.message);
    }
  }

  /**
   * 对应上游 `onStartCommand(intent, flags, startId)`。
   * 返回 `true` 表示"保持长时任务"（上游 `START_STICKY`），
   * 返回 `false` 表示"用完即停"（上游 `START_NOT_STICKY`）。
   */
  public async onStartCommand(action: string | null, extras: Map<string, Object>): Promise<boolean> {
    await this.onCreate();
    if (action === ArchiverDownloadService.ACTION_START) {
      this.notificationDisabled = false;
    }

    // 分派与 extras 解析全在 ArchiverCommandPlanner（纯函数、有单测）；这里只执行副作用
    const plan: ArchiverCommandPlan = ArchiverCommandPlanner.plan(action, extras);

    if (plan.kind === ArchiverCommandPlanner.KIND_IGNORE) {
      this.stopSelfIfNeeded();
      return plan.keepAlive;
    }
    if (plan.kind === ArchiverCommandPlanner.KIND_STOP) {
      await this.stopForeground(true);
      this.foregroundStarted = false;
      return plan.keepAlive;
    }
    if (plan.kind === ArchiverCommandPlanner.KIND_PAUSE) {
      ArchiverDownloader.getInstance().pause(plan.gid);
      return plan.keepAlive;
    }
    if (plan.kind === ArchiverCommandPlanner.KIND_RESUME) {
      await ArchiverDownloader.getInstance().resume(plan.gid);
      return plan.keepAlive;
    }

    // KIND_UPDATE：无通知权限且已退化为静默时，跳过每 500ms 重建 wantAgent 与通知对象
    if (this.notificationDisabled && (this.foregroundStarted || !plan.paused)) {
      return plan.keepAlive;
    }
    const request: notificationManager.NotificationRequest = await this.buildRequest(plan.title, plan.gid,
      plan.token, plan.downloaded, plan.total, plan.speed, plan.remaining, plan.paused);
    if (plan.paused) {
      await this.showPausedNotification(request);
      return plan.keepAlive;
    }
    if (!this.foregroundStarted) {
      await this.startForegroundCompat(NOTIFICATION_ID, request);
      this.foregroundStarted = true;
    } else {
      await this.publish(request);
    }
    return plan.keepAlive;
  }
  /**
   * 对应上游 `showPausedNotification(notification)`：
   * 确保前台已起 → 撤长时任务（保留通知）→ 再发一次通知 → stopSelf。
   */
  private async showPausedNotification(request: notificationManager.NotificationRequest): Promise<void> {
    if (!this.foregroundStarted) {
      await this.startForegroundCompat(NOTIFICATION_ID, request);
      this.foregroundStarted = true;
    }
    // 上游 STOP_FOREGROUND_DETACH：撤长时任务但保留通知
    await this.stopForeground(false);
    this.foregroundStarted = false;
    await this.publish(request);
    this.stopSelfIfNeeded();
  }

  /**
   * 构造进度通知（上游 `buildNotification(...)`）。
   */
  private async buildRequest(title: string, gid: number, token: string, downloaded: number, total: number,
    speed: number, remaining: number, paused: boolean): Promise<notificationManager.NotificationRequest> {
    // 判定全在 ArchiverNotificationPlanner（纯函数、有单测）；本方法只拼平台结构
    const plan: ArchiverNotificationPlan =
      ArchiverNotificationPlanner.plan(title, gid, downloaded, total, speed, remaining, paused);
    const requestCode: number = paused ? REQUEST_RESUME : REQUEST_PAUSE;

    const content: notificationManager.NotificationContent = {
      notificationContentType: notificationManager.ContentType.NOTIFICATION_CONTENT_BASIC_TEXT,
      normal: {
        title: plan.title,
        text: plan.text,
        additionalText: plan.info
      }
    };

    // A-01：agent 必须是 `getWantAgent()` 的**真实产物**（原实现把 WantAgentInfo 当 WantAgent 塞进
    // NotificationRequest，类型上靠 Object 蒙过去、运行期按钮拿不到可用 agent）。现在 await 出来，
    // 且每次构建都带新的 clickSeq/ts（见 nextClickSeq 的注释）。
    const tapAgent: Object | null =
      await this.serviceActionAgent(plan.action, gid, token, requestCode);
    const request: notificationManager.NotificationRequest = {
      id: NOTIFICATION_ID,
      notificationSlotType: notificationManager.SlotType.SERVICE_INFORMATION,
      content: content,
      isOngoing: plan.ongoing,
      tapDismissed: !plan.ongoing
    };
    if (tapAgent !== null) {
      request.wantAgent = tapAgent;
    }

    if (plan.hasButton) {
      // 按钮单独取一次 agent：它与点击的通知主体是**两个不同的呈现项**，
      // 共用同一个 agent 会让"点通知"和"点按钮"互相覆写额外数据（同 UPDATE_PRESENT_FLAG 的坑）。
      const buttonAgent: Object | null =
        await this.serviceActionAgent(plan.action, gid, token, requestCode);
      if (buttonAgent !== null) {
        request.actionButtons = [{
          title: paused ? LABEL_RESUME : LABEL_PAUSE,
          wantAgent: buttonAgent
        }];
      } else {
        // 不静默：拿不到 agent 时按钮会显示但点了没反应，必须在日志里能看出来
        hilog.error(DOMAIN, TAG,
          'actionButtons 未挂载（getWantAgent 失败）—— 通知上的「%{public}s」按钮将无效',
          paused ? LABEL_RESUME : LABEL_PAUSE);
      }
    }

    if (plan.hasTemplate) {
      request.template = {
        name: 'downloadTemplate',
        data: {
          title: plan.title,
          fileName: plan.title,
          progressValue: plan.percent,
          maxValue: 100
        }
      };
    }
    return request;
  }


  /**
   * 对应上游 `serviceActionIntent(action, gid, requestCode)`：
   * 把 action 塞进 want 的 parameters，由 EntryAbility 转发回 `onStartCommand`。
   *
   * A-01 修复三件事（原实现三件都缺）：
   *   ① 返回**真实 agent**（`await getWantAgent(info)`），而不是把 `WantAgentInfo` 当 WantAgent 返回；
   *   ② parameters 带 `clickSeq` + `ts` → 两次点击在接收方可区分（对位上游 per-click PendingIntent）；
   *   ③ 拿不到 agent 时返回 null 并打 error（不静默返回一个假对象）。
   */
  private async serviceActionAgent(action: string, gid: number, token: string,
    requestCode: number): Promise<Object | null> {
    const bundleName: string = this.context === null ? 'com.ehviewer.harmony' : this.context.abilityInfo.bundleName;
    const abilityName: string = this.context === null ? 'EntryAbility' : this.context.abilityInfo.name;
    const clickSeq: number = ArchiverDownloadService.nextClickSeq();
    const ts: number = Date.now();
    const want: Want = {
      bundleName: bundleName,
      abilityName: abilityName,
      parameters: {
        'archiver_action': action,
        'gid': gid,
        'token': token,
        'requestCode': requestCode,
        'clickSeq': clickSeq,
        'ts': ts
      }
    };
    const info: wantAgent.WantAgentInfo = {
      wants: [want],
      actionType: wantAgent.OperationType.START_ABILITY,
      requestCode: requestCode,
      actionFlags: [wantAgent.WantAgentFlags.UPDATE_PRESENT_FLAG]
    };
    try {
      const agent: Object = await wantAgent.getWantAgent(info);
      // A-01 验收判据（连点两次看这两行 log 的 clickSeq 是否递增；接收方一侧见 EntryAbility）
      hilog.info(DOMAIN, TAG,
        'serviceActionAgent: action=%{public}s gid=%{public}d requestCode=%{public}d clickSeq=%{public}d ts=%{public}d',
        action, gid, requestCode, clickSeq, ts);
      return agent;
    } catch (e) {
      const err: BusinessError = e as BusinessError;
      hilog.error(DOMAIN, TAG,
        'getWantAgent failed（后果：通知点击与「暂停/继续」按钮全部无动作）code=%{public}d message=%{public}s',
        err.code, err.message);
      return null;
    }
  }

  /**
   * 对应上游 `startForegroundCompat(id, notification)`：
   * 挂通知 + 起长时任务（幂等）。
   */
  private async startForegroundCompat(id: number,
    request: notificationManager.NotificationRequest): Promise<void> {
    await this.publish(request);
    if (this.context === null || this.backgroundRunning) {
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
      this.backgroundRunning = true;
    } catch (e) {
      const err: BusinessError = e as BusinessError;
      this.backgroundRunning = false;
      hilog.warn(DOMAIN, TAG, 'startBackgroundRunning unavailable, code=%{public}d, message=%{public}s',
        err.code, err.message);
    }
  }

  /**
   * @param removeNotification true 等价 `STOP_FOREGROUND_REMOVE`（撤长时任务 + 撤通知）；
   *                           false 等价 `STOP_FOREGROUND_DETACH`（撤长时任务，通知留下）。
   */
  private async stopForeground(removeNotification: boolean): Promise<void> {
    if (this.context !== null && this.backgroundRunning) {
      try {
        await backgroundTaskManager.stopBackgroundRunning(this.context);
      } catch (e) {
        const err: BusinessError = e as BusinessError;
        hilog.error(DOMAIN, TAG, 'stopBackgroundRunning failed, code=%{public}d, message=%{public}s',
          err.code, err.message);
      } finally {
        this.backgroundRunning = false;
      }
    }
    if (removeNotification && this.hasActiveNotification) {
      try {
        await notificationManager.cancel(NOTIFICATION_ID);
      } catch (e) {
        const err: BusinessError = e as BusinessError;
        hilog.error(DOMAIN, TAG, 'cancel notification failed, code=%{public}d, message=%{public}s',
          err.code, err.message);
      } finally {
        this.hasActiveNotification = false;
      }
    }
  }

  private async publish(request: notificationManager.NotificationRequest): Promise<void> {
    if (this.notificationDisabled) {
      return;
    }
    try {
      await notificationManager.publish(request);
      this.hasActiveNotification = true;
    } catch (e) {
      const err: BusinessError = e as BusinessError;
      if (err.code === 1600004) {
        if (!this.notificationDisabled) {
          this.notificationDisabled = true;
          hilog.warn(DOMAIN, TAG, 'notification disabled (code=1600004), degrading to silent mode');
        }
        return;
      }
      hilog.error(DOMAIN, TAG, 'publish failed, code=%{public}d, message=%{public}s', err.code, err.message);
    }
  }

  /** 对应上游 `stopSelfIfNeeded()`：没进前台就直接收工。 */
  private stopSelfIfNeeded(): void {
    if (!this.foregroundStarted) {
      hilog.info(DOMAIN, TAG, 'stopSelfIfNeeded: nothing to keep alive');
    }
  }

  // -------------------------------------------------------------- 静态入口

  /** 对应上游 `ArchiverDownloadService.start(context, title, gid, token)`。 */
  public static start(title: string | null, gid: number, token: string | null): void {
    const extras: Map<string, Object> = new Map<string, Object>();
    extras.set(ArchiverDownloadService.EXTRA_TITLE, title === null ? '' : title);
    extras.set(ArchiverDownloadService.EXTRA_GID, gid);
    extras.set(ArchiverDownloadService.EXTRA_TOKEN, token === null ? '' : token);
    ArchiverDownloadService.dispatch(ArchiverDownloadService.ACTION_START, extras);
  }

  /** 对应上游 `updateProgress(context, title, gid, token, downloaded, total, speed, remaining, paused)`。 */
  public static updateProgress(title: string | null, gid: number, token: string | null, downloaded: number,
    total: number, speed: number, remaining: number, paused: boolean): void {
    const extras: Map<string, Object> = new Map<string, Object>();
    extras.set(ArchiverDownloadService.EXTRA_TITLE, title === null ? '' : title);
    extras.set(ArchiverDownloadService.EXTRA_GID, gid);
    extras.set(ArchiverDownloadService.EXTRA_TOKEN, token === null ? '' : token);
    extras.set(ArchiverDownloadService.EXTRA_DOWNLOADED, downloaded);
    extras.set(ArchiverDownloadService.EXTRA_TOTAL, total);
    extras.set(ArchiverDownloadService.EXTRA_SPEED, speed);
    extras.set(ArchiverDownloadService.EXTRA_REMAINING, remaining);
    extras.set(ArchiverDownloadService.EXTRA_PAUSED, paused);
    ArchiverDownloadService.dispatch(ArchiverDownloadService.ACTION_UPDATE, extras);
  }

  /** 对应上游 `stop(context)`。 */
  public static stop(): void {
    ArchiverDownloadService.dispatch(ArchiverDownloadService.ACTION_STOP, new Map<string, Object>());
  }

  private static dispatch(action: string, extras: Map<string, Object>): void {
    const service: ArchiverDownloadService = ArchiverDownloadService.getInstance();
    service.onStartCommand(action, extras).catch((e: Object) => {
      hilog.error(DOMAIN, TAG, 'dispatch %{public}s failed: %{public}s', action, String(e));
    });
  }

  /**
   * A-01：**通知 / 「暂停·继续」按钮点击的入口**（由 `EntryAbility` 在 `onCreate` / `onNewWant` 调用）。
   *
   * 为什么需要它：`serviceActionAgent()` 造出的 want 会带着 `archiver_action` 参数重新拉起 EntryAbility，
   * 但原实现里**全仓没有任何地方读这个参数**（`grep archiver_action` 只有写入侧一处）
   * ⇒ 即使 agent 造对了，点击也只会"把应用拉到前台"，不会暂停/继续下载。
   * 本方法把 want 参数原样搬进 extras 交给 `onStartCommand`，打通最后一跳。
   *
   * @returns true = 本类已处理（调用方不必再走"默认打开首页"的分支）
   */
  public static handleWantParameters(params: Record<string, Object> | null | undefined): boolean {
    if (params === null || params === undefined) {
      return false;
    }
    const actionValue: Object | undefined = params['archiver_action'];
    if (actionValue === undefined || actionValue === null) {
      return false;
    }
    const action: string = String(actionValue);
    const extras: Map<string, Object> = new Map<string, Object>();
    const keys: string[] = Object.keys(params);
    for (let i = 0; i < keys.length; i++) {
      extras.set(keys[i], params[keys[i]] as Object);
    }
    // 验收判据（A-01）：连点两次，这两行 log 的 clickSeq 必须递增、ts 必须不同
    hilog.info(DOMAIN, TAG,
      'handleWantParameters: action=%{public}s gid=%{public}d clickSeq=%{public}d ts=%{public}d',
      action,
      ArchiverDownloadService.readLong(extras, 'gid', -1),
      ArchiverDownloadService.readLong(extras, 'clickSeq', -1),
      ArchiverDownloadService.readLong(extras, 'ts', -1));
    ArchiverDownloadService.dispatch(action, extras);
    return true;
  }

  // ------------------------------------------------------------ extras 读取

  public static readString(extras: Map<string, Object>, key: string, fallback: string): string {
    const value: Object | undefined = extras.get(key);
    if (value === undefined || value === null) {
      return fallback;
    }
    return String(value);
  }

  public static readLong(extras: Map<string, Object>, key: string, fallback: number): number {
    const value: Object | undefined = extras.get(key);
    if (value === undefined || value === null) {
      return fallback;
    }
    const parsed: number = Number(value);
    return isNaN(parsed) ? fallback : parsed;
  }

  public static readBoolean(extras: Map<string, Object>, key: string, fallback: boolean): boolean {
    const value: Object | undefined = extras.get(key);
    if (value === undefined || value === null) {
      return fallback;
    }
    return value === true || String(value) === 'true';
  }
}
