/*
 * download-sync 纯逻辑单测：等待队列与空闲判定（`DownloadManager`）
 * C-10：harmony/entry/src/test/<module>/
 *
 * 队列的 bug 表现是"下载卡住不动"或"跳着下"，而且**都不报错**：
 *   - `isIdle()` 少判一项 → 服务提前 stopSelf，队列里还有任务却没人跑（像卡死）
 *   - 插入方向搞反 → "全部开始"顺序倒过来（我选的是从上往下，先下的却是最后一条）
 *   - 取队首用 `pop()` 而不是 `shift()` → 变成后进先出，队列语义直接坏掉
 */

import { DownloadQueueRules } from '../../main/ets/hippo/ehviewer/download/DownloadManager';

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
  // ------------------------------------------------------ 1) 空闲判定（两项都要判）
  eq('无任务 + 空队列 → 空闲', DownloadQueueRules.isIdle(false, 0), true);
  eq('有任务 → 非空闲', DownloadQueueRules.isIdle(true, 0), false);
  eq('**队列非空也非空闲**（少判这一项 → 服务提前 stopSelf，任务没人跑）',
    DownloadQueueRules.isIdle(false, 3), false);
  eq('有任务且队列非空 → 非空闲', DownloadQueueRules.isIdle(true, 3), false);

  // ------------------------------------------------------ 2) 能否启动下一个
  eq('无任务 + 有队列 → 可以启动', DownloadQueueRules.canStartNext(false, 2), true);
  eq('有任务 → 不能再启动（单并发）', DownloadQueueRules.canStartNext(true, 2), false);
  eq('无任务 + 空队列 → 不能启动', DownloadQueueRules.canStartNext(false, 0), false);

  // ------------------------------------------------------ 3) 插入方向
  eq('downloadOrder=true → push（队尾）', DownloadQueueRules.insertSide(true), 'push');
  eq('downloadOrder=false → unshift（队首）', DownloadQueueRules.insertSide(false), 'unshift');
  eq('单条重下 → 一律 unshift（插到最前，与批量不对称）',
    DownloadQueueRules.insertSideForRestart(), 'unshift');

  // ------------------------------------------------------ 4) FIFO 取队首
  eq('队列长度 3 → 取下标 0（FIFO；取 length-1 就成 LIFO）',
    DownloadQueueRules.nextIndex(3), 0);
  eq('空队列 → -1（不取）', DownloadQueueRules.nextIndex(0), -1);

  // ------------------------------------------------------ 5) 组合场景：真的做到 FIFO
  //
  // 用真实的数组语义模拟 waitList：先 push 三条，再按 nextIndex 依次取。
  const waitList: string[] = [];
  waitList.push('A');
  waitList.push('B');
  waitList.push('C');
  const taken: string[] = [];
  while (DownloadQueueRules.nextIndex(waitList.length) === 0) {
    taken.push(waitList.shift() as string);
  }
  eq('FIFO：入队 A,B,C → 出队 A,B,C', taken, ['A', 'B', 'C']);
  eq('取完队列空 → isIdle 且无任务 = 空闲',
    DownloadQueueRules.isIdle(false, waitList.length), true);

  // 重下插队：A 正在下，B/C 排队，重下 D 应插到最前
  const wl2: string[] = ['B', 'C'];
  wl2.unshift('D');
  eq('重下插队 → D 排最前', wl2, ['D', 'B', 'C']);

  // ------------------------------------------------------ 汇总
  if (fails.length > 0) {
    console.error(`\n✗ ${fails.length} 条失败 / ${pass + fails.length} 条断言`);
    for (const f of fails) {
      console.error('  - ' + f);
    }
    throw new Error('queue test failed');
  }
  console.log(`✓ queue: ${pass} 条断言全部通过`);
}

main();
