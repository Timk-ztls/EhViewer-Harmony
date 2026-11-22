// ConacoTask 的**纯逻辑**断言（不触网、不落盘：useDiskCache=false && useNetwork=false 走全失败分支）
const path = require('path');
const OUT = process.argv[2] || path.join(process.env.TEMP, 'tscheck', 'out2', 'conaco');
const { ConacoTask, Builder, ArrayBufferInputStreamLike, FileInputStreamLike } = require(path.join(OUT, 'ConacoTask.js'));
const { IOUtils } = require(path.join(OUT, '..', 'lib', 'yorozuya', 'IOUtils.js'));
const { CacheOutputStreamPipe } = require(path.join(OUT, '..', 'beerbelly', 'SimpleDiskCache.js'));
const { IoThreadPoolExecutor } = require(path.join(OUT, '..', 'util', 'IoThreadPoolExecutor.js'));
const { ResponseBuilder, Protocol } = require(path.join(OUT, '..', 'okhttp', 'Response.js'));
const { ResponseBody } = require(path.join(OUT, '..', 'okhttp', 'ResponseBody.js'));
const { RequestBuilder } = require(path.join(OUT, '..', 'okhttp', 'Request.js'));
const fsModule = require(require.resolve('@ohos.file.fs', { paths: [OUT, process.cwd()] }));

let fail = 0;
const eq = (a, b, label) => {
  const A = JSON.stringify(a), B = JSON.stringify(b);
  if (A === B) console.log('  PASS  ' + label);
  else { fail++; console.log('  FAIL  ' + label + '\n    实际: ' + A + '\n    期望: ' + B); }
};
const throws = (fn, label, expect) => {
  try { fn(); fail++; console.log('  FAIL  ' + label + '（未抛错）'); }
  catch (e) {
    const ok = expect === undefined || String(e.message).indexOf(expect) >= 0;
    if (ok) console.log('  PASS  ' + label + ' → "' + e.message + '"');
    else { fail++; console.log('  FAIL  ' + label + ' → 错误消息不含 "' + expect + '"，实际 "' + e.message + '"'); }
  }
};

// 假 Unikery：记录所有回调
class FakeUnikery {
  constructor(id) { this.id = id; this.calls = []; }
  getTaskId() { return this.id; }
  setTaskId(v) { this.id = v; }
  onMiss(s) { this.calls.push('miss:' + s); }
  onRequest() { this.calls.push('request'); }
  onWait() { this.calls.push('wait'); }
  onProgress() { this.calls.push('progress'); }
  onGetValue(v, s) { this.calls.push('get:' + s); return true; }
  onFailure() { this.calls.push('failure'); }
  onCancel() { this.calls.push('cancel'); }
}
const fakeHelper = {
  decode() { return null; }, sizeOf() { return 0; }, useMemoryCache() { return false; },
  onAddToMemoryCache() {}, onRemoveFromMemoryCache() {},
};
const fakeCache = { getFromDisk() { return null; }, getFromDiskWithFlag() { return null; },
  putToMemory() {}, removeFromDisk() {}, getDiskCache() { return null; }, getFromMemory() { return null; } };
const fakeExec = { execute(fn) { fn(); } };

const mkBuilder = (unikery) => new Builder()
  .setId(1).setKey('k').setUnikery(unikery)
  .setHelper(fakeHelper).setCache(fakeCache).setOkHttpClient({})
  .setDiskExecutor(fakeExec).setNetworkExecutor(fakeExec)
  .setUseDiskCache(false).setUseNetwork(false);

// 1) Builder 默认值（上游 useMemoryCache/useDiskCache/useNetwork = true，hardware = true）
const bDef = new Builder();
eq(bDef.mUseMemoryCache, true, 'Builder 默认 useMemoryCache = true');
eq(bDef.mUseDiskCache, true, 'Builder 默认 useDiskCache = true');
eq(bDef.mUseNetwork, true, 'Builder 默认 useNetwork = true');
eq(bDef.hardware, true, 'Builder 默认 hardware = true');
eq(bDef.mId, 0, 'Builder 默认 id = 0');

