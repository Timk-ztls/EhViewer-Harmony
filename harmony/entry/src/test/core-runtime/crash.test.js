// Crash：日志文本格式（逐字节对照上游）+ 落盘编排 + shouldSave 三态
global.Observed = (target) => target;
const path = require('path');
const OUT = process.argv[2] || path.join(process.env.TEMP, 'tscheck', 'out11');
const { Crash } = require(path.join(OUT, 'ehviewer', 'Crash.js'));
const { PacketInfo, CrashDeviceInfo, CrashMemoryInfo, CrashRuntimeInfo } =
  require(path.join(OUT, 'ehviewer', 'CrashTypes.js'));
const { AppConfig } = require(path.join(OUT, 'ehviewer', 'AppConfig.js'));
// 先初始化 AppConfig，否则 getExternalCrashDir() 返回 null（saveCrashLog 会直接短路）
AppConfig.initialize({ filesDir: '/tmp/fake-files', cacheDir: '/tmp/fake-cache' });

let fail = 0;
const eq = (a, b, label) => {
  const A = JSON.stringify(a), B = JSON.stringify(b);
  if (A === B) console.log('  PASS  ' + label);
  else { fail++; console.log('  FAIL  ' + label + '\n    实际: ' + A + '\n    期望: ' + B); }
};

const EOL = '\r\n';
const mkDevice = () => {
  const d = new CrashDeviceInfo();
  d.board = 'B'; d.bootloader = 'BL'; d.cpuAbi = 'arm64'; d.cpuAbi2 = '';
  d.device = 'DEV'; d.display = 'HarmonyOS 5.0'; d.fingerprint = 'FP';
  d.hardware = 'HW'; d.host = 'H'; d.id = 'ID'; d.manufacturer = 'HUAWEI';
  d.model = 'Mate'; d.product = 'P'; d.radio = ''; d.serial = '';
  d.tags = 'T'; d.type = 'T'; d.user = 'U'; d.codename = 'REL';
  d.incremental = '1'; d.release = '5.0.0'; d.sdkInt = 20;
  return d;
};
const mkMem = () => {
  const m = new CrashMemoryInfo();
  m.appAllocated = 1024 * 1024;      // 1.0 MiB
  m.nativeAllocated = 0;             // 0 B
  m.appMax = 20 * 1024 * 1024;       // 20.0 MiB
  m.total = 8 * 1024 * 1024 * 1024;  // 8.0 GiB
  return m;
};
const stackOf = (t) => `java.lang.Error: ${t.msg}\n\tat x.y.Z(Z.kt:1)\n`;
const rt = new CrashRuntimeInfo('com.x.MainAbility', null);

// ── avoidNull ──
eq(Crash.avoidNull(null), 'null', 'avoidNull(null) → "null"');
eq(Crash.avoidNull('a'), 'a', 'avoidNull("a") → "a"');
eq(Crash.avoidNull(''), '', 'avoidNull("") → ""（空串不是 null）');

// ── shouldSave 三态（对应上游 `!initialized || getSaveCrashLog()`）──
eq(Crash.shouldSave(false, false), true, '接线未完成 + 开关关 → **仍然记录**（上游 !initialized）');
eq(Crash.shouldSave(false, true), true, '接线未完成 + 开关开 → 记录');
eq(Crash.shouldSave(true, true), true, '接线完成 + 开关开 → 记录');
eq(Crash.shouldSave(true, false), false, '接线完成 + 开关关 → **不记录**');

// ── 常量 ──
eq(Crash.EOL, '\r\n', 'EOL 是硬编码 \\r\\n（不是 System.lineSeparator）');
eq([Crash.FILE_PREFIX, Crash.FILE_SUFFIX], ['crash-', '.log'], '文件名前缀/后缀 crash- / .log');

// ── formatCrashLog：逐段结构 ──
const pkg = new PacketInfo('com.example.eh', '2.0.2.6', 20206);
const text = Crash.formatCrashLog('2026-10-25-19-30-00-000', pkg, mkDevice(), mkMem(),
  () => 'AA:BB', rt, { msg: 'boom' }, stackOf);

