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
 * 移植自 app/src/main/java/com/hippo/ehviewer/download/DownloadManager.java（1315 逻辑行 / 1513 行含注释）。
 *
 * ============================================================================
 * 一、状态机（1:1 保留，状态值来自 storage-db 的 DownloadInfo）
 * ============================================================================
 * 「落库」列回答 lead 的 D-012 追问：该转换是否需要 `await` 一次 RDB 写。
 * 只有「落库=是」的转换才引入异步边界；落库=否 的转换是纯内存，不存在交错窗口。
 *
 * | 上游状态 | 值 | 鸿蒙侧 | 进入条件（上游对应代码） | 离开条件 | 落库 |
 * |---|---|---|---|---|---|
 * | STATE_INVALID | -1 | 同值，只作查询返回值 | `getDownloadState(gid)` 查不到记录时返回 | 从不被写入实体 | 否（纯返回值） |
 * | STATE_NONE | 0 | 同值 | `addDownload(galleryInfo, label)` 建记录；`stopDownloadInternal`；`stopCurrentDownloadInternal`；`stopAllDownload`（清 waitList 中每条）；`stopRangeDownloadInternal`；`getNoneDownloadInfo`；`addDownloadList` 里把 WAIT/DOWNLOAD 归零 | → WAIT（start* 系列） | **是**（`EhDB.putDownloadInfo`，每条一次） |
 * | STATE_WAIT | 1 | 同值 | `startDownload`（已存在且非 WAIT）；`startRangeDownload` / `startAllDownload`（NONE 或 FAILED）；`addDownloadList` 保留；`addDownload(info,label,STATE_WAIT)` | → DOWNLOAD（`ensureDownload` 从 waitList 取队首）；→ NONE（stop*） | **是** |
 * | STATE_DOWNLOAD | 2 | 同值 | 仅 `ensureDownload()`：`currentTask != null` 时直接返回，保证**同时只有一个下载** | → FINISH/FAILED（`NotifyTask.TYPE_ON_FINISH`）；→ NONE（stop*） | **是**（speed/remaining/total/finished/downloaded/legacy 的复位一并落库） |
 * | STATE_FINISH | 3 | 同值 | `onFinish` 且 `legacy = total - finished == 0` | → WAIT（`startRangeDownload` / `startAllDownload` 允许 FINISH 重下） | **是** |
 * | STATE_FAILED | 4 | 同值 | `onFinish` 且 `legacy != 0` | → WAIT（start* 系列） | **是** |
 * | STATE_UPDATE | 5 | 同值，**本管理器从不写入** | 由版本升级流程使用（不在本文件范围） | — | 不涉及 |
 * | GOTO_NEW | 6 | 同值，非状态，仅作 UI 跳转常量 | — | — | 否 |
 *
 * 另有一类"只动内存、不落库"的写入（与上游一致）：
 *   `onGetPages` / `onPageSuccess` / `onPageFailure` 只更新 `total/finished/downloaded` 并通知监听器，
 *   不调 `putDownloadInfo`；`SpeedReminder` 只更新 `speed/remaining`。这些是**展示态**，
 *   崩溃后由 `.ehviewer`（SpiderInfo）重新读出，因此无需落库 —— 上游同样如此。
 *
 * ----------------------------------------------------------------------------
 * 原子性设计（D-012 专项：RDB 全层 async 之后如何不撕裂状态转换）
 * ----------------------------------------------------------------------------
 * 问题：上游所有状态转换都在主线程 Handler 上执行，天然串行、天然原子。D-012 之后每个
 * `EhDB.*` / `SpiderQueen.*` 调用都是真实 `await`，两个转换可能交错。典型撕裂窗口是
 * `ensureDownload()`：读 waitList → await 取 spider → 写 currentTask → await 落库；
 * 若中间插进 `stopCurrentDownload()`，就会出现"spider 已绑定、currentTask 已被置空"的悬挂。
 *
 * 对策（三层，缺一不可）：
 *   1. **单一串行队列**：`serial(body)` 把所有**写路径**（start* / stop* / delete* /
 *      changeLabel / addLabel* / renameLabel / moveLabel / getNoneDownloadInfo /
 *      resetAllReadingProgress）与**下载回调的处理体**（`enqueueNotifyTask` →
 *      `applyNotifyTask`）串成一条 FIFO 链。队列用 Promise 链（`lockTail`）实现，失败也释放。
 *      于是"读-改-写"三段在同一个 body 内，await 只发生在 body 内部，不会被别的转换插入。
 *   2. **禁止嵌套入队**：body 内部只 `await` 底层异步调用，**不再调用 `serial()`**
 *      （嵌套 = 自锁：await 排在队尾的自己）。`applyNotifyTask` 的 `TYPE_ON_FINISH` 分支
 *      因此把落库 / 回调 / `ensureDownload()` 直接写在体内。
 *   3. **执行时刻快照 + 身份校验**：`applyNotifyTask` 在处理时刻（而非回调时刻）读
 *      `currentTask`，与上游 `NotifyTask.run()` 一致；释放 spider 前先
 *      `removeOnSpiderListener`，保证迟到的回调打不到新任务上（竞态 R3）。
 *
 * 不进队列的只有**纯读**接口（`getDownloadInfo` / `getAllDownloadInfoList` /
 * `getDownloadState` …）与**展示态写入**（speed/remaining），它们不参与状态机不变式。
 * 也**不用** TaskPool：跨线程只会复制 `DownloadInfo`，破坏"同一实体"语义。
 *
 * 关键竞态点（上游靠"全部在主线程 Handler 上执行"保证，鸿蒙侧没有那个约束，故显式加锁）：
 *   R1 `ensureDownload()` 与 `stopCurrentDownloadInternal()` 交叉：上游靠主线程串行；
 *      这里所有**写操作**（含 ensureDownload）都进 `serial()` 串行队列（FIFO），保证
 *      `currentTask`/`currentSpider`/`waitList` 三者不会半更新。
 *   R2 `SpeedReminder` 定时器与状态变更交叉：定时器回调只读 `currentTask` 并写 speed/remaining，
 *      若 `currentTask` 已变 null 则跳过；`stop()` 里清 timer + 清累计。
 *   R3 `onFinish` 里先置 `currentTask = null` 再 release spider，然后 `ensureDownload()` 启下一个：
 *      顺序逐行保留，否则会把下一个任务的 spider 监听器串到上一个身上。
 *   R4 `NotifyTask` 复用池（上游 ConcurrentPool(5)）：池里对象只做数据载体，`run()` 结束推回，
 *      不需要锁；但 `pop()` 可能拿到脏字段，所以每个 set*Data 都把不相关字段显式复位。
 *   R5 `mWaitList` 的遍历删除：Java 用 Iterator.remove，这里统一用「倒序扫描 + splice」，
 *      避免边遍历边改导致的跳过（`stopAllDownload` / `stopRangeDownloadInternal` / `getNoneDownloadInfo`）。
 *
 * ============================================================================
 * 二、平台差异（本文件内已处理的）
 * ============================================================================
 *   D-a 无 `Context`：上游 `mContext` 只用于 `takePersistableUriPermission`（恢复 content:// 授权）。
 *       鸿蒙侧 URI 授权由 `@ohos.file.fs` + 系统选择器直接持有，无需在此重放；仅打日志。
 *   D-b 无同步 DB：上游构造器里同步 `EhDB.getAllDownloadInfo()`。这里改为私有构造 + 静态
 *       `create()` 异步工厂（core-runtime 的 `EhApplication.getDownloadManager()` 需相应改为异步）。
 *   D-c 无 `AsyncTask`：`resetAllReadingProgress` 改为 async 方法，顺序（串行写 .ehviewer）不变。
 *   D-d 无嵌套类/匿名类：`NotifyTask` / `SpeedReminder` 提到文件作用域（同文件，不导出）；
 *       `DownloadListener` 由嵌套接口提为同文件导出接口（ArkTS 无嵌套接口）。
 *   D-e 无 `List<DownloadInfo>` 泛型重载：`addDownload` 的三个重载拆成
 *       `addDownloadList(list)` / `addDownload(galleryInfo, label, state)` / `addDownload(galleryInfo, label)`。
 *   D-f `SimpleHandler.post/postDelayed` → `setTimeout` / `clearTimeout`。
 */

import { hilog } from '@kit.PerformanceAnalysisKit';

import { DownloadInfoListener } from './DownloadInfoListener';
import { EhDB } from '../EhDB';
import { Settings } from '../Settings';
import { GalleryInfo } from '../client/data/GalleryInfo';
import { DownloadInfo } from '../dao/DownloadInfo';
import { DownloadLabel } from '../dao/DownloadLabel';
import { SpiderDen, MODE_DOWNLOAD } from '../spider/SpiderDen';
import { MediaScannerLike, NoopMediaScanner } from './MediaScanner';
import { SpiderInfo } from '../spider/SpiderInfo';
import { OnSpiderListener, SpiderQueen } from '../spider/SpiderQueen';
import { UniFile } from '../../unifile/UniFile';
import { MathUtils } from '../../lib/yorozuya/MathUtils';
import { DOWNLOAD_INFO_FILENAME, DOWNLOAD_INFO_HEADER } from './DownloadInfoCsvFormat';
import { ObjectUtils } from '../../lib/yorozuya/ObjectUtils';

const DOMAIN: number = 0x0D0C;
const TAG: string = 'DownloadManager';

/**
 * `.ehviewer` 的两个线格式常量已迁到无依赖叶子模块 `DownloadInfoCsvFormat`
 * （原因见该文件头：把 UI 层/${'$'}{'}'}单测从 RDB 依赖图里解出来）。
 * 这里 **re-export** 保持既有 import 不变 —— 常量仍只有一处定义。
 */
export { DOWNLOAD_INFO_FILENAME, DOWNLOAD_INFO_HEADER };

/** 通知任务复用池容量（上游 `new ConcurrentPool<>(5)`）。 */
const NOTIFY_TASK_POOL_SIZE: number = 5;