// 2) Builder.isValid() 与构造期 require 的缺失校验
throws(() => new Builder().isValid(), 'isValid 缺 unikery → 抛可诊断错误', 'unikery is required');
throws(() => new Builder().setUnikery(new FakeUnikery(1)).isValid(), 'isValid 缺 helper → 抛', 'helper is required');
throws(() => new Builder().build(), 'build 缺必填项 → 抛（不是静默 NPE）', 'is required');

// 3) getKey 透传
eq(mkBuilder(new FakeUnikery(1)).build().getKey(), 'k', 'getKey 返回 Builder 设置的 key');

// 4) start()：无 disk/network 时走 onMiss(DISK)+onMiss(NETWORK)+onFailure，并触发 finish 回调
let finished = null;
const u = new FakeUnikery(1);
const t = mkBuilder(u).setConaco((task) => { finished = task; }).build();
t.start();
eq(u.calls, ['miss:1', 'miss:2', 'failure'], 'start() 无缓存无网络 → miss(DISK=1) / miss(NETWORK=2) / failure');
eq(finished === t, true, 'start() 结束触发 Conaco.finishConacoTask 回调');

// 5) 差异 2c：clearUnikery() 后任务自行停止（不再回调 Unikery）
const u2 = new FakeUnikery(1);
let finished2 = false;
const t2 = mkBuilder(u2).setConaco(() => { finished2 = true; }).build();
t2.clearUnikery();
t2.start();
eq(u2.calls, [], 'clearUnikery() 后 start() 不再回调 Unikery（缓解条件生效）');
// 与上游一致：onFinish() 在 !mStop 时必定回调 finishConacoTask，**即使 unikery 已为 null**
eq(finished2, true, '…但 mStop=false 时 onFinish 仍回调 finishConacoTask（上游语义）');

// 6) stop()：置取消 + onCancel + 清 unikery
const u3 = new FakeUnikery(1);
const t3 = mkBuilder(u3).build();
t3.stop();
eq(u3.calls, ['cancel'], 'stop() 触发 onCancel');
eq(t3.getUnikery(), null, 'stop() 立即 clearUnikery（差异 2b）');
t3.start();
eq(u3.calls, ['cancel'], 'stop() 后 start() 不做事（mStop 短路）');

// 7) P0 #1 (F-7)：ArrayBufferInputStreamLike / FileInputStreamLike EOF 返回 -1 (IOUtils.EOF)，不死循环
{
  const data = new Uint8Array([10, 20, 30, 40, 50]).buffer;
  const ais = new ArrayBufferInputStreamLike(data);
  const outChunks = [];
  const copied = IOUtils.copy(ais, {
    write(buf, off, len) {
      outChunks.push(...Array.from(new Uint8Array(buf, off, len)));
    },
  });
  eq(copied, 5, 'P0 #1: IOUtils.copy(ArrayBufferInputStreamLike) 正常终止且拷贝 5 字节');
  eq(outChunks, [10, 20, 30, 40, 50], 'P0 #1: 拷贝内容一致');
  eq(ais.read(new ArrayBuffer(4)), IOUtils.EOF, 'P0 #1: ArrayBufferInputStreamLike 再次读返回 IOUtils.EOF (-1)');

  const origReadSync = fsModule.readSync;
  const origCloseSync = fsModule.closeSync;
  let readCallCount = 0;
  fsModule.readSync = (fd, buf) => {
    readCallCount++;
    if (readCallCount === 1) {
      new Uint8Array(buf).set([7, 8, 9]);
      return 3;
    }
    if (readCallCount === 2) {
      return 0; // OHOS EOF 返回 0
    }
    throw new Error('read failure');
  };
  fsModule.closeSync = () => {};
  try {
    const fis = new FileInputStreamLike({ fd: 99, path: '/tmp/fake' });
    const fisOut = [];
    const fisTotal = IOUtils.copy(fis, {
      write(buf, off, len) {
        fisOut.push(...Array.from(new Uint8Array(buf, off, len)));
      },
    });
    eq(fisTotal, 3, 'P0 #1: IOUtils.copy(FileInputStreamLike) 在 readSync=0 时终止（不死循环）');
    eq(fisOut, [7, 8, 9], 'P0 #1: FileInputStreamLike 读出字节一致');
    eq(fis.read(new ArrayBuffer(4)), IOUtils.EOF, 'P0 #1: readSync 抛错也返回 IOUtils.EOF (-1)');
    fis.close();
    eq(fis.read(new ArrayBuffer(4)), IOUtils.EOF, 'P0 #1: close 后 read 返回 IOUtils.EOF (-1)');
  } finally {
    fsModule.readSync = origReadSync;
    fsModule.closeSync = origCloseSync;
  }
}

