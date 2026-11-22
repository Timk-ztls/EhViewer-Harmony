/*
 * 上游：app/src/main/java/com/hippo/ehviewer/ui/scene/download/DownloadLabelsScene.java
 *       （inventory S0219，上游实际 394 行；清单登记 338 行）
 * 目标：harmony/entry/src/main/ets/hippo/ehviewer/ui/scene/download/DownloadLabelsScene.ets
 *
 * 背景：**下载标签管理页**。列表支持：点标签 → 重命名、点删除按钮 → 删除（带确认）、
 * 拖拽手柄 → 调整顺序；菜单"添加" → 新建标签。三个对话框（新建/重命名/删除确认）都有
 * "空/等于默认名/已存在"三重校验。
 *
 * ── 上游行为逐条对照 ────────────────────────────────────────────────────────
 * `class DownloadLabelsScene extends ToolbarScene`
 *   字段：`public List<DownloadLabel> mList`（**public 且 onCreate 里就取**）、`mRecyclerView` / `mViewTransition` / `mAdapter`
 *   `onCreate` → `mList = EhApplication.getDownloadManager(context).getLabelList()`
 *   `onDestroy` → `mList = null`（**不留引用**）
 *   `onCreateView3`:
 *     · `scene_label_list` → `recyclerView = R.id.recycler_view`、`tip = R.id.tip`
 *     · `mViewTransition = new ViewTransition(mRecyclerView, tip)` —— **注意：这里是 recyclerView 与 tip**（HistoryScene 是 content/tip）
 *     · `tip` drawable = `@drawable/big_label`（图标在顶）+ `tip.setText(@string/no_download_label)`
 *     · 拖拽：`RecyclerViewDragDropManager` + `shadow_8dp` 拖拽阴影
 *     · `adapter.setHasStableIds(true)`（**稳定 id = 标签 id**）→ `dragDropManager.createWrappedAdapter(adapter)`
 *     · `LinearLayoutManager`（**线性，不是网格**）；`SwipeDismissItemAnimator`
 *     · `updateView()`
 *   `onViewCreated` → `setTitle(@string/download_labels)` + 返回图标 `v_arrow_left_dark_x24`
 *   `onDestroyView` → `recyclerView.stopScroll()` → 三段置 null
 *   `onNavigationClick` → `onBackPressed()`
 *   `getMenuResId()` → `R.menu.scene_download_label`
 *   `onMenuItemClick(item)` → `R.id.action_add`：弹 `EditTextDialogBuilder`（title=`@string/new_label_title`，
 *     hint=`@string/download_labels`）→ `NewLabelDialogHelper`
 *     **注意：`action_add` 分支结尾是 `break`，函数最后 `return false`** —— 即**已处理也返回 false**
 *     （与 HistoryScene 的 `return true` 相反，照搬）
 *   `updateView()`：`mViewTransition != null` 时，`mList != null && mList.size() > 0` → `showView(0)`；否则 `showView(1)`
 *
 *   `NewLabelDialogHelper.onClick`（正按钮）——**三重校验，顺序固定**：
 *     ① `TextUtils.isEmpty(text)` → `setError(@string/label_text_is_empty)`
 *     ② `getString(@string/default_download_label_name).equals(text)` → `setError(@string/label_text_is_invalid)`
 *     ③ `downloadManager.containLabel(text)` → `setError(@string/label_text_exist)`
 *     ④ 否则：`setError(null)` → `dialog.dismiss()` → `downloadManager.addLabel(text)`
 *        → `mAdapter.notifyItemInserted(mList.size() - 1)`（**用 size-1，因为 addLabel 已把新项加进 list**）
 *        → 再按 `mList.size() > 0` 切视图
 *
 *   `RenameLabelDialogHelper.onClick`：**前三步与新建完全相同**（同一套错误文案），
 *     ④ 否则 `downloadManager.renameLabel(mOriginalLabel, text)` → `notifyItemChanged(mPosition)`
 *
 *   `LabelHolder`（label / dragHandler / delete 三个视图）+ `onClick`：
 *     · `position = getAdapterPosition()`；`context/mList/mRecyclerView` 任一 null → return
 *     · 点的是 `label` → 弹性重命名对话框（初值 = `raw.getLabel()`，title=`@string/rename_label_title`）
 *     · 点的是 `delete` → 确认对话框（title=`@string/delete_label_title`，
 *       message=`getString(@string/delete_label_message, label.getLabel())` 带占位参数）
 *       → 正按钮 `downloadManager.deleteLabel(label.getLabel())`
 *       → **`onDismiss` 里**才 `notifyDataSetChanged()` + `updateView()`
 *       （不是在 onClick 里 —— 删除结果是异步的，等对话框关闭再刷新）
 *
 *   `LabelAdapter`:
 *     · `getItemId` → `mList.get(position).getId()`（**稳定 id = 标签 id**，null 时 0）
 *     · `onBindViewHolder` → `holder.label.setText(mList.get(position).getLabel())`
 *     · `onCheckCanStartDrag` → `ViewUtils.isViewUnder(dragHandler, x, y, 0)`
 *       —— **只有按住拖拽手柄才开始拖**（按标签文字不能拖）
 *     · `onGetItemDraggableRange` → **null**（不限制范围）
 *     · `onMoveItem(from, to)` → `from == to` **直接 return**；否则 `downloadManager.moveLabel(from, to)`
 *     · `onCheckCanDrop` → **恒 true**
 *     · `onItemDragStarted` / `onItemDragFinished` → **空实现**
 *
 * ── 关键行为（照搬，别"顺手修"）──────────────────────────────────────────────
 * 1. **`action_add` 分支 `break` 后落到 `return false`** —— 已处理也返回 false（上游如此）。
 * 2. **新建/重命名共用同一套三重校验与文案**（空 → 默认名 → 已存在），顺序不能换：
 *    先判空再判默认名，否则空串会被当成"不是默认名"放过。
 * 3. **`notifyItemInserted(mList.size() - 1)`** —— `addLabel` 已经把新标签加进 `mList`，
 *    所以新项下标是 `size - 1`（若先 notify 再 add，会少一行）。
 * 4. **删除后的刷新在 `onDismiss` 里**，不在正按钮回调里（见上）。
 * 5. **`onMoveItem` 里 `from == to` 直接 return**（拖回原位不产生 DB 写）。
 * 6. **只有按住 `dragHandler` 才能拖**（`isViewUnder(dragHandler, x, y, 0)`）。
 * 7. **`getItemId` 用标签 id 而不是位置** —— 拖拽/插入/删除时动画才不串行。
 * 8. `tip` 的文案是 `@string/no_download_label`，图标 `@drawable/big_label`（图标在**顶部**）。
 *
 * ── 平台差异（依赖倒置 + ArkUI 载体）────────────────────────────────────────
 * 1. **`ToolbarScene` 未落地** → `LabelsSceneHost`（列表读/四种标签操作/四种对话框宿主能力/返回/提示）。
 * 2. **`ViewTransition(recyclerView, tip)`** → `updateView()` 返回 **0/1**（照搬语义），由页面层渲染。
 * 3. **`EditTextDialogBuilder` → 本仓库 `EditTextDialogSpec`（`hippo/app/DialogSpecs.ets`）**：
 *    它是**纯数据**（`text` / `hint` / `error` / `ready`），没有 `show()`。
 *    所以本文件产出/更新 spec（`setError` 等价于写 `spec.error`），"弹窗"由页面层执行。
 * 4. **`RecyclerViewDragDropManager`** → ArkUI `List` 的 `onItemDrag*` + `ListItem.dragPreview`；
 *    本文件只产出**拖拽判定**（`canStartDrag(position, onHandler)`）与**移动决策**（`onMoveItem`）。
 * 5. **`TextUtils.isEmpty`** → `text.length === 0`（上游 `isEmpty` 对 null 也 true；本文件入参已归一成 string）。
 * 6. **`getString(R.string.delete_label_message, label)`** 带占位参数 → 本文件产出 `messageArgs`，
 *    由页面层做 `%1$s` 替换（ArkTS 侧字符串资源不支持参数化，见 D-061 的同类处理）。
 *
 * ── 依赖实测（本仓已存在）──────────────────────────────────────────────────
 * `DownloadLabel`（`getId()` / `getLabel()`）、`DownloadManager` 的
 * `getLabelList()` / `containLabel(label)` / `addLabel(label)` / `renameLabel(from,to)` /
 * `deleteLabel(label)` / `moveLabel(from,to)`（后四个均 async）、
 * `EditTextDialogSpec`、`hippo/ui/layout/scene_label_list.ets`、`hippo/ui/drawable/big_label.ets`、
 * 以及 10 个字符串键（`download_labels` / `new_label_title` / `rename_label_title` / `delete_label_title` /
 * `delete_label_message` / `label_text_is_empty` / `label_text_is_invalid` / `label_text_exist` /
 * `no_download_label` / `default_download_label_name`）—— **实测全部已在 `strings.json`**。
 *
 * ── 缺口（已登记，不假装有）──────────────────────────────────────────────────
 * `item_download_label` 布局**没有独立文件**（只在 `dialog_torrent_list.ets` 的注释里被提及）→
 * 记 `TODO(ui-scene)`，本文件不渲染布局，只产出绑定数据。
 */

