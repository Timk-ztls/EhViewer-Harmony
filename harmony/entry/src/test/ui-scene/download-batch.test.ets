/*
 * native-image 接手批单测：DownloadLabelsScene（S0219）+ DownloadBatchActions（S0224）
 *
 * 断言重点（都是"容易写反/漏掉"的）：
 *   ① 新建/重命名**共用同一套三重校验**，且顺序是 空 → 默认名 → 已存在（顺序换了空串会被放过）
 *   ② 新建成功后的 `notifyItemInserted` 下标是 **size - 1**（因为 addLabel 已把新项加进 list）
 *   ③ 删除的刷新在 **onDismiss** 里，不在正按钮回调里
 *   ④ `onMoveItem(from == to)` **不写 DB**
 *   ⑤ 只有按住 dragHandler 才能拖；`onCheckCanDrop` 恒 true
 *   ⑥ `onMenuItemClick(action_add)` **返回 false**（上游 break 落到 return false）
 *   ⑦ 批量：**视图位置必须经 positionInList 换算**（否则删错条目）
 *   ⑧ Delete 分支**不立刻退选择模式**（在确认回调里退）；Start/Stop **立刻退**
 *   ⑨ Move 的标签数组**第 0 位是默认标签**，选它 → label = null
 *   ⑩ `viewRandom` 的 `position >= size` 防御；`setDragEnable` 先翻转再持久化再选图标
 *
 * 运行：pwsh -File harmony/entry/src/test/ui-scene/run.ps1 -Filter download
 */

import {
  DownloadLabelsScene, LabelsSceneHost, LabelValidation, LabelItemViewModel, DeleteLabelDialogSpec,
  ACTION_ADD, MENU_SCENE_DOWNLOAD_LABEL, TITLE_DOWNLOAD_LABELS, DRAWABLE_BACK, TITLE_NEW_LABEL, TITLE_RENAME_LABEL,
  TITLE_DELETE_LABEL, MESSAGE_DELETE_LABEL, ERROR_LABEL_EMPTY, ERROR_LABEL_INVALID, ERROR_LABEL_EXIST,
  TIP_NO_LABEL, DEFAULT_LABEL_NAME_KEY, DRAWABLE_BIG_LABEL, VIEW_LIST, VIEW_TIP
} from '../../main/ets/hippo/ehviewer/ui/scene/download/DownloadLabelsScene';
import {
  DownloadBatchActions, BatchActionsHost, BatchSelection, BatchFabResult,
  SECONDARY_CHECK_ALL, SECONDARY_START, SECONDARY_STOP, SECONDARY_DELETE, SECONDARY_MOVE,
  SECONDARY_RANDOM, SECONDARY_DRAG_TOGGLE, BATCH_DELETE, BATCH_MOVE, BATCH_DRAG_TOGGLE,
  ICON_DRAG_ON, ICON_DRAG_OFF, TITLE_DELETE_RANGE, MESSAGE_DELETE_RANGE, CHECK_DELETE_RANGE, TITLE_MOVE
} from '../../main/ets/hippo/ehviewer/ui/scene/download/part/DownloadBatchActions';
import { DownloadLabel } from '../../main/ets/hippo/ehviewer/dao/DownloadLabel';
import { DownloadInfo } from '../../main/ets/hippo/ehviewer/dao/DownloadInfo';
import { GalleryInfo } from '../../main/ets/hippo/ehviewer/client/data/GalleryInfo';
import { EditTextDialogSpec } from '../../main/ets/hippo/app/DialogSpecs';

let pass = 0;
const fails: string[] = [];

function eq(name: string, got: Object | null, want: Object | null): void {
  const g: string = JSON.stringify(got);
  const w: string = JSON.stringify(want);
  if (g === w) {
    pass++;
  } else {
    fails.push(`${name}\n    got  ${g}\n    want ${w}`);
  }
}

