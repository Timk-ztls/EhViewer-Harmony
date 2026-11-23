// RestoreDownload 的扫描/应用两段纯逻辑断言
global.Observed = (target) => target;
const path = require('path');
const OUT = process.argv[2] || path.join(process.env.TEMP, 'tscheck', 'out9');
const { RestoreDownloadPreference, RestoreItem, SpiderHeader } =
  require(path.join(OUT, 'RestoreDownloadPreference.js'));

let fail = 0;
const eq = (a, b, label) => {
  const A = JSON.stringify(a), B = JSON.stringify(b);
  if (A === B) console.log('  PASS  ' + label);
  else { fail++; console.log('  FAIL  ' + label + '\n    实际: ' + A + '\n    期望: ' + B); }
};

const SI = '.ehviewer';
const mkDir = (name, hasSi, header) => ({
  getName: () => name,
  isDirectory: () => true,
  findFile: async (fn) => ((fn === SI && hasSi) ? { getName: () => SI, __h: header } : null),
  listFiles: async () => [],
});
const mkFile = (name) => ({
  getName: () => name,
  isDirectory: () => false,
  findFile: async () => null,
  listFiles: async () => null,
});

(async () => {
  const readHeader = (f) => (f.__h !== undefined ? f.__h : null);
  // 1) 非目录 → null
  eq(await RestoreDownloadPreference.getRestoreItem(mkFile('x'), () => false, readHeader, SI), null,
    'getRestoreItem: 非目录 → null');
  // 2) 目录但无 spider info → null
  eq(await RestoreDownloadPreference.getRestoreItem(mkDir('d', false, null), () => false, readHeader, SI), null,
    'getRestoreItem: 目录中没有 SPIDER_INFO → null');
  // 3) header 读失败 → null
  const d3 = mkDir('d', true, null);
  eq(await RestoreDownloadPreference.getRestoreItem(d3, () => false, readHeader, SI), null,
    'getRestoreItem: readHeader 失败 → null');
  // 4) 已在下载列表 → null（上游 mManager.containDownloadInfo）
  const d4 = mkDir('123-456', true, new SpiderHeader(123, 'tok'));
  eq(await RestoreDownloadPreference.getRestoreItem(d4, (g) => g === 123, readHeader, SI), null,
    'getRestoreItem: gid 已在下载列表 → null（不需要恢复）');
  // 5) 正常恢复项
  const item = await RestoreDownloadPreference.getRestoreItem(d4, () => false, readHeader, SI);
  eq(item !== null && item.gid === 123 && item.token === 'tok' && item.dirname === '123-456', true,
    'getRestoreItem: 正常项 = {gid, token, dirname=目录名}');

  // 6) scanRestoreItems：目录不可用 → noDirectory=true（对应上游返回 null → "恢复失败"）
  const r1 = await RestoreDownloadPreference.scanRestoreItems(() => false, readHeader, SI,
    undefined, undefined, null);
  eq(r1.noDirectory, true, 'scanRestoreItems: downloadLocation 为 null → noDirectory=true');
  eq(r1.items.length, 0, '…items 为空');

  // 7) 进度回调：先 (0,total) 再逐项 (i+1,total)
  const dir = { isDirectory: () => true, listFiles: async () => [mkFile('a'), mkFile('b')] };
  const progress = [];
  const r2 = await RestoreDownloadPreference.scanRestoreItems(() => false, readHeader, SI,
    (p, m) => progress.push([p, m]), undefined, dir);
  eq(progress, [[0, 2], [1, 2], [2, 2]], 'scanRestoreItems: 进度 (0,total) + 每项 (i+1,total)');
  eq(r2.items.length, 0, '…都不是目录 → 0 个恢复项');

  // 8) 取消：立刻返回且不产出
  const dir3 = { isDirectory: () => true, listFiles: async () => [mkFile('a')] };
  const r3 = await RestoreDownloadPreference.scanRestoreItems(() => false, readHeader, SI,
    undefined, () => true, dir3);
  eq(r3.items.length, 0, 'scanRestoreItems: 取消后不产出恢复项');

  // 9) applyRestore：无线上标题时回退为 dirname / gid，不跳过
  const items = [new RestoreItem(1, 't1', 'd1'), new RestoreItem(2, 't2', 'd2'), new RestoreItem(3, 't3', null)];
  const added = []; const put = [];
  const count = await RestoreDownloadPreference.applyRestore(items,
    (it) => (it.gid === 1 ? 'api-title' : null),       // gid=2/3 详情填充失败，走兜底标题
    (it) => added.push([it.gid, it.title]),
    async (gid, dirname) => { put.push(gid + ':' + dirname); });
  eq(count, 3, 'applyRestore: 无线上标题不跳过，count=3');
  eq(added, [[1, 'api-title'], [2, 'd2'], [3, '3']], '…标题兜底：API → dirname → String(gid)');
  eq(put, ['1:d1', '2:d2'], '…dirname 为 null 的项不写 DOWNLOAD_DIRNAME（上游 putDownloadDirname 只在有值时调）');

  // 10) 三层回退（.ehviewer → CBOR/readHeader → ComicInfo.xml）及边界校验
  let comicCalls = 0;
  const comicOnly = await RestoreDownloadPreference.getRestoreItem(
    mkDir('dir-comic', false, null),
    () => false,
    readHeader,
    SI,
    () => { comicCalls++; return new SpiderHeader(456, 'tok_xml'); }
  );
  eq(comicCalls, 1, 'getRestoreItem: 缺 .ehviewer 时调用 readComicInfo');
  eq(comicOnly !== null && comicOnly.gid === 456 && comicOnly.token === 'tok_xml' && comicOnly.dirname === 'dir-comic',
    true, 'getRestoreItem: ComicInfo.xml 回退成功');

  const corruptFallback = await RestoreDownloadPreference.getRestoreItem(
    mkDir('dir-corrupt', true, null),
    () => false,
    readHeader,
    SI,
    () => new SpiderHeader(789, 'tok_c2')
  );
  eq(corruptFallback !== null && corruptFallback.gid === 789 && corruptFallback.token === 'tok_c2',
    true, 'getRestoreItem: .ehviewer 读失败时回退 readComicInfo');

  let comicCallsWhenPrimaryValid = 0;
  const primaryWins = await RestoreDownloadPreference.getRestoreItem(
    mkDir('dir-primary', true, new SpiderHeader(0, 'tok_zero')),
    () => false,
    readHeader,
    SI,
    () => { comicCallsWhenPrimaryValid++; return new SpiderHeader(999, 'other'); }
  );
  eq(comicCallsWhenPrimaryValid, 0, 'getRestoreItem: 主读取成功（含 gid=0）时不调 readComicInfo');
  eq(primaryWins !== null && primaryWins.gid === 0 && primaryWins.token === 'tok_zero',
    true, 'getRestoreItem: gid=0 且 token 非空有效');

  const emptyTokenRejected = await RestoreDownloadPreference.getRestoreItem(
    mkDir('dir-empty-tok', true, new SpiderHeader(10, '')),
    () => false,
    readHeader,
    SI,
    () => new SpiderHeader(10, '')
  );
  eq(emptyTokenRejected, null, 'getRestoreItem: 空 token 拒绝恢复');

  console.log('\n' + (fail === 0 ? 'ALL PASS' : fail + ' FAILED'));
  process.exit(fail === 0 ? 0 : 1);
})();