/** 速度统计周期（上游 `SimpleHandler.postDelayed(this, 2000)`）。 */
const SPEED_REFRESH_INTERVAL_MS: number = 2000;

/** 无法计算剩余时间时的占位值：300 天（上游原值，保留）。 */
const REMAINING_PLACEHOLDER_MS: number = 300 * 24 * 60 * 60 * 1000;

/**
 * 上游嵌套接口 `DownloadManager.DownloadListener`（下载服务倾听器）。
 * ArkTS 没有嵌套接口/匿名类，提到文件作用域并导出；成员与上游逐条一致。
 */
export interface DownloadListener {
  /** 命中 509（配额/限流）错误。 */
  onGet509(): void;

  /** 开始下载某条记录。 */
  onStart(info: DownloadInfo): void;

  /** 速度/进度刷新（由 SpeedReminder 每 2s 驱动）。 */
  onDownload(info: DownloadInfo): void;

  /** 单页下载进度更新。 */
  onGetPage(info: DownloadInfo): void;

  /** 本条记录下载结束（FINISH 或 FAILED）。 */
  onFinish(info: DownloadInfo): void;

  /** 本条记录被取消/停止。 */
  onCancel(info: DownloadInfo): void;
}

/**
 * 上游 `private class DownloadManager.NotifyTask`：一次性数据载体，
 * 把 SpiderQueen 回调（可能在 IO 线程）收到的数据搬到"主线程"再处理。
 * 鸿蒙侧回调上下文已经都在同一个事件循环里，但**保留这个收敛点**（单点处理 + 复用池），
 * 目的在于：① 保证 `currentTask` 的快照发生在处理时而不是回调时（与上游一致）；
 * ② 避免每页都新建对象。
 */
class NotifyTask {
  public static readonly TYPE_ON_GET_PAGES: number = 0;
  public static readonly TYPE_ON_GET_509: number = 1;
  public static readonly TYPE_ON_PAGE_DOWNLOAD: number = 2;
  public static readonly TYPE_ON_PAGE_SUCCESS: number = 3;
  public static readonly TYPE_ON_PAGE_FAILURE: number = 4;
  public static readonly TYPE_ON_FINISH: number = 5;

  public type: number = 0;
  public pages: number = 0;
  public index: number = 0;
  public contentLength: number = 0;
  public receivedSize: number = 0;
  public bytesRead: number = 0;
  public error: string = '';
  public finished: number = 0;
  public downloaded: number = 0;
  public total: number = 0;
  /**
   * **回调时刻**的 gid 快照（D-012 身份校验用）。
   *
   * 上游靠"回调与状态变更都在主线程"保证顺序；D-012 之后通知任务是异步执行的，
   * 队列里可能还压着**上一个任务**的进度，而 `currentTask` 已经换成新任务。
   * 没有这个快照，就会把 A 的页数写到 B 的记录上（不报错，只是数据错乱）。
   */
  public gid: number = -1;

  public setOnGetPagesData(pages: number): void {
    this.reset();
    this.type = NotifyTask.TYPE_ON_GET_PAGES;
    this.pages = pages;
  }

  public setOnGet509Data(index: number): void {
    this.reset();
    this.type = NotifyTask.TYPE_ON_GET_509;
    this.index = index;
  }

  public setOnPageDownloadData(index: number, contentLength: number, receivedSize: number,
    bytesRead: number): void {
    this.reset();
    this.type = NotifyTask.TYPE_ON_PAGE_DOWNLOAD;
    this.index = index;
    this.contentLength = contentLength;
    this.receivedSize = receivedSize;
    this.bytesRead = bytesRead;
  }

  public setOnPageSuccessData(index: number, finished: number, downloaded: number, total: number): void {
    this.reset();
    this.type = NotifyTask.TYPE_ON_PAGE_SUCCESS;
    this.index = index;
    this.finished = finished;
    this.downloaded = downloaded;
    this.total = total;
  }

  public setOnPageFailureData(index: number, error: string, finished: number, downloaded: number,
    total: number): void {
    this.reset();
    this.type = NotifyTask.TYPE_ON_PAGE_FAILURE;
    this.index = index;
    this.error = error;
    this.finished = finished;
    this.downloaded = downloaded;
    this.total = total;
  }

  public setOnFinishData(finished: number, downloaded: number, total: number): void {
    this.reset();
    this.type = NotifyTask.TYPE_ON_FINISH;
    this.finished = finished;
    this.downloaded = downloaded;
    this.total = total;
  }

  /** 复用池要求：出池即干净，避免上一条任务的残值被读到。 */
  private reset(): void {
    this.gid = -1;
    this.pages = 0;
    this.index = 0;
    this.contentLength = 0;
    this.receivedSize = 0;
    this.bytesRead = 0;
    this.error = '';
    this.finished = 0;
    this.downloaded = 0;
    this.total = 0;
  }
}

/** 时间倒序（上游 `DATE_DESC_COMPARATOR`：`lhs.time - rhs.time > 0 → -1`）。 */
function dateDescComparator(lhs: DownloadInfo, rhs: DownloadInfo): number {
  const dif: number = lhs.time - rhs.time;
  if (dif > 0) {
    return -1;
  } else if (dif < 0) {
    return 1;
  }
  return 0;
}

/**
 * 下载状态机的**纯判定**（不碰存储、不碰队列）。
 *
 * 为什么单独抽出来：状态表里真正会出错的不是赋值，而是**进入条件**——
 *   - `startRangeDownload` 允许 NONE / FAILED / **FINISH**（已下完的可以重下）
 *   - `startAllDownload`  只允许 NONE / FAILED（FINISH 不参与"全部开始"）
 *   - `addDownloadList`（恢复）把 WAIT / DOWNLOAD 一律归 NONE（不允许恢复出"正在下载"）
 * 这三个不对称是上游的真实语义，写反了不会报错、只会行为漂移。抽成纯函数后由宿主单测钉住。
 */
export class DownloadStateMachine {
  /** `startRangeDownload` 的可入队状态：NONE / FAILED / FINISH（FINISH 允许重下）。 */
  static isStartableForRange(state: number): boolean {
    return state === DownloadInfo.STATE_NONE ||
      state === DownloadInfo.STATE_FAILED ||
      state === DownloadInfo.STATE_FINISH;
  }

  /** `startAllDownload` 的可入队状态：只有 NONE / FAILED（**不含** FINISH）。 */
  static isStartableForAll(state: number): boolean {
    return state === DownloadInfo.STATE_NONE || state === DownloadInfo.STATE_FAILED;
  }

  /** 恢复/导入时：WAIT / DOWNLOAD 一律归 NONE（不能凭空恢复出"正在下载"）。 */
  static needsResetOnRestore(state: number): boolean {
    return state === DownloadInfo.STATE_WAIT || state === DownloadInfo.STATE_DOWNLOAD;
  }

  /** `onFinish` 的终态判定：`legacy = total - finished`，0 才算 FINISH。 */
  static resolveFinishState(legacy: number): number {
    return legacy === 0 ? DownloadInfo.STATE_FINISH : DownloadInfo.STATE_FAILED;
  }

  /**
   * 终态判定（**推荐入口**）：直接从 total / finished 算，杜绝"忘了先给 legacy 赋值"。
   *
   * 为什么加这个：上游 `TYPE_ON_FINISH` 里有一步 `info.legacy = mTotal - mFinished;`
   * （DownloadManager.java:1296）很容易在移植时漏掉 —— 一旦漏掉，`legacy` 会保持
   * 开始下载时写入的 `-1`，于是 `resolveFinishState(-1)` 恒返回 STATE_FAILED，
   * **所有下载都会显示"失败"**（哪怕每一页都成功）。这个 bug 不报错、不崩，只是结果全错。
   */
  static resolveFinishStateFromCounts(total: number, finished: number): number {
    return DownloadStateMachine.resolveFinishState(total - finished);
  }

  static isTerminal(state: number): boolean {
    return state === DownloadInfo.STATE_FINISH || state === DownloadInfo.STATE_FAILED;
  }

  /**
   * 批量入队的取用下标：`downloadOrder = true` 按传入顺序，否则倒序
   * （上游 `for (i = n; i > 0; i--)` 的等价形态）。
   */
  static enqueueIndex(downloadOrder: boolean, size: number, cursor: number): number {
    return downloadOrder ? cursor : size - 1 - cursor;
  }

  /**
   * 批量"全部开始"时插入等待队列的方向：`downloadOrder = true` 用 push（队尾），
   * 否则 unshift（队首）—— 上游两分支的差异，影响"全部开始"的执行顺序。
   */
  static usePushForAll(downloadOrder: boolean): boolean {
    return downloadOrder;
  }
}
/**
 * 通知任务的**身份校验**（D-012 加固）。
 *
 * 上游的保证是"回调与状态变更都在主线程"，所以 `currentTask` 在处理时刻一定还是那条任务。
 * D-012 之后通知任务是异步执行的，队列里可能还压着**上一个任务**的进度，而 `currentTask`
 * 已经换成新任务（或已清空）。没有这道校验，把 A 的页数/完成事件写到 B 上**不会报错**，
 * 只会让 B 的进度与终态错乱 —— 属于最难查的一类。
 *
 * 判定规则：`任务快照 gid` 必须等于 `处理时刻的 gid`。
 * 注意 `-1` 与 `-1` 相等（都没有任务）不算同一任务，故两边都要 >= 0 才放行。
 */
export class NotifyIdentity {
  static shouldApply(taskGid: number, currentGid: number): boolean {
    if (taskGid < 0 || currentGid < 0) {
      return false;
    }
    return taskGid === currentGid;
  }
}

/**
 * `applyNotifyTask` 的**分派决策**（纯函数，覆盖"调用点是否真的用了校验"这个盲区）。
 *
 * 为什么要有这一层：`NotifyIdentity.shouldApply` 本身有断言，但"`applyNotifyTask` 有没有调用它"
 * 没人测 —— 这正是 `legacy` 那类 bug 的形状（**函数对、接缝错**）。
 * 把分派抽出来之后，"509 永远放行 / 其余按 gid 校验" 变成可断言的事实。
 */
