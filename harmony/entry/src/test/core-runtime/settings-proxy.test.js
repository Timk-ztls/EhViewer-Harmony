// Settings 代理访问器 + EhProxySelector + OkHttpEhProxySelector + PreferenceActions 接线
global.Observed = (target) => target;
const path = require('path');
const OUT = process.argv[2] || path.join(process.env.TEMP, 'tscheck', 'out11');
const { Settings } = require(path.join(OUT, 'ehviewer', 'Settings.js'));
const { EhProxySelector, OkHttpEhProxySelector, ProxyRouteKind, ProxyType, SystemProxyConfig } =
  require(path.join(OUT, 'ehviewer', 'EhProxySelector.js'));
const { PreferenceActions } = require(path.join(OUT, 'ehviewer', 'preference', 'PreferenceActions.js'));
const { HttpUrl } = require(path.join(OUT, 'okhttp', 'HttpUrl.js'));
const { ProxyType: OkProxyType } = require(path.join(OUT, 'okhttp', 'ProxySelector.js'));

let fail = 0;
const eq = (a, b, label) => {
  const A = JSON.stringify(a), B = JSON.stringify(b);
  if (A === B) console.log('  PASS  ' + label);
  else { fail++; console.log('  FAIL  ' + label + '\n    实际: ' + A + '\n    期望: ' + B); }
};