import { DownloadLabel } from '../../../dao/DownloadLabel';
import { EditTextDialogSpec } from '../../../../app/DialogSpecs';
import { ToolbarLogic, ContentViewToken } from '../ToolbarScene';

/** 上游 `R.layout.scene_label_list` */
export const LAYOUT_SCENE_LABEL_LIST: string = 'scene_label_list';
/** 上游 `R.menu.scene_download_label` */
export const MENU_SCENE_DOWNLOAD_LABEL: string = 'menu/scene_download_label';

/** 上游 R.drawable.v_arrow_left_dark_x24 */
export const DRAWABLE_BACK: string = 'v_arrow_left_dark_x24';
/** 上游 `R.id.action_add` */
export const ACTION_ADD: string = 'action_add';
/** 上游 `@string/download_labels`（标题/hint 共用） */
export const TITLE_DOWNLOAD_LABELS: string = 'app.string.download_labels';
/** 上游 `@string/new_label_title` / `@string/rename_label_title` / `@string/delete_label_title` */
export const TITLE_NEW_LABEL: string = 'app.string.new_label_title';
export const TITLE_RENAME_LABEL: string = 'app.string.rename_label_title';
export const TITLE_DELETE_LABEL: string = 'app.string.delete_label_title';
/** 上游 `@string/delete_label_message`（带 `%1$s` 占位） */
export const MESSAGE_DELETE_LABEL: string = 'app.string.delete_label_message';
/** 三重校验的三条错误文案（**顺序即判据顺序**） */
export const ERROR_LABEL_EMPTY: string = 'app.string.label_text_is_empty';
export const ERROR_LABEL_INVALID: string = 'app.string.label_text_is_invalid';
export const ERROR_LABEL_EXIST: string = 'app.string.label_text_exist';
/** 上游 `@string/no_download_label` */
export const TIP_NO_LABEL: string = 'app.string.no_download_label';
/** 上游 `@string/default_download_label_name`（**不允许用户把标签命名成这个**） */
export const DEFAULT_LABEL_NAME_KEY: string = 'app.string.default_download_label_name';
/** 上游 `@drawable/big_label` */
export const DRAWABLE_BIG_LABEL: string = 'big_label';

