// Settings 写路径：fire-and-forget 但**不静默**（对应上游 apply() + 系统日志）
global.Observed = (target) => target;
const path = require('path');
const OUT = process.argv[2] || path.join(process.env.TEMP, 'tscheck', 'out9');
const captured = [];
// 先拦截 hilog，验证 logFlushError 真的被调用且带 key
const hilogShim = require.resolve(path.join(process.env.TEMP, 'tscheck', 'node_modules', '@ohos.hilog'));
require(hilogShim);
const hilogMod = require(hilogShim);
hilogMod.error = (domain, tag, fmt, ...args) => { captured.push(args.join('|')); };
hilogMod.default.error = hilogMod.error;

const { Settings } = require(path.join(OUT, 'Settings.js'));

let fail = 0;
const eq = (a, b, label) => {
  const A = JSON.stringify(a), B = JSON.stringify(b);
  if (A === B) console.log('  PASS  ' + label);
  else { fail++; console.log('  FAIL  ' + label + '\n    实际: ' + A + '\n    期望: ' + B); }
};

(async () => {
  // 1) logFlushError 存在且会打一条带 key 的 error
  captured.length = 0;
  Settings.logFlushError('TEST_KEY', new Error('boom'));
  eq(captured.length, 1, 'logFlushError 打了一条 hilog.error');
  eq(captured[0].indexOf('TEST_KEY') >= 0, true, '…日志里带 key（可定位是哪一项没落盘）');
  eq(captured[0].indexOf('boom') >= 0, true, '…日志里带错误消息');

  // 2) 写路径：flush 失败时**不抛错**（fire-and-forget），但日志被记录
  const store = new Map();
  let flushShouldFail = false;
  Settings.sPref = {
    getSync: (k, d) => (store.has(k) ? store.get(k) : d),
    putSync: (k, v) => { store.set(k, v); },
    deleteSync: (k) => { store.delete(k); },
    hasSync: (k) => store.has(k),
    flush: async () => { if (flushShouldFail) throw new Error('disk full'); },
    getAll: async () => ({}),
  };
  captured.length = 0;
  flushShouldFail = true;
  let threw = false;
  try {
    Settings.putString('K1', 'V1');
    await new Promise((r) => setTimeout(r, 20));   // 让 catch 有机会执行
  } catch (e) { threw = true; }
  eq(threw, false, 'putString 在 flush 失败时**不抛错**（保持 apply() 语义）');
  eq(store.get('K1'), 'V1', '…内存/缓存已更新（调用方视角成功）');
  eq(captured.length >= 1, true, '…但日志记录了 flush 失败（不再静默）');
  eq(captured[0].indexOf('K1') >= 0, true, '…日志里带出错的 key');

  console.log('\n' + (fail === 0 ? 'ALL PASS' : fail + ' FAILED'));
  process.exit(fail === 0 ? 0 : 1);
})();
