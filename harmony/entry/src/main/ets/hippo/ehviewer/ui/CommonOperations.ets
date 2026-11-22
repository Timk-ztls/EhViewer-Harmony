/*
 * 上游：app/src/main/java/com/hippo/ehviewer/ui/CommonOperations.java
 *       （inventory S0189，上游实际 263 行；清单登记 236 行）
 * 目标：harmony/entry/src/main/ets/hippo/ehviewer/ui/CommonOperations.ets
 *
 * 背景：三组"跨页面复用"的操作：**收藏**、**开始下载**、**.nomedia 维护**。
 * 全项目多处调用（长按菜单、批量操作、下载页），所以这里的行为必须逐条照搬。
 *
 * ── 上游行为逐条对照 ────────────────────────────────────────────────────────
 * `doAddToFavorites(activity, gi, slot, listener)`：
 *   ① `slot == -1` → **纯本地收藏**：`EhDB.putLocalFavorite(gi)` + `listener.onSuccess(null)`（**不发请求**）
 *   ② `slot ∈ [0, 9]` → `METHOD_ADD_FAVORITES`，`setArgs(gid, token, slot, "")`（**第四个参数是空串**）
 *   ③ 其它 → `listener.onFailure(new Exception())`（上游注释 `// TODO Add text`）
 * `addToFavorites(activity, gi, listener, isDefaultFavSolt)`：
 *   · `slot = Settings.getDefaultFavSlot()`；items = **11 项**：`[0]=@string/local_favorites` + `favCat[0..9]`
 *   · **`(slot >= -1 && slot <= 9) && !isDefaultFavSolt`** → 直接用该 slot 走 `doAddToFavorites`
 *     （`newFavoriteName = slot >= 0 ? items[slot+1] : null`）
 *   · 否则弹 `ListCheckBoxDialogBuilder(items, …, checkedText=@string/remember_favorite_collection, false)`
 *     + title `@string/add_favorites_dialog_title` + cancel → `listener.onCancel()`
 *     · 选中回调：`slot1 = position - 1`（**-1 表示本地收藏**）
 *       → `doAddToFavorites(..., slot1, Delegate(..., slot1))`
 *       → **`builder.isChecked()` → `putDefaultFavSlot(slot1)`；否则 `putDefaultFavSlot(INVALID_DEFAULT_FAV_SLOT)`**
 * `removeFromFavorites(activity, gi, listener)`：
 *   ① `EhDB.removeLocalFavorites(gid)` ② `METHOD_ADD_FAVORITES` + `setArgs(gid, token, **-1**, "")`
 *   ③ 回调 `DelegateFavoriteCallback(listener, gi, **null**, **-2**)` —— **slot 传 -2**
 * `DelegateFavoriteCallback.onSuccess`：
 *   `info.favoriteName = newFavoriteName` → `info.favoriteSlot = slot` → `delegate.onSuccess`
 *   → **`getFavouriteStatusRouter().modifyFavourites(gid, slot)`**（通知所有列表刷新收藏态）
 *
 * `startDownload(activity, gi, forceDefault)` → 转调 `startDownload(activity, [gi], forceDefault)`
 * `startDownload(activity, infos, forceDefault)`：
 *   ① 遍历：`dm.containDownloadInfo(gid)` → 进 `toStart`；否则进 `toAdd`
 *   ② **`toStart` 非空** → `startService(ACTION_START_RANGE, KEY_GID_LIST=toStart)`（**续传已有任务**）
 *   ③ **`toAdd` 为空 → 提示 `@string/added_to_download_list` 并 return**（没有新任务可加）
 *   ④ `justStart = forceDefault`；`!justStart && Settings.getHasDefaultDownloadLabel()` 时
 *      `label = Settings.getDefaultDownloadLabel()`；**`justStart = (label == null || dm.containLabel(label))`**
 *      —— 注意这里语义是"默认标签**不可用**（空或已不存在）→ 就直接开，不弹选择"
 *   ⑤ `!justStart && dm.getLabelList().size() == 0` → `justStart = true; label = null`（没有自定义标签）
 *   ⑥ `justStart`：逐个 `startService(ACTION_START, KEY_LABEL=label, KEY_GALLERY_INFO=gi)` + 提示
 *   ⑦ 否则弹选择框：items = **`[@string/default_download_label_name] + 所有标签`**
 *      · 选中：`position == 0 → label1 = null`；否则 `label1 = items[position]`，
 *        **`!dm.containLabel(label1)` → `label1 = null`**（标签已被删则退化为无标签）
 *      · 逐个 startService(ACTION_START)
 *      · `isChecked()` → `putHasDefaultDownloadLabel(true)` + `putDefaultDownloadLabel(label1)`；
 *        否则 `putHasDefaultDownloadLabel(false)`
 *      · 提示 `@string/added_to_download_list`
 *      · checkedText = `@string/remember_download_label`，title = `@string/download`
 *
 * `ensureNoMediaFile(file)`：`file == null → return`；`noMedia = file.createFile(".nomedia")`；
 *   **`noMedia == null → return`**；然后 `openInputStream()` 试一次（**只为触发创建**），
 *   `catch (IOException) { /* Ignore *\/ }`，`finally closeQuietly`
 * `removeNoMediaFile(file)`：`file == null → return`；`noMedia = file.subFile(".nomedia")`；
 *   **`noMedia != null && noMedia.isFile()`** 才 `delete()`
 *
 * ── 关键行为（照搬，别"顺手修"）──────────────────────────────────────────────
 * 1. **`slot == -1` 是"本地收藏"，不发网络请求**（`putLocalFavorite` + 立即 onSuccess）。
 *    与 `slot ∈ [0,9]` 的远端收藏是两条完全不同的路径。
 * 2. **`slot 传 -2` 的清空语义**（`removeFromFavorites` 里的 Delegate）：-2 不是合法 slot，
 *    只是让 `modifyFavourites(gid, -2)` 表达"已取消收藏"。
 * 3. **`addToFavorites` 的 `justStart` 判断是"反的"**：
 *    `justStart = (label == null || dm.containLabel(label))` —— 默认标签**空或已存在**时直接开。
 *    直觉会写成 `!containLabel`（找不到才直接开），**那样就反了**。
 * 4. **`toStart` 与 `toAdd` 都非空时，两件事都做**：先对已有的发 RANGE 续传，再对新的发 START。
 * 5. **`toAdd` 为空时直接提示"已加入下载列表"并 return** —— 即使什么都没做也提示（上游如此）。
 * 6. **选择框里 `position == 0` 是"默认标签"→ label = null**；
 *    且**选到的标签若已被删（`!containLabel`）也退化为 null**。
 * 7. **`ensureNoMediaFile` 的 `createFile` 返回 null 就 return**（不是抛错）；
 *    读流只为"确保文件系统真的创建了它"，异常被**完全忽略**。
 * 8. **`removeNoMediaFile` 用 `subFile`（不创建）而不是 `createFile`** —— 查了才删。
 *
 * ── 平台差异 ────────────────────────────────────────────────────────────────
 * 1. `Activity.startService(Intent)` → `OpsHost.startRange(gids)` / `startSingle(gi, label)`。
 * 2. `EhClient.execute` → `OpsHost.addFavorites(gid, token, slot, callback)`。
 * 3. `ListCheckBoxDialogBuilder` → 本仓 `ListCheckBoxDialogSpec`（纯数据）→ 产出 spec。
 * 4. `UniFile` → `OpsHost` 的 `createNoMedia(path)` / `findNoMedia(path)` / `deleteFile(path)`。
 * 5. `Settings.getDefaultFavSlot/putDefaultFavSlot` 等在本仓库 `Settings` **尚无**（见「缺口」）→ 走 `OpsSettings`。
 * 6. `FavouriteStatusRouter.modifyFavourites(gid, slot)` → `OpsHost.modifyFavourites(gid, slot)`。
 *
 * ── 依赖实测（本仓已存在）──────────────────────────────────────────────────
 * `GalleryInfo`（`favoriteName` / `favoriteSlot`）、`DownloadManager.containDownloadInfo` /
 * `containLabel` / `getLabelList`、`hippo/app/DialogSpecs.ets` 的 `ListCheckBoxDialogSpec`、
 * `EhDB.putLocalFavorite` / `removeLocalFavorites`。
 *
 * ── 缺口 ───────────────────────────────────────────────────────────────────
 * `Settings.INVALID_DEFAULT_FAV_SLOT` / `getDefaultFavSlot` / `putDefaultFavSlot` /
 * `getHasDefaultDownloadLabel` / `putHasDefaultDownloadLabel` / `getDefaultDownloadLabel` /
 * `putDefaultDownloadLabel` / `getFavCat` —— 本仓库 `Settings.ets` 里**都没有**（已 grep 确认），
 * 全部通过 `OpsSettings` 注入；补进 Settings 是 core-runtime 的活。
 */