export class NotifyDispatch {
  public static readonly APPLY: string = 'apply';
  public static readonly DROP: string = 'drop';

  static plan(type: number, taskGid: number, currentGid: number): string {
    // 509 是全局事件（不绑定具体任务）→ 永远放行
    // TYPE_ON_GET_509 = 1（NotifyTask 是文件内私有类，常量值在此复述并在断言里钉住一致性）
    if (type === 1) {
      return NotifyDispatch.APPLY;
    }
    return NotifyIdentity.shouldApply(taskGid, currentGid) ? NotifyDispatch.APPLY : NotifyDispatch.DROP;
  }
}

/**
 * 等待队列的**纯判定**（不碰存储、不碰网络）。
 *
 * 队列这块的 bug 表现是"下载卡住不动"或"跳着下"：
 *   - `isIdle()` 少判一项 → 服务提前 stopSelf，队列里还有任务却没人跑（看起来像卡死）；
 *   - 插入方向搞反 → "全部开始"顺序倒过来（用户看到的是"我从上往下选的，先下的是最后一条"）；
 *   - 取队首用 `pop()` 而不是 `shift()` → 变成后进先出，队列语义直接坏掉（不报错）。
 */
export class DownloadQueueRules {
  /**
   * 空闲判定（上游 `isIdle()` = `mCurrentTask == null && mWaitList.size() == 0`）。
   * **两项都要判**：只看 currentTask 会在"队列里还有任务"时误判空闲。
   */
  static isIdle(hasCurrentTask: boolean, waitListLength: number): boolean {
    return !hasCurrentTask && waitListLength === 0;
  }

  /**
   * 队列是否还能放任务（上游单并发：`ensureDownload()` 里 currentTask != null 直接返回）。
   * 返回 true 表示"可以立刻启动下一个"。
   */
  static canStartNext(hasCurrentTask: boolean, waitListLength: number): boolean {
    return !hasCurrentTask && waitListLength > 0;
  }

  /**
   * 批量入队时的插入位置（上游 `addDownloadList`：downloadOrder 决定 push / unshift）。
   * 返回 'push'（队尾）或 'unshift'（队首）。
   */
  static insertSide(downloadOrder: boolean): string {
    return downloadOrder ? 'push' : 'unshift';
  }

  /**
   * 单个任务重下的插入位置：上游 `startRangeDownload` 一律 `unshift`（插到最前面先下）。
   * 这一条与批量入队**不对称**，是真实的优先级语义。
   */
  static insertSideForRestart(): string {
    return 'unshift';
  }

  /** 取下一个任务的下标：FIFO 必须取 0（换成 length-1 就是 LIFO）。 */
  static nextIndex(waitListLength: number): number {
    return waitListLength > 0 ? 0 : -1;
  }
}
/**
 * 串行 FIFO 队列（D-012 的落点）。
 *
 * 为什么单独成类：整个 `DownloadManager` 的**所有写路径**都排在这条链上，
 * 它坏掉的形态有两种，都不会报错：
 *   1. **失败不释放** → 后续所有写操作永久挂起（下载再也启动不了，看日志像"死锁"）；
 *   2. **不是 FIFO** → "读-改-写"三段之间被别的转换插入，`currentTask`/`waitList` 半更新。
 * 抽出来后这两条都能在宿主上直接断言。
 *
 * 铁律（同 `DownloadManager` 文件头）：**body 内部禁止再 enqueue**。
 * 嵌套入队 = await 排在队尾的自己 = 自锁。本类不阻止它，但测试里有一条断言
 * 证明"嵌套确实会自锁"，防止有人以为可以那么写。
 */
export class SerialQueue {
  private lockTail: Promise<void> = Promise.resolve();

  public enqueue<T>(body: () => Promise<T>): Promise<T> {
    const result: Promise<T> = this.lockTail.then(body);
    this.lockTail = result.then((): void => {
      // 释放队列
    }, (): void => {
      // 失败也要释放，否则后续任务永久挂起
    });
    return result;
  }

  /** 队列排空时 resolve（测试与关闭流程用）。 */
  public drain(): Promise<void> {
    return this.lockTail;
  }
}

/**
 * 标签列表的**纯操作**（对位上游 `DownloadManager.moveLabel/renameLabel` 里的列表变更部分）。
 *
 * 为什么单独测：标签顺序是用户可见的（下载页左栏），而 `moveLabel` 的坑在于
 * **先删后插**的下标语义 —— 从前面删掉一条，后面的下标全部前移，此时用原来的 `toPosition`
 * 插入会**差一位**。上游 `EhDB.moveDownloadLabel(from, to)` 按时间字段轮转，两边必须同口径。
 * 写错了不报错，只是"拖到第 2 位却排到第 3 位"。
 */
export class LabelListOps {
  /**
   * 把 `from` 位置的元素移动到 `to` 位置（与 `splice(from,1)` + `splice(to,0,x)` 同语义）。
   *
   * 返回新数组（不改入参），并处理越界：
   *   - `from` 越界 → 原样返回（上游 `remove(from)` 返回 null 后直接 return）
   *   - `to` 越界 → 追加到末尾（`splice` 越界即追加，保持 JS 语义一致）
   */
  static move<T>(list: T[], from: number, to: number): T[] {
    const result: T[] = list.slice();
    if (from < 0 || from >= result.length) {
      return result;
    }
    const removed: T[] = result.splice(from, 1);
    if (removed.length === 0) {
      return result;
    }
    result.splice(to, 0, removed[0]);
    return result;
  }

  /**
   * 删除后插入的下标修正：`from < to` 时，删掉前面一项会让目标下标前移一位。
   *
   * 说明：**当前 `moveLabel` 不做这个修正**（与上游 Java `LinkedList` 的同款写法一致：
   * 上游也是先 `remove(from)` 再 `add(to, x)`，语义上"目标位置按删除后的列表计算"）。
   * 本函数留给需要"从原列表视角"计算下标的调用方，避免以后有人误用。
   */
  static adjustIndexAfterRemoval(from: number, to: number): number {
    return from < to ? to - 1 : to;
  }

  /** 重命名后需要同步的下标（上游 `renameLabel` 遍历 labelList 找同名字符串）。 */
  static indexOfLabel(labels: string[], name: string): number {
    for (let i = 0; i < labels.length; i++) {
      if (labels[i] === name) {
        return i;
      }
    }
    return -1;
  }
}
export class DownloadManager implements OnSpiderListener {
  /** 全部下载记录（上游 `LinkedList<DownloadInfo> mAllInfoList`，新记录 insert(0)）。 */
  private readonly allInfoList: DownloadInfo[] = [];
  /** gid → 记录（上游 `SparseJLArray<DownloadInfo> mAllInfoMap`）。 */
  private readonly allInfoMap: Map<number, DownloadInfo> = new Map<number, DownloadInfo>();
  /** 标签 → 该标签下的记录列表（不含默认标签）。 */
  private readonly labelMap: Map<string, DownloadInfo[]> = new Map<string, DownloadInfo[]>();
  /** 标签 → 条数（上游 `mLabelCountMap`，与 labelMap 分离维护）。 */
  private readonly labelCountMap: Map<string, number> = new Map<string, number>();
  /** 全部标签（不含默认标签）。 */
  private readonly labelList: DownloadLabel[] = [];
  /** 默认标签（label == null）下的记录。 */
  private readonly defaultInfoList: DownloadInfo[] = [];
  /** 等待启动队列（FIFO，队首先下）。 */
  private readonly waitList: DownloadInfo[] = [];

  private readonly speedReminder: SpeedReminder;

  /** 相册扫描器（默认 Noop + warn-once，见 MediaScanner.ets） */
  private mediaScanner: MediaScannerLike | null = new NoopMediaScanner();

  private downloadListener: DownloadListener | null = null;
  private readonly downloadInfoListeners: DownloadInfoListener[] = [];

  private currentTask: DownloadInfo | null = null;
  private currentSpider: SpiderQueen | null = null;

  /** NotifyTask 复用池（上游 ConcurrentPool(5)）。 */
  private readonly notifyTaskPool: NotifyTask[] = [];

  /**
   * 串行化队列：所有"会改内部结构"的入口都排进这里（FIFO），
   * 复刻上游"所有变更都在主线程 Handler 上串行执行"的隐式约束（竞态 R1）。
   */
  private readonly serialQueue: SerialQueue = new SerialQueue();

  private constructor() {
    this.speedReminder = new SpeedReminder(
      (): DownloadInfo | null => this.currentTask,
      (info: DownloadInfo): void => this.onSpeedReminderTick(info)
    );
  }

  /** 应用级单例（对位上游 `EhApplication.getDownloadManager()` 的持有者语义）。 */
  private static sInstance: DownloadManager | null = null;
  private static sInitPromise: Promise<DownloadManager> | null = null;

  /**
   * 异步工厂（D-b）：上游构造器同步读库，鸿蒙侧必须 await。
   *
   * 注意：这里是**纯创建**，不写单例；需要全局唯一的调用方请用 `getInstance()`。
   */
  public static async create(): Promise<DownloadManager> {
    const manager: DownloadManager = new DownloadManager();
    await manager.load();
    return manager;
  }

  /**
   * 应用级单例入口 —— 承担上游 `EhApplication.getDownloadManager(Context)` 的职责。
   *
   * 为什么放在这里而不是 EhApplication：core-runtime 的 `EhApplication.ets` 把
   * `getDownloadManager` 标为"待接线 → download"，即由本模块提供持有者；而且放这里能避免
   * `EhApplication → DownloadManager → EhDB` 的反向依赖噪音。
   * 并发安全：初始化用同一个 Promise，重复调用只读一次库。
   */
  public static async getInstance(): Promise<DownloadManager> {
    const cached: DownloadManager | null = DownloadManager.sInstance;
    if (cached !== null) {
      return cached;
    }
    if (DownloadManager.sInitPromise === null) {
      DownloadManager.sInitPromise = (async (): Promise<DownloadManager> => {
        const created: DownloadManager = await DownloadManager.create();
        DownloadManager.sInstance = created;
        return created;
      })();
    }
    const pending: Promise<DownloadManager> | null = DownloadManager.sInitPromise;
    if (pending === null) {
      return await DownloadManager.create();
    }
    return await pending;
  }

