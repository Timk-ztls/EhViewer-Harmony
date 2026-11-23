global.Observed = (target) => target;
const path = require('path');

const OUT = process.argv[2] || path.join(process.env.TEMP, 'tscheck', 'out_imghost', 'hippo');
const ohosFs = require(path.resolve(OUT, '..', '..', 'node_modules', '@ohos.file.fs'));
const { DefaultImageRequestHost } = require(path.join(OUT, 'ehviewer', 'image', 'DefaultImageRequestHost.js'));
const {
  ImageRequest,
  LoadImageController,
  LoadImageHostBridge
} = require(path.join(OUT, 'widget', 'LoadImageView.js'));
const { Protocol, Response } = require(path.join(OUT, 'okhttp', 'Response.js'));
const { ResponseBody } = require(path.join(OUT, 'okhttp', 'ResponseBody.js'));
const { Headers } = require(path.join(OUT, 'okhttp', 'Headers.js'));

let pass = 0;
let fail = 0;
const eq = (a, b, label) => {
  const A = JSON.stringify(a), B = JSON.stringify(b);
  if (A === B) { pass++; console.log('  PASS  ' + label); }
  else { fail++; console.log('  FAIL  ' + label + '\n    实际: ' + A + '\n    期望: ' + B); }
};

async function tick() {
  await new Promise((r) => setTimeout(r, 8));
}

function makeTarget(host) {
  const ctrl = new LoadImageController();
  const applied = [];
  let failures = 0;
  ctrl.setRequestHost(host);
  ctrl.onAttached();
  ctrl.attach(new LoadImageHostBridge(
    (src) => applied.push(src),
    () => { failures++; },
    () => {}
  ));
  return { ctrl, applied, getFailures: () => failures };
}

function makeReq(key, url, listIndex) {
  const req = new ImageRequest();
  req.key = key;
  req.url = url;
  req.listIndex = listIndex;
  return req;
}

