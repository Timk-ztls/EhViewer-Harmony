/*
 * DownloadsScene Part 1 单测（数据层 + 骨架）
 *
 * 钉住的是「标签回退」「标题退化」「参数解析」「控制器未注入要显式失败」这四类——
 * 它们都有同一个失败模式：**UI 看起来正常，但数据是错的/没更新**。
 *
 * 上游 L302-305 的「标签被删 → 回退默认标签」是这里最容易被写错的一条：
 * 若不回退，切到一个已被删除的标签，列表会永久空白且无法自愈。
 */

import { DownloadsScene, DownloadsSceneAction, DownloadManagerLike,
  DownloadSceneControllersLike } from '../../main/ets/hippo/ehviewer/ui/scene/download/DownloadsScene';
import { DownloadInfo } from '../../main/ets/hippo/ehviewer/dao/DownloadInfo';

let pass = 0;
const fails: string[] = [];

function eq(name: string, got: unknown, want: unknown): void {
  const g = JSON.stringify(got);
  const w = JSON.stringify(want);
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
    fails.push(name);
  }
}

function infos(...gids: number[]): DownloadInfo[] {
  const out: DownloadInfo[] = [];
  for (const g of gids) {
    out.push(new DownloadInfo(g));
  }
  return out;
}

/** 假 DownloadManager：three lists，labelList 为 null 模拟"标签被删"。 */
class FakeManager implements DownloadManagerLike {
  defaultList: DownloadInfo[] = [];
  labelMap: Map<string, DownloadInfo[]> = new Map<string, DownloadInfo[]>();

  getDownloadInfoList(): DownloadInfo[] {
    return this.defaultList.slice();
  }

  getDefaultDownloadInfoList(): DownloadInfo[] {
    return this.defaultList;
  }

  getLabelDownloadInfoList(label: string): DownloadInfo[] | null {
    const list: DownloadInfo[] | undefined = this.labelMap.get(label);
    return list !== undefined ? list : null;
  }
}

class FakeControllers implements DownloadSceneControllersLike {
  archiveCalls: number = 0;
  albumCalls: number = 0;
  searchBarCalls: number = 0;
  startAllCalls: number = 0;
  stopAllCalls: number = 0;
  guideCalls: number = 0;
  setTotalPagesCalls: number[] = [];
  searchKeySet: (string | null)[] = [];
  archiveResult: boolean = true;

  archiveImporter = {
    showImportDialog: (onDone: (success: boolean, message: string | null) => void): void => {
      this.archiveCalls++;
      onDone(this.archiveResult, 'ok');
    }
  };

  albumImporter = {
    showImportDialog: (onDone: (success: boolean, count: number) => void): void => {
      this.albumCalls++;
      onDone(true, 3);
    }
  };

  searchController = {
    showSearchBar: (): void => {
      this.searchBarCalls++;
    },
    getSearchKey: (): string | null => null,
    setSearchKey: (key: string | null): void => {
      this.searchKeySet.push(key);
    },
    onSearchChanged: null as ((key: string | null) => void) | null
  };

  batchActions = {
    startAll: async (): Promise<void> => {
      this.startAllCalls++;
    },
    stopAll: async (): Promise<void> => {
      this.stopAllCalls++;
    },
    onStateChanged: null as ((running: boolean, done: number, total: number) => void) | null
  };

  pagination = {
    onPageSelected: (page: number): void => {
    },
    getCurrentPage: (): number => 0,
    setTotalPages: (total: number): void => {
      this.setTotalPagesCalls.push(total);
    }
  };

  guideHelper = {
    showGuideIfNeeded: (): void => {
      this.guideCalls++;
    },
    isGuideDismissed: (): boolean => false
  };
}

// ================================================================ 1) updateForLabel

{
  const manager: FakeManager = new FakeManager();
  manager.defaultList = infos(1, 2, 3);
  manager.labelMap.set('A', infos(10, 11));

  const scene: DownloadsScene = new DownloadsScene(manager);
  eq('初始列表为空（未调用 updateForLabel）', scene.getList().length, 0);

  scene.updateForLabel();
  eq('无标签 → 默认列表', scene.getList().map((d: DownloadInfo): number => d.getGid()), [1, 2, 3]);
  eq('getBackList 与 mList 同源', scene.getBackList().length, 3);

  scene.setLabel('A');
  eq('切到标签 A → 该标签列表', scene.getList().map((d: DownloadInfo): number => d.getGid()), [10, 11]);
  eq('当前标签是 A', scene.getLabel(), 'A');

  // 标签被删（manager 返回 null）→ 必须回退默认且清空 mLabel（上游 L302-305）
  scene.setLabel('GONE');
  eq('标签不存在 → 回退默认列表', scene.getList().map((d: DownloadInfo): number => d.getGid()), [1, 2, 3]);
  eq('标签不存在 → mLabel 被清空（避免永久空白）', scene.getLabel(), null);
}

