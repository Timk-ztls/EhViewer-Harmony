/*
 * DownloadListDataSource 单测
 *
 * 钉住的是**两个"位置"的换算**（屏幕位置 ↔ 列表下标）：
 *   分页生效（list > 500 且 isCanPagination）时，
 *     positionInList(p)  = p + pageSize * (indexPage - 1)
 *     listIndexInPage(p) = p % pageSize
 *   否则两者相等。
 *
 * 这里最容易错的三处：
 *   1. 阈值是 **> 500**（不是 >=）—— 恰好 500 项时应**不分页**
 *   2. 最后一页的条数是 `min(pageSize, total - start)`，不是固定 pageSize
 *   3. 页号超出（数据变少后没回到第 1 页）→ 返回 0 项，不能越界读
 */

import { DownloadListDataSource, DownloadDataSourceListener, DownloadOrderWriter } from '../../main/ets/hippo/ehviewer/ui/scene/download/DownloadListDataSource';
import { DownloadAdapterCallbackLike } from '../../main/ets/hippo/ehviewer/ui/scene/download/DownloadAdapterContracts';
import { DownloadInfo } from '../../main/ets/hippo/ehviewer/dao/DownloadInfo';
import { DownloadLabel } from '../../main/ets/hippo/ehviewer/dao/DownloadLabel';
import { DownloadsDao } from '../../main/ets/hippo/ehviewer/dao/DownloadsDao';
import { QuickSearch } from '../../main/ets/hippo/ehviewer/dao/QuickSearch';
import { Filter } from '../../main/ets/hippo/ehviewer/dao/Filter';
import { DaoMaster } from '../../main/ets/hippo/ehviewer/dao/DaoMaster';
import { DaoSession } from '../../main/ets/hippo/ehviewer/dao/DaoSession';
import { EhDB } from '../../main/ets/hippo/ehviewer/EhDB';
import { EhDbFilterStore } from '../../main/ets/hippo/ehviewer/db/EhDbFilterStore';
import { EhFilter, FilterLike } from '../../main/ets/hippo/ehviewer/client/EhFilter';
import { SpiderInfo } from '../../main/ets/hippo/ehviewer/spider/SpiderInfo';
import relationalStore from '@ohos.data.relationalStore';

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

/** 按上游语义实现的假 callback（公式直接照抄，不掺入被测代码的判断）。 */
class FakeCallback implements DownloadAdapterCallbackLike {
  list: DownloadInfo[] = [];
  pageSize: number = 50;
  indexPage: number = 1;
  canPaginate: boolean = true;
  paginationSize: number = 500;

  getIndexPage(): number {
    return this.indexPage;
  }

  getPageSize(): number {
    return this.pageSize;
  }

  getPaginationSize(): number {
    return this.paginationSize;
  }

  isCanPagination(): boolean {
    return this.canPaginate;
  }

  private active(): boolean {
    return this.list.length > this.paginationSize && this.canPaginate;
  }

  positionInList(position: number): number {
    return this.active() ? position + this.pageSize * (this.indexPage - 1) : position;
  }

  listIndexInPage(position: number): number {
    return this.active() ? position % this.pageSize : position;
  }

  getList(): DownloadInfo[] {
    return this.list;
  }

  getSpiderInfoMap(): Map<number, SpiderInfo> {
    return new Map<number, SpiderInfo>();
  }

  getDownloadManager(): Object | null {
    return null;
  }
}

function buildList(count: number): DownloadInfo[] {
  const out: DownloadInfo[] = [];
  for (let i = 0; i < count; i++) {
    out.push(new DownloadInfo(1000 + i));
  }
  return out;
}

class Recorder implements DownloadDataSourceListener {
  reloads: number = 0;
  changes: number[] = [];

  onDataReloaded(): void {
    this.reloads++;
  }

  onDataChange(index: number): void {
    this.changes.push(index);
  }
}

// ================================================================ 1) 不分页（未达阈值）

