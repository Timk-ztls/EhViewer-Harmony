/*
 * DaoSession.fromStore 单测
 *
 * 它解锁 `EhDB.exportDB` / `importDB`（把行读/写进**第二个库**）与 `RestoreDownloadPreference`。
 * 断言重点不是"能 new"，而是**语义约束**：
 *   1) 用第二个 store 造出的 session，所有 DAO 都绑在**那个** store 上（不是默认库）
 *   2) 每次 fromStore 都是**新实例**（DAO 缓存不共享）——与上游 `new DaoSession(db)` 一致
 *   3) 不要用它替换默认 session（文档约束；这里通过"两次调用互不影响"间接体现）
 *   4) `getStore()` 能取回绑定对象（导出/导入需要确认连的是哪个库）
 */

import { DaoSession } from '../../main/ets/hippo/ehviewer/dao/DaoSession';
import { DaoMaster } from '../../main/ets/hippo/ehviewer/dao/DaoMaster';
import { MSQLiteOpenHelper } from '../../main/ets/hippo/database/MSQLiteOpenHelper';
import { GalleryTagsDao } from '../../main/ets/hippo/ehviewer/dao/GalleryTagsDao';
import { DownloadsDao } from '../../main/ets/hippo/ehviewer/dao/DownloadsDao';
import { DownloadLabelDao } from '../../main/ets/hippo/ehviewer/dao/DownloadLabelDao';
import { DownloadDirnameDao } from '../../main/ets/hippo/ehviewer/dao/DownloadDirnameDao';
import { HistoryDao } from '../../main/ets/hippo/ehviewer/dao/HistoryDao';
import { QuickSearchDao } from '../../main/ets/hippo/ehviewer/dao/QuickSearchDao';
import { BlackListDao } from '../../main/ets/hippo/ehviewer/dao/BlackListDao';
import { LocalFavoritesDao } from '../../main/ets/hippo/ehviewer/dao/LocalFavoritesDao';
import { BookmarksBao } from '../../main/ets/hippo/ehviewer/dao/BookmarksBao';
import { FilterDao } from '../../main/ets/hippo/ehviewer/dao/FilterDao';
import { DownloadLabel } from '../../main/ets/hippo/ehviewer/dao/DownloadLabel';
import { QuickSearch } from '../../main/ets/hippo/ehviewer/dao/QuickSearch';
import { Filter } from '../../main/ets/hippo/ehviewer/dao/Filter';
import { BlackList } from '../../main/ets/hippo/ehviewer/dao/BlackList';
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

/**
 * 假 store：DAO 的构造器只保存引用，不会立刻触库，
 * 所以这里只需要一个"可辨识身份"的对象即可验证绑定关系。
 */
interface FakeStore {
  tag: string;
  version: number;
}

function makeStore(tag: string): FakeStore {
  return { tag: tag, version: 8 };
}

/** 把假 store 当 RdbStore 传进去（测试专用；生产由 relationalStore.getRdbStore 返回真实对象）。 */
function asStore(fake: FakeStore): relationalStore.RdbStore {
  return fake as unknown as relationalStore.RdbStore;
}

// ================================================================ 1) 绑定的是传入的那个 store

{
  const s1: FakeStore = makeStore('db-one');
  const session: DaoSession = DaoSession.fromStore(asStore(s1));
  ok('fromStore 返回非 null', session !== null);
  ok('getStore 取回同一个 store 对象', (session.getStore() as unknown as FakeStore) === s1);
  eq('getStore().tag 正确', (session.getStore() as unknown as FakeStore).tag, 'db-one');

  // 10 个 DAO 都能取到，且都是非 null（懒加载不触库）
  ok('getGalleryTagsDao', session.getGalleryTagsDao() !== null);
  ok('getDownloadsDao', session.getDownloadsDao() !== null);
  ok('getDownloadLabelDao', session.getDownloadLabelDao() !== null);
  ok('getDownloadDirnameDao', session.getDownloadDirnameDao() !== null);
  ok('getHistoryDao', session.getHistoryDao() !== null);
  ok('getQuickSearchDao', session.getQuickSearchDao() !== null);
  ok('getBlackListDao', session.getBlackListDao() !== null);
  ok('getLocalFavoritesDao', session.getLocalFavoritesDao() !== null);
  ok('getBookmarksBao', session.getBookmarksBao() !== null);
  ok('getFilterDao', session.getFilterDao() !== null);
}

// ================================================================ 2) 每次都是新实例（DAO 缓存不共享）

