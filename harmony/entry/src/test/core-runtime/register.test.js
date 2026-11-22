// Register 运行时行为断言（纯逻辑；Register 只依赖 SparseILArray + Multimap，无平台 API）
const path = require('path');
const OUT = process.argv[2] || path.join(process.env.TEMP, 'tscheck', 'out');
const { Register } = require(path.join(OUT, 'conaco', 'Register.js'));

class Task {
  constructor(key) { this.mKey = key; }
  getKey() { return this.mKey; }
}

let fail = 0;
const eq = (a, b, label) => {
  const A = JSON.stringify(a), B = JSON.stringify(b);
  if (A === B) console.log('  PASS  ' + label);
  else { fail++; console.log('  FAIL  ' + label + '\n    实际: ' + A + '\n    期望: ' + B); }
};

// 1) 首次注册同一 key 不报重复
const r = new Register();
eq(r.register(1, new Task('k1')), false, '首次注册 key=k1 → 不重复');
// 2) 第二个同 key 任务 → 检出重复
eq(r.register(2, new Task('k1')), true, '再注册 key=k1 → 检出重复');
// 3) 重复注册仍会 append（上游语义：去重由 Conaco 负责，Register 只报告）
eq(r.contain(2), true, '重复 key 的任务仍被登记（contain(2)）');
// 4) getByKey 取该 key 下**第一个**
eq(r.getByKey('k1').getKey(), 'k1', 'getByKey 返回首个任务');
eq(r.getByKey('nope'), null, 'getByKey 未知 key → null');
eq(r.getByKey(null), null, 'getByKey(null) → null');
// 5) unregister 同时清 keyMap；剩余同 key 任务仍可查到
const removed = r.unregister(1);
eq(removed !== null, true, 'unregister(1) 返回被移除任务');
eq(r.contain(1), false, 'unregister 后 contain(1) === false');
eq(r.getByKey('k1') !== null, true, 'unregister 后同 key 的另一个任务仍可查');
eq(r.unregister(99), null, 'unregister 不存在的 id → null');
// 6) 无 key 任务不参与重复检查（上游 "For no-key task, there no need to check"）
const r2 = new Register();
eq(r2.register(1, new Task(null)), false, '无 key 任务注册不报重复');
eq(r2.register(2, new Task(null)), false, '再一个无 key 任务也不报重复');
eq(r2.getByKey(null), null, 'getByKey(null) 永远 null（无 key 任务不可按 key 取）');
// 7) id 与 key 可复用
const r3 = new Register();
r3.register(1, new Task('a'));
r3.unregister(1);
eq(r3.register(1, new Task('a')), false, 'unregister 后同 id 同 key 再注册不报重复');

console.log('\n' + (fail === 0 ? 'ALL PASS' : fail + ' FAILED'));
process.exit(fail === 0 ? 0 : 1);
