# 跑所有模块的 TS 单测（第二道编译门）+ 一行汇总
#
# 为什么需要这道门（Lead 已采纳为项目规则）：
#   · 仓库构建（build_hap / hvigor）只编译「从 @Entry 可达的闭包」→ 漏掉"不进图但被测试引用"的文件
#   · TS 单测编译（本脚本）按测试实际 import 编译 → 漏掉"进图但无测试"的文件
#   **只跑一条，另一条的假绿就没人发现。**
#
# 设计（两次失败尝试的结论，别重犯）：
#   ✗ 一次 tsc 编译整棵 hippo/ 树       → 带进别的模块的 ArkTS 专有语法，5276 个无关错误
#   ✗ 按模块"联合编译一次"再跑 test.js  → **各 run 脚本的 out 目录布局不一样**
#        （老测试如 settings-flush / thread 期望 `OUT/Settings.js` 扁平布局，
#          新测试如 crash 期望 `OUT/ehviewer/Crash.js` 分层布局）→ 一个 out 目录服务不了两种
#   ✓ **并行执行各自的 run*.ps1**：每个单元仍是它自己的编译+运行，
#      给每个 worker 一个独立的 `%TEMP%` 目录做隔离（node_modules 用 junction 共享），
#      从而既能并行、又完全保留各脚本原有语义。
#
# 用法：
#   pwsh -File scripts/run_all_tests.ps1                     # 并行（默认 4 worker）
#   ⚠️ **外部进程（手工探针 / 另一个 run_all_tests 实例）不得写 worker 目录** %TEMP%\rasts-worker-*：
#      两个进程同时往同一 	scheck\src 拷整棵树 + 同一 out* 跑 tsc → 文件锁 → 挂死（实测）。
#   ⚠️ 实测 6 worker 时偶发单个单元假失败（6 个 tsc 并发吃内存 → 编译静默失败 → node 找不到 .js）；
#      单跑该单元必过。默认降到 4；机器强可显式 -Workers 6。
#   pwsh -File scripts/run_all_tests.ps1 -Workers 1          # 串行（等价旧行为）
#   pwsh -File scripts/run_all_tests.ps1 -Module core-runtime
#   pwsh -File scripts/run_all_tests.ps1 -Quiet -Uncovered   # 一行 + 未覆盖清单
#   pwsh -File scripts/run_all_tests.ps1 -List               # 只列清单不跑
#
# 判据（不是"通过率"，是"覆盖面"）：
#   · 断言总数 = 所有单元输出里 `PASS  ` 行数之和
#   · 失败数   = `FAIL  ` 行数之和 + 退出码非 0 的次数
#   · 未覆盖面 = src/main/ets/hippo 下没有被任何 run 脚本 Copy、也没有被任何 test 文件引用的 .ets
param(
  [string]$Module = '',
  [switch]$Quiet,
  [switch]$Uncovered,
  [switch]$List,
  [switch]$Summary,
  [int]$Workers = 4,
  [int]$TimeoutSec = 600
)

$ErrorActionPreference = 'Continue'
$root = (git -C $PSScriptRoot rev-parse --show-toplevel) -replace '/', '\'
$testRoot = Join-Path $root 'harmony\entry\src\test'
$hippoRoot = Join-Path $root 'harmony\entry\src\main\ets\hippo'
$artifacts = Join-Path $root 'artifacts'
$tscheck = Join-Path $env:TEMP 'tscheck'
New-Item -ItemType Directory -Force -Path $artifacts | Out-Null

if (-not (Test-Path $testRoot)) { Write-Host "FAIL: 找不到测试目录 $testRoot"; exit 2 }
if (-not (Test-Path (Join-Path $tscheck 'node_modules\typescript'))) {
  Write-Host "FAIL: 找不到 $tscheck\node_modules\typescript（tscheck 环境未就绪）"
  exit 2
}

# 全仓 test 目录（用于"分母"）：`shared/` 这类**只有占位目录、没有 run 脚本**的模块也算进去，
# 否则输出 `1/1 modules` 会让人以为全仓只有 1 个模块（实际 7 个，其中 1 个无测试）。
$allTestDirs = Get-ChildItem $testRoot -Directory | ForEach-Object { $_.Name } | Sort-Object
$modules = $allTestDirs
$moduleFiltered = $false
if ($Module) {
  $modules = $modules | Where-Object { $_ -eq $Module }
  if (-not $modules) { Write-Host "FAIL: 没有模块 $Module（现有: $($allTestDirs -join ', ')）"; exit 2 }
  $moduleFiltered = $true
}