{
  const store: FakeStore = makeStore('db-two');
  const a: DaoSession = DaoSession.fromStore(asStore(store));
  const b: DaoSession = DaoSession.fromStore(asStore(store));
  ok('两次 fromStore 得到不同 session', a !== b);
  ok('两个 session 的 DAO 实例也不同（没有共享缓存）',
    a.getDownloadsDao() !== b.getDownloadsDao());
  ok('但两者绑定同一个 store', a.getStore() === b.getStore());

  // 同一 session 内 DAO 是懒加载缓存的（取两次是同一个对象）
  ok('同一 session 内 getDownloadsDao 幂等', a.getDownloadsDao() === a.getDownloadsDao());
}

// ================================================================ 3) 两个库互不影响（导出/导入的典型用法）

{
  const src: FakeStore = makeStore('db-source');
  const dst: FakeStore = makeStore('db-target');
  const srcSession: DaoSession = DaoSession.fromStore(asStore(src));
  const dstSession: DaoSession = DaoSession.fromStore(asStore(dst));
  eq('源 session 连的是源库', (srcSession.getStore() as unknown as FakeStore).tag, 'db-source');
  eq('目标 session 连的是目标库', (dstSession.getStore() as unknown as FakeStore).tag, 'db-target');
  ok('两个 session 的 downloadsDao 各自绑定各自库', srcSession.getDownloadsDao() !== dstSession.getDownloadsDao());
}

// ================================================================ 4) clear() 是空操作（无 identity scope）

{
  const session: DaoSession = DaoSession.fromStore(asStore(makeStore('db-three')));
  let threw: boolean = false;
  try {
    session.clear();
  } catch (e) {
    threw = true;
  }
  ok('clear() 不抛错（本 port 无 identity scope）', !threw);
  ok('clear() 后 DAO 仍可用', session.getFilterDao() !== null);
}

// ================================================================ 5) QueryBuilder 新实例、LIMIT 0、save() 主键回填 & dropAllTable 游标关闭

class FakeResultSet implements relationalStore.ResultSet {
  rowCount: number;
  private readonly cols: string[];
  private readonly rows: Array<Array<relationalStore.ValueType>>;
  private cursor: number = -1;
  closedCount: number = 0;

  constructor(cols: string[], rows: Array<Array<relationalStore.ValueType>>) {
    this.cols = cols;
    this.rows = rows;
    this.rowCount = rows.length;
  }

  getColumnIndex(name: string): number {
    return this.cols.indexOf(name);
  }

  isColumnNull(index: number): boolean {
    if (this.cursor < 0 || this.cursor >= this.rows.length) {
      return true;
    }
    const v: relationalStore.ValueType = this.rows[this.cursor][index];
    return v === null || v === undefined;
  }

  getString(index: number): string {
    return String(this.rows[this.cursor][index]);
  }

  getLong(index: number): number {
    return Number(this.rows[this.cursor][index]);
  }

  getDouble(index: number): number {
    return Number(this.rows[this.cursor][index]);
  }

  goToNextRow(): boolean {
    this.cursor++;
    return this.cursor < this.rows.length;
  }

  close(): void {
    this.closedCount++;
  }
}

interface RecordedInsert {
  table: string;
  values: relationalStore.ValuesBucket;
}

class FakeDaoRdbStore implements relationalStore.RdbStore {
  version: number = DaoMaster.SCHEMA_VERSION;
  nextRowId: number = 100;
  inserts: RecordedInsert[] = [];
  updates: number = 0;
  deletes: number = 0;
  execSqls: string[] = [];
  queries: string[] = [];
  resultSets: FakeResultSet[] = [];
  queryHandler: ((sql: string, args?: Array<relationalStore.ValueType>) => FakeResultSet) | null = null;
  execHandler: ((sql: string) => void) | null = null;

  async insert(table: string, values: relationalStore.ValuesBucket,
    _conflict?: relationalStore.ConflictResolution): Promise<number> {
    const id: number = ++this.nextRowId;
    this.inserts.push({ table: table, values: values });
    return id;
  }

  async update(_values: relationalStore.ValuesBucket,
    _predicates: relationalStore.RdbPredicates): Promise<number> {
    this.updates++;
    return 1;
  }

  async delete(_predicates: relationalStore.RdbPredicates): Promise<number> {
    this.deletes++;
    return 1;
  }

  async querySql(sql: string, args?: Array<relationalStore.ValueType>): Promise<relationalStore.ResultSet> {
    this.queries.push(sql);
    const rs: FakeResultSet = this.queryHandler !== null
      ? this.queryHandler(sql, args)
      : new FakeResultSet([], []);
    this.resultSets.push(rs);
    return rs;
  }

  async executeSql(sql: string, _args?: Array<relationalStore.ValueType>): Promise<void> {
    this.execSqls.push(sql);
    if (this.execHandler !== null) {
      this.execHandler(sql);
    }
  }

  beginTransaction(): void {
  }

  commit(): void {
  }

  rollBack(): void {
  }

  async close(): Promise<void> {
  }
}

function installPredicatesEqualToStub(): void {
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
}

