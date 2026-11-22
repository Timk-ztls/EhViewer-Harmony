// Settings.aDelete 的三种语义（回归修复的运行时断言）
global.Observed = (target) => target;
const path = require('path');
const OUT = process.argv[2] || path.join(process.env.TEMP, 'tscheck', 'out9');
const { Settings } = require(path.join(OUT, 'Settings.js'));

let fail = 0;
const eq = (a, b, label) => {
  const A = JSON.stringify(a), B = JSON.stringify(b);
  if (A === B) console.log('  PASS  ' + label);
  else { fail++; console.log('  FAIL  ' + label + '\n    实际: ' + A + '\n    期望: ' + B); }
};
const throws = async (fn, label, expect) => {
  try { await fn(); fail++; console.log('  FAIL  ' + label + '（未抛错）'); }
  catch (e) {
    const ok = expect === undefined || String(e.message).indexOf(expect) >= 0;
    if (ok) console.log('  PASS  ' + label + ' → "' + e.message + '"');
    else { fail++; console.log('  FAIL  ' + label + ' → "' + e.message + '"'); }
  }
};

(async () => {
  // 语义 0：未 attach → 必须 throw（装配期问题，不是"删除失败"）
  await throws(() => Settings.deleteArchiverDownloadUrl(7),
    '未 attach 时 deleteArchiverDownloadUrl → 抛错（不再静默 false）',
    'Settings not attached');

  // attach 一个内存版 preferences（桩：hasSync/deleteSync/flush）
  const store = new Map([['7Url', 'http://x'], ['7Total', 42]]);
  const fakePref = {
    getSync: (k, d) => (store.has(k) ? store.get(k) : d),
    putSync: (k, v) => { store.set(k, v); },
    deleteSync: (k) => { store.delete(k); },
    hasSync: (k) => store.has(k),
    flush: async () => { flushCount++; },
    getAll: async () => ({}),
  };
  let flushCount = 0;
  Settings.sArchiverPref = fakePref;

  // 语义 1：键不存在 → false（正常"没删到"）
  eq(await Settings.deleteArchiverDownloadPaused(7), false, '键不存在 → 返回 false（正常语义1）');
  eq(flushCount, 0, '…且没有触发 flush（本来就没写盘）');

  // 语义 2：删除并落盘成功 → true，且 flush 被 await
  eq(await Settings.deleteArchiverDownloadUrl(7), true, '删除成功 → 返回 true（语义2）');
  eq(flushCount, 1, '…且 flush 被调用（commit 语义）');
  eq(store.has('7Url'), false, '…键真的被删掉');

  // 语义 3：flush 失败 → 抛错（不伪装成 false）
  const badPref = Object.assign({}, fakePref, {
    hasSync: () => true,
    deleteSync: () => {},
    flush: async () => { throw new Error('disk full'); },
  });
  Settings.sArchiverPref = badPref;
  await throws(() => Settings.deleteArchiverDownloadTotal(7),
    'flush 失败 → 抛错（语义3，不伪装成"没删到"）', 'disk full');

  console.log('\n' + (fail === 0 ? 'ALL PASS' : fail + ' FAILED'));
  process.exit(fail === 0 ? 0 : 1);
})();
