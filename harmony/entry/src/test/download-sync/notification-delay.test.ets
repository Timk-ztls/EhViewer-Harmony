/*
 * download-sync 纯逻辑单测：通知节流（`DownloadService.NotificationDelay`）
 * C-10：harmony/entry/src/test/<module>/
 *
 * 这块的 bug 表现是"丢通知 / 重复发 / 常驻通知消失"，真机上极难稳定复现（依赖时序）。
 * 抽成 `NotificationDelayPlanner.decide()` 后，三条最容易被破坏的语义可以逐条钉住：
 *   1. 窗口内的后续操作**只保留最后一个**（覆盖，不是排队）
 *   2. `posted == true` 时新操作只覆盖 ops，**不刷新 lastTime**（窗口从第一次入队算）
 *   3. `startForeground(immediate)` 打断待执行操作；首次非 immediate 必须立刻生效
 */

import {
  NotificationDelayAction,
  NotificationDelayDecision,
  NotificationDelayPlanner
} from '../../main/ets/hippo/ehviewer/download/DownloadService';

const DELAY: number = 1000;

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

function decide(action: number, posted: boolean, started: boolean, lastTime: number, now: number):
  NotificationDelayDecision {
  return NotificationDelayPlanner.decide(action, posted, started, lastTime, now, DELAY);
}

const NOTIFY: number = 0;
const CANCEL: number = 1;
const START_FG: number = 2;

function main(): void {
  // ---------------------------------------------- 1) 窗口外：立刻执行
  const d1: NotificationDelayDecision =
    decide(NotificationDelayAction.SHOW, false, true, 0, 2000);
  eq('窗口外 show → 立刻 publish', d1.effect, NotificationDelayPlanner.EFFECT_PUBLISH_NOW);
  eq('窗口外 show → 不进入待执行', d1.posted, false);
  eq('窗口外 show → lastTime 更新为 now', d1.lastTime, 2000);

  const d2: NotificationDelayDecision =
    decide(NotificationDelayAction.CANCEL, false, true, 0, 2000);
  eq('窗口外 cancel → 立刻 cancelNow', d2.effect, NotificationDelayPlanner.EFFECT_CANCEL_NOW);

  // ---------------------------------------------- 2) 窗口内：延后，且记 ops
  const d3: NotificationDelayDecision =
    decide(NotificationDelayAction.SHOW, false, true, 2000, 2500);
  eq('窗口内 show → DEFER', d3.effect, NotificationDelayPlanner.EFFECT_DEFER);
  eq('窗口内 show → 记录 OPS_NOTIFY', d3.ops, NOTIFY);
  eq('窗口内 show → 进入待执行', d3.posted, true);
  eq('窗口内 show → lastTime 刷新为 now（上游行为）', d3.lastTime, 2500);

  // ---------------------------------------------- 3) 已有待执行操作：只覆盖 ops，不刷新 lastTime
  const d4: NotificationDelayDecision =
    decide(NotificationDelayAction.CANCEL, true, true, 2000, 2900);
  eq('已 posted 再 cancel → 仍 DEFER（覆盖）', d4.effect, NotificationDelayPlanner.EFFECT_DEFER);
  eq('已 posted 再 cancel → ops 改为 CANCEL（只保留最后一个）', d4.ops, CANCEL);
  eq('已 posted 再 cancel → **不刷新** lastTime', d4.lastTime, 2000);
  eq('已 posted 再 cancel → 仍 posted', d4.posted, true);

  const d5: NotificationDelayDecision =
    decide(NotificationDelayAction.SHOW, true, true, 2000, 2950);
  eq('已 posted 再 show → ops 回到 NOTIFY', d5.ops, NOTIFY);
  eq('已 posted 再 show → 不刷新 lastTime', d5.lastTime, 2000);

  // ---------------------------------------------- 4) startForeground(immediate)
  const d6: NotificationDelayDecision =
    decide(NotificationDelayAction.START_FOREGROUND_IMMEDIATE, true, false, 2000, 2500);
  eq('immediate → 立刻 START_FOREGROUND（打断待执行）',
    d6.effect, NotificationDelayPlanner.EFFECT_START_FOREGROUND);
  eq('immediate → 清空 posted', d6.posted, false);
  eq('immediate → 已进入长时任务', d6.startedForeground, true);

  // ---------------------------------------------- 5) 非 immediate 的 startForeground
  const d7: NotificationDelayDecision =
    decide(NotificationDelayAction.START_FOREGROUND, false, false, 0, 100);
  eq('首次非 immediate → 立刻生效（否则长任务起不来）',
    d7.effect, NotificationDelayPlanner.EFFECT_START_FOREGROUND);
  eq('首次非 immediate → 标记已进入', d7.startedForeground, true);

  const d8: NotificationDelayDecision =
    decide(NotificationDelayAction.START_FOREGROUND, false, true, 2000, 2500);
  eq('已进入过 + 窗口内 → DEFER', d8.effect, NotificationDelayPlanner.EFFECT_DEFER);
  eq('已进入过 + 窗口内 → 记录 OPS_START_FOREGROUND', d8.ops, START_FG);

  const d9: NotificationDelayDecision =
    decide(NotificationDelayAction.START_FOREGROUND, false, true, 2000, 4000);
  eq('已进入过 + 窗口外 → 立刻生效', d9.effect, NotificationDelayPlanner.EFFECT_START_FOREGROUND);

  // ---------------------------------------------- 6) 边界：恰好等于窗口
  //
  // 上游判定是 `now - lastTime > delay`（严格大于），等于窗口时仍然延后。
  const d10: NotificationDelayDecision =
    decide(NotificationDelayAction.SHOW, false, true, 2000, 3000);
  eq('恰好等于窗口（1000ms）→ 仍延后（上游是 > 不是 >=）',
    d10.effect, NotificationDelayPlanner.EFFECT_DEFER);
  const d11: NotificationDelayDecision =
    decide(NotificationDelayAction.SHOW, false, true, 2000, 3001);
  eq('超过窗口 1ms → 立刻执行', d11.effect, NotificationDelayPlanner.EFFECT_PUBLISH_NOW);

  // ---------------------------------------------- 汇总
  if (fails.length > 0) {
    console.error(`\n✗ ${fails.length} 条失败 / ${pass + fails.length} 条断言`);
    for (const f of fails) {
      console.error('  - ' + f);
    }
    throw new Error('notification-delay test failed');
  }
  console.log(`✓ notification-delay: ${pass} 条断言全部通过`);
}

main();
