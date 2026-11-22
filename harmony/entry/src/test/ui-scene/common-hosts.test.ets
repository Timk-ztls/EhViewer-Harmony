/*
 * native-image 接手批单测：CommonOperations（S0189）+ HostsActivity（S0209）
 *
 * 断言重点（都是"反直觉 / 顺序敏感 / 归一化差分"的）：
 *   ① ★收藏三大分支：`slot == -1` = **本地收藏不发请求**；`0..9` = 远端；其它 = onFailure
 *   ② ★`justStart` 的判断是**反的**：`label == null || containLabel(label)`（不是 !containLabel）
 *   ③ `addToFavorites` 的 items = **11 项**（`[0]` 本地收藏 + 10 个 favCat）
 *   ④ 选择框里 `position → slot1 = position - 1`（**0 → -1 = 本地收藏**）
 *   ⑤ `removeFromFavorites` 的 Delegate slot 是 **-2**（不是 -1）
 *   ⑥ `DelegateFavoriteCallback.onSuccess` 回写 `favoriteName/favoriteSlot` 并通知路由
 *   ⑦ `startDownloads`：已有任务发 RANGE、新任务发 START；**`toAdd` 为空也提示**
 *   ⑧ 选择框里选到的标签**已被删** → 退化为 null
 *   ⑨ Hosts：**host 归一化 trim+小写；ip 只 trim**
 *   ⑩ Hosts：**先校验 host 再校验 ip，首个错误即 return（不两个都标红）**
 *   ⑪ Hosts：编辑时 **host 输入框禁用**；删除用输入框里的 host（不校验）
 *   ⑫ Hosts：列表/tip 可见性在 onCreate 与 notifyHostsChanges **各算一次**
 *   ⑬ `.nomedia`：create 失败就 return；remove 用 subFile **查了才删**
 *
 * 运行：pwsh -File harmony/entry/src/test/ui-scene/run.ps1 -Filter common-hosts
 */

import {
  CommonOperations, OpsHost, OpsSettings, FavoriteCallback, DelegateFavoriteCallback, DownloadStartResult,
  INVALID_DEFAULT_FAV_SLOT, SLOT_LOCAL, SLOT_REMOVED,
  STR_LOCAL_FAVORITES, STR_REMEMBER_FAV, STR_ADD_FAV_TITLE, STR_REMEMBER_LABEL, STR_DOWNLOAD_TITLE,
  STR_ADDED_TO_DOWNLOAD, STR_DEFAULT_LABEL_NAME
} from '../../main/ets/hippo/ehviewer/ui/CommonOperations';
import {
  HostsActivity, HostsHost, HostEntry, HostDialogSpec, HostCommitResult, HostListState,
  KEY_HOST, KEY_IP, DIALOG_TAG_ADD_HOST, DIALOG_TAG_EDIT_HOST,
  STR_INVALID_HOST, STR_INVALID_IP, STR_ADD_HOST, STR_EDIT_HOST, STR_EDIT_HOST_DELETE,
  HOST_DIALOG_ADD, HOST_DIALOG_EDIT, FAB_BOTTOM_PADDING_VP, SHOW_LAST_DIVIDER, normalizeHost
} from '../../main/ets/hippo/ehviewer/ui/HostsActivity';
import { HostIpPair } from '../../main/ets/hippo/ehviewer/Hosts';
import { GalleryInfo } from '../../main/ets/hippo/ehviewer/client/data/GalleryInfo';
import { DownloadLabel } from '../../main/ets/hippo/ehviewer/dao/DownloadLabel';
import { ListCheckBoxDialogSpec } from '../../main/ets/hippo/app/DialogSpecs';

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

