// LogCat.save 的编排与失败语义
global.Observed = (target) => target;
const path = require('path');
const OUT = process.argv[2] || path.join(process.env.TEMP, 'tscheck', 'out11');
const { LogCat } = require(path.join(OUT, 'util', 'LogCat.js'));

let fail = 0;
const eq = (a, b, label) => {
  const A = JSON.stringify(a), B = JSON.stringify(b);
  if (A === B) console.log('  PASS  ' + label);
  else { fail++; console.log('  FAIL  ' + label + '\n    实际: ' + A + '\n    期望: ' + B); }
};

const mkIo = (over) => Object.assign({
  ensureFile: async () => true,
  dumpLogs: async () => new Uint8Array([1, 2, 3]),
  writeBytes: async (p, b) => { written.push(p + ':' + b.length); },
}, over);
let written = [];

(async () => {
  // 1) 正常路径：ensureFile → dump → write
  written = [];
  eq(await LogCat.save('/tmp/logcat.txt', mkIo({})), true, '正常路径 → true');
  eq(written, ['/tmp/logcat.txt:3'], '…按顺序写入目标文件（3 字节）');

  // 2) path=null → false（不调 ensureFile）
  let ensureCalled = false;
  eq(await LogCat.save(null, mkIo({ ensureFile: async () => { ensureCalled = true; return true; } })), false,
    'path=null → false');
  eq(ensureCalled, false, '…且**不调用** ensureFile（先短路）');

  // 3) ensureFile 失败 → false，且不采集、不写
  let dumped = false;
  written = [];
  eq(await LogCat.save('/tmp/x', mkIo({
    ensureFile: async () => false,
    dumpLogs: async () => { dumped = true; return new Uint8Array(); },
  })), false, 'ensureFile 失败 → false');
  eq(dumped, false, '…不采集日志（上游 ensureFile 失败直接 return false）');
  eq(written.length, 0, '…不写文件');

  // 4) 采集抛错 → false（上游 catch IOException）
  eq(await LogCat.save('/tmp/x', mkIo({ dumpLogs: async () => { throw new Error('logcat 不存在'); } })), false,
    'dumpLogs 抛错 → false（不向上抛）');

  // 5) 写入抛错 → false
  eq(await LogCat.save('/tmp/x', mkIo({ writeBytes: async () => { throw new Error('磁盘满'); } })), false,
    'writeBytes 抛错 → false');

  // 6) 空日志也能落盘（0 字节文件）
  written = [];
  eq(await LogCat.save('/tmp/empty', mkIo({ dumpLogs: async () => new Uint8Array(0) })), true,
    '空日志 → 仍然 true（上游 IOUtils.copy 0 字节不算错误）');
  eq(written, ['/tmp/empty:0'], '…写出 0 字节文件');

  console.log('\n' + (fail === 0 ? 'ALL PASS' : fail + ' FAILED'));
  process.exit(fail === 0 ? 0 : 1);
})();
