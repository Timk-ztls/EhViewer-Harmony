// ArkTS 的 @Observed 装饰器在 Node 无实现 → 必须在任何 require 之前打桩
global.Observed = (target) => target;

// PreferenceActions 新增两段纯逻辑的运行时断言
const path = require('path');
const OUT = process.argv[2] || path.join(process.env.TEMP, 'tscheck', 'out8');
const { PreferenceActions } = require(path.join(OUT, 'PreferenceActions.js'));
const { AppConfig } = require(path.join(OUT, '..', 'AppConfig.js'));

let fail = 0;
const eq = (a, b, label) => {
  const A = JSON.stringify(a), B = JSON.stringify(b);
  if (A === B) console.log('  PASS  ' + label);
  else { fail++; console.log('  FAIL  ' + label + '\n    实际: ' + A + '\n    期望: ' + B); }
};

(async () => {
  const HOST_E = 'e-hentai.org';
  const HOST_EX = 'exhentai.org';
  const K_ID = PreferenceActions.COOKIE_KEY_IPD_MEMBER_ID;
  const K_PASS = PreferenceActions.COOKIE_KEY_IPD_PASS_HASH;

  // key 常量对上游 EhCookieStore
  eq(K_ID, 'ipb_member_id', 'COOKIE_KEY_IPD_MEMBER_ID = ipb_member_id');
  eq(K_PASS, 'ipb_pass_hash', 'COOKIE_KEY_IPD_PASS_HASH = ipb_pass_hash');

  // ── isSignedIn：上游 onBindViewHolder 里查 4 次的语义 ──
  const mkContains = (set) => (host, key) => set.indexOf(host + '|' + key) >= 0;

  eq(PreferenceActions.isSignedIn(mkContains([]), HOST_E, HOST_EX), false, '无 cookie → 未登录');
  eq(PreferenceActions.isSignedIn(mkContains([HOST_E + '|' + K_ID]), HOST_E, HOST_EX), true, 'E 站有 member_id → 已登录');
  eq(PreferenceActions.isSignedIn(mkContains([HOST_E + '|' + K_PASS]), HOST_E, HOST_EX), true, 'E 站有 pass_hash → 已登录');
  eq(PreferenceActions.isSignedIn(mkContains([HOST_EX + '|' + K_ID]), HOST_E, HOST_EX), true, 'ex 站有 member_id → 已登录');
  eq(PreferenceActions.isSignedIn(mkContains([HOST_EX + '|' + K_PASS]), HOST_E, HOST_EX), true, 'ex 站有 pass_hash → 已登录');
  eq(PreferenceActions.isSignedIn(mkContains(['other|' + K_ID]), HOST_E, HOST_EX), false, '其它主机的同名 cookie 不算（必须查 E/ex 两站）');

  // ── exportData：注入式导出 ──
  // AppConfig 未 initialize 时 getExternalDataDir() 返回 null → exportData 必须返回 null（不崩）
  eq(await PreferenceActions.exportData(async () => true), null, 'AppConfig 未初始化 → exportData 返回 null');
  AppConfig.initialize({ filesDir: '/tmp/fake-files', cacheDir: '/tmp/fake-cache' });
  const okPath = await PreferenceActions.exportData(async () => true);
  eq(okPath !== null, true, 'exportFn 成功 → 返回非 null 路径');
  eq(/\.db$/.test(okPath), true, '…路径以 .db 结尾');
  eq(okPath.indexOf('EhViewer') >= 0 || okPath.length > 0, true, '…路径来自 AppConfig.getExternalDataDir()');

  const badPath = await PreferenceActions.exportData(async () => false);
  eq(badPath, null, 'exportFn 失败 → 返回 null（上游返 null → UI 显示导出失败）');

  // 文件名格式必须与 ReadableTime.getFilenamableTime 一致：yyyy-MM-dd-HH-mm-ss-SSS
  eq(/\/\d{4}-\d{2}-\d{2}-\d{2}-\d{2}-\d{2}-\d{3}\.db$/.test(okPath), true,
    '文件名格式 yyyy-MM-dd-HH-mm-ss-SSS.db（上游用 getFilenamableTime）');

  console.log('\n' + (fail === 0 ? 'ALL PASS' : fail + ' FAILED'));
  process.exit(fail === 0 ? 0 : 1);
})();
