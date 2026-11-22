/*
 * 上游：app/src/main/java/com/hippo/ehviewer/ui/scene/download/part/DownloadBatchActions.kt
 *       （inventory S0224，上游实际 362 行；清单登记 321 行）
 * 目标：harmony/entry/src/main/ets/hippo/ehviewer/ui/scene/download/part/DownloadBatchActions.ets
 *
 * 背景：下载页的**批量操作中心**（FAB 二级按钮 + 三个对话框）。上游把它单独抽成一个类，
 * 通过 `Host` 接口反向依赖下载页 —— 这个设计正好与我们的"宿主接口化"做法同构，**照搬即可**。
 *
 * ── 上游行为逐条对照（`onClickSecondaryFab(view, fab, position)`）──────────
 * 前置：`context/activity/recyclerView` 任一为 null → **直接 return**
 * `position == 0` → `recyclerView.checkAll()`（全选），**之后不走收集逻辑**
 * 其它 position → 先收集：
 *   · `collectGid = position ∈ {1 Start, 2 Stop, 3 Delete}`
 *   · `collectDownloadInfo = position ∈ {3 Delete, 4 Move}`
 *   · 遍历 `getCheckedItemPositions()`，**只取 value == true 的项**；
 *     每项经 `mHost.positionInList(keyAt(i))` **换算成列表下标**（视图位置 ≠ 列表下标，见「关键行为」1）
 *   分支：
 *   · `1 Start`：`gidList.isEmpty → return`；`startService(DownloadService ACTION_START_RANGE, KEY_GID_LIST)` → `outOfCustomChoiceMode()`
 *   · `2 Stop`：`gidList.isEmpty → return`；`downloadManager.stopRangeDownload(gidList)` → `outOfCustomChoiceMode()`
 *   · `3 Delete`：`downloadInfoList.isEmpty → return`；
 *       弹 `CheckBoxDialogBuilder(message=@string/download_remove_dialog_message_2 **带数量**,
 *       checkText=@string/download_remove_dialog_check_text, checked=Settings.getRemoveImageFiles())`
 *       + title `@string/download_remove_dialog_title` → `DeleteRangeDialogHelper`（**此处不退出选择模式**，在 helper 里退）
 *   · `4 Move`：`downloadInfoList.isEmpty → return`；
 *       标签数组 = **[`@string/default_download_label_name`] + 所有 `getLabelList()` 的 label**
 *       （**默认标签在**第 0 位**，选中即"移出标签"**）→ `@string/download_move_dialog_title` + `setItems` → `MoveDialogHelper`
 *   · `5`：`list == null || list.isEmpty → return`；`onClickPrimaryFab(fabLayout, null)` + `viewRandom()`
 *   · `6`：`setDragEnable(fab)`
 *
 * `setDragEnable(fab)`：**翻转** `DownloadAdapter.DRAG_ENABLE` → `Settings.setDragDownloadGallery(新值)`
 *   → 按新值换图标：`true → v_mobile_hand_left_x24`、`false → v_mobile_hand_left_off_x24`
 *
 * `viewRandom()`：`list == null → return`；`position = (Math.random() * list.size).toInt()`；
 *   **`position < 0 || position >= list.size → return`**（防御 `random()` 返回 1.0 的边界）；
 *   `activity/recyclerView` 任一 null → return；起 `GalleryActivity(ACTION_EH, KEY_GALLERY_INFO=list[position])`
 *
 * `DeleteDialogHelper`（**单条删除，当前下载页未使用，保留**）：
 *   ① `which != BUTTON_POSITIVE → return`
 *   ② `deleteDownload(gid)`
 *   ③ `Settings.putRemoveImageFiles(builder.isChecked)`；`checked` 时：
 *      `file = SpiderDen.getExistingGalleryDownloadDir(gi)` → `EhDB.removeDownloadDirname(gid)`
 *      → `file != null ? deleteFileAsync(file) : deleteGalleryFilesAsync([gi])`
 *
 * `DeleteRangeDialogHelper`：
 *   ① `which != BUTTON_POSITIVE → return`
 *   ② **先 `outOfCustomChoiceMode()`**（见「关键行为」2）→ `deleteRangeDownload(gidList)`
 *   ③ `Settings.putRemoveImageFiles(checked)`；`checked` → `deleteGalleryFilesAsync(downloadInfoList)`
 *
 * `MoveDialogHelper`：
 *   ① **取消选择模式在最前面**（`context == null` 就直接 return，**连选择模式都不退**）
 *   ② `which == 0` → label = **null**（= 移出标签）；否则 `label = labels[which]`
 *   ③ `downloadManager.changeLabel(downloadInfoList, label)`
 *
 * `DeleteFileTask` / `DeleteGalleryFilesTask`：后台删除；后者对每个 info
 *   取 `SpiderDen.getGalleryDownloadDir(info)` → `EhDB.removeDownloadDirname(gid)` → `file.delete()`
 *
 * ── 关键行为（照搬，别"顺手修"）──────────────────────────────────────────────
 * 1. **`mHost.positionInList(keyAt(i))` 换算下标** —— `getCheckedItemPositions()` 的 key 是**视图位置**
 *    （可能有 header / 已过滤项），必须换成列表下标再用，否则**删错条目**。
 * 2. **Delete 分支不立刻退出选择模式**（在 `DeleteRangeDialogHelper` 里退）；而 Start/Stop **立刻退**。
 *    差异原因是 Delete 要弹对话框、用户可能取消。
 * 3. **`MoveDialogHelper` 里"取消选择模式"在 `context == null` 判断之后** ——
 *    context 为 null 时连选择模式都不退（上游如此）。
 * 4. **Move 的标签数组第 0 位是"默认标签"文案**，选中它 → `label = null`（移出标签）。
 * 5. **`viewRandom()` 的 `position >= list.size` 防御**（`Math.random()` 理论上 < 1，但浮点乘法后 `toInt()` 仍需防）。
 * 6. **`setDragEnable` 先翻转再持久化**，且图标按**翻转后**的值选。
 * 7. **删除图片文件是"用户勾选"决定**：`Settings.putRemoveImageFiles(checked)` **无条件写回**
 *    （即使用户取消删除操作？不 —— 它在 `which == POSITIVE` 之后，所以只有确认才写）。
 * 8. `DeleteDialogHelper` 里 `getExistingGalleryDownloadDir`（**已存在**的目录）与
 *    `DeleteGalleryFilesTask` 里 `getGalleryDownloadDir`（**算出来的**目录）**不是同一个 API**：
 *    前者用于"已经下载过、文件名可能有 7z 标记"，后者用于"按 gid 推目录再删"。**不要合并**。
 *
 * ── 平台差异（依赖倒置 + ArkUI 载体）────────────────────────────────────────
 * 1. **上游已有 `Host` 接口**（`context` / `activity2` / `recyclerView` / `list` / `downloadManager` /
 *    `positionInList` / `fabLayout` / `onClickPrimaryFab` / `launchGalleryActivity` / `resources` / `getString`）
 *    → **照搬这个接口形状**，只把 Android 特有类型换掉：
 *    `recyclerView` → 选择集能力（`getCheckedItemPositions` / `checkAll` / `outOfCustomChoiceMode`）；
 *    `Intent/startService` → `startRangeDownload(gidList)`；`fab` → 图标名。
 * 2. **`DownloadService.ACTION_START_RANGE` + `KEY_GID_LIST`** → 宿主方法 `startRangeDownload(gids)`，
 *    参数类型用 `number[]`（上游 `LongList` 是优化过的 long 容器；ArkTS 无此需求，gid < 2^53 安全）。
 * 3. **`CheckBoxDialogBuilder` → 本仓库 `CheckBoxDialogSpec`**（`hippo/app/DialogSpecs.ets`，纯数据）：
 *    本文件产出 spec（message/messageArgs/checkText/checked），"弹窗"由页面层执行。
 * 4. **`AsyncTask`** → 宿主注入 `deleteFileAsync` / `deleteGalleryFilesAsync`（`taskpool` 实现），
 *    本文件只**决定调哪个**。
 * 5. **静态字段 `DownloadAdapter.DRAG_ENABLE`** → 本仓库放在本类的 `dragEnable` 字段并由宿主持久化。
 *
 * ── 依赖实测（本仓已存在）──────────────────────────────────────────────────
 * `DownloadInfo`、`GalleryInfo`、`CheckBoxDialogSpec`（`title`/`message`）、
 * `DownloadManager` 的 `stopRangeDownload` / `deleteRangeDownload` / `deleteDownload` / `changeLabel` / `getLabelList`。
 *
 * ── 缺口（已登记，不假装有）──────────────────────────────────────────────────
 * `SpiderDen.getExistingGalleryDownloadDir` / `getGalleryDownloadDir`、`EhDB.removeDownloadDirname`、
 * `Settings.getRemoveImageFiles` / `putRemoveImageFiles` / `setDragDownloadGallery`：
 * 前三个属 storage-db / download-sync 的 IO 层 → 走宿主注入；后三个走宿主 `settings` 能力。
 */

