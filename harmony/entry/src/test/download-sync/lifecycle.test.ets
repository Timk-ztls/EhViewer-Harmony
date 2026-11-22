/*
 * download-sync 纯逻辑单测：服务收尾判定（`DownloadService.checkStopSelf`）
 * C-10：harmony/entry/src/test/<module>/
 *
 * 上游门槛：`mDownloadManager == null || isIdle`。两个条件都容易被"优化"掉：
 *   - 去掉 `== null` → manager 还没建好时（onStartCommand 早到）服务永不停，**常驻通知常亮**；
 *   - 只看 `!isIdle` → 队列空了但 currentTask 还在时停服务 → **下载被拦腰打断**。
 *
 * 还有一条用户可感知的语义：收尾只能撤"下载中"通知，**"下载完成"通知必须保留**
 * （上游 `stopForeground(STOP_FOREGROUND_REMOVE)` 只撤前台那条；完成通知是独立 id 的普通通知）。
 * 写错就是"下完了但用户没看见"。
 */

import {
  DownloadNotificationPlanner,
  DownloadService,
  ServiceLifecyclePlanner,
  ServiceStopPlan
} from '../../main/ets/hippo/ehviewer/download/DownloadService';

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

function main(): void {
  // ------------------------------------------------ 1) 门槛：两种条件都要停
  const noManager: ServiceStopPlan = ServiceLifecyclePlanner.plan(false, false);
  eq('manager 未建立 → 收尾（上游 `== null` 那一半）', noManager.shouldStop, true);

  const idle: ServiceStopPlan = ServiceLifecyclePlanner.plan(true, true);
  eq('manager 已建 + 空闲 → 收尾', idle.shouldStop, true);

  // ------------------------------------------------ 2) 不能停的两种情形
  const busy: ServiceStopPlan = ServiceLifecyclePlanner.plan(true, false);
  eq('**有任务在下载 → 绝不收尾**（否则下载被拦腰打断）', busy.shouldStop, false);
  eq('不收尾时不动通知', busy.cancelDownloadingNotification, false);
  eq('不收尾时不清 foreground 标志', busy.clearForegroundFlag, false);
  eq('不收尾时不成长时任务', busy.stopContinuousTask, false);

  // ------------------------------------------------ 3) 收尾时的三个副作用必须同时做
  eq('收尾 → 撤"下载中"通知', idle.cancelDownloadingNotification, true);
  eq('收尾 → 清 foreground 标志（下次要重新 startForeground）', idle.clearForegroundFlag, true);
  eq('收尾 → 停长时任务', idle.stopContinuousTask, true);

  // ------------------------------------------------ 4) 完成通知必须保留（用户可感知）
  eq('收尾时保留"下载完成"通知（撤了 = 下完了但用户没看见）',
    idle.keepDownloadedNotification, true);
  eq('不收尾时同样不撤完成通知', busy.keepDownloadedNotification, true);
  eq('manager 未建立时也不撤完成通知', noManager.keepDownloadedNotification, true);

  // ------------------------------------------------ 5) 通知 ID 与收尾范围的关系
  //
  // 两个通知是独立 id：1=下载中 / 2=已完成 / 3=509。
  // 收尾只撤 1（通过 NotificationDelay.cancel(notifyId=ID_DOWNLOADING)），2/3 不受影响。
  eq('下载中通知 id = 1', DownloadNotificationPlanner.ID_DOWNLOADING, 1);
  eq('完成通知 id = 2', DownloadNotificationPlanner.ID_DOWNLOADED, 2);
  eq('509 通知 id = 3', DownloadNotificationPlanner.ID_509, 3);

  // ------------------------------------------------ 6) 组合真值表（4 种输入全覆盖）
  const table: string[] = [];
  const cases: number[][] = [[0, 0], [0, 1], [1, 0], [1, 1]];
  for (let i = 0; i < cases.length; i++) {
    const hasManager: boolean = cases[i][0] === 1;
    const isIdle: boolean = cases[i][1] === 1;
    table.push(ServiceLifecyclePlanner.plan(hasManager, isIdle).shouldStop ? 'STOP' : 'KEEP');
  }
  // 注意 hasManager=false 的两行：**无论 isIdle 是什么都要收尾**（上游 `||` 的短路语义）。
  eq('真值表 [无manager,无manager+空闲,有manager+有任务,有manager+空闲]',
    table, ['STOP', 'STOP', 'KEEP', 'STOP']);

  // ------------------------------------------------ 7) download_action Want 参数过滤
  eq('handleWantParameters(null) → false（不误吞冷启动）',
    DownloadService.handleWantParameters(null), false);
  const emptyParams: Record<string, Object> = {};
  eq('handleWantParameters(无 download_action) → false',
    DownloadService.handleWantParameters(emptyParams), false);
  const clearParams: Record<string, Object> = { 'download_action': DownloadService.ACTION_CLEAR };
  eq('handleWantParameters(含 download_action) → true',
    DownloadService.handleWantParameters(clearParams), true);

  // ------------------------------------------------ 汇总
  if (fails.length > 0) {
    console.error(`\n✗ ${fails.length} 条失败 / ${pass + fails.length} 条断言`);
    for (const f of fails) {
      console.error('  - ' + f);
    }
    throw new Error('lifecycle test failed');
  }
  console.log(`✓ lifecycle: ${pass} 条断言全部通过`);
}

main();
