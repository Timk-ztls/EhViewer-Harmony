// IdentityCookie 解析与展示串断言
global.Observed = (target) => target;
const path = require('path');
const OUT = process.argv[2] || path.join(process.env.TEMP, 'tscheck', 'out9');
const { IdentityCookiePreference } = require(path.join(OUT, 'IdentityCookiePreference.js'));

let fail = 0;
const eq = (a, b, label) => {
  const A = JSON.stringify(a), B = JSON.stringify(b);
  if (A === B) console.log('  PASS  ' + label);
  else { fail++; console.log('  FAIL  ' + label + '\n    实际: ' + A + '\n    期望: ' + B); }
};

const K = IdentityCookiePreference;

// 1) 三个 key 常量（上游 EhCookieStore）
eq(K.KEY_IPD_MEMBER_ID, 'ipb_member_id', 'KEY_IPD_MEMBER_ID');
eq(K.KEY_IPD_PASS_HASH, 'ipb_pass_hash', 'KEY_IPD_PASS_HASH');
eq(K.KEY_IGNEOUS, 'igneous', 'KEY_IGNEOUS');

// 2) 空列表 → 无身份（上游 → "游客"文案分支）
const empty = K.build([]);
eq(empty.hasIdentity(), false, '无 cookie → hasIdentity() = false（走"游客"分支）');

// 3) 三个值都存在
const full = K.build([
  { name: 'ipb_member_id', value: '12345' },
  { name: 'ipb_pass_hash', value: 'abcdef' },
  { name: 'igneous', value: 'xyz' },
]);
eq(full.hasIdentity(), true, '三项齐全 → hasIdentity() = true');
eq(full.toHtml(), 'ipb_member_id: 12345<br>ipb_pass_hash: abcdef<br>igneous: xyz',
  'toHtml 与上游字符串拼接逐字一致（<br> 分隔）');

// 4) 缺项时上游输出字面 "null"（Java 字符串拼接语义）——照搬
const partial = K.build([{ name: 'ipb_member_id', value: '999' }]);
eq(partial.toHtml(), 'ipb_member_id: 999<br>ipb_pass_hash: null<br>igneous: null',
  '缺项输出字面 "null"（Java 拼接语义，逐字照搬）');
eq(partial.hasIdentity(), true, '只有 member_id 也算已登录身份');

// 5) 同名 cookie 后者覆盖前者（上游 for + switch 直接赋值）
const dup = K.build([
  { name: 'igneous', value: 'first' },
  { name: 'igneous', value: 'second' },
]);
eq(dup.igneous, 'second', '同名 cookie 后者覆盖前者（上游语义）');

// 6) 剪贴板文本：上游 `message.replace("<br>", "\n")` **只替换第一处**（String.replace 非全局）
eq(full.toPlainText(), 'ipb_member_id: 12345\nipb_pass_hash: abcdef<br>igneous: xyz',
  'toPlainText 只把**第一个** <br> 换成换行（上游 String.replace 非全局）');

// 7) 不相关 cookie 被忽略
const noise = K.build([{ name: 'other', value: 'x' }, { name: 'ipb_member_id', value: '1' }]);
eq(noise.hasIdentity(), true, '忽略无关 cookie，仍能抓到 ipb_member_id');

console.log('\n' + (fail === 0 ? 'ALL PASS' : fail + ' FAILED'));
process.exit(fail === 0 ? 0 : 1);
