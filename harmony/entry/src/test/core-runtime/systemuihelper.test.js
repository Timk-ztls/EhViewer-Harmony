// SystemUiHelper 家族：四档 flag 位运算（纯逻辑部分）
global.Observed = (target) => target;
const path = require('path');
const OUT = process.argv[2] || path.join(process.env.TEMP, 'tscheck', 'out9');
const u = path.join(OUT, 'util');

const { SystemUiHelper } = require(path.join(u, 'SystemUiHelper.js'));
const { SystemUiHelperImplHC } = require(path.join(u, 'SystemUiHelperImplHC.js'));
const { SystemUiHelperImplICS } = require(path.join(u, 'SystemUiHelperImplICS.js'));
const { SystemUiHelperImplJB } = require(path.join(u, 'SystemUiHelperImplJB.js'));
const { SystemUiHelperImplKK } = require(path.join(u, 'SystemUiHelperImplKK.js'));

let fail = 0;
const eq = (a, b, label) => {
  const A = JSON.stringify(a), B = JSON.stringify(b);
  if (A === B) console.log('  PASS  ' + label);
  else { fail++; console.log('  FAIL  ' + label + '\n    实际: ' + A + '\n    期望: ' + B); }
};
const S = SystemUiHelper;

// ── 常量 ──
eq([S.LEVEL_LOW_PROFILE, S.LEVEL_HIDE_STATUS_BAR, S.LEVEL_LEAN_BACK, S.LEVEL_IMMERSIVE], [0, 1, 2, 3], '四个 LEVEL = 0/1/2/3');
eq([S.FLAG_LAYOUT_IN_SCREEN_OLDER_DEVICES, S.FLAG_IMMERSIVE_STICKY], [1, 2], '两个 FLAG = 0x1/0x2');
eq([S.SYSTEM_UI_FLAG_LOW_PROFILE, S.SYSTEM_UI_FLAG_HIDE_NAVIGATION, S.SYSTEM_UI_FLAG_FULLSCREEN], [1, 2, 4],
  'SYSTEM_UI_FLAG_LOW_PROFILE=1 / HIDE_NAVIGATION=2 / FULLSCREEN=4（Android 常量）');
eq([S.SYSTEM_UI_FLAG_LAYOUT_STABLE, S.SYSTEM_UI_FLAG_LAYOUT_HIDE_NAVIGATION, S.SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN],
  [0x100, 0x200, 0x400], 'LAYOUT_* = 0x100/0x200/0x400');
eq([S.SYSTEM_UI_FLAG_IMMERSIVE, S.SYSTEM_UI_FLAG_IMMERSIVE_STICKY], [0x800, 0x1000], 'IMMERSIVE=0x800 / STICKY=0x1000');

// ── HC 档 ──
const hc = new SystemUiHelperImplHC(S.LEVEL_HIDE_STATUS_BAR, 0);
eq(hc.createShowFlags(), 0, 'HC show = STATUS_BAR_VISIBLE(0)');
eq(hc.createHideFlags(), 1, 'HC hide = STATUS_BAR_HIDDEN(1)');
eq(hc.isHiddenByVisibility(1), true, 'HC：(visibility & 1) != 0 → 隐藏');
eq(hc.isHiddenByVisibility(0), false, 'HC：visibility=0 → 显示');

// ── ICS 档：level 决定 LOW_PROFILE vs HIDE_NAVIGATION ──
const icsLow = new SystemUiHelperImplICS(S.LEVEL_LOW_PROFILE, 0);
const icsLean = new SystemUiHelperImplICS(S.LEVEL_LEAN_BACK, 0);
eq(icsLow.createShowFlags(), 0, 'ICS show = VISIBLE(0)');
eq(icsLow.createTestFlags(), 1, 'ICS test@LOW_PROFILE = LOW_PROFILE(1)');
eq(icsLean.createTestFlags(), 2, 'ICS test@LEAN_BACK = HIDE_NAVIGATION(2)');
eq(icsLow.createHideFlags(), 1, 'ICS hide@LOW_PROFILE = 1（只 LOW_PROFILE）');
eq(icsLean.createHideFlags(), 3, 'ICS hide@LEAN_BACK = LOW_PROFILE|HIDE_NAVIGATION = 3');

// ── JB 档：按 level 叠加 layout 标志 ──
const jbLow = new SystemUiHelperImplJB(S.LEVEL_LOW_PROFILE, 0);
const jbHide = new SystemUiHelperImplJB(S.LEVEL_HIDE_STATUS_BAR, 0);
const jbLean = new SystemUiHelperImplJB(S.LEVEL_LEAN_BACK, 0);
eq(jbLow.createShowFlags(), 0, 'JB show@LOW_PROFILE = 0（不叠 layout）');
eq(jbHide.createShowFlags(), 0x100 | 0x400, 'JB show@HIDE_STATUS_BAR = LAYOUT_STABLE|LAYOUT_FULLSCREEN = 0x500');
eq(jbLean.createShowFlags(), 0x100 | 0x400 | 0x200, 'JB show@LEAN_BACK 再叠 LAYOUT_HIDE_NAVIGATION = 0x700');
eq(jbHide.createHideFlags(), 1 | 0x100 | 0x400 | 0x4, 'JB hide@HIDE_STATUS_BAR = LOW_PROFILE|STABLE|LAYOUT_FULL|FULLSCREEN = 0x505');
eq(jbLow.shouldToggleActionBar(), true, 'JB@LOW_PROFILE 才手动 toggle ActionBar');
eq(jbHide.shouldToggleActionBar(), false, 'JB@HIDE_STATUS_BAR 不手动 toggle ActionBar');

// ── KK 档：IMMERSIVE 才加 IMMERSIVE/STICKY 位 ──
const kkImm = new SystemUiHelperImplKK(S.LEVEL_IMMERSIVE, 0);
const kkImmSticky = new SystemUiHelperImplKK(S.LEVEL_IMMERSIVE, S.FLAG_IMMERSIVE_STICKY);
const kkLow = new SystemUiHelperImplKK(S.LEVEL_LOW_PROFILE, 0);
eq((kkImm.createHideFlags() & 0x800) !== 0, true, 'KK hide@IMMERSIVE 含 IMMERSIVE(0x800)');
eq((kkImm.createHideFlags() & 0x1000), 0, '…且不含 STICKY（未设 FLAG_IMMERSIVE_STICKY）');
eq((kkImmSticky.createHideFlags() & 0x1000) !== 0, true, 'KK hide@IMMERSIVE+STICKY 含 STICKY(0x1000)');
eq((kkImmSticky.createHideFlags() & 0x800), 0, '…且不含非 sticky IMMERSIVE（二者互斥）');
eq((kkLow.createHideFlags() & 0x1800), 0, 'KK hide@LOW_PROFILE 不含任何 IMMERSIVE 位（只有 IMMERSIVE 级别才加）');

// ── 对照断言（陷阱 68）：ICS vs JB 的 hide 在同一 level 下必须不同 ──
eq(icsLean.createHideFlags() !== jbLean.createHideFlags(), true,
  '对照：ICS hide(0x3) ≠ JB hide(' + jbLean.createHideFlags().toString(16) + ')（子类确实有增量）');

// ── toggle：上游不清理延时任务，只翻转 ──
eq(S.toggle(true), false, 'toggle(isShowing=true) → false');
eq(S.toggle(false), true, 'toggle(isShowing=false) → true');

console.log('\n' + (fail === 0 ? 'ALL PASS' : fail + ' FAILED'));
process.exit(fail === 0 ? 0 : 1);
