/*
 * 上游：app/src/main/java/com/hippo/ehviewer/ui/scene/download/DownloadLabelDraw.java
 *       （inventory S0217，上游 195 行；清单登记 171 行）
 * 目标：harmony/entry/src/main/ets/hippo/ehviewer/ui/scene/download/DownloadLabelDraw.ets
 *
 * 背景：下载页**右侧抽屉**里的"下载标签"列表。每项显示标签名 + 条目数；点一项 → 切到该标签的筛选；
 * 菜单两项：进标签管理页（`DownloadLabelsScene`）、设"默认下载标签"。
 *
 * ── 上游行为逐条对照 ────────────────────────────────────────────────────────
 * 字段：`inflater` / `scene: DownloadsScene` / `container` / `context` / `view` / `toolbar` / `listView`
 * `createView()`：
 *   · `bookmarks_draw` 布局；toolbar 标题 `@string/download_labels`；菜单 `@menu/drawer_download`
 *   · 菜单：
 *     · `action_settings` → `scene.startScene(Announcer(DownloadLabelsScene))` → **true**
 *     · `action_default_download_label`：
 *       `dm == null → return true`（**已处理也返回 true**）；
 *       items = **`[let_me_select, default_download_label_name, ...所有标签]`**（**比别处多一个"让我选择"**）
 *       → AlertDialog(title `@string/default_download_label`)：
 *         · `which == 0`（让我选择）→ `putHasDefaultDownloadLabel(false)`
 *         · 否则 `putHasDefaultDownloadLabel(true)`；`which == 1` → `label = null`；否则 `label = items[which]`
 *           → `putDefaultDownloadLabel(label)`
 *     · 其它 → **false**
 *   · 标签列表：`labels = [@string/default_download_label_name] + 所有 getLabelList() 标签`（**第 0 位是默认**）
 *   · **条目数**：第 0 项用 `dm.getDefaultDownloadInfoList().size()`；其余用 `dm.getLabelCount(label)`
 *   · 点击：**`scene.searching` 为真 → Toast `@string/download_searching` 并 return**（搜索中不许切标签）；
 *     `position == 0 → label = null`；否则 `label = labels[position]`
 *     → **`!ObjectUtils.equal(label, scene.mLabel)`** 才动作（相等就不动）：
 *       `scene.mLabel = label` → `scene.updateForLabel()` →
 *       **`searchKey` 非空 → `scene.startSearching()`；否则 `scene.updateView()`** → `scene.closeDrawer(Gravity.RIGHT)`
 * `updateDownloadLabels()`：**与 createView 里的列表构建逻辑完全重复**（上游复制粘贴），
 *   重新 `getLabelList()` + 重建 adapter + **重设同一个点击监听**。
 *
 * ── 关键行为（照搬，别"顺手修"）──────────────────────────────────────────────
 * 1. **"默认下载标签"菜单的 items 有 "+2 偏移"**：`[让我选择, 默认名称, ...标签]`，
 *    而 `CommonOperations.startDownloads` 那边是 `[默认名称, ...标签]`（"+1 偏移"）。
 *    **两处的 0 号含义不同** —— 不能复用同一个 items 构造。
 * 2. **`dm == null` 时 `return true`**（已处理），而外层 `default` 才 `return false`。
 * 3. **搜索中不允许切标签**（Toast `download_searching`）—— 因为切标签会重排队列。
 * 4. **`!ObjectUtils.equal(label, scene.mLabel)` 才动作** —— 点已选中的标签**什么都不做**（连抽屉都不关）。
 * 5. **切标签后的分支**：`searchKey` 非空 → `startSearching()`（重搜）；否则 `updateView()`。
 * 6. **`updateDownloadLabels()` 与 createView 的列表构建完全重复** —— 上游复制粘贴，照搬（保留两份是为了
 *    "创建时"与"标签变化后"两个时机各自独立；合并成一份会改变调用次数语义）。
 * 7. 抽屉的关闭方向是 **`Gravity.RIGHT`**（右侧抽屉）。
 *
 * ── 平台差异 ────────────────────────────────────────────────────────────────
 * 1. `Toolbar` / `ListView` / `DrawerLayout` / `AlertDialog` 在 ArkUI 无对位 → `LabelDrawHost`。
 * 2. `DownloadManager` 的四个方法（`getLabelList` / `getDefaultDownloadInfoList` / `getLabelCount` /
 *    `getAll`）→ `LabelDrawHost` 转发（本仓 `DownloadManager` 已有前两个与 `getLabelCount`）。
 * 3. `Settings.putHasDefaultDownloadLabel/putDefaultDownloadLabel` 本仓 `Settings` 尚无 → 宿主 `LabelDrawSettings`。
 * 4. `ObjectUtils.equal(a, b)` → ArkTS `===`（含 null 情形：`null === null` 为 true，等价）。
 * 5. `Toast` → 宿主 `showToast(key)`；`scene.closeDrawer(Gravity.RIGHT)` → `closeDrawer()`。
 *
 * ── 依赖实测（本仓已存在）──────────────────────────────────────────────────
 * `DownloadLabel`（`getLabel()`）、`DownloadManager.getLabelList` / `getDefaultDownloadInfoList` / `getLabelCount`、
 * `hippo/ui/layout/bookmarks_draw.ets`、全部 6 个字符串键。
 */