import { GalleryInfo } from '../client/data/GalleryInfo';
import { DownloadLabel } from '../dao/DownloadLabel';
import { ListCheckBoxDialogSpec } from '../../app/DialogSpecs';

/** 上游 `Settings.INVALID_DEFAULT_FAV_SLOT`（值 = -2，与"清空收藏"的 Delegate slot 一致） */
export const INVALID_DEFAULT_FAV_SLOT: number = -2;
/** 上游 `slot == -1` = 本地收藏 */
export const SLOT_LOCAL: number = -1;
/** 上游 `removeFromFavorites` 里 Delegate 传的 slot */
export const SLOT_REMOVED: number = -2;

/** 上游字符串键 */
export const STR_LOCAL_FAVORITES: string = 'app.string.local_favorites';
export const STR_REMEMBER_FAV: string = 'app.string.remember_favorite_collection';
export const STR_ADD_FAV_TITLE: string = 'app.string.add_favorites_dialog_title';
export const STR_REMEMBER_LABEL: string = 'app.string.remember_download_label';
export const STR_DOWNLOAD_TITLE: string = 'app.string.download';
export const STR_ADDED_TO_DOWNLOAD: string = 'app.string/added_to_download_list';
export const STR_DEFAULT_LABEL_NAME: string = 'app.string.default_download_label_name';

