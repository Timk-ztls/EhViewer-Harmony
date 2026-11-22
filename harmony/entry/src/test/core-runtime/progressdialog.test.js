// ProgressDialog：延迟状态机 + 文案格式化 + show 顺序
global.Observed = (target) => target;
const path = require('path');
const OUT = process.argv[2] || path.join(process.env.TEMP, 'tscheck', 'out11');
const { ProgressDialogState, ProgressDialogHelper, ProgressStyle } =
  require(path.join(OUT, 'app', 'ProgressDialog.js'));

let fail = 0;
const eq = (a, b, label) => {
  const A = JSON.stringify(a), B = JSON.stringify(b);
  if (A === B) console.log('  PASS  ' + label);
  else { fail++; console.log('  FAIL  ' + label + '\n    实际: ' + A + '\n    期望: ' + B); }
};

// ── 常量与默认值 ──
eq([ProgressStyle.STYLE_SPINNER, ProgressStyle.STYLE_HORIZONTAL, ProgressDialogHelper.STYLE_SPINNER,
    ProgressDialogHelper.STYLE_HORIZONTAL], [0, 1, 0, 1], '样式常量 SPINNER=0 / HORIZONTAL=1（枚举与静态双形态）');
const d0 = new ProgressDialogState();
eq(d0.progressNumberFormat, '%1d/%2d', "默认 number format = '%1d/%2d'（上游 initFormats）");
eq(d0.progressPercentFormatEnabled, true, '默认启用百分比格式');
eq(d0.progressStyle, ProgressStyle.STYLE_SPINNER, '默认样式 = SPINNER（圆形）');

// ── 状态机：视图未就绪 → 延迟；就绪后回放 ──
const d = new ProgressDialogState();
d.setMax(100);
d.setProgress(30);
d.setSecondaryProgress(10);
d.setIndeterminate(true);
eq([d.getMax(), d.getProgress(), d.getSecondaryProgress(), d.isIndeterminate()],
  [100, 30, 10, true], '视图未就绪：getter 读延迟缓存');
d.applyPending();
eq([d.getMax(), d.getProgress(), d.getSecondaryProgress(), d.isIndeterminate()],
  [100, 30, 10, true], 'applyPending 后值不变（回放成功）');
d.setMax(200);
eq(d.getMax(), 200, '视图就绪后 setMax 直接生效');
// setProgress 走的是 hasStarted，不是 viewReady → 必须 markStarted 才即时生效
d.setProgress(50);
eq(d.getProgress(), 30, '视图就绪但未 start → setProgress 仍被延迟（读 applied=30）');
d.markStarted();
d.setProgress(50);
eq(d.getProgress(), 50, 'start 之后 setProgress 才即时生效');

// ── setProgress 用 hasStarted（唯一用它的 setter）──
const d2 = new ProgressDialogState();
d2.markViewReady();          // 视图已建
d2.setProgress(70);          // 但还没 onStart
eq(d2.getProgress(), 0, '视图就绪但**未 start** → setProgress 被延迟（读缓存 0）');
d2.markStarted();
d2.setProgress(70);
eq(d2.getProgress(), 70, 'onStart 后 setProgress 直接生效');

// setter 看 hasStarted、getter 看 viewReady —— **两者不对称，这是上游原样**
const d3 = new ProgressDialogState();
d3.markStarted();
d3.setProgress(88);          // setter：hasStarted=true → 写 appliedProgress
eq(d3.getProgress(), 0, '未建视图：setProgress 写了 applied(88)，但 getter 读缓存 → 返回 0（**不对称**）');
d3.applyPending();           // 回放：progressVal=0 不大于 0 → **不覆盖** applied 的 88
eq(d3.getProgress(), 88, '…applyPending 不会覆盖它（回放条件是 progressVal>0，而缓存是 0）');
d3.markStopped();
d3.setProgress(99);          // setter：hasStarted=false → 写缓存
eq(d3.getProgress(), 88, 'onStop 后 setProgress 写入缓存，getter 仍读 applied=88');

// ── applyPending 的回放条件不对称 ──
const d4 = new ProgressDialogState();
d4.setMax(0);                 // 0 → 不回放
d4.setProgress(-5);           // 负数 → 不回放
d4.setIndeterminate(true);    // 无条件回放
d4.applyPending();
eq([d4.getMax(), d4.getProgress(), d4.isIndeterminate()], [0, 0, true],
  'applyPending：max=0 / progress<0 **不回放**，indeterminate 无条件回放（上游不对称）');