  /** 测试/重启用：丢弃单例（下次 getInstance 会重新读库）。 */
  public static resetInstance(): void {
    DownloadManager.sInstance = null;
    DownloadManager.sInitPromise = null;
  }

  /**
   * 对应上游构造器主体：读标签、读全部记录、按标签分桶、修补缺失标签、
   * 恢复 content:// 授权（鸿蒙侧只打日志，见 D-a）。
   */
  private async load(): Promise<void> {
    const labels: DownloadLabel[] = await EhDB.getAllDownloadLabelList();
    for (let i = 0; i < labels.length; i++) {
      this.labelList.push(labels[i]);
      // storage-db 的 DownloadLabel.getLabel() 返回 string | null（列 NOT NULL，正常不会为 null）。
      // 这里跳过 null 而不是塞空串当 key —— 空串会与「无标签」的 '' 语义混淆。
      const labelText: string | null = labels[i].getLabel();
      if (labelText === null) {
        hilog.warn(DOMAIN, TAG, 'skip DownloadLabel with null label');
        continue;
      }
      this.labelMap.set(labelText, []);
    }

    const allInfoList: DownloadInfo[] = await EhDB.getAllDownloadInfo();
    for (let i = 0; i < allInfoList.length; i++) {
      const info: DownloadInfo = allInfoList[i];

      if (info.archiveUri !== null && info.archiveUri.indexOf('content://') === 0) {
        // D-a：鸿蒙侧不接受 Android 的持久化 URI 授权语义，仅记录
        hilog.warn(DOMAIN, TAG, 'archiveUri is a content:// uri, permission is not replayed: %{public}s',
          info.archiveUri);
      }

      this.allInfoList.push(info);
      this.allInfoMap.set(info.gid, info);

      let list: DownloadInfo[] | null = this.getInfoListForLabel(info.label);
      if (list === null) {
        // 记录里的标签在标签表中不存在 → 补建（上游同样会写库）
        list = [];
        this.labelMap.set(info.label as string, list);
        if (!this.containLabel(info.label)) {
          this.labelList.push(await EhDB.addDownloadLabel(info.label as string));
        }
      }
      list.push(info);
    }

    // 条数统计与 labelMap 同步
    this.labelMap.forEach((value: DownloadInfo[], key: string): void => {
      this.labelCountMap.set(key, value.length);
    });
  }

  // ------------------------------------------------------------------ 基础查询

  public replaceInfo(newInfo: DownloadInfo, oldInfo: DownloadInfo): void {
    for (let i = 0; i < this.allInfoList.length; i++) {
      if (oldInfo.gid === this.allInfoList[i].gid) {
        this.allInfoList[i] = newInfo;
        break;
      }
    }
    const infoList: DownloadInfo[] | null = this.getInfoListForLabel(oldInfo.label);
    if (infoList !== null) {
      for (let i = 0; i < infoList.length; i++) {
        if (oldInfo.gid === infoList[i].gid) {
          infoList[i] = newInfo;
          break;
        }
      }
    }

    this.allInfoMap.delete(oldInfo.gid);
    this.allInfoMap.set(newInfo.gid, newInfo);

    for (let i = 0; i < this.downloadInfoListeners.length; i++) {
      this.downloadInfoListeners[i].onReplace(newInfo, oldInfo);
    }
  }

  private getInfoListForLabel(label: string | null): DownloadInfo[] | null {
    if (label === null) {
      return this.defaultInfoList;
    }
    const list: DownloadInfo[] | undefined = this.labelMap.get(label);
    return list === undefined ? null : list;
  }

  public containLabel(label: string | null): boolean {
    if (label === null) {
      return false;
    }
    for (let i = 0; i < this.labelList.length; i++) {
      if (label === this.labelList[i].getLabel()) {
        return true;
      }
    }
    return false;
  }

  public containDownloadInfo(gid: number): boolean {
    return this.allInfoMap.has(gid);
  }

  public getLabelList(): DownloadLabel[] {
    return this.labelList;
  }

  /**
   * 上游返回 `long` 且用 try/catch(NullPointerException) 兜底；
   * 这里 Map.get 返回 undefined，等价兜底为 0。
   */
  public getLabelCount(label: string | null): number {
    if (label === null) {
      return 0;
    }
    const count: number | undefined = this.labelCountMap.get(label);
    return count === undefined ? 0 : count;
  }

  public getAllDownloadInfoList(): DownloadInfo[] {
    return this.allInfoList;
  }

  public getDefaultDownloadInfoList(): DownloadInfo[] {
    return this.defaultInfoList;
  }

  public getLabelDownloadInfoList(label: string): DownloadInfo[] | null {
    const list: DownloadInfo[] | undefined = this.labelMap.get(label);
    return list === undefined ? null : list;
  }

  public getDownloadInfoList(): DownloadInfo[] {
    return this.allInfoList.slice();
  }

  public getDownloadInfo(gid: number): DownloadInfo | null {
    const info: DownloadInfo | undefined = this.allInfoMap.get(gid);
    return info === undefined ? null : info;
  }

  /**
   * 把某条记录从"当前任务/等待队列"里摘出来，但保留记录本身。
   * 返回摘出后的记录（上游行为：先停，再查表返回）。
   */
  public getNoneDownloadInfo(gid: number): Promise<DownloadInfo | null> {
    return this.serial(async (): Promise<DownloadInfo | null> => {
      const task: DownloadInfo | null = this.currentTask;
      if (task !== null && task.gid === gid) {
        await this.stopCurrentDownloadInternal();
      } else {
        // 倒序扫描（不含 currentTask），与上游 Iterator.remove 语义一致
        for (let i = this.waitList.length - 1; i >= 0; i--) {
          const info: DownloadInfo = this.waitList[i];
          if (info.gid === gid) {
            info.state = DownloadInfo.STATE_NONE;
            this.waitList.splice(i, 1);
            break;
          }
        }
      }
      return this.getDownloadInfo(gid);
    });
  }

  public getDownloadState(gid: number): number {
    const info: DownloadInfo | null = this.getDownloadInfo(gid);
    return info === null ? DownloadInfo.STATE_INVALID : info.state;
  }

  public addDownloadInfoListener(downloadInfoListener: DownloadInfoListener | null): void {
    if (downloadInfoListener === null) {
      return;
    }
    this.downloadInfoListeners.push(downloadInfoListener);
  }

  public removeDownloadInfoListener(downloadInfoListener: DownloadInfoListener | null): void {
    if (downloadInfoListener === null) {
      return;
    }
    const index: number = this.downloadInfoListeners.indexOf(downloadInfoListener);
    if (index >= 0) {
      this.downloadInfoListeners.splice(index, 1);
    }
  }

  public setDownloadListener(listener: DownloadListener | null): void {
    this.downloadListener = listener;
  }

  public isIdle(): boolean {
    return DownloadQueueRules.isIdle(this.currentTask !== null, this.waitList.length);
  }

  // ------------------------------------------------------------- 启动 / 停止

  /**
   * 启动下一条：上游 `ensureDownload()`。
   * 同一时刻只允许一个下载（`currentTask != null` 直接返回）。
   */
  private async ensureDownload(): Promise<void> {
    if (!DownloadQueueRules.canStartNext(this.currentTask !== null, this.waitList.length)) {
      return;
    }

    const info: DownloadInfo = this.waitList.shift() as DownloadInfo;
    const spider: SpiderQueen = await SpiderQueen.obtainSpiderQueen(info, MODE_DOWNLOAD);
    this.currentTask = info;
    this.currentSpider = spider;
    spider.addOnSpiderListener(this);
    info.state = DownloadInfo.STATE_DOWNLOAD;
    info.speed = -1;
    info.remaining = -1;
    info.total = -1;
    info.finished = 0;
    info.downloaded = 0;
    info.legacy = -1;
    await EhDB.putDownloadInfo(info);
    this.speedReminder.start();
    if (this.downloadListener !== null) {
      this.downloadListener.onStart(info);
    }
    const list: DownloadInfo[] | null = this.getInfoListForLabel(info.label);
    if (list !== null) {
      this.notifyUpdate(info, list);
    }
  }

  /**
   * 开始下载单条（上游 package-private `startDownload(GalleryInfo, String)`）。
   */
  public startDownload(galleryInfo: GalleryInfo, label: string | null): Promise<void> {
    return this.serial(async (): Promise<void> => {
      const task: DownloadInfo | null = this.currentTask;
      if (task !== null && task.gid === galleryInfo.gid) {
        return;
      }

      // 本地导入的归档/相册不参与常规下载
      if (galleryInfo instanceof DownloadInfo) {
        const downloadInfo: DownloadInfo = galleryInfo as DownloadInfo;
        if (downloadInfo.archiveUri !== null) {
          return;
        }
      }

      const exist: DownloadInfo | null = this.getDownloadInfo(galleryInfo.gid);
      if (exist !== null) {
        if (exist.archiveUri !== null) {
          return;
        }
        if (exist.state !== DownloadInfo.STATE_WAIT) {
          exist.state = DownloadInfo.STATE_WAIT;
          this.waitList.push(exist);
          await EhDB.putDownloadInfo(exist);
          const list: DownloadInfo[] | null = this.getInfoListForLabel(exist.label);
          if (list !== null) {
            this.notifyUpdate(exist, list);
          }
          await this.ensureDownload();
        }
        return;
      }

      // 新记录
      // storage-db 的 DownloadInfo 只保留 `(gid?)` 构造器 + `updateInfo(GalleryInfo)`，
      // 对位上游的两个构造器（`DownloadInfo()` 与 `DownloadInfo(GalleryInfo)`）
      const info: DownloadInfo = new DownloadInfo(galleryInfo.gid);
      info.updateInfo(galleryInfo);
      info.label = label;
      info.state = DownloadInfo.STATE_WAIT;
      info.time = Date.now();

      const list: DownloadInfo[] | null = this.getInfoListForLabel(info.label);
      if (list === null) {
        hilog.error(DOMAIN, TAG, 'startDownload: no list for label=%{public}s',
          label === null ? 'null' : label);
        return;
      }
      list.unshift(info);

      this.allInfoList.unshift(info);
      this.allInfoMap.set(galleryInfo.gid, info);
      this.waitList.push(info);

      await EhDB.putDownloadInfo(info);

      for (let i = 0; i < this.downloadInfoListeners.length; i++) {
        this.downloadInfoListeners[i].onAdd(info, list, list.length - 1);
      }
      await this.ensureDownload();

      await EhDB.putHistoryInfo(info);
    });
  }