/** `ViewTransition` 的两个视图索引：0 = 列表、1 = tip（上游 `showView(0/1)`） */
export const VIEW_LIST: number = 0;
export const VIEW_TIP: number = 1;

/**
 * 本页宿主能力（`ToolbarScene` + `DownloadManager` + 对话框 + 提示）。
 * 见「平台差异」1/3/4。
 */
export interface LabelsSceneHost {
  /** 上游 `EhApplication.getDownloadManager(context).getLabelList()` */
  getLabelList(): DownloadLabel[];
  /** 上游 `containLabel(text)` */
  containLabel(text: string): boolean;
  /** 上游 `addLabel(text)`（async；完成后 list 里已含新项） */
  addLabel(text: string): Promise<void>;
  /** 上游 `renameLabel(mOriginalLabel, text)` */
  renameLabel(from: string, to: string): Promise<void>;
  /** 上游 `deleteLabel(label)` */
  deleteLabel(label: string): Promise<void>;
  /** 上游 `moveLabel(fromPosition, toPosition)` */
  moveLabel(from: number, to: number): Promise<void>;
  /** 上游 `@string/default_download_label_name` 的**已解析文本**（用于"不能与默认名相同"的比较） */
  getDefaultLabelName(): string;
  /** 上游 `@string/delete_label_message` 的占位替换结果 */
  formatDeleteLabelMessage(label: string): string;
  onBackPressed(): void;
}

/** 一次"新建/重命名"校验的结果：要么给错误文案，要么通过 */
export class LabelValidation {
  /** null = 校验通过 */
  error: string | null = null;

  static ok(): LabelValidation {
    return new LabelValidation();
  }

  static fail(errorKey: string): LabelValidation {
    const v: LabelValidation = new LabelValidation();
    v.error = errorKey;
    return v;
  }

  isValid(): boolean {
    return this.error === null;
  }
}

