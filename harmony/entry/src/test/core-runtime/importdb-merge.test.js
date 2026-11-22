// R-08（importDB 逐表合并的去重判据）+ R-10（migrate 写回 version）
global.Observed = (target) => target;
const path = require('path');
const OUT = process.argv[2] || path.join(process.env.TEMP, 'tscheck', 'out11');
const { EhDB } = require(path.join(OUT, 'ehviewer', 'EhDB.js'));
const { QuickSearch } = require(path.join(OUT, 'ehviewer', 'dao', 'QuickSearch.js'));
const { Filter } = require(path.join(OUT, 'ehviewer', 'dao', 'Filter.js'));
const { BlackList } = require(path.join(OUT, 'ehviewer', 'dao', 'BlackList.js'));
const { GalleryTags } = require(path.join(OUT, 'ehviewer', 'dao', 'GalleryTags.js'));
const { LocalFavoriteInfo } = require(path.join(OUT, 'ehviewer', 'dao', 'LocalFavoriteInfo.js'));
const { GalleryInfo } = require(path.join(OUT, 'ehviewer', 'client', 'data', 'GalleryInfo.js'));

let fail = 0;
const eq = (a, b, label) => {
  const A = JSON.stringify(a), B = JSON.stringify(b);
  if (A === B) console.log('  PASS  ' + label);
  else { fail++; console.log('  FAIL  ' + label + '\n    实际: ' + A + '\n    期望: ' + B); }
};

// ══ R-08 判据三：QuickSearch 按 name 去重 ══
{
  const cur = [new QuickSearch(1, 'a'), new QuickSearch(2, 'b')];
  eq(EhDB.quickSearchNameDuplicated(cur, 'a'), true, '同名 "a" → 判重（跳过）');
  eq(EhDB.quickSearchNameDuplicated(cur, 'c'), false, '不同名 "c" → 导入');
  eq(EhDB.quickSearchNameDuplicated([], 'a'), false, '当前库为空 → 导入');
  // ObjectUtils.equal(null, null) 为 true → **名字都为 null 也算同名**
  eq(EhDB.quickSearchNameDuplicated([new QuickSearch(3, null)], null), true,
    '**当前库有一条 name=null 且来项也是 null → 判重**（ObjectUtils.equal 语义）');
  eq(EhDB.quickSearchNameDuplicated([new QuickSearch(3, null)], 'x'), false, 'null vs "x" → 不判重');
}

// ══ Filter：按 mode + text 去重，**不看 id** ══
{
  const cur = [new Filter(10, 0, 'tag:a')];
  eq(EhDB.filterAlreadyPresent(cur, new Filter(99, 0, 'tag:a')), true,
    '**id 不同但 mode+text 相同 → 判重**（上游 Filter.equals 只比这两项）');
  eq(EhDB.filterAlreadyPresent(cur, new Filter(10, 1, 'tag:a')), false, 'mode 不同 → 不判重');
  eq(EhDB.filterAlreadyPresent(cur, new Filter(10, 0, 'tag:b')), false, 'text 不同 → 不判重');
  eq(EhDB.filterAlreadyPresent([], new Filter(null, 0, 'x')), false, '当前库为空 → 导入');
}

// ══ BlackList / GalleryTags：**D-072 修复**（上游无 equals → contains 恒 false）══
{
  const existing = new BlackList(1, 'spam', 'r', 'aw', '2020-01-01', 0);
  const cur = [existing];
  eq(EhDB.blackListAlreadyPresent(cur, existing), true, '同一对象 → 判重');
  eq(EhDB.blackListAlreadyPresent(cur, new BlackList(1, 'spam', 'r', 'aw', '2020-01-01', 0)), true,
    '**内容/对象不同的同一 badgayname → 判重成功（D-072：不再重复插入）**');
  eq(EhDB.blackListAlreadyPresent(cur, new BlackList(9, 'spam', 'other-reason', null, '2024-09-09', 1)), true,
    '…**业务键只看 badgayname**（reason/add_time/mode 不同仍判重 —— 与上游 inBlackList 的查询条件一致）');
  eq(EhDB.blackListAlreadyPresent(cur, new BlackList(1, 'other', 'r', 'aw', '2020-01-01', 0)), false,
    '…badgayname 不同 → 不判重');
  eq(EhDB.blackListAlreadyPresent([], new BlackList(null, 'x')), false, '空库 → 不判重');
}

