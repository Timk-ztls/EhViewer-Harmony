// Settings 的 4 个 GuideDownload* 访问器（S0226 DownloadGuideHelper 消费）
global.Observed = (target) => target;
const path = require('path');
const OUT = process.argv[2] || path.join(process.env.TEMP, 'tscheck', 'out11');
const { Settings } = require(path.join(OUT, 'ehviewer', 'Settings.js'));

let fail = 0;
const eq = (a, b, label) => {
  const A = JSON.stringify(a), B = JSON.stringify(b);
  if (A === B) console.log('  PASS  ' + label);
  else { fail++; console.log('  FAIL  ' + label + '\n    实际: ' + A + '\n    期望: ' + B); }
};

// ── key 字面量（审计按字面量 grep，必须与上游一致）──
eq(Settings.KEY_GUIDE_DOWNLOAD_THUMB, 'guide_download_thumb', "key = 'guide_download_thumb'（上游 L1316）");
eq(Settings.KEY_GUIDE_DOWNLOAD_LABELS, 'guide_download_labels', "key = 'guide_download_labels'（上游 L1327）");

// ── 默认值：**两个都是 true**（反直觉，最容易写反成 false）──
eq(Settings.DEFAULT_GUIDE_DOWNLOAD_THUMB, true, '**默认 thumb = true**（引导默认显示）');
eq(Settings.DEFAULT_GUIDE_DOWNLOAD_LABELS, true, '**默认 labels = true**');

// ── 未写入时读默认 ──
eq(Settings.getGuideDownloadThumb(), true, '未写入 → getGuideDownloadThumb() === true');
eq(Settings.getGuideDownloadLabels(), true, '未写入 → getGuideDownloadLabels() === true');

// ── 写读往返 ──
Settings.putGuideDownloadThumb(false);
eq(Settings.getGuideDownloadThumb(), false, 'putGuideDownloadThumb(false) → 读回 false（用户点过后不再显示）');
Settings.putGuideDownloadThumb(true);
eq(Settings.getGuideDownloadThumb(), true, '…改回 true → 读回 true');

// ── 三个 t 的拼写：**方法必须真的叫这个名** ──
eq(typeof Settings.puttGuideDownloadLabels, 'function',
  '**`puttGuideDownloadLabels`（三个 t）必须存在** —— 上游方法名就是它（上游出现 1 次，正确拼写 0 次）');
eq(typeof Settings.putGuideDownloadLabels, 'undefined',
  '**没有 `putGuideDownloadLabels`（两个 t）** —— 上游也没有；加别名可以，但不能替换');
Settings.puttGuideDownloadLabels(false);
eq(Settings.getGuideDownloadLabels(), false, 'puttGuideDownloadLabels(false) → 读回 false');
Settings.puttGuideDownloadLabels(true);
eq(Settings.getGuideDownloadLabels(), true, '…改回 true → 读回 true');

// ── 两个开关互相独立（不能被写成同一个 key）──
Settings.putGuideDownloadThumb(false);
Settings.puttGuideDownloadLabels(true);
eq([Settings.getGuideDownloadThumb(), Settings.getGuideDownloadLabels()], [false, true],
  '**两个开关独立**：thumb=false 不影响 labels 仍为 true（key 不同）');

console.log('\n' + (fail === 0 ? 'ALL PASS' : fail + ' FAILED'));
process.exit(fail === 0 ? 0 : 1);