# 没有任何 run*.ps1 的模块（分母里要单独说清，否则"没跑"会被误读成"没测"）
$noTestDirs = @()
foreach ($d in $allTestDirs) {
  $hasRun = (Get-ChildItem (Join-Path $testRoot $d) -Filter 'run*.ps1' -File -ErrorAction SilentlyContinue | Measure-Object).Count -gt 0
  if (-not $hasRun) { $noTestDirs += $d }
}

# ── 收集单元（每个 run*.ps1 是一个单元）──────────────────────────────────────
$units = @()
foreach ($m in $modules) {
  $dir = Join-Path $testRoot $m
  $runs = Get-ChildItem $dir -Filter 'run*.ps1' -File -ErrorAction SilentlyContinue | Sort-Object Name
  foreach ($r in $runs) { $units += @{ Module = $m; Name = $r.Name; Path = $r.FullName } }
}
if ($units.Count -eq 0) { Write-Host "FAIL: 没有找到任何 run*.ps1"; exit 2 }

if ($List) {
  $units | ForEach-Object { Write-Host ("  {0}/{1}" -f $_.Module, $_.Name) }
  $scope = if ($moduleFiltered) { "（已按 -Module $Module 过滤）" } else { '' }
  Write-Host ("共 {0} 个单元；模块 {1}/{2}{3}；无 test 的模块: {4}" -f `
    $units.Count, $modules.Count, $allTestDirs.Count, $scope,
    $(if ($noTestDirs.Count -gt 0) { $noTestDirs -join ',' } else { '无' }))
  exit 0
}

$logPath = Join-Path $artifacts ('run-all-tests-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '.log')
$log = New-Object System.Collections.Generic.List[string]
$log.Add("units=$($units.Count) modules=$($modules.Count)/$($allTestDirs.Count) workers=$Workers filtered=$moduleFiltered")
Write-Host ("  并行跑 {0} 个单元（{1} worker）…" -f $units.Count, $Workers)

# ── 每个 worker 一个独立 TEMP（node_modules 用 junction 共享，避免重复拷贝）────
# ⚠️ **必须预置整棵 hippo 树**：各 run 脚本只 Copy 自己的几个文件，其余依赖一直是从
#    `%TEMP%\tscheck\src` 里**别人早先拷进去的**文件解析来的（隐式共享状态）。
#    新 worker 若是空 src，那些依赖就解析不到 → tsc 报一堆 Cannot find module。
#    预置后：每脚本的 Copy-Item 仍会覆盖自己的文件（语义不变），而依赖都能找到。
. (Join-Path $PSScriptRoot 'lib\sync_hippo.ps1')

$runWorkerPrefix = "rasts-worker-$PID-"

function InitializeWorker([int]$i) {
  $wd = Join-Path $env:TEMP ($runWorkerPrefix + $i)
  $inner = Join-Path $wd 'tscheck'
  $nm = Join-Path $inner 'node_modules'
  if (-not (Test-Path $nm)) {
    New-Item -ItemType Directory -Force -Path $inner | Out-Null
    cmd /c "mklink /J `"$nm`" `"$(Join-Path $tscheck 'node_modules')`"" | Out-Null
    if (-not (Test-Path $nm)) { Copy-Item -Recurse -Force (Join-Path $tscheck 'node_modules') $nm }
  }
  $srcHippo = Join-Path $inner 'src\hippo'
  Sync-HippoTree -SrcHippo $hippoRoot -DstHippo $srcHippo
  return $wd
}

$workerDirs = @()
for ($i = 0; $i -lt $Workers; $i++) { $workerDirs += (InitializeWorker $i) }

# ── 调度：最多 Workers 个并发 ─────────────────────────────────────────────────
$results = @{}
$queue = New-Object System.Collections.Queue
$units | ForEach-Object { $queue.Enqueue($_) }
$running = @{}