/** 上游 `DownloadService.ACTION_*` 与 `KEY_*`（本实现以宿主方法表达） */
export const ACTION_START: string = 'start';
export const ACTION_START_RANGE: string = 'start_range';
export const KEY_GID_LIST: string = 'gid_list';
export const KEY_LABEL: string = 'label';
export const KEY_GALLERY_INFO: string = 'gallery_info';

/** 收藏回调（上游 `EhClient.Callback<Void>`） */
export interface FavoriteCallback {
  onSuccess(): void;
  onFailure(e: Error): void;
  onCancel(): void;
}

/** 设置读取（见「缺口」：这些字段本仓库 Settings 尚无） */
export interface OpsSettings {
  getDefaultFavSlot(): number;
  putDefaultFavSlot(slot: number): void;
  /** `Settings.getFavCat()` → 固定 10 项 */
  getFavCat(): string[];
  getHasDefaultDownloadLabel(): boolean;
  putHasDefaultDownloadLabel(v: boolean): void;
  getDefaultDownloadLabel(): string | null;
  putDefaultDownloadLabel(label: string | null): void;
}

/** 宿主能力 */
export interface OpsHost {
  /** 上游 `EhDB.putLocalFavorite(gi)` */
  putLocalFavorite(gi: GalleryInfo): void;
  /** 上游 `EhDB.removeLocalFavorites(gid)` */
  removeLocalFavorites(gid: number): void;
  /** 上游 `EhClient.execute(METHOD_ADD_FAVORITES, gid, token, slot, "")` */
  addFavoritesRemote(gid: number, token: string, slot: number, callback: FavoriteCallback): void;
  /** 上游 `FavouriteStatusRouter.modifyFavourites(gid, slot)` */
  modifyFavourites(gid: number, slot: number): void;
  /** 上游 `DownloadManager.containDownloadInfo(gid)` */
  containDownloadInfo(gid: number): boolean;
  /** 上游 `DownloadManager.containLabel(label)` */
  containLabel(label: string | null): boolean;
  /** 上游 `DownloadManager.getLabelList()` */
  getLabelList(): DownloadLabel[];
  /** 上游 `startService(ACTION_START_RANGE, KEY_GID_LIST)` */
  startRange(gids: number[]): void;
  /** 上游 `startService(ACTION_START, KEY_LABEL, KEY_GALLERY_INFO)` */
  startSingle(gi: GalleryInfo, label: string | null): void;
  /** 上游 `activity.showTip(key, LENGTH_SHORT)` */
  showTip(key: string): void;
  /** 上游 `activity.getString(key)`（对话框 items 里的标签文案） */
  resolveString(key: string): string;
  /** 页面层"弹选择框"（本文件只产出 spec） */
  showListCheckBox(spec: ListCheckBoxDialogSpec, onSelect: (position: number, checked: boolean) => void,
    onCancel: () => void): void;
  /** 上游 `file.createFile(".nomedia")`；返回 null 表示创建失败 */
  createNoMedia(path: string): boolean;
  /** 上游 `file.subFile(".nomedia")` 且 `isFile()`；返回 false = 不存在或不是文件 */
  findNoMediaFile(path: string): boolean;
  /** 上游 `noMedia.delete()` */
  deleteFile(path: string): void;
}