/** 列表项绑定数据（上游 `LabelHolder` 的 label 文本 + 稳定 id） */
export class LabelItemViewModel {
  id: number = 0;
  label: string = '';
}

export class DownloadLabelsScene {
  private host: LabelsSceneHost;
  /**
   * ★ 接线到 `ToolbarScene` 的**共用状态机**（组合而非继承，见 D-0xx）：
   * 本类是无视图的逻辑类（不继承 `BaseScene`），所以不 `extends ToolbarScene`，
   * 而是复用它的 `ToolbarLogic` —— 四步装配（补标题 / inflate 菜单 / 挂导航 / 挂点击）
   * 与 `mTempTitle` 延迟语义全部来自基类同一份实现，不再在各 Scene 里各写一套。
   */
  private toolbar: ToolbarLogic = new ToolbarLogic((key: string): string => key);
  /** 上游 `public List<DownloadLabel> mList` */
  private list: DownloadLabel[] | null = null;

  constructor(host: LabelsSceneHost) {
    this.host = host;
  }

  /** 上游 `onCreate()`：`mList = downloadManager.getLabelList()` */
  onCreate(): void {
    this.list = this.host.getLabelList();
  }

  /** 上游 `onDestroy()`：`mList = null` */
  onDestroy(): void {
    this.list = null;
  }

  /** 上游 `getMenuResId()` */
  getMenuResId(): string {
    return MENU_SCENE_DOWNLOAD_LABEL;
  }

  /**
   * 上游 `onViewCreated()` 的两步（标题 + 返回图标），**改走共用 ToolbarLogic**：
   *   `setTitle(@string/download_labels)` + `setNavigationIcon(v_arrow_left_dark_x24)`
   * ★ 注意本类可能先 `setTitle` 后 `attach`（上游的顺序问题）—— `ToolbarLogic` 的
   *   `mTempTitle` 延迟语义正是为此存在，所以这里**必须先 attach 再 setTitle**，
   *   而"先 setTitle"的调用方也会被正确暂存（这正是接线后得到的行为）。
   */
  onViewCreated(): void {
    // 挂上 toolbar（本类无真实视图，用 token 表达"toolbar 已就绪"）
    this.toolbar.attachView(new ContentViewToken('DownloadLabelsScene'));
    this.toolbar.setTitleRes(TITLE_DOWNLOAD_LABELS);
    this.toolbar.setNavigationIcon(DRAWABLE_BACK);
  }

  /** 供页面层取当前 toolbar 状态（标题 / 导航图标 / 已 inflate 的菜单） */
  getToolbarTitle(): string | null {
    const tb = this.toolbar.getToolbar();
    return tb === null ? this.toolbar.getTempTitle() : tb.title;
  }

  /** 上游 `onNavigationClick` */
  onNavigationClick(): void {
    this.host.onBackPressed();
  }

  /**
   * 上游 `updateView()`：`mList != null && size > 0` → `showView(0)`；否则 `showView(1)`。
   * （上游外层还有 `mViewTransition != null` 判断；本实现无该概念，等价于恒真）
   */
  updateView(): number {
    const list: DownloadLabel[] | null = this.list;
    if (list !== null && list.length > 0) {
      return VIEW_LIST;
    }
    return VIEW_TIP;
  }

  /** 上游 `LabelAdapter.getItemCount()` */
  getItemCount(): number {
    return this.list === null ? 0 : this.list.length;
  }

  /** 上游 `getItemId(position)` → `mList.get(position).getId()`；**null 时 0**（上游如此） */
  getItemId(position: number): number {
    const list: DownloadLabel[] | null = this.list;
    if (list === null || position < 0 || position >= list.length) {
      return 0;
    }
    const id: number | null = list[position].getId();
    return id === null ? 0 : id;
  }

  /** 上游 `onBindViewHolder` → `holder.label.setText(mList.get(position).getLabel())` */
  bindItem(position: number): LabelItemViewModel | null {
    const list: DownloadLabel[] | null = this.list;
    if (list === null || position < 0 || position >= list.length) {
      return null;
    }
    const vm: LabelItemViewModel = new LabelItemViewModel();
    vm.id = this.getItemId(position);
    const label: string | null = list[position].getLabel();
    vm.label = label === null ? '' : label;
    return vm;
  }

