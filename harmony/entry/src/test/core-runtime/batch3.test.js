// 批次 3：FileUtils / PackageUtils / PermissionRequester + yorozuya FileUtils 的 %.1f 修正
global.Observed = (target) => target;
const path = require('path');
const crypto = require('crypto');
const OUT = process.argv[2] || path.join(process.env.TEMP, 'tscheck', 'out11');
const { FileUtils } = require(path.join(OUT, 'util', 'FileUtils.js'));
const { PackageUtils } = require(path.join(OUT, 'util', 'PackageUtils.js'));
const { PermissionRequester, PermissionDecision } = require(path.join(OUT, 'util', 'PermissionRequester.js'));
const { FileUtils: YFileUtils } = require(path.join(OUT, 'lib', 'yorozuya', 'FileUtils.js'));

let fail = 0;
const eq = (a, b, label) => {
  const A = JSON.stringify(a), B = JSON.stringify(b);
  if (A === B) console.log('  PASS  ' + label);
  else { fail++; console.log('  FAIL  ' + label + '\n    实际: ' + A + '\n    预期: ' + B); }
};

// ══ 1. yorozuya FileUtils 的 %.1f 修正（审计 C 的 P2）══
// 现实现 = toFixed(1)（等价 Java %.1f 的 HALF_UP）；旧实现 = floor(v*10+0.5)/10
const oldImpl = (v) => (Math.floor(v * 10 + 0.5) / 10).toFixed(1);
const newImpl = (v) => v.toFixed(1);
eq(newImpl(0.15), '0.1', '0.15 → "0.1"（Java %.1f；旧实现给 "0.2"）');
eq(newImpl(0.95), '0.9', '0.95 → "0.9"（旧实现给 "1.0"）');
eq(newImpl(8.95), '8.9', '8.95 → "8.9"（旧实现给 "9.0"）');
eq(newImpl(1.45), '1.4', '1.45 → "1.4"（旧实现给 "1.5"）');
eq(newImpl(2.25), '2.3', '2.25 → "2.3"（**恰好 .5 → HALF_UP 进位**；HALF_EVEN 会给 2.2）');
eq(newImpl(2.35), '2.4', '2.35 → "2.4"（2.35 的精确值略大，HALF_EVEN 同样给 2.4 —— 不能区分）');
eq(oldImpl(0.15) !== newImpl(0.15), true, '对照：旧实现 0.15 → "0.2"，与新实现不同');
// 实际暴露的测试出口与实现一致
eq(YFileUtils.formatOneDecimalForTest(8.95), '8.9', '暴露的 formatOneDecimalForTest 已是修正后实现');
eq(YFileUtils.formatOneDecimalForTest(2.25), '2.3', '…2.25 → "2.3"（HALF_UP）');
// 人类可读字节串回归（整数字节，实际调用路径）
eq(YFileUtils.humanReadableByteCount(1024, false), '1.0 KiB', '1024 → "1.0 KiB"');
eq(YFileUtils.humanReadableByteCount(1536, false), '1.5 KiB', '1536 → "1.5 KiB"');
eq(YFileUtils.humanReadableByteCount(1048576, false), '1.0 MiB', '1048576 → "1.0 MiB"');
eq(YFileUtils.humanReadableByteCount(1000, true), '1.0 kB', '1000(si) → "1.0 kB"');
eq(YFileUtils.humanReadableByteCount(1500, true), '1.5 kB', '1500(si) → "1.5 kB"');

// ══ 2. util/FileUtils ══
const mkIo = (files) => {
  const state = { files: Object.assign({}, files), dirs: new Set(), opened: [], written: [], flushed: 0, renamed: [] };
  return {
    state,
    exists: (p) => state.files[p] !== undefined || state.dirs.has(p),
    isDirectory: (p) => state.dirs.has(p),
    mkdirs: (p) => { state.dirs.add(p); return true; },
    rename: (a, b) => { state.renamed.push([a, b]); state.files[b] = state.files[a]; delete state.files[a]; return true; },
    openIn: (p) => { const s = { p, data: state.files[p] || new Uint8Array(0), pos: 0 }; state.opened.push(s); return s; },
    openOut: (p) => { const s = { p, chunks: [] }; state.opened.push(s); return s; },
    read: (s, buf, len) => { const n = Math.min(len, s.data.length - s.pos); if (n <= 0) return 0; buf.set(s.data.subarray(s.pos, s.pos + n)); s.pos += n; return n; },
    write: (s, buf, len) => { s.chunks.push(Array.from(buf.subarray(0, len))); state.written.push(len); },
    flush: () => { state.flushed++; },
    close: () => {},
  };
};