{
  const cb: FakeCallback = new FakeCallback();
  cb.list = buildList(499);
  const ds: DownloadListDataSource = new DownloadListDataSource(cb);
  eq('499 项 < 500 → 全量', ds.totalCount(), 499);
  eq('不分页 → getData(0) 是首项', ds.getData(0) !== null ? ds.getData(0)!.getGid() : -1, 1000);
  eq('不分页 → getData(498) 是末项', ds.getData(498) !== null ? ds.getData(498)!.getGid() : -1, 1498);
  eq('不分页 → getData(499) 越界返回 null', ds.getData(499), null);
  eq('不分页 → indexInPage 原样', ds.indexInPage(7), 7);
}

// ================================================================ 2) 阈值边界：恰好 500 项**不分页**（> 不是 >=）

{
  const cb: FakeCallback = new FakeCallback();
  cb.list = buildList(500);
  const ds: DownloadListDataSource = new DownloadListDataSource(cb);
  eq('恰好 500 项 → 不分页（全部 500 项）', ds.totalCount(), 500);
  eq('恰好 500 项 → getData(499) 仍是末项', ds.getData(499) !== null ? ds.getData(499)!.getGid() : -1, 1499);

  cb.list = buildList(501);
  eq('501 项 → 开始分页（首页 = pageSize）', ds.totalCount(), 50);
  eq('501 项分页后 → getData(0) 仍是首项', ds.getData(0) !== null ? ds.getData(0)!.getGid() : -1, 1000);
}

// ================================================================ 3) 分页换算（pageSize=50）

{
  const cb: FakeCallback = new FakeCallback();
  cb.list = buildList(501);
  cb.pageSize = 50;
  cb.indexPage = 1;
  const ds: DownloadListDataSource = new DownloadListDataSource(cb);

  eq('第 1 页 = 50 项', ds.totalCount(), 50);

  cb.indexPage = 2;
  eq('第 2 页 = 50 项', ds.totalCount(), 50);
  eq('第 2 页 getData(0) → 列表下标 50 → gid 1050',
    ds.getData(0) !== null ? ds.getData(0)!.getGid() : -1, 1050);
  eq('第 2 页 getData(49) → 列表下标 99 → gid 1099',
    ds.getData(49) !== null ? ds.getData(49)!.getGid() : -1, 1099);
  eq('第 2 页 indexInPage(7) = 7', ds.indexInPage(7), 7);

  cb.indexPage = 11;
  eq('最后一页只剩 1 项（501 - 500）', ds.totalCount(), 1);
  eq('最后一页 getData(0) → gid 1500', ds.getData(0) !== null ? ds.getData(0)!.getGid() : -1, 1500);

  cb.indexPage = 12;
  eq('页号超出 → 0 项（不越界读）', ds.totalCount(), 0);
  eq('页号超出 → getData(0) = null', ds.getData(0), null);
}

// ================================================================ 4) pageSize 异常（控件未回报）

{
  const cb: FakeCallback = new FakeCallback();
  cb.list = buildList(600);
  cb.pageSize = 0;
  const ds: DownloadListDataSource = new DownloadListDataSource(cb);
  eq('pageSize = 0 → 退化为不分页（不除零）', ds.totalCount(), 600);
  ok('pageSize = 0 时仍能取数据', ds.getData(5) !== null);
}

// ================================================================ 5) 通知：reload + 列表下标→屏幕位置

{
  const cb: FakeCallback = new FakeCallback();
  cb.list = buildList(501);
  cb.pageSize = 50;
  cb.indexPage = 2;
  const ds: DownloadListDataSource = new DownloadListDataSource(cb);
  const rec: Recorder = new Recorder();
  ds.registerDataChangeListener(rec);
  eq('注册后只有一个监听器（重复注册去重）', (ds.registerDataChangeListener(rec), 1), 1);

  ds.reload();
  eq('reload → onDataReloaded', rec.reloads, 1);

  // 第 2 页（列表下标 50..99）→ 屏幕位置 0..49
  ds.notifyItemChanged(55);
  eq('第 2 页内的项 → 屏幕位置 5', rec.changes, [5]);

  ds.notifyItemChanged(10);      // 不在当前页 → 不通知（不能刷到错误的行）
  eq('不在当前页的项 → 不通知', rec.changes, [5]);

  ds.notifyItemChanged(120);     // 越界 → 不通知
  eq('越界下标 → 不通知', rec.changes, [5]);

  ds.unregisterDataChangeListener(rec);
  ds.reload();
  eq('注销后不再收到通知', rec.reloads, 1);
}


