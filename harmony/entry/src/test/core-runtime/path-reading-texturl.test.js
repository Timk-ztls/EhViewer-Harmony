// PathNaturalComparator / ReadingRefreshRate / TextUrl→Html 闭环
global.Observed = (target) => target;
const path = require('path');
const OUT = process.argv[2] || path.join(process.env.TEMP, 'tscheck', 'out9');
const util = path.join(OUT, 'util');

const { PathNaturalComparator } = require(path.join(util, 'PathNaturalComparator.js'));
const { ReadingRefreshRate } = require(path.join(OUT, 'ehviewer', 'util', 'ReadingRefreshRate.js'));
const { TextUrl } = require(path.join(util, 'TextUrl.js'));
const { Html } = require(path.join(OUT, 'text', 'Html.js'));

let fail = 0;
const eq = (a, b, label) => {
  const A = JSON.stringify(a), B = JSON.stringify(b);
  if (A === B) console.log('  PASS  ' + label);
  else { fail++; console.log('  FAIL  ' + label + '\n    实际: ' + A + '\n    期望: ' + B); }
};

const cmp = (a, b) => PathNaturalComparator.INSTANCE.compare(a, b);
const lt = (a, b) => cmp(a, b) < 0;

// ── PathNaturalComparator ──
eq(cmp(null, null), 0, 'null vs null → 0');
eq(cmp(null, 'a'), -1, 'null 排前 → -1');
eq(cmp('a', null), 1, 'null 排后 → 1');
eq(lt('file2/', 'file10/'), true, 'file2/ < file10/（数字按数值比，不是字典序）');
eq(lt('file10/', 'file2/'), false, 'file10/ 不 < file2/（反向为假）');
eq(cmp('same/', 'same/'), 0, '相同路径 → 0');
eq(lt('a/b/', 'a/c/'), true, '分隔符分段后逐段比较：a/b/ < a/c/');
eq(lt('dir2/x', 'dir10/x'), true, '中间段也按数值比：dir2/x < dir10/x');
// 对照：纯字典序会给出相反结果 —— 这条证明"不是普通字符串比较"
eq('file10/' < 'file2/', true, '对照：字典序 file10/ < file2/（与自然序相反）');

// ── ReadingRefreshRate.sanitize ──
eq([ReadingRefreshRate.SYSTEM_DEFAULT, ReadingRefreshRate.DISPLAY_MAX], [0, -1], '常量 SYSTEM_DEFAULT=0 / DISPLAY_MAX=-1');
eq([60, 90, 120, 0, -1].map((v) => ReadingRefreshRate.sanitize(v)), [60, 90, 120, 0, -1],
  'sanitize: 60/90/120/0/-1 全部保留');
eq(ReadingRefreshRate.sanitize(75), 0, 'sanitize(75) → 0（不在白名单 → 回落 SYSTEM_DEFAULT）');
eq(ReadingRefreshRate.sanitize(-2), 0, 'sanitize(-2) → 0');
eq(ReadingRefreshRate.sanitize(144), 0, 'sanitize(144) → 0（144Hz 不在白名单）');

// ── findBestMode / resolveHz ──
const cur = { physicalWidth: 100, physicalHeight: 200, refreshRate: 60 };
const modes = [
  { physicalWidth: 100, physicalHeight: 200, refreshRate: 60 },
  { physicalWidth: 100, physicalHeight: 200, refreshRate: 90 },
  { physicalWidth: 100, physicalHeight: 200, refreshRate: 120 },
  { physicalWidth: 50, physicalHeight: 100, refreshRate: 120 },
];
eq(ReadingRefreshRate.findBestMode(modes, cur, 0), null, 'settingHz=SYSTEM_DEFAULT → null（不干预）');
eq(ReadingRefreshRate.findBestMode(null, cur, 90), null, '无 modes → null');
eq(ReadingRefreshRate.findBestMode(modes, cur, 90).refreshRate, 90, '要 90Hz → 选到同分辨率的 90');
eq(ReadingRefreshRate.findBestMode(modes, cur, 75).refreshRate, 60, '要 75Hz（无此档）→ 取 <=75 且同分辨率最高的 60');
eq(ReadingRefreshRate.findBestMode(modes, cur, -1).refreshRate, 120, 'DISPLAY_MAX → 同分辨率最高 120（不选异分辨率的）');
eq(ReadingRefreshRate.resolveHz(modes, cur, 0), 0, 'resolveHz(SYSTEM_DEFAULT) → 0（跟随系统）');
eq(ReadingRefreshRate.resolveHz(modes, cur, 90), 90, 'resolveHz(90) → 90');

// ── TextUrl → Html 闭环 ──
const s = TextUrl.handleTextUrl('看这个 https://e-hentai.org/g/123/abc/ 很好');
eq(s.spans.length, 1, 'TextUrl 找到 1 个 URL');
eq(s.text.substring(s.spans[0].start, s.spans[0].end), 'https://e-hentai.org/g/123/abc/',
  '…span 区间正好覆盖整条 URL');
const html = Html.toHtml(s);
eq(html.indexOf('<a href="https://e-hentai.org/g/123/abc/">https://e-hentai.org/g/123/abc/</a>') >= 0, true,
  '闭环：handleTextUrl → Html.toHtml 产出 <a href>（两个组件接口匹配）');

const none = TextUrl.handleTextUrl('没有链接的文本');
eq(none.spans.length, 0, '无 URL → 0 个 span（上游返回原 content）');

const two = TextUrl.handleTextUrl('a http://a.com b https://b.com/c');
eq(two.spans.length, 2, '两个 URL → 2 个 span');
eq(two.spans[0].start < two.spans[1].start, true, '…span 按出现顺序');

console.log('\n' + (fail === 0 ? 'ALL PASS' : fail + ' FAILED'));
process.exit(fail === 0 ? 0 : 1);