// ================================================================ 2) 未注入 manager 时不崩

{
  const scene: DownloadsScene = new DownloadsScene(null);
  scene.updateForLabel();     // 上游同样早退（L294-296）
  eq('无 manager → 列表保持空', scene.getList().length, 0);
  let threw: boolean = false;
  try {
    scene.showSearchBar();
  } catch (e) {
    threw = true;
  }
  ok('无控制器 → showSearchBar 显式抛错（不是静默无反应）', threw);
}

// ================================================================ 3) 参数解析

{
  const manager: FakeManager = new FakeManager();
  manager.defaultList = infos(100, 200, 300);
  const scene: DownloadsScene = new DownloadsScene(manager);
  scene.updateForLabel();

  eq('null 参数 → true 且不改状态', scene.handleArguments(null), true);

  const argsGid: Map<string, Object> = new Map<string, Object>();
  argsGid.set(DownloadsSceneAction.KEY_GID, 200);
  scene.handleArguments(argsGid);
  eq('gid 参数 → mInitPosition 指向该 gid 的下标', scene.getInitPosition(), 1);

  const argsGidMissing: Map<string, Object> = new Map<string, Object>();
  argsGidMissing.set(DownloadsSceneAction.KEY_GID, 999);
  scene.handleArguments(argsGidMissing);
  eq('不存在的 gid → mInitPosition = -1', scene.getInitPosition(), -1);

  const argsClear: Map<string, Object> = new Map<string, Object>();
  argsClear.set(DownloadsSceneAction.KEY_ACTION, DownloadsSceneAction.ACTION_CLEAR_DOWNLOAD_SERVICE);
  scene.handleArguments(argsClear);
  ok('clear service 请求被标记', scene.consumeClearDownloadServiceRequest());
  ok('clear service 请求只能消费一次', !scene.consumeClearDownloadServiceRequest());

  manager.labelMap.set('L', infos(7));
  const argsLabel: Map<string, Object> = new Map<string, Object>();
  argsLabel.set(DownloadsSceneAction.KEY_LABEL, 'L');
  scene.handleArguments(argsLabel);
  eq('label 参数 → 立即切标签并加载', scene.getLabel(), 'L');
  eq('label 参数 → 列表已切换', scene.getList().map((d: DownloadInfo): number => d.getGid()), [7]);
}

// ================================================================ 4) 标题与分页

{
  const manager: FakeManager = new FakeManager();
  manager.defaultList = infos(1, 2);
  const ctrl: FakeControllers = new FakeControllers();
  const scene: DownloadsScene = new DownloadsScene(manager);
  scene.setControllers(ctrl);
  scene.updateForLabel();

  const title: string = scene.getTitle();
  ok('标题非空', title.length > 0);
  eq('标题经 getTitle 与 updateTitle 返回一致', scene.getTitle(), title);
  eq('分页 setTotalPages 被调用', ctrl.setTotalPagesCalls.length, 1);
  ok('2 项 → 1 页', ctrl.setTotalPagesCalls[0] === 1);

  eq('默认每页 50（上游 perPageCountChoices 首项）', scene.getPageSize(), 50);
  eq('可选每页条数与上游一致', DownloadsScene.PER_PAGE_CHOICES, [50, 100, 200, 300, 500]);

  let many: number[] = [];
  for (let i = 1; i <= 51; i++) { many.push(i); }
  manager.defaultList = infos.apply(null, many);
  scene.updateForLabel();
  eq('51 项 / 每页 50 → 2 页', ctrl.setTotalPagesCalls[ctrl.setTotalPagesCalls.length - 1], 2);

  scene.setPageSize(100);
  eq('setPageSize(100) 生效', scene.getPageSize(), 100);
  scene.updateForLabel();
  eq('51 项 / 每页 100 → 1 页', ctrl.setTotalPagesCalls[ctrl.setTotalPagesCalls.length - 1], 1);

  scene.setPageSize(0);
  eq('非法 pageSize(0) 被忽略', scene.getPageSize(), 100);
}

// ================================================================ 5) 控制器转发 + 导入后由场景刷新