function StartUnit($unit, $workerTemp) {
  return Start-Job -ScriptBlock {
    param($path, $tempDir)
    $env:TEMP = $tempDir
    $env:TMP = $tempDir
    $ErrorActionPreference = 'Continue'
    # **先清掉这个 worker 的产物目录**（out / out5 / out9 / out11 …）。
    # 为什么：历史 runner 里有 42/49 个把 `tsc` 输出 `| Out-Null` 吞了，
    # 于是"源码编译不过"时 node 会去跑**上一次 emit 的旧 JS** → 断言全绿。
    # 清空产物后**旧 JS 不存在**，这个失效模式就不可能发生（node 会直接找不到模块而失败）。
    foreach ($outDir in (Get-ChildItem (Join-Path $tempDir 'tscheck') -Directory -Filter 'out*' -ErrorAction SilentlyContinue)) {
      if (Test-Path $outDir.FullName) {
        try { [System.IO.Directory]::Delete($outDir.FullName, $true) } catch { }
      }
    }
    $o = & pwsh -NoProfile -File $path 2>&1 | Out-String
    return @{ Out = $o; Code = $LASTEXITCODE }
  } -ArgumentList $unit.Path, $workerTemp
}

# $workerIdx 计数器分配 worker 目录是**错的**：unit1 先完成时 worker0 会被立刻分给 unit7，
# 而别的 worker 可能还在跑 —— 一旦把同一个目录并发给两个 unit，两个 tsc 就写同一个 out11
# （Windows 文件锁 → 卡死；实测跑了 25 分钟只完成 17 个就僵住）。
# 正确做法：**空闲目录池**，只有跑完的 unit 才把目录还回来。
$freeWorkers = New-Object System.Collections.Queue
$workerDirs | ForEach-Object { $freeWorkers.Enqueue($_) }