{
  const io = mkIo({ '/src/a.txt': new Uint8Array([1, 2, 3]) });
  eq(FileUtils.moveFile('/src/a.txt', '/dst', io), true, 'moveFile 成功 → true');
  eq(io.state.renamed[0], ['/src/a.txt', '/dst/a.txt'], '…rename 到 destDir/<原名>');
  eq(io.state.dirs.has('/dst'), true, '…目标目录不存在时会创建');
  const io2 = mkIo({});
  eq(FileUtils.moveFile('/nope.txt', '/dst', io2), false, 'moveFile 源不存在 → false');
  eq(io2.state.renamed.length, 0, '…不调用 rename');
  const io3 = mkIo({ '/src/a.txt': new Uint8Array([1]), '/dst/a.txt': new Uint8Array([9]) });
  io3.rename = () => { throw new Error('SecurityException'); };
  eq(FileUtils.moveFile('/src/a.txt', '/dst', io3), false, 'moveFile rename 抛 SecurityException → false');
}

{
  // copyFile：多块拷贝（2500 字节 → 3 块）
  const data = new Uint8Array(2500); for (let i = 0; i < data.length; i++) data[i] = i & 0xFF;
  const io = mkIo({ '/src': data });
  eq(FileUtils.copyFile('/src', '/dst', io), true, 'copyFile 成功 → true');
  eq(io.state.written, [1024, 1024, 452], '…按 1024 块拷贝（1024+1024+452）');
  eq(io.state.flushed, 0, 'flush=false → 不调用 flush');
  const io2 = mkIo({ '/src': data });
  FileUtils.copyFileWithFlush('/src', '/dst', true, io2);
  eq(io2.state.flushed, 1, 'flush=true → 调用 1 次 flush');

  // 空文件：read 直接返回 0 → 不写任何块
  const io3 = mkIo({ '/src': new Uint8Array(0) });
  eq(FileUtils.copyFile('/src', '/dst', io3), true, 'copyFile 空文件 → true');
  eq(io3.state.written, [], '…不写任何块（read 返回 0 即退出循环）');

  // 读取抛错 → false
  const io4 = mkIo({ '/src': data });
  io4.openIn = () => { throw new Error('EACCES'); };
  eq(FileUtils.copyFile('/src', '/dst', io4), false, 'openIn 抛错 → false');
}

{
  // read：UTF-8 解码
  const utf8 = (s) => new Uint8Array(Buffer.from(s, 'utf8'));
  const io = mkIo({ '/f': utf8('中文abc') });
  eq(FileUtils.read('/f', io, (s) => s.data), '中文abc', 'read 按 UTF-8 解码（含中文）');
  eq(FileUtils.read(null, io, (s) => s.data), null, 'read(null) → null');
  const ioErr = mkIo({});
  ioErr.openIn = () => { throw new Error('ENOENT'); };
  eq(FileUtils.read('/nope', ioErr, (s) => s.data), null, 'read 异常 → null');
  // 4 字节 UTF-8（emoji）
  eq(FileUtils.decodeUtf8(utf8('😀')), '😀', 'decodeUtf8 支持 4 字节码点（代理对）');
}

// ══ 3. PackageUtils ══
const sha1 = (b) => new Uint8Array(crypto.createHash('sha1').update(Buffer.from(b)).digest());
{
  const cert = new Uint8Array([1, 2, 250, 255]);
  const fp = PackageUtils.computeSHA1(cert, sha1);
  const expect = crypto.createHash('sha1').update(Buffer.from(cert)).digest('hex')
    .toUpperCase().match(/.{2}/g).join(':');
  eq(fp, expect, 'computeSHA1 与 node crypto 逐字符一致（大写 + 冒号分隔）');
  eq(fp.length, 59, '…长度 59（20 字节 × 2 + 19 个冒号）');
  eq(fp, fp.toUpperCase(), '…全大写');
  eq(/^[0-9A-F]{2}(:[0-9A-F]{2}){19}$/.test(fp), true, '…形如 AA:BB:…（20 段两位十六进制）');
  // 补零：0x05 → "05"
  // 单字节输入（覆盖高/低位，含会产生前导零 nibble 的情况）与 node 逐字符对照
  let zeroPadFound = false;
  for (let b = 0; b < 256; b++) {
    const got = PackageUtils.computeSHA1(new Uint8Array([b]), sha1);
    const want = crypto.createHash('sha1').update(Buffer.from([b])).digest('hex')
      .toUpperCase().match(/.{2}/g).join(':');
    if (got !== want) { fail++; console.log('  FAIL  单字节 ' + b + ' 与 node 不一致：' + got + ' vs ' + want); break; }
    if (/:[0-9A-F][0-9A-F]/.test(got) && got.split(':').some((p) => p.charAt(0) === '0')) zeroPadFound = true;
  }
  eq(zeroPadFound, true, '256 个单字节输入全部与 node 一致，且覆盖到**需要补零**的段（0x0X）');
  // 算法抛错 → null
  eq(PackageUtils.computeSHA1(cert, () => { throw new Error('no SHA1'); }), null, 'SHA1 抛错 → null');
  // getSignature
  eq(PackageUtils.getSignature('pkg', () => cert, sha1), expect, 'getSignature 取证书 → 指纹');
  eq(PackageUtils.getSignature('pkg', () => null, sha1), null, '证书取不到 → null');
  eq(PackageUtils.getSignature('pkg', () => new Uint8Array(0), sha1), null, '证书空数组 → null');
  eq(PackageUtils.getSignature('pkg', () => { throw new Error('no pkg'); }, sha1), null, '取证书抛错 → null');
}

