// EhProxySelector 四种模式与降级 / RecordingApplication 记录与倒序重建 / ImageBitmapHelper 缓存判定
global.Observed = (target) => target;
const path = require('path');
const OUT = process.argv[2] || path.join(process.env.TEMP, 'tscheck', 'out11');
const { EhProxySelector, ProxyRouteKind, ProxyType, ProxyRoute } =
  require(path.join(OUT, 'ehviewer', 'EhProxySelector.js'));
const { RecordingApplication } = require(path.join(OUT, 'content', 'RecordingApplication.js'));
const { ImageBitmapHelper } = require(path.join(OUT, 'ehviewer', 'image', 'ImageBitmapHelper.js'));

let fail = 0;
const eq = (a, b, label) => {
  const A = JSON.stringify(a), B = JSON.stringify(b);
  if (A === B) console.log('  PASS  ' + label);
  else { fail++; console.log('  FAIL  ' + label + '\n    实际: ' + A + '\n    期望: ' + B); }
};

// ══ EhProxySelector ══
const mkSettings = (type, ip, port) => ({
  getProxyType: () => type, getProxyIp: () => ip, getProxyPort: () => port,
});
const sysRoute = () => new ProxyRoute(ProxyRouteKind.SYSTEM, null, -1);

eq(ProxyType.TYPE_DIRECT, 0, 'TYPE_DIRECT = 0');
eq(ProxyType.TYPE_SYSTEM, 1, 'TYPE_SYSTEM = 1');
eq(ProxyType.TYPE_HTTP, 2, 'TYPE_HTTP = 2');
eq(ProxyType.TYPE_SOCKS, 3, 'TYPE_SOCKS = 3');

// delegationOf：DIRECT → NULL / SYSTEM → ALTERNATIVE / HTTP,SOCKS → NONE
eq(EhProxySelector.delegationOf(0), 'NULL', 'DIRECT → delegation 是 NullProxySelector');
eq(EhProxySelector.delegationOf(1), 'ALTERNATIVE', 'SYSTEM → 用系统代理');
eq(EhProxySelector.delegationOf(2), 'NONE', 'HTTP → delegation = null');
eq(EhProxySelector.delegationOf(3), 'NONE', 'SOCKS → delegation = null');
eq(EhProxySelector.delegationOf(99), 'ALTERNATIVE', '**未知类型值 → 系统代理**（上游 switch 的 default 与 TYPE_SYSTEM 共用分支）');

// select：直连
eq(EhProxySelector.select(mkSettings(0, '1.2.3.4', 8080), sysRoute).kind, ProxyRouteKind.NO_PROXY,
  'DIRECT → NO_PROXY（即使填了 ip/port 也不用）');
// 系统
eq(EhProxySelector.select(mkSettings(1, null, -1), sysRoute).kind, ProxyRouteKind.SYSTEM, 'SYSTEM → 系统代理');
// HTTP 合法
{
  const r = EhProxySelector.select(mkSettings(2, '127.0.0.1', 8888), sysRoute);
  eq([r.kind, r.host, r.port], [ProxyRouteKind.HTTP, '127.0.0.1', 8888], 'HTTP + 合法 ip/port → HTTP 代理');
}
// SOCKS 合法
{
  const r = EhProxySelector.select(mkSettings(3, '127.0.0.1', 1080), sysRoute);
  eq([r.kind, r.host, r.port], [ProxyRouteKind.SOCKS, '127.0.0.1', 1080], 'SOCKS + 合法 → SOCKS 代理');
}
// HTTP 但 ip 为空 → 静默降级为系统代理（不报错）
eq(EhProxySelector.select(mkSettings(2, '', 8888), sysRoute).kind, ProxyRouteKind.SYSTEM,
  '**HTTP + ip="" → 静默降级为系统代理**（delegation=null → alternative）');
eq(EhProxySelector.select(mkSettings(2, null, 8888), sysRoute).kind, ProxyRouteKind.SYSTEM,
  'HTTP + ip=null → 降级');
// port 非法 → 降级
eq(EhProxySelector.select(mkSettings(2, '1.2.3.4', -1), sysRoute).kind, ProxyRouteKind.SYSTEM,
  'HTTP + port=-1 → 降级');
eq(EhProxySelector.select(mkSettings(2, '1.2.3.4', 70000), sysRoute).kind, ProxyRouteKind.SYSTEM,
  'HTTP + port=70000（越界）→ 降级');
eq(EhProxySelector.select(mkSettings(2, '1.2.3.4', 0), sysRoute).kind, ProxyRouteKind.HTTP,
  'HTTP + port=0 → **仍用代理**（0 是合法端口，上游 isValidInetPort 允许）');
// connectFailed 只描述
eq(EhProxySelector.describeConnectFailed('https://x/', 'h', 1), 'https://x/ h:1 connect failed',
  'connectFailed 只产出描述串（不改变配置）');