// ================================================================ 6) 拖动排序（canDrag / canDrop / moveItem）

class FakeOrderWriter {
  moves: string[] = [];

  moveDownload(from: number, to: number): void {
    this.moves.push(`${from}->${to}`);
  }
}

{
  const cb: FakeCallback = new FakeCallback();
  cb.list = buildList(5);
  const ds: DownloadListDataSource = new DownloadListDataSource(cb);

  ok('canDrag(0) 为真（开关开启且有效位置）', ds.canDrag(0));
  ok('canDrag(99) 为假（越界）', !ds.canDrag(99));

  // 同标签（都是 null）→ 允许
  ok('canDrop 同标签允许', ds.canDrop(0, 3));

  // 跨标签 → 禁止（不能静默改变归属）
  cb.list[3].setLabel('B');
  ok('canDrop 跨标签禁止', !ds.canDrop(0, 3));
  eq('moveItem 跨标签被拒绝', ds.moveItem(0, 3), false);

  // 未注入 writer → 拒绝而不是假装成功
  cb.list[3].setLabel(null);
  eq('未注入 DownloadOrderWriter → moveItem 返回 false', ds.moveItem(0, 3), false);

  // 注入 writer 后：下标正确透传（不分页时屏幕位置 == 列表下标）
  const writer: FakeOrderWriter = new FakeOrderWriter();
  ds.setOrderWriter(writer as unknown as DownloadOrderWriter);
  eq('注入后 moveItem 成功', ds.moveItem(1, 4), true);
  eq('writer 收到的是列表下标', writer.moves, ['1->4']);
}
// ================================================================ 7) DownloadsDao / EhDB / EhDbFilterStore / DownloadInfo 假库验证

class MemResultSet implements relationalStore.ResultSet {
  rowCount: number;
  private readonly cols: string[];
  private readonly rows: Array<Array<relationalStore.ValueType>>;
  private idx: number = -1;

  constructor(cols: string[], rows: Array<Array<relationalStore.ValueType>>) {
    this.cols = cols;
    this.rows = rows;
    this.rowCount = rows.length;
  }

  getColumnIndex(name: string): number {
    return this.cols.indexOf(name);
  }

  isColumnNull(index: number): boolean {
    return this.idx < 0 || this.idx >= this.rows.length ||
      this.rows[this.idx][index] === null || this.rows[this.idx][index] === undefined;
  }

  getString(index: number): string {
    return String(this.rows[this.idx][index]);
  }

  getLong(index: number): number {
    return Number(this.rows[this.idx][index]);
  }

  getDouble(index: number): number {
    return Number(this.rows[this.idx][index]);
  }

  goToNextRow(): boolean {
    this.idx++;
    return this.idx < this.rows.length;
  }

  goToFirstRow(): boolean {
    this.idx = 0;
    return this.rows.length > 0;
  }

  close(): void {
  }
}

class MemRdbStore implements relationalStore.RdbStore {
  version: number = DaoMaster.SCHEMA_VERSION;
  nextId: number = 10;
  execSqls: string[] = [];
  txCommits: number = 0;
  txRollbacks: number = 0;
  closed: boolean = false;
  dirnameMap: Map<number, string> = new Map<number, string>();
  filterRows: Map<number, Filter> = new Map<number, Filter>();
  downloadsCols: string[] = [
    'GID', 'TOKEN', 'TITLE', 'TITLE_JPN', 'THUMB', 'CATEGORY', 'POSTED', 'UPLOADER',
    'RATING', 'SIMPLE_LANGUAGE', 'STATE', 'LEGACY', 'TIME', 'LABEL', 'ARCHIVE_URI'
  ];
  downloadRows: Array<Array<relationalStore.ValueType>> = [];
  labelInserts: Array<relationalStore.ValuesBucket> = [];
  delayFirstDirnameLoad: boolean = false;