import { DownloadInfo } from '../../../../dao/DownloadInfo';
import { GalleryInfo } from '../../../../client/data/GalleryInfo';
import { CheckBoxDialogSpec } from '../../../../../app/DialogSpecs';
import { hilog } from '@kit.PerformanceAnalysisKit';

/** 上游 FAB 二级按钮的 7 个位置（0..6），含义见文件头 */
export const SECONDARY_CHECK_ALL: number = 0;
export const SECONDARY_START: number = 1;
export const SECONDARY_STOP: number = 2;
export const SECONDARY_DELETE: number = 3;
export const SECONDARY_MOVE: number = 4;
export const SECONDARY_RANDOM: number = 5;
export const SECONDARY_DRAG_TOGGLE: number = 6;

/** 上游两个拖拽图标 */
export const ICON_DRAG_ON: string = 'v_mobile_hand_left_x24';
export const ICON_DRAG_OFF: string = 'v_mobile_hand_left_off_x24';

/** 上游字符串键 */
export const TITLE_DELETE_RANGE: string = 'app.string.download_remove_dialog_title';
export const MESSAGE_DELETE_RANGE: string = 'app.string.download_remove_dialog_message_2';
export const CHECK_DELETE_RANGE: string = 'app.string.download_remove_dialog_check_text';
export const TITLE_MOVE: string = 'app.string.download_move_dialog_title';
export const DEFAULT_LABEL_NAME_KEY: string = 'app.string.default_download_label_name';