// ══ RecordingApplication ══
{
  class Rec extends RecordingApplication {
    onCreate() {}
  }
  const app = new Rec();
  const order = [];
  app.onActivityCreated('a', () => order.push('a'));
  app.onActivityCreated('b', () => order.push('b'));
  app.onActivityCreated('c', () => order.push('c'));
  eq(app.getKeys(), ['a', 'b', 'c'], '三个页面按注册顺序记录');

  // recreate 倒序
  const recreated = app.recreate();
  eq(recreated, ['c', 'b', 'a'], '**recreate 倒序**（先重建栈顶）');
  eq(order, ['c', 'b', 'a'], '…回调也按倒序触发');

  // destroyed 移除目标
  app.onActivityDestroyed('b');
  eq(app.getKeys(), ['a', 'c'], 'onActivityDestroyed 移除目标');

  // dead 条目被清理
  app.markDead('a');
  eq(app.getKeys(), ['c'], 'markDead 后 getKeys 不再列出');
  eq(app.size(), 2, '…但物理条目还在（等下次 destroyed 清理）');
  app.onActivityDestroyed('c');
  eq(app.size(), 0, '**destroyed 时顺手清理已失效条目**（a 也被清掉）');

  // dead 的条目不参与 recreate
  const app2 = new Rec();
  const hits = [];
  app2.onActivityCreated('x', () => hits.push('x'));
  app2.onActivityCreated('y', () => hits.push('y'));
  app2.markDead('y');
  eq(app2.recreate(), ['x'], 'recreate 跳过已失效条目');
  eq(hits, ['x'], '…只回调存活的');

  // 空列表 recreate 不崩
  const app3 = new Rec();
  eq(app3.recreate(), [], '空列表 recreate → []');
}

// ══ ImageBitmapHelper ══
const mkImage = (w, h) => {
  const st = { obtains: 0, releases: 0 };
  return {
    st,
    getWidth: () => w, getHeight: () => h,
    obtain: () => { st.obtains++; }, release: () => { st.releases++; },
  };
};
{
  // sizeOf = w*h*4
  eq(ImageBitmapHelper.sizeOf(mkImage(10, 20)), 800, 'sizeOf = 10*20*4 = 800');
  eq(ImageBitmapHelper.sizeOf(mkImage(0, 0)), 0, 'sizeOf 0×0 = 0');

  // useMemoryCache：像素面积 <= 512*512
  eq(ImageBitmapHelper.MAX_CACHE_SIZE, 262144, 'MAX_CACHE_SIZE = 512*512 = 262144');
  eq(ImageBitmapHelper.useMemoryCache(mkImage(512, 512)), true, '512×512（= 上限）→ true');
  eq(ImageBitmapHelper.useMemoryCache(mkImage(513, 512)), false, '513×512（超上限）→ false');
  eq(ImageBitmapHelper.useMemoryCache(mkImage(1, 1)), true, '1×1 → true');
  eq(ImageBitmapHelper.useMemoryCache(null), true, '**value=null → true**（中间态放行）');

  // obtain / release
  {
    const img = mkImage(1, 1);
    ImageBitmapHelper.onAddToMemoryCache(img);
    eq(img.st.obtains, 1, 'onAddToMemoryCache → obtain() 一次');
    ImageBitmapHelper.onRemoveFromMemoryCache(img);
    eq(img.st.releases, 1, 'onRemoveFromMemoryCache → release() 一次');
  }

  // decode：四步顺序 + finally
  {
    const calls = [];
    const pipe = {
      obtain: () => calls.push('obtain'),
      open: () => { calls.push('open'); return {}; },
      close: () => calls.push('close'),
      release: () => calls.push('release'),
    };
    const img = mkImage(2, 2);
    const out = ImageBitmapHelper.decode(pipe, () => img);
    eq(out === img, true, 'decode 成功 → 返回图像');
    eq(calls, ['obtain', 'open', 'close', 'release'], '**四步顺序 obtain→open→close→release**');
  }
  // decode 失败（解码器返回 null）→ 仍 close/release
  {
    const calls = [];
    const pipe = {
      obtain: () => calls.push('obtain'), open: () => { calls.push('open'); return {}; },
      close: () => calls.push('close'), release: () => calls.push('release'),
    };
    eq(ImageBitmapHelper.decode(pipe, () => null), null, '解码 null → 返回 null');
    eq(calls, ['obtain', 'open', 'close', 'release'], '**失败路径也 close+release**（不泄漏）');
  }
  // open 抛错 → 仍 close/release（finally）
  {
    const calls = [];
    const pipe = {
      obtain: () => calls.push('obtain'),
      open: () => { calls.push('open'); throw new TypeError('not FileInputStream'); },
      close: () => calls.push('close'), release: () => calls.push('release'),
    };
    eq(ImageBitmapHelper.decode(pipe, () => mkImage(1, 1)), null, 'open 抛 TypeError → null');
    eq(calls, ['obtain', 'open', 'close', 'release'], '**open 抛错时 close+release 仍执行**（finally）');
  }
  // decodeImage 抛 RangeError（对应 OOM）→ null 且不向上抛
  {
    const pipe = { obtain: () => {}, open: () => ({}), close: () => {}, release: () => {} };
    eq(ImageBitmapHelper.decode(pipe, () => { const e = new RangeError('OOM'); throw e; }), null,
      'decodeImage 抛 RangeError（对应 OutOfMemoryError）→ null，不向上抛');
  }
}

console.log('\n' + (fail === 0 ? 'ALL PASS' : fail + ' FAILED'));
process.exit(fail === 0 ? 0 : 1);