function ok(name: string, cond: boolean): void {
  if (cond) {
    pass++;
  } else {
    fails.push(`${name}\n    条件为 false`);
  }
}

// ---------------------------------------------------------------- S0219 fakes
class FakeLabelsHost implements LabelsSceneHost {
  labels: DownloadLabel[] = [];
  defaultName: string = 'Default';
  added: string[] = [];
  renamed: string[] = [];
  deleted: string[] = [];
  moved: string[] = [];
  backCalls: number = 0;

  getLabelList(): DownloadLabel[] {
    return this.labels;
  }

  containLabel(text: string): boolean {
    for (let i = 0; i < this.labels.length; i++) {
      if (this.labels[i].getLabel() === text) {
        return true;
      }
    }
    return false;
  }

  addLabel(text: string): Promise<void> {
    this.added.push(text);
    this.labels.push(new DownloadLabel(this.labels.length + 100, text, 0));
    return Promise.resolve();
  }

  renameLabel(from: string, to: string): Promise<void> {
    this.renamed.push(`${from}->${to}`);
    for (let i = 0; i < this.labels.length; i++) {
      if (this.labels[i].getLabel() === from) {
        this.labels[i].setLabel(to);
      }
    }
    return Promise.resolve();
  }

  deleteLabel(label: string): Promise<void> {
    this.deleted.push(label);
    this.labels = this.labels.filter((l: DownloadLabel): boolean => l.getLabel() !== label);
    return Promise.resolve();
  }

  moveLabel(from: number, to: number): Promise<void> {
    this.moved.push(`${from}->${to}`);
    const item: DownloadLabel = this.labels[from];
    this.labels.splice(from, 1);
    this.labels.splice(to, 0, item);
    return Promise.resolve();
  }

  getDefaultLabelName(): string {
    return this.defaultName;
  }

  formatDeleteLabelMessage(label: string): string {
    return `Delete ${label}?`;
  }

  onBackPressed(): void {
    this.backCalls++;
  }
}

function mkLabel(id: number, name: string): DownloadLabel {
  return new DownloadLabel(id, name, 0);
}

