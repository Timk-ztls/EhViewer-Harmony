// Html.toHtml / escapeHtml 运行时断言（对应 D-036：只移植 Spanned→HTML 方向）
const path = require('path');
const OUT = process.argv[2] || path.join(process.env.TEMP, 'tscheck', 'out6');
const { Html, SpannedText, TextSpan, SpanType } = require(path.join(OUT, 'Html.js'));

const NL = String.fromCharCode(10);
let fail = 0;
const eq = (a, b, label) => {
  const A = JSON.stringify(a), B = JSON.stringify(b);
  if (A === B) console.log('  PASS  ' + label);
  else { fail++; console.log('  FAIL  ' + label + '\n    实际: ' + A + '\n    期望: ' + B); }
};

// ── escapeHtml（上游 withinStyle 的六条分支）──
eq(Html.escapeHtml('a<b>c'), 'a&lt;b&gt;c', 'escapeHtml: < > 转义');
eq(Html.escapeHtml('a&b'), 'a&amp;b', 'escapeHtml: & 转义');
eq(Html.escapeHtml('a"b'), 'a"b', 'escapeHtml: 双引号不转义（上游如此）');
eq(Html.escapeHtml('中文'), '&#20013;&#25991;', 'escapeHtml: 非 ASCII → 十进制实体');
eq(Html.escapeHtml('a  b'), 'a&nbsp; b', 'escapeHtml: 连续空格 → 第一个之后 &nbsp;');
eq(Html.escapeHtml('a' + NL + 'b'), 'a&#10;b', 'escapeHtml: 换行(0x0A<0x20) → &#10;');
eq(Html.escapeHtml('😀'), '&#128512;', 'escapeHtml: 代理对 → 单码点实体');

// ── toHtml：无 span 的纯文本 ──
eq(Html.toHtml(new SpannedText('hello', [])), '<p dir="ltr">hello</p>' + NL, 'toHtml: 纯文本包一层 <p>');
eq(Html.toHtml(new SpannedText('a' + NL + 'b', [])),
  '<p dir="ltr">a<br>' + NL + 'b</p>' + NL, 'toHtml: 单个换行 → <br> + 断段');

// ── 字符样式 ──
eq(Html.toHtml(new SpannedText('x', [new TextSpan(0, 1, SpanType.BOLD, null)])),
  '<p dir="ltr"><b>x</b></p>' + NL, 'toHtml: BOLD → <b>x</b>');

eq(Html.toHtml(new SpannedText('x', [new TextSpan(0, 1, SpanType.URL, 'https://e/x')])),
  '<p dir="ltr"><a href="https://e/x">x</a></p>' + NL, 'toHtml: URL → <a href>');

// 上游 ForegroundColorSpan 存的是 ARGB（带 alpha）；int32 回绕后丢掉 alpha → 6 位
eq(Html.toHtml(new SpannedText('x', [new TextSpan(0, 1, SpanType.FOREGROUND, 0xFFFF0000)])),
  '<p dir="ltr"><font color ="#ff0000">x</font></p>' + NL, 'toHtml: FOREGROUND(ARGB) → 6 位十六进制');

// ── 嵌套顺序：闭合按 span 反向 → 严格嵌套 ──
const biOut = Html.toHtml(new SpannedText('x', [
  new TextSpan(0, 1, SpanType.BOLD, null),
  new TextSpan(0, 1, SpanType.ITALIC, null),
]));
eq(biOut, '<p dir="ltr"><b><i>x</i></b></p>' + NL, 'toHtml: BOLD+ITALIC → 严格嵌套 <b><i>x</i></b>');
eq(biOut.indexOf('</b></i>') >= 0, false, 'toHtml: 不是 </b></i>（跨 span 反向闭合，结论与预设相反）');

// ── Alignment → <div align="…">（上游 elements 初值是空格，故有两个空格，照搬）──
eq(Html.toHtml(new SpannedText('x', [new TextSpan(0, 1, SpanType.ALIGN_CENTER, null)])),
  '<div align="center"  ><p dir="ltr">x</p>' + NL + '</div>', 'toHtml: 居中 → <div align="center"  >（两个空格）');

// ── Quote → <blockquote> ──
eq(Html.toHtml(new SpannedText('x', [new TextSpan(0, 1, SpanType.QUOTE, null)])),
  '<blockquote><p dir="ltr">x</p>' + NL + '</blockquote>' + NL, 'toHtml: QUOTE → <blockquote>');

console.log('\n' + (fail === 0 ? 'ALL PASS' : fail + ' FAILED'));
process.exit(fail === 0 ? 0 : 1);