  /**
   * 批量开始（上游 `startRangeDownload(LongList)`）。
   * `downloadOrder == true` 时按传入顺序入队，否则倒序入队（保证队首是传入的第一个）。
   */
  public startRangeDownload(gidList: number[]): Promise<void> {
    return this.serial(async (): Promise<void> => {
      let update: boolean = false;
      const downloadOrder: boolean = Settings.getDownloadOrder();
      const size: number = gidList.length;
      for (let k = 0; k < size; k++) {
        const gid: number = gidList[DownloadStateMachine.enqueueIndex(downloadOrder, size, k)];
        const info: DownloadInfo | null = this.getDownloadInfo(gid);
        if (info === null) {
          hilog.debug(DOMAIN, TAG, 'startRangeDownload: no info for gid=%{public}d', gid);
          continue;
        }
        if (info.archiveUri !== null) {
          continue;
        }
        if (DownloadStateMachine.isStartableForRange(info.state)) {
          update = true;
          info.state = DownloadInfo.STATE_WAIT;
          this.waitList.push(info);
          await EhDB.putDownloadInfo(info);
        }
      }
      if (update) {
        for (let i = 0; i < this.downloadInfoListeners.length; i++) {
          this.downloadInfoListeners[i].onUpdateAll();
        }
        await this.ensureDownload();
      }
    });
  }

  /**
   * 全部开始（上游 `startAllDownload()`）：只挑 NONE / FAILED。
   */
  public startAllDownload(): Promise<void> {
    return this.serial(async (): Promise<void> => {
      let update: boolean = false;
      const downloadOrder: boolean = Settings.getDownloadOrder();
      for (let i = 0; i < this.allInfoList.length; i++) {
        const info: DownloadInfo = this.allInfoList[i];
        if (DownloadStateMachine.isStartableForAll(info.state)) {
          update = true;
          info.state = DownloadInfo.STATE_WAIT;
          if (DownloadStateMachine.usePushForAll(downloadOrder)) {
            this.waitList.push(info);
          } else {
            this.waitList.unshift(info);
          }
          await EhDB.putDownloadInfo(info);
        }
      }
      if (update) {
        for (let i = 0; i < this.downloadInfoListeners.length; i++) {
          this.downloadInfoListeners[i].onUpdateAll();
        }
        await this.ensureDownload();
      }
    });
  }

  /**
   * 批量导入记录（上游 `addDownload(List<DownloadInfo>)`，用于"恢复下载"）。
   */
  public addDownloadList(downloadInfoList: DownloadInfo[]): Promise<void> {
    return this.serial(async (): Promise<void> => {
      for (let k = 0; k < downloadInfoList.length; k++) {
        const info: DownloadInfo = downloadInfoList[k];
        if (this.containDownloadInfo(info.gid)) {
          continue;
        }
        // 恢复出来的记录不允许停留在 WAIT/DOWNLOAD
        if (DownloadStateMachine.needsResetOnRestore(info.state)) {
          info.state = DownloadInfo.STATE_NONE;
        }

        let list: DownloadInfo[] | null = this.getInfoListForLabel(info.label);
        if (list === null) {
          list = [];
          this.labelMap.set(info.label as string, list);
          if (!this.containLabel(info.label)) {
            this.labelList.push(await EhDB.addDownloadLabel(info.label as string));
          }
        }
        list.push(info);
        list.sort(dateDescComparator);

        this.allInfoList.push(info);
        this.allInfoMap.set(info.gid, info);

        await EhDB.putDownloadInfo(info);
      }

      this.allInfoList.sort(dateDescComparator);

      for (let i = 0; i < this.downloadInfoListeners.length; i++) {
        this.downloadInfoListeners[i].onReload();
      }
    });
  }

  /**
   * 批量导入标签（上游 `addDownloadLabel(List<DownloadLabel>)`）。
   */
  public addDownloadLabel(downloadLabelList: DownloadLabel[]): Promise<void> {
    return this.serial(async (): Promise<void> => {
      for (let i = 0; i < downloadLabelList.length; i++) {
        const label: DownloadLabel = downloadLabelList[i];
        const labelString: string | null = label.getLabel();
        if (labelString === null) {
          continue;
        }
        if (!this.containLabel(labelString)) {
          this.labelMap.set(labelString, []);
          this.labelList.push(await EhDB.addDownloadLabel(label));
        }
      }
    });
  }

  /**
   * 新增一条记录并指定状态（上游重载 3：`addDownload(galleryInfo, label, state)`）。
   */
  public addDownload(galleryInfo: GalleryInfo, label: string | null, state: number): Promise<void> {
    return this.serial(async (): Promise<void> => {
      if (this.containDownloadInfo(galleryInfo.gid)) {
        return;
      }

      const info: DownloadInfo = new DownloadInfo(galleryInfo.gid);
      info.updateInfo(galleryInfo);
      info.label = label;
      info.state = state;
      info.time = Date.now();

      const list: DownloadInfo[] | null = this.getInfoListForLabel(info.label);
      if (list === null) {
        hilog.error(DOMAIN, TAG, 'addDownload: no list for label=%{public}s',
          label === null ? 'null' : label);
        return;
      }
      const labelKey: string = label === null ? '' : label;
      const oldCount: number | undefined = this.labelCountMap.get(labelKey);
      this.labelCountMap.set(labelKey, oldCount === undefined ? 1 : oldCount + 1);
      list.unshift(info);

      this.allInfoList.unshift(info);
      this.allInfoMap.set(galleryInfo.gid, info);

      await EhDB.putDownloadInfo(info);

      for (let i = 0; i < this.downloadInfoListeners.length; i++) {
        this.downloadInfoListeners[i].onAdd(info, list, list.length - 1);
      }
    });
  }

  /**
   * 新增一条 STATE_NONE 记录（上游重载 2：`addDownload(galleryInfo, label)`）。
   */
  public addDownloadWithStateNone(galleryInfo: GalleryInfo, label: string | null): Promise<void> {
    return this.addDownload(galleryInfo, label, DownloadInfo.STATE_NONE);
  }

  /**
   * 只建记录、不触发 onAdd（上游 `addDownloadInfo(galleryInfo, label)`）。
   * 与 `addDownload` 的差异保留：这里 `allInfoList` **不插入**，只进标签列表与 map。
   */
  public addDownloadInfo(galleryInfo: GalleryInfo, label: string | null): Promise<void> {
    return this.serial(async (): Promise<void> => {
      if (this.containDownloadInfo(galleryInfo.gid)) {
        return;
      }

      const info: DownloadInfo = new DownloadInfo(galleryInfo.gid);
      info.updateInfo(galleryInfo);
      info.label = label;
      info.state = DownloadInfo.STATE_NONE;
      if (info.time === 0) {
        info.time = Date.now();
      }

      const list: DownloadInfo[] | null = this.getInfoListForLabel(info.label);
      if (list === null) {
        hilog.error(DOMAIN, TAG, 'addDownloadInfo: no list for label=%{public}s',
          label === null ? 'null' : label);
        return;
      }
      list.unshift(info);

      await EhDB.putDownloadInfo(info);
      this.allInfoMap.set(galleryInfo.gid, info);
    });
  }

  public stopDownload(gid: number): Promise<void> {
    return this.serial(async (): Promise<void> => {
      const info: DownloadInfo | null = await this.stopDownloadInternal(gid);
      if (info !== null) {
        const list: DownloadInfo[] | null = this.getInfoListForLabel(info.label);
        if (list !== null) {
          this.notifyUpdate(info, list);
        }
        await this.ensureDownload();
      }
    });
  }

  public stopCurrentDownload(): Promise<void> {
    return this.serial(async (): Promise<void> => {
      const info: DownloadInfo | null = await this.stopCurrentDownloadInternal();
      if (info !== null) {
        const list: DownloadInfo[] | null = this.getInfoListForLabel(info.label);
        if (list !== null) {
          this.notifyUpdate(info, list);
        }
        await this.ensureDownload();
      }
    });
  }

  public stopRangeDownload(gidList: number[]): Promise<void> {
    return this.serial(async (): Promise<void> => {
      await this.stopRangeDownloadInternal(gidList);
      for (let i = 0; i < this.downloadInfoListeners.length; i++) {
        this.downloadInfoListeners[i].onUpdateAll();
      }
      await this.ensureDownload();
    });
  }

  public stopAllDownload(): Promise<void> {
    return this.serial(async (): Promise<void> => {
      for (let i = 0; i < this.waitList.length; i++) {
        const info: DownloadInfo = this.waitList[i];
        info.state = DownloadInfo.STATE_NONE;
        await EhDB.putDownloadInfo(info);
      }
      this.waitList.length = 0;

      await this.stopCurrentDownloadInternal();

      for (let i = 0; i < this.downloadInfoListeners.length; i++) {
        this.downloadInfoListeners[i].onUpdateAll();
      }
    });
  }

