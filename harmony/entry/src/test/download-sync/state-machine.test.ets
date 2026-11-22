/*
 * download-sync 纯逻辑单测：下载状态机的进入条件（C-10：harmony/entry/src/test/<module>/）
 *
 * 对应 `DownloadManager.ets` 文件头的「状态机对照表」。真机/集成测试只能验"跑起来对不对"，
 * 而状态表里最容易写反的是**进入条件的不对称**：
 *   - startRangeDownload 允许 FINISH（已下完可重下），startAllDownload 不允许
 *   - 恢复导入时 WAIT / DOWNLOAD 必须归 NONE（不能恢复出"正在下载"）
 *   - 终态由 legacy = total - finished 是否为 0 决定
 * 这些写反了不会报错，只会行为漂移 —— 本文件把它们钉成断言。
 */

import { DownloadStateMachine } from '../../main/ets/hippo/ehviewer/download/DownloadManager';
import { DownloadInfo } from '../../main/ets/hippo/ehviewer/dao/DownloadInfo';

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
  // -------------------------------------------------- 进入条件：范围下载 vs 全部下载
  eq('范围下载：NONE 可入队', DownloadStateMachine.isStartableForRange(DownloadInfo.STATE_NONE), true);
  eq('范围下载：FAILED 可入队', DownloadStateMachine.isStartableForRange(DownloadInfo.STATE_FAILED), true);
  eq('范围下载：FINISH **可**重下（上游不对称点）',
    DownloadStateMachine.isStartableForRange(DownloadInfo.STATE_FINISH), true);
  eq('范围下载：WAIT 不重复入队', DownloadStateMachine.isStartableForRange(DownloadInfo.STATE_WAIT), false);
  eq('范围下载：DOWNLOAD 不重复入队',
    DownloadStateMachine.isStartableForRange(DownloadInfo.STATE_DOWNLOAD), false);

  eq('全部下载：NONE 可入队', DownloadStateMachine.isStartableForAll(DownloadInfo.STATE_NONE), true);
  eq('全部下载：FAILED 可入队', DownloadStateMachine.isStartableForAll(DownloadInfo.STATE_FAILED), true);
  eq('全部下载：FINISH **不可**入队（与范围下载的不对称）',
    DownloadStateMachine.isStartableForAll(DownloadInfo.STATE_FINISH), false);
  eq('全部下载：WAIT 不入队', DownloadStateMachine.isStartableForAll(DownloadInfo.STATE_WAIT), false);
  eq('全部下载：DOWNLOAD 不入队',
    DownloadStateMachine.isStartableForAll(DownloadInfo.STATE_DOWNLOAD), false);

  // -------------------------------------------------- 恢复/导入
  eq('恢复：WAIT 要归 NONE', DownloadStateMachine.needsResetOnRestore(DownloadInfo.STATE_WAIT), true);
  eq('恢复：DOWNLOAD 要归 NONE', DownloadStateMachine.needsResetOnRestore(DownloadInfo.STATE_DOWNLOAD), true);
  eq('恢复：FINISH 保持', DownloadStateMachine.needsResetOnRestore(DownloadInfo.STATE_FINISH), false);
  eq('恢复：FAILED 保持', DownloadStateMachine.needsResetOnRestore(DownloadInfo.STATE_FAILED), false);
  eq('恢复：NONE 保持', DownloadStateMachine.needsResetOnRestore(DownloadInfo.STATE_NONE), false);

  // -------------------------------------------------- 终态判定
  eq('终态：legacy = 0 → FINISH', DownloadStateMachine.resolveFinishState(0), DownloadInfo.STATE_FINISH);
  eq('终态：legacy = 3 → FAILED', DownloadStateMachine.resolveFinishState(3), DownloadInfo.STATE_FAILED);
  eq('终态：legacy = -1（total 未知）→ FAILED',
    DownloadStateMachine.resolveFinishState(-1), DownloadInfo.STATE_FAILED);
  eq('isTerminal(FINISH)', DownloadStateMachine.isTerminal(DownloadInfo.STATE_FINISH), true);
  eq('isTerminal(FAILED)', DownloadStateMachine.isTerminal(DownloadInfo.STATE_FAILED), true);
  eq('isTerminal(DOWNLOAD)', DownloadStateMachine.isTerminal(DownloadInfo.STATE_DOWNLOAD), false);

  // -------------------------------------------------- 批量入队的顺序语义
  // downloadOrder = true（正序）：取第 0,1,2… 个
  eq('正序取用：size=3 → [0,1,2]',
    [0, 1, 2].map((k: number): number => DownloadStateMachine.enqueueIndex(true, 3, k)), [0, 1, 2]);
  // downloadOrder = false（倒序）：取第 2,1,0 个 —— 上游 `for (i = n; i > 0; i--)`
  eq('倒序取用：size=3 → [2,1,0]',
    [0, 1, 2].map((k: number): number => DownloadStateMachine.enqueueIndex(false, 3, k)), [2, 1, 0]);
  eq('全部开始：正序用 push（队尾）', DownloadStateMachine.usePushForAll(true), true);
  eq('全部开始：倒序用 unshift（队首）', DownloadStateMachine.usePushForAll(false), false);

  // -------------------------------------------------- 终态：从计数直接算（防"忘了赋 legacy"）
  //
  // 真实 bug：上游 TYPE_ON_FINISH 里有一步 `info.legacy = mTotal - mFinished`，
  // 移植时漏掉 → legacy 保持开始时的 -1 → resolveFinishState(-1) 恒为 FAILED
  // → **每一页都成功也显示"下载失败"**。这条断言把这个入口钉死。
  eq('全部成功（10/10）→ FINISH',
    DownloadStateMachine.resolveFinishStateFromCounts(10, 10), DownloadInfo.STATE_FINISH);
  eq('差 1 页（10/9）→ FAILED',
    DownloadStateMachine.resolveFinishStateFromCounts(10, 9), DownloadInfo.STATE_FAILED);
  eq('全部失败（10/0）→ FAILED',
    DownloadStateMachine.resolveFinishStateFromCounts(10, 0), DownloadInfo.STATE_FAILED);
  eq('多下（进度越界 10/11）→ legacy<0 → FAILED（不误判成功）',
    DownloadStateMachine.resolveFinishStateFromCounts(10, 11), DownloadInfo.STATE_FAILED);

  // -------------------------------------------------- 状态全表：8 行逐行守护
  //
  // 用"每个状态在四个判定里的归属"做穷举，确保状态机表里每一行都有断言，
  // 也防止有人把 STATE_UPDATE / GOTO_NEW 误加进"可入队"集合。
  const allStates: number[] = [
    DownloadInfo.STATE_INVALID, DownloadInfo.STATE_NONE, DownloadInfo.STATE_WAIT,
    DownloadInfo.STATE_DOWNLOAD, DownloadInfo.STATE_FINISH, DownloadInfo.STATE_FAILED,
    DownloadInfo.STATE_UPDATE, DownloadInfo.GOTO_NEW
  ];
  const startableRange: number[] = [];
  const startableAll: number[] = [];
  const resettable: number[] = [];
  const terminal: number[] = [];
  for (let i = 0; i < allStates.length; i++) {
    const s: number = allStates[i];
    if (DownloadStateMachine.isStartableForRange(s)) {
      startableRange.push(s);
    }
    if (DownloadStateMachine.isStartableForAll(s)) {
      startableAll.push(s);
    }
    if (DownloadStateMachine.needsResetOnRestore(s)) {
      resettable.push(s);
    }
    if (DownloadStateMachine.isTerminal(s)) {
      terminal.push(s);
    }
  }
  eq('范围下载可入队 = {NONE, FINISH, FAILED}（表里 FINISH 的"离开条件"）',
    startableRange, [DownloadInfo.STATE_NONE, DownloadInfo.STATE_FINISH, DownloadInfo.STATE_FAILED]);
  eq('全部下载可入队 = {NONE, FAILED}（不含 FINISH）',
    startableAll, [DownloadInfo.STATE_NONE, DownloadInfo.STATE_FAILED]);
  eq('恢复时归零 = {WAIT, DOWNLOAD}（表里 NONE 的"进入条件"之一）',
    resettable, [DownloadInfo.STATE_WAIT, DownloadInfo.STATE_DOWNLOAD]);
  eq('终态 = {FINISH, FAILED}',
    terminal, [DownloadInfo.STATE_FINISH, DownloadInfo.STATE_FAILED]);

  // 表里两行"永不被管理器接受"的状态：INVALID(-1) 只作查询返回值；UPDATE(5)/GOTO_NEW(6) 不在本管理器范围
  eq('INVALID 不是任何可入队/终态/待归零状态',
    {
      r: DownloadStateMachine.isStartableForRange(DownloadInfo.STATE_INVALID),
      a: DownloadStateMachine.isStartableForAll(DownloadInfo.STATE_INVALID),
      t: DownloadStateMachine.isTerminal(DownloadInfo.STATE_INVALID),
      z: DownloadStateMachine.needsResetOnRestore(DownloadInfo.STATE_INVALID)
    }, { r: false, a: false, t: false, z: false });
  eq('UPDATE(5) 不被任何入口接受（表里写明"本管理器从不写入"）',
    {
      r: DownloadStateMachine.isStartableForRange(DownloadInfo.STATE_UPDATE),
      a: DownloadStateMachine.isStartableForAll(DownloadInfo.STATE_UPDATE),
      t: DownloadStateMachine.isTerminal(DownloadInfo.STATE_UPDATE)
    }, { r: false, a: false, t: false });
  eq('GOTO_NEW(6) 不被任何入口接受（非状态，仅 UI 跳转常量）',
    {
      r: DownloadStateMachine.isStartableForRange(DownloadInfo.GOTO_NEW),
      a: DownloadStateMachine.isStartableForAll(DownloadInfo.GOTO_NEW),
      t: DownloadStateMachine.isTerminal(DownloadInfo.GOTO_NEW)
    }, { r: false, a: false, t: false });
  // -------------------------------------------------- 汇总
  if (fails.length > 0) {
    console.error(`\n✗ ${fails.length} 条失败 / ${pass + fails.length} 条断言`);
    for (const f of fails) {
      console.error('  - ' + f);
    }
    throw new Error('state machine test failed');
  }
  console.log(`✓ state-machine: ${pass} 条断言全部通过`);
}

main();