  async insert(table: string, values: relationalStore.ValuesBucket): Promise<number> {
    if (table === 'DOWNLOAD_DIRNAME') {
      const gid: number = Number(values['GID']);
      this.dirnameMap.set(gid, String(values['DIRNAME']));
      return gid;
    }
    if (table === 'DOWNLOAD_LABELS') {
      this.labelInserts.push(values);
      return ++this.nextId;
    }
    if (table === 'FILTER') {
      const id: number = ++this.nextId;
      const f: Filter = new Filter(id, Number(values['MODE']), String(values['TEXT']), Number(values['ENABLE']) !== 0);
      this.filterRows.set(id, f);
      return id;
    }
    return ++this.nextId;
  }

  async update(values: relationalStore.ValuesBucket, predicates: relationalStore.RdbPredicates): Promise<number> {
    const p: Record<string, Object> = predicates as unknown as Record<string, Object>;
    const table: string = p['tableName'] !== undefined ? String(p['tableName']) : '';
    const keyVal: number = p['lastValue'] !== undefined ? Number(p['lastValue']) : -1;
    if (table === 'DOWNLOAD_DIRNAME' || values['DIRNAME'] !== undefined) {
      this.dirnameMap.set(keyVal, String(values['DIRNAME']));
    }
    if (values['ENABLE'] !== undefined && this.filterRows.has(keyVal)) {
      const f: Filter = this.filterRows.get(keyVal) as Filter;
      f.setEnable(Number(values['ENABLE']) !== 0);
    }
    return 1;
  }

  async delete(predicates: relationalStore.RdbPredicates): Promise<number> {
    const p: Record<string, Object> = predicates as unknown as Record<string, Object>;
    const keyVal: number = p['lastValue'] !== undefined ? Number(p['lastValue']) : -1;
    this.filterRows.delete(keyVal);
    return 1;
  }

  async querySql(sql: string, args?: Array<relationalStore.ValueType>): Promise<relationalStore.ResultSet> {
    if (sql.indexOf('PRAGMA user_version') >= 0) {
      return new MemResultSet(['user_version'], [[this.version]]);
    }
    if (sql.indexOf('FROM "DOWNLOADS"') >= 0) {
      return new MemResultSet(this.downloadsCols, this.downloadRows);
    }
    if (sql.indexOf('FROM "DOWNLOAD_DIRNAME"') >= 0 && args !== undefined && args.length > 0) {
      const gid: number = Number(args[0]);
      if (this.delayFirstDirnameLoad) {
        this.delayFirstDirnameLoad = false;
        await new Promise<void>((resolve: () => void): void => {
          setTimeout((): void => {
            resolve();
          }, 15);
        });
      }
      if (this.dirnameMap.has(gid)) {
        return new MemResultSet(['GID', 'DIRNAME'], [[gid, this.dirnameMap.get(gid) as string]]);
      }
      return new MemResultSet(['GID', 'DIRNAME'], []);
    }
    if (sql.indexOf('FROM "FILTER"') >= 0) {
      const out: Array<Array<relationalStore.ValueType>> = [];
      this.filterRows.forEach((f: Filter): void => {
        out.push([f.getId(), f.getMode(), f.getText(), f.getEnable() === true ? 1 : 0]);
      });
      return new MemResultSet(['_id', 'MODE', 'TEXT', 'ENABLE'], out);
    }
    if (sql.indexOf('FROM "DOWNLOAD_LABELS"') >= 0) {
      return new MemResultSet(['_id', 'LABEL', 'TIME'], [[1, 'ExtLbl', 50]]);
    }
    return new MemResultSet([], []);
  }

  async executeSql(sql: string): Promise<void> {
    this.execSqls.push(sql);
  }

  beginTransaction(): void {
  }

  commit(): void {
    this.txCommits++;
  }

  rollBack(): void {
    this.txRollbacks++;
  }

  async close(): Promise<void> {
    this.closed = true;
  }
}

class CustomFilter implements FilterLike {
  mode: number;
  text: string;
  enable: boolean;

  constructor(mode: number, text: string, enable: boolean) {
    this.mode = mode;
    this.text = text;
    this.enable = enable;
  }

  getMode(): number {
    return this.mode;
  }

  getText(): string {
    return this.text;
  }

  setText(t: string): void {
    this.text = t;
  }

  isEnable(): boolean {
    return this.enable;
  }