import { DownloadLabel } from '../../../dao/DownloadLabel';

/** 上游字符串键 */
export const STR_DOWNLOAD_LABELS: string = 'app.string.download_labels';
export const STR_LET_ME_SELECT: string = 'app.string.let_me_select';
export const STR_DEFAULT_LABEL_NAME: string = 'app.string.default_download_label_name';
export const STR_DEFAULT_LABEL: string = 'app.string.default_download_label';
export const STR_DOWNLOAD_SEARCHING: string = 'app.string.download_searching';
/** 上游菜单项 id */
export const MENU_ACTION_SETTINGS: string = 'action_settings';
export const MENU_ACTION_DEFAULT_DOWNLOAD_LABEL: string = 'action_default_download_label';
/** 上游 `R.menu.drawer_download` */
export const MENU_DRAWER_DOWNLOAD: string = 'menu/drawer_download';
/** 上游 `Gravity.RIGHT`（抽屉方向，见「关键行为」7） */
export const DRAWER_GRAVITY_RIGHT: string = 'RIGHT';

/** 本抽屉的设置读写（见「平台差异」3） */
export interface LabelDrawSettings {
  putHasDefaultDownloadLabel(v: boolean): void;
  putDefaultDownloadLabel(label: string | null): void;
}

/** 宿主能力（`DownloadsScene` 的四个字段 + 视图 + 提示） */
export interface LabelDrawHost {
  /** 上游 `scene.getMDownloadManager()` —— 可为 null */
  getDownloadManager(): LabelDrawManager | null;
  /** 上游 `scene.getString(key)` */
  resolveString(key: string): string;
  /** 上游 `scene.searching` */
  isSearching(): boolean;
  /** 上游 `scene.getSearchKey()` */
  getSearchKey(): string | null;
  /** 上游 `scene.mLabel` 的读写 */
  getCurrentLabel(): string | null;
  setCurrentLabel(label: string | null): void;
  /** 上游 `scene.updateForLabel()` / `scene.updateView()` / `scene.startSearching()` */
  updateForLabel(): void;
  updateView(): void;
  startSearching(): void;
  /** 上游 `scene.startScene(Announcer(DownloadLabelsScene))` */
  startLabelsScene(): void;
  /** 上游 `scene.closeDrawer(Gravity.RIGHT)` */
  closeDrawer(): void;
  /** 上游 `Toast.makeText(context, R.string.download_searching, LENGTH_LONG)` */
  showToast(key: string): void;
}

/** `DownloadManager` 的最小面（只钉本文件用到的四个方法） */
export interface LabelDrawManager {
  /** 上游 `getLabelList()` */
  getLabelList(): DownloadLabel[];
  /** 上游 `getDefaultDownloadInfoList().size()` */
  getDefaultDownloadCount(): number;
  /** 上游 `getLabelCount(label)` */
  getLabelCount(label: string): number;
}

/** 列表项（上游 `DownloadLabelItem(label, count)`） */
export class DownloadLabelItem {
  label: string = '';
  /** 该项的条目数（第 0 项 = 默认标签的条目数） */
  count: number = 0;

  constructor(label: string = '', count: number = 0) {
    this.label = label;
    this.count = count;
  }
}

/** "设为默认下载标签"对话框（上游 items 有 **+2 偏移**，见「关键行为」1） */
export class DefaultLabelDialogSpec {
  title: string = STR_DEFAULT_LABEL;
  /** `[让我选择, 默认名称, ...标签]` —— **0 号是"让我选择"** */
  items: string[] = [];
}

/** 一次"设为默认"选择的产物 */
export class DefaultLabelChoice {
  /** `putHasDefaultDownloadLabel(...)` */
  hasDefault: boolean = false;
  /** `putDefaultDownloadLabel(...)`（hasDefault=false 时不写） */
  defaultLabel: string | null = null;
}

export class DownloadLabelDraw {
  private host: LabelDrawHost;
  private settings: LabelDrawSettings;

  constructor(host: LabelDrawHost, settings: LabelDrawSettings) {
    this.host = host;
    this.settings = settings;
  }

  /** 上游 toolbar 的标题键 */
  getToolbarTitleKey(): string {
    return STR_DOWNLOAD_LABELS;
  }

  /** 上游 `getMenuResId()` → `R.menu.drawer_download` */
  getMenuResId(): string {
    return MENU_DRAWER_DOWNLOAD;
  }