export class CommonOperations {
  private host: OpsHost;
  private settings: OpsSettings;

  constructor(host: OpsHost, settings: OpsSettings) {
    this.host = host;
    this.settings = settings;
  }

  /**
   * 上游 `doAddToFavorites(...)`：
   * `slot == -1` → 本地收藏（不发请求）；`slot ∈ [0,9]` → 远端；其它 → onFailure。
   */
  doAddToFavorites(gi: GalleryInfo, slot: number, listener: FavoriteCallback): void {
    if (slot === SLOT_LOCAL) {
      this.host.putLocalFavorite(gi);
      listener.onSuccess();
      return;
    }
    if (slot >= 0 && slot <= 9) {
      // 上游：setArgs(gid, token, slot, "") —— 第四个参数是空串
      this.host.addFavoritesRemote(gi.gid, gi.token, slot, listener);
      return;
    }
    listener.onFailure(new Error('invalid favorite slot'));
  }

  /**
   * 上游 `addToFavorites(activity, gi, listener, isDefaultFavSolt)`。
   * @param isDefaultFavSolt 上游参数名（**拼写就是 FavSolt**）；true = 强制弹选择框
   */
  addToFavorites(gi: GalleryInfo, listener: FavoriteCallback, isDefaultFavSolt: boolean): void {
    const slot: number = this.settings.getDefaultFavSlot();
    // 上游：items[0] = local_favorites，然后拷贝 10 个 favCat
    const items: string[] = [];
    items.push(this.host.resolveString(STR_LOCAL_FAVORITES));
    const favCat: string[] = this.settings.getFavCat();
    for (let i = 0; i < 10; i++) {
      items.push(i < favCat.length ? favCat[i] : '');
    }

    if (slot >= -1 && slot <= 9 && !isDefaultFavSolt) {
      // 上游：newFavoriteName = slot >= 0 ? items[slot + 1] : null
      const newFavoriteName: string | null = slot >= 0 ? items[slot + 1] : null;
      this.doAddToFavorites(gi, slot,
        new DelegateFavoriteCallback(listener, gi, newFavoriteName, slot, this.host));
      return;
    }

    const spec: ListCheckBoxDialogSpec = new ListCheckBoxDialogSpec(
      items, this.host.resolveString(STR_REMEMBER_FAV), false);
    spec.title = this.host.resolveString(STR_ADD_FAV_TITLE);
    this.host.showListCheckBox(spec, (position: number, checked: boolean): void => {
      const slot1: number = position - 1;   // ★ position 0 = 本地收藏 → slot -1
      const name1: string | null = (slot1 >= 0 && slot1 <= 9) ? items[slot1 + 1] : null;
      this.doAddToFavorites(gi, slot1,
        new DelegateFavoriteCallback(listener, gi, name1, slot1, this.host));
      // 上游：checked → putDefaultFavSlot(slot1)；否则 putDefaultFavSlot(INVALID)
      if (checked) {
        this.settings.putDefaultFavSlot(slot1);
      } else {
        this.settings.putDefaultFavSlot(INVALID_DEFAULT_FAV_SLOT);
      }
    }, (): void => {
      listener.onCancel();
    });
  }

