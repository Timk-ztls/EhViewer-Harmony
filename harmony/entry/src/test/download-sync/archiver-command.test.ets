/*
 * download-sync 纯逻辑单测：归档下载的 action 分派（`ArchiverDownloadService.onStartCommand`）
 * C-10：harmony/entry/src/test/<module>/
 *
 * 为什么必须测：五个 action 只靠字符串相等分派，写错一个分支**不会编译报错**，
 * 只会"按暂停变继续"或"按停止变成刷新通知"。真机上表现为"点按钮没反应 / 点了反而开始下载"，
 * 而且会跟通知节流搅在一起，极难定位。
 *
 * 上游语义（`ArchiverDownloadService.onStartCommand`）：
 *   STOP   → START_NOT_STICKY（keepAlive=false）
 *   PAUSE  → START_NOT_STICKY（keepAlive=false）
 *   RESUME → START_STICKY     （keepAlive=true）
 *   默认   → START_STICKY     （keepAlive=true，含未知 action）
 */

import {
  ArchiverCommandPlan,
  ArchiverCommandPlanner,
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

function extras(pairs: Map<string, Object>): Map<string, Object> {
  return pairs;
}

function withGid(gid: number): Map<string, Object> {
  const m: Map<string, Object> = new Map<string, Object>();
  m.set(ArchiverDownloadService.EXTRA_GID, gid);
  return m;
}

function main(): void {
  const KIND_IGNORE: number = ArchiverCommandPlanner.KIND_IGNORE;
  const KIND_UPDATE: number = ArchiverCommandPlanner.KIND_UPDATE;
  const KIND_PAUSE: number = ArchiverCommandPlanner.KIND_PAUSE;
  const KIND_RESUME: number = ArchiverCommandPlanner.KIND_RESUME;
  const KIND_STOP: number = ArchiverCommandPlanner.KIND_STOP;

  // ---------------------------------------------- 1) action = null
  const pNull: ArchiverCommandPlan = ArchiverCommandPlanner.plan(null, extras(new Map<string, Object>()));
  eq('action 为 null → IGNORE', pNull.kind, KIND_IGNORE);
  eq('action 为 null → keepAlive=false', pNull.keepAlive, false);

  // ---------------------------------------------- 2) STOP
  const pStop: ArchiverCommandPlan =
    ArchiverCommandPlanner.plan(ArchiverDownloadService.ACTION_STOP, withGid(1001));
  eq('STOP → KIND_STOP', pStop.kind, KIND_STOP);
  eq('STOP → keepAlive=false（上游 START_NOT_STICKY）', pStop.keepAlive, false);

  // ---------------------------------------------- 3) PAUSE / RESUME（需要 gid）
  const pPause: ArchiverCommandPlan =
    ArchiverCommandPlanner.plan(ArchiverDownloadService.ACTION_PAUSE, withGid(1001));
  eq('PAUSE → KIND_PAUSE', pPause.kind, KIND_PAUSE);
  eq('PAUSE → keepAlive=false', pPause.keepAlive, false);
  eq('PAUSE → gid 解析正确', pPause.gid, 1001);

  const pPauseNoGid: ArchiverCommandPlan =
    ArchiverCommandPlanner.plan(ArchiverDownloadService.ACTION_PAUSE, extras(new Map<string, Object>()));
  eq('PAUSE 不带 gid → IGNORE（无效指令不下发暂停）', pPauseNoGid.kind, KIND_IGNORE);
  eq('PAUSE 不带 gid → gid 回退 -1', pPauseNoGid.gid, -1);

  const pResume: ArchiverCommandPlan =
    ArchiverCommandPlanner.plan(ArchiverDownloadService.ACTION_RESUME, withGid(1001));
  eq('RESUME → KIND_RESUME', pResume.kind, KIND_RESUME);
  eq('RESUME → keepAlive=**true**（上游 START_STICKY，与 PAUSE 不对称）', pResume.keepAlive, true);

  const pResumeNoGid: ArchiverCommandPlan =
    ArchiverCommandPlanner.plan(ArchiverDownloadService.ACTION_RESUME, extras(new Map<string, Object>()));
  eq('RESUME 不带 gid → IGNORE（但 keepAlive 仍为 true）',
    { kind: pResumeNoGid.kind, alive: pResumeNoGid.keepAlive }, { kind: KIND_IGNORE, alive: true });

  // gid = 0 是合法 gid（首图馆），不能被当成"没带"
  const pGidZero: ArchiverCommandPlan =
    ArchiverCommandPlanner.plan(ArchiverDownloadService.ACTION_PAUSE, withGid(0));
  eq('gid=0 视为合法（不能被当成未携带）', pGidZero.kind, KIND_PAUSE);

  // ---------------------------------------------- 4) 默认分支：刷新进度
  const progressExtras: Map<string, Object> = new Map<string, Object>();
  progressExtras.set(ArchiverDownloadService.EXTRA_TITLE, '作品 A');
  progressExtras.set(ArchiverDownloadService.EXTRA_GID, 1001);
  progressExtras.set(ArchiverDownloadService.EXTRA_TOKEN, 'tok');
  progressExtras.set(ArchiverDownloadService.EXTRA_DOWNLOADED, 512);
  progressExtras.set(ArchiverDownloadService.EXTRA_TOTAL, 2048);
  progressExtras.set(ArchiverDownloadService.EXTRA_SPEED, 1024);
  progressExtras.set(ArchiverDownloadService.EXTRA_REMAINING, 30000);

  const pUpdate: ArchiverCommandPlan =
    ArchiverCommandPlanner.plan(ArchiverDownloadService.ACTION_UPDATE, progressExtras);
  eq('UPDATE → KIND_UPDATE', pUpdate.kind, KIND_UPDATE);
  eq('UPDATE 非暂停 → 需要进前台', pUpdate.needForeground, true);
  eq('UPDATE 非暂停 → keepAlive=true', pUpdate.keepAlive, true);
  eq('extras 全解析正确',
    {
      t: pUpdate.title, g: pUpdate.gid, tk: pUpdate.token,
      d: pUpdate.downloaded, tot: pUpdate.total, sp: pUpdate.speed, rem: pUpdate.remaining
    },
    { t: '作品 A', g: 1001, tk: 'tok', d: 512, tot: 2048, sp: 1024, rem: 30000 });

  // START 与未知 action 都走同一条默认路径（上游 else 分支）
  const pStart: ArchiverCommandPlan =
    ArchiverCommandPlanner.plan(ArchiverDownloadService.ACTION_START, progressExtras);
  eq('START 走默认分支（上游 else）', pStart.kind, KIND_UPDATE);
  const pUnknown: ArchiverCommandPlan =
    ArchiverCommandPlanner.plan('some_unknown_action', progressExtras);
  eq('未知 action 也走默认分支（不是忽略）', pUnknown.kind, KIND_UPDATE);

  // ---------------------------------------------- 5) 暂停态的更新
  const pausedExtras: Map<string, Object> = new Map<string, Object>();
  pausedExtras.set(ArchiverDownloadService.EXTRA_GID, 1001);
  pausedExtras.set(ArchiverDownloadService.EXTRA_PAUSED, true);
  const pPaused: ArchiverCommandPlan =
    ArchiverCommandPlanner.plan(ArchiverDownloadService.ACTION_UPDATE, pausedExtras);
  eq('暂停态更新 → 标记 paused', pPaused.paused, true);
  eq('暂停态更新 → 不需要进前台（走 showPausedNotification）', pPaused.needForeground, false);
  eq('暂停态更新 → keepAlive=false（上游 START_NOT_STICKY）', pPaused.keepAlive, false);

  // ---------------------------------------------- 6) 缺省值
  const pBare: ArchiverCommandPlan =
    ArchiverCommandPlanner.plan(ArchiverDownloadService.ACTION_UPDATE, extras(new Map<string, Object>()));
  eq('全空 extras 的缺省值',
    { g: pBare.gid, t: pBare.title, d: pBare.downloaded, tot: pBare.total, rem: pBare.remaining,
      paused: pBare.paused },
    { g: -1, t: '', d: 0, tot: 0, rem: -1, paused: false });

  // ---------------------------------------------- 汇总
  if (fails.length > 0) {
    console.error(`\n✗ ${fails.length} 条失败 / ${pass + fails.length} 条断言`);
    for (const f of fails) {
      console.error('  - ' + f);
    }
    throw new Error('archiver-command test failed');
  }
  console.log(`✓ archiver-command: ${pass} 条断言全部通过`);
}

main();
