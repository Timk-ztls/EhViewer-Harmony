// EhDB 历史裁剪 + Settings.getVersionCode
global.Observed = (target) => target;
const path = require('path');
const OUT = process.argv[2] || path.join(process.env.TEMP, 'tscheck', 'out11');
const { EhDB } = require(path.join(OUT, 'ehviewer', 'EhDB.js'));
const { Settings } = require(path.join(OUT, 'ehviewer', 'Settings.js'));

let fail = 0;
const eq = (a, b, label) => {
  const A = JSON.stringify(a), B = JSON.stringify(b);
  if (A === B) console.log('  PASS  ' + label);
  else { fail++; console.log('  FAIL  ' + label + '\n    实际: ' + A + '\n    期望: ' + B); }
};

// ══ 两个 offset 的口径（上游两处不一致，必须分别钉住）══
eq(EhDB.historyTrimOffset(100), 100, '单条版：MAX=100 → offset 100');
eq(EhDB.historyTrimOffset(200), 200, '单条版：MAX=200 → offset 200');
eq(EhDB.historyTrimOffset(0), 100, '**单条版：MAX=0 → 兜底 100**（上游 L850-856，不是 0）');
eq(EhDB.historyTrimOffset(-5), 100, '单条版：MAX 负数 → 兜底 100');
eq(EhDB.historyTrimOffset(1), 1, '单条版：MAX=1 → offset 1（只留最新一条）');

eq(EhDB.historyListTrimOffset(100), 100, '列表版：MAX=100 → offset 100');
eq(EhDB.historyListTrimOffset(0), 0, '**列表版：MAX=0 → offset 0（没有兜底，上游缺陷）**');
eq(EhDB.historyListTrimOffset(-5), -5, '列表版：MAX 负数原样');

eq(EhDB.MAX_HISTORY_COUNT >= 1, true, 'MAX_HISTORY_COUNT 默认值 ≥ 1（当前=' + EhDB.MAX_HISTORY_COUNT + '）');

// ══ trimHistory：offset<=0 保守不删（B 类修复，避免把历史清空）══
const mkDao = (rows) => {
  const st = { rows: rows.slice(), deleted: [], queried: null };
  const dao = {
    st,
    queryBuilder: () => {
      const q = {
        _offset: 0, _limit: 0,
        orderDesc: () => q, orderAsc: () => q,
        limit: (n) => { q._limit = n; return q; },
        offset: (n) => { q._offset = n; return q; },
        list: async () => {
          st.queried = { offset: q._offset, limit: q._limit };
          // 按 time 降序，跳过前 offset 条
          const sorted = st.rows.slice().sort((a, b) => b.time - a.time);
          return sorted.slice(q._offset);
        },
      };
      return q;
    },
    deleteInTx: async (list) => {
      list.forEach((x) => st.deleted.push(x.gid));
      const ids = new Set(list.map((x) => x.gid));
      st.rows = st.rows.filter((x) => !ids.has(x.gid));
    },
  };
  return dao;
};

(async () => {
  // 5 条历史，MAX=3 → 删掉最旧 2 条
  {
    const dao = mkDao([
      { gid: 1, time: 100 }, { gid: 2, time: 200 }, { gid: 3, time: 300 },
      { gid: 4, time: 400 }, { gid: 5, time: 500 },
    ]);
    const n = await EhDB.trimHistory(dao, 3);
    eq(n, 2, '5 条 + offset=3 → 删 2 条');
    eq(dao.st.deleted.sort((a, b) => a - b), [1, 2], '…删掉的是**最旧的**两条（gid 1、2）');
    eq(dao.st.rows.map((r) => r.gid).sort((a, b) => a - b), [3, 4, 5], '…保留最新的三条');
    eq(dao.st.queried, { offset: 3, limit: -1 }, '**查询用 limit(-1) + offset(N)**（上游同款）');
  }
  // 行数少于 offset → 什么都不删
  {
    const dao = mkDao([{ gid: 1, time: 1 }, { gid: 2, time: 2 }]);
    eq(await EhDB.trimHistory(dao, 100), 0, '2 条 + offset=100 → 删 0 条');
    eq(dao.st.deleted.length, 0, '…没有删除动作');
  }
  // offset <= 0 → 保护性不删（否则 SQL 会从头取全部并删光）
  {
    const dao = mkDao([{ gid: 1, time: 1 }, { gid: 2, time: 2 }]);
    eq(await EhDB.trimHistory(dao, 0), 0, '**offset=0 → 不删（保护）**');
    eq(dao.st.rows.length, 2, '…两条都还在');
    eq(await EhDB.trimHistory(dao, -3), 0, 'offset 负数 → 不删');
    eq(dao.st.rows.length, 2, '…仍然完整');
  }
  // 恰好等于 offset → 不删
  {
    const dao = mkDao([{ gid: 1, time: 1 }, { gid: 2, time: 2 }, { gid: 3, time: 3 }]);
    eq(await EhDB.trimHistory(dao, 3), 0, '3 条 + offset=3 → 删 0 条（边界）');
  }
  // offset=1 → 只留最新
  {
    const dao = mkDao([{ gid: 1, time: 1 }, { gid: 2, time: 9 }]);
    eq(await EhDB.trimHistory(dao, 1), 1, 'offset=1 → 删 1 条');
    eq(dao.st.rows.map((r) => r.gid), [2], '…留下的必须是最新的（time 最大的）');
  }

  // ══ Settings.getVersionCode ══
  eq(Settings.KEY_VERSION_CODE, 'version_code', "key 字面量 = 'version_code'（上游一致）");
  eq(Settings.DEFAULT_VERSION_CODE, 0, '默认 0（= 从未记录）');
  eq(Settings.getVersionCode(), 0, '未写入 → 0');
  Settings.putVersionCode(20206);
  eq(Settings.getVersionCode(), 20206, 'putVersionCode(20206) → 读回 20206');
  Settings.putVersionCode(0);
  eq(Settings.getVersionCode(), 0, 'putVersionCode(0) → 读回 0（可与"从未记录"区分不了，上游同款）');

  console.log('\n' + (fail === 0 ? 'ALL PASS' : fail + ' FAILED'));
  process.exit(fail === 0 ? 0 : 1);
})();