/**
 * 上游 `interface Host`（**照搬形状**，只换平台特有类型，见「平台差异」1）。
 */
export interface BatchActionsHost {
  /** 上游 `recyclerView.checkAll()` */
  checkAll(): void;
  /** 上游 `getCheckedItemPositions()` → 视图位置数组（**只含已选中的**） */
  getCheckedItemPositions(): number[];
  /** 上游 `outOfCustomChoiceMode()` */
  outOfCustomChoiceMode(): void;
  /** 上游 `positionInList(position)`：**视图位置 → 列表下标**（见「关键行为」1） */
  positionInList(position: number): number;
  /** 上游 `list` */
  getList(): DownloadInfo[] | null;
  /** 上游 `startService(DownloadService ACTION_START_RANGE, KEY_GID_LIST)` */
  startRangeDownload(gids: number[]): void;
  /** 上游 `downloadManager.stopRangeDownload(gidList)` */
  stopRangeDownload(gids: number[]): Promise<void>;
  /** 上游 `downloadManager.deleteRangeDownload(gidList)` */
  deleteRangeDownload(gids: number[]): Promise<void>;
  /** 上游 `downloadManager.deleteDownload(gid)` */
  deleteDownload(gid: number): Promise<void>;
  /** 上游 `downloadManager.changeLabel(list, label)` */
  changeLabel(list: DownloadInfo[], label: string | null): Promise<void>;
  /** 上游 `downloadManager.getLabelList()` → 只取 label 文本 */
  getLabelTexts(): string[];
  /** 上游 `Settings.getRemoveImageFiles()` */
  getRemoveImageFiles(): boolean;
  /** 上游 `Settings.putRemoveImageFiles(checked)` */
  putRemoveImageFiles(checked: boolean): void;
  /** 上游 `Settings.setDragDownloadGallery(enabled)` */
  setDragDownloadGallery(enabled: boolean): void;
  /** 上游 `EhDB.removeDownloadDirname(gid)` */
  removeDownloadDirname(gid: number): void;
  /** 上游 `SpiderDen.getExistingGalleryDownloadDir(gi)` → null 表示目录不存在 */
  getExistingDownloadDir(info: GalleryInfo): string | null;
  /** 上游 `deleteFileAsync(file)` */
  deleteFileAsync(path: string): void;
  /** 上游 `deleteGalleryFilesAsync(list)` */
  deleteGalleryFilesAsync(list: GalleryInfo[]): void;
  /** 上游 `launchGalleryActivity(intent)` */
  launchGalleryActivity(galleryInfo: GalleryInfo): void;
  /** 上游 `onClickPrimaryFab(fabLayout, null)` */
  onClickPrimaryFab(): void;
  /** 上游 `getString(resId, vararg args)`（`%1$s` 占位由宿主本地化层替换） */
  formatMessage(key: string, arg: string): string;
  /** 上游 `getString(@string/default_download_label_name)` 的已解析文本 */
  getDefaultLabelName(): string;
}