  /**
   * 上游 `onMenuItemClick(action_add)` 的对话框描述：
   * `EditTextDialogBuilder(context, null, @string/download_labels)` + title `@string/new_label_title`。
   * **注意返回值**：上游该分支 `break` 后落到 `return false`（见「关键行为」1）——
   * 所以 `onMenuItemClick` 返回 false，而**对话框描述由本方法单独给出**。
   */
  buildNewLabelDialog(): EditTextDialogSpec {
    const spec: EditTextDialogSpec = new EditTextDialogSpec(null, TITLE_DOWNLOAD_LABELS);
    spec.title = TITLE_NEW_LABEL;
    return spec;
  }

  /** 上游 `onMenuItemClick(item)`：**只有 action_add 会弹对话框，但函数仍返回 false** */
  onMenuItemClick(itemId: string): boolean {
    if (itemId === ACTION_ADD) {
      this.pendingNewDialog = this.buildNewLabelDialog();
      // 上游：case action_add: { ... } break; } → return false;
      return false;
    }
    return false;
  }

  /** 待弹出的"新建"对话框（null = 未弹） */
  private pendingNewDialog: EditTextDialogSpec | null = null;

  /** 页面层取"新建"对话框描述 */
  getNewLabelDialog(): EditTextDialogSpec | null {
    return this.pendingNewDialog;
  }

  /**
   * **新建/重命名共用的三重校验**（见「关键行为」2）：
   * ① 空 → `label_text_is_empty`
   * ② 等于默认标签名 → `label_text_is_invalid`
   * ③ 已存在 → `label_text_exist`
   * ④ 否则通过
   */
  validateLabelText(text: string): LabelValidation {
    if (text.length === 0) {
      return LabelValidation.fail(ERROR_LABEL_EMPTY);
    }
    if (text === this.host.getDefaultLabelName()) {
      return LabelValidation.fail(ERROR_LABEL_INVALID);
    }
    if (this.host.containLabel(text)) {
      return LabelValidation.fail(ERROR_LABEL_EXIST);
    }
    return LabelValidation.ok();
  }

  /**
   * 上游 `NewLabelDialogHelper.onClick`（正按钮）：
   * 校验 → 通过则 `setError(null)` + `dismiss()` + `addLabel(text)` + `notifyItemInserted(size - 1)` + 切视图。
   * @returns true = 已创建（对话框应关闭）
   */
  async confirmNewLabel(spec: EditTextDialogSpec): Promise<boolean> {
    const text: string = spec.getText();
    const v: LabelValidation = this.validateLabelText(text);
    spec.error = v.error;
    if (!v.isValid()) {
      return false;   // 上游：只 setError，不关对话框
    }
    await this.host.addLabel(text);
    // 上游：mList 已被 addLabel 更新（追加到末尾），新项下标 = size - 1
    this.list = this.host.getLabelList();
    this.pendingNewDialog = null;
    this.lastInsertedIndex = this.list.length - 1;
    this.updateView();
    return true;
  }

  /** 最近一次插入的下标（上游 `notifyItemInserted(mList.size() - 1)`，测试观测用） */
  private lastInsertedIndex: number = -1;

  getLastInsertedIndex(): number {
    return this.lastInsertedIndex;
  }

  /**
   * 上游 `LabelHolder.onClick` 点 **label** 的分支：弹重命名对话框
   * （初值 = 当前标签名，title = `@string/rename_label_title`）。
   */
  buildRenameDialog(position: number): EditTextDialogSpec | null {
    const list: DownloadLabel[] | null = this.list;
    if (list === null || position < 0 || position >= list.length) {
      return null;
    }
    const raw: DownloadLabel = list[position];
    const original: string | null = raw.getLabel();
    const spec: EditTextDialogSpec = new EditTextDialogSpec(original, TITLE_DOWNLOAD_LABELS);
    spec.title = TITLE_RENAME_LABEL;
    this.pendingRename = new PendingRename(current2string(original), position);
    return spec;
  }

  private pendingRename: PendingRename | null = null;

  /**
   * 上游 `RenameLabelDialogHelper.onClick`：**校验与新建完全相同**，
   * 通过后 `renameLabel(mOriginalLabel, text)` → `notifyItemChanged(mPosition)`。
   */
  async confirmRename(spec: EditTextDialogSpec): Promise<boolean> {
    const pending: PendingRename | null = this.pendingRename;
    if (pending === null) {
      return false;
    }
    const text: string = spec.getText();
    const v: LabelValidation = this.validateLabelText(text);
    spec.error = v.error;
    if (!v.isValid()) {
      return false;
    }
    await this.host.renameLabel(pending.original, text);
    this.list = this.host.getLabelList();
    this.pendingRename = null;
    this.lastChangedIndex = pending.position;
    return true;
  }

