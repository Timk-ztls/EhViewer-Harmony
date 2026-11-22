/*
 * download-sync 纯逻辑单测：通知任务的身份校验（D-012 加固，`NotifyIdentity`）
 * C-10：harmony/entry/src/test/<module>/
 *
 * 上游的保证是"回调与状态变更都在主线程"，所以 `currentTask` 在处理时刻一定还是那条任务。
 * D-012 之后通知任务是**异步执行**的：队列里可能还压着上一个任务的进度，而 `currentTask`
 * 已经换成新任务（或已清空）。没有校验，把 A 的页数/完成事件写到 B 上**不会报错**，
 * 只会让 B 的进度与终态错乱 —— 属于最难查的一类。
 *
 * 与 `ArchiverDownloader` 的 taskId 校验是同构的：
 *   - Archiver：`activeTasks.get(gid)?.taskId !== task.taskId` → 丢弃（同一 gid 可能被重下，必须比 taskId）
 *   - DownloadManager：`task.gid !== currentGid` → 丢弃（同一时刻只有一个 currentTask，gid 足够区分）
 */

import { NotifyIdentity } from '../../main/ets/hippo/ehviewer/download/DownloadManager';

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
  // ---------------------------------------------- 1) 匹配 → 执行
  eq('快照 gid == 当前 gid → 执行', NotifyIdentity.shouldApply(1001, 1001), true);
  eq('gid=0（首图馆）也是合法 gid → 执行', NotifyIdentity.shouldApply(0, 0), true);

  // ---------------------------------------------- 2) 不匹配 → 丢弃（核心）
  eq('**快照是 A、当前已换成 B → 丢弃**（否则 A 的进度写到 B 上）',
    NotifyIdentity.shouldApply(1001, 2002), false);
  eq('快照是 A、当前已清空（-1）→ 丢弃（任务已停止）',
    NotifyIdentity.shouldApply(1001, -1), false);
  eq('快照为空（-1）、当前有任务 → 丢弃（不属于任何任务的事件）',
    NotifyIdentity.shouldApply(-1, 1001), false);

  // ---------------------------------------------- 3) 两个 -1 不能算"同一任务"
  //
  // 这是最容易写错的一格：`-1 === -1` 成立，但语义是"双方都没有任务"，
  // 不是"指向同一个任务"。放行会让"任务已停止后压进来的进度"被写到一个空任务上。
  eq('**快照 -1 且当前 -1 → 仍然丢弃**（相等但不是同一任务）',
    NotifyIdentity.shouldApply(-1, -1), false);

  // ---------------------------------------------- 4) 边界：非法负数一律丢弃
  eq('负数 gid（任何一侧）→ 丢弃', NotifyIdentity.shouldApply(-5, 1001), false);
  eq('负数 gid（另一侧）→ 丢弃', NotifyIdentity.shouldApply(1001, -5), false);

  // ---------------------------------------------- 5) 四种真实场景（对应上游时序）
  //
  // a) 正常：A 正在下，回调与执行时刻一致
  eq('场景 a：A 下 A 的页 → 执行', NotifyIdentity.shouldApply(1001, 1001), true);
  // b) A 完成后 B 开始：队列里还压着 A 的一条页进度
  eq('场景 b：A 的页在 B 的 currentTask 下执行 → 丢弃', NotifyIdentity.shouldApply(1001, 2002), false);
  // c) A 被 stop：currentTask 清空，队列里的 A 进度
  eq('场景 c：A 被 stop 后 A 的完成事件 → 丢弃', NotifyIdentity.shouldApply(1001, -1), false);
  // d) A 重下（同 gid 新任务）：gid 相同，gid 级校验放行 —— 这与 Archiver 用 taskId 的差异点
  eq('场景 d：同 gid 重下 → gid 级校验放行（同一时刻只有一个 currentTask，够用）',
    NotifyIdentity.shouldApply(1001, 1001), true);

  // ---------------------------------------------- 6) 汇总
  if (fails.length > 0) {
    console.error(`\n✗ ${fails.length} 条失败 / ${pass + fails.length} 条断言`);
    for (const f of fails) {
      console.error('  - ' + f);
    }
    throw new Error('notify identity test failed');
  }
  console.log(`✓ notify-identity: ${pass} 条断言全部通过`);
}

main();