/** 一次批量操作的收集结果（上游 `gidList` + `downloadInfoList` 两套并行容器） */
export class BatchSelection {
  gids: number[] = [];
  infos: DownloadInfo[] = [];

  isEmpty(): boolean {
    return this.infos.length === 0 && this.gids.length === 0;
  }
}

export class DownloadBatchActions {
  private host: BatchActionsHost;
  /**
   * 上游 `DownloadAdapter.DRAG_ENABLE`（**静态**字段）。本实现放实例字段并持久化到 Settings，
   * 语义等价：翻转 → 持久化 → 换图标。
   */
  private dragEnable: boolean = false;

  constructor(host: BatchActionsHost) {
    this.host = host;
  }

  /** 当前拖拽开关（测试观测 / 页面层选图标） */
  isDragEnabled(): boolean {
    return this.dragEnable;
  }

  /**
   * 收集选中项（上游 while 循环 + 两套容器的等价实现）。
   * @param collectGid position ∈ {1,2,3}
   * @param collectInfo position ∈ {3,4}
   */
  private collect(collectGid: boolean, collectInfo: boolean): BatchSelection {
    const sel: BatchSelection = new BatchSelection();
    const list: DownloadInfo[] | null = this.host.getList();
    if (list === null) {
      return sel;
    }
    const checked: number[] = this.host.getCheckedItemPositions();
    for (let i = 0; i < checked.length; i++) {
      // ★ 关键：视图位置 → 列表下标（见「关键行为」1）
      const listIndex: number = this.host.positionInList(checked[i]);
      if (listIndex < 0 || listIndex >= list.length) {
        continue;
      }
      const info: DownloadInfo = list[listIndex];
      if (collectInfo) {
        sel.infos.push(info);
      }
      if (collectGid) {
        sel.gids.push(info.gid);
      }
    }
    return sel;
  }