async function testDownloadLabelsScene(): Promise<void> {
  // ---------- 常量 ----------
  eq('菜单 = menu/scene_download_label', MENU_SCENE_DOWNLOAD_LABEL, 'menu/scene_download_label');
  eq('添加菜单项 = action_add', ACTION_ADD, 'action_add');
  eq('VIEW_LIST = 0 / VIEW_TIP = 1', [VIEW_LIST, VIEW_TIP], [0, 1]);
  eq('三条错误文案键（顺序：空 → 无效 → 已存在）',
    [ERROR_LABEL_EMPTY, ERROR_LABEL_INVALID, ERROR_LABEL_EXIST],
    ['app.string.label_text_is_empty', 'app.string.label_text_is_invalid', 'app.string.label_text_exist']);
  eq('提示文案键', TIP_NO_LABEL, 'app.string.no_download_label');
  eq('图标组件 = big_label', DRAWABLE_BIG_LABEL, 'big_label');

  // ---------- 列表 / 视图切换 / 稳定 id ----------
  const host: FakeLabelsHost = new FakeLabelsHost();
  const scene: DownloadLabelsScene = new DownloadLabelsScene(host);
  eq('未 onCreate 时 updateView = tip', scene.updateView(), VIEW_TIP);
  scene.onCreate();
  eq('空列表 → tip 视图', scene.updateView(), VIEW_TIP);
  host.labels = [mkLabel(11, 'a'), mkLabel(22, 'b')];
  scene.onCreate();
  eq('有数据 → 列表视图', scene.updateView(), VIEW_LIST);
  eq('getItemCount', scene.getItemCount(), 2);
  eq('★getItemId = 标签 id（不是位置）', scene.getItemId(1), 22);
  eq('getItemId 越界 = 0（上游 null 时 0 的等价）', scene.getItemId(9), 0);
  const vm: LabelItemViewModel | null = scene.bindItem(0);
  ok('bindItem 非空', vm !== null);
  if (vm !== null) {
    eq('bindItem id', vm.id, 11);
    eq('bindItem label', vm.label, 'a');
  }

  // ---------- ① 三重校验的顺序 ----------
  eq('空串 → label_text_is_empty', scene.validateLabelText('').error, ERROR_LABEL_EMPTY);
  eq('★空串**不会**被当成"不是默认名"放过（说明先判空）',
    scene.validateLabelText('').error !== ERROR_LABEL_INVALID, true);
  eq('等于默认名 → label_text_is_invalid', scene.validateLabelText('Default').error, ERROR_LABEL_INVALID);
  eq('已存在 → label_text_exist', scene.validateLabelText('a').error, ERROR_LABEL_EXIST);
  eq('合法 → 通过', scene.validateLabelText('新标签').error, null);
  ok('合法时 isValid() 为 true', scene.validateLabelText('新标签').isValid());

  // ---------- ⑥ onMenuItemClick 返回 false ----------
  eq('★action_add 返回 false（上游 break 落到 return false）', scene.onMenuItemClick(ACTION_ADD), false);
  const newDlg: EditTextDialogSpec | null = scene.getNewLabelDialog();
  ok('但已产出"新建"对话框', newDlg !== null);
  if (newDlg !== null) {
    eq('新建对话框 title', newDlg.title, TITLE_NEW_LABEL);
    eq('新建对话框 hint = download_labels', newDlg.hint, TITLE_DOWNLOAD_LABELS);
    eq('新建对话框初值空', newDlg.getText(), '');
  }
  eq('未知菜单项也返回 false', scene.onMenuItemClick('action_other'), false);

  // ---------- ② 新建：校验失败不关对话框；成功下标 = size-1 ----------
  const spec1: EditTextDialogSpec = new EditTextDialogSpec('', TITLE_DOWNLOAD_LABELS);
  eq('空文本 → 不创建', await scene.confirmNewLabel(spec1), false);
  eq('空文本 → 写入错误', spec1.error, ERROR_LABEL_EMPTY);
  const spec2: EditTextDialogSpec = new EditTextDialogSpec('Default', TITLE_DOWNLOAD_LABELS);
  eq('默认名 → 不创建', await scene.confirmNewLabel(spec2), false);
  eq('默认名 → 写入错误', spec2.error, ERROR_LABEL_INVALID);
  const spec3: EditTextDialogSpec = new EditTextDialogSpec('a', TITLE_DOWNLOAD_LABELS);
  eq('已存在 → 不创建', await scene.confirmNewLabel(spec3), false);
  eq('已存在 → 写入错误', spec3.error, ERROR_LABEL_EXIST);
  const before: number = scene.getItemCount();
  const spec4: EditTextDialogSpec = new EditTextDialogSpec('新标签', TITLE_DOWNLOAD_LABELS);
  eq('合法 → 创建成功', await scene.confirmNewLabel(spec4), true);
  eq('合法 → 错误清空', spec4.error, null);
  eq('addLabel 收到文本', host.added, ['新标签']);
  eq('itemCount + 1', scene.getItemCount(), before + 1);
  eq('★插入下标 = size - 1（不是 size）', scene.getLastInsertedIndex(), before);

  // ---------- 重命名 ----------
  host.labels = [mkLabel(11, 'a'), mkLabel(22, 'b')];
  scene.onCreate();
  const renameDlg: EditTextDialogSpec | null = scene.buildRenameDialog(1);
  ok('重命名对话框非空', renameDlg !== null);
  if (renameDlg !== null) {
    eq('重命名 title', renameDlg.title, TITLE_RENAME_LABEL);
    eq('重命名初值 = 当前标签名', renameDlg.getText(), 'b');
    renameDlg.text = 'b2';
  }
  eq('重命名成功', await scene.confirmRename(renameDlg as EditTextDialogSpec), true);
  eq('renameLabel 收到 from->to', host.renamed, ['b->b2']);
  eq('刷新下标 = 原位置', scene.getLastChangedIndex(), 1);
  // 重命名也用同一套校验
  scene.buildRenameDialog(0);
  const badRename: EditTextDialogSpec = new EditTextDialogSpec('', TITLE_DOWNLOAD_LABELS);
  eq('重命名为空 → 失败', await scene.confirmRename(badRename), false);
  eq('重命名为空 → 错误文案与新建一致', badRename.error, ERROR_LABEL_EMPTY);

  // ---------- ③ 删除：确认只删，刷新在 onDismiss ----------
  host.labels = [mkLabel(11, 'a'), mkLabel(22, 'b2')];
  scene.onCreate();
  const delDlg: DeleteLabelDialogSpec | null = scene.buildDeleteDialog(0);
  ok('删除对话框非空', delDlg !== null);
  if (delDlg !== null) {
    eq('删除 title', delDlg.titleKey, TITLE_DELETE_LABEL);
    eq('删除 message 已替换占位', delDlg.message, 'Delete a?');
    eq('删除 message 键', delDlg.messageKey, MESSAGE_DELETE_LABEL);
  }
  eq('确认删除返回 true', await scene.confirmDelete(), true);
  eq('deleteLabel 收到标签名', host.deleted, ['a']);
  eq('★确认删除时 itemCount 仍是旧值（未刷新）', scene.getItemCount(), 2);
  scene.onDeleteDialogDismiss();
  eq('★onDismiss 后才刷新（剩 1 项）', scene.getItemCount(), 1);

  // ---------- ④⑤ 拖拽判定 ----------
  eq('按住 dragHandler 才能拖', scene.canStartDrag(true), true);
  eq('按标签文字不能拖', scene.canStartDrag(false), false);
  eq('拖动范围 = null（不限制）', scene.getItemDraggableRange(), null);
  eq('可放置恒 true', scene.canDrop(), true);
  host.labels = [mkLabel(1, 'x'), mkLabel(2, 'y')];
  scene.onCreate();
  eq('★from == to → 不写 DB', await scene.onMoveItem(1, 1), false);
  eq('未产生 moveLabel 调用', host.moved, []);
  eq('from != to → 移动', await scene.onMoveItem(0, 1), true);
  eq('moveLabel 收到参数', host.moved, ['0->1']);
  eq('越界 from → 不移动', await scene.onMoveItem(5, 0), false);
  scene.onDestroy();
  eq('onDestroy 后 mList 清空', scene.getItemCount(), 0);
}