// ══ 写入入口语义（用假 session 观察）══════════════════════════════════════════
const mkSession = (overrides) => Object.assign({
  getLocalFavoritesDao: () => ({ load: async () => null, insert: async () => 1 }),
  getQuickSearchDao: () => ({ insert: async () => 7 }),
  getFilterDao: () => ({ insert: async () => 8 }),
  getBlackListDao: () => ({ insert: async () => 9 }),
}, overrides);

(async () => {
  // putLocalFavorite：已存在 → 整个跳过
  {
    const inserted = [];
    EhDB.attach(mkSession({
      getLocalFavoritesDao: () => ({
        load: async (gid) => ({ gid }),
        insert: async (e) => { inserted.push(e); return 1; },
      }),
    }));
    const g = new GalleryInfo();
    g.gid = 555;
    await EhDB.putLocalFavorite(g);
    eq(inserted.length, 0, 'putLocalFavorite：**已在库中 → 不插入、不覆盖 time**');
  }
  // putLocalFavorite：不存在 → fromGalleryInfo + time=now 后插入
  {
    const inserted = [];
    EhDB.attach(mkSession({
      getLocalFavoritesDao: () => ({
        load: async () => null,
        insert: async (e) => { inserted.push(e); return 1; },
      }),
    }));
    const g = new GalleryInfo();
    g.gid = 777;
    g.title = 'T';
    await EhDB.putLocalFavorite(g);
    eq(inserted.length, 1, 'putLocalFavorite：不在库 → 插入一条');
    eq(inserted[0] instanceof LocalFavoriteInfo, true, '…插入的是 LocalFavoriteInfo');
    eq(inserted[0].gid, 777, '…gid 透传');
    eq(typeof inserted[0].time === 'number' && inserted[0].time > 0, true,
      '…**time 被设为当前时间**（非 LocalFavoriteInfo 分支才刷 time）');
  }
  // putLocalFavorite：传入的本来就是 LocalFavoriteInfo → 保留它自己的 time
  {
    const inserted = [];
    EhDB.attach(mkSession({
      getLocalFavoritesDao: () => ({
        load: async () => null,
        insert: async (e) => { inserted.push(e); return 1; },
      }),
    }));
    const info = new LocalFavoriteInfo(888);
    info.time = 12345;
    await EhDB.putLocalFavorite(info);
    eq(inserted[0].time, 12345, '**传入 LocalFavoriteInfo 时保留原 time（不覆盖）**');
  }

  // insertQuickSearch：id 置 null；time=0 → 补当前时间
  {
    EhDB.attach(mkSession({}));
    const qs = new QuickSearch(42, 'n');
    qs.time = 0;
    await EhDB.insertQuickSearch(qs);
    eq(qs.id, 7, '**insertQuickSearch：id 先置 null 再由 insert 返回**（42 → 7）');
    eq(qs.time > 0, true, '…time=0 时补当前时间');
    const qs2 = new QuickSearch(42, 'n');
    qs2.time = 999;
    await EhDB.insertQuickSearch(qs2);
    eq(qs2.time, 999, '…time 已有值则**不动**');
  }

  // addFilter：id 置 null 后插入并回填
  {
    EhDB.attach(mkSession({}));
    const f = new Filter(123, 0, 'x');
    await EhDB.addFilter(f);
    eq(f.getId(), 8, 'addFilter：id 置 null 后由 insert 返回（123 → 8）');
  }

  // insertBlackList：badgayname=null → **静默丢弃**
  {
    const inserted = [];
    EhDB.attach(mkSession({
      getBlackListDao: () => ({ insert: async (e) => { inserted.push(e); return 1; } }),
    }));
    await EhDB.insertBlackList(new BlackList(1, null, 'r', null, null, 0));
    eq(inserted.length, 0, '**insertBlackList：badgayname=null → 静默丢弃**（上游同款）');
    const b = new BlackList(1, 'spam', 'r', null, null, 0);
    await EhDB.insertBlackList(b);
    eq(inserted.length, 1, '…有名字则插入');
    eq(b.id, null, '**插入后 id 不回填**（上游 `dao.insert(blackList)` 没接收返回值）');
  }

  // ══ R-10a：setStoreVersion 基本语义 ══
  {
    const calls = [];
    const fakeStore = { executeSql: async (sql) => { calls.push(sql); } };
    await EhDB.setStoreVersion(fakeStore, 8);
    eq(calls, ['PRAGMA user_version = 8'], 'setStoreVersion(8) → 执行 `PRAGMA user_version = 8`');
    for (const bad of [1.5, -1, NaN, Infinity]) {
      let threw = false;
      try { await EhDB.setStoreVersion(fakeStore, bad); } catch (e) { threw = true; }
      eq(threw, true, `setStoreVersion(${bad}) → 抛错（拒绝非法版本号）`);
    }
  }

  // ══ R-12：putHistoryInfoList **不裁剪**（上游批量版没有 trim）══
  {
    const rows = [];
    const dao = {
      load: async (gid) => rows.find((r) => r.gid === gid) || null,
      insert: async (e) => { rows.push(e); return e.gid; },
      queryBuilder: () => ({ orderDesc: () => ({ limit: () => ({ offset: () => ({ list: async () => [] }) }) }) }),
      deleteInTx: async () => {},
    };
    EhDB.attach(Object.assign(mkSession({}), { getHistoryDao: () => dao }));
    // 造 500 条，MAX_HISTORY_COUNT 默认 100：**导入后必须一条都不删**
    const list = [];
    for (let i = 1; i <= 500; i++) {
      const h = { gid: i, time: i };
      list.push(h);
    }
    await EhDB.putHistoryInfoList(list);
    eq(rows.length, 500, '**导入 500 条历史 → 全部保留（R-12：批量版不裁剪）**');
    eq(rows.length > 100, true, '…不受 MAX_HISTORY_COUNT(=100) 影响');
    // 已存在的 gid 不重复插入
    await EhDB.putHistoryInfoList([{ gid: 1, time: 999 }, { gid: 501, time: 501 }]);
    eq(rows.length, 501, '已存在的 gid 跳过、新的插入（500 → 501）');
  }

  // ══ R-10：**迁移失败 → 不写 version**（这才是 R-10 的价值所在）══
  {
    const calls = [];
    let rolledBack = false;
    let committed = false;
    const failingStore = {
      beginTransaction: () => calls.push('BEGIN'),
      executeSql: async (sql) => {
        calls.push(sql);
        // 让 6→7 的 ALTER 之外的某条语句失败：用 oldVersion=2 走到 2→3 的 CREATE TABLE 时抛
        if (sql.indexOf('CREATE TABLE "FILTER2"') >= 0) { throw new Error('disk I/O error'); }
      },
      commit: () => { committed = true; },
      rollBack: () => { rolledBack = true; },
    };
    let threw = false;
    try { await EhDB.migrate(failingStore, 2); } catch (e) { threw = true; }
    eq(threw, true, 'migrate 中途失败 → **向外抛错**（不吞）');
    eq(rolledBack, true, '…调用了 rollBack');
    eq(committed, false, '…**没有 commit**');
    eq(calls.some((s) => s.indexOf('PRAGMA user_version') >= 0), false,
      '**…且从未写 user_version（迁移失败 ⇒ 版本保持旧值）**');

    // 正向对照：正常迁移到 8 时，version 写在 commit **之前**
    const okCalls = [];
    let okCommitAt = -1;
    const okStore = {
      beginTransaction: () => okCalls.push('BEGIN'),
      executeSql: async (sql) => { okCalls.push(sql); },
      commit: () => { okCommitAt = okCalls.length; okCalls.push('COMMIT'); },
      rollBack: () => okCalls.push('ROLLBACK'),
    };
    await EhDB.migrate(okStore, 7);   // 只走 7→8
    const pragmaAt = okCalls.findIndex((s) => s.indexOf('PRAGMA user_version') >= 0);
    eq(pragmaAt >= 0, true, '正常迁移写入了 user_version');
    eq(pragmaAt < okCommitAt, true, '**…且写在 COMMIT 之前**（写失败可随事务回滚）');
    eq(okCalls[pragmaAt], 'PRAGMA user_version = 8', '…值是 SCHEMA_VERSION(8)');
  }

  console.log('\n' + (fail === 0 ? 'ALL PASS' : fail + ' FAILED'));
  process.exit(fail === 0 ? 0 : 1);
})();