  /**
   * 上游 `onClickSecondaryFab(view, fab, position)`。
   * @returns 产出的对话框描述（Delete/Move 会返回；其它分支 null）
   */
  onClickSecondaryFab(position: number): BatchFabResult | null {
    // 上游前置：context/activity/recyclerView 任一 null → return（本实现 host 恒存在）

    // 上游：if (0 == position) { recyclerView.checkAll() } else { ... }
    if (position === SECONDARY_CHECK_ALL) {
      this.host.checkAll();
      return null;
    }

    const collectGid: boolean =
      position === SECONDARY_START || position === SECONDARY_STOP || position === SECONDARY_DELETE;
    const collectInfo: boolean =
      position === SECONDARY_DELETE || position === SECONDARY_MOVE;
    const sel: BatchSelection = this.collect(collectGid, collectInfo);

    if (position === SECONDARY_START) {
      // 上游：if (gidList!!.isEmpty) return
      if (sel.gids.length === 0) {
        return null;
      }
      this.host.startRangeDownload(sel.gids);
      // 上游：cancel check mode（**Start 立刻退**）
      this.host.outOfCustomChoiceMode();
      return null;
    }

    if (position === SECONDARY_STOP) {
      if (sel.gids.length === 0) {
        return null;
      }
      // 上游：downloadManager?.stopRangeDownload(gidList)（未 await，调完即走）
      //
      // ⚠ 上游这里是 Kotlin 的 `?.` 空安全调用，**异常会顺着调用栈抛给上层**；
      //   我们改成了 fire-and-forget + catch，所以必须留一条痕迹 ——
      //   否则"停止批量下载失败"在日志里完全不可见（用户看到进度条不动，查不到任何原因）。
      //   silent-failures 闸门的 A2（多行空 catch）就是抓这个形态。
      const p: Promise<void> = this.host.stopRangeDownload(sel.gids);
      p.catch((_e: Error): void => {
        hilog.error(0x0000, 'DownloadBatchActions',
          'stopRangeDownload failed (already left choice mode): %{public}s', _e.message);
      });
      this.host.outOfCustomChoiceMode();
      return null;
    }

    if (position === SECONDARY_DELETE) {
      if (sel.infos.length === 0) {
        return null;
      }
      // 上游：CheckBoxDialogBuilder(message 带**数量**, checkText, checked = Settings.getRemoveImageFiles())
      // 上游 `CheckBoxDialogBuilder(context, message带数量, checkText, checked)`
      const spec: CheckBoxDialogSpec = new CheckBoxDialogSpec(
        this.host.formatMessage(MESSAGE_DELETE_RANGE, sel.gids.length.toString()),
        CHECK_DELETE_RANGE, this.host.getRemoveImageFiles());
      spec.title = TITLE_DELETE_RANGE;
      const result: BatchFabResult = new BatchFabResult();
      result.dialog = spec;
      result.kind = BATCH_DELETE;
      result.selection = sel;
      // **注意**：Delete 分支不在这里退出选择模式（见「关键行为」2）
      return result;
    }

    if (position === SECONDARY_MOVE) {
      if (sel.infos.length === 0) {
        return null;
      }
      // 上游：labelList = [default_download_label_name] + getLabelList() 的 label
      const labels: string[] = [];
      labels.push(this.host.getDefaultLabelName());
      const rawLabels: string[] = this.host.getLabelTexts();
      for (let i = 0; i < rawLabels.length; i++) {
        labels.push(rawLabels[i]);
      }
      const spec: MoveDialogSpec = new MoveDialogSpec();
      spec.title = TITLE_MOVE;
      spec.items = labels;
      const result: BatchFabResult = new BatchFabResult();
      result.moveDialog = spec;
      result.kind = BATCH_MOVE;
      result.selection = sel;
      return result;
    }

    if (position === SECONDARY_RANDOM) {
      const list: DownloadInfo[] | null = this.host.getList();
      if (list === null || list.length === 0) {
        return null;
      }
      this.host.onClickPrimaryFab();
      this.viewRandom();
      return null;
    }

    if (position === SECONDARY_DRAG_TOGGLE) {
      const icon: string = this.setDragEnable();
      const result: BatchFabResult = new BatchFabResult();
      result.kind = BATCH_DRAG_TOGGLE;
      result.fabIcon = icon;
      return result;
    }

    return null;
  }

  /**
   * 上游 `setDragEnable(fab)`：**先翻转** → 持久化 → **按新值**选图标。
   * @returns 新图标名
   */
  setDragEnable(): string {
    this.dragEnable = !this.dragEnable;
    this.host.setDragDownloadGallery(this.dragEnable);
    // 上游：if (DownloadAdapter.DRAG_ENABLE) 换 v_mobile_hand_left_x24 else 换 ..._off_x24
    return this.dragEnable ? ICON_DRAG_ON : ICON_DRAG_OFF;
  }

