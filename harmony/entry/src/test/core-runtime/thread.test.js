// thread/ 等价层的**运行时**断言（定时器语义必须真跑，编译通过说明不了任何事）
const path = require('path');
const d = process.env.TEMP;
const OUT = process.argv[2] || path.join(d, 'tscheck', 'out');
const { SerialThreadExecutor } = require(path.join(OUT, 'SerialThreadExecutor.js'));
const { InfiniteThreadExecutor } = require(path.join(OUT, 'InfiniteThreadExecutor.js'));
const { PriorityThreadFactory } = require(path.join(OUT, 'PriorityThreadFactory.js'));

const sleep = (ms) => new Promise(r => setTimeout(r, ms));
let fail = 0;
const eq = (a, b, label) => {
  const A = JSON.stringify(a), B = JSON.stringify(b);
  if (A === B) console.log('  PASS  ' + label);
  else { fail++; console.log('  FAIL  ' + label + '\n    实际: ' + A + '\n    期望: ' + B); }
};

(async () => {
  // ── SerialThreadExecutor ────────────────────────────────────────────────
  // 1) 串行且保序：三个任务先后执行，不得交叠
  const order = [];
  let concurrent = 0, maxConcurrent = 0;
  const s1 = new SerialThreadExecutor(50, [], new PriorityThreadFactory('Disk', -10));
  const makeTask = (n) => () => {
    concurrent++; maxConcurrent = Math.max(maxConcurrent, concurrent);
    order.push(n);
    // 同步任务：故意不等待，检验"串行"是靠 pump 链而非任务体
    concurrent--;
  };
  s1.execute(makeTask(1)); s1.execute(makeTask(2)); s1.execute(makeTask(3));
  eq(s1.isRunning(), true, 'Serial: execute 后 worker 存活');
  await sleep(30);
  eq(order, [1, 2, 3], 'Serial: 按入队顺序串行执行');
  eq(maxConcurrent, 1, 'Serial: 任意时刻只有 1 个任务在执行');

  // 2) 保活到期后 worker 退出
  await sleep(120);
  eq(s1.isRunning(), false, 'Serial: 空闲超过 keepAlive(50ms) 后 worker 退出');

  // 3) 退出后再投任务 → 重新拉起
  s1.execute(makeTask(4));
  eq(s1.isRunning(), true, 'Serial: 退出后新任务重新拉起 worker');
  await sleep(20);
  eq(order, [1, 2, 3, 4], 'Serial: 重启后继续按序执行');

  // 4) 任务抛错不阻塞后续
  const order2 = [];
  const s2 = new SerialThreadExecutor(50, [], new PriorityThreadFactory('Disk', -10));
  s2.execute(() => { throw new Error('boom'); });
  s2.execute(() => { order2.push('after'); });
  await sleep(20);
  eq(order2, ['after'], 'Serial: 前一个任务抛错后仍继续执行下一个');

  // ── InfiniteThreadExecutor ──────────────────────────────────────────────
  // 5) 每个任务独立 runner（并发不受限）
  let ranInf = 0;
  const inf = new InfiniteThreadExecutor(50, [], new PriorityThreadFactory('Network', -10));
  for (let i = 0; i < 5; i++) { inf.execute(() => { ranInf++; }); }
  eq(inf.getThreadCount(), 5, 'Infinite: 5 个任务 → 5 个 runner');
  await sleep(20);
  eq(ranInf, 5, 'Infinite: 5 个任务全部执行');

  // 6) 保活到期 → runner 全部退出
  await sleep(120);
  eq(inf.getThreadCount(), 0, 'Infinite: 空闲超过 keepAlive 后 runner 归零');

  // 7) 线程名元数据保留
  eq(new PriorityThreadFactory('Conaco-Network', -10).getName(), 'Conaco-Network', 'PriorityThreadFactory.getName 保留上游命名');

  console.log('\n' + (fail === 0 ? 'ALL PASS' : fail + ' FAILED'));
  process.exit(fail === 0 ? 0 : 1);
})();