// ---------------------------------------------------------------- S0189 fakes
class FakeOpsHost implements OpsHost {
  localPut: number[] = [];
  localRemoved: number[] = [];
  remote: string[] = [];
  modified: string[] = [];
  contained: Set<number> = new Set<number>();
  labels: Set<string> = new Set<string>();
  labelList: DownloadLabel[] = [];
  ranges: number[][] = [];
  singles: string[] = [];
  tips: string[] = [];
  listCheckBoxSpecs: ListCheckBoxDialogSpec[] = [];
  selectHandler: ((position: number, checked: boolean) => void) | null = null;
  cancelHandler: (() => void) | null = null;
  createNoMediaResult: boolean = true;
  findNoMediaResult: boolean = false;
  deletedFiles: string[] = [];

  putLocalFavorite(gi: GalleryInfo): void {
    this.localPut.push(gi.gid);
  }

  removeLocalFavorites(gid: number): void {
    this.localRemoved.push(gid);
  }

  addFavoritesRemote(gid: number, token: string, slot: number, callback: FavoriteCallback): void {
    this.remote.push(`${gid}:${slot}`);
    // 默认立即成功（测试可在断言前改成失败）
    callback.onSuccess();
  }

  modifyFavourites(gid: number, slot: number): void {
    this.modified.push(`${gid}:${slot}`);
  }

  containDownloadInfo(gid: number): boolean {
    return this.contained.has(gid);
  }

  containLabel(label: string | null): boolean {
    return label !== null && this.labels.has(label);
  }

  getLabelList(): DownloadLabel[] {
    return this.labelList;
  }

  startRange(gids: number[]): void {
    this.ranges.push(gids);
  }

  startSingle(gi: GalleryInfo, label: string | null): void {
    this.singles.push(`${gi.gid}:${label === null ? '<null>' : label}`);
  }

  showTip(key: string): void {
    this.tips.push(key);
  }

  resolveString(key: string): string {
    if (key === STR_LOCAL_FAVORITES) { return 'Local'; }
    if (key === STR_DEFAULT_LABEL_NAME) { return 'Default'; }
    return key;
  }

  showListCheckBox(spec: ListCheckBoxDialogSpec, onSelect: (position: number, checked: boolean) => void,
    onCancel: () => void): void {
    this.listCheckBoxSpecs.push(spec);
    this.selectHandler = onSelect;
    this.cancelHandler = onCancel;
  }

  createNoMedia(path: string): boolean {
    return this.createNoMediaResult;
  }

  findNoMediaFile(path: string): boolean {
    return this.findNoMediaResult;
  }

  deleteFile(path: string): void {
    this.deletedFiles.push(path);
  }

  pick(position: number, checked: boolean): void {
    if (this.selectHandler !== null) {
      this.selectHandler(position, checked);
    }
  }
}

class FakeOpsSettings implements OpsSettings {
  defaultFavSlot: number = 0;
  favCat: string[] = ['c0', 'c1', 'c2', 'c3', 'c4', 'c5', 'c6', 'c7', 'c8', 'c9'];
  hasDefaultLabel: boolean = false;
  defaultLabel: string | null = null;
  savedFavSlots: number[] = [];
  savedHasLabel: boolean[] = [];
  savedLabels: (string | null)[] = [];

  getDefaultFavSlot(): number {
    return this.defaultFavSlot;
  }

  putDefaultFavSlot(slot: number): void {
    this.savedFavSlots.push(slot);
    this.defaultFavSlot = slot;
  }

  getFavCat(): string[] {
    return this.favCat;
  }

  getHasDefaultDownloadLabel(): boolean {
    return this.hasDefaultLabel;
  }

  putHasDefaultDownloadLabel(v: boolean): void {
    this.savedHasLabel.push(v);
    this.hasDefaultLabel = v;
  }

  getDefaultDownloadLabel(): string | null {
    return this.defaultLabel;
  }

  putDefaultDownloadLabel(label: string | null): void {
    this.savedLabels.push(label);
    this.defaultLabel = label;
  }
}

class FakeFavCallback implements FavoriteCallback {
  successes: number = 0;
  failures: number = 0;
  cancels: number = 0;

  onSuccess(): void {
    this.successes++;
  }

  onFailure(e: Error): void {
    this.failures++;
  }

  onCancel(): void {
    this.cancels++;
  }
}