  /**
   * 上游 `viewRandom()`：随机取一条并起阅读器。
   * **防御 `position >= list.size`**（见「关键行为」5）。
   * @param randomValue 由调用方给 `Math.random()` 的值（便于断言边界）；缺省用随机
   * @returns 是否成功打开（便于断言）
   */
  viewRandom(randomValue?: number): boolean {
    const list: DownloadInfo[] | null = this.host.getList();
    if (list === null) {
      return false;
    }
    const r: number = randomValue === undefined ? Math.random() : randomValue;
    const position: number = Math.floor(r * list.length);
    // 上游：if (position < 0 || position >= list.size) return
    if (position < 0 || position >= list.length) {
      return false;
    }
    this.host.launchGalleryActivity(list[position]);
    return true;
  }

  /** 上游 `DeleteRangeDialogHelper.onClick`：正按钮才执行；**先退选择模式**再删（见「关键行为」2） */
  async onDeleteRangeConfirm(selection: BatchSelection, checked: boolean): Promise<boolean> {
    // 上游：if (which != BUTTON_POSITIVE) return —— 由调用方只传确认
    // 上游：先 outOfCustomChoiceMode()
    this.host.outOfCustomChoiceMode();
    const p: Promise<void> = this.host.deleteRangeDownload(selection.gids);
    await p;
    // 上游：Settings.putRemoveImageFiles(checked)（**无条件写回**）
    this.host.putRemoveImageFiles(checked);
    if (checked) {
      const infos: GalleryInfo[] = [];
      for (let i = 0; i < selection.infos.length; i++) {
        infos.push(selection.infos[i]);
      }
      this.host.deleteGalleryFilesAsync(infos);
    }
    return true;
  }

  /**
   * 上游 `DeleteDialogHelper.onClick`（**单条删除，当前下载页未使用，保留**）：
   * 注意它用的是 `getExistingGalleryDownloadDir`（已存在目录）而非算出来的目录（见「关键行为」8）。
   */
  async onDeleteSingleConfirm(info: GalleryInfo, checked: boolean): Promise<boolean> {
    const p: Promise<void> = this.host.deleteDownload(info.gid);
    await p;
    this.host.putRemoveImageFiles(checked);
    if (checked) {
      const dir: string | null = this.host.getExistingDownloadDir(info);
      this.host.removeDownloadDirname(info.gid);
      if (dir !== null) {
        this.host.deleteFileAsync(dir);
      } else {
        const one: GalleryInfo[] = [info];
        this.host.deleteGalleryFilesAsync(one);
      }
    }
    return true;
  }

  /**
   * 上游 `MoveDialogHelper.onClick(which)`：
   * ★ 上游把"取消选择模式"放在 `context == null` 判断**之后** —— 本实现 host 恒存在，故总能退；
   *   `which == 0` → label = **null**（= 移出标签）；否则 `labels[which]`。
   */
  async onMoveSelect(selection: BatchSelection, labels: string[], which: number): Promise<boolean> {
    this.host.outOfCustomChoiceMode();
    let label: string | null = null;
    if (which !== 0) {
      if (which < 0 || which >= labels.length) {
        return false;
      }
      label = labels[which];
    }
    await this.host.changeLabel(selection.infos, label);
    return true;
  }
}

/** 二级 FAB 分支的结果类型 */
export const BATCH_DELETE: number = 3;
export const BATCH_MOVE: number = 4;
export const BATCH_DRAG_TOGGLE: number = 6;

/** 二级 FAB 点击后的产物（对话框描述 / 图标），null 表示无界面产物 */
export class BatchFabResult {
  kind: number = -1;
  dialog: CheckBoxDialogSpec | null = null;
  moveDialog: MoveDialogSpec | null = null;
  selection: BatchSelection | null = null;
  /** 拖拽开关翻转后的图标名 */
  fabIcon: string = '';
}

/** 移动对话框描述（`@string/download_move_dialog_title` + 标签数组） */
export class MoveDialogSpec {
  title: string = TITLE_MOVE;
  /** **第 0 位是"默认标签"文案**（选中 = 移出标签，见「关键行为」4） */
  items: string[] = [];
}

