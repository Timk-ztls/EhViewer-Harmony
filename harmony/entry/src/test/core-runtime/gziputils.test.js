// GZIPUtils：gzip+Base64 roundtrip（真 zlib）、Base64.DEFAULT 形态、ZIP 解包防穿越
global.Observed = (target) => target;
const path = require('path');
const zlib = require('zlib');
const OUT = process.argv[2] || path.join(process.env.TEMP, 'tscheck', 'out11');
const { GZIPUtils } = require(path.join(OUT, 'ehviewer', 'util', 'GZIPUtils.js'));

let fail = 0;
const eq = (a, b, label) => {
  const A = JSON.stringify(a), B = JSON.stringify(b);
  if (A === B) console.log('  PASS  ' + label);
  else { fail++; console.log('  FAIL  ' + label + '\n    实际: ' + A + '\n    期望: ' + B); }
};

const gzip = (u8) => new Promise((res, rej) =>
  zlib.gzip(Buffer.from(u8), (e, out) => (e ? rej(e) : res(new Uint8Array(out)))));
const gunzip = (u8) => new Promise((res, rej) =>
  zlib.gunzip(Buffer.from(u8), (e, out) => (e ? rej(e) : res(new Uint8Array(out)))));

(async () => {
  // ── compress 的边界（上游第一行就 return）──
  eq(await GZIPUtils.compress(null, gzip), null, 'compress(null) → null（原样返回）');
  eq(await GZIPUtils.compress('', gzip), '', "compress('') → ''（原样返回，**不产生空 gzip**）");

  // ── roundtrip ──
  const text = '{"gid":123,"token":"abc","title":"中文标题"}';
  const c1 = await GZIPUtils.compress(text, gzip);
  eq(await GZIPUtils.uncompress(c1, gunzip), text, 'roundtrip：压缩再解压 = 原文（含中文）');

  const long = 'x'.repeat(2000);
  const c2 = await GZIPUtils.compress(long, gzip);
  eq((await GZIPUtils.uncompress(c2, gunzip)).length, 2000, 'roundtrip：2000 字符');

  // ── Base64.DEFAULT 形态（**每 76 字符换行 + 末尾换行**）──
  // 用**不可压缩**的数据，保证 Base64 超过 76 字符（'a'.repeat(300) 压缩后极短）
  let noise = '';
  for (let i = 0; i < 200; i++) { noise += String.fromCharCode(33 + ((i * 37) % 90)); }
  const c3 = await GZIPUtils.compress(noise, gzip);
  eq(c3.indexOf('\n') > 0, true, 'Base64 输出含换行（DEFAULT 会换行，NO_WRAP 不会）');
  const lines = c3.split('\n').filter((l) => l.length > 0);
  eq(lines.every((l) => l.length <= 76), true, '…每行不超过 76 字符');
  eq(lines.length >= 2, true, '…200 字符不可压缩数据 → Base64 至少 2 行');

  // ── uncompress 的失败路径 ──
  eq(await GZIPUtils.uncompress(null, gunzip), null, 'uncompress(null) → null');
  eq(await GZIPUtils.uncompress('不是base64!!', gunzip), null, 'uncompress(非法 Base64) → null（不抛）');
  const notGzip = GZIPUtils.encodeBase64Default(new Uint8Array([1, 2, 3, 4]));
  eq(await GZIPUtils.uncompress(notGzip, gunzip), null, 'uncompress(合法 Base64 但非 gzip) → null（不抛）');
  // 带换行的 base64 也能解（DEFAULT 解码忽略空白）
  const withBreaks = c1.replace(/\n/g, '\n  ');
  eq(await GZIPUtils.uncompress(withBreaks, gunzip), text, '解码忽略空白（换行/空格不影响）');

  // ── encodeBase64Default / decodeBase64Default 对照 Node 的 base64 ──
  const bytes = new Uint8Array([0, 1, 2, 253, 254, 255, 65, 66, 67]);
  const mine = GZIPUtils.encodeBase64Default(bytes).replace(/\n/g, '');
  eq(mine, Buffer.from(bytes).toString('base64'), 'Base64 编码结果与 Node 一致（去掉换行后）');
  eq(Array.from(GZIPUtils.decodeBase64Default(mine)), Array.from(bytes), 'Base64 解码往返');
  eq(Array.from(GZIPUtils.decodeBase64Default('AAEC/f7/QEFCQw==')), Array.from(Buffer.from('AAEC/f7/QEFCQw==', 'base64')), '解码含 = 填充（对照 Node 的 base64，**16 字符 - 2 填充 = 10 字节**）');

  // ── getFileList：按开关筛选，目录以 '/' 结尾判定 ──
  const entries = ['a.txt', 'dir/', 'dir/b.txt', 'dir/sub/', 'dir/sub/c.txt'];
  const fakeIo = { listEntries: async () => entries };
  eq(await GZIPUtils.getFileList('z', true, true, fakeIo), entries, 'getFileList(两者都要) → 全部');
  eq(await GZIPUtils.getFileList('z', false, true, fakeIo), ['a.txt', 'dir/b.txt', 'dir/sub/c.txt'],
    'getFileList(仅文件) → 3 个');
  eq(await GZIPUtils.getFileList('z', true, false, fakeIo), ['dir/', 'dir/sub/'],
    'getFileList(仅目录) → 2 个');
  eq(await GZIPUtils.getFileList('z', false, false, fakeIo), [], 'getFileList(都不要) → 空');

  // ── unZipFolder：解包 + 两个分支的 '..' 防护 ──
  const made = [];
  const extracted = [];
  const mkIo = (ents) => ({
    listEntries: async () => ents,
    extractEntry: async (z, e, t) => { extracted.push(e + '->' + t); },
    exists: async (p) => made.indexOf(p) >= 0,
    mkdirs: async (p) => { made.push(p); return true; },
    createFile: async (p) => { made.push(p); return true; },
    openEntryStream: async () => ({ stream: 1 }),
  });

  made.length = 0; extracted.length = 0;
  const ok = await GZIPUtils.unZipFolder('z.zip', '/out', mkIo(['a.txt', 'dir/', 'dir/b.txt']));
  eq(ok, true, 'unZipFolder 正常包 → true');
  eq(extracted.length, 2, '…解出 2 个文件');
  eq(made.indexOf('/out/dir') >= 0, true, '…目录条目建了 /out/dir');

  // 文件条目含 '..' → 跳过（上游原样）
  made.length = 0; extracted.length = 0;
  await GZIPUtils.unZipFolder('z.zip', '/out', mkIo(['../../etc/passwd']));
  eq(extracted.length, 0, '文件条目含 .. → **跳过不解**（上游原样）');

  // 目录条目含 '..' → 也跳过（**我们补上的，上游只检查文件**）
  made.length = 0;
  await GZIPUtils.unZipFolder('z.zip', '/out', mkIo(['../../../evil/']));
  eq(made.filter((p) => p.indexOf('evil') >= 0).length, 0,
    '目录条目含 .. → **不 mkdirs**（B 类安全修复：上游此处无检查）');

  // IO 异常 → false（上游 catch IOException 返回 false）
  const badIo = Object.assign({}, mkIo(['a.txt']), { extractEntry: async () => { throw new Error('io'); } });
  eq(await GZIPUtils.unZipFolder('z.zip', '/out', badIo), false, 'unZipFolder IO 异常 → false（不抛）');

  // upZip：透传
  eq((await GZIPUtils.upZip('z.zip', 'a.txt', mkIo(['a.txt']))) !== null, true, 'upZip 返回条目流');
  eq(await GZIPUtils.upZip('z.zip', 'nope', { openEntryStream: async () => null }), null, 'upZip 找不到 → null');

  console.log('\n' + (fail === 0 ? 'ALL PASS' : fail + ' FAILED'));
  process.exit(fail === 0 ? 0 : 1);
})();