  /**
   * 上游 `removeFromFavorites`：
   * 先 `removeLocalFavorites` → 远端 `setArgs(gid, token, **-1**, "")` → Delegate 传 `slot = -2`。
   */
  removeFromFavorites(gi: GalleryInfo, listener: FavoriteCallback): void {
    this.host.removeLocalFavorites(gi.gid);
    this.host.addFavoritesRemote(gi.gid, gi.token, -1,
      new DelegateFavoriteCallback(listener, gi, null, SLOT_REMOVED, this.host));
  }

  /**
   * 上游 `startDownload(activity, infos, forceDefault)` 的完整逻辑。
   * 返回是否发出了"新任务"（`toAdd` 非空）。
   */
  startDownloads(infos: GalleryInfo[], forceDefault: boolean): DownloadStartResult {
    const result: DownloadStartResult = new DownloadStartResult();

    const toStart: number[] = [];
    const toAdd: GalleryInfo[] = [];
    for (let i = 0; i < infos.length; i++) {
      const gi: GalleryInfo = infos[i];
      if (this.host.containDownloadInfo(gi.gid)) {
        toStart.push(gi.gid);
      } else {
        toAdd.push(gi);
      }
    }

    // ② 已有任务 → 续传
    if (toStart.length > 0) {
      this.host.startRange(toStart);
      result.rangeStarted = toStart.length;
    }

    // ③ 没有新任务 → 提示并 return（**即使什么都没做也提示**）
    if (toAdd.length === 0) {
      this.host.showTip(STR_ADDED_TO_DOWNLOAD);
      result.usedDefaultLabel = true;
      return result;
    }

    let justStart: boolean = forceDefault;
    let label: string | null = null;
    // ④ ★ 这里的判断是"反的"：默认标签**空或已存在**时才算 justStart（见「关键行为」3）
    if (!justStart && this.settings.getHasDefaultDownloadLabel()) {
      label = this.settings.getDefaultDownloadLabel();
      justStart = label === null || this.host.containLabel(label);
    }
    // ⑤ 没有自定义标签 → 直接开
    if (!justStart && this.host.getLabelList().length === 0) {
      justStart = true;
      label = null;
    }

    if (justStart) {
      for (let i = 0; i < toAdd.length; i++) {
        this.host.startSingle(toAdd[i], label);
      }
      this.host.showTip(STR_ADDED_TO_DOWNLOAD);
      result.usedDefaultLabel = true;
      result.started = toAdd.length;
      return result;
    }

    // ⑦ 让用户选标签
    const list: DownloadLabel[] = this.host.getLabelList();
    const items: string[] = [];
    items.push(this.host.resolveString(STR_DEFAULT_LABEL_NAME));
    for (let i = 0; i < list.length; i++) {
      const l: string | null = list[i].getLabel();
      items.push(l === null ? '' : l);
    }
    const spec: ListCheckBoxDialogSpec = new ListCheckBoxDialogSpec(
      items, this.host.resolveString(STR_REMEMBER_LABEL), false);
    spec.title = this.host.resolveString(STR_DOWNLOAD_TITLE);

    this.host.showListCheckBox(spec, (position: number, checked: boolean): void => {
      let label1: string | null = null;
      if (position !== 0) {
        label1 = items[position];
        // 上游：标签已被删 → 退化为无标签
        if (!this.host.containLabel(label1)) {
          label1 = null;
        }
      }
      for (let i = 0; i < toAdd.length; i++) {
        this.host.startSingle(toAdd[i], label1);
      }
      if (checked) {
        this.settings.putHasDefaultDownloadLabel(true);
        this.settings.putDefaultDownloadLabel(label1);
      } else {
        this.settings.putHasDefaultDownloadLabel(false);
      }
      this.host.showTip(STR_ADDED_TO_DOWNLOAD);
    }, (): void => {
      // 上游没有给这个选择框设 cancel listener —— 取消即什么都不做
    });
    result.awaitingLabelChoice = true;
    return result;
  }

