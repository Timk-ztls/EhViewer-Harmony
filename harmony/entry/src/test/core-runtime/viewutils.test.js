// ViewUtils 纯逻辑断言（MeasureSpec / 命中判定 / id 生成）
global.Observed = (target) => target;
const path = require('path');
const OUT = process.argv[2] || path.join(process.env.TEMP, 'tscheck', 'out11');
const { ViewUtils, MeasureSpec } = require(path.join(OUT, 'lib', 'yorozuya', 'ViewUtils.js'));

let fail = 0;
const eq = (a, b, label) => {
  const A = JSON.stringify(a), B = JSON.stringify(b);
  if (A === B) console.log('  PASS  ' + label);
  else { fail++; console.log('  FAIL  ' + label + '\n    实际: ' + A + '\n    期望: ' + B); }
};

// ── MeasureSpec 位运算 ──
eq([MeasureSpec.UNSPECIFIED, MeasureSpec.EXACTLY, MeasureSpec.AT_MOST], [0, 1, 2],
  'MeasureSpec 三模式 = 0/1/2（Android 值）');
const spec = MeasureSpec.makeMeasureSpec(1080, MeasureSpec.EXACTLY);
eq(MeasureSpec.getMode(spec), MeasureSpec.EXACTLY, 'makeMeasureSpec → getMode 往返（EXACTLY）');
eq(MeasureSpec.getSize(spec), 1080, 'makeMeasureSpec → getSize 往返（1080）');
const spec2 = MeasureSpec.makeMeasureSpec(500, MeasureSpec.AT_MOST);
eq([MeasureSpec.getMode(spec2), MeasureSpec.getSize(spec2)], [MeasureSpec.AT_MOST, 500],
  'AT_MOST 500 往返');
eq(ViewUtils.MAX_SIZE, 0x3FFFFFFF, 'MAX_SIZE = 0x3FFFFFFF（去掉高 2 位 Mode）');
eq(MeasureSpec.getSize(MeasureSpec.makeMeasureSpec(ViewUtils.MAX_SIZE, MeasureSpec.AT_MOST)),
  ViewUtils.MAX_SIZE, 'MAX_SIZE 打包后仍能原样取出（不溢出到 Mode 位）');

// ── getSuitableSize 三分支 ──
eq(ViewUtils.getSuitableSize(300, MeasureSpec.makeMeasureSpec(0, MeasureSpec.UNSPECIFIED)), 300,
  'UNSPECIFIED → 用自身 size');
eq(ViewUtils.getSuitableSize(300, MeasureSpec.makeMeasureSpec(1080, MeasureSpec.EXACTLY)), 1080,
  'EXACTLY → **忽略自身 size**，用 specSize（300→1080）');
eq(ViewUtils.getSuitableSize(300, MeasureSpec.makeMeasureSpec(200, MeasureSpec.AT_MOST)), 200,
  'AT_MOST: size(300) > spec(200) → min = 200');
eq(ViewUtils.getSuitableSize(150, MeasureSpec.makeMeasureSpec(200, MeasureSpec.AT_MOST)), 150,
  'AT_MOST: size(150) < spec(200) → 150（取自身）');
eq(ViewUtils.getSuitableSize(0, MeasureSpec.makeMeasureSpec(200, MeasureSpec.AT_MOST)), 200,
  'AT_MOST: size==0 → **用满 specSize**（不是 0，这是上游特例）');

// ── isViewUnder：左闭右开 + slop 外扩 ──
const v = { left: 100, right: 200, top: 50, bottom: 150, translationX: 0, translationY: 0 };
eq(ViewUtils.isViewUnder(v, 150, 100, 0), true, '内部点 → 命中');
eq(ViewUtils.isViewUnder(v, 100, 50, 0), true, '左上角（闭区间）→ 命中');
eq(ViewUtils.isViewUnder(v, 200, 150, 0), false, '右下角（**开区间**）→ 不命中');
eq(ViewUtils.isViewUnder(v, 199, 149, 0), true, '右下角内一格 → 命中');
eq(ViewUtils.isViewUnder(v, 95, 100, 0), false, '左外 5px、slop=0 → 不命中');
eq(ViewUtils.isViewUnder(v, 95, 100, 10), true, '左外 5px、slop=10 → 命中（容差外扩）');
eq(ViewUtils.isViewUnder(null, 150, 100, 0), false, 'view=null → false（不崩）');

// translation 生效
const vt = { left: 100, right: 200, top: 50, bottom: 150, translationX: 50, translationY: 20 };
eq(ViewUtils.isViewUnder(vt, 245, 165, 0), true, 'translation(+50,+20) 后新位置命中');
eq(ViewUtils.isViewUnder(v, 110, 60, 0), true, '对照：未平移时 (110,60) 命中');
eq(ViewUtils.isViewUnder(vt, 110, 60, 0), false, '…平移后同一坐标不再命中（矩形整体移动）');

// ── getX2 / getY2 ──
eq(ViewUtils.getX2(vt), 250, 'getX2 = right(200) + translationX(50)');
eq(ViewUtils.getY2(vt), 170, 'getY2 = bottom(150) + translationY(20)');
eq(ViewUtils.getX2(v), 200, 'translation=0 时 getX2 = right');

// ── getIndexInParent ──
const a = {}, b = {}, c = {};
eq(ViewUtils.getIndexInParent(b, [a, b, c]), 1, 'getIndexInParent 命中中间 → 1');
eq(ViewUtils.getIndexInParent({}, [a, b, c]), -1, '不在列表 → -1');
eq(ViewUtils.getIndexInParent(a, []), -1, '空列表 → -1');

// ── generateViewId：递增 + 回绕到 1（不是 0）──
ViewUtils.resetNextGeneratedIdForTest(1);
eq([ViewUtils.generateViewId(), ViewUtils.generateViewId(), ViewUtils.generateViewId()], [1, 2, 3],
  'generateViewId 从 1 递增');
ViewUtils.resetNextGeneratedIdForTest(0x00FFFFFF);
eq(ViewUtils.generateViewId(), 0x00FFFFFF, '到达上限时先返回上限值');
eq(ViewUtils.generateViewId(), 1, '…然后**回绕到 1**（不是 0，也不是溢出）');
eq(ViewUtils.generateViewId(), 2, '…回绕后继续递增');

console.log('\n' + (fail === 0 ? 'ALL PASS' : fail + ' FAILED'));
process.exit(fail === 0 ? 0 : 1);
