/*
 * download-sync 纯逻辑单测：归档下载通知（`ArchiverDownloadService.buildNotification`）
 * C-10：harmony/entry/src/test/<module>/
 *
 * 两块容易被"优化"掉、坏起来用户直接没法恢复的语义：
 *   1. 暂停时必须是 `ongoing=false` + `tapDismissed=true` + 按钮变「继续」
 *      —— 写成 ongoing=true，通知栏就消不掉；按钮不变「继续」，用户**没有任何办法**恢复下载；
 *   2. `total <= 0`（长度未知）时**不能挂进度模板**，否则进度条停在 0 看着像卡死。
 */

import {
  ArchiverNotificationPlan,
  ArchiverNotificationPlanner,
  ArchiverDownloadService
} from '../../main/ets/hippo/ehviewer/download/ArchiverDownloadService';

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

function main(): void {
  // ------------------------------------------------ 1) 百分比（整数除法 + 上限）
  eq('percent(0, 100) = 0', ArchiverNotificationPlanner.percent(0, 100), 0);
  eq('percent(50, 100) = 50', ArchiverNotificationPlanner.percent(50, 100), 50);
  eq('percent(1, 3) = 33（向下取整）', ArchiverNotificationPlanner.percent(1, 3), 33);
  eq('percent(2, 3) = 66（不四舍五入到 67）', ArchiverNotificationPlanner.percent(2, 3), 66);
  eq('percent(200, 100) = 100（上限截断）', ArchiverNotificationPlanner.percent(200, 100), 100);
  eq('percent(x, 0) = 0（total 未知不除零）', ArchiverNotificationPlanner.percent(50, 0), 0);
  eq('percent(x, -1) = 0', ArchiverNotificationPlanner.percent(50, -1), 0);

  // ------------------------------------------------ 2) 速度文案
  const withRemain: string = ArchiverNotificationPlanner.formatSpeedText(1024, 61000);
  ok('速度文案带 /S', withRemain.indexOf('/S') >= 0);
  ok('有剩余时间时带「剩余」', withRemain.indexOf('剩余') >= 0);
  const noRemain: string = ArchiverNotificationPlanner.formatSpeedText(1024, -1);
  ok('remaining < 0 不带「剩余」', noRemain.indexOf('剩余') < 0);
  ok('负速度归零（不出现负号）', ArchiverNotificationPlanner.formatSpeedText(-100, -1).indexOf('-') < 0);

  // ------------------------------------------------ 3) 下载中
  const running: ArchiverNotificationPlan =
    ArchiverNotificationPlanner.plan('作品 A', 1001, 512, 2048, 1024, 30000, false);
  eq('下载中：常驻（ongoing=true）', running.ongoing, true);
  eq('下载中：可点击暂停', running.action, ArchiverDownloadService.ACTION_PAUSE);
  eq('下载中：百分比 25%', running.percent, 25);
  eq('下载中：additionalText 为 25%', running.info, '25%');
  eq('下载中：挂进度模板', running.hasTemplate, true);
  eq('下载中：有按钮（gid >= 0）', running.hasButton, true);
  ok('下载中：正文是速度', running.text.indexOf('/S') >= 0);

  // ------------------------------------------------ 4) 暂停态（用户恢复的唯一入口）
  const paused: ArchiverNotificationPlan =
    ArchiverNotificationPlanner.plan('作品 A', 1001, 512, 2048, 0, -1, true);
  eq('暂停：非常驻（用户可划掉）', paused.ongoing, false);
  eq('暂停：动作变「继续」', paused.action, ArchiverDownloadService.ACTION_RESUME);
  eq('暂停：正文是暂停文案', paused.text, '已暂停');
  ok('暂停：正文不是速度', paused.text.indexOf('/S') < 0);

  // ------------------------------------------------ 5) 长度未知（total <= 0）
  const unknown: ArchiverNotificationPlan =
    ArchiverNotificationPlanner.plan('作品 B', 2002, 300, 0, 0, -1, false);
  eq('长度未知：不挂进度模板（否则进度条停在 0 像卡死）', unknown.hasTemplate, false);
  eq('长度未知：additionalText 为空', unknown.info, '');

  // ------------------------------------------------ 6) 空标题 / gid < 0
  eq('空标题回退「归档下载」(LABEL_SERVICE)',
    ArchiverNotificationPlanner.plan('', 1001, 0, 100, 0, -1, false).title, '归档下载');
  eq('gid < 0 时不显示按钮（上游同款判断）',
    ArchiverNotificationPlanner.plan('作品 A', -1, 0, 100, 0, -1, false).hasButton, false);

  // ------------------------------------------------ 7) 速度为 0 且未下载：正文留空
  eq('speed=0 且 downloaded=0：正文留空（不显示 0 B/s）',
    ArchiverNotificationPlanner.plan('作品 C', 1001, 0, 1000, 0, -1, false).text, '');

  // ------------------------------------------------ A-01：点击序号（连点可区分）
  //
  // 为什么钉住：鸿蒙的 `Want.parameters` 在 `getWantAgent()` 时**固化**、`trigger()` 不改它，
  // 配合 `UPDATE_PRESENT_FLAG`（"替换已存在的额外数据"）→ 两次点击的参数逐字节相同，
  // 接收方无法区分 → 用户视角"暂停/继续按钮连点第二次无效"。
  // 修法是在 parameters 里带自增 clickSeq + ts，所以这三条性质必须被断言锁死：
  //   ① 严格递增  ② 值域 1..999999（0 保留给"未设置"）  ③ 连续取值不重复
  const s1: number = ArchiverDownloadService.nextClickSeq();
  const s2: number = ArchiverDownloadService.nextClickSeq();
  const s3: number = ArchiverDownloadService.nextClickSeq();
  ok('A-01 nextClickSeq 严格递增', s2 > s1 && s3 > s2);
  ok('A-01 nextClickSeq 值域 1..999999', s1 >= 1 && s3 <= 999999);
  const seen: Set<number> = new Set<number>();
  for (let i = 0; i < 500; i++) {
    seen.add(ArchiverDownloadService.nextClickSeq());
  }
  eq('A-01 连续 500 次 nextClickSeq 互不相同', seen.size, 500);

  // handleWantParameters：只有带 archiver_action 才认领 —— 否则会把"普通冷启动"也当成下载命令吞掉
  ok('A-01 handleWantParameters(null) = false', !ArchiverDownloadService.handleWantParameters(null));
  const emptyParams: Record<string, Object> = {};
  ok('A-01 无 archiver_action 时不认领',
    !ArchiverDownloadService.handleWantParameters(emptyParams));

  // ------------------------------------------------ 汇总
  if (fails.length > 0) {
    console.error(`\n✗ ${fails.length} 条失败 / ${pass + fails.length} 条断言`);
    for (const f of fails) {
      console.error('  - ' + f);
    }
    throw new Error('archiver-notification test failed');
  }
  console.log(`✓ archiver-notification: ${pass} 条断言全部通过`);
}

main();
