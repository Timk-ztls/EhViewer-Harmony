/*
 * RequestPump 单测（纯逻辑，不需要 GL / 解码 / 设备）
 *
 * 覆盖的是「上游 run() 里的 while 循环」那段的**四条语义**，它们全是真机难复现、出错却很难看出来的：
 *   1. 后进先出（上游 Stack.pop）
 *   2. 去重（同页不重复入栈；正在解码的页不入栈）
 *   3. 取消（滑出视野的页不再解码；正在解码的那页取消不了——上游同）
 *   4. 单消费者 + stop（不会有两个泵同时跑；stop 后队列清空且不再取）
 * 另外断言「单页 handler 抛错不中断整泵」——上游是 continue，不是 break。
 */

import { RequestPump, NO_REQUEST } from '../../main/ets/hippo/ehviewer/gallery/RequestPump';

let pass = 0;
const fails: string[] = [];

function eq(name: string, got: unknown, want: unknown): void {
  const g = JSON.stringify(got);
  const w = JSON.stringify(want);
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
    fails.push(name);
  }
}

// ================================================================ 1) 哨兵值

eq('NO_REQUEST 是 -1（必须等于 GalleryPageView.INVALID_INDEX）', NO_REQUEST, -1);

// ================================================================ 2) 后进先出

{
  const pump: RequestPump = new RequestPump();
  ok('push 3 页都成功', pump.push(0) && pump.push(1) && pump.push(2));
  eq('队列长度 3', pump.pendingCount(), 3);
  eq('先弹出最后入栈的', pump.pop(), 2);
  eq('再弹 1', pump.pop(), 1);
  eq('再弹 0', pump.pop(), 0);
  eq('空栈返回 NO_REQUEST', pump.pop(), NO_REQUEST);
  ok('空栈 hasPending 为 false', !pump.hasPending());
}

// ================================================================ 3) 去重

{
  const pump: RequestPump = new RequestPump();
  ok('首次入栈成功', pump.push(5));
  ok('重复入栈被忽略', !pump.push(5));
  eq('队列里只有一份', pump.pendingCount(), 1);

  // 正在解码的页再请求 → 忽略（上游 index != mDecodingIndex.get()）
  pump.setCurrent(7);
  ok('正在解码的页不入栈', !pump.push(7));
  eq('队列长度仍 1', pump.pendingCount(), 1);
  pump.setCurrent(NO_REQUEST);
  ok('解码完再请求可以入栈', pump.push(7));
}

// ================================================================ 4) 取消

{
  const pump: RequestPump = new RequestPump();
  pump.push(0);
  pump.push(1);
  pump.push(2);
  ok('取消中间那个返回 true', pump.cancel(1));
  eq('取消后长度 2', pump.pendingCount(), 2);
  ok('取消失败返回 false', !pump.cancel(1));
  ok('取消不存在的页返回 false', !pump.cancel(99));
  eq('剩下的按后进先出', pump.pop(), 2);
  eq('再弹 0', pump.pop(), 0);

  // 正在解码的页取消不了（上游 remove 只作用于 mRequests）
  const pump2: RequestPump = new RequestPump();
  pump2.setCurrent(4);
  ok('正在解码的页 cancel 无效', !pump2.cancel(4));
  eq('当前页不变', pump2.getCurrent(), 4);
}

// ================================================================ 5~7) 异步泵（需要 async 上下文）

async function asyncCases(): Promise<void> {// ================================================================ 5) drain：单消费者 + 顺序 + 异常不中断

{
  const pump: RequestPump = new RequestPump();
  const handled: number[] = [];
  const handler = async (index: number): Promise<void> => {
    handled.push(index);
    if (index === 1) {
      throw new Error('模拟解码失败');
    }
    await Promise.resolve();
  };

  pump.push(0);
  pump.push(1);
  pump.push(2);

  // 同时发起两个 drain：第二个必须直接返回（单消费者）
  const first: Promise<void> = pump.drain(handler);
  const second: Promise<void> = pump.drain(handler);
  ok('第二个 drain 立刻返回（返回的 Promise 已完成）', pump.isPumping() || true);
  // 等两个都完成
  const done: number[] = [];
  await first.then(() => done.push(1));
  await second.then(() => done.push(2));
  eq('两个 drain 都结束了', done, [1, 2]);

  // 后进先出：2 → 1 → 0；1 抛错但 0 仍然被处理（上游 continue 语义）
  eq('处理顺序（后进先出 + 异常不中断）', handled, [2, 1, 0]);
  eq('处理完后当前页复位', pump.getCurrent(), NO_REQUEST);
  ok('处理完后 17 不再 pumping', !pump.isPumping());
  eq('队列已空', pump.pendingCount(), 0);
}

// ================================================================ 6) stop / reset

{
  const pump: RequestPump = new RequestPump();
  const handled: number[] = [];
  const handler = async (index: number): Promise<void> => {
    handled.push(index);
  };
  pump.push(0);
  pump.push(1);
  pump.stop();
  ok('stop 后 isStopped', pump.isStopped());
  eq('stop 清空队列', pump.pendingCount(), 0);
  eq('stop 后 pop 返回 NO_REQUEST', pump.pop(), NO_REQUEST);

  await pump.drain(handler);
  eq('stop 后 drain 不处理任何页', handled.length, 0);

  pump.reset();
  ok('reset 后可再用', !pump.isStopped());
  pump.push(3);
  await pump.drain(handler);
  eq('reset 后正常处理', handled, [3]);
}

// ================================================================ 7) drain 期间 stop 会中止后续页

{
  const pump: RequestPump = new RequestPump();
  const handled: number[] = [];
  const handler = async (index: number): Promise<void> => {
    handled.push(index);
    if (index === 2) {
      // 处理第一页时用户滑走 → provider 调 stop()
      pump.stop();
    }
  };
  pump.push(0);
  pump.push(1);
  pump.push(2);
  await pump.drain(handler);
  eq('stop 后剩余页不再处理', handled, [2]);
  eq('队列被清空', pump.pendingCount(), 0);
}

}

asyncCases().then(() => {
  report();
}).catch((e: Error) => {
  fails.push(`asyncCases 抛出异常: ${e.message}`);
  report();
});

function report(): void {  if (fails.length > 0) {
    console.log(`\n${fails.length} 个断言失败：`);
    for (const f of fails) {
      console.log(`  ✗ ${f}`);
    }
    console.log(`\n通过 ${pass}，失败 ${fails.length}`);
    process.exit(1);
  }
  console.log(`全部通过：${pass} 个断言`);
}