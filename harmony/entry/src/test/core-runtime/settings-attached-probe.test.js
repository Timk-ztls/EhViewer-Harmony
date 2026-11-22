// 运行期探针：Settings.isAttached() + attach() 并发去重 / 延后暴露 / 预写保留重放
global.Observed = (target) => target;
const path = require('path');
const OUT = process.argv[2] || path.join(process.env.TEMP, 'tscheck', 'out11');

const prefShimPath = require.resolve(path.join(process.env.TEMP, 'tscheck', 'node_modules', '@ohos.data.preferences'));
const prefMod = require(prefShimPath);
const { Settings } = require(path.join(OUT, 'ehviewer', 'Settings.js'));

let fail = 0;
const eq = (a, b, label) => {
  const A = JSON.stringify(a), B = JSON.stringify(b);
  if (A === B) console.log('  PASS  ' + label);
  else { fail++; console.log('  FAIL  ' + label + '\n    实际: ' + A + '\n    期望: ' + B); }
};

const fakeCtx = { filesDir: '/tmp/files', cacheDir: '/tmp/cache' };

(async () => {
  // ① attach 之前必须为 false —— 且预写入在 attach 前可读
  eq(Settings.isAttached(), false, '**attach 之前 isAttached() === false**');
  Settings.putTheme(Settings.THEME_BLACK); // pre-attach write
  Settings.putProxyIp('10.0.0.1');
  Settings.putProxyIp(null); // pre-attach delete should also survive
  Settings.putArchiverDownloadId(77, 321);

  // ② 拦截 getPreferences：验证并发 attach 去重 + 未完成前绝不提前暴露 sPref/sAttached
  let resolveMainPref;
  let resolveMainAll;
  const openNames = [];
  let mainFlushed = 0;
  let archiverFlushed = 0;
  const mainStore = new Map([
    ['theme', '0'],
    ['proxy_ip', '9.9.9.9'],
    ['domain_fronting', 'true'],
  ]);
  const archiverStore = new Map([
    ['88Url', 'https://arch.example/88'],
  ]);

  const makeMockPref = (store, onFlush, isMain) => ({
    getSync: (k, d) => (store.has(k) ? store.get(k) : d),
    putSync: (k, v) => { store.set(k, v); },
    deleteSync: (k) => { store.delete(k); },
    hasSync: (k) => store.has(k),
    flush: async () => { onFlush(); },
    getAll: () => {
      const obj = {};
      store.forEach((v, k) => { obj[k] = v; });
      if (isMain) {
        return new Promise((r) => { resolveMainAll = () => r(obj); });
      }
      return Promise.resolve(obj);
    },
  });

  const origDefaultGet = prefMod.default.getPreferences;
  const origGet = prefMod.getPreferences;
  const mockGetPreferences = (_ctx, name) => {
    openNames.push(name);
    if (name === 'settings') {
      return new Promise((r) => {
        resolveMainPref = () => r(makeMockPref(mainStore, () => { mainFlushed++; }, true));
      });
    }
    return Promise.resolve(makeMockPref(archiverStore, () => { archiverFlushed++; }, false));
  };
  prefMod.default.getPreferences = mockGetPreferences;
  prefMod.getPreferences = mockGetPreferences;

  // 并发调用两次 attach
  const p1 = Settings.attach(fakeCtx);
  const p2 = Settings.attach(fakeCtx);
  await Promise.resolve();

  eq(Settings.isAttached(), false, 'getPreferences 未完成时 isAttached() 仍为 false');
  eq(Settings.sPref, null, '…且 sPref 仍为 null（不提前暴露）');

  resolveMainPref();
  await new Promise((r) => setTimeout(r, 10));

  // 在 getAll() 仍未完成时再写入一条，并检查 isAttached 仍为 false
  eq(Settings.isAttached(), false, 'getPreferences 完成但 getAll() 未完成时 isAttached() 仍为 false');
  eq(Settings.sPref, null, '…且 sPref 仍为 null');
  Settings.putDF(false);

  resolveMainAll();
  await Promise.all([p1, p2]);

  eq(openNames, ['settings', 'archiver'], '并发 attach 去重：两库各只打开一次');
  eq(Settings.isAttached(), true, '**attach 之后 isAttached() === true**');
  eq(Settings.getTheme(), Settings.THEME_BLACK, '预写 theme 覆盖磁盘旧值并保留');
  eq(Settings.getDF(), false, 'attach 期间的写入(putDF=false) 保留且生效');
  eq(Settings.getProxyIp(), null, '预删 proxy_ip 覆盖磁盘旧值(9.9.9.9 → null)');
  eq(Settings.getArchiverDownloadUrl(88), 'https://arch.example/88', '磁盘原有 archiver 数据载入成功');
  eq(Settings.getArchiverDownloadId(77), 321, '预写 archiver 数据保留并写入');
  eq(mainStore.get('theme'), '2', '预写已落盘回 mainStore');
  eq(mainStore.get('domain_fronting'), false, '期间写入已落盘回 mainStore');
  eq(mainStore.has('proxy_ip'), false, '预删已从 mainStore 删除');
  eq(archiverStore.get('77DId'), 321, '预写 archiver 已落盘回 archiverStore');
  eq([mainFlushed >= 1, archiverFlushed >= 1], [true, true], '预写重放触发了 flush');

  // ③ 幂等：恢复后重复 attach 仍为 true 且不会丢失刚写的数据
  prefMod.default.getPreferences = mockGetPreferences;
  prefMod.getPreferences = mockGetPreferences;
  const p3 = Settings.attach(fakeCtx);
  await new Promise((r) => setTimeout(r, 10));
  resolveMainPref();
  await new Promise((r) => setTimeout(r, 10));
  resolveMainAll();
  await p3;
  eq(Settings.isAttached(), true, '重复 attach → 仍 true（幂等）');
  eq(Settings.getTheme(), Settings.THEME_BLACK, '重复 attach 后仍保留最新配置');
  eq(typeof Settings.getPreloadImage() === 'number', true, 'attach 后读设置可用（返回 number）');

  prefMod.default.getPreferences = origDefaultGet;
  prefMod.getPreferences = origGet;

  console.log('\n' + (fail === 0 ? 'ALL PASS' : fail + ' FAILED'));
  process.exit(fail === 0 ? 0 : 1);
})();