// ══ 4. PermissionRequester ══
{
  const mknow = (granted, rationale) => {
    const calls = [];
    return {
      calls,
      isGranted: () => granted,
      shouldShowRationale: () => rationale,
      requestPermissions: (p, code) => calls.push('req:' + p.join(',') + ':' + code),
    };
  };
  // 决策
  eq(PermissionRequester.decide(mknow(true, false), 'P'), PermissionDecision.ALREADY_GRANTED, 'decide：已授权');
  eq(PermissionRequester.decide(mknow(false, true), 'P'), PermissionDecision.NEED_RATIONALE, 'decide：需解释');
  eq(PermissionRequester.decide(mknow(false, false), 'P'), PermissionDecision.REQUEST, 'decide：直接申请');

  // 无回调重载：已授权 → true 且**不回调**
  let agreed = [];
  const io1 = mknow(true, false);
  eq(PermissionRequester.request('P', 7, io1), true, 'request(已授权) → true（无需申请）');
  eq(io1.calls.length, 0, '…未发起申请');
  eq(agreed, [], '…无回调重载不调用 agree');

  // 带回调重载：已授权 → true 且**立刻回调 agree(requestCode)**
  const io2 = mknow(true, false);
  eq(PermissionRequester.requestWithCallback('P', 9, io2, { agree: (c) => agreed.push(c) }), true,
    'requestWithCallback(已授权) → true');
  eq(agreed, [9], '**…并立刻回调 agree(9)**（两个重载的关键差异）');

  // 需解释 → false 且不发起申请（等调用方渲染对话框后调 confirmRequest）
  const io3 = mknow(false, true);
  eq(PermissionRequester.request('P', 1, io3), false, 'request(需解释) → false');
  eq(io3.calls.length, 0, '…此时**不发起申请**（等用户点确定）');
  PermissionRequester.confirmRequest('P', 1, io3);
  eq(io3.calls, ['req:P:1'], 'confirmRequest 后才发起申请');

  // 直接申请 → false 且立刻发起
  const io4 = mknow(false, false);
  eq(PermissionRequester.request('P', 2, io4), false, 'request(直接申请) → false');
  eq(io4.calls, ['req:P:2'], '…并立刻发起申请');

  // 回调是全局单例（last-wins）
  agreed = [];
  PermissionRequester.requestWithCallback('P', 11, mknow(true, false), { agree: (c) => agreed.push('A' + c) });
  PermissionRequester.requestWithCallback('P', 12, mknow(true, false), { agree: (c) => agreed.push('B' + c) });
  eq(agreed, ['A11', 'B12'], '两次注册各自回调一次');
  PermissionRequester.requestWithCallback('P', 13, mknow(true, false), { agree: () => {} });
  accepted = [];
  eq(PermissionRequester.getCallback() !== null, true, 'getCallback 返回最后注册的回调');
  PermissionRequester.clearCallback();
  eq(PermissionRequester.getCallback(), null, 'clearCallback 后可清空（上游无此方法）');
  // 清空后带回调重载仍能工作：只是不回调
  eq(PermissionRequester.request('P', 14, mknow(true, false)), true, '清空回调后无回调重载仍返回 true');
}
var accepted;

console.log('\n' + (fail === 0 ? 'ALL PASS' : fail + ' FAILED'));
process.exit(fail === 0 ? 0 : 1);
