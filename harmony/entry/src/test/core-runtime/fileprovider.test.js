// FileProvider：URI ↔ 路径映射 + 越界防护 + modeToMode
global.Observed = (target) => target;
const path = require('path');
const OUT = process.argv[2] || path.join(process.env.TEMP, 'tscheck', 'out11');
const { FileProvider, FileMode } = require(path.join(OUT, 'content', 'FileProvider.js'));

let fail = 0;
const eq = (a, b, label) => {
  const A = JSON.stringify(a), B = JSON.stringify(b);
  if (A === B) console.log('  PASS  ' + label);
  else { fail++; console.log('  FAIL  ' + label + '\n    实际: ' + A + '\n    期望: ' + B); }
};
const throwsWith = (fn, sub, label) => {
  try { fn(); fail++; console.log('  FAIL  ' + label + '（未抛错）'); }
  catch (e) {
    if (String(e.message).indexOf(sub) >= 0) console.log('  PASS  ' + label + ' → "' + e.message + '"');
    else { fail++; console.log('  FAIL  ' + label + ' → "' + e.message + '"'); }
  }
};

// 极简规范化器：解析 '..' 与 '.'（模拟 getCanonicalPath 的路径部分）
const canon = (p) => {
  const abs = p.startsWith('/');
  const out = [];
  for (const seg of p.split('/')) {
    if (seg === '' || seg === '.') continue;
    if (seg === '..') { out.pop(); continue; }
    out.push(seg);
  }
  return (abs ? '/' : '') + out.join('/');
};

// ── 常量 ──
eq([FileProvider.TAG_ROOT_PATH, FileProvider.TAG_FILES_PATH, FileProvider.TAG_CACHE_PATH,
    FileProvider.TAG_EXTERNAL, FileProvider.TAG_EXTERNAL_FILES, FileProvider.TAG_EXTERNAL_CACHE],
  ['root-path', 'files-path', 'cache-path', 'external-path', 'external-files-path', 'external-cache-path'],
  '六个 XML 标签名与上游一致');
eq(FileProvider.DEVICE_ROOT, '/', 'DEVICE_ROOT = "/"');

// ── addRoot 校验 ──
const fp = new FileProvider('com.example.files', canon);
throwsWith(() => fp.addRoot('', '/data'), 'Name must not be empty', 'addRoot 空名字 → 抛错');
fp.addRoot('files', '/data/app/files');
fp.addRoot('cache', '/data/app/cache');
eq(fp.getRoots().length, 2, 'addRoot 注册两个根');

// ── getUriForFile：最长匹配根 ──
eq(fp.getUriForFile('/data/app/files/a.txt'), 'content://com.example.files/files/a.txt',
  'getUriForFile: 命中 files 根');
eq(fp.getUriForFile('/data/app/cache/b.png'), 'content://com.example.files/cache/b.png',
  'getUriForFile: 命中 cache 根');
// 最长匹配：再注册一个更深的根，应优先命中它
fp.addRoot('sub', '/data/app/files/sub');
eq(fp.getUriForFile('/data/app/files/sub/x.txt'), 'content://com.example.files/sub/x.txt',
  'getUriForFile 选**最长匹配根**（不是先注册的那个）');
eq(fp.getUriForFile('/data/app/files/y.txt'), 'content://com.example.files/files/y.txt',
  '…非 sub 下仍命中 files 根');
throwsWith(() => fp.getUriForFile('/etc/passwd'),
  'Failed to find configured root', 'getUriForFile: 根之外的路径 → 抛错');

// ── getFileForUri：往返 ──
eq(fp.getFileForUri('content://com.example.files/files/a.txt'), '/data/app/files/a.txt',
  'getFileForUri 往返正确');
eq(fp.getFileForUri('content://com.example.files/cache/b.png'), '/data/app/cache/b.png',
  '…cache 根往返正确');
throwsWith(() => fp.getFileForUri('content://com.example.files/nosuch/a.txt'),
  'Unable to find configured root', 'getFileForUri: 未知根 → 抛错');

// ── 路径穿越防护（最关键） ──
throwsWith(() => fp.getFileForUri('content://com.example.files/files/../../etc/passwd'),
  'Resolved path jumped beyond configured root', '路径穿越 `../..` → 抛 SecurityError 同义错误');
throwsWith(() => fp.getFileForUri('content://com.example.files/files/%2E%2E/%2E%2E/etc/passwd'),
  'Resolved path jumped beyond configured root', 'URL 编码的穿越 %2E%2E → 同样被拦（解码后检查）');

// 根内合法上跳不算穿越
eq(fp.getFileForUri('content://com.example.files/files/sub/../a.txt'), '/data/app/files/a.txt',
  '根内合法上跳（sub/..）→ 允许，规范化后仍在根下');

// ── modeToMode ──
eq(FileProvider.modeToMode('r'), FileMode.MODE_READ_ONLY, "mode 'r' → READ_ONLY");
eq(FileProvider.modeToMode('w'),
  FileMode.MODE_WRITE_ONLY | FileMode.MODE_CREATE | FileMode.MODE_TRUNCATE, "mode 'w' → WRITE|CREATE|TRUNCATE");
eq(FileProvider.modeToMode('wt'),
  FileMode.MODE_WRITE_ONLY | FileMode.MODE_CREATE | FileMode.MODE_TRUNCATE, "mode 'wt' 与 'w' 同值");
eq(FileProvider.modeToMode('wa'),
  FileMode.MODE_WRITE_ONLY | FileMode.MODE_CREATE | FileMode.MODE_APPEND, "mode 'wa' → WRITE|CREATE|APPEND");
eq(FileProvider.modeToMode('rw'),
  FileMode.MODE_READ_WRITE | FileMode.MODE_CREATE, "mode 'rw' → READ_WRITE|CREATE");
eq(FileProvider.modeToMode('rwt'),
  FileMode.MODE_READ_WRITE | FileMode.MODE_CREATE | FileMode.MODE_TRUNCATE, "mode 'rwt' → READ_WRITE|CREATE|TRUNCATE");
throwsWith(() => FileProvider.modeToMode('x'), 'Invalid mode: x', 'mode 非法 → 抛错');

// ── buildPath ──
eq(FileProvider.buildPath('/a', 'b', 'c'), '/a/b/c', 'buildPath 多段拼接');
eq(FileProvider.buildPath('/a/', 'b'), '/a/b', "buildPath base 末尾有 '/' 时不重复补");
eq(FileProvider.buildPath('/a'), '/a', 'buildPath 无段 → 原样');

console.log('\n' + (fail === 0 ? 'ALL PASS' : fail + ' FAILED'));
process.exit(fail === 0 ? 0 : 1);
