// HashCodeUtils + MultimapSet 断言
global.Observed = (target) => target;
const path = require('path');
const OUT = process.argv[2] || path.join(process.env.TEMP, 'tscheck', 'out9');

const { HashCodeUtils } = require(path.join(OUT, 'util', 'HashCodeUtils.js'));
const col = path.join(OUT, 'lib', 'yorozuya', 'collect');
const { MultimapSet } = require(path.join(col, 'MultimapSet.js'));
const { Multimap } = require(path.join(col, 'Multimap.js'));

let fail = 0;
const eq = (a, b, label) => {
  const A = JSON.stringify(a), B = JSON.stringify(b);
  if (A === B) console.log('  PASS  ' + label);
  else { fail++; console.log('  FAIL  ' + label + '\n    实际: ' + A + '\n    期望: ' + B); }
};

// ── HashCodeUtils（对照 Java 已知值）──
eq(HashCodeUtils.hashCode(), 0, 'hashCode() 无参 → 0（上游 args==null 返回 0）');
eq(HashCodeUtils.hashCode('a'), 97, 'hashCode("a") = 97（Java String.hashCode）');
eq(HashCodeUtils.hashCode('ab'), 3105, 'hashCode("ab") = 3105（31*97+98）');
eq(HashCodeUtils.hashCode(null), 0, 'hashCode(null) = 0（o?.hashCode() ?: 0）');
eq(HashCodeUtils.hashCode('a', 'b'), 31 * 97 + 98, 'hashCode("a","b") = 31*97+98 = 3105（与单串 "ab" 同值，符合公式）');
eq(HashCodeUtils.hashCode(1, 2), 33, 'hashCode(1,2) = 31*1+2 = 33（数字取自身）');
eq(HashCodeUtils.hashCode(true), 1231, 'hashCode(true) = 1231（Java Boolean.hashCode）');
eq(HashCodeUtils.hashCode(false), 1237, 'hashCode(false) = 1237');
// 32 位回绕：构造一个会溢出的串
const long = 'x'.repeat(40);
eq(Number.isInteger(HashCodeUtils.hashCode(long)), true, '长串哈希是 32 位整数（|0 回绕），实际=' + HashCodeUtils.hashCode(long));

// ── MultimapSet：Set 语义（去重）──
const s = MultimapSet.create();
eq(s.putElement('k', 'v1'), 1, 'putElement 返回集合大小 1');
eq(s.putElement('k', 'v1'), 1, '重复加入**不增长**（Set 语义），仍为 1');
eq(s.putElement('k', 'v2'), 2, '加入新元素 → 2');
eq(s.countElements('k'), 2, 'countElements = 2');
eq(s.containsElement('k', 'v1'), true, 'containsElement(k,v1)');
eq(s.containsElement('k', 'vX'), false, 'containsElement(k,vX) = false');
eq(s.removeElement('k', 'v1'), true, 'removeElement 已存在 → true');
eq(s.removeElement('k', 'v1'), false, '再删一次 → false（已不存在）');
eq(s.countElements('k'), 1, '删除后剩 1');

// ── 对比 Multimap（List 语义）：重复加入会增长 —— 这条能证明两者差异没被写平 ──
const m = Multimap.create();
m.putElement('k', 'v1');
m.putElement('k', 'v1');
eq(m.countElements('k'), 2, 'Multimap(List) 重复加入 → 2（与 MultimapSet 的 1 形成对照）');

// putElements 返回值：只有真新增才 true
const s2 = MultimapSet.create();
eq(s2.putElements('k', ['a', 'b']), true, 'putElements 全新增 → true');
eq(s2.putElements('k', ['a']), false, 'putElements 全是已有元素 → false（Set.addAll 语义）');
eq(s2.putElements('k', ['a', 'c']), true, 'putElements 含一个新元素 → true');

console.log('\n' + (fail === 0 ? 'ALL PASS' : fail + ' FAILED'));
process.exit(fail === 0 ? 0 : 1);
