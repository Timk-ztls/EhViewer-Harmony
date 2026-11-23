<#
  run.ps1 —— net-parse 纯逻辑单测跑批（C-10：harmony/entry/src/test/<module>/）

  做法（不是"写一份 JS 副本再测"）：
    1. 把 harmony/entry/src/main/ets/hippo 整棵树机械复制成 .ts（只去掉 @Observed 等 UI 装饰器）
       —— 保持目录结构，这样 .ets 里 `../../../okhttp/index` 之类的相对 import 原样可用
    2. 把 tests/*.test.ts 放进「被测文件所在目录」（默认 client/data），相对 import 与仓库一致
    3. 用 DevEco SDK 自带 tsc 只编译测试入口（tsc 自动跟随 import 拉入依赖，
       不被 import 的文件不参与编译，避免把 @ohos.* 依赖全拖进来）
       + ohos-stubs.d.ts 提供 @ohos.* 的类型桩
    4. node 执行

  用法：
    pwsh -File run.ps1                     # 跑全部 tests/*.test.ts
    pwsh -File run.ps1 -Test roundtrip     # 只跑名字含 roundtrip 的
    pwsh -File run.ps1 -Clean              # 清 out/ 后重跑

  依赖：node + tsc（优先 SDK 自带，见 $TscCandidates；找不到回退 hvigor 缓存）
#>
[CmdletBinding()]
param(
  [string]$Root = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..\..\..')).Path,
  # 被测树根（整棵树都会被机械转成 .ts）
  [string]$EtsRoot = '',
  # 测试文件被放到哪个子目录（相对 $EtsRoot），即被测文件所在目录
  [string]$TestHome = 'ehviewer\client\data',
  [string]$Test = '',
  [switch]$Clean
)

$ErrorActionPreference = 'Stop'
$here = $PSScriptRoot
$outRoot = Join-Path ([IO.Path]::GetTempPath()) ('net-parse-tests-' + $PID)
$genRoot = Join-Path $outRoot 'gen'
$jsRoot = Join-Path $outRoot 'js'

if (-not $EtsRoot) {
  $EtsRoot = Join-Path $Root 'harmony\entry\src\main\ets\hippo'
}
if (-not (Test-Path $EtsRoot)) { throw "被测树不存在：$EtsRoot" }

# ---- tsc ----
$TscCandidates = @(
  (Join-Path $env:LOCALAPPDATA 'Huawei\Sdk\20\ets\build-tools\ets-loader\node_modules\typescript\lib\tsc.js'),
  (Join-Path $env:LOCALAPPDATA 'Huawei\Sdk\20\ets\build-tools\ets-loader\node_modules\typescript\bin\tsc'),
  (Join-Path $env:USERPROFILE 'AppData\Local\Huawei\Sdk\20\ets\build-tools\ets-loader\node_modules\typescript\lib\tsc.js')
)
$tsc = $null
foreach ($c in $TscCandidates) { if (Test-Path $c) { $tsc = $c; break } }
if (-not $tsc) {
  $cacheRoot = Join-Path $Root '..\tools\hvigor-home\project_caches'
  if (Test-Path $cacheRoot) {
    $found = Get-ChildItem $cacheRoot -Recurse -Filter 'tsc.js' -ErrorAction SilentlyContinue |
      Where-Object { $_.FullName -match 'typescript\\lib\\tsc\.js$' } | Select-Object -First 1
    if ($found) { $tsc = $found.FullName }
  }
}
if (-not $tsc) {
  throw @"
找不到 tsc。请安装 DevEco Studio（或 command-line-tools），期望路径：
  %LOCALAPPDATA%\Huawei\Sdk\20\ets\build-tools\ets-loader\node_modules\typescript\lib\tsc.js
"@
}
$node = (Get-Command node -ErrorAction SilentlyContinue).Source
if (-not $node) { throw '找不到 node（请把 node 加入 PATH）' }

Remove-Item $genRoot, $jsRoot -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force -Path $genRoot, $jsRoot | Out-Null

Write-Host "tsc   : $tsc" -ForegroundColor Cyan
Write-Host "node  : $node" -ForegroundColor Cyan
Write-Host "被测树: $EtsRoot" -ForegroundColor Cyan

# ---- 1) 整棵树 .ets → .ts（只去 UI 装饰器）----
$genTree = Join-Path $genRoot 'hippo'
$copied = 0
Get-ChildItem $EtsRoot -Filter '*.ets' -Recurse | ForEach-Object {
  $rel = $_.FullName.Substring($EtsRoot.Length).TrimStart('\')
  $dst = Join-Path $genTree ($rel -replace '\.ets$', '.ts')
  $dir = Split-Path $dst -Parent
  if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
  $text = Get-Content $_.FullName -Raw
  $text = $text -replace '(?m)^\s*@(Observed|Component|Entry|State|Prop|Link|Provide|Consume|Builder|Styles|Extend|Watch|StorageLink|StorageProp|LocalStorageLink|LocalStorageProp)\b[^\r\n]*\r?\n', ''
  Set-Content -Path $dst -Value $text -NoNewline
  $copied++
}
Write-Host "`n▶ 生成 .ts：$copied 个" -ForegroundColor Cyan

# ---- 2) 测试文件放进被测目录 ----
$testSrc = Join-Path $here 'tests'
if (-not (Test-Path $testSrc)) { throw "缺少 tests/ 目录：$testSrc" }
$tests = Get-ChildItem $testSrc -Filter '*.test.ts'
if ($Test) { $tests = $tests | Where-Object { $_.BaseName -like "*$Test*" } }
if (-not $tests) { throw '没有匹配的测试文件' }
$testHomeDir = Join-Path $genTree $TestHome
if (-not (Test-Path $testHomeDir)) { New-Item -ItemType Directory -Force -Path $testHomeDir | Out-Null }
foreach ($t in $tests) { Copy-Item $t.FullName (Join-Path $testHomeDir $t.Name) -Force }

# ---- 3) 编译（只给测试入口 + ohos 桩；依赖由 tsc 跟随 import 拉入）----
$stub = Join-Path $here 'ohos-stubs.d.ts'
$inputs = @()
$inputs += ($tests | ForEach-Object { Join-Path $testHomeDir $_.Name })
if (Test-Path $stub) { $inputs += $stub }
Write-Host "`n▶ tsc（入口 $($tests.Count) 个 + 桩）" -ForegroundColor Cyan
$tscOut = & $node $tsc --target ES2020 --module commonjs --skipLibCheck --esModuleInterop --rootDir $genTree --outDir $jsRoot @inputs 2>&1
$tscExit = $LASTEXITCODE
foreach ($line in $tscOut) {
  if ("$line" -notmatch 'warning TS28014:.*@ohos\.net\.socket') {
    Write-Host $line
  }
}
if ($tscExit -ne 0) {
  $realDiags = $tscOut | Where-Object {
    $s = "$_".Trim()
    $s.Length -gt 0 -and $s -notmatch 'warning TS28014:.*@ohos\.net\.socket'
  }
  if ($tscExit -ne 2 -or $realDiags.Count -gt 0) {
    throw "tsc 编译失败 exit=$tscExit"
  }
}

# ---- 3.5) @ohos.* 运行时桩（node 无法解析平台模块；只实现测试真正用到的那几个）----
# 注意：node 按「完整包名」找包，'@ohos.util' 是一个目录名（不是 @ohos\util）
$shimRoot = Join-Path $jsRoot 'node_modules'
New-Item -ItemType Directory -Force -Path $shimRoot | Out-Null
$utilShim = @"
class TextEncoder {
  encodeInto(s) { return new Uint8Array(Buffer.from(s, 'utf8')); }
}
const TextDecoder = {
  create(enc) {
    return { decodeToString(u8) { return Buffer.from(u8).toString('utf8'); } };
  }
};
module.exports = { default: { TextEncoder, TextDecoder }, TextEncoder, TextDecoder };
"@
New-Item -ItemType Directory -Force -Path (Join-Path $shimRoot '@ohos.util') | Out-Null
Set-Content -Path (Join-Path $shimRoot '@ohos.util\index.js') -Value $utilShim -NoNewline
# @ohos.file.fs 用 node fs 实现（RequestBody.createFromFile 在测试里要真读文件）
$fsShim = @"
const nodeFs = require('fs');
const filePos = new Map();   // fd → 当前 filePointer（模拟内核语义）
const OpenMode = { READ_ONLY: 0, WRITE_ONLY: 1, READ_WRITE: 2, CREATE: 64, TRUNC: 512, APPEND: 1024 };
const AccessModeType = { READ: 4, WRITE: 2, EXECUTE: 1 };
const WhenceType = { SEEK_SET: 0, SEEK_CUR: 1, SEEK_END: 2 };
const fsImpl = {
  OpenMode,
  AccessModeType,
  WhenceType,
  statSync(p) { const s = (typeof p === 'number') ? nodeFs.fstatSync(p) : nodeFs.statSync(p); return { size: s.size, mtime: Math.floor(s.mtimeMs / 1000), isDirectory() { return s.isDirectory(); }, isFile() { return s.isFile(); } }; },
  accessSync(p) { return nodeFs.existsSync(p); },
  fsyncSync(fd) { try { nodeFs.fsyncSync(typeof fd === 'number' ? fd : fd.fd); } catch (e) { } },
  mkdirSync(p, recursion) { nodeFs.mkdirSync(p, { recursive: !!recursion }); },
  listFileSync(p) { return nodeFs.readdirSync(p); },
  rmdirSync(p) { nodeFs.rmSync(p, { recursive: true, force: true }); },
  readTextSync(p) { return nodeFs.readFileSync(p, 'utf8'); },
  openSync(p, mode) {
    let flags = 'r';
    const rw = (mode & OpenMode.READ_WRITE) !== 0;
    const wo = (mode & OpenMode.WRITE_ONLY) !== 0;
    const create = (mode & OpenMode.CREATE) !== 0;
    const trunc = (mode & OpenMode.TRUNC) !== 0;
    if (create && trunc) { flags = rw ? 'w+' : 'w'; }
    else if (create) { flags = nodeFs.existsSync(p) ? (rw ? 'r+' : 'w') : (rw ? 'w+' : 'w'); }
    else if (rw) { flags = 'r+'; }
    else if (wo) { flags = 'w'; }
    const fd = nodeFs.openSync(p, flags);
    filePos.set(fd, 0);
    return { fd, path: p, name: p.split(/[\\/]/).pop() };
  },
  // ArkTS 的 readSync 第一个参数是 file.fd（数字）；也兼容直接传句柄对象
  // 【SDK 语义】ReadOptions.offset 是「文件内起点 = filePointer + offset」，不是缓冲区下标
  // （见 docs/f3-readsync-ruling.md）。这里必须按 SDK 建模，否则 F-3 那类 bug 在测试里看不出来。
  readSync(fd, buf, opts) {
    const realFd = (typeof fd === 'number') ? fd : fd.fd;
    const b = Buffer.from(buf);
    const rel = (opts && typeof opts.offset === 'number' && opts.offset >= 0) ? opts.offset : 0;
    const len = (opts && typeof opts.length === 'number') ? opts.length : b.length;
    const base = filePos.has(realFd) ? filePos.get(realFd) : 0;
    const n = nodeFs.readSync(realFd, b, 0, len, base + rel);
    filePos.set(realFd, base + rel + n);
    return n;
  },
  writeSync(fd, buf, opts) {
    const realFd = (typeof fd === 'number') ? fd : fd.fd;
    const b = (typeof buf === 'string') ? Buffer.from(buf, 'utf8') : Buffer.from(buf);
    const len = (opts && typeof opts.length === 'number') ? opts.length : b.length;
    const base = filePos.has(realFd) ? filePos.get(realFd) : 0;
    const n = nodeFs.writeSync(realFd, b, 0, len, base);
    filePos.set(realFd, base + n);
    return n;
  },
  lseek(fd, offset, whence) { return fsImpl.lseekSync(fd, offset, whence); },
  lseekSync(fd, offset, whence) {
    const realFd = (typeof fd === 'number') ? fd : fd.fd;
    const base = filePos.has(realFd) ? filePos.get(realFd) : 0;
    const next = whence === 2 ? nodeFs.fstatSync(realFd).size + offset : (whence === 1 ? base + offset : offset);
    filePos.set(realFd, next);
    return next;
  },
  closeSync(f) { try { nodeFs.closeSync(typeof f === 'number' ? f : f.fd); } catch (e) { } },
  unlinkSync(p) { try { nodeFs.unlinkSync(p); } catch (e) { } },
  renameSync(oldPath, newPath) { nodeFs.renameSync(oldPath, newPath); },
  access(p) { return Promise.resolve(fsImpl.accessSync(p)); },
  mkdir(p, recursion) { fsImpl.mkdirSync(p, recursion); return Promise.resolve(); },
  stat(p) { return Promise.resolve(fsImpl.statSync(p)); },
  listFile(p) { return Promise.resolve(fsImpl.listFileSync(p)); },
  open(p, mode) { return Promise.resolve(fsImpl.openSync(p, mode)); },
  read(fd, buf, opts) { return Promise.resolve(fsImpl.readSync(fd, buf, opts)); },
  write(fd, buf, opts) { return Promise.resolve(fsImpl.writeSync(fd, buf, opts)); },
  close(f) { fsImpl.closeSync(f); return Promise.resolve(); },
  unlink(p) { fsImpl.unlinkSync(p); return Promise.resolve(); },
  rename(oldPath, newPath) { fsImpl.renameSync(oldPath, newPath); return Promise.resolve(); }
};
// tsc 在 import fs from '@ohos.file.fs' + xport = 时生成 __importDefault(require(...)).default，
// 所以既要让 module.exports 本身可用，也要给一个 .default 指向自己
module.exports = fsImpl;
module.exports.default = fsImpl;
"@
New-Item -ItemType Directory -Force -Path (Join-Path $shimRoot '@ohos.file.fs') | Out-Null
Set-Content -Path (Join-Path $shimRoot '@ohos.file.fs\index.js') -Value $fsShim -NoNewline
# @kit.PerformanceAnalysisKit：EhClient 的 hilog（node 侧无需真实日志，空实现）
$hilogShim = @"
const noop = () => {};
module.exports = { hilog: { debug: noop, info: noop, warn: noop, error: noop } };
"@
New-Item -ItemType Directory -Force -Path (Join-Path $shimRoot '@kit.PerformanceAnalysisKit') | Out-Null
Set-Content -Path (Join-Path $shimRoot '@kit.PerformanceAnalysisKit\index.js') -Value $hilogShim -NoNewline
$ohosHilogShim = @"
const noop = () => {};
const impl = { debug: noop, info: noop, warn: noop, error: noop };
module.exports = impl;
module.exports.default = impl;
"@
New-Item -ItemType Directory -Force -Path (Join-Path $shimRoot '@ohos.hilog') | Out-Null
Set-Content -Path (Join-Path $shimRoot '@ohos.hilog\index.js') -Value $ohosHilogShim -NoNewline
$fileUriShim = @"
const impl = { getUriFromPath(p) { return 'file://' + p; } };
module.exports = impl;
module.exports.default = impl;
"@
New-Item -ItemType Directory -Force -Path (Join-Path $shimRoot '@ohos.file.fileuri') | Out-Null
Set-Content -Path (Join-Path $shimRoot '@ohos.file.fileuri\index.js') -Value $fileUriShim -NoNewline
$httpShim = @"
const impl = {
  HttpDataType: { STRING: 0, OBJECT: 1, ARRAY_BUFFER: 2 },
  RequestMethod: { OPTIONS: 'OPTIONS', GET: 'GET', HEAD: 'HEAD', POST: 'POST', PUT: 'PUT', DELETE: 'DELETE', TRACE: 'TRACE', CONNECT: 'CONNECT' },
  createHttp() { throw new Error('http.createHttp mock not installed'); }
};
module.exports = impl;
module.exports.default = impl;
"@
New-Item -ItemType Directory -Force -Path (Join-Path $shimRoot '@ohos.net.http') | Out-Null
Set-Content -Path (Join-Path $shimRoot '@ohos.net.http\index.js') -Value $httpShim -NoNewline

$socketShim = @"
const impl = {
  ProxyTypes: { NONE: 0, SOCKS5: 1 },
  constructTCPSocketInstance() { throw new Error('socket.constructTCPSocketInstance mock not installed'); },
  constructTLSSocketInstance() { throw new Error('socket.constructTLSSocketInstance mock not installed'); }
};
module.exports = impl;
module.exports.default = impl;
"@
New-Item -ItemType Directory -Force -Path (Join-Path $shimRoot '@ohos.net.socket') | Out-Null
Set-Content -Path (Join-Path $shimRoot '@ohos.net.socket\index.js') -Value $socketShim -NoNewline

$connShim = @"
const impl = {
  async getAddressesByName(host) { return []; }
};
module.exports = impl;
module.exports.default = impl;
"@
New-Item -ItemType Directory -Force -Path (Join-Path $shimRoot '@ohos.net.connection') | Out-Null
Set-Content -Path (Join-Path $shimRoot '@ohos.net.connection\index.js') -Value $connShim -NoNewline
# ---- 4) 跑 ----
$failed = @()
foreach ($t in $tests) {
  $jsFile = Join-Path (Join-Path $jsRoot $TestHome) ($t.BaseName + '.js')
  if (-not (Test-Path $jsFile)) { throw "找不到编译产物：$jsFile" }
  Write-Host "`n▶ node $jsFile" -ForegroundColor Cyan
  & $node $jsFile
  if ($LASTEXITCODE -ne 0) { $failed += $t.Name }
}

if ($failed.Count -gt 0) {
  Write-Host "`n✗ 失败：$($failed -join ', ')" -ForegroundColor Red
  exit 1
}
Write-Host "`n✓ 全部通过（$($tests.Count) 个测试文件）" -ForegroundColor Green

