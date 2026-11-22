// EhClient 测试：调度生命周期（不是 dispatch 表）
//
// 三条必须照搬的语义：
//   1. execute 时已 cancel → 直接 onCancel，不跑 dispatcher
//   2. Task.stop() 幂等；stop 之后 setCall() → CancelledException
//   3. onPostExecute：CancelledException → 什么都不做；其它 Error → onFailure；否则 onSuccess

import {
  EhClient, MethodDispatcher, Scheduler, Task, TaskCallback, TaskInterface
} from '../EhClient';
import { EhRequest } from '../EhRequest';
import { CancelledException } from '../exception/MarkerExceptions';

let pass = 0;
let fail = 0;
const failures: string[] = [];

function eq(name: string, actual: unknown, expected: unknown): void {
  const a = JSON.stringify(actual);
  const e = JSON.stringify(expected);
  if (a === e) {
    pass++;
  } else {
    fail++;
    failures.push(`${name}\n    actual  = ${a}\n    expected= ${e}`);
  }
}

function ok(name: string, cond: boolean): void {
  if (cond) {
    pass++;
  } else {
    fail++;
    failures.push(name);
  }
}

/** 手动驱动的 scheduler：把 runnable 攒起来，测试里显式 flush。 */
class ManualScheduler implements Scheduler {
  queued: (() => void)[] = [];

  schedule(runnable: () => void): void {
    this.queued.push(runnable);
  }

  flush(): void {
    const list = this.queued;
    this.queued = [];
    for (const r of list) {
      r();
    }
  }
}

class RecordingCallback implements TaskCallback {
  events: string[] = [];
  lastResult: Object | null = null;
  lastError: Error | null = null;

  onSuccess(result: Object): void {
    this.events.push('success');
    this.lastResult = result;
  }

  onFailure(e: Error): void {
    this.events.push('failure');
    this.lastError = e;
  }

  onCancel(): void {
    this.events.push('cancel');
  }
}

async function tick(): Promise<void> {
  await new Promise<void>((resolve) => {
    setTimeout(resolve, 0);
  });
}

const flushPromises = async (): Promise<void> => {
  await tick();
  await tick();
};