  public deleteDownload(gid: number): Promise<void> {
    return this.serial(async (): Promise<void> => {
      await this.stopDownloadInternal(gid);
      const info: DownloadInfo | null = this.getDownloadInfo(gid);
      if (info === null) {
        return;
      }

      await EhDB.removeDownloadInfo(info.gid);

      this.removeFromAllInfoList(info);
      this.allInfoMap.delete(info.gid);

      const list: DownloadInfo[] | null = this.getInfoListForLabel(info.label);
      if (list !== null) {
        const index: number = list.indexOf(info);
        if (index >= 0) {
          list.splice(index, 1);
          for (let i = 0; i < this.downloadInfoListeners.length; i++) {
            this.downloadInfoListeners[i].onRemove(info, list, index);
          }
        }
      }

      await this.ensureDownload();
    });
  }

  public deleteRangeDownload(gidList: number[]): Promise<void> {
    return this.serial(async (): Promise<void> => {
      await this.stopRangeDownloadInternal(gidList);

      for (let k = 0; k < gidList.length; k++) {
        const gid: number = gidList[k];
        const info: DownloadInfo | null = this.getDownloadInfo(gid);
        if (info === null) {
          hilog.debug(DOMAIN, TAG, 'deleteRangeDownload: no info for gid=%{public}d', gid);
          continue;
        }

        await EhDB.removeDownloadInfo(info.gid);

        this.removeFromAllInfoList(info);
        this.allInfoMap.delete(info.gid);

        const list: DownloadInfo[] | null = this.getInfoListForLabel(info.label);
        if (list !== null) {
          const index: number = list.indexOf(info);
          if (index >= 0) {
            list.splice(index, 1);
          }
        }
      }

      for (let i = 0; i < this.downloadInfoListeners.length; i++) {
        this.downloadInfoListeners[i].onReload();
      }

      await this.ensureDownload();
    });
  }

  /**
   * 把全部下载记录的阅读进度重置为 0（上游 `resetAllReadingProgress()`，重载 1）。
   */
  public resetAllReadingProgress(): Promise<void> {
    return this.resetAllReadingProgressWithCallback(null);
  }

  /**
   * 上游 `resetAllReadingProgress(@Nullable Runnable onComplete)`（重载 2）：
   *   1. 先让正在运行的读取端也归零（`SpiderQueen.resetReadingProgress`），同步部分；
   *   2. 再在后台线程逐个把 `.ehviewer` 的 `startPage` 写 0（`AsyncTask.doInBackground`）；
   *   3. 完成后回调 `onComplete`（`onPostExecute`）。
   */
  public resetAllReadingProgressWithCallback(onComplete: (() => void) | null): Promise<void> {
    return this.serial(async (): Promise<void> => {
      const list: DownloadInfo[] = this.allInfoList.slice();

      for (let i = 0; i < list.length; i++) {
        await SpiderQueen.resetReadingProgress(list[i].gid);
      }

      const galleryInfo: GalleryInfo = new GalleryInfo();
      for (let i = 0; i < list.length; i++) {
        const downloadInfo: DownloadInfo = list[i];
        galleryInfo.gid = downloadInfo.gid;
        galleryInfo.token = downloadInfo.token;
        galleryInfo.title = downloadInfo.title;
        galleryInfo.thumb = downloadInfo.thumb;
        galleryInfo.category = downloadInfo.category;
        galleryInfo.posted = downloadInfo.posted;
        galleryInfo.uploader = downloadInfo.uploader;
        galleryInfo.rating = downloadInfo.rating;

        const downloadDir: UniFile | null = await SpiderDen.getGalleryDownloadDir(galleryInfo);
        if (downloadDir === null) {
          continue;
        }
        const file: UniFile | null = downloadDir.findFile(DOWNLOAD_INFO_FILENAME);
        if (file === null) {
          continue;
        }
        // storage-db 的静态入口叫 readFile / readHeaderFile（同步返回），没有 read / readHeader
        const spiderInfo: SpiderInfo | null = SpiderInfo.readFile(file);
        if (spiderInfo === null) {
          continue;
        }
        spiderInfo.startPage = 0;
        // 上游写的是 `writeNewSpiderInfoToLocal(new SpiderDen(galleryInfo), mContext)`；
        // storage-db 的实现改为「直接吃下载目录 UniFile」，不再需要 Context
        spiderInfo.writeNewSpiderInfoToLocal(downloadDir);
      }

      if (onComplete !== null) {
        onComplete();
      }
    });
  }

  // -------------------------------------------------------- 内部停止/删除实现

  /**
   * 停单条：命中当前任务走 `stopCurrentDownloadInternal`，否则从等待队列摘掉。
   * 上游注释："Update in DB / Update listener / No ensureDownload"。
   */
  private async stopDownloadInternal(gid: number): Promise<DownloadInfo | null> {
    const task: DownloadInfo | null = this.currentTask;
    if (task !== null && task.gid === gid) {
      return await this.stopCurrentDownloadInternal();
    }

    for (let i = 0; i < this.waitList.length; i++) {
      const info: DownloadInfo = this.waitList[i];
      if (info.gid === gid) {
        this.waitList.splice(i, 1);
        info.state = DownloadInfo.STATE_NONE;
        await EhDB.putDownloadInfo(info);
        return info;
      }
    }
    return null;
  }

  /**
   * 停当前任务：先摘监听器并释放 spider，再置 NONE、写库、回调 onCancel。
   */
  private async stopCurrentDownloadInternal(): Promise<DownloadInfo | null> {
    const info: DownloadInfo | null = this.currentTask;
    const spider: SpiderQueen | null = this.currentSpider;

    if (spider !== null) {
      spider.removeOnSpiderListener(this);
      await SpiderQueen.releaseSpiderQueen(spider, MODE_DOWNLOAD);
    }
    this.currentTask = null;
    this.currentSpider = null;
    this.speedReminder.stop();

    if (info === null) {
      return null;
    }

    info.state = DownloadInfo.STATE_NONE;
    await EhDB.putDownloadInfo(info);
    if (this.downloadListener !== null) {
      this.downloadListener.onCancel(info);
    }
    return info;
  }

  /**
   * 批量停：上游按"两向"选择更省的分支（比 waitList 短就逐个停，否则整体扫）。
   * 这个分支选择逻辑保留（大列表下性能差异真实存在）。
   */
  private async stopRangeDownloadInternal(gidList: number[]): Promise<void> {
    if (gidList.length < this.waitList.length) {
      for (let k = 0; k < gidList.length; k++) {
        await this.stopDownloadInternal(gidList[k]);
      }
      return;
    }

    const task: DownloadInfo | null = this.currentTask;
    if (task !== null && gidList.indexOf(task.gid) >= 0) {
      await this.stopCurrentDownloadInternal();
    }

    for (let i = this.waitList.length - 1; i >= 0; i--) {
      const info: DownloadInfo = this.waitList[i];
      if (gidList.indexOf(info.gid) >= 0) {
        this.waitList.splice(i, 1);
        info.state = DownloadInfo.STATE_NONE;
        await EhDB.putDownloadInfo(info);
      }
    }
  }

  private removeFromAllInfoList(info: DownloadInfo): void {
    const index: number = this.allInfoList.indexOf(info);
    if (index >= 0) {
      this.allInfoList.splice(index, 1);
    }
  }

  // ------------------------------------------------------------------ 标签操作

  /**
   * 批量改标签（上游 `changeLabel(list, label)`）：不允许新标签。
   */
  public changeLabel(list: DownloadInfo[], label: string | null): Promise<void> {
    return this.serial(async (): Promise<void> => {
      if (label !== null && !this.containLabel(label)) {
        hilog.error(DOMAIN, TAG, 'changeLabel: label not exist: %{public}s', label);
        return;
      }
      const dstList: DownloadInfo[] | null = this.getInfoListForLabel(label);
      if (dstList === null) {
        hilog.error(DOMAIN, TAG, 'changeLabel: no list for label=%{public}s',
          label === null ? 'null' : label);
        return;
      }

      for (let k = 0; k < list.length; k++) {
        const info: DownloadInfo = list[k];
        if (ObjectUtils.equal(info.label, label)) {
          continue;
        }
        const srcList: DownloadInfo[] | null = this.getInfoListForLabel(info.label);
        if (srcList === null) {
          hilog.error(DOMAIN, TAG, 'changeLabel: no src list for label=%{public}s',
            info.label === null ? 'null' : info.label);
          continue;
        }

        const index: number = srcList.indexOf(info);
        if (index >= 0) {
          srcList.splice(index, 1);
        }
        dstList.push(info);
        info.label = label;
        dstList.sort(dateDescComparator);

        await EhDB.putDownloadInfo(info);
      }

      for (let i = 0; i < this.downloadInfoListeners.length; i++) {
        this.downloadInfoListeners[i].onReload();
      }
    });
  }

  public addLabel(label: string | null): Promise<void> {
    return this.serial(async (): Promise<void> => {
      if (label === null || this.containLabel(label)) {
        return;
      }
      this.labelList.push(await EhDB.addDownloadLabel(label));
      this.labelMap.set(label, []);

      for (let i = 0; i < this.downloadInfoListeners.length; i++) {
        this.downloadInfoListeners[i].onUpdateLabels();
      }
    });
  }

  /**
   * 静默加标签：不回调 onUpdateLabels（上游 `addLabelInSyncThread`，
   * 供已经在同步流程里的调用方使用，避免监听器重入）。
   */
  public addLabelInSyncThread(label: string | null): Promise<void> {
    return this.serial(async (): Promise<void> => {
      if (label === null || this.containLabel(label)) {
        return;
      }
      this.labelList.push(await EhDB.addDownloadLabel(label));
      this.labelMap.set(label, []);
    });
  }

  public moveLabel(fromPosition: number, toPosition: number): Promise<void> {
    return this.serial(async (): Promise<void> => {
      const removed: DownloadLabel[] = this.labelList.splice(fromPosition, 1);
      if (removed.length === 0) {
        return;
      }
      this.labelList.splice(toPosition, 0, removed[0]);
      await EhDB.moveDownloadLabel(fromPosition, toPosition);

      for (let i = 0; i < this.downloadInfoListeners.length; i++) {
        this.downloadInfoListeners[i].onUpdateLabels();
      }
    });
  }

