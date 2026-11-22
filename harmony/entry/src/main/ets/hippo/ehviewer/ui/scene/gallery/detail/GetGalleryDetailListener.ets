/*
 * 上游：app/src/main/java/com/hippo/ehviewer/ui/scene/gallery/detail/GetGalleryDetailListener.kt
 *       （inventory S0234，66 行）
 * 目标：harmony/entry/src/main/ets/hippo/ehviewer/ui/scene/gallery/detail/GetGalleryDetailListener.ets
 *
 * 背景：**拉取画廊详情**的异步回调。上游继承 `EhCallback<GalleryDetailScene?, GalleryDetail?>`，
 * 在请求结束时做五件有副作用的事（缓存/历史/标签同步/通知场景/清理全局登记）。
 *
 * ── 上游行为逐条对照 ────────────────────────────────────────────────────────
 * `class GetGalleryDetailListener(context, stageId, sceneTag, private val resultMode: Int)`
 *   : `EhCallback<GalleryDetailScene?, GalleryDetail?>(context, stageId, sceneTag)`
 *
 *   `onSuccess(result: GalleryDetail?)`:
 *     ① `application.removeGlobalStuff(this)`            —— **第一步就清理注册**（无论结果）
 *     ② `if (result == null) return`                      —— null 直接返回（此时**已**清理）
 *     ③ `EhApplication.getGalleryDetailCache(application).put(result.gid, result)`   —— 写缓存
 *     ④ `EhDB.putHistoryInfo(result)`                     —— 加历史
 *     ⑤ `GalleryDetailTagsSyncTask(result).start()`        —— 起标签同步任务
 *     ⑥ `scene?.onGetGalleryDetailSuccess(result)`        —— 通知场景（scene 可空）
 *
 *   `onFailure(e: Exception)`:
 *     ① `application.removeGlobalStuff(this)`
 *     ② `scene` 非空时：
 *          `resultMode == RESULT_DETAIL` → `scene.onGetGalleryDetailFailure(e)` 然后 return
 *          否则                          → `scene.onGetGalleryDetailUpdateFailure(e)`
 *        （**scene 为空就什么都不做**）
 *
 *   `onCancel()`: `application.removeGlobalStuff(this)`（仅此）
 *
 *   `isInstance(scene: SceneFragment?)`: `scene != null && scene is GalleryDetailScene`
 *
 *   `newPath(result: GalleryDetail)`: `FileUtils.sanitizeFilename(result.gid + "-" + EhUtils.getSuitableTitle(result))`
 *
 *   `companion object { RESULT_DETAIL = 1; RESULT_UPDATE = 0 }`
 *
 * ── 关键行为（照搬，别"顺手修"）──────────────────────────────────────────────
 * 1. **`removeGlobalStuff(this)` 是三条回调的**第一句** —— 包括 cancel。它保证监听器不会滞留。
 *    漏掉会导致内存里累积未释放的监听器（上游用 WeakReference 池管理）。
 * 2. **`onSuccess` 里 `result == null` 的 return 在清理**之后** → null 结果不会提前返回而不清理。
 * 3. **`onFailure` 的分支不对称**：`RESULT_DETAIL` 走 `onGetGalleryDetailFailure` 并 **return**；
 *    其余走 `onGetGalleryDetailUpdateFailure`（**没有 return**，因为后面也没代码）。
 *    两条路径都以 `removeGlobalStuff` 开头。
 * 4. **`scene` 为空时 `onFailure` 什么都不做**（上游 `scene ?.let { ... }`）。
 * 5. `RESULT_DETAIL = 1` / `RESULT_UPDATE = 0` —— **注意 DETAIL 是 1、UPDATE 是 0**（反直觉，容易写反）。
 * 6. `newPath` 的结果**没有被本类使用**（上游这个方法在本类内未调用，留给外部/未来用）——
 *    但它是唯一**纯函数**，所以本实现把它落下来并断言（见测试）。
 *
 * ── 平台差异（依赖倒置，按 Lead 批准的方案 B）────────────────────────────────
 * 1. **`EhCallback` 尚未落地**（gl-render S0231）。本文件声明它实际用到的四个协作能力为
 *    `GalleryDetailCallbackHost`：`removeGlobalStuff` / `putGalleryDetailCache` / `putHistoryInfo` /
 *    `startTagsSync`。`EhCallback` 落地后 `implements GalleryDetailCallbackHost` 即接入。
 *    —— 与 `GalleryUpdateDialog` 的 `GalleryDetailSceneHost`、`SplashActivity` 的 `NewsFetcher` 同一做法。
 * 2. **场景通知**（`scene?.onGetGalleryDetailSuccess(...)`）→ `GalleryDetailSceneCallbacks` 接口
 *    （三个方法），`GalleryDetailScene` 落地后 `implements` 即接入；`scene == null` 用 `null` 表达。
 * 3. **`isInstance(scene)`** 上游判 `instanceof GalleryDetailScene`；本仓库 Scene 层用 **tag 字符串**
 *    （`SceneTypes` 的 `SceneTransitionHelper` 同样只给 tag）→ 改为 `isInstance(sceneTag)` 与构造参数比。
 * 4. **`newPath` 的 null 语义**：上游 Java `String + (可能为 null 的 String)` 会拼出 `"null"` 字面量；
 *    本仓库 `EhUtils.getSuitableTitle` 返回 `string | null`。这里用 `?? ''`（空串），
 *    因为 `title`/`titleJpn` 在上游是**非空字段**，"null" 分支实际不可达；若真为 null，
 *    文件名里出现 "null" 比空串更糟。此差异已在断言里钉住（`gid + '-'`）。
 *
 * ── 关联 ────────────────────────────────────────────────────────────────────
 * - 数据：`GalleryDetail`（`gid` / `title` / `titleJpn`）
 * - 纯函数依赖（均已存在，实测）：`hippo/lib/yorozuya/FileUtils.ets` 的 `sanitizeFilename`、
 *   `hippo/ehviewer/client/EhUtils.ets` 的 `getSuitableTitle`
 * - 副作用目标（均已存在）：`EhDB.putHistoryInfo`、`EhApplication.getGalleryDetailCache`、
 *   `GalleryDetailTagsSyncTask(detail).start()`
 */

