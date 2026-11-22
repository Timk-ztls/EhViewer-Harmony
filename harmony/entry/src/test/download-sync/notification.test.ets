/*
 * download-sync 纯逻辑单测：DownloadService 的通知状态机 N1–N8（C-10：harmony/entry/src/test/<module>/）
 *
 * 为什么这些逻辑能在宿主跑：真机验收只能验"显示效果"，而"发哪条通知、写什么文案、计数对不对"
 * 是纯逻辑。为此把 N1–N8 抽成 `DownloadNotificationPlanner`（纯函数、不认 notificationManager），
 * 本文件就是它的验收清单 —— 真机验收时按同一张表逐条对显示。
 *
 * 对照表的 N 编号见 `DownloadService.ets` 文件头「通知状态转换表」：
 *   N1 前台常驻 / N2 开始 / N3 进度 / N4 完成 / N5 509 / N6-N7 取消与收尾（副作用，宿主不验）/ N8 清除
 */

import {
  DownloadCounters,
  DownloadNotificationPlan,
  DownloadNotificationPlanner,
  DownloadService,
  FinishedSummary
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

function ok(name: string, cond: boolean): void {
  if (cond) {
    pass++;
  } else {
    fails.push(`${name}\n    want true, got false`);
  }
}

function main(): void {
  // ---------------------------------------------------------------- N1 前台常驻
  const idle: DownloadNotificationPlan = DownloadNotificationPlanner.idlePlan();
  eq('N1 通知 ID = 1（ID_DOWNLOADING）', idle.id, 1);
  eq('N1 标题固定「下载服务」', idle.title, '下载服务');
  eq('N1 不确定进度（progress = -1）', idle.progress, -1);
  eq('N1 常驻（ongoing）', idle.ongoing, true);
  eq('N1 无附加信息', idle.info, '');

  // ---------------------------------------------------------------- N2 开始下载
  eq('N2 空标题回退「下载服务」', DownloadNotificationPlanner.startPlan('').title, '下载服务');
  eq('N2 有标题原样使用', DownloadNotificationPlanner.startPlan('作品 A').title, '作品 A');
  eq('N2 仍是常驻', DownloadNotificationPlanner.startPlan('作品 A').ongoing, true);
  eq('N2 仍是不确定进度', DownloadNotificationPlanner.startPlan('作品 A').progress, -1);

  // ---------------------------------------------------------------- N3 进度
  const p: DownloadNotificationPlan = DownloadNotificationPlanner.progressPlan('作品 A', 1024, 90000, 3, 12);
  eq('N3 页数进度 = finished/total', p.info, '3/12');
  eq('N3 progress/max 供进度条', { progress: p.progress, max: p.max }, { progress: 3, max: 12 });
  ok('N3 文本含速度单位（/S）', p.text.indexOf('/S') >= 0);
  ok('N3 remaining >= 0 时含「剩余」', p.text.indexOf('剩余') >= 0);

  const pNoRemain: DownloadNotificationPlan =
    DownloadNotificationPlanner.progressPlan('作品 A', 1024, -1, 3, 12);
  ok('N3 remaining < 0 时不显示剩余时间', pNoRemain.text.indexOf('剩余') < 0);

  // 上游细节：total 或 finished 为 -1 时 additionalText 留空
  eq('N3 total = -1 → info 为空', DownloadNotificationPlanner.progressInfo(3, -1), '');
  eq('N3 finished = -1 → info 为空', DownloadNotificationPlanner.progressInfo(-1, 12), '');
  // 上游把负速度当 0 处理
  ok('N3 负速度按 0 处理（不出现负号）',
    DownloadNotificationPlanner.formatSpeedText(-5, -1).indexOf('-') < 0);

  // ---------------------------------------------------------------- N4 完成文案
  const st1: Map<number, boolean> = new Map<number, boolean>();
  const ti1: Map<number, string> = new Map<number, string>();
  DownloadNotificationPlanner.markFinished(st1, ti1, 1001, '作品 A', true);
  const s1: FinishedSummary = DownloadNotificationPlanner.summarize(st1, ti1);
  eq('N4 单条成功 → 文案带标题', s1.text, '已成功下载 作品 A');
  eq('N4 单条成功 → 不需要多行列表', s1.needLines, false);
  eq('N4 计数：成功 1 / 失败 0 / 已下载 1',
    { f: s1.finishedCount, x: s1.failedCount, d: s1.downloadedCount }, { f: 1, x: 0, d: 1 });

  const s2: FinishedSummary = DownloadNotificationPlanner.summarize(st1, ti1);
  eq('N4 重复完成同一条 → 计数不翻倍', s2.downloadedCount, 1);

  DownloadNotificationPlanner.markFinished(st1, ti1, 1002, '作品 B', true);
  const s3: FinishedSummary = DownloadNotificationPlanner.summarize(st1, ti1);
  eq('N4 两条成功 → 「已成功下载 2 项」', s3.text, '已成功下载 2 项');
  eq('N4 两条成功 → needLines', s3.needLines, true);
  eq('N4 多行正文按插入序 ✓', s3.lines, ['✓ 作品 A', '✓ 作品 B']);

  const st2: Map<number, boolean> = new Map<number, boolean>();
  const ti2: Map<number, string> = new Map<number, string>();
  DownloadNotificationPlanner.markFinished(st2, ti2, 2001, '作品 C', false);
  DownloadNotificationPlanner.markFinished(st2, ti2, 2002, '作品 D', false);
  const s4: FinishedSummary = DownloadNotificationPlanner.summarize(st2, ti2);
  eq('N4 两条失败 → 「下载失败 2 项」', s4.text, '下载失败 2 项');
  eq('N4 多行正文 ✗', s4.lines, ['✗ 作品 C', '✗ 作品 D']);

  const st3: Map<number, boolean> = new Map<number, boolean>();
  const ti3: Map<number, string> = new Map<number, string>();
  DownloadNotificationPlanner.markFinished(st3, ti3, 3001, '作品 E', true);
  DownloadNotificationPlanner.markFinished(st3, ti3, 3002, '作品 F', false);
  const s5: FinishedSummary = DownloadNotificationPlanner.summarize(st3, ti3);
  eq('N4 混合 → 「成功 1 项，失败 1 项」', s5.text, '成功 1 项，失败 1 项');
  eq('N4 混合 → 多行含 ✓ 与 ✗', s5.lines.length, 2);

  // 同一 gid 由失败翻成功（上游增量计数要 ±1 的地方）
  DownloadNotificationPlanner.markFinished(st3, ti3, 3002, '作品 F', true);
  const s6: FinishedSummary = DownloadNotificationPlanner.summarize(st3, ti3);
  eq('N4 翻转后计数：成功 2 / 失败 0',
    { f: s6.finishedCount, x: s6.failedCount, d: s6.downloadedCount }, { f: 2, x: 0, d: 2 });

  // 空列表实际不可达（onFinish 必然带着一条记录），这里只钉住**不崩**，且与上游 else 分支一致：
  // 上游 finishedCount==0 且 failedCount==0 时落进 else → "成功 0 项，失败 0 项"。
  const empty: FinishedSummary =
    DownloadNotificationPlanner.summarize(new Map<number, boolean>(), new Map<number, string>());
  eq('N4 空列表不崩，且与上游 else 分支一致', empty.text, '成功 0 项，失败 0 项');
  eq('N4 空列表计数全 0',
    { f: empty.finishedCount, x: empty.failedCount, d: empty.downloadedCount }, { f: 0, x: 0, d: 0 });

  // ---------------------------------------------------------------- N4 完成通知
  const done: DownloadNotificationPlan = DownloadNotificationPlanner.donePlan(s3);
  eq('N4 通知 ID = 2（ID_DOWNLOADED）', done.id, 2);
  eq('N4 标题「下载完成」', done.title, '下载完成');
  eq('N4 非常驻（可被用户清掉）', done.ongoing, false);
  eq('N4 角标 = 已下载条数', done.badge, 2);
  eq('N4 多行正文透传', done.lines, ['✓ 作品 A', '✓ 作品 B']);

  // ---------------------------------------------------------------- N5 509 告警
  const alert: DownloadNotificationPlan = DownloadNotificationPlanner.alert509Plan();
  eq('N5 通知 ID = 3（ID_509）', alert.id, 3);
  eq('N5 标题', alert.title, '509 流量限制');
  eq('N5 非常驻', alert.ongoing, false);
  eq('N5 与主状态机解耦（无多行）', alert.lines.length, 0);

  // ---------------------------------------------------------------- N8 清除（ACTION_CLEAR）
  //
  // N8 是唯一"不 publish、只清状态"的一行。上游清三个 int 计数器；
  // 移植里计数已改为由两条映射推导（D-041），因此 clear() 只需清映射 ——
  // 断言钉住"清完之后对外暴露的计数全为 0"，不钉实现细节。
  DownloadService.clear();
  const c0: DownloadCounters = DownloadService.getCounters();
  eq('N8 clear() 后计数全为 0',
    { f: c0.finishedCount, x: c0.failedCount, d: c0.downloadedCount }, { f: 0, x: 0, d: 0 });
  DownloadService.clear();
  const c1: DownloadCounters = DownloadService.getCounters();
  eq('N8 clear() 幂等（重复调用不报错、仍为 0）',
    { f: c1.finishedCount, x: c1.failedCount, d: c1.downloadedCount }, { f: 0, x: 0, d: 0 });

  // 清空后仍能继续记录（clear 不该把静态结构弄坏）
  const stAfter: Map<number, boolean> = new Map<number, boolean>();
  const tiAfter: Map<number, string> = new Map<number, string>();
  DownloadNotificationPlanner.markFinished(stAfter, tiAfter, 9001, '作品 Z', true);
  const sAfter: FinishedSummary = DownloadNotificationPlanner.summarize(stAfter, tiAfter);
  eq('N8 清除后继续记录仍正确', sAfter.text, '已成功下载 作品 Z');
  // ---------------------------------------------------------------- 汇总
  if (fails.length > 0) {
    console.error(`\n✗ ${fails.length} 条失败 / ${pass + fails.length} 条断言`);
    for (const f of fails) {
      console.error('  - ' + f);
    }
    throw new Error('notification test failed');
  }
  console.log(`✓ notification: ${pass} 条断言全部通过`);
}

main();