eq(text.indexOf('TIME=2026-10-25-19-30-00-000' + EOL) === 0, true, '首行是 TIME=<时间>');
eq(text.split(EOL)[1], '', '…紧跟一个空行');
eq(text.indexOf('======== PackageInfo ========') > 0, true, '含 PackageInfo 段');
eq(text.indexOf('PackageName=com.example.eh') > 0, true, '…PackageName');
eq(text.indexOf('VersionName=2.0.2.6') > 0, true, '…VersionName');
eq(text.indexOf('VersionCode=20206') > 0, true, '…VersionCode');
eq(text.indexOf('Signature=AA:BB') > 0, true, '…Signature 走注入的取签名');
eq(text.indexOf('======== Runtime ========') > 0, true, '含 Runtime 段');
eq(text.indexOf('TopActivity=com.x.MainAbility') > 0, true, '…TopActivity');
eq(text.indexOf('TopScene=null') > 0, true, '…TopScene 为 null 时输出字面 "null"（avoidNull）');
eq(text.indexOf('======== DeviceInfo ========') > 0, true, '含 DeviceInfo 段');
eq(text.indexOf('MEMORY=1.0 MiB') > 0, true, 'MEMORY 走 humanReadableByteCount（1 MiB → "1.0 MiB"）');
eq(text.indexOf('MEMORY_NATIVE=0 B') > 0, true, '…0 字节 → "0 B"');
eq(text.indexOf('MEMORY_MAX=20.0 MiB') > 0, true, '…20 MiB');
eq(text.indexOf('MEMORY_TOTAL=8.0 GiB') > 0, true, '…8 GiB（跨到 GiB 档）');
eq(text.indexOf('SDK=20') > 0, true, '…SDK 段');
eq(text.indexOf('======== CrashInfo ========') > 0, true, '含 CrashInfo 段');
eq(text.indexOf('java.lang.Error: boom') > 0, true, '…含栈文本');
eq(text.endsWith(EOL), true, '全文以 \\r\\n 结尾（上游最后写了一个空行）');
eq(text.indexOf('\n\n') >= 0, false, '**不含裸 \\n**（只有 \\r\\n；裸 \\n 会与上游日志不匹配）');

// 段顺序
const order = ['TIME=', 'PackageInfo', 'Runtime', 'DeviceInfo', 'CrashInfo']
  .map((k) => text.indexOf(k));
eq(order[0] < order[1] && order[1] < order[2] && order[2] < order[3] && order[3] < order[4], true,
  '四段顺序：PackageInfo → Runtime → DeviceInfo → CrashInfo');

// 包信息取不到 → 上游写 "Can't get package information"
const textNoPkg = Crash.formatCrashLog('T', null, mkDevice(), mkMem(), () => null, rt,
  { msg: 'x' }, stackOf);
eq(textNoPkg.indexOf("Can't get package information") > 0, true, '包信息为 null → "Can\'t get package information"');
eq(textNoPkg.indexOf('PackageName=') === -1, true, '…且不出现 PackageName=');

// versionName 为 null → 输出字面 "null"；签名为 null → "null"
const pkg2 = new PacketInfo('p', null, 1);
const textNulls = Crash.formatCrashLog('T', pkg2, mkDevice(), mkMem(), () => null, rt,
  { msg: 'x' }, stackOf);
eq(textNulls.indexOf('VersionName=null') > 0, true, 'versionName=null → "VersionName=null"');
eq(textNulls.indexOf('Signature=null') > 0, true, '签名取不到 → "Signature=null"');

// ── formatThrowable：主异常 + 逐个 cause ──
const causeChain = { msg: 'outer', cause: { msg: 'inner', cause: null } };
const fmt = Crash.formatThrowable(causeChain, stackOf, (t) => t.cause);
eq(fmt.indexOf('java.lang.Error: outer') >= 0, true, '先输出主异常');
eq(fmt.indexOf('java.lang.Error: inner') > fmt.indexOf('java.lang.Error: outer'), true,
  '再输出 cause（顺序：主 → cause）');
const fmtNoCause = Crash.formatThrowable({ msg: 'solo' }, stackOf);
eq(fmtNoCause.split('java.lang.Error').length - 1, 1, '无 cause → 只有一段栈');
// 多级 cause 链
const deep = { msg: 'a', cause: { msg: 'b', cause: { msg: 'c', cause: null } } };
const fmtDeep = Crash.formatThrowable(deep, stackOf, (t) => t.cause);
eq(['a', 'b', 'c'].every((m) => fmtDeep.indexOf('Error: ' + m) >= 0), true, '三级 cause 链全部输出');

// ── saveCrashLog 编排（注入 writeText/deleteFile）──
(async () => {
  const written = [];
  const deleted = [];
  const okPath = await Crash.saveCrashLog({ msg: 'x' }, pkg, mkDevice(), mkMem(), () => 'SIG', rt,
    stackOf, async (p, t) => { written.push([p, t.length]); }, (p) => deleted.push(p),
    () => 1700000000000);
  eq(okPath !== null, true, 'saveCrashLog 成功 → 返回路径');
  eq(/crash-.*\.log$/.test(okPath), true, '…文件名 crash-<时间>.log');
  eq(written.length, 1, '…writeText 调用一次');
  eq(deleted.length, 0, '…成功时不删文件');

  // 写失败 → 删半截文件并返回 null
  const badPath = await Crash.saveCrashLog({ msg: 'x' }, pkg, mkDevice(), mkMem(), () => 'SIG', rt,
    stackOf, async () => { throw new Error('disk full'); }, (p) => deleted.push(p),
    () => 1700000000000);
  eq(badPath, null, '写失败 → 返回 null');
  eq(deleted.length, 1, '…**删掉半截文件**（上游 catch 里 file.delete()）');

  // 崩溃目录存在性（已初始化 → 有外部目录）
  eq(AppConfig.getExternalCrashDir() !== null, true, 'AppConfig 初始化后 getExternalCrashDir 非 null');
  eq(AppConfig.getExternalCrashDir().endsWith('/crash'), true, '…目录以 /crash 结尾');

  console.log('\n' + (fail === 0 ? 'ALL PASS' : fail + ' FAILED'));
  process.exit(fail === 0 ? 0 : 1);
})();