import { hilog } from '@kit.PerformanceAnalysisKit';
import { GalleryDetail } from '../../../../client/data/GalleryDetail';
import { EhUtils } from '../../../../client/EhUtils';
import { FileUtils } from '../../../../../lib/yorozuya/FileUtils';

/** 上游 `companion object`：**DETAIL = 1、UPDATE = 0**（见「关键行为」5） */
export const RESULT_DETAIL: number = 1;
export const RESULT_UPDATE: number = 0;

/**
 * 本监听器对 `EhCallback` 基类的最小依赖（依赖倒置，见「平台差异」1）。
 * `EhCallback` 落地后 `implements GalleryDetailCallbackHost` 即可接入。
 */
export interface GalleryDetailCallbackHost {
  /** 上游 `application.removeGlobalStuff(this)` —— 三条回调的**第一句** */
  removeGlobalStuff(listener: Object): void;
  /** 上游 `EhApplication.getGalleryDetailCache(application).put(gid, detail)` */
  putGalleryDetailCache(gid: number, detail: GalleryDetail): void;
  /** 上游 `EhDB.putHistoryInfo(detail)`（本仓库是 async，返回 Promise） */
  putHistoryInfo(detail: GalleryDetail): Promise<void>;
  /** 上游 `GalleryDetailTagsSyncTask(detail).start()` */
  startTagsSync(detail: GalleryDetail): void;
}

/** 上游 `scene?.onGetGalleryDetailSuccess/Failure/UpdateFailure` 三个通知口 */
export interface GalleryDetailSceneCallbacks {
  onGetGalleryDetailSuccess(result: GalleryDetail): void;
  onGetGalleryDetailFailure(error: Error): void;
  onGetGalleryDetailUpdateFailure(error: Error): void;
}