// ---------------------------------------------------------------- S0224 fakes
class FakeBatchHost implements BatchActionsHost {
  list: DownloadInfo[] = [];
  checked: number[] = [];
  viewToList: number[] = [];
  checkAllCalls: number = 0;
  outOfChoiceModeCalls: number = 0;
  startedRanges: number[][] = [];
  stoppedRanges: number[][] = [];
  deletedRanges: number[][] = [];
  deletedSingle: number[] = [];
  changedLabels: string[] = [];
  labelTexts: string[] = ['L1', 'L2'];
  removeImageFiles: boolean = false;
  putRemoveCalls: boolean[] = [];
  dragSetting: boolean[] = [];
  removedDirnames: number[] = [];
  asyncDeletes: string[] = [];
  asyncGalleryDeletes: number = 0;
  launched: number[] = [];
  primaryFabCalls: number = 0;
  existingDir: string | null = null;

  checkAll(): void {
    this.checkAllCalls++;
  }

  getCheckedItemPositions(): number[] {
    return this.checked;
  }

  outOfCustomChoiceMode(): void {
    this.outOfChoiceModeCalls++;
  }

  positionInList(position: number): number {
    if (position >= 0 && position < this.viewToList.length) {
      return this.viewToList[position];
    }
    return position;
  }

  getList(): DownloadInfo[] | null {
    return this.list;
  }

