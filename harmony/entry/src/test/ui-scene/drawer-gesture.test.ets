/*
 * ui-widget：S0289 EhDrawerLayout 的**手势层数学**单测（第 8 轮新增）
 *
 * 背景：上游 `EhDrawerLayout.java` 那 144 行里**一行抽屉代码都没有** ——
 * 边缘拖拽 / scrim / 吸附 / 返回键关闭全部来自 AndroidX 的 `DrawerLayout` 父类。
 * 所以「父类给的能力」必须由我们的等价物自己保住语义，常量照 AOSP。
 *
 * 断言重点（每条都对应一个"用户能看见"的后果）：
 *   ① `shouldStartDrag`：关闭态只有左边缘 20vp 内能起手（否则和列表横滑/翻页打架）；
 *      打开态任意位置起手（拖动即关）
 *   ② `clampOffset`：拖过头不外溢（负 / 超宽都被夹住）
 *   ③ `snapTarget`：越过半数 → 打开，否则回弹（AOSP 的 settle 判定）
 *   ④ `scrimAlpha`：与进度**线性**联动，最大 0x99/0xFF（AOSP COLOR_SCRIM）
 *   ⑤ `clampDrawerWidth`：抽屉宽 ≤ 父宽 − 64dp（AOSP MIN_DRAWER_MARGIN）
 *
 * 运行：pwsh -File harmony/entry/src/test/ui-scene/run.ps1 -Filter drawer-gesture
 */

import { DrawerGestureMath } from '../../main/ets/hippo/ehviewer/widget/DrawerGestureMath';

let pass = 0;
const fails: string[] = [];

function eq(name: string, got: Object | null, want: Object | null): void {
  const g: string = JSON.stringify(got);
  const w: string = JSON.stringify(want);
  if (g === w) {
    pass++;
  } else {
    fails.push(`${name}\n    got  ${g}\n    want ${w}`);
  }
}

function ok(name: string, cond: boolean): void {
  if (cond) {
    pass++;
  } else {
    fails.push(`${name}\n    want true, got false`);
  }
}

/** 浮点近似（scrim 是除法结果，不能直接比字符串） */
function near(name: string, got: number, want: number, eps: number): void {
  if (Math.abs(got - want) <= eps) {
    pass++;
  } else {
    fails.push(`${name}\n    got  ${got}\n    want ${want} (±${eps})`);
  }
}

function main(): void {
  const W: number = 280;

  // ------------------------------------------------ ① 起手判定（边缘 20vp）
  ok('关闭态：x=0 在边缘内 → 可起手', DrawerGestureMath.shouldStartDrag(0, false, W));
  ok('关闭态：x=20 恰在边界 → 可起手（AOSP 是 <=）', DrawerGestureMath.shouldStartDrag(20, false, W));
  ok('关闭态：x=21 越过边缘 → 不可起手', !DrawerGestureMath.shouldStartDrag(21, false, W));
  ok('关闭态：x=200 屏中间 → 不可起手（防与列表横滑打架）',
    !DrawerGestureMath.shouldStartDrag(200, false, W));
  ok('打开态：x=200 任意位置 → 可起手（拖动即关）',
    DrawerGestureMath.shouldStartDrag(200, true, W));
  ok('负坐标 → 不可起手', !DrawerGestureMath.shouldStartDrag(-1, false, W));

  // ------------------------------------------------ ② offset 夹紧
  eq('offset=-50 → 0（不回弹到负）', DrawerGestureMath.clampOffset(-50, W), 0);
  eq('offset=100 → 100', DrawerGestureMath.clampOffset(100, W), 100);
  eq('offset=999 → 280（不超宽）', DrawerGestureMath.clampOffset(999, W), 280);
  eq('width=0 时恒 0（未测量完成）', DrawerGestureMath.clampOffset(100, 0), 0);

  // ------------------------------------------------ ③ 吸附阈值（半数）
  eq('offset=0 → 关', DrawerGestureMath.snapTarget(0, W), 0);
  eq('offset=139（<半）→ 回弹关', DrawerGestureMath.snapTarget(139, W), 0);
  eq('offset=140（恰半）→ 打开', DrawerGestureMath.snapTarget(140, W), 280);
  eq('offset=280（全开）→ 保持在开', DrawerGestureMath.snapTarget(280, W), 280);

  // ------------------------------------------------ ④ scrim 线性 + AOSP 上限
  near('scrim(0) = 0', DrawerGestureMath.scrimAlpha(0, W), 0, 1e-9);
  near('scrim(全开) = 0x99/0xFF ≈ 0.6',
    DrawerGestureMath.scrimAlpha(W, W), 0x99 / 0xFF, 1e-9);
  near('scrim(半开) = 0.3（线性）',
    DrawerGestureMath.scrimAlpha(W / 2, W), (0x99 / 0xFF) / 2, 1e-9);
  near('scrim 不会超过 0.6（拖过头也不更黑）',
    DrawerGestureMath.scrimAlpha(999, W), 0x99 / 0xFF, 1e-9);

  // ------------------------------------------------ ⑤ 抽屉宽上限（父宽 − 64dp）
  eq('期望 280 / 父宽 400 → 280（未被截）', DrawerGestureMath.clampDrawerWidth(280, 400), 280);
  eq('期望 400 / 父宽 400 → 336（400−64）', DrawerGestureMath.clampDrawerWidth(400, 400), 336);
  eq('父宽未知（0）→ 用期望值', DrawerGestureMath.clampDrawerWidth(280, 0), 280);
  eq('父宽太小（50）→ 回退期望值（不产生负宽）',
    DrawerGestureMath.clampDrawerWidth(280, 50), 280);

  // ------------------------------------------------ 汇总
  if (fails.length > 0) {
    console.error(`\n✗ ${fails.length} 条失败 / ${pass + fails.length} 条断言`);
    for (const f of fails) {
      console.error('  - ' + f);
    }
    throw new Error('drawer-gesture test failed');
  }
  console.log(`✓ drawer-gesture: ${pass} 条断言全部通过`);
}

main();