(async () => {
  // ── key 与默认值 ──
  eq([Settings.KEY_PROXY_TYPE, Settings.KEY_PROXY_IP, Settings.KEY_PROXY_PORT],
    ['proxy_type', 'proxy_ip', 'proxy_port'], '三个 key 与上游字面量一致');
  eq(Settings.DEFAULT_PROXY_TYPE, 1, '**默认 TYPE_SYSTEM = 1（不是 0=直连）**');
  eq(Settings.DEFAULT_PROXY_IP, null, '默认 IP = null');
  eq(Settings.DEFAULT_PROXY_PORT, -1, '**默认端口 = -1（"未配置"哨兵）**');

  eq(Settings.getProxyType(), ProxyType.TYPE_SYSTEM, '未写入 → getProxyType() === SYSTEM');
  eq(Settings.getProxyIp(), null, '未写入 → getProxyIp() === null');
  eq(Settings.getProxyPort(), -1, '未写入 → getProxyPort() === -1');

  // ── PreferenceActions 默认值与接线 ──
  eq(PreferenceActions.DEFAULT_PROXY_TYPE, 1, 'PreferenceActions.DEFAULT_PROXY_TYPE 修复为 1 (TYPE_SYSTEM)');
  eq(PreferenceActions.getProxyType(), ProxyType.TYPE_SYSTEM, 'PreferenceActions.getProxyType() 默认读到 SYSTEM(1)');
  PreferenceActions.putDefaultCategories(0x21);
  eq(Settings.getDefaultCategories(), 0x21, 'PreferenceActions.putDefaultCategories 写入 Settings');
  eq(Settings.getEhConfig().defaultCategories, 0x21, '…且同步 sEhConfig');
  PreferenceActions.putExcludedTagNamespaces(0x05);
  eq(Settings.getExcludedTagNamespaces(), 0x05, 'PreferenceActions.putExcludedTagNamespaces 写入 Settings');
  eq(Settings.getEhConfig().excludedNamespaces, 0x05, '…且同步 sEhConfig');

  // 写读往返
  Settings.putProxyType(ProxyType.TYPE_SOCKS);
  eq(Settings.getProxyType(), ProxyType.TYPE_SOCKS, 'putProxyType(SOCKS) → 读回 3');
  Settings.putProxyIp('192.0.2.10');
  eq(Settings.getProxyIp(), '192.0.2.10', 'putProxyIp → 读回');
  Settings.putProxyPort(1080);
  eq(Settings.getProxyPort(), 1080, 'putProxyPort(1080) → 读回 1080');
  Settings.putProxyIp(null);
  eq(Settings.getProxyIp(), null, 'putProxyIp(null) → 读回 null');

  // ── 接线：defaultProxySettings() 读的就是 Settings ──
  {
    const ps = EhProxySelector.defaultProxySettings();
    eq(typeof ps.getProxyType === 'function', true, 'defaultProxySettings() 返回实现（有 getProxyType）');

    Settings.putProxyType(ProxyType.TYPE_SOCKS);
    Settings.putProxyIp('192.0.2.10');
    Settings.putProxyPort(1080);
    const r = EhProxySelector.select(ps, () => { throw new Error('不应走系统代理'); });
    eq([r.kind, r.host, r.port], [ProxyRouteKind.SOCKS, '192.0.2.10', 1080],
      '**接线生效：Settings 里配的 SOCKS 代理被 select 用上**');

    Settings.putProxyType(ProxyType.TYPE_DIRECT);
    eq(EhProxySelector.select(ps, () => { throw new Error('直连不应走系统代理'); }).kind,
      ProxyRouteKind.NO_PROXY, 'DIRECT → NO_PROXY');

    Settings.putProxyType(ProxyType.TYPE_SYSTEM);
    let called = false;
    const sys = EhProxySelector.select(ps, () => { called = true; return { kind: ProxyRouteKind.SYSTEM, host: null, port: -1 }; });
    eq([sys.kind, called], [ProxyRouteKind.SYSTEM, true], 'SYSTEM → 走注入的系统代理回调');

    Settings.putProxyType(ProxyType.TYPE_HTTP);
    Settings.putProxyIp('192.0.2.10');
    Settings.putProxyPort(-1);
    eq(EhProxySelector.select(ps, () => ({ kind: ProxyRouteKind.SYSTEM, host: null, port: -1 })).kind,
      ProxyRouteKind.SYSTEM, '**HTTP + 端口 -1（未配置）→ 降级为系统代理**');
  }

  // ── OkHttpEhProxySelector（ProxySelector 子类 + 系统代理异步缓存）──
  {
    const urlEh = HttpUrl.get('https://e-hentai.org/g/1/a/');
    const urlLocal = HttpUrl.get('http://localhost:8080/test');
    const urlExcluded = HttpUrl.get('https://sub.internal.net/api');

    let fetchCalls = 0;
    let resolveFetch;
    const selector = new OkHttpEhProxySelector(undefined, () => {
      fetchCalls++;
      return new Promise((r) => {
        resolveFetch = () => r(new SystemProxyConfig('127.0.0.1', 7890, ['localhost', '.internal.net']));
      });
    });

    // TYPE_HTTP 合法配置 → 同步返回 HTTP Proxy
    Settings.putProxyType(ProxyType.TYPE_HTTP);
    Settings.putProxyIp('192.0.2.20');
    Settings.putProxyPort(8080);
    const pHttp = selector.select(urlEh);
    eq([pHttp.length, pHttp[0].type(), pHttp[0].address(), pHttp[0].port()],
      [1, OkProxyType.HTTP, '192.0.2.20', 8080], 'OkHttpEhProxySelector: HTTP → Proxy(HTTP)');

    // TYPE_DIRECT → DIRECT (explicit NO_PROXY)
    Settings.putProxyType(ProxyType.TYPE_DIRECT);
    const pDirect = selector.select(urlEh);
    eq([pDirect[0].type(), pDirect[0].isNoProxy()], [OkProxyType.DIRECT, true],
      'OkHttpEhProxySelector: DIRECT → Proxy.direct() (isNoProxy=true)');

    // TYPE_SYSTEM → select 同步不阻塞；并发 refreshSystemProxy 去重；完成后生效且尊重 exclusionList
    Settings.putProxyType(ProxyType.TYPE_SYSTEM);
    const preSelect = selector.select(urlEh);
    eq([preSelect[0].type(), preSelect[0].isNoProxy()], [OkProxyType.DIRECT, false],
      '系统代理未就绪时 select 同步返回 Proxy.system()（isNoProxy=false）');

    const r1 = selector.refreshSystemProxy();
    const r2 = selector.refreshSystemProxy();
    resolveFetch();
    await Promise.all([r1, r2]);
    eq(fetchCalls, 1, 'refreshSystemProxy 并发去重');

    const pSys = selector.select(urlEh);
    eq([pSys[0].type(), pSys[0].address(), pSys[0].port()],
      [OkProxyType.HTTP, '127.0.0.1', 7890], 'OkHttpEhProxySelector: SYSTEM → 命中缓存系统代理');
    const pLocal = selector.select(urlLocal);
    eq([pLocal[0].type(), pLocal[0].isNoProxy()], [OkProxyType.DIRECT, true],
      'exclusionList 精确匹配 localhost → Proxy.direct() (isNoProxy=true)');
    const pExcl = selector.select(urlExcluded);
    eq([pExcl[0].type(), pExcl[0].isNoProxy()], [OkProxyType.DIRECT, true],
      'exclusionList 后缀匹配 .internal.net → Proxy.direct() (isNoProxy=true)');

    // 无自定义 fetcher 时（Node shim 无 getDefaultHttpProxy）安全捕获不崩
    const safeSelector = new OkHttpEhProxySelector(undefined);
    await safeSelector.refreshSystemProxy();
    const pSafe = safeSelector.select(urlEh);
    eq([pSafe[0].type(), pSafe[0].isNoProxy()], [OkProxyType.DIRECT, false],
      'connection.getDefaultHttpProxy 异常/缺失时安全回退 Proxy.system() (isNoProxy=false)');
  }

  console.log('\n' + (fail === 0 ? 'ALL PASS' : fail + ' FAILED'));
  process.exit(fail === 0 ? 0 : 1);
})();