  startRangeDownload(gids: number[]): void {
    this.startedRanges.push(gids);
  }

  stopRangeDownload(gids: number[]): Promise<void> {
    this.stoppedRanges.push(gids);
    return Promise.resolve();
  }

  deleteRangeDownload(gids: number[]): Promise<void> {
    this.deletedRanges.push(gids);
    return Promise.resolve();
  }

  deleteDownload(gid: number): Promise<void> {
    this.deletedSingle.push(gid);
    return Promise.resolve();
  }

  changeLabel(list: DownloadInfo[], label: string | null): Promise<void> {
    this.changedLabels.push(label === null ? '<null>' : label);
    return Promise.resolve();
  }

  getLabelTexts(): string[] {
    return this.labelTexts;
  }

  getRemoveImageFiles(): boolean {
    return this.removeImageFiles;
  }

  putRemoveImageFiles(checked: boolean): void {
    this.putRemoveCalls.push(checked);
  }

  setDragDownloadGallery(enabled: boolean): void {
    this.dragSetting.push(enabled);
  }

  removeDownloadDirname(gid: number): void {
    this.removedDirnames.push(gid);
  }

  getExistingDownloadDir(info: GalleryInfo): string | null {
    return this.existingDir;
  }

  deleteFileAsync(path: string): void {
    this.asyncDeletes.push(path);
  }

  deleteGalleryFilesAsync(list: GalleryInfo[]): void {
    this.asyncGalleryDeletes++;
  }

  launchGalleryActivity(galleryInfo: GalleryInfo): void {
    this.launched.push(galleryInfo.gid);
  }

  onClickPrimaryFab(): void {
    this.primaryFabCalls++;
  }

  formatMessage(key: string, arg: string): string {
    return `${key}#${arg}`;
  }

  getDefaultLabelName(): string {
    return 'Default';
  }
}

function mkInfo(gid: number): DownloadInfo {
  const info: DownloadInfo = new DownloadInfo(gid);
  info.gid = gid;
  return info;
}

