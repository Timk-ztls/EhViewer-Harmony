/*
 * `HistoryInfo.fromGalleryInfo` 单测（对位上游 `HistoryInfo(GalleryInfo)` 构造器）
 *
 * 为什么值得测：core-runtime 的 `EhDB.putHistoryInfo` 会用它把 GalleryInfo 转成 History 行。
 * 这个拷贝**多拷一列**不会报错（字段根本不存在于 HISTORY 表 → 落库时静默丢弃），
 * **少拷一列**会让历史列表缺字段（也不报错）。两类错误都只在 UI 上看得出，
 * 所以用断言把「拷哪 11 列、不拷哪 10 列」钉死。
 *
 * 判定依据是 DDL：HistoryDao.CREATE_TABLE_SQL 的列全集
 *   GID / TOKEN / TITLE / TITLE_JPN / THUMB / CATEGORY / POSTED / UPLOADER / RATING /
 *   SIMPLE_LANGUAGE / MODE / TIME
 * 其中 MODE / TIME 是 history 专有列，上游构造器不碰。
 */

import { HistoryInfo } from '../../main/ets/hippo/ehviewer/dao/HistoryInfo';
import { HistoryDao } from '../../main/ets/hippo/ehviewer/dao/HistoryDao';
import { GalleryInfo } from '../../main/ets/hippo/ehviewer/client/data/GalleryInfo';
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

/** 造一个所有字段都是非默认值的 GalleryInfo，这样"没被拷贝"的字段一眼能看出来。 */
function makeFullGalleryInfo(): GalleryInfo {
  const g: GalleryInfo = new GalleryInfo();
  g.gid = 123456;
  g.token = 'abcd1234';
  g.title = 'Title';
  g.titleJpn = 'タイトル';
  g.thumb = 'https://example.invalid/t.jpg';
  g.category = 2;
  g.posted = '2024-01-02 03:04';
  g.uploader = 'uploader';
  g.rating = 4.5;
  g.simpleLanguage = 'chinese';
  g.rated = true;
  g.simpleTags = ['tag1', 'tag2'];
  // 以下 8 个字段在 HISTORY 表里**没有列**，必须保持默认值
  g.pages = 42;
  g.thumbWidth = 1280;
  g.thumbHeight = 1810;
  g.spanSize = 6;
  g.spanIndex = 3;
  g.spanGroupIndex = 1;
  g.favoriteSlot = 3;
  g.favoriteName = 'my-favorite';
  g.tgList = ['group:artist$foo'];
  g.postedAt = 1700000000000;
  return g;
}

// ================================================================ 1) 拷贝的 11 个字段

{
  const src: GalleryInfo = makeFullGalleryInfo();
  const h: HistoryInfo = HistoryInfo.fromGalleryInfo(src);
  eq('gid', h.gid, 123456);
  eq('token', h.token, 'abcd1234');
  eq('title', h.title, 'Title');
  eq('titleJpn（非 ASCII 不丢）', h.titleJpn, 'タイトル');
  eq('thumb', h.thumb, 'https://example.invalid/t.jpg');
  eq('category', h.category, 2);
  eq('posted（字符串原样，不做 Date 转换）', h.posted, '2024-01-02 03:04');
  eq('uploader', h.uploader, 'uploader');
  eq('rating（REAL 列，保留小数）', h.rating, 4.5);
  eq('simpleLanguage', h.simpleLanguage, 'chinese');
  eq('simpleTags（共享引用，与上游同）', h.simpleTags, ['tag1', 'tag2']);
}

// ================================================================ 2) 不拷贝的字段（HISTORY 无此列）

{
  const h: HistoryInfo = HistoryInfo.fromGalleryInfo(makeFullGalleryInfo());
  eq('pages 未拷贝', h.pages, 0);
  eq('thumbWidth 未拷贝', h.thumbWidth, 0);
  eq('thumbHeight 未拷贝', h.thumbHeight, 0);
  eq('spanSize 未拷贝', h.spanSize, 0);
  eq('spanIndex 未拷贝', h.spanIndex, 0);
  eq('spanGroupIndex 未拷贝', h.spanGroupIndex, 0);
  eq('favoriteSlot 未拷贝（保持基类默认 -2）', h.favoriteSlot, -2);
  eq('favoriteName 未拷贝', h.favoriteName, null);
  eq('tgList 未拷贝', h.tgList, null);
  eq('postedAt 未拷贝', h.postedAt, -1);
  eq('rated 未拷贝', h.rated, false);
}

// ================================================================ 3) history 专有列默认值