  public renameLabel(from: string, to: string): Promise<void> {
    return this.serial(async (): Promise<void> => {
      let found: boolean = false;
      for (let i = 0; i < this.labelList.length; i++) {
        const raw: DownloadLabel = this.labelList[i];
        if (from === raw.getLabel()) {
          found = true;
          raw.setLabel(to);
          await EhDB.updateDownloadLabel(raw);
          break;
        }
      }
      if (!found) {
        return;
      }

      const list: DownloadInfo[] | undefined = this.labelMap.get(from);
      if (list === undefined) {
        return;
      }
      this.labelMap.delete(from);

      for (let i = 0; i < list.length; i++) {
        const info: DownloadInfo = list[i];
        info.label = to;
        await EhDB.putDownloadInfo(info);
      }
      this.labelMap.set(to, list);

      for (let i = 0; i < this.downloadInfoListeners.length; i++) {
        this.downloadInfoListeners[i].onRenameLabel(from, to);
      }
    });
  }

  public deleteLabel(label: string): Promise<void> {
    return this.serial(async (): Promise<void> => {
      let found: boolean = false;
      for (let i = 0; i < this.labelList.length; i++) {
        const raw: DownloadLabel = this.labelList[i];
        if (label === raw.getLabel()) {
          found = true;
          this.labelList.splice(i, 1);
          await EhDB.removeDownloadLabel(raw);
          break;
        }
      }
      if (!found) {
        return;
      }

      const list: DownloadInfo[] | undefined = this.labelMap.get(label);
      if (list === undefined) {
        return;
      }
      this.labelMap.delete(label);
      this.labelCountMap.delete(label);

      for (let i = 0; i < list.length; i++) {
        const info: DownloadInfo = list[i];
        info.label = null;
        await EhDB.putDownloadInfo(info);
        this.defaultInfoList.push(info);
      }
      this.defaultInfoList.sort(dateDescComparator);

      for (let i = 0; i < this.downloadInfoListeners.length; i++) {
        this.downloadInfoListeners[i].onChange();
      }
    });
  }

  // ------------------------------------------------------ OnSpiderListener 回调

  public onGetPages(pages: number): void {
    const task: NotifyTask = this.popNotifyTask();
    task.setOnGetPagesData(pages);
    task.gid = this.currentGid();
    this.enqueueNotifyTask(task);
  }

  public onGet509(index: number): void {
    const task: NotifyTask = this.popNotifyTask();
    task.setOnGet509Data(index);
    task.gid = this.currentGid();
    this.enqueueNotifyTask(task);
  }

  public onPageDownload(index: number, contentLength: number, receivedSize: number,
    bytesRead: number): void {
    const task: NotifyTask = this.popNotifyTask();
    task.setOnPageDownloadData(index, contentLength, receivedSize, bytesRead);
    task.gid = this.currentGid();
    this.enqueueNotifyTask(task);
  }

  public onPageSuccess(index: number, finished: number, downloaded: number, total: number): void {
    const task: NotifyTask = this.popNotifyTask();
    task.setOnPageSuccessData(index, finished, downloaded, total);
    task.gid = this.currentGid();
    this.enqueueNotifyTask(task);
  }

  public onPageFailure(index: number, error: string, finished: number, downloaded: number,
    total: number): void {
    const task: NotifyTask = this.popNotifyTask();
    task.setOnPageFailureData(index, error, finished, downloaded, total);
    task.gid = this.currentGid();
    this.enqueueNotifyTask(task);
  }

  public onFinish(finished: number, downloaded: number, total: number): void {
    const task: NotifyTask = this.popNotifyTask();
    task.setOnFinishData(finished, downloaded, total);
    task.gid = this.currentGid();
    this.enqueueNotifyTask(task);
  }

  /** 上游明确忽略图片回调（图片由 UI 的 Image 管线负责）。 */
  public onGetImageSuccess(index: number, image: Object): void {
    hilog.debug(DOMAIN, TAG, 'onGetImageSuccess ignored, index=%{public}d', index);
  }

  public onGetImageFailure(index: number, error: string): void {
    hilog.debug(DOMAIN, TAG, 'onGetImageFailure ignored, index=%{public}d, error=%{public}s', index, error);
  }

  private popNotifyTask(): NotifyTask {
    const task: NotifyTask | undefined = this.notifyTaskPool.pop();
    return task === undefined ? new NotifyTask() : task;
  }

  /** **回调时刻**的 gid（无当前任务时 -1）。 */
  private currentGid(): number {
    const info: DownloadInfo | null = this.currentTask;
    return info === null ? -1 : info.gid;
  }

  /**
   * 把 NotifyTask 投进串行队列（D-012 + 竞态 R1 的落地点）。
   *
   * 为什么必须串行：`TYPE_ON_FINISH` 里要"读 currentTask → 置 null → await 释放 spider →
   * await 写库 → await ensureDownload()"。D-012 之后每个 await 都是真实的异步边界，
   * 不串行的话 `stopDownload()`/`deleteDownload()` 可能插进来，读到"已置 null 但还没落库"
   * 的中间态 —— 上游靠"全在主线程 Handler 上"避免了这个洞，这里用 FIFO 队列重建同一约束。
   */
  private enqueueNotifyTask(task: NotifyTask): void {
    this.serial(async (): Promise<void> => {
      await this.applyNotifyTask(task);
    }).then((): void => {
      if (this.notifyTaskPool.length < NOTIFY_TASK_POOL_SIZE) {
        this.notifyTaskPool.push(task);
      }
    }).catch((e: Object) => {
      hilog.error(DOMAIN, TAG, 'notify task failed: %{public}s', this.errorToString(e));
    });
  }

  /**
   * 上游 `NotifyTask.run()`：全部状态写入都发生在"回到主线程之后"，
   * 因此这里读 `currentTask` 是**处理时刻的快照**（不是回调时刻）——
   * 这个顺序对 `TYPE_ON_FINISH` 尤其关键（见竞态 R3）。
   *
   * 调用约束：**只能**由 `enqueueNotifyTask` 在串行队列内部调用，不要直接在回调里 await，
   * 否则会绕过队列，回到 D-012 之前的交错风险。
   */
  private async applyNotifyTask(task: NotifyTask): Promise<void> {
    // D-012 身份校验：任务快照 gid ≠ 处理时刻 gid → 丢弃（否则把旧任务的进度写到新任务上）
    // 分派规则在 NotifyDispatch.plan（纯函数、有 18 格断言），这里只执行结论。
    if (NotifyDispatch.plan(task.type, task.gid, this.currentGid()) === NotifyDispatch.DROP) {
      hilog.warn(DOMAIN, TAG,
        'drop stale notify task: type=%{public}d taskGid=%{public}d currentGid=%{public}d',
        task.type, task.gid, this.currentGid());
      return;
    }
    switch (task.type) {
      case NotifyTask.TYPE_ON_GET_PAGES: {
        const info: DownloadInfo | null = this.currentTask;
        if (info === null) {
          hilog.error(DOMAIN, TAG, 'Current task is null, but it should not be');
        } else {
          info.total = task.pages;
          const list: DownloadInfo[] | null = this.getInfoListForLabel(info.label);
          if (list !== null) {
            this.notifyUpdate(info, list);
          }
        }
        break;
      }
      case NotifyTask.TYPE_ON_GET_509: {
        if (this.downloadListener !== null) {
          this.downloadListener.onGet509();
        }
        break;
      }
      case NotifyTask.TYPE_ON_PAGE_DOWNLOAD: {
        this.speedReminder.onDownload(task.index, task.contentLength, task.receivedSize, task.bytesRead);
        break;
      }
      case NotifyTask.TYPE_ON_PAGE_SUCCESS: {
        this.speedReminder.onDone(task.index);
        const info: DownloadInfo | null = this.currentTask;
        if (info === null) {
          hilog.error(DOMAIN, TAG, 'Current task is null, but it should not be');
        } else {
          info.finished = task.finished;
          info.downloaded = task.downloaded;
          info.total = task.total;
          if (this.downloadListener !== null) {
            this.downloadListener.onGetPage(info);
          }
          const list: DownloadInfo[] | null = this.getInfoListForLabel(info.label);
          if (list !== null) {
            this.notifyUpdate(info, list);
          }
        }
        break;
      }
      case NotifyTask.TYPE_ON_PAGE_FAILURE: {
        this.speedReminder.onDone(task.index);
        const info: DownloadInfo | null = this.currentTask;
        if (info === null) {
          hilog.error(DOMAIN, TAG, 'Current task is null, but it should not be');
        } else {
          info.finished = task.finished;
          info.downloaded = task.downloaded;
          info.total = task.total;
          const list: DownloadInfo[] | null = this.getInfoListForLabel(info.label);
          if (list !== null) {
            this.notifyUpdate(info, list);
          }
        }
        break;
      }
      case NotifyTask.TYPE_ON_FINISH: {
        this.speedReminder.onFinish();
        // 下载结束：先摘 currentTask，再释放 spider，最后 ensureDownload 启下一个（竞态 R3）
        const info: DownloadInfo | null = this.currentTask;
        this.currentTask = null;
        const spider: SpiderQueen | null = this.currentSpider;
        this.currentSpider = null;
        if (spider !== null) {
          spider.removeOnSpiderListener(this);
          await SpiderQueen.releaseSpiderQueen(spider, MODE_DOWNLOAD);
        }
        if (info === null || spider === null) {
          hilog.error(DOMAIN, TAG, 'Current stuff is null, but it should not be');
          break;
        }
        this.speedReminder.stop();
        info.finished = task.finished;
        info.downloaded = task.downloaded;
        info.total = task.total;
        // 上游 DownloadManager.java:1296：legacy = total - finished（漏这一步 = 所有下载都判失败）
        info.legacy = info.total - info.finished;
        info.state = DownloadStateMachine.resolveFinishStateFromCounts(info.total, info.finished);
        // 状态落库 + 回调 + 启动下一个（已在串行队列内，直接 await，不再嵌套 serial）
        await EhDB.putDownloadInfo(info);
        if (this.downloadListener !== null) {
          this.downloadListener.onFinish(info);
        }
        // 上游 `DownloadManager.java` 完成分支：`if (Settings.getMediaScan())` 才通知相册刷新。
        // **条件调用是本条的关键**（消费者驱动清单报的正是"getMediaScan 全仓 0 调用"）：
        // 用户关掉"图片保存后通知图库"就不该扫 —— 断言钉的也是这个条件，不是"方法存在"。
        // 扫描落地动作见 MediaScanner.ets（Noop + warn-once，等 UI 侧定路线）。
        this.scanFinished(info);
        const list: DownloadInfo[] | null = this.getInfoListForLabel(info.label);
        if (list !== null) {
          this.notifyUpdate(info, list);
        }
        await this.ensureDownload();
        break;
      }
      default:
        break;
    }

  }

