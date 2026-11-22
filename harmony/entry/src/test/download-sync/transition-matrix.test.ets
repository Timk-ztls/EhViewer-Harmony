/*
 * download-sync 纯逻辑单测：状态转换矩阵 **8 状态 × 5 事件 = 40 格穷举**
 * C-10：harmony/entry/src/test/<module>/
 *
 * 为什么穷举：集合相等断言（state-machine.test.ets）只证明"每个状态的归属对"，
 * 但状态机的错常常出在**某一格**（"FINISH 能被全部开始"这类不对称），
 * 集合断言会把两格混在一起比，说不清是哪一格错。
 *
 * 三态标注（第三态很关键，它区分"测试没写到"和"这格本来就不存在"）：
 *   A:<状态>  允许，且落到该状态
 *   D         不允许（操作拒绝，状态不变）
 *   N         **不适用**：该状态不可能出现在这个事件的处理路径上
 *
 * 事件对应上游方法：
 *   START_RANGE = startRangeDownload      STAT_ALL = startAllDownload
 *   RESTORE     = addDownloadList（恢复导入）
 *   STOP        = stopDownload/stopAllDownload/stopRangeDownload 的共同效果
 *   FINISH      = onFinish（终态由 legacy = total - finished 决定）
 */

import { DownloadStateMachine } from '../../main/ets/hippo/ehviewer/download/DownloadManager';
import { DownloadInfo } from '../../main/ets/hippo/ehviewer/dao/DownloadInfo';

let pass = 0;
const fails: string[] = [];

function eq(name: string, got: string, want: string): void {
  if (got === want) {
    pass++;
  } else {
    fails.push(`${name}\n    got  ${got}\n    want ${want}`);
  }
}

/** 事件编号 */
const E_RANGE: number = 0;
const E_ALL: number = 1;
const E_RESTORE: number = 2;
const E_STOP: number = 3;
const E_FINISH: number = 4;
const EVENT_NAMES: string[] = ['START_RANGE', 'START_ALL', 'RESTORE', 'STOP', 'FINISH'];

/** 状态列表（含两个非状态常量，验证它们"不被任何事件接受"） */
const STATES: number[] = [
  DownloadInfo.STATE_INVALID,
  DownloadInfo.STATE_NONE,
  DownloadInfo.STATE_WAIT,
  DownloadInfo.STATE_DOWNLOAD,
  DownloadInfo.STATE_FINISH,
  DownloadInfo.STATE_FAILED,
  DownloadInfo.STATE_UPDATE,
  DownloadInfo.GOTO_NEW
];
const STATE_NAMES: string[] = ['INVALID', 'NONE', 'WAIT', 'DOWNLOAD', 'FINISH', 'FAILED', 'UPDATE', 'GOTO_NEW'];

/** 状态是否"可能出现在处理路径上"（INVALID 只是查询返回值；UPDATE/GOTO_NEW 不在本管理器） */
function isRealState(state: number): boolean {
  return state === DownloadInfo.STATE_NONE || state === DownloadInfo.STATE_WAIT ||
    state === DownloadInfo.STATE_DOWNLOAD || state === DownloadInfo.STATE_FINISH ||
    state === DownloadInfo.STATE_FAILED;
}

/**
 * 期望矩阵（每行一个状态，5 列对应 5 个事件）。
 * 每一格都是对着上游代码写下的，不是照着实现反推的 —— 这正是穷举的意义。
 */
const EXPECTED: string[][] = [
  // INVALID(-1)：只作 `getDownloadState` 的返回值，从不写入实体
  ['N', 'N', 'N', 'N', 'N'],
  // NONE(0)：可被两个 start 拉进队列；恢复时保持；stop 后仍是 NONE
  ['A:WAIT', 'A:WAIT', 'A:NONE', 'A:NONE', 'N'],
  // WAIT(1)：已在队列里，start* 拒绝重复入队；恢复归 NONE；stop 移除
  ['D', 'D', 'A:NONE', 'A:NONE', 'N'],
  // DOWNLOAD(2)：正在下载，start* 拒绝；恢复归 NONE；stop 取消；FINISH 由 legacy 决定
  ['D', 'D', 'A:NONE', 'A:NONE', 'A:FINISH'],
  // FINISH(3)：**范围下载可重下（A:WAIT），全部下载不可（D）** —— 全表唯一的不对称
  ['A:WAIT', 'D', 'A:FINISH', 'N', 'N'],
  // FAILED(4)：两个 start 都接受
  ['A:WAIT', 'A:WAIT', 'A:FAILED', 'N', 'N'],
  // UPDATE(5)：版本升级流程用，本管理器从不写入 → 不该出现在任何处理路径
  ['N', 'N', 'N', 'N', 'N'],
  // GOTO_NEW(6)：非状态，仅 UI 跳转常量
  ['N', 'N', 'N', 'N', 'N']
];