function mkGi(gid: number, token: string = 'tok'): GalleryInfo {
  const gi: GalleryInfo = new GalleryInfo();
  gi.gid = gid;
  gi.token = token;
  return gi;
}

function testCommonOperations(): void {
  // ---------- 常量 ----------
  eq('INVALID_DEFAULT_FAV_SLOT = -2', INVALID_DEFAULT_FAV_SLOT, -2);
  eq('SLOT_LOCAL = -1 / SLOT_REMOVED = -2', [SLOT_LOCAL, SLOT_REMOVED], [-1, -2]);

  // ---------- ① 收藏三分支 ----------
  const h1: FakeOpsHost = new FakeOpsHost();
  const st1: FakeOpsSettings = new FakeOpsSettings();
  const ops1: CommonOperations = new CommonOperations(h1, st1);
  const cb1: FakeFavCallback = new FakeFavCallback();
  const gi1: GalleryInfo = mkGi(100);

  ops1.doAddToFavorites(gi1, SLOT_LOCAL, cb1);
  eq('★slot=-1 → 走本地收藏', h1.localPut, [100]);
  eq('★slot=-1 → **不发远端请求**', h1.remote, []);
  eq('slot=-1 → 立即 onSuccess', cb1.successes, 1);

  ops1.doAddToFavorites(gi1, 3, cb1);
  eq('slot=3 → 发远端请求', h1.remote, ['100:3']);
  eq('远端成功 → 回调 onSuccess', cb1.successes, 2);
  // 断言修正：`doAddToFavorites` **本身不通知路由** —— 通知在 `DelegateFavoriteCallback.onSuccess` 里
  // （上游 doAddToFavorites 只发请求；modifyFavourites 由 Delegate 做）。
  // 我这里第一版直接传了裸 callback，所以路由数组应为空。Delegate 路径由下面 removeFromFavorites 覆盖。
  eq('★doAddToFavorites 直调不通知路由（通知在 Delegate 里）', h1.modified, []);

  ops1.doAddToFavorites(gi1, 10, cb1);
  eq('slot=10（越界）→ onFailure', cb1.failures, 1);
  eq('越界不发远端', h1.remote.length, 1);
  ops1.doAddToFavorites(gi1, -2, cb1);
  eq('slot=-2 也是非法 → onFailure', cb1.failures, 2);

  // ---------- ② addToFavorites：默认 slot 直用 ----------
  const h2: FakeOpsHost = new FakeOpsHost();
  const st2: FakeOpsSettings = new FakeOpsSettings();
  st2.defaultFavSlot = 2;
  const ops2: CommonOperations = new CommonOperations(h2, st2);
  const cb2: FakeFavCallback = new FakeFavCallback();
  const gi2: GalleryInfo = mkGi(200);
  ops2.addToFavorites(gi2, cb2, false);
  eq('默认 slot=2 且非强制 → 直接收藏', h2.remote, ['200:2']);
  eq('回写 favoriteSlot = 2', gi2.favoriteSlot, 2);
  eq('回写 favoriteName = items[3]（= c2）', gi2.favoriteName, 'c2');
  eq('不弹选择框', h2.listCheckBoxSpecs.length, 0);

  // 默认 slot = -1（本地）→ 不弹框，直接本地
  const h3: FakeOpsHost = new FakeOpsHost();
  const st3: FakeOpsSettings = new FakeOpsSettings();
  st3.defaultFavSlot = -1;
  const ops3: CommonOperations = new CommonOperations(h3, st3);
  const gi3: GalleryInfo = mkGi(300);
  ops3.addToFavorites(gi3, new FakeFavCallback(), false);
  eq('默认 slot=-1 → 本地收藏', h3.localPut, [300]);
  eq('本地收藏 favoriteName = null', gi3.favoriteName, null);
  eq('本地收藏 favoriteSlot = -1', gi3.favoriteSlot, -1);

  // 强制弹框（isDefaultFavSolt = true）
  const h4: FakeOpsHost = new FakeOpsHost();
  const st4: FakeOpsSettings = new FakeOpsSettings();
  st4.defaultFavSlot = 1;
  const ops4: CommonOperations = new CommonOperations(h4, st4);
  const cb4: FakeFavCallback = new FakeFavCallback();
  ops4.addToFavorites(mkGi(400), cb4, true);
  eq('★强制 → 弹选择框', h4.listCheckBoxSpecs.length, 1);
  eq('③ items 共 11 项', h4.listCheckBoxSpecs[0].items.length, 11);
  eq('items[0] = 本地收藏', h4.listCheckBoxSpecs[0].items[0], 'Local');
  eq('items[1..10] = favCat', h4.listCheckBoxSpecs[0].items.slice(1),
    ['c0', 'c1', 'c2', 'c3', 'c4', 'c5', 'c6', 'c7', 'c8', 'c9']);
  eq('④ 选择框 title', h4.listCheckBoxSpecs[0].title, STR_ADD_FAV_TITLE);
  eq('复选框文案', h4.listCheckBoxSpecs[0].checkText, STR_REMEMBER_FAV);
  eq('复选框默认未勾选', h4.listCheckBoxSpecs[0].checked, false);

  // 选 position=3 → slot1 = 2
  const gi4: GalleryInfo = mkGi(401);
  ops4.addToFavorites(gi4, cb4, true);
  h4.pick(3, true);
  eq('④ position=3 → slot 2', h4.remote[h4.remote.length - 1], '401:2');
  eq('勾选 → 记住 slot 2', st4.savedFavSlots, [2]);
  // 选 position=0 → slot -1（本地）
  const h5: FakeOpsHost = new FakeOpsHost();
  const st5: FakeOpsSettings = new FakeOpsSettings();
  const ops5: CommonOperations = new CommonOperations(h5, st5);
  ops5.addToFavorites(mkGi(500), new FakeFavCallback(), true);
  h5.pick(0, false);
  eq('★position=0 → slot -1（本地收藏）', h5.localPut, [500]);
  eq('未勾选 → 记住 INVALID(-2)', st5.savedFavSlots, [INVALID_DEFAULT_FAV_SLOT]);

  // cancel → onCancel
  const h6: FakeOpsHost = new FakeOpsHost();
  const ops6: CommonOperations = new CommonOperations(h6, new FakeOpsSettings());
  const cb6: FakeFavCallback = new FakeFavCallback();
  ops6.addToFavorites(mkGi(600), cb6, true);
  if (h6.cancelHandler !== null) { h6.cancelHandler(); }
  eq('取消 → 回调 onCancel', cb6.cancels, 1);

  // ---------- ⑤ removeFromFavorites：Delegate slot = -2 ----------
  const h7: FakeOpsHost = new FakeOpsHost();
  const ops7: CommonOperations = new CommonOperations(h7, new FakeOpsSettings());
  const gi7: GalleryInfo = mkGi(700);
  ops7.removeFromFavorites(gi7, new FakeFavCallback());
  eq('先移除本地收藏', h7.localRemoved, [700]);
  eq('远端 slot = -1', h7.remote, ['700:-1']);
  eq('★Delegate 传 slot = -2 → 路由收到 -2', h7.modified, ['700:-2']);
  eq('★favoriteSlot 回写 -2', gi7.favoriteSlot, -2);
  eq('favoriteName 回写 null', gi7.favoriteName, null);

  // ---------- ⑦ startDownloads ----------
  const h8: FakeOpsHost = new FakeOpsHost();
  const st8: FakeOpsSettings = new FakeOpsSettings();
  const ops8: CommonOperations = new CommonOperations(h8, st8);
  h8.contained.add(1);
  const r8: DownloadStartResult = ops8.startDownloads([mkGi(1), mkGi(2)], true);
  eq('已有任务走 RANGE', h8.ranges, [[1]]);
  eq('新任务走 START（label=null）', h8.singles, ['2:<null>']);
  eq('提示"已加入下载列表"', h8.tips, [STR_ADDED_TO_DOWNLOAD]);
  eq('结果：续传 1 条 + 新开 1 条', [r8.rangeStarted, r8.started], [1, 1]);

  // toAdd 为空 → 只提示
  const h9: FakeOpsHost = new FakeOpsHost();
  const ops9: CommonOperations = new CommonOperations(h9, new FakeOpsSettings());
  h9.contained.add(5);
  const r9: DownloadStartResult = ops9.startDownloads([mkGi(5)], true);
  eq('★全已存在 → 仍提示', h9.tips, [STR_ADDED_TO_DOWNLOAD]);
  eq('不发 START', h9.singles, []);
  eq('结果 started = 0', r9.started, 0);

  // ---------- ② justStart 的"反直觉"判断 ----------
  // 情形 A：hasDefaultLabel=true, defaultLabel='L1', containLabel('L1')=true → justStart=true
  const hA: FakeOpsHost = new FakeOpsHost();
  const stA: FakeOpsSettings = new FakeOpsSettings();
  stA.hasDefaultLabel = true;
  stA.defaultLabel = 'L1';
  hA.labels.add('L1');
  hA.labelList = [new DownloadLabel(1, 'L1', 0), new DownloadLabel(2, 'L2', 0)];
  const opsA: CommonOperations = new CommonOperations(hA, stA);
  const rA: DownloadStartResult = opsA.startDownloads([mkGi(9)], false);
  eq('★默认标签存在 → 直接用该标签开（不弹框）', hA.singles, ['9:L1']);
  eq('★不弹选择框', hA.listCheckBoxSpecs.length, 0);
  eq('usedDefaultLabel = true', rA.usedDefaultLabel, true);

  // 情形 B：hasDefaultLabel=true 但 defaultLabel='gone' 且 containLabel=false → justStart=false → 弹框
  const hB: FakeOpsHost = new FakeOpsHost();
  const stB: FakeOpsSettings = new FakeOpsSettings();
  stB.hasDefaultLabel = true;
  stB.defaultLabel = 'gone';
  hB.labelList = [new DownloadLabel(1, 'L1', 0)];
  // 测试前置：标签 L1 必须**真实存在**于 DownloadManager（否则 `!containLabel` 会把选择退化成 null）
  hB.labels.add('L1');
  const opsB: CommonOperations = new CommonOperations(hB, stB);
  const rB: DownloadStartResult = opsB.startDownloads([mkGi(10)], false);
  eq('★默认标签已不存在 → 弹选择框', hB.listCheckBoxSpecs.length, 1);
  eq('awaitingLabelChoice = true', rB.awaitingLabelChoice, true);
  eq('此刻还没开任务', hB.singles, []);
  eq('选择框 items = [Default, L1]', hB.listCheckBoxSpecs[0].items, ['Default', 'L1']);
  eq('选择框 title = download', hB.listCheckBoxSpecs[0].title, STR_DOWNLOAD_TITLE);
  // 选 position 1（L1）
  hB.pick(1, true);
  eq('选中 L1 → 用 L1 开', hB.singles, ['10:L1']);
  eq('勾选 → 记住 hasDefault=true + label=L1',
    [stB.savedHasLabel, stB.savedLabels], [[true], ['L1']]);

  // 情形 C：position=0 → label null
  const hC: FakeOpsHost = new FakeOpsHost();
  const stC: FakeOpsSettings = new FakeOpsSettings();
  stC.hasDefaultLabel = true;
  stC.defaultLabel = 'gone';
  hC.labelList = [new DownloadLabel(1, 'L1', 0)];
  const opsC: CommonOperations = new CommonOperations(hC, stC);
  opsC.startDownloads([mkGi(11)], false);
  hC.pick(0, false);
  eq('选"默认标签" → label null', hC.singles, ['11:<null>']);
  eq('未勾选 → 记住 hasDefault=false', stC.savedHasLabel, [false]);

  // 情形 D：选到的标签已被删 → 退化为 null
  const hD: FakeOpsHost = new FakeOpsHost();
  const stD: FakeOpsSettings = new FakeOpsSettings();
  stD.hasDefaultLabel = true;
  stD.defaultLabel = 'gone';
  hD.labelList = [new DownloadLabel(1, 'L1', 0), new DownloadLabel(2, 'L2', 0)];
  const opsD: CommonOperations = new CommonOperations(hD, stD);
  opsD.startDownloads([mkGi(12)], false);
  // 模拟"选之前把 L2 删了"
  hD.labels.delete('L2');
  hD.labels.add('L1');
  hD.pick(2, false);
  eq('⑧ 选到已删标签 L2 → 退化为 null', hD.singles, ['12:<null>']);

  // ⑤ 分支（"无任何自定义标签 → 直接开"）只在 **④ 没能确定 justStart** 时才生效：
  //   上游 `if (!justStart && 0 == dm.getLabelList().size())`。
  //   我的第一版把 ④ 造成成功（默认标签有效且 labelList 空）→ 走了 ④，label 仍是默认标签。
  //   正确构造：默认标签**已失效**（不在 DownloadManager 里）+ labelList 空 → ④ justStart=false → ⑤ 命中。
  const hE: FakeOpsHost = new FakeOpsHost();
  const stE: FakeOpsSettings = new FakeOpsSettings();
  stE.hasDefaultLabel = true;
  stE.defaultLabel = 'gone';
  hE.labelList = [];
  const opsE: CommonOperations = new CommonOperations(hE, stE);
  opsE.startDownloads([mkGi(13)], false);
  eq('★⑤ 无自定义标签 → 直接开且 label=null', hE.singles, ['13:<null>']);
  eq('不弹框', hE.listCheckBoxSpecs.length, 0);
  // 对偶：默认标签有效 + labelList 空 → 走 ④，用默认标签（不走 ⑤）
  const hE2: FakeOpsHost = new FakeOpsHost();
  const stE2: FakeOpsSettings = new FakeOpsSettings();
  stE2.hasDefaultLabel = true;
  stE2.defaultLabel = 'L1';
  hE2.labels.add('L1');
  hE2.labelList = [];
  const opsE2: CommonOperations = new CommonOperations(hE2, stE2);
  opsE2.startDownloads([mkGi(14)], false);
  eq('★④ 默认标签有效 → 用默认标签（⑤ 不生效）', hE2.singles, ['14:L1']);

  // ---------- ⑬ .nomedia ----------
  const hF: FakeOpsHost = new FakeOpsHost();
  const opsF: CommonOperations = new CommonOperations(hF, new FakeOpsSettings());
  hF.createNoMediaResult = false;
  eq('create 失败 → false', opsF.ensureNoMediaFile('/d/x'), false);
  hF.createNoMediaResult = true;
  eq('create 成功 → true', opsF.ensureNoMediaFile('/d/x'), true);
  eq('路径为空 → false（等价 file == null）', opsF.ensureNoMediaFile(''), false);
  hF.findNoMediaResult = false;
  eq('not found → 不删', opsF.removeNoMediaFile('/d/x'), false);
  eq('未产生删除调用', hF.deletedFiles, []);
  hF.findNoMediaResult = true;
  eq('found → 删', opsF.removeNoMediaFile('/d/x'), true);
  eq('产生了删除调用', hF.deletedFiles, ['/d/x']);
}