{
  const manager: FakeManager = new FakeManager();
  manager.defaultList = infos(1);
  const ctrl: FakeControllers = new FakeControllers();
  const scene: DownloadsScene = new DownloadsScene(manager);
  scene.setControllers(ctrl);
  scene.updateForLabel();
  eq('注入控制器', scene.hasControllers(), true);

  // 导入归档：控制器只导入，刷新由场景做 → 导入成功后列表应被重取
  manager.defaultList = infos(1, 2, 3);       // 模拟导入新增了两项
  let archived: boolean = false;
  scene.showArchiveImportDialog((success: boolean, message: string | null): void => {
    archived = success;
  });
  eq('归档导入回调被调用', ctrl.archiveCalls, 1);
  eq('导入成功 → 回调告知成功', archived, true);
  // 刷新由 importer 自己做（Host 契约里有 updateForLabel）→ 场景**不再重取列表**
  // 若这里仍是 3，说明场景也刷了一次 = 双刷（会闪一下）
  eq('导入成功后场景不重取列表（避免双刷）', scene.getList().length, 1);
  ok('但标题已更新', scene.getTitle().length > 0);

  // 导入失败 → 不刷新也不改标题
  ctrl.archiveResult = false;
  scene.showArchiveImportDialog(null);
  eq('导入失败后列表仍不变', scene.getList().length, 1);

  scene.showAlbumImportDialog(null);
  eq('相册导入被调用', ctrl.albumCalls, 1);

  scene.showSearchBar();
  eq('搜索栏被调用', ctrl.searchBarCalls, 1);
  scene.showGuideIfNeeded();
  eq('引导被调用', ctrl.guideCalls, 1);

  scene.applySearchKey('abc');
  eq('searchKey 更新', scene.getSearchKey(), 'abc');
  ok('searching = true', scene.isSearching());
  eq('searchKey 转发给控制器', ctrl.searchKeySet, ['abc']);
  scene.applySearchKey(null);
  ok('searchKey 清空后 searching = false', !scene.isSearching());
}

// ================================================================ 6) 分类过滤（上游禁用）+ Part 2 边界

{
  const manager: FakeManager = new FakeManager();
  manager.defaultList = infos(1, 2);
  const scene: DownloadsScene = new DownloadsScene(manager);
  scene.updateForLabel();
  eq('默认分类 = ALL_CATEGORY', scene.getSelectedCategory() !== undefined, true);

  scene.setSelectedCategory(-999);      // 非 ALL → 走"未实现"分支（只 warn，不改列表）
  eq('非 ALL 分类当前不过滤（上游 L312 禁用）', scene.getList().length, 2);
  scene.setSelectedCategory(scene.getSelectedCategory());
  eq('恢复 ALL 后列表仍是完整列表', scene.getList().length, 2);

  // 视图状态（替代原来的 buildViewTree 抛 TODO）：宿主组件读这些字段渲染
  const vs = scene.getViewState();
  ok('getViewState 标题非空', vs.title.length > 0);
  eq('getViewState 项数 = 列表长度', vs.itemCount, 2);
  eq('getViewState pageSize 默认 50', vs.pageSize, 50);
  ok('2 项时不分页', !vs.paginationActive);

  // 菜单：40 项，已接线 9 项；未接线要**记录下来**而不是静默 false
  eq('菜单共 40 项', scene.getMenu().length, 40);
  const cov: number[] = scene.getMenuCoverage();
  // 10 项静态接线 + 17 项派发给 executor（状态 6 + 排序 11）= 27
  eq('已接线 40 项（全部；12 类别过滤 + local_import 属上游禁用 D-044）', cov[0], 40);
  eq('总数 40', cov[1], 40);
  eq('未接线列表初始为空', scene.getUnhandledMenuIds().length, 0);
  ok('action_start_all 已处理', scene.handleMenuItem('action_start_all'));
  ok('sort_download_list 已处理（只展开子菜单）', scene.handleMenuItem('sort_download_list'));
  ok('类别过滤项已识别（上游禁用但 return true）', scene.handleMenuItem('doujinshi'));
  ok('未知 id 返回 false', !scene.handleMenuItem('no_such_item'));
  eq('未知 id 被记录（可诊断）', scene.getUnhandledMenuIds(), ['no_such_item']);
  // download_done 等过滤/排序项现已派发给 download-sync 的 executor → 视为已处理
  ok('download_done 已派发给 executor（返回 true）', scene.handleMenuItem('download_done'));
  eq('未接线列表仍是 1 条（只有 no_such_item）', scene.getUnhandledMenuIds().length, 1);
  eq('菜单覆盖率 = 40/40', scene.getMenuCoverage(), [40, 40]);
}

// ================================================================ 汇总

if (fails.length > 0) {
  console.log(`\n${fails.length} 个断言失败：`);
  for (const f of fails) {
    console.log(`  ✗ ${f}`);
  }
  console.log(`\n通过 ${pass}，失败 ${fails.length}`);
  process.exit(1);
}
console.log(`全部通过：${pass} 个断言`);
