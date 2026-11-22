/*
 * download-sync 纯逻辑单测：串行 FIFO 队列（`SerialQueue`，D-012 的落点）
 * C-10：harmony/entry/src/test/<module>/
 *
 * `DownloadManager` 的所有写路径都排在这条链上。它坏掉的两种形态都**不报错**：
 *   1. 失败不释放 → 后续所有写操作永久挂起（下载再也启动不了，日志像"死锁"）
 *   2. 不是 FIFO → "读-改-写"三段之间被别的转换插入，currentTask/waitList 半更新
 *
 * 第三组断言是**反向保护**：证明"body 内部再 enqueue"确实会自锁，
 * 免得以后有人觉得"嵌套一下更方便"。
 */

import { SerialQueue } from '../../main/ets/hippo/ehviewer/download/DownloadManager';

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

function delay(ms: number): Promise<void> {
  return new Promise<void>((resolve: () => void): void => {
    setTimeout(resolve, ms);
  });
}

async function main(): Promise<void> {
  // ------------------------------------------------ 1) FIFO 顺序
  const q1: SerialQueue = new SerialQueue();
  const order: number[] = [];
  const t1: Promise<void> = q1.enqueue(async (): Promise<void> => {
    await delay(20);          // 第一个故意慢，验证后来者不会插队
    order.push(1);
  });
  const t2: Promise<void> = q1.enqueue(async (): Promise<void> => {
    order.push(2);
  });
  const t3: Promise<void> = q1.enqueue(async (): Promise<void> => {
    order.push(3);
  });
  await Promise.all([t1, t2, t3]);
  eq('FIFO：即使第一个最慢，顺序仍是 1,2,3', order, [1, 2, 3]);

  // ------------------------------------------------ 2) 失败也要释放（关键）
  const q2: SerialQueue = new SerialQueue();
  let afterFailedRan: boolean = false;
  const bad: Promise<void> = q2.enqueue(async (): Promise<void> => {
    throw new Error('boom');
  });
  let caught: boolean = false;
  try {
    await bad;
  } catch (e) {
    caught = true;
  }
  ok('抛错的任务本身仍然 reject（调用方能感知）', caught);

  const good: Promise<void> = q2.enqueue(async (): Promise<void> => {
    afterFailedRan = true;
  });
  await good;
  ok('失败之后队列仍可继续（不释放 → 后续永久挂起）', afterFailedRan);

  // 连续失败也不能把队列打死
  const q3: SerialQueue = new SerialQueue();
  for (let i = 0; i < 3; i++) {
    try {
      await q3.enqueue(async (): Promise<void> => {
        throw new Error('boom' + i);
      });
    } catch (e) {
      // 忽略
    }
  }
  let survived: boolean = false;
  await q3.enqueue(async (): Promise<void> => {
    survived = true;
  });
  ok('连续 3 次失败后队列仍可用', survived);

  // ------------------------------------------------ 3) 串行性：同一时刻只有一个 body 在执行
  const q4: SerialQueue = new SerialQueue();
  let inFlight: number = 0;
  let maxInFlight: number = 0;
  const jobs: Promise<void>[] = [];
  for (let i = 0; i < 5; i++) {
    jobs.push(q4.enqueue(async (): Promise<void> => {
      inFlight++;
      if (inFlight > maxInFlight) {
        maxInFlight = inFlight;
      }
      await delay(5);
      inFlight--;
    }));
  }
  await Promise.all(jobs);
  eq('任意时刻最多 1 个 body 在执行（串行保证）', maxInFlight, 1);

  // ------------------------------------------------ 4) 反向保护：嵌套 enqueue 会自锁
  //
  // 这是 `DownloadManager` 文件头那条铁律的机器证明：
  // body 里再 enqueue 一次，外层的 await 在等排队在队尾的自己 → 永远不 resolve。
  const q5: SerialQueue = new SerialQueue();
  let nestedCompleted: boolean = false;
  const nested: Promise<void> = q5.enqueue(async (): Promise<void> => {
    await q5.enqueue(async (): Promise<void> => {
      nestedCompleted = true;
    });
  });
  // 给足时间：如果没自锁，200ms 足够完成
  await Promise.race([nested, delay(200)]);
  ok('嵌套 enqueue 不会在 200ms 内完成（证明会自锁，禁止这么写）', !nestedCompleted);

  // drain() 对未自锁的队列可用
  const q6: SerialQueue = new SerialQueue();
  let drained: boolean = false;
  q6.enqueue(async (): Promise<void> => {
    await delay(10);
    drained = true;
  });
  await q6.drain();
  ok('drain() 在队列排空后 resolve', drained);

  // ------------------------------------------------ 汇总
  if (fails.length > 0) {
    console.error(`\n✗ ${fails.length} 条失败 / ${pass + fails.length} 条断言`);
    for (const f of fails) {
      console.error('  - ' + f);
    }
    throw new Error('serial queue test failed');
  }
  console.log(`✓ serial-queue: ${pass} 条断言全部通过`);
}

main().catch((e: Error): void => {
  console.error('✗ serial-queue 异常: ' + e.message);
  throw e;
});