async function main(): Promise<void> {
  // ---------- 1. 正常成功路径（含 args 透传） ----------
  {
    const scheduler = new ManualScheduler();
    const seen: number[] = [];
    let seenArgs: Object[] = [];
    const dispatcher: MethodDispatcher = {
      invoke: async (_task: TaskInterface, method: number, args: Object[]): Promise<Object> => {
        seen.push(method);
        seenArgs = args;
        return 'ok';
      }
    };
    const client = new EhClient(dispatcher, scheduler);
    const cb = new RecordingCallback();
    const req = new EhRequest()
      .setMethod(EhClient.METHOD_GET_GALLERY_LIST)
      .setArgs(['https://e-hentai.org/', 0])
      .setCallback(cb);
    client.execute(req);
    eq('execute 未立即执行（交给 scheduler）', seen.length, 0);
    scheduler.flush();
    await flushPromises();
    eq('dispatcher 收到 method', seen, [EhClient.METHOD_GET_GALLERY_LIST]);
    eq('dispatcher 收到 args', seenArgs, ['https://e-hentai.org/', 0]);
    eq('回调 onSuccess', cb.events, ['success']);
    eq('结果透传', cb.lastResult, 'ok');
    ok('request 已绑定 task', req.getTask() !== null);
  }

  // ---------- 2. 已取消的 request：直接 onCancel，不跑 dispatcher ----------
  {
    const scheduler = new ManualScheduler();
    let called = 0;
    const dispatcher: MethodDispatcher = {
      invoke: async (): Promise<Object> => {
        called++;
        return 'never';
      }
    };
    const client = new EhClient(dispatcher, scheduler);
    const cb = new RecordingCallback();
    const req = new EhRequest().setMethod(EhClient.METHOD_SIGN_IN).setCallback(cb);
    req.cancel();
    client.execute(req);
    scheduler.flush();
    await flushPromises();
    eq('dispatcher 未被调用', called, 0);
    eq('回调 onCancel', cb.events, ['cancel']);
  }

  // ---------- 3. 异常 → onFailure ----------
  {
    const scheduler = new ManualScheduler();
    const dispatcher: MethodDispatcher = {
      invoke: async (): Promise<Object> => {
        throw new Error('network boom');
      }
    };
    const client = new EhClient(dispatcher, scheduler);
    const cb = new RecordingCallback();
    client.execute(new EhRequest().setMethod(EhClient.METHOD_GET_NEWS).setCallback(cb));
    scheduler.flush();
    await flushPromises();
    eq('回调 onFailure', cb.events, ['failure']);
    eq('异常消息透传', (cb.lastError as Error).message, 'network boom');
  }

  // ---------- 4. stop() 幂等 + onCancel 异步派发且只一次 ----------
  {
    const scheduler = new ManualScheduler();
    let invoked = 0;
    const dispatcher: MethodDispatcher = {
      invoke: (): Promise<Object> => {
        invoked++;
        return new Promise<Object>(() => { }); // 永不完成
      }
    };
    const client = new EhClient(dispatcher, scheduler);
    const cb = new RecordingCallback();
    const req = new EhRequest().setMethod(EhClient.METHOD_GET_HOME).setCallback(cb);
    const task = client.execute(req);
    task.stop();
    task.stop();
    eq('stop 不在同步栈重入 onCancel', cb.events, []);
    ok('task.isStop()', task.isStop());
    scheduler.flush();
    await flushPromises();
    eq('stop 两次 flush 后只发一次 onCancel', cb.events, ['cancel']);
    eq('PENDING 时 stop 不再调用 dispatcher', invoked, 0);
  }

  // ---------- 5. stop 之后 setCall → CancelledException ----------
  {
    const scheduler = new ManualScheduler();
    const dispatcher: MethodDispatcher = {
      invoke: (): Promise<Object> => new Promise<Object>(() => { })
    };
    const client = new EhClient(dispatcher, scheduler);
    const task = client.execute(new EhRequest().setMethod(EhClient.METHOD_GET_HOME));
    task.stop();
    let threw = false;
    try {
      task.setCall({});
    } catch (e) {
      threw = e instanceof CancelledException;
    }
    ok('stop 后 setCall 抛 CancelledException', threw);
  }

  // ---------- 6. onPostExecute 收到 CancelledException → 静默 ----------
  {
    const scheduler = new ManualScheduler();
    const dispatcher: MethodDispatcher = {
      invoke: (): Promise<Object> => new Promise<Object>(() => { })
    };
    const client = new EhClient(dispatcher, scheduler);
    const cb = new RecordingCallback();
    const task: Task = client.execute(new EhRequest().setMethod(EhClient.METHOD_GET_HOME).setCallback(cb));
    task.onPostExecute(new CancelledException());
    eq('CancelledException 不触发任何回调', cb.events, []);
  }

  // ---------- 7. METHOD_* 常量与上游一致（含 27/28 的空洞） ----------
  {
    eq('SIGN_IN=0', EhClient.METHOD_SIGN_IN, 0);
    eq('GET_GALLERY_DETAIL=3（2 被跳过）', EhClient.METHOD_GET_GALLERY_DETAIL, 3);
    eq('ARCHIVER=27', EhClient.METHOD_ARCHIVER, 27);
    eq('DOWNLOAD_ARCHIVER=28', EhClient.METHOD_DOWNLOAD_ARCHIVER, 28);
    eq('GET_EDIT_COMMENT=29', EhClient.METHOD_GET_EDIT_COMMENT, 29);
    eq('ADD_TAG=20（19 被跳过）', EhClient.METHOD_ADD_TAG, 20);
    eq('GET_HOME=25 / RESET_LIMIT=26', EhClient.METHOD_GET_HOME + 1, EhClient.METHOD_RESET_LIMIT);
  }
}

main().then((): void => {
  console.log(`\n=== 结果：${pass} passed, ${fail} failed ===`);
  if (fail > 0) {
    for (const f of failures) {
      console.log('  FAIL ' + f);
    }
    throw new Error('EhClient 断言失败：' + fail);
  }
}).catch((e: Error): void => {
  console.log('  FAIL ' + e.message);
  throw e;
});