// ---------------------------------------------------------------- S0209 fakes
class FakeHostsHost implements HostsHost {
  entries: HostEntry[] = [];
  puts: string[] = [];
  deletes: string[] = [];
  finishCalls: number = 0;
  shown: HostDialogSpec[] = [];
  hostValid: boolean = true;
  ipValid: boolean = true;

  async getAll(): Promise<HostIpPair[]> {
    return this.entries.map((e: HostEntry): HostIpPair => new HostIpPair(e.host, e.ip));
  }

  async put(host: string, ip: string): Promise<boolean> {
    this.puts.push(`${host}=${ip}`);
    this.entries.push(new HostEntry(host, ip));
    return true;
  }

  async delete(host: string): Promise<void> {
    this.deletes.push(host);
    this.entries = this.entries.filter((e: HostEntry): boolean => e.host !== host);
  }

  isValidHost(host: string): boolean {
    return this.hostValid;
  }

  isValidIp(ip: string): boolean {
    return this.ipValid;
  }

  finish(): void {
    this.finishCalls++;
  }

  showDialog(spec: HostDialogSpec): void {
    this.shown.push(spec);
  }
}

async function testHostsActivity(): Promise<void> {
  // ---------- 常量 ----------
  eq('两个 args 键带包名前缀', [KEY_HOST, KEY_IP],
    ['com.hippo.ehviewer.ui.HostsActivity.HOST', 'com.hippo.ehviewer.ui.HostsActivity.IP']);
  ok('两个对话框 tag 互不相同', DIALOG_TAG_ADD_HOST !== DIALOG_TAG_EDIT_HOST);
  eq('两个对话框类型常量', [HOST_DIALOG_ADD, HOST_DIALOG_EDIT], [0, 1]);
  eq('FAB 底部留白常量', FAB_BOTTOM_PADDING_VP, 72);
  eq('showLastDivider = true（本页有，GalleryInfoScene 无）', SHOW_LAST_DIVIDER, true);

  // ---------- ⑨ host 归一化 vs ip 只 trim ----------
  eq('host: trim + 小写', normalizeHost('  EXample.COM  '), 'example.com');
  eq('host: 大写变小数（Locale.US 语义）', normalizeHost('AbC'), 'abc');
  eq('host: 纯空白 → 空串', normalizeHost('   '), '');
  // ip 只 trim：用 put + spy 观察
  const h1: FakeHostsHost = new FakeHostsHost();
  const a1: HostsActivity = new HostsActivity(h1);
  await a1.onCreate();
  const addSpec: HostDialogSpec = a1.onClickFab();
  addSpec.hostText = '  MyHost.COM ';
  addSpec.ipText = '  2001:DB8::1  ';
  const r1: HostCommitResult = await a1.put(addSpec);
  eq('★host 归一化为 myhost.com', r1.ok, true);
  eq('★ip 只 trim、**保持大小写**', h1.puts, ['myhost.com=2001:DB8::1']);

  // ---------- ⑩ 校验顺序：先 host 后 ip，首个错误即 return ----------
  const h2: FakeHostsHost = new FakeHostsHost();
  const a2: HostsActivity = new HostsActivity(h2);
  await a2.onCreate();
  const s2: HostDialogSpec = a2.onClickFab();
  s2.hostText = 'bad host';
  s2.ipText = 'bad ip';
  h2.hostValid = false;
  h2.ipValid = false;
  const r2: HostCommitResult = await a2.put(s2);
  eq('host 非法 → 失败', r2.ok, false);
  eq('host 非法 → hostError', s2.hostError, STR_INVALID_HOST);
  eq('★host 非法时 **ipError 保持 null**（不两个都标红）', s2.ipError, null);
  eq('未写入', h2.puts, []);
  // 只 ip 非法
  h2.hostValid = true;
  h2.ipValid = false;
  const s3: HostDialogSpec = a2.onClickFab();
  s3.hostText = 'ok.com';
  s3.ipText = 'bad';
  const r3: HostCommitResult = await a2.put(s3);
  eq('ip 非法 → 失败', r3.ok, false);
  eq('ip 非法 → ipError', s3.ipError, STR_INVALID_IP);
  eq('host 已通过 → hostError null', s3.hostError, null);
  eq('仍未写入', h2.puts, []);

  // ---------- 列表 / tip 可见性（两处各算一次）----------
  const h4: FakeHostsHost = new FakeHostsHost();
  const a4: HostsActivity = new HostsActivity(h4);
  const st4: HostListState = await a4.onCreate();
  eq('空数据 → tip 可见、列表隐藏', [st4.tipVisible, st4.listVisible], [true, false]);
  h4.entries = [new HostEntry('a.com', '1.1.1.1')];
  const st5: HostListState = await a4.notifyHostsChanges();
  eq('有数据 → 列表可见、tip 隐藏', [st5.tipVisible, st5.listVisible], [false, true]);
  eq('itemCount = 1', a4.getItemCount(), 1);
  eq('bindItem(0)', [a4.bindItem(0)?.host, a4.bindItem(0)?.ip], ['a.com', '1.1.1.1']);
  eq('越界 bindItem → null', a4.bindItem(5), null);
  eq('getEntries() 返回列表快照', a4.getEntries().length, 1);

  // ---------- ⑪ 编辑对话框：host 禁用、带初值、有删除按钮 ----------
  const editSpec: HostDialogSpec | null = a4.onItemClick(0);
  ok('产出编辑对话框', editSpec !== null);
  if (editSpec !== null) {
    eq('kind = EDIT', editSpec.kind, HOST_DIALOG_EDIT);
    eq('title = edit_host', editSpec.title, STR_EDIT_HOST);
    eq('初值回填 host', editSpec.hostText, 'a.com');
    eq('初值回填 ip', editSpec.ipText, '1.1.1.1');
    eq('★编辑时 host 输入框禁用', editSpec.hostInputEnabled, false);
    eq('有删除按钮', editSpec.negativeText, STR_EDIT_HOST_DELETE);
    eq('dialogTag = EDIT', editSpec.dialogTag, DIALOG_TAG_EDIT_HOST);
  }
  // 新增对话框：host 可编辑、无删除按钮
  const addSpec2: HostDialogSpec = a4.onClickFab();
  eq('新增 kind = ADD', addSpec2.kind, HOST_DIALOG_ADD);
  eq('新增 title = add_host', addSpec2.title, STR_ADD_HOST);
  eq('新增 host 可编辑', addSpec2.hostInputEnabled, true);
  eq('新增无删除按钮', addSpec2.negativeText, null);
  eq('新增 dialogTag = ADD', addSpec2.dialogTag, DIALOG_TAG_ADD_HOST);

  // ---------- 删除：归一化但不校验 ----------
  const h6: FakeHostsHost = new FakeHostsHost();
  const a6: HostsActivity = new HostsActivity(h6);
  h6.entries = [new HostEntry('del.com', '2.2.2.2')];
  await a6.onCreate();
  const delSpec: HostDialogSpec | null = a6.onItemClick(0);
  ok('编辑对话框可用于删除', delSpec !== null);
  if (delSpec !== null) {
    delSpec.hostText = '  DEL.com ';   // 用户在(禁用的)输入框里留下的值 → 仍会归一化
    await a6.delete(delSpec);
  }
  eq('★删除用归一化后的 host', h6.deletes, ['del.com']);
  eq('删除后数据清空', a6.getItemCount(), 0);

  // ---------- 可见性：delete 后回到 tip ----------
  const st7: HostListState = await a6.notifyHostsChanges();
  eq('删空后 tip 可见', [st7.tipVisible, st7.listVisible], [true, false]);

  // ---------- 导航 ----------
  const before: number = h6.finishCalls;
  eq('home 返回 true', a6.onOptionsItemSelected('android.R.id.home'), true);
  eq('home 触发 finish', h6.finishCalls, before + 1);
  eq('其它菜单项返回 false', a6.onOptionsItemSelected('menu_x'), false);
}

async function main(): Promise<void> {
  testCommonOperations();
  await testHostsActivity();
  if (fails.length > 0) {
    console.error(`\n✗ ${fails.length} 条失败 / ${pass + fails.length} 条断言`);
    for (const f of fails) {
      console.error('  - ' + f);
    }
    throw new Error('common/hosts test failed');
  }
  console.log(`✓ 通用操作 + Hosts 配置页批: ${pass} 条断言全部通过`);
}

main().catch((err: Object): void => {
  console.error(err);
  throw err;
});