  setEnable(e: boolean): void {
    this.enable = e;
  }

  getId(): number {
    return -1;
  }
}

async function runAsyncDownloadDbTests(): Promise<void> {
  const proto: Record<string, Object | null> =
    relationalStore.RdbPredicates.prototype as unknown as Record<string, Object | null>;
  if (typeof proto['equalTo'] !== 'function') {
    proto['equalTo'] = function (this: Record<string, Object | null>, field: string,
      value: relationalStore.ValueType): Object {
      this['lastField'] = field;
      this['lastValue'] = value;
      return this;
    };
  }

  const targetStore: MemRdbStore = new MemRdbStore();
  EhDB.attach(DaoSession.fromStore(targetStore));

  // 7a) DownloadsDao QueryBuilder fresh + LIMIT 0 + getAllDownloadInfo 状态重置
  const dlDao: DownloadsDao = new DownloadsDao(targetStore);
  ok('DownloadsDao.queryBuilder() 返回独立实例', dlDao.queryBuilder() !== dlDao.queryBuilder());
  eq('DownloadsDao.limit(0)', dlDao.queryBuilder().limit(0).sql(), 'SELECT * FROM "DOWNLOADS" LIMIT 0');

  targetStore.downloadRows = [
    [1, 't1', 'wait', '', '', 1, '', '', 3.0, null, DownloadInfo.STATE_WAIT, 0, 100, null, null],
    [2, 't2', 'dl', '', '', 1, '', '', 3.0, null, DownloadInfo.STATE_DOWNLOAD, 0, 90, null, null],
    [3, 't3', 'done', '', '', 1, '', '', 3.0, null, DownloadInfo.STATE_FINISH, 0, 80, null, null]
  ];
  const dlList: DownloadInfo[] = await EhDB.getAllDownloadInfo();
  eq('getAllDownloadInfo STATE_WAIT → STATE_NONE', dlList[0].state, DownloadInfo.STATE_NONE);
  eq('getAllDownloadInfo STATE_DOWNLOAD → STATE_NONE', dlList[1].state, DownloadInfo.STATE_NONE);
  eq('getAllDownloadInfo 保留 STATE_FINISH', dlList[2].state, DownloadInfo.STATE_FINISH);

  // 7b) addDownloadLabel(DownloadLabel) 置 null _id + moveDownloadLabel 越界保护
  const lbl: DownloadLabel = new DownloadLabel(888, 'Custom', 200);
  const savedLbl: DownloadLabel = await EhDB.addDownloadLabel(lbl);
  eq('addDownloadLabel(DownloadLabel) 插入前 id 置 null',
    targetStore.labelInserts[0]['_id'] === undefined ? null : targetStore.labelInserts[0]['_id'], null);
  ok('addDownloadLabel 回填新 _id (非 888)', savedLbl.getId() !== 888 && savedLbl.getId() !== null);
  await EhDB.moveDownloadLabel(-1, 2);
  await EhDB.moveDownloadLabel(0, -1);
  ok('moveDownloadLabel 负下标安全返回', true);

  // 7c) EhDB.serial 串行化并发 check-then-insert（避免重复 insert）
  targetStore.delayFirstDirnameLoad = true;
  await Promise.all([
    EhDB.putDownloadDirname(404, 'dirA'),
    EhDB.putDownloadDirname(404, 'dirB')
  ]);
  eq('EhDB.serial 并发 putDownloadDirname 后最终值为 dirB', targetStore.dirnameMap.get(404), 'dirB');

  // 7d) EhDB.migrate v1 -> 建 FILTER 表
  const migStore: MemRdbStore = new MemRdbStore();
  await EhDB.migrate(migStore, 1);
  ok('EhDB.migrate(1) 创建 FILTER 表后再升级',
    migStore.execSqls.some((s: string): boolean => s.indexOf('CREATE TABLE IF NOT EXISTS "FILTER"') >= 0));

  // 7e) EhDB.exportDB 清理临时库 + 建 v8 + 含 BOOKMARKS/Black_List + 写回调失败返回 false
  const expDeleted: string[] = [];
  const expStore: MemRdbStore = new MemRdbStore();
  const expOk: boolean = await EhDB.exportDB(
    targetStore,
    '/tmp/out.db',
    async (_name: string): Promise<relationalStore.RdbStore> => expStore,
    async (name: string): Promise<void> => {
      expDeleted.push(name);
    },
    async (_name: string, _dest: string): Promise<boolean> => true
  );
  eq('exportDB 成功返回 true', expOk, true);
  eq('exportDB 前后均删除 eh.export.db', expDeleted, ['eh.export.db', 'eh.export.db']);
  ok('exportDB 初始化 BOOKMARKS 表',
    expStore.execSqls.some((s: string): boolean => s.indexOf('"BOOKMARKS"') >= 0));
  ok('exportDB 初始化 Black_List 表',
    expStore.execSqls.some((s: string): boolean => s.indexOf('"Black_List"') >= 0));
  ok('exportDB 关闭临时 store', expStore.closed);

  // 7f) EhDB.importDB 向外部回调传递 DownloadLabel[] / DownloadInfo[] 并包装事务
  let receivedLabels: number = -1;
  let receivedDownloads: number = -1;
  targetStore.txCommits = 0;
  const srcStore: MemRdbStore = new MemRdbStore();
  srcStore.version = DaoMaster.SCHEMA_VERSION;
  srcStore.downloadRows = [
    [99, 'tok', 'ext', '', '', 1, '', '', 3.5, null, DownloadInfo.STATE_FINISH, 0, 50, null, null]
  ];
  const impErr: string | null = await EhDB.importDB(
    srcStore,
    null,
    async (list: DownloadInfo[]): Promise<void> => {
      receivedDownloads = list.length;
    },
    async (list: DownloadLabel[]): Promise<void> => {
      receivedLabels = list.length;
    }
  );
  eq('importDB 成功返回 null', impErr, null);
  eq('importDB 传递 external labels', receivedLabels, 1);
  eq('importDB 传递 external downloads', receivedDownloads, 1);
  eq('importDB 目标写入提交事务', targetStore.txCommits, 1);

  const futureStore: MemRdbStore = new MemRdbStore();
  futureStore.version = 999;
  eq('importDB 高版本返回 cant_read_the_file',
    await EhDB.importDB(futureStore, null, null, null), 'cant_read_the_file');

  // 7g) EhDbFilterStore：reload 未完成前 isLoaded=false；add -> trigger -> delete 同步突发串行一致性
  const fStore: EhDbFilterStore = new EhDbFilterStore();
  targetStore.filterRows.clear();
  const initialCall = fStore.getAllFilter();
  eq('EhDbFilterStore 未完成前返回空缓存', initialCall.length, 0);
  await fStore.reload();
  eq('EhDbFilterStore reload 完成后 isLoaded=true', fStore.isLoaded(), true);

  const cf: CustomFilter = new CustomFilter(EhFilter.MODE_TITLE, 'MixedCase', false);
  fStore.addFilter(cf);
  fStore.triggerFilter(cf);
  await new Promise<void>((resolve: () => void): void => {
    setTimeout((): void => {
      resolve();
    }, 30);
  });
  eq('EhDbFilterStore 同步 add→trigger 在 DB 中最终为 enable=false',
    Array.from(targetStore.filterRows.values())[0].getEnable(), false);
  fStore.deleteFilter(cf);
  await new Promise<void>((resolve: () => void): void => {
    setTimeout((): void => {
      resolve();
    }, 30);
  });
  eq('EhDbFilterStore deleteFilter 从库中删除记录', targetStore.filterRows.size, 0);
  eq('EhDbFilterStore unsupportedOps=0', fStore.getUnsupportedOpCount(), 0);
}

// ================================================================ 汇总

runAsyncDownloadDbTests().then((): void => {
  if (fails.length > 0) {
    console.log(`\n${fails.length} 个断言失败：`);
    for (const f of fails) {
      console.log(`  ✗ ${f}`);
    }
    console.log(`\n通过 ${pass}，失败 ${fails.length}`);
    process.exit(1);
  }
  console.log(`全部通过：${pass} 个断言`);
}).catch((err: Object): void => {
  console.log(`异常终止: ${(err as Error).message}`);
  process.exit(1);
});