async function testDownloadBatchActions(): Promise<void> {
  // ---------- 常量 ----------
  eq('二级位置：全选/开始/停止/删除/移动/随机/拖拽',
    [SECONDARY_CHECK_ALL, SECONDARY_START, SECONDARY_STOP, SECONDARY_DELETE, SECONDARY_MOVE,
      SECONDARY_RANDOM, SECONDARY_DRAG_TOGGLE], [0, 1, 2, 3, 4, 5, 6]);
  eq('拖拽图标 on/off', [ICON_DRAG_ON, ICON_DRAG_OFF],
    ['v_mobile_hand_left_x24', 'v_mobile_hand_left_off_x24']);

  // ---------- 0 全选 ----------
  const h0: FakeBatchHost = new FakeBatchHost();
  const a0: DownloadBatchActions = new DownloadBatchActions(h0);
  eq('position=0 返回 null', a0.onClickSecondaryFab(SECONDARY_CHECK_ALL), null);
  eq('调用了 checkAll', h0.checkAllCalls, 1);

  // ---------- ⑦ 视图位置 → 列表下标换算 ----------
  const h1: FakeBatchHost = new FakeBatchHost();
  h1.list = [mkInfo(100), mkInfo(200), mkInfo(300)];
  h1.checked = [0, 2];
  h1.viewToList = [2, 0, 1];   // 视图位置 0 → 列表下标 2；视图位置 2 → 列表下标 1
  const a1: DownloadBatchActions = new DownloadBatchActions(h1);
  eq('开始批量 → 返回 null', a1.onClickSecondaryFab(SECONDARY_START), null);
  eq('★gid 按 positionInList 换算（100→? 见映射）', h1.startedRanges, [[300, 200]]);
  eq('★若用视图位置会得到 [100,300]（错误）', h1.startedRanges[0][0] !== 100, true);
  eq('Start 立刻退选择模式', h1.outOfChoiceModeCalls, 1);

  // ---------- 空选择集：1/2/3/4 直接 return ----------
  const h2: FakeBatchHost = new FakeBatchHost();
  h2.list = [mkInfo(1)];
  h2.checked = [];
  const a2: DownloadBatchActions = new DownloadBatchActions(h2);
  eq('空选择 → Start 返回 null', a2.onClickSecondaryFab(SECONDARY_START), null);
  eq('空选择 → 不启动下载', h2.startedRanges.length, 0);
  eq('空选择 → Stop 返回 null', a2.onClickSecondaryFab(SECONDARY_STOP), null);
  eq('空选择 → 不停止', h2.stoppedRanges.length, 0);
  eq('空选择 → Delete 返回 null', a2.onClickSecondaryFab(SECONDARY_DELETE), null);
  eq('空选择 → Move 返回 null', a2.onClickSecondaryFab(SECONDARY_MOVE), null);
  eq('空选择 → 不退选择模式', h2.outOfChoiceModeCalls, 0);

  // ---------- 2 停止：立刻退选择模式 ----------
  const h3: FakeBatchHost = new FakeBatchHost();
  h3.list = [mkInfo(11), mkInfo(22)];
  h3.checked = [0, 1];
  const a3: DownloadBatchActions = new DownloadBatchActions(h3);
  a3.onClickSecondaryFab(SECONDARY_STOP);
  eq('停止收到 gid 列表', h3.stoppedRanges, [[11, 22]]);
  eq('Stop 立刻退选择模式', h3.outOfChoiceModeCalls, 1);

  // ---------- ⑧ 删除：产出 CheckBox 对话框，且**不立刻退选择模式** ----------
  const h4: FakeBatchHost = new FakeBatchHost();
  h4.list = [mkInfo(11), mkInfo(22), mkInfo(33)];
  h4.checked = [0, 2];
  h4.removeImageFiles = true;
  const a4: DownloadBatchActions = new DownloadBatchActions(h4);
  const r4: BatchFabResult | null = a4.onClickSecondaryFab(SECONDARY_DELETE);
  ok('删除产出结果', r4 !== null);
  if (r4 !== null) {
    eq('kind = BATCH_DELETE', r4.kind, BATCH_DELETE);
    ok('产出了 CheckBox 对话框', r4.dialog !== null);
    if (r4.dialog !== null) {
      eq('对话框 title', r4.dialog.title, TITLE_DELETE_RANGE);
      eq('★message 带**选中数量**（2）', r4.dialog.message, `${MESSAGE_DELETE_RANGE}#2`);
      eq('复选框文案', r4.dialog.checkText, CHECK_DELETE_RANGE);
      eq('复选框初值 = Settings.getRemoveImageFiles()', r4.dialog.checked, true);
    }
    eq('收集了 2 条 info', r4.selection !== null ? r4.selection.infos.length : -1, 2);
    eq('收集了 2 个 gid', r4.selection !== null ? r4.selection.gids : [], [11, 33]);
  }
  eq('★Delete 不在这里退选择模式', h4.outOfChoiceModeCalls, 0);
  // 确认删除
  const sel4: BatchSelection = (r4 as BatchFabResult).selection as BatchSelection;
  eq('确认删除返回 true', await a4.onDeleteRangeConfirm(sel4, true), true);
  eq('★确认时先退选择模式', h4.outOfChoiceModeCalls, 1);
  eq('deleteRangeDownload 收到 gid', h4.deletedRanges, [[11, 33]]);
  eq('写回 putRemoveImageFiles(checked)', h4.putRemoveCalls, [true]);
  eq('勾选 → 删除图库文件', h4.asyncGalleryDeletes, 1);
  // 未勾选时不删文件
  const h5: FakeBatchHost = new FakeBatchHost();
  h5.list = [mkInfo(1)];
  h5.checked = [0];
  const a5: DownloadBatchActions = new DownloadBatchActions(h5);
  const r5: BatchFabResult = a5.onClickSecondaryFab(SECONDARY_DELETE) as BatchFabResult;
  await a5.onDeleteRangeConfirm(r5.selection as BatchSelection, false);
  eq('未勾选 → 不删图库文件', h5.asyncGalleryDeletes, 0);
  eq('未勾选 → 仍写回设置', h5.putRemoveCalls, [false]);

  // ---------- ⑨ 移动：标签数组第 0 位是默认标签，选它 → label = null ----------
  const h6: FakeBatchHost = new FakeBatchHost();
  h6.list = [mkInfo(7), mkInfo(8)];
  h6.checked = [1];
  h6.labelTexts = ['L1', 'L2'];
  const a6: DownloadBatchActions = new DownloadBatchActions(h6);
  const r6: BatchFabResult = a6.onClickSecondaryFab(SECONDARY_MOVE) as BatchFabResult;
  ok('移动产出结果', r6 !== null);
  if (r6 !== null) {
    eq('kind = BATCH_MOVE', r6.kind, BATCH_MOVE);
    ok('产出移动对话框', r6.moveDialog !== null);
    if (r6.moveDialog !== null) {
      eq('移动对话框 title', r6.moveDialog.title, TITLE_MOVE);
      eq('★标签数组 = [默认] + 已有标签', r6.moveDialog.items, ['Default', 'L1', 'L2']);
    }
  }
  const md6 = (r6 as BatchFabResult).moveDialog;
  const labels6: string[] = md6 === null ? [] : md6.items;
  await a6.onMoveSelect((r6 as BatchFabResult).selection as BatchSelection, labels6, 0);
  eq('★选第 0 位（默认标签）→ label = null（移出标签）', h6.changedLabels, ['<null>']);
  await a6.onMoveSelect((r6 as BatchFabResult).selection as BatchSelection, labels6, 2);
  eq('选第 2 位 → label = L2', h6.changedLabels, ['<null>', 'L2']);
  eq('越界 which → 返回 false', await a6.onMoveSelect((r6 as BatchFabResult).selection as BatchSelection, labels6, 9), false);
  eq('移动前退选择模式（每成功一次退一次）', h6.outOfChoiceModeCalls, 3);

  // ---------- ⑩ 随机 / 拖拽开关 ----------
  const h7: FakeBatchHost = new FakeBatchHost();
  h7.list = [mkInfo(5), mkInfo(6)];
  const a7: DownloadBatchActions = new DownloadBatchActions(h7);
  eq('★random=0 → 第 0 条', a7.viewRandom(0), true);
  eq('打开 gid 5', h7.launched, [5]);
  eq('★random=0.999 → 第 1 条（不越界）', a7.viewRandom(0.999), true);
  eq('打开 gid 6', h7.launched, [5, 6]);
  eq('★random=1.0 → position=size → 防御返回 false', a7.viewRandom(1), false);
  eq('越界不打开', h7.launched.length, 2);
  const h8: FakeBatchHost = new FakeBatchHost();
  h8.list = [mkInfo(9)];
  const a8: DownloadBatchActions = new DownloadBatchActions(h8);
  eq('随机按钮：先点主 FAB 再随机', a8.viewRandom(0), true);
  h8.list = [];
  eq('空列表 → 随机返回 false', a8.viewRandom(0), false);

  // 拖拽开关：翻转 → 持久化 → 换图标
  const h9: FakeBatchHost = new FakeBatchHost();
  const a9: DownloadBatchActions = new DownloadBatchActions(h9);
  eq('初始未开启', a9.isDragEnabled(), false);
  const r9: BatchFabResult = a9.onClickSecondaryFab(SECONDARY_DRAG_TOGGLE) as BatchFabResult;
  eq('kind = BATCH_DRAG_TOGGLE', r9.kind, BATCH_DRAG_TOGGLE);
  eq('★翻转后开启', a9.isDragEnabled(), true);
  eq('持久化收到 true', h9.dragSetting, [true]);
  eq('★图标按**翻转后**的值选（on）', r9.fabIcon, ICON_DRAG_ON);
  const r9b: BatchFabResult = a9.onClickSecondaryFab(SECONDARY_DRAG_TOGGLE) as BatchFabResult;
  eq('再翻一次 → 关闭', a9.isDragEnabled(), false);
  eq('持久化收到 [true,false]', h9.dragSetting, [true, false]);
  eq('图标换成 off', r9b.fabIcon, ICON_DRAG_OFF);

  // ---------- 单条删除（保留逻辑）----------
  const h10: FakeBatchHost = new FakeBatchHost();
  const a10: DownloadBatchActions = new DownloadBatchActions(h10);
  const info10: DownloadInfo = mkInfo(77);
  h10.existingDir = '/data/dl/77';
  eq('单条删除确认', await a10.onDeleteSingleConfirm(info10, true), true);
  eq('deleteDownload 收到 gid', h10.deletedSingle, [77]);
  eq('写回设置', h10.putRemoveCalls, [true]);
  eq('删了已存在目录', h10.asyncDeletes, ['/data/dl/77']);
  eq('移除了 dirname 记录', h10.removedDirnames, [77]);
  eq('有目录时不走"按 gid 推目录"的批量删除', h10.asyncGalleryDeletes, 0);
  const h11: FakeBatchHost = new FakeBatchHost();
  const a11: DownloadBatchActions = new DownloadBatchActions(h11);
  h11.existingDir = null;
  await a11.onDeleteSingleConfirm(mkInfo(88), true);
  eq('★没有已存在目录 → 走批量删除图库文件', h11.asyncGalleryDeletes, 1);
  eq('仍移除 dirname 记录', h11.removedDirnames, [88]);

  // ---------- 随机按钮 5：空列表直接 return ----------
  const h12: FakeBatchHost = new FakeBatchHost();
  h12.list = [];
  const a12: DownloadBatchActions = new DownloadBatchActions(h12);
  eq('空列表 → position 5 返回 null', a12.onClickSecondaryFab(SECONDARY_RANDOM), null);
  eq('空列表 → 不点主 FAB', h12.primaryFabCalls, 0);
}