// 8) P1 #7 (F-1)：onDiskLoadPostExecute 当 mUseNetwork=false 时触发 onMiss(DISK) + onFailure
{
  const uNoNet = new FakeUnikery(10);
  let finishedNoNet = false;
  const tNoNet = new Builder()
    .setId(10).setKey('k_nonet').setUnikery(uNoNet)
    .setHelper(fakeHelper).setCache(fakeCache).setOkHttpClient({})
    .setDiskExecutor(fakeExec).setNetworkExecutor(fakeExec)
    .setUseDiskCache(true).setUseNetwork(false)
    .setConaco(() => { finishedNoNet = true; })
    .build();
  tNoNet.start();
  eq(uNoNet.calls, ['miss:1', 'failure'], 'P1 #7: disk miss 且 useNetwork=false → onMiss(1) + onFailure()');
  eq(finishedNoNet, true, 'P1 #7: useNetwork=false 失败后仍触发 finish 回调');
}

// 9) P1 #5 & #6 异步回归（Response 关闭、Concurrency=3 限流、isNotNecessary 中止缓存写不删旧缓存）
(async () => {
  // 9a) IoThreadPoolExecutor(3) 并发上限确实限制同时执行的 fetchAndStore
  let activeCalls = 0;
  let maxConcurrent = 0;
  const resolvers = [];
  const pool = new IoThreadPoolExecutor(3);
  const deferredClient = {
    newCall(req) {
      return {
        execute() {
          activeCalls++;
          if (activeCalls > maxConcurrent) maxConcurrent = activeCalls;
          return new Promise((resolve) => {
            resolvers.push(() => {
              activeCalls--;
              const bodyBytes = new Uint8Array([1, 2, 3, 4]).buffer;
              const resp = new ResponseBuilder()
                .request(req).protocol(Protocol.HTTP_1_1).code(200).message('OK')
                .body(new ResponseBody(null, bodyBytes))
                .build();
              resolve(resp);
            });
          });
        },
        cancel() {},
      };
    },
  };

  const tasks = [];
  for (let i = 1; i <= 5; i++) {
    const uk = new FakeUnikery(i);
    const task = new Builder()
      .setId(i).setKey('k_' + i).setUrl('https://example.invalid/' + i).setUnikery(uk)
      .setHelper(fakeHelper).setCache(fakeCache).setOkHttpClient(deferredClient)
      .setDiskExecutor(fakeExec).setNetworkExecutor(pool)
      .setUseDiskCache(false).setUseNetwork(true)
      .build();
    tasks.push(task);
    task.start();
  }
  await Promise.resolve();
  await Promise.resolve();
  eq(maxConcurrent, 3, 'P1 #6: IoThreadPoolExecutor(3) 真实限制同时并发 fetchAndStore 不超过 3');
  eq(resolvers.length, 3, 'P1 #6: 仅前 3 个网络请求已发起，后 2 个排队等待');

  // 逐个放行所有 5 个请求
  while (resolvers.length > 0) {
    const r = resolvers.shift();
    r();
    await new Promise((res) => setTimeout(res, 2));
  }
  await new Promise((res) => setTimeout(res, 10));
  eq(activeCalls, 0, 'P1 #6: 所有排队网络任务全部执行结束');

  // 9b) Response.close() 在 isNotNecessary() / putToDataContainer 失败路径也会被调用
  let bodyCloseCalls = 0;
  const mkRespWithTrackedClose = (req, payload) => {
    const body = new ResponseBody(null, payload);
    const origClose = body.close.bind(body);
    body.close = () => { bodyCloseCalls++; origClose(); };
    return new ResponseBuilder()
      .request(req).protocol(Protocol.HTTP_1_1).code(200).message('OK').body(body).build();
  };

  const ukCancelled = new FakeUnikery(20);
  const cancelClient = {
    newCall(req) {
      return {
        async execute() {
          ukCancelled.setTaskId(999); // 请求返回时任务已过时（isNotNecessary = true）
          return mkRespWithTrackedClose(req, new Uint8Array([1, 2]).buffer);
        },
        cancel() {},
      };
    },
  };
  await new Promise((resolve) => {
    const tc = new Builder()
      .setId(20).setKey('k_cancel').setUrl('https://example.invalid/cancel').setUnikery(ukCancelled)
      .setHelper(fakeHelper).setCache(fakeCache).setOkHttpClient(cancelClient)
      .setDiskExecutor(fakeExec).setNetworkExecutor(fakeExec)
      .setUseDiskCache(false).setUseNetwork(true)
      .setConaco(() => resolve())
      .build();
    tc.start();
  });
  eq(bodyCloseCalls, 1, 'P1 #6: isNotNecessary 早退路径也调用 Response.close()');

  // 9c) P1 #5: putToDiskCache 中途 isNotNecessary() → close os + abort CacheOutputStreamPipe + release + 不删除既有有效缓存
  let events = [];
  let removeFromDiskCalls = 0;
  const fakeEditor = {
    newOutputStream() { return { write() {}, close() { events.push('writer.close'); } }; },
    commit() { events.push('editor.commit'); },
    abort() { events.push('editor.abort'); },
  };
  const mockSimpleCache = {
    obtainLock() { return { tag: 'lock' }; },
    releaseLock() { events.push('pipe.release'); },
    diskCacheOrNull() { return { edit() { return fakeEditor; } }; },
  };
  const pipe = new CacheOutputStreamPipe(mockSimpleCache, 'hash_abort');
  const cacheWithPipe = {
    getFromDisk() { return null; },
    getFromDiskWithFlag() { return null; },
    putToMemory() {},
    removeFromDisk() { removeFromDiskCalls++; },
    getDiskCache() {
      return {
        getOutputStreamPipe() { return pipe; },
      };
    },
    getFromMemory() { return null; },
  };
  const ukMidCancel = new FakeUnikery(30);
  let progressTriggered = false;
  ukMidCancel.onProgress = () => {
    progressTriggered = true;
    ukMidCancel.setTaskId(999); // 第一块 4KB 写完回调进度时使任务失效
  };
  const bigClient = {
    newCall(req) {
      return {
        async execute() {
          return mkRespWithTrackedClose(req, new Uint8Array(8192).buffer);
        },
        cancel() {},
      };
    },
  };
  await new Promise((resolve) => {
    const tMid = new Builder()
      .setId(30).setKey('k_mid_cancel').setUrl('https://example.invalid/big').setUnikery(ukMidCancel)
      .setHelper(fakeHelper).setCache(cacheWithPipe).setOkHttpClient(bigClient)
      .setDiskExecutor(fakeExec).setNetworkExecutor(fakeExec)
      .setUseDiskCache(false).setUseNetwork(true)
      .setConaco(() => resolve())
      .build();
    tMid.start();
  });
  eq(progressTriggered, true, 'P1 #5: 大于 4KB 响应触发了 notifyProgress');
  eq(events.includes('writer.close'), true, 'P1 #5: putToDiskCache 中途失效时关闭了 writer/os');
  eq(events.includes('editor.abort'), true, 'P1 #5: putToDiskCache 中途失效时调用了 editor.abort()');
  eq(events.includes('editor.commit'), false, 'P1 #5: 未调用 editor.commit()（不覆盖已有有效缓存）');
  eq(events.includes('pipe.release'), true, 'P1 #5: 释放了 pipe 锁');
  eq(removeFromDiskCalls, 0, 'P1 #5: 任务失效中止时未误调用 removeFromDisk 删除旧缓存');

  console.log('\n' + (fail === 0 ? 'ALL PASS' : fail + ' FAILED'));
  process.exit(fail === 0 ? 0 : 1);
})();