while ($queue.Count -gt 0 -or $running.Count -gt 0) {
  while ($queue.Count -gt 0 -and $running.Count -lt $Workers -and $freeWorkers.Count -gt 0) {
    $u = $queue.Dequeue()
    $wd = $freeWorkers.Dequeue()
    $job = StartUnit $u $wd
    $running[$job.Id] = @{ Job = $job; Unit = $u; Start = Get-Date; Worker = $wd }
  }
  if ($running.Count -eq 0) { break }
  $done = Wait-Job -Job ($running.Values | ForEach-Object { $_.Job }) -Any -Timeout 30
  if (-not $done) {
    foreach ($k in @($running.Keys)) {
      $el = ((Get-Date) - $running[$k].Start).TotalSeconds
      if ($el -gt $TimeoutSec) {
        $j = $running[$k].Job
        Stop-Job $j -ErrorAction SilentlyContinue
        $results[$k] = @{ Unit = $running[$k].Unit; Out = "TIMEOUT after ${TimeoutSec}s"; Code = 124 }
        Remove-Job $j -Force -ErrorAction SilentlyContinue
        $freeWorkers.Enqueue($running[$k].Worker)
        $running.Remove($k)
      }
    }
    continue
  }
  foreach ($j in @($done)) {
    $res = Receive-Job $j
    $k = $j.Id
    $u = $running[$k].Unit
    $results[$k] = @{ Unit = $u; Out = "$($res.Out)"; Code = [int]$res.Code }
    Remove-Job $j -Force -ErrorAction SilentlyContinue
    $freeWorkers.Enqueue($running[$k].Worker)   # 归还目录（必须在本 unit 真正跑完之后）
    $el = ((Get-Date) - $running[$k].Start).TotalSeconds
    $running.Remove($k)
    # 进度可见：长跑不能"闷着"（上一版跑了 25 分钟没有任何输出，看不出是在跑还是卡死）
    if (-not $Quiet -and -not $Summary) {
      $p0 = ([regex]::Matches("$($res.Out)", '(?m)^\s*PASS\s')).Count
      Write-Host ("  [{0}/{1}] {2}/{3} exit={4} PASS={5} ({6:N1}s)" -f `
        ($results.Count), $units.Count, $u.Module, $u.Name, $res.Code, $p0, $el)
    }
  }
}

# ── 汇总 ──────────────────────────────────────────────────────────────────────
$byModule = @{}
$totalAssert = 0; $totalFail = 0; $failDetails = @(); $assertUncounted = 0
foreach ($k in $results.Keys) {
  $r = $results[$k]
  $m = $r.Unit.Module
  $p = ([regex]::Matches($r.Out, '(?m)^\s*PASS\s')).Count
  $f = ([regex]::Matches($r.Out, '(?m)^\s*FAIL\s')).Count
  # 各模块的测试格式不同：core-runtime 打 `PASS  ...`；storage-db / ui-scene 打中文「全部通过，N 个断言」
  # （且它们的输出在跨进程捕获后可能已乱码）。PASS 计到 0 但退出码 0 时，**不能报成"0 个断言"**
  # —— 那会让人误以为这个单元没断言。改为计一笔 `n/a`，单独在汇总里报数。
  if ($p -eq 0 -and $f -eq 0 -and $r.Code -eq 0) {
    $assertUncounted++
  }
  if (-not $byModule.ContainsKey($m)) { $byModule[$m] = @{ Assert = 0; Fail = 0; Units = 0; Bad = @(); Nc = 0 } }
  $byModule[$m].Assert += $p
  $byModule[$m].Units += 1
  if ($p -eq 0 -and $f -eq 0 -and $r.Code -eq 0) { $byModule[$m].Nc += 1 }
  if ($r.Code -ne 0 -or $f -gt 0) {
    $byModule[$m].Fail += [Math]::Max($f, 1)
    $byModule[$m].Bad += $r.Unit.Name
    $failDetails += ("  FAIL  {0}/{1}  exit={2}  PASS={3} FAIL={4}" -f $m, $r.Unit.Name, $r.Code, $p, $f)
  }
  $totalAssert += $p
  if ($r.Code -ne 0 -or $f -gt 0) { $totalFail += [Math]::Max($f, 1) }
  $log.Add("=== $m / $($r.Unit.Name) (exit=$($r.Code)) ===")
  $log.Add($r.Out)
}

$moduleLines = @()
$okModules = 0
foreach ($m in ($byModule.Keys | Sort-Object)) {
  $e = $byModule[$m]
  if ($e.Bad.Count -eq 0) {
    $okModules++
    $moduleLines += ("  OK    {0} : {1} 单元 / {2} 断言" -f $m, $e.Units, $e.Assert)
  } else {
    $moduleLines += ("  FAIL  {0} : {1} 单元 / {2} 断言 / 失败 {3}（{4}）" -f $m, $e.Units, $e.Assert, $e.Fail, ($e.Bad -join ', '))
  }
}
foreach ($m in $modules) {
  if (-not $byModule.ContainsKey($m)) { $moduleLines += "  SKIP  $m（无 run*.ps1）" }
}

# ── 覆盖面 ────────────────────────────────────────────────────────────────────
$allEts = Get-ChildItem $hippoRoot -Recurse -File -Filter '*.ets' |
  ForEach-Object { $_.FullName.Substring($hippoRoot.Length).TrimStart('\') -replace '\\', '/' }
$evidenced = New-Object System.Collections.Generic.HashSet[string]
foreach ($sf in (Get-ChildItem $testRoot -Recurse -Include 'run*.ps1', '*.test.js', '*.test.ets' -File -ErrorAction SilentlyContinue)) {
  $txt = Get-Content $sf.FullName -Raw -ErrorAction SilentlyContinue
  if (-not $txt) { continue }
  foreach ($mm in [regex]::Matches($txt, 'main[\\/]ets[\\/]hippo[\\/](?<p>[A-Za-z0-9_.\-/\\]+?)\.(?:ets|ts)')) {
    [void]$evidenced.Add((($mm.Groups['p'].Value -replace '\\', '/')))
  }
  foreach ($mm in [regex]::Matches($txt, "hippo/(?<p>[A-Za-z0-9_./\-]+?)\.(?:ts|ets|js)")) {
    [void]$evidenced.Add($mm.Groups['p'].Value)
  }
  foreach ($mm in [regex]::Matches($txt, "'(?<p>[A-Za-z0-9_]+)\.js'")) {
    [void]$evidenced.Add($mm.Groups['p'].Value)
  }
}
$uncoveredList = @()
foreach ($e in $allEts) {
  $noExt = $e -replace '\.ets$', ''
  $leaf = ($noExt -split '/')[-1]
  $hit = $evidenced.Contains($noExt) -or $evidenced.Contains($leaf)
  if (-not $hit) {
    foreach ($ev in $evidenced) { if ($ev.EndsWith('/' + $leaf) -or $ev -eq $leaf) { $hit = $true; break } }
  }
  if (-not $hit) { $uncoveredList += $e }
}

# ── test-only 检测（V-03 的教训）──────────────────────────────────────────────
# 判据：一个 .ets **被测试 import** 但**生产代码 0 处 import** → 它是 test-only（镜像）。
# 理由：test-only 文件的断言只证明"镜像正确"，不证明"生产正确"。
# 实现：① 收集生产代码（hippo/ 下除 __probe__ 外）里的 import 目标 basename
#       ② 收集测试引用的 basename ③ 差集即为 test-only
$prodImported = New-Object System.Collections.Generic.HashSet[string]
foreach ($sf in (Get-ChildItem $hippoRoot -Recurse -File -Filter '*.ets' | Where-Object { $_.FullName -notlike '*\__probe__\*' })) {
  $txt = Get-Content $sf.FullName -Raw -ErrorAction SilentlyContinue
  if (-not $txt) { continue }
  foreach ($mm in [regex]::Matches($txt, "from\s+'(?<p>[^']+)'")) {
    $spec = $mm.Groups['p'].Value
    $leaf = ($spec -split '/')[-1]
    if ($leaf) { [void]$prodImported.Add($leaf) }
  }
}
$testOnlyList = @()
foreach ($e in $allEts) {
  $leaf = (($e -replace '\.ets$', '') -split '/')[-1]
  $tested = $evidenced.Contains(($e -replace '\.ets$', '')) -or $evidenced.Contains($leaf)
  if ($tested -and -not $prodImported.Contains($leaf)) {
    $testOnlyList += $e
  }
}

# ── 未覆盖清单落盘（供后续补测试查）──────────────────────────────────────────
$uncoveredPath = Join-Path $artifacts 'tests-uncovered.txt'
$uLines = @("# 未覆盖的 .ets（$($uncoveredList.Count)/$($allEts.Count)）—— 由 scripts/run_all_tests.ps1 生成 $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')")
$uLines += $uncoveredList
$uLines += ''
$uLines += "# test-only 的 .ets（$($testOnlyList.Count)）—— 只被测试引用、生产 0 处 import；其断言只证明镜像正确"
$uLines += $testOnlyList
Set-Content -Path $uncoveredPath -Value $uLines -Encoding utf8NoBOM

$log.Add('')
$log.Add('=== 汇总 ===')
$log.AddRange([string[]]$moduleLines)
if ($failDetails.Count -gt 0) { $log.AddRange([string[]]$failDetails) }
$log.Add("未覆盖 $($uncoveredList.Count)/$($allEts.Count) 个 .ets")
$log.Add("test-only $($testOnlyList.Count) 个 .ets")
if ($Uncovered) { $log.AddRange([string[]]$uncoveredList) }
if ($testOnlyList.Count -gt 0) { $log.AddRange([string[]]$testOnlyList) }
Set-Content -Path $logPath -Value $log -Encoding utf8NoBOM

if (-not $Quiet -and -not $Summary) {
  $moduleLines | ForEach-Object { Write-Host $_ }
  $failDetails | ForEach-Object { Write-Host $_ -ForegroundColor Red }
  if ($Uncovered) {
    Write-Host "未覆盖 $($uncoveredList.Count)/$($allEts.Count) 个 .ets:"
    $uncoveredList | ForEach-Object { Write-Host "  $_" }
  }
}
if ($testOnlyList.Count -gt 0 -and -not $Summary) {
  Write-Host "test-only $($testOnlyList.Count) 个 .ets（断言只证明镜像正确，不证明生产正确）:"
  $testOnlyList | ForEach-Object { Write-Host "  $_" }
}

$verdict = if ($totalFail -eq 0) { 'OK:  ' } else { 'FAIL:' }
# 模块分母写清三件事：通过的 / **全仓总数** / 其中"无 test 的模块"，
# 再加过滤标记 —— 否则 `1/1 modules` 会被误读成"全仓只有 1 个模块"（实际 7 个）。
$scopeTail = if ($moduleFiltered) {
  " (filtered to $Module; 全仓 $($allTestDirs.Count) 个模块)"
} elseif ($noTestDirs.Count -gt 0) {
  " ($($noTestDirs.Count) 无 test: $($noTestDirs -join ','))"
} else { '' }
$assertTail = if ($assertUncounted -gt 0) { " (+$assertUncounted units assertions-n/a)" } else { '' }
Write-Host ("{0} {1}/{2} modules{3}, {4} units, {5} assertions{6}, {7} failed, uncovered={8}/{9}, test-only={10}  (log: {11})" -f `
  $verdict, $okModules, $allTestDirs.Count, $scopeTail, $units.Count, $totalAssert, $assertTail, $totalFail,
  $uncoveredList.Count, $allEts.Count, $testOnlyList.Count, (Split-Path $logPath -Leaf))

# Clean up per-PID isolated worker sandboxes (remove node_modules junction first before deleting dir)
foreach ($wd in $workerDirs) {
  $nm = Join-Path $wd 'tscheck\node_modules'
  if (Test-Path $nm) { cmd /c rmdir "$nm" 2>&1 | Out-Null }
  if (Test-Path $wd) {
    try { [System.IO.Directory]::Delete($wd, $true) } catch { }
  }
}

if ($totalFail -gt 0) { exit 1 }
exit 0