{
  const h: HistoryInfo = HistoryInfo.fromGalleryInfo(makeFullGalleryInfo());
  eq('mode 默认 0（由调用方 setMode）', h.mode, 0);
  eq('time 默认 0（由调用方 setTime）', h.time, 0);
  // 拷贝完仍可正常 set，且不影响源对象
  h.setMode(7);
  h.setTime(1700000000000);
  eq('setMode 生效', h.getMode(), 7);
  eq('setTime 生效', h.getTime(), 1700000000000);
}

// ================================================================ 4) 边界：空 GalleryInfo

{
  const empty: GalleryInfo = new GalleryInfo();
  const h: HistoryInfo = HistoryInfo.fromGalleryInfo(empty);
  eq('空对象 gid', h.gid, 0);
  eq('空对象 title', h.title, '');
  eq('空对象 simpleLanguage（基类是 |null）', h.simpleLanguage, null);
  eq('空对象 simpleTags', h.simpleTags, null);
  eq('空对象 rating', h.rating, 0);
}

// ================================================================ 5) 独立性：改结果不影响源

{
  const src: GalleryInfo = makeFullGalleryInfo();
  const h: HistoryInfo = HistoryInfo.fromGalleryInfo(src);
  h.title = 'Changed';
  h.gid = 999;
  eq('改 HistoryInfo 不影响源 gid', src.gid, 123456);
  eq('改 HistoryInfo 不影响源 title', src.title, 'Title');
}

// ================================================================ 6) HistoryDao QueryBuilder 与 save() 假库 SQL 验证

class FakeHistoryResultSet implements relationalStore.ResultSet {
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
    return this.idx < 0 || this.idx >= this.rows.length || this.rows[this.idx][index] === null;
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

  close(): void {
  }
}

class FakeHistoryStore implements relationalStore.RdbStore {
  version: number = 8;
  existingGids: Set<number> = new Set<number>();
  inserts: number = 0;
  updates: number = 0;

  async insert(_table: string, values: relationalStore.ValuesBucket): Promise<number> {
    this.inserts++;
    const gid: number = Number(values['GID']);
    this.existingGids.add(gid);
    return gid;
  }

  async update(_values: relationalStore.ValuesBucket,
    _predicates: relationalStore.RdbPredicates): Promise<number> {
    this.updates++;
    return 1;
  }

  async delete(_predicates: relationalStore.RdbPredicates): Promise<number> {
    return 1;
  }

  async querySql(sql: string, args?: Array<relationalStore.ValueType>): Promise<relationalStore.ResultSet> {
    if (sql.indexOf('WHERE "GID" = ?') >= 0 && args !== undefined && args.length > 0) {
      const gid: number = Number(args[0]);
      if (this.existingGids.has(gid)) {
        return new FakeHistoryResultSet(
          ['GID', 'TOKEN', 'TITLE', 'TITLE_JPN', 'THUMB', 'CATEGORY', 'POSTED', 'UPLOADER',
            'RATING', 'SIMPLE_LANGUAGE', 'MODE', 'TIME'],
          [[gid, 'tok', 't', '', '', 1, '', '', 4.0, null, 0, 100]]
        );
      }
    }
    return new FakeHistoryResultSet([], []);
  }

  async executeSql(_sql: string, _args?: Array<relationalStore.ValueType>): Promise<void> {
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

async function runAsyncHistoryDaoTests(): Promise<void> {
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

  const store: FakeHistoryStore = new FakeHistoryStore();
  const dao: HistoryDao = new HistoryDao(store);

  const qb1 = dao.queryBuilder().where(HistoryDao.Properties.Gid.eq(77)).limit(10);
  const qb2 = dao.queryBuilder();
  ok('HistoryDao.queryBuilder() 返回独立实例', qb1 !== qb2);
  eq('HistoryDao 新建 builder 无残留条件', qb2.sql(), 'SELECT * FROM "HISTORY"');
  eq('HistoryDao limit(0) 输出 LIMIT 0', dao.queryBuilder().limit(0).sql(), 'SELECT * FROM "HISTORY" LIMIT 0');

  const h: HistoryInfo = HistoryInfo.fromGalleryInfo(makeFullGalleryInfo());
  h.setTime(500);
  await dao.save(h);
  eq('HistoryDao.save 首次走 insert', store.inserts, 1);
  await dao.save(h);
  eq('HistoryDao.save 已存在时走 update', store.updates, 1);
}

// ================================================================ 汇总

runAsyncHistoryDaoTests().then((): void => {
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