eq(d4.getMax(), 0, '…因此 max 保持默认 0');

// increment 在视图未就绪时累加到 mIncrementBy，回放时**叠加到 applied**
const d5 = new ProgressDialogState();
d5.setProgress(10);
d5.incrementProgressBy(5);
d5.incrementProgressBy(7);
d5.applyPending();
eq(d5.getProgress(), 22, '延迟的 increment 会累加（5+7）并在回放时叠加到 progress(10) = 22');

// ── formatProgressNumber ──
eq(ProgressDialogHelper.formatProgressNumber(3, 10, '%1d/%2d'), '3/10', "format %1d/%2d → '3/10'");
eq(ProgressDialogHelper.formatProgressNumber(3, 10, null), '', 'format=null → 空串（上游 else 分支）');
eq(ProgressDialogHelper.formatProgressNumber(3, 10, '%1d 项 / 共 %2d 项'), '3 项 / 共 10 项',
  '自定义 format 也能替换两个占位符');

// ── formatProgressPercent（NumberFormat 0 位小数）──
eq(ProgressDialogHelper.formatProgressPercent(1, 4, true), '25%', '1/4 → 25%');
eq(ProgressDialogHelper.formatProgressPercent(1, 3, true), '33%', '1/3 → 33%（0 位小数，四舍五入）');
eq(ProgressDialogHelper.formatProgressPercent(2, 3, true), '67%', '2/3 → 67%（四舍五入不是截断）');
eq(ProgressDialogHelper.formatProgressPercent(10, 10, true), '100%', '满进度 → 100%');
eq(ProgressDialogHelper.formatProgressPercent(0, 10, true), '0%', '0/10 → 0%');
// max=0 的三条路径（上游**无守卫**，直接 progress/max）—— 我第一版把这三条混成一条，已更正
eq(ProgressDialogHelper.formatProgressPercent(0, 0, true), 'NaN', 'max=0 且 progress=0 → 0.0/0.0 = NaN → "NaN"');
eq(ProgressDialogHelper.formatProgressPercent(5, 0, true), '\u221E', 'max=0 且 progress>0 → +Infinity → "∞"（**不是 NaN**）');
eq(ProgressDialogHelper.formatProgressPercent(-5, 0, true), '-\u221E', 'max=0 且 progress<0 → -Infinity → "-∞"');

// Java DecimalFormat 默认 HALF_EVEN（不是 Math.round 的 HALF_UP）
eq(ProgressDialogHelper.formatProgressPercent(1, 8, true), '12%', '1/8 = 12.5% → **HALF_EVEN → 12%**（Math.round 会给 13%）');
eq(ProgressDialogHelper.formatProgressPercent(3, 8, true), '38%', '3/8 = 37.5% → HALF_EVEN → 38%（37 是奇数，进到偶数 38）');
eq(ProgressDialogHelper.formatProgressPercent(5, 8, true), '62%', '5/8 = 62.5% → HALF_EVEN → 62%（63 奇数，退到偶数 62）');
eq(ProgressDialogHelper.formatProgressPercent(5, 10, false), '', 'format 禁用 → 空串');

// ── show 的调用顺序 ──
eq(ProgressDialogHelper.buildShowSequence(false, false, false),
  ['setTitle', 'setMessage', 'setIndeterminate(false)', 'setCancelable(false)', 'show'],
  'show 序列：无 cancelListener 时不含 setOnCancelListener');
eq(ProgressDialogHelper.buildShowSequence(true, true, true),
  ['setTitle', 'setMessage', 'setIndeterminate(true)', 'setCancelable(true)', 'setOnCancelListener', 'show'],
  'show 序列：有 cancelListener 时在 show 之前插入');
eq(ProgressDialogHelper.buildShowSequence(false, false, false).indexOf('show'),
  ProgressDialogHelper.buildShowSequence(false, false, false).length - 1, 'show 永远是最后一步');

console.log('\n' + (fail === 0 ? 'ALL PASS' : fail + ' FAILED'));
process.exit(fail === 0 ? 0 : 1);