async function runAsyncDaoTests(): Promise<void> {
  installPredicatesEqualToStub();

  const fake: FakeDaoRdbStore = new FakeDaoRdbStore();
  const s: DaoSession = DaoSession.fromStore(fake);

  // 5a) 所有 10 个 DAO 的 queryBuilder() 每次返回全新实例且条件不串扰
  {
    const gt = s.getGalleryTagsDao();
    ok('GalleryTagsDao queryBuilder 每次新实例', gt.queryBuilder() !== gt.queryBuilder());
    gt.queryBuilder().where(GalleryTagsDao.Properties.Gid.eq(1)).orderDesc(GalleryTagsDao.Properties.Gid).limit(5).offset(2);
    eq('GalleryTagsDao 全新 builder 不残留条件', gt.queryBuilder().sql(), 'SELECT * FROM "Gallery_Tags"');
    eq('GalleryTagsDao limit(0)', gt.queryBuilder().limit(0).sql(), 'SELECT * FROM "Gallery_Tags" LIMIT 0');

    const dl = s.getDownloadsDao();
    ok('DownloadsDao queryBuilder 每次新实例', dl.queryBuilder() !== dl.queryBuilder());
    dl.queryBuilder().where(DownloadsDao.Properties.Gid.eq(2)).limit(9).offset(1);
    eq('DownloadsDao 全新 builder 不残留条件', dl.queryBuilder().sql(), 'SELECT * FROM "DOWNLOADS"');
    eq('DownloadsDao limit(0)+offset(3)', dl.queryBuilder().limit(0).offset(3).sql(),
      'SELECT * FROM "DOWNLOADS" LIMIT 0 OFFSET 3');

    const lbl = s.getDownloadLabelDao();
    ok('DownloadLabelDao queryBuilder 每次新实例', lbl.queryBuilder() !== lbl.queryBuilder());
    lbl.queryBuilder().where(DownloadLabelDao.Properties.Label.eq('a')).limit(4);
    eq('DownloadLabelDao 全新 builder 不残留条件', lbl.queryBuilder().sql(), 'SELECT * FROM "DOWNLOAD_LABELS"');
    eq('DownloadLabelDao limit(0)', lbl.queryBuilder().limit(0).sql(), 'SELECT * FROM "DOWNLOAD_LABELS" LIMIT 0');

    const dn = s.getDownloadDirnameDao();
    ok('DownloadDirnameDao queryBuilder 每次新实例', dn.queryBuilder() !== dn.queryBuilder());
    dn.queryBuilder().where(DownloadDirnameDao.Properties.Gid.eq(3)).limit(4);
    eq('DownloadDirnameDao 全新 builder 不残留条件', dn.queryBuilder().sql(), 'SELECT * FROM "DOWNLOAD_DIRNAME"');
    eq('DownloadDirnameDao limit(0)', dn.queryBuilder().limit(0).sql(), 'SELECT * FROM "DOWNLOAD_DIRNAME" LIMIT 0');

    const hs = s.getHistoryDao();
    ok('HistoryDao queryBuilder 每次新实例', hs.queryBuilder() !== hs.queryBuilder());
    hs.queryBuilder().where(HistoryDao.Properties.Gid.eq(4)).limit(4);
    eq('HistoryDao 全新 builder 不残留条件', hs.queryBuilder().sql(), 'SELECT * FROM "HISTORY"');
    eq('HistoryDao limit(0)', hs.queryBuilder().limit(0).sql(), 'SELECT * FROM "HISTORY" LIMIT 0');

    const qs = s.getQuickSearchDao();
    ok('QuickSearchDao queryBuilder 每次新实例', qs.queryBuilder() !== qs.queryBuilder());
    qs.queryBuilder().where(QuickSearchDao.Properties.Name.eq('q')).limit(4);
    eq('QuickSearchDao 全新 builder 不残留条件', qs.queryBuilder().sql(), 'SELECT * FROM "QUICK_SEARCH"');
    eq('QuickSearchDao limit(0)', qs.queryBuilder().limit(0).sql(), 'SELECT * FROM "QUICK_SEARCH" LIMIT 0');

    const bl = s.getBlackListDao();
    ok('BlackListDao queryBuilder 每次新实例', bl.queryBuilder() !== bl.queryBuilder());
    bl.queryBuilder().where(BlackListDao.Properties.Badgayname.eq('u')).limit(4);
    eq('BlackListDao 全新 builder 不残留条件', bl.queryBuilder().sql(), 'SELECT * FROM "Black_List"');
    eq('BlackListDao limit(0)', bl.queryBuilder().limit(0).sql(), 'SELECT * FROM "Black_List" LIMIT 0');

    const lf = s.getLocalFavoritesDao();
    ok('LocalFavoritesDao queryBuilder 每次新实例', lf.queryBuilder() !== lf.queryBuilder());
    lf.queryBuilder().where(LocalFavoritesDao.Properties.Gid.eq(5)).limit(4);
    eq('LocalFavoritesDao 全新 builder 不残留条件', lf.queryBuilder().sql(), 'SELECT * FROM "LOCAL_FAVORITES"');
    eq('LocalFavoritesDao limit(0)', lf.queryBuilder().limit(0).sql(), 'SELECT * FROM "LOCAL_FAVORITES" LIMIT 0');

    const bm = s.getBookmarksBao();
    ok('BookmarksBao queryBuilder 每次新实例', bm.queryBuilder() !== bm.queryBuilder());
    bm.queryBuilder().where(BookmarksBao.Properties.Gid.eq(6)).limit(4);
    eq('BookmarksBao 全新 builder 不残留条件', bm.queryBuilder().sql(), 'SELECT * FROM "BOOKMARKS"');
    eq('BookmarksBao limit(0)', bm.queryBuilder().limit(0).sql(), 'SELECT * FROM "BOOKMARKS" LIMIT 0');

    const fl = s.getFilterDao();
    ok('FilterDao queryBuilder 每次新实例', fl.queryBuilder() !== fl.queryBuilder());
    fl.queryBuilder().where(FilterDao.Properties.Text.eq('t')).limit(4);
    eq('FilterDao 全新 builder 不残留条件', fl.queryBuilder().sql(), 'SELECT * FROM "FILTER"');
    eq('FilterDao limit(0)', fl.queryBuilder().limit(0).sql(), 'SELECT * FROM "FILTER" LIMIT 0');
    eq('FilterDao 仅 offset 无 limit', fl.queryBuilder().offset(2).sql(),
      'SELECT * FROM "FILTER" LIMIT -1 OFFSET 2');
  }

  // 5b) _id 自增主键 DAO save() 回填生成的 rowId，再次 save() 走 update
  {
    const dlEntity: DownloadLabel = new DownloadLabel();
    dlEntity.setLabel('MyLabel');
    dlEntity.setTime(1000);
    await s.getDownloadLabelDao().save(dlEntity);
    eq('DownloadLabelDao.save 回填 _id', dlEntity.getId(), 101);
    await s.getDownloadLabelDao().save(dlEntity);
    eq('DownloadLabelDao 二次 save 走 update', fake.updates, 1);

    const qsEntity: QuickSearch = new QuickSearch();
    qsEntity.setName('QS1');
    await s.getQuickSearchDao().save(qsEntity);
    eq('QuickSearchDao.save 回填 _id', qsEntity.getId(), 102);
    await s.getQuickSearchDao().save(qsEntity);
    eq('QuickSearchDao 二次 save 走 update', fake.updates, 2);

    const flEntity: Filter = new Filter();
    flEntity.setMode(0);
    flEntity.setText('tag:test');
    flEntity.setEnable(true);
    await s.getFilterDao().save(flEntity);
    eq('FilterDao.save 回填 _id', flEntity.getId(), 103);
    await s.getFilterDao().save(flEntity);
    eq('FilterDao 二次 save 走 update', fake.updates, 3);

    const blEntity: BlackList = new BlackList(undefined, 'bad_user');
    await s.getBlackListDao().save(blEntity);
    eq('BlackListDao.save 回填 _id', blEntity.id, 104);
  }

  // 5c) MSQLiteOpenHelper.dropAllTable：跳过 NULL 列名，并在成功与抛错路径均关闭 ResultSet
  {
    const dropStore: FakeDaoRdbStore = new FakeDaoRdbStore();
    dropStore.queryHandler = (): FakeResultSet =>
      new FakeResultSet(['name'], [[null], ['T_ONE'], ['T_TWO']]);
    await MSQLiteOpenHelper.dropAllTable(dropStore);
    eq('dropAllTable 跳过 NULL 并删除 2 张表', dropStore.execSqls,
      ['DROP TABLE IF EXISTS "T_ONE"', 'DROP TABLE IF EXISTS "T_TWO"']);
    eq('dropAllTable 关闭 ResultSet', dropStore.resultSets[0].closedCount, 1);

    const errStore: FakeDaoRdbStore = new FakeDaoRdbStore();
    errStore.queryHandler = (): FakeResultSet =>
      new FakeResultSet(['name'], [['T_FAIL']]);
    errStore.execHandler = (): void => {
      throw new Error('drop error');
    };
    let threwDrop: boolean = false;
    try {
      await MSQLiteOpenHelper.dropAllTable(errStore);
    } catch (_e) {
      threwDrop = true;
    }
    ok('dropAllTable 异常向上抛出', threwDrop);
    eq('dropAllTable 异常路径仍通过 finally 关闭 ResultSet', errStore.resultSets[0].closedCount, 1);
  }
}

// ================================================================ 汇总

runAsyncDaoTests().then((): void => {
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