(async () => {
  if (ohosFs.__reset) ohosFs.__reset();
  const tmpDir = '/tmp/eh_imghost_test';
  const pngBuf = new Uint8Array([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]).buffer;

  try {
    // 1) Cache-Control: no-store 与请求控制
    {
      const seenHeaders = [];
      const seenUrls = [];
      const fakeClient = {
        newCall(req) {
          seenUrls.push(req.url().toString());
          seenHeaders.push(req.header('Cache-Control'));
          return {
            async execute() {
              return new Response(req, Protocol.HTTP_1_1, 200, 'OK',
                new Headers([], []), new ResponseBody(null, pngBuf), null, Date.now());
            }
          };
        }
      };
      const host = new DefaultImageRequestHost(() => fakeClient, () => tmpDir);
      const t = makeTarget(host);
      host.request(t.ctrl, makeReq('k0', 'https://ehgt.org/t0.jpg', 0));
      for (let i = 0; i < 6; i++) await tick();
      eq(seenHeaders, ['no-store'], '缩略图请求显式携带 Cache-Control: no-store 跳过 http_cache 双重写盘');
      eq(t.applied.length, 1, '首个缩略图下载完成并回填视图');
    }

    // 2) target 切换 URL 时撤销旧孤儿任务，不占用并发槽位也不错误回调
    {
      const started = [];
      const resolvers = new Map();
      const fakeClient = {
        newCall(req) {
          const u = req.url().toString();
          started.push(u);
          return {
            execute() {
              return new Promise((resolve) => {
                resolvers.set(u, () => {
                  resolve(new Response(req, Protocol.HTTP_1_1, 200, 'OK',
                    new Headers([], []), new ResponseBody(null, pngBuf), null, Date.now()));
                });
              });
            }
          };
        }
      };
      const host = new DefaultImageRequestHost(() => fakeClient, () => tmpDir);

      // 先占满 6 个并发下载槽位
      const blockers = [];
      for (let i = 0; i < 6; i++) {
        const b = makeTarget(host);
        blockers.push(b);
        host.request(b.ctrl, makeReq(`blk_${i}`, `https://ehgt.org/blk_${i}.jpg`, 0));
      }
      await tick();
      eq(started.length, 6, '前 6 个并发请求立即占满 MAX_CONCURRENT_DOWNLOADS=6');

      // 第 7 个目标先排队请求 orphan_old.jpg，再立刻切换成 replacement_new.jpg
      const orphanTarget = makeTarget(host);
      host.request(orphanTarget.ctrl, makeReq('k_old', 'https://ehgt.org/orphan_old.jpg', 1));
      host.request(orphanTarget.ctrl, makeReq('k_new', 'https://ehgt.org/replacement_new.jpg', 1));

      // 放行前 6 个槽位，排队的应当只有 replacement_new.jpg
      for (const fn of resolvers.values()) fn();
      for (let i = 0; i < 8; i++) await tick();
      const newFn = resolvers.get('https://ehgt.org/replacement_new.jpg');
      if (newFn) newFn();
      for (let i = 0; i < 6; i++) await tick();

      eq(started.indexOf('https://ehgt.org/orphan_old.jpg'), -1,
        '同目标切换 URL 后已取消队列中 orphanedUrl，不再发起多余下载');
      eq(started.indexOf('https://ehgt.org/replacement_new.jpg') >= 0, true,
        '同目标切换 URL 后新 URL 正常完成下载');
    }

    // 3) 可见窗口优先出队（LIFO）于预取队列
    {
      const order = [];
      const pending = new Map();
      const fakeClient = {
        newCall(req) {
          const u = req.url().toString();
          order.push(u);
          return {
            execute() {
              return new Promise((resolve) => {
                pending.set(u, () => {
                  resolve(new Response(req, Protocol.HTTP_1_1, 200, 'OK',
                    new Headers([], []), new ResponseBody(null, pngBuf), null, Date.now()));
                });
              });
            }
          };
        }
      };
      const host = new DefaultImageRequestHost(() => fakeClient, () => tmpDir);
      host.updateVisibleRange(10, 15);

      // 占满 6 个槽位
      for (let i = 0; i < 6; i++) {
        const b = makeTarget(host);
        host.request(b.ctrl, makeReq(`sat_${i}`, `https://ehgt.org/sat_${i}.jpg`, 10));
      }
      await tick();

      // 先入预取区（0..9），再入当前屏幕可见区（10..15）
      const p2 = makeTarget(host);
      const p3 = makeTarget(host);
      const v12 = makeTarget(host);
      const v14 = makeTarget(host);
      host.request(p2.ctrl, makeReq('kp2', 'https://ehgt.org/p2.jpg', 2));
      host.request(p3.ctrl, makeReq('kp3', 'https://ehgt.org/p3.jpg', 3));
      host.request(v12.ctrl, makeReq('kv12', 'https://ehgt.org/v12.jpg', 12));
      host.request(v14.ctrl, makeReq('kv14', 'https://ehgt.org/v14.jpg', 14));

      // 释放前 6 个占位槽位，观察随后出队顺序
      for (const fn of Array.from(pending.values())) fn();
      for (let i = 0; i < 8; i++) await tick();
      for (const fn of Array.from(pending.values())) fn();
      for (let i = 0; i < 8; i++) await tick();

      const afterSat = order.slice(6);
      eq(afterSat.slice(0, 2), ['https://ehgt.org/v14.jpg', 'https://ehgt.org/v12.jpg'],
        'visibleQueue 绝对优先于 prefetchQueue 且 LIFO 先拉最新滚动可见项');
      eq(afterSat.slice(2, 4), ['https://ehgt.org/p3.jpg', 'https://ehgt.org/p2.jpg'],
        'visibleQueue 清空后再处理 prefetchQueue');

      host.resetVisibleRange();
    }
  } finally {
    if (ohosFs.__reset) ohosFs.__reset();
  }

  console.log('\n' + (fail === 0 ? `ALL PASS (${pass} assertions)` : `${fail} FAILED / ${pass} PASSED`));
  process.exit(fail === 0 ? 0 : 1);
})();
