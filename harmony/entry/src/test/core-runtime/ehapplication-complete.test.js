// EhApplication 补全段 + Settings 新增 getter 断言
global.Observed = (target) => target;
const path = require('path');
const OUT = process.argv[2] || path.join(process.env.TEMP, 'tscheck', 'out11');
const { EhApplication } = require(path.join(OUT, 'ehviewer', 'EhApplication.js'));
const { Settings } = require(path.join(OUT, 'ehviewer', 'Settings.js'));
const { AppConfig } = require(path.join(OUT, 'ehviewer', 'AppConfig.js'));
const { OhosNetworkMonitor, OhosNetworkBackend } = require(path.join(OUT, 'ehviewer', 'OhosNetworkMonitor.js'));
const { Network } = require(path.join(OUT, 'network', 'Network.js'));
const { EhProxySelector } = require(path.join(OUT, 'ehviewer', 'EhProxySelector.js'));

let fail = 0;
const eq = (a, b, label) => {
  const A = JSON.stringify(a), B = JSON.stringify(b);
  if (A === B) console.log('  PASS  ' + label);
  else { fail++; console.log('  FAIL  ' + label + '\n    实际: ' + A + '\n    期望: ' + B); }
};

(async () => {
  // ── getMemoryCacheMaxSize：min(20MB, appMaxMemory) ──
  eq(EhApplication.getMemoryCacheMaxSize(500 * 1024 * 1024), 20 * 1024 * 1024,
    'appMaxMemory=500MB → 上限封顶 20MB');
  eq(EhApplication.getMemoryCacheMaxSize(8 * 1024 * 1024), 8 * 1024 * 1024,
    'appMaxMemory=8MB → 取实际值 8MB（不受封顶影响）');
  eq(EhApplication.getMemoryCacheMaxSize(20 * 1024 * 1024), 20 * 1024 * 1024, 'appMaxMemory=20MB → 正好等于封顶');

  // ── 常量（上游真值）──
  eq(EhApplication.CONACO_DISK_CACHE_MAX_SIZE, 320 * 1024 * 1024, 'Conaco 磁盘缓存 320MB');
  eq(EhApplication.CONACO_DISK_CACHE_DIR_NAME, 'thumb', 'Conaco 磁盘缓存目录名 thumb');
  eq(EhApplication.OKHTTP_CACHE_DIR_NAME, 'http_cache', 'OkHttp 缓存目录名 http_cache');
  eq(EhApplication.OKHTTP_CACHE_MAX_SIZE, 50 * 1024 * 1024, 'OkHttp 缓存 50MB');
  eq(EhApplication.GUIDE_GALLERY_VERSION_CODE, 52, '引导阈值硬编码 52');
  eq(EhApplication.BETA, false, 'BETA = false');

  // ── getDeveloperEmail：防爬写法还原 ──
  eq(EhApplication.getDeveloperEmail(), 'xiaojieonly' + String.fromCharCode(64) + 'foxmail.com',
    'getDeveloperEmail 含 @ 字符（上游用 $ 替换防爬）');
  eq(EhApplication.getDeveloperEmail().indexOf('@') > 0, true, '…确实是 @ 而不是 $');

  // ── 图片客户端独立于普通客户端 ──
  const plain = EhApplication.getOkHttpClient(null);
  const img = EhApplication.getImageOkHttpClient(null);
  eq(plain !== img, true, 'getImageOkHttpClient 与 getOkHttpClient 是**不同实例**');
  eq(EhApplication.getImageOkHttpClient(null) === img, true, '…但各自是单例（第二次调用返回同一实例）');

  // ── clearTempDir：内外部都清，只有外部补 .nomedia ──
  AppConfig.initialize({ filesDir: '/tmp/fake-files', cacheDir: '/tmp/fake-cache' });
  const calls = [];
  await EhApplication.clearTempDir(async (d) => { calls.push('del:' + d); },
    async (d) => { calls.push('nomedia:' + d); });
  eq(calls.filter((c) => c.startsWith('del:')).length >= 1, true, 'clearTempDir 至少清一个临时目录');
  const nomediaCalls = calls.filter((c) => c.startsWith('nomedia:'));
  eq(nomediaCalls.length <= 1, true, '.nomedia 只对外部临时目录补（最多 1 次）');

  // ── update：版本 < 52 → putGuideGallery(true) ──
  Settings.putGuideGallery(false);
  EhApplication.update(51);
  eq(Settings.getGuideGallery(), true, 'versionCode=51 < 52 → 引导置 true');
  Settings.putGuideGallery(false);
  EhApplication.update(52);
  eq(Settings.getGuideGallery(), false, 'versionCode=52 → 不改（边界：不 < 52）');
  Settings.putGuideGallery(false);
  EhApplication.update(53);
  eq(Settings.getGuideGallery(), false, 'versionCode=53 → 不改');

  // ── 用户标签列表：纯内存 ──
  EhApplication.saveUserTagList({ tags: [1] });
  eq(EhApplication.getUserTagList() !== null, true, 'saveUserTagList 后可取回');
  EhApplication.saveUserTagList(null);
  eq(EhApplication.getUserTagList(), null, 'saveUserTagList(null) → 清空');

  // ── showEventPane 两道守卫顺序 ──
  eq(EhApplication.shouldShowEventPane(null), false, 'html=null → 不显示');
  Settings.setKeyShowEhEvents(false);
  eq(EhApplication.shouldShowEventPane('<p>x</p>'), false, '开关关闭 → 不显示（即使 html 非空）');
  Settings.setKeyShowEhEvents(true);
  Settings.setLoginProvider(() => true);
  eq(EhApplication.shouldShowEventPane('<p>x</p>'), true, '开关开启 + 已登录 + html 非空 → 显示');

  // ── getShowEhEvents：短路求值（开关关时不查登录态）──
  Settings.setKeyShowEhEvents(false);
  let loginQueried = false;
  eq(Settings.getShowEhEvents(() => { loginQueried = true; return true; }), false,
    'getShowEhEvents：开关关闭 → false');
  eq(loginQueried, false, '…且**没有查询登录态**（&& 短路，上游求值顺序）');
  Settings.setKeyShowEhEvents(true);
  eq(Settings.getShowEhEvents(() => false), false, '开关开 + 未登录 → false');
  eq(Settings.getShowEhEvents(() => true), true, '开关开 + 已登录 → true');

  // ── OhosNetworkMonitor VPN 自动避让 + OhosNetworkBackend ──
  const savedProxyType = Settings.isAttached() ? Settings.getProxyType() : Settings.DEFAULT_PROXY_TYPE;
  try {
    OhosNetworkMonitor.setVpnActiveOverrideForTest(true);
    Settings.putProxyType(EhProxySelector.TYPE_SYSTEM);
    eq(OhosNetworkMonitor.shouldBypassBuiltInRouting(), true, 'VPN 活跃 + TYPE_SYSTEM → 旁路内置 Hosts/DF/DoH');
    Settings.putProxyType(EhProxySelector.TYPE_DIRECT);
    eq(OhosNetworkMonitor.shouldBypassBuiltInRouting(), true, 'VPN 活跃 + TYPE_DIRECT → 旁路内置 Hosts/DF/DoH');
    Settings.putProxyType(EhProxySelector.TYPE_HTTP);
    eq(OhosNetworkMonitor.shouldBypassBuiltInRouting(), false, 'VPN 活跃 + TYPE_HTTP → 不旁路（遵循手动 HTTP 代理）');
    Settings.putProxyType(EhProxySelector.TYPE_SOCKS);
    eq(OhosNetworkMonitor.shouldBypassBuiltInRouting(), false, 'VPN 活跃 + TYPE_SOCKS → 不旁路（遵循手动 SOCKS 代理）');
    eq(new OhosNetworkBackend().getActiveNetworkType(), Network.TYPE_VPN, 'VPN 活跃 → NetworkBackend 返回 TYPE_VPN');

    OhosNetworkMonitor.setVpnActiveOverrideForTest(false);
    Settings.putProxyType(EhProxySelector.TYPE_SYSTEM);
    eq(OhosNetworkMonitor.shouldBypassBuiltInRouting(), false, '无 VPN + TYPE_SYSTEM → 不旁路内置 Hosts/DF/DoH');
  } finally {
    OhosNetworkMonitor.setVpnActiveOverrideForTest(null);
    Settings.putProxyType(savedProxyType);
  }

  console.log('\n' + (fail === 0 ? 'ALL PASS' : fail + ' FAILED'));
  process.exit(fail === 0 ? 0 : 1);
})();
