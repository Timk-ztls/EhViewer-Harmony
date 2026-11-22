// MathUtils.toSigned32 / toUnsigned32 断言
global.Observed = (target) => target;
const path = require('path');
const OUT = process.argv[2] || path.join(process.env.TEMP, 'tscheck', 'out11');
const { MathUtils } = require(path.join(OUT, 'lib', 'yorozuya', 'MathUtils.js'));

let fail = 0;
const eq = (a, b, label) => {
  const A = JSON.stringify(a), B = JSON.stringify(b);
  if (A === B) console.log('  PASS  ' + label);
  else { fail++; console.log('  FAIL  ' + label + '\n    实际: ' + A + '\n    期望: ' + B); }
};

// ── Lead 指定的四条 ──
eq(MathUtils.toSigned32(0xFF00FF00), -16711936, 'toSigned32(0xFF00FF00) = -16711936（Java int 语义）');
eq(MathUtils.toUnsigned32(0xFF00FF00), 4278255360, 'toUnsigned32(0xFF00FF00) = 4278255360（JS 值域）');
eq(MathUtils.toSigned32(-1), -1, 'toSigned32(-1) = -1');
eq(MathUtils.toUnsigned32(-1), 4294967295, 'toUnsigned32(-1) = 4294967295');

// ── 边界与幂等 ──
eq(MathUtils.toSigned32(0x7FFFFFFF), 2147483647, 'toSigned32(0x7FFFFFFF) = 2147483647（int 上界）');
eq(MathUtils.toSigned32(0x80000000), -2147483648, 'toSigned32(0x80000000) = -2147483648（int 下界）');
eq(MathUtils.toUnsigned32(0), 0, 'toUnsigned32(0) = 0');
eq(MathUtils.toUnsigned32(0xFFFFFFFF), 4294967295, 'toUnsigned32(0xFFFFFFFF) = 4294967295');

// 幂等：连转两次结果不变
eq(MathUtils.toSigned32(MathUtils.toSigned32(0xFF00FF00)), -16711936, 'toSigned32 幂等');
eq(MathUtils.toUnsigned32(MathUtils.toUnsigned32(-1)), 4294967295, 'toUnsigned32 幂等');

// 互逆：signed → unsigned 得回原无符号值
eq(MathUtils.toUnsigned32(MathUtils.toSigned32(0xFF00FF00)), 4278255360,
  'toUnsigned32(toSigned32(0xFF00FF00)) 回到 4278255360（互为逆）');

// 小数截断（ToInt32 语义，不是四舍五入）
eq(MathUtils.toSigned32(3.9), 3, 'toSigned32(3.9) = 3（截断，不四舍五入）');
eq(MathUtils.toSigned32(-3.9), -3, 'toSigned32(-3.9) = -3（向零截断）');

// 超出 32 位的数按模 2^32 取（ToInt32 的规范行为）
eq(MathUtils.toSigned32(0x1FF00FF00), MathUtils.toSigned32(0xFF00FF00),
  'toSigned32 对超 32 位输入按模 2^32 取（0x1FF00FF00 与 0xFF00FF00 同值）');

// NaN/Infinity → 0（ToInt32 规范）
eq(MathUtils.toSigned32(NaN), 0, 'toSigned32(NaN) = 0（ToInt32 规范）');
eq(MathUtils.toSigned32(Infinity), 0, 'toSigned32(Infinity) = 0');

console.log('\n' + (fail === 0 ? 'ALL PASS' : fail + ' FAILED'));
process.exit(fail === 0 ? 0 : 1);