export class GetGalleryDetailListener {
  /** 上游 `private val resultMode: Int` */
  private resultMode: number;
  /** 上游 `EhCallback` 持有的 sceneTag（用于 `isInstance` 判定，见「平台差异」3） */
  private sceneTag: string;
  /** 场景 tag 的目标值（`instanceof GalleryDetailScene` 的等价判据） */
  private detailSceneTag: string;

  constructor(resultMode: number, sceneTag: string, detailSceneTag: string = 'GalleryDetailScene') {
    this.resultMode = resultMode;
    this.sceneTag = sceneTag;
    this.detailSceneTag = detailSceneTag;
  }

  /**
   * 上游 `onSuccess(result)`：
   * ① 清理全局登记 → ② null 返回 → ③ 写缓存 → ④ 加历史 → ⑤ 起标签同步 → ⑥ 通知场景
   *
   * 注意 ⑤/⑥ 有副作用：`putHistoryInfo` 是 async，本方法**不 await**（上游也是调完即走，
   * 用 `EhDB` 的异步写入）。
   */
  onSuccess(result: GalleryDetail | null, host: GalleryDetailCallbackHost,
    scene: GalleryDetailSceneCallbacks | null): void {
    // ① 上游第一句：application.removeGlobalStuff(this) —— **无论结果如何都先清理**
    host.removeGlobalStuff(this);
    // ② null 直接返回（此时已清理）
    if (result === null) {
      return;
    }
    // ③ Put gallery detail to cache
    host.putGalleryDetailCache(result.gid, result);
    // ④ Add history（异步，不阻塞）
    const historyPromise: Promise<void> = host.putHistoryInfo(result);
    // 显式忽略 rejection：上游同样是"调完即走"，且 EhDB 内部已 catch。
    // 但上游 Java 会 `printStackTrace()` —— **吞掉的是传播，不是痕迹**。
    // silent-failures 闸门抓的就是"catch 里什么都没有"（A2 多行空 catch）。
    historyPromise.catch((_e: Error): void => {
      hilog.debug(0x0000, 'GetGalleryDetailListener',
        'putHistoryInfo failed (upstream also swallows+prints): %{public}s', _e.message);
    });
    // ⑤ Save tags
    host.startTagsSync(result);
    // ⑥ Notify success（scene 可空）
    if (scene !== null) {
      scene.onGetGalleryDetailSuccess(result);
    }
  }

  /**
   * 上游 `onFailure(e)`：
   * ① 清理 → ② scene 非空时按 resultMode 分流（DETAIL 分支 **return**，其余不 return）
   */
  onFailure(error: Error, host: GalleryDetailCallbackHost,
    scene: GalleryDetailSceneCallbacks | null): void {
    // ① 清理
    host.removeGlobalStuff(this);
    // ② scene 为空 → 什么都不做（上游 scene?.let）
    if (scene === null) {
      return;
    }
    if (this.resultMode === RESULT_DETAIL) {
      scene.onGetGalleryDetailFailure(error);
      return;   // 上游这里 return
    }
    scene.onGetGalleryDetailUpdateFailure(error);
  }

  /** 上游 `onCancel()`：**仅**清理全局登记 */
  onCancel(host: GalleryDetailCallbackHost): void {
    host.removeGlobalStuff(this);
  }

  /** 上游 `isInstance(scene)`：`scene != null && scene is GalleryDetailScene` → 改为 tag 比较（见「平台差异」3） */
  isInstance(sceneTag: string | null): boolean {
    if (sceneTag === null) {
      return false;
    }
    return sceneTag === this.detailSceneTag;
  }

  /**
   * 上游 `newPath(result)`：`sanitizeFilename(gid + "-" + getSuitableTitle(result))`。
   * **纯函数**，可断言（见「关键行为」6）。
   */
  newPath(result: GalleryDetail): string {
    const title: string | null = EhUtils.getSuitableTitle(result);
    // 见「平台差异」4：上游平台类型遇 null 会拼出 "null" 字面量；这里用空串（不可达分支，且更合理）
    const suffix: string = title === null ? '' : title;
    return FileUtils.sanitizeFilename(result.gid.toString() + '-' + suffix);
  }

  /** 本监听器的 sceneTag（测试观测用） */
  getSceneTag(): string {
    return this.sceneTag;
  }
}