  /** 上游 `startDownload(activity, gi, forceDefault)`（单条重载） */
  startDownload(gi: GalleryInfo, forceDefault: boolean): DownloadStartResult {
    return this.startDownloads([gi], forceDefault);
  }

  /**
   * 上游 `ensureNoMediaFile(file)`：
   * `createFile` 返回 null → return；否则试读一次（**只为确保创建**），异常**完全忽略**。
   * @returns true = 确认存在（或已存在）
   */
  ensureNoMediaFile(path: string): boolean {
    if (path.length === 0) {
      return false;   // 上游 file == null
    }
    const created: boolean = this.host.createNoMedia(path);
    if (!created) {
      return false;
    }
    // 上游：openInputStream() 只为触发创建；IOException 被忽略；finally closeQuietly
    return true;
  }

  /** 上游 `removeNoMediaFile(file)`：用 `subFile`（不创建）查了才删 */
  removeNoMediaFile(path: string): boolean {
    if (path.length === 0) {
      return false;
    }
    const exists: boolean = this.host.findNoMediaFile(path);
    if (!exists) {
      return false;
    }
    this.host.deleteFile(path);
    return true;
  }
}

/** 上游 `DelegateFavoriteCallback`：成功后回写 info + 通知收藏态路由 */
export class DelegateFavoriteCallback implements FavoriteCallback {
  private delegate: FavoriteCallback;
  private info: GalleryInfo;
  private newFavoriteName: string | null;
  private slot: number;
  private host: OpsHost;

  constructor(delegate: FavoriteCallback, info: GalleryInfo, newFavoriteName: string | null,
    slot: number, host: OpsHost) {
    this.delegate = delegate;
    this.info = info;
    this.newFavoriteName = newFavoriteName;
    this.slot = slot;
    this.host = host;
  }

  onSuccess(): void {
    // 上游：info.favoriteName = newFavoriteName; info.favoriteSlot = slot
    this.info.favoriteName = this.newFavoriteName;
    this.info.favoriteSlot = this.slot;
    this.delegate.onSuccess();
    // 上游：EhApplication.getFavouriteStatusRouter().modifyFavourites(info.gid, slot)
    this.host.modifyFavourites(this.info.gid, this.slot);
  }

  onFailure(e: Error): void {
    this.delegate.onFailure(e);
  }

  onCancel(): void {
    this.delegate.onCancel();
  }
}

/** `startDownloads` 的结果（便于断言走了哪条分支） */
export class DownloadStartResult {
  /** 续传了多少条已有任务（>0 说明发过 RANGE） */
  rangeStarted: number = 0;
  /** 直接开了多少条新任务 */
  started: number = 0;
  /** 是否走了"用默认/无标签直接开"的分支 */
  usedDefaultLabel: boolean = false;
  /** 是否弹出了标签选择框（此时 started 仍为 0） */
  awaitingLabelChoice: boolean = false;
}