  /**
   * 下载完成后的相册扫描（上游 `if (Settings.getMediaScan()) mediaScan(...)`）。
   *
   * 两件事分开：
   *   ① **是否扫** = `Settings.getMediaScan()`（用户设置，条件调用）；
   *   ② **怎么扫** = 注入的 `MediaScannerLike`（默认 Noop，warn-once）。
   *
   * 只在**成功完成**时调用（本方法只被 STATE_FINISH 分支调），失败/取消不扫 ——
   * 上游同样只在完成回调里做。
   */
  private scanFinished(info: DownloadInfo): void {
    if (!Settings.getMediaScan()) {
      return;
    }
    if (this.mediaScanner === null) {
      return;
    }
    // 扫描目标 = 该画廊的下载目录（上游扫的是目录下的每个文件；目录级扫描器自己展开）。
    // ⚠️ 这里**没有**去猜路径：路径解析需要 `SpiderDen.getGalleryDownloadDir(galleryInfo)`，
    // 而 `onFinish` 分支只有 `DownloadInfo`（没有 `GalleryInfo`）。故用 dirname 映射键交给扫描器解析，
    // 解析不出来时扫描器自己 warn —— 不在本层拼一个可能错的字符串。
    this.mediaScanner.scanGallery(info.gid);
  }

  /** 注入扫描器（生产实现见 MediaScanner.ets；测试可注入计数桩）。 */
  public setMediaScanner(scanner: MediaScannerLike | null): void {
    this.mediaScanner = scanner;
  }

  private notifyUpdate(info: DownloadInfo, list: DownloadInfo[]): void {
    for (let i = 0; i < this.downloadInfoListeners.length; i++) {
      this.downloadInfoListeners[i].onUpdate(info, list, this.waitList);
    }
  }

  // ------------------------------------------------------------------ 速度统计

  /**
   * SpeedReminder 每 2s 一次的落地回调（上游 `SpeedReminder.run()` 里
   * 对 mDownloadListener / mDownloadInfoListeners 的通知部分）。
   */
  private onSpeedReminderTick(info: DownloadInfo): void {
    if (this.downloadListener !== null) {
      this.downloadListener.onDownload(info);
    }
    const list: DownloadInfo[] | null = this.getInfoListForLabel(info.label);
    if (list !== null) {
      this.notifyUpdate(info, list);
    }
  }

  // ---------------------------------------------------------------- 串行化队列

  /**
   * 把所有写操作排成 FIFO 队列。返回本次任务的 Promise（调用方可 await 或不 await，
   * 顺序保证由队列本身承担 —— 上游靠"都在主线程上"实现同一保证）。
   */
  private serial<T>(body: () => Promise<T>): Promise<T> {
    return this.serialQueue.enqueue(body);
  }

  private errorToString(e: Object): string {
    if (e instanceof Error) {
      return e.message;
    }
    return String(e);
  }
}

/**
 * 上游 `class DownloadManager.SpeedReminder implements Runnable`。
 *
 * 每 2s 触发一次：算速度（`bytesRead / 2`，再与上一次 `lerp(oldSpeed, new, 0.75)` 平滑），
 * 再按"正在下载的页"的 contentLength/receivedSize 估剩余时间。
 * 逐行等价，唯一差异：`SimpleHandler.postDelayed` → `setTimeout`。
 */
/**
 * 速度/剩余时间的**纯计算**（对位上游 `SpeedReminder.run()`）。
 *
 * 为什么必须单独测：这两条公式直接决定用户看到的"速度"和"剩余时间"，
 * 而它们只在真机下载时才会跑到；写错了既不报错也不崩，只是**数字看着不对**（没人写断言。
 * 真机验收也看不出 1.3 倍偏差）。
 *
 * 三条关键语义：
 *   1. 速度做**指数平滑**：首次直接用 `bytesRead / 2`，之后 `lerp(old, new, 0.75)`
 *      （`lerp` 的 t=0.75 表示"更靠近新值"，写成 0.25 会让速度变化迟钝）；
 *   2. `total <= 0`（长度未知）→ 剩余时间 **-1**（UI 显示"--"）；
 *   3. 速度为 0 → 剩余时间用占位值（不是无穷大，也不是 -1）。
 */
export class SpeedMath {
  /** 一秒两次采样：`newSpeed = bytesRead / 2`，并与上一次结果做 0.75 平滑。 */
  static nextSpeed(oldSpeed: number, bytesRead: number): number {
    const raw: number = bytesRead / 2;
    if (oldSpeed === -1) {
      return raw;
    }
    return MathUtils.lerp(oldSpeed, raw, 0.75);
  }

  /**
   * 剩余时间估算（毫秒）。
   *
   * 正在下载的 n 页只知道已收到的字节，剩余页数按**当前 n 页的平均大小**外推：
   *   totalSize += (Σ contentLength) * (total - downloaded - n) / n
   * 这是上游的估算口径，去掉这一项会让剩余时间系统性偏小。
   */
  static remaining(total: number, downloaded: number, speed: number, contentLengths: number[],
    receivedSizes: number[], placeholder: number): number {
    if (total <= 0) {
      return -1;
    }
    if (speed === 0) {
      return placeholder;
    }
    const n: number = Math.max(contentLengths.length, receivedSizes.length);
    if (n === 0) {
      return -1;
    }
    let downloadingContentLengthSum: number = 0;
    let totalSize: number = 0;
    for (let i = 0; i < n; i++) {
      const contentLength: number = i < contentLengths.length ? contentLengths[i] : 0;
      const receivedSize: number = i < receivedSizes.length ? receivedSizes[i] : 0;
      downloadingContentLengthSum += contentLength;
      totalSize += contentLength - receivedSize;
    }
    totalSize += downloadingContentLengthSum * (total - downloaded - n) / n;
    return totalSize / speed * 1000;
  }
}
class SpeedReminder {
  private readonly getCurrentTask: () => DownloadInfo | null;
  private readonly onTick: (info: DownloadInfo) => void;

  private stopped: boolean = true;
  private bytesRead: number = 0;
  private oldSpeed: number = -1;
  private timerId: number = -1;

  /** 页 index → contentLength / receivedSize（上游 SparseIJArray）。 */
  private readonly contentLengthMap: Map<number, number> = new Map<number, number>();
  private readonly receivedSizeMap: Map<number, number> = new Map<number, number>();

  constructor(getCurrentTask: () => DownloadInfo | null, onTick: (info: DownloadInfo) => void) {
    this.getCurrentTask = getCurrentTask;
    this.onTick = onTick;
  }

  public start(): void {
    if (this.stopped) {
      this.stopped = false;
      this.schedule();
    }
  }

  public stop(): void {
    if (!this.stopped) {
      this.stopped = true;
      this.bytesRead = 0;
      this.oldSpeed = -1;
      this.contentLengthMap.clear();
      this.receivedSizeMap.clear();
      if (this.timerId !== -1) {
        clearTimeout(this.timerId);
        this.timerId = -1;
      }
    }
  }

  public onDownload(index: number, contentLength: number, receivedSize: number, bytesRead: number): void {
    this.contentLengthMap.set(index, contentLength);
    this.receivedSizeMap.set(index, receivedSize);
    this.bytesRead += bytesRead;
  }

  public onDone(index: number): void {
    this.contentLengthMap.delete(index);
    this.receivedSizeMap.delete(index);
  }

  public onFinish(): void {
    this.contentLengthMap.clear();
    this.receivedSizeMap.clear();
  }

  /**
   * 对应上游 `run()`。
   */
  public tick(): void {
    const info: DownloadInfo | null = this.getCurrentTask();
    if (info !== null) {
      // 速度平滑 + 剩余时间估算全部走纯函数（有单测）
      const newSpeed: number = SpeedMath.nextSpeed(this.oldSpeed, this.bytesRead);
      this.oldSpeed = newSpeed;
      info.speed = newSpeed;
      info.remaining = SpeedMath.remaining(info.total, info.downloaded, newSpeed,
        this.valuesOf(this.contentLengthMap), this.valuesOf(this.receivedSizeMap), REMAINING_PLACEHOLDER_MS);
      this.onTick(info);
    }

    this.bytesRead = 0;

    if (!this.stopped) {
      this.schedule();
    }
  }

  /** 按插入顺序取出所有值（对应上游 SparseIJArray 的长度 + valueAt 组合）。 */
  private valuesOf(map: Map<number, number>): number[] {
    const result: number[] = [];
    map.forEach((value: number): void => {
      result.push(value);
    });
    return result;
  }

  /** `SparseIJArray.valueAt(i)` 的等价：按插入顺序取第 i 个值，缺失按 0。 */
  private valueAt(map: Map<number, number>, index: number): number {
    let i: number = 0;
    let result: number = 0;
    map.forEach((value: number): void => {
      if (i === index) {
        result = value;
      }
      i++;
    });
    return result;
  }

  private schedule(): void {
    if (this.timerId !== -1) {
      clearTimeout(this.timerId);
    }
    this.timerId = setTimeout((): void => {
      this.timerId = -1;
      this.tick();
    }, SPEED_REFRESH_INTERVAL_MS);
  }
}