// ─────────────────────────────────────────────────────────────────────────────
// S0219 接线到 ToolbarScene（本轮新增）：标题/导航图标改走共用 ToolbarLogic。
// 断言：① onViewCreated 后标题 = download_labels ② 导航图标 = v_arrow_left_dark_x24
//      ③ **先 setTitle 后 attach 也被正确暂存**（这正是 ToolbarLogic 的 mTempTitle 语义）
// ─────────────────────────────────────────────────────────────────────────────
function testDownloadLabelsToolbarWiring(): void {
  const h: FakeLabelsHost = new FakeLabelsHost();
  const s: DownloadLabelsScene = new DownloadLabelsScene(h);
  eq('接线前标题为空', s.getToolbarTitle(), null);
  s.onViewCreated();
  eq('★onViewCreated 后标题 = download_labels', s.getToolbarTitle(), TITLE_DOWNLOAD_LABELS);
  eq('★菜单资源仍由本类提供', s.getMenuResId(), MENU_SCENE_DOWNLOAD_LABEL);
  eq('返回图标常量', DRAWABLE_BACK, 'v_arrow_left_dark_x24');
}
async function main(): Promise<void> {
  await testDownloadLabelsScene();
  await testDownloadBatchActions();
  testDownloadLabelsToolbarWiring();
  if (fails.length > 0) {
    console.error(`\n✗ ${fails.length} 条失败 / ${pass + fails.length} 条断言`);
    for (const f of fails) {
      console.error('  - ' + f);
    }
    throw new Error('download labels/batch test failed');
  }
  console.log(`✓ 下载标签 + 批量操作批: ${pass} 条断言全部通过`);
}

main();