  private lastChangedIndex: number = -1;

  getLastChangedIndex(): number {
    return this.lastChangedIndex;
  }

  /**
   * 上游 `LabelHolder.onClick` 点 **delete** 的分支：确认对话框描述。
   * title = `@string/delete_label_title`，message = `getString(@string/delete_label_message, label)`。
   */
  buildDeleteDialog(position: number): DeleteLabelDialogSpec | null {
    const list: DownloadLabel[] | null = this.list;
    if (list === null || position < 0 || position >= list.length) {
      return null;
    }
    const label: string | null = list[position].getLabel();
    const text: string = current2string(label);
    const spec: DeleteLabelDialogSpec = new DeleteLabelDialogSpec();
    spec.titleKey = TITLE_DELETE_LABEL;
    spec.messageKey = MESSAGE_DELETE_LABEL;
    spec.message = this.host.formatDeleteLabelMessage(text);
    this.pendingDelete = new PendingDelete(text);
    return spec;
  }

  private pendingDelete: PendingDelete | null = null;

  /**
   * 上游删除确认正按钮：`deleteLabel(label)` —— **只删，不刷新**；
   * 刷新在 `onDeleteDialogDismiss()` 里（见「关键行为」4）。
   */
  async confirmDelete(): Promise<boolean> {
    const pending: PendingDelete | null = this.pendingDelete;
    if (pending === null) {
      return false;
    }
    await this.host.deleteLabel(pending.label);
    return true;
  }

  /**
   * 上游 `setOnDismissListener`：`notifyDataSetChanged()` + `updateView()`
   * —— **删除结果在这里才反映到界面**（见「关键行为」4）。
   */
  onDeleteDialogDismiss(): void {
    this.pendingDelete = null;
    this.list = this.host.getLabelList();
    this.updateView();
  }

  /**
   * 上游 `onCheckCanStartDrag(holder, position, x, y)`：
   * `ViewUtils.isViewUnder(holder.dragHandler, x, y, 0)` —— **只有按住拖拽手柄可拖**。
   */
  canStartDrag(onDragHandler: boolean): boolean {
    return onDragHandler;
  }

  /** 上游 `onGetItemDraggableRange(...)` → **null**（不限制拖动范围） */
  getItemDraggableRange(): null {
    return null;
  }

  /** 上游 `onCheckCanDrop(dragPosition, dropPosition)` → **恒 true** */
  canDrop(): boolean {
    return true;
  }

  /**
   * 上游 `onMoveItem(from, to)`：`from == to` **直接 return**（见「关键行为」5）；
   * 否则 `moveLabel(from, to)`。
   * @returns true = 产生了移动（已写 DB）
   */
  async onMoveItem(from: number, to: number): Promise<boolean> {
    // 上游先判 context == null（本实现 host 恒存在），再判 from == to
    if (from === to) {
      return false;
    }
    const list: DownloadLabel[] | null = this.list;
    if (list === null || from < 0 || to < 0 || from >= list.length || to >= list.length) {
      return false;
    }
    await this.host.moveLabel(from, to);
    this.list = this.host.getLabelList();
    return true;
  }

  /** 上游 `onItemDragStarted` / `onItemDragFinished` → **空实现**（照搬） */
  onItemDragStarted(position: number): void {
  }

  onItemDragFinished(from: number, to: number, result: boolean): void {
  }

  /** 当前列表（只读副本） */
  getList(): DownloadLabel[] {
    return this.list === null ? [] : this.list.slice();
  }
}

/** 上游 `getLabel()` 返回可空；ArkTS 侧归一成 string（`null → ''`） */
function current2string(v: string | null): string {
  return v === null ? '' : v;
}

/** 删除确认对话框描述（title + 已替换占位的 message） */
export class DeleteLabelDialogSpec {
  titleKey: string = TITLE_DELETE_LABEL;
  messageKey: string = MESSAGE_DELETE_LABEL;
  /** `getString(@string/delete_label_message, label)` 的结果（见「平台差异」6） */
  message: string = '';
}

/** 待执行的重命名（上游用构造参数捕获 originalLabel + position） */
class PendingRename {
  original: string;
  position: number;

  constructor(original: string, position: number) {
    this.original = original;
    this.position = position;
  }
}

/** 待执行的删除 */
class PendingDelete {
  label: string;

  constructor(label: string) {
    this.label = label;
  }
}