  /**
   * 上游菜单点击：
   * `action_settings` → 进标签管理页 + **true**；
   * `action_default_download_label` → **dm == null 也返回 true**（已处理），否则产出对话框描述 + true；
   * 其它 → false。
   */
  onMenuItemClick(itemId: string): MenuClickResult {
    const result: MenuClickResult = new MenuClickResult();
    if (itemId === MENU_ACTION_SETTINGS) {
      this.host.startLabelsScene();
      result.handled = true;
      return result;
    }
    if (itemId === MENU_ACTION_DEFAULT_DOWNLOAD_LABEL) {
      const dm: LabelDrawManager | null = this.host.getDownloadManager();
      if (dm === null) {
        // 上游：if (null == dm) { return true; }
        result.handled = true;
        return result;
      }
      const list: DownloadLabel[] = dm.getLabelList();
      // ★ items = [让我选择, 默认名称, ...标签] —— "+2 偏移"（见「关键行为」1）
      const items: string[] = [];
      items.push(this.host.resolveString(STR_LET_ME_SELECT));
      items.push(this.host.resolveString(STR_DEFAULT_LABEL_NAME));
      for (let i = 0; i < list.length; i++) {
        items.push(labelText(list[i]));
      }
      const spec: DefaultLabelDialogSpec = new DefaultLabelDialogSpec();
      spec.title = this.host.resolveString(STR_DEFAULT_LABEL);
      spec.items = items;
      result.handled = true;
      result.dialog = spec;
      return result;
    }
    return result;   // handled = false
  }

  /**
   * 上游"设为默认下载标签"的列表点击：
   * `which == 0` → 关掉默认标签（`putHasDefaultDownloadLabel(false)`，**不写 label**）；
   * `which == 1` → `label = null`；否则 `label = items[which]`。
   */
  onDefaultLabelSelected(spec: DefaultLabelDialogSpec, which: number): DefaultLabelChoice {
    const choice: DefaultLabelChoice = new DefaultLabelChoice();
    if (which === 0) {
      this.settings.putHasDefaultDownloadLabel(false);
      choice.hasDefault = false;
      return choice;
    }
    this.settings.putHasDefaultDownloadLabel(true);
    let label: string | null = null;
    if (which !== 1) {
      label = which < spec.items.length ? spec.items[which] : null;
    }
    this.settings.putDefaultDownloadLabel(label);
    choice.hasDefault = true;
    choice.defaultLabel = label;
    return choice;
  }

  /**
   * 上游 `createView()` / `updateDownloadLabels()` 里**完全重复**的列表构建（见「关键行为」6）：
   * `labels = [默认名称] + 所有标签`；第 0 项条目数 = `getDefaultDownloadInfoList().size()`，
   * 其余 = `getLabelCount(label)`。
   */
  buildLabelItems(): DownloadLabelItem[] {
    const result: DownloadLabelItem[] = [];
    const dm: LabelDrawManager | null = this.host.getDownloadManager();
    if (dm === null) {
      return result;
    }
    const list: DownloadLabel[] = dm.getLabelList();
    const labels: string[] = [];
    // 第 0 位是"默认标签名"
    labels.push(this.host.resolveString(STR_DEFAULT_LABEL_NAME));
    for (let i = 0; i < list.length; i++) {
      labels.push(labelText(list[i]));
    }
    for (let i = 0; i < labels.length; i++) {
      const label: string = labels[i];
      if (i === 0) {
        result.push(new DownloadLabelItem(label, dm.getDefaultDownloadCount()));
        continue;
      }
      result.push(new DownloadLabelItem(label, dm.getLabelCount(label)));
    }
    return result;
  }

  /**
   * 上游点击列表项：
   * ① **搜索中 → Toast 并 return**（见「关键行为」3）
   * ② `position == 0 → label = null`
   * ③ **`!equal(label, scene.mLabel)` 才动作**（连抽屉都不关，见「关键行为」4）
   * ④ 动作：`mLabel = label` → `updateForLabel()` → `searchKey` 非空 ? `startSearching()` : `updateView()`
   * ⑤ `closeDrawer(Gravity.RIGHT)`
   * @returns 是否真的切换了标签
   */
  onItemClick(position: number, items: DownloadLabelItem[]): boolean {
    if (this.host.isSearching()) {
      this.host.showToast(STR_DOWNLOAD_SEARCHING);
      return false;
    }
    if (position < 0 || position >= items.length) {
      return false;
    }
    let label: string | null = null;
    if (position !== 0) {
      label = items[position].label;
    }
    // 上游：if (!ObjectUtils.equal(label, scene.mLabel)) { ... }
    if (label === this.host.getCurrentLabel()) {
      return false;   // 相等 → 什么都不做（含不关抽屉）
    }
    this.host.setCurrentLabel(label);
    this.host.updateForLabel();
    const key: string | null = this.host.getSearchKey();
    if (key !== null && key.length > 0) {
      this.host.startSearching();
    } else {
      this.host.updateView();
    }
    this.host.closeDrawer();
    return true;
  }
}

/** 菜单点击结果（`handled` + 可能的对话框） */
export class MenuClickResult {
  handled: boolean = false;
  dialog: DefaultLabelDialogSpec | null = null;
}

/** `DownloadLabel.getLabel()` 可能为 null → 归一成空串 */
function labelText(l: DownloadLabel): string {
  const v: string | null = l.getLabel();
  return v === null ? '' : v;
}