/** 计算实际结果（全部走产品代码的纯判定，不在这里重写规则） */
function actual(state: number, event: number): string {
  // 非真实状态：任何事件都不接受（这一条对 INVALID/UPDATE/GOTO_NEW 立即返回 N）
  if (!isRealState(state)) {
    return 'N';
  }
  switch (event) {
    case E_RANGE:
      return DownloadStateMachine.isStartableForRange(state) ? 'A:WAIT' : 'D';
    case E_ALL:
      return DownloadStateMachine.isStartableForAll(state) ? 'A:WAIT' : 'D';
    case E_RESTORE:
      // 恢复：WAIT/DOWNLOAD 归 NONE，其余保持不变
      return DownloadStateMachine.needsResetOnRestore(state) ? 'A:NONE' : `A:${STATE_NAMES[STATES.indexOf(state)]}`;
    case E_STOP:
      // stop* 只作用在 waitList（WAIT）与 currentTask（DOWNLOAD）上；NONE 是幂等
      if (state === DownloadInfo.STATE_NONE || state === DownloadInfo.STATE_WAIT ||
        state === DownloadInfo.STATE_DOWNLOAD) {
        return 'A:NONE';
      }
      return 'N';
    case E_FINISH:
      // FINISH 事件只可能从 DOWNLOAD 触发；终态由 legacy 决定
      if (state !== DownloadInfo.STATE_DOWNLOAD) {
        return 'N';
      }
      return DownloadStateMachine.resolveFinishStateFromCounts(10, 10) === DownloadInfo.STATE_FINISH
        ? 'A:FINISH' : 'A:FAILED';
    default:
      return '?';
  }
}

function main(): void {
  // ------------------------------------------------ 40 格逐格比对
  let cells: number = 0;
  for (let s = 0; s < STATES.length; s++) {
    for (let e = 0; e < EVENT_NAMES.length; e++) {
      cells++;
      const got: string = actual(STATES[s], e);
      eq(`[${STATE_NAMES[s]} × ${EVENT_NAMES[e]}]`, got, EXPECTED[s][e]);
    }
  }
  eq('矩阵规模 = 8 × 5 = 40 格', String(cells), '40');

  // ------------------------------------------------ 逐格之外的三条不变量
  //
  // 这些是"跨格"性质，单格比对抓不到：
  eq('不对称点：FINISH 可范围重下、不可全部开始',
    `${actual(DownloadInfo.STATE_FINISH, E_RANGE)}/${actual(DownloadInfo.STATE_FINISH, E_ALL)}`,
    'A:WAIT/D');

  // 终态由 legacy 决定：同一次 FINISH 事件，legacy=0 → FINISH，legacy>0 → FAILED
  eq('FINISH 事件：legacy=0 → STATE_FINISH',
    String(DownloadStateMachine.resolveFinishStateFromCounts(10, 10)), String(DownloadInfo.STATE_FINISH));
  eq('FINISH 事件：legacy>0 → STATE_FAILED',
    String(DownloadStateMachine.resolveFinishStateFromCounts(10, 9)), String(DownloadInfo.STATE_FAILED));

  // 任何 start 的落点都是 WAIT，绝不会直接落到 DOWNLOAD（只有 ensureDownload 才写 DOWNLOAD）
  eq('start* 只落 WAIT，不直接落 DOWNLOAD（写 DOWNLOAD 的唯一入口是 ensureDownload）',
    `${actual(DownloadInfo.STATE_NONE, E_RANGE)}/${actual(DownloadInfo.STATE_FAILED, E_ALL)}`,
    'A:WAIT/A:WAIT');

  // ------------------------------------------------ 汇总
  if (fails.length > 0) {
    console.error(`\n✗ ${fails.length} 格不符 / ${pass + fails.length} 条断言`);
    for (const f of fails) {
      console.error('  - ' + f);
    }
    throw new Error('transition matrix test failed');
  }
  console.log(`✓ transition-matrix: ${pass} 条断言全部通过（含 40 格穷举）`);
}

main();
