# TS 单测的编译门（复用库，被各 run*.ps1 dot-source 使用）
#
# 为什么需要（今天第三次"验证工具自己不验证"）：
#   `node tsc ... | Out-Null` 把编译错误吞掉 → 即使源码编不过，node 仍然会去跑
#   **上一次 emit 出来的旧 JS** → 断言全绿。症状：**改了源码但断言结果不变**。
#
# 两道判据：
#   ① 编译失败必须失败：只看**本 runner 的根文件**的错误（仓库里另有别的模块的已知噪音，
#      一并当失败会让所有 runner 常红 → 人们会把这个门关掉）
#   ② 产物必须比源码新：outDir 里每个 .js 的 mtime 必须 >= 对应 .ts 的 mtime；
#      否则说明 emit 没发生（tsc 早退 / 增量缓存 / 上一步失败），跑的是旧产物
#
# 用法（在 run-*.ps1 里）：
#   . "$(git -C $PSScriptRoot rev-parse --show-toplevel)/scripts/lib/tsc_gate.ps1"
#   $ok = Invoke-TscGate -WorkDir $d -OutDir "out11" -RootTs @("src/hippo/ehviewer/Settings.ts")
#   if (-not $ok) { exit 1 }

function Invoke-TscGate {
  param(
    [Parameter(Mandatory = $true)][string]$WorkDir,      # tsc 的工作目录（通常是 $env:TEMP\tscheck）
    [Parameter(Mandatory = $true)][string]$OutDir,       # 相对 WorkDir 的 outDir（如 "out11"）
    [Parameter(Mandatory = $true)][string[]]$RootTs,     # 本次编译的根 .ts（相对 WorkDir）
    [string[]]$ExtraArgs = @(),
    [switch]$Quiet
  )

  $tsc = Join-Path $WorkDir 'node_modules\typescript\bin\tsc'
  if (-not (Test-Path $tsc)) {
    Write-Host "FAIL[tsc-gate]: 找不到 $tsc"
    return $false
  }

  $baseArgs = @(
    '--noEmit', 'false',
    '--outDir', $OutDir,
    '--rootDir', 'src',
    '--strict', '--skipLibCheck',
    '--module', 'commonjs', '--target', 'es2020', '--moduleResolution', 'node',
    '--noUnusedLocals', 'false', '--noUnusedParameters', 'false', '--noImplicitAny', 'false'
  )

  Push-Location $WorkDir
  $out = & node $tsc @baseArgs @ExtraArgs @RootTs 2>&1 | Out-String
  $code = $LASTEXITCODE
  Pop-Location

  # ── 判据 ①：只看根文件的错误 ────────────────────────────────────────────────
  $rootsPattern = ($RootTs | ForEach-Object { [regex]::Escape((Split-Path $_ -Leaf)) }) -join '|'
  $myErrors = ($out -split "`n") | Where-Object { $_ -match 'error TS' -and $_ -match $rootsPattern }
  if ($myErrors) {
    Write-Host "FAIL[tsc-gate]: 根文件编译报错（共 $($myErrors.Count) 条，列前 5）:"
    $myErrors | Select-Object -First 5 | ForEach-Object { Write-Host "  $($_.Trim())" }
    return $false
  }
  $otherErrors = (($out -split "`n") | Where-Object { $_ -match 'error TS' }).Count
  if (-not $Quiet -and $otherErrors -gt 0) {
    Write-Host "  note[tsc-gate]: 另有 $otherErrors 条其它文件的已知噪音（不计入本 runner）"
  }

  # ── 判据 ②：产物必须比源码新（检出"跑的是旧 JS"）─────────────────────────────
  $stale = @()
  foreach ($rel in $RootTs) {
    $tsAbs = Join-Path $WorkDir $rel
    if (-not (Test-Path $tsAbs)) { continue }
    $relInSrc = $rel -replace '^src[\\/]', ''
    $jsAbs = Join-Path (Join-Path $WorkDir $OutDir) (($relInSrc -replace '\.ts$', '.js'))
    if (-not (Test-Path $jsAbs)) {
      $stale += "$relInSrc → .js 未产出"
      continue
    }
    try {
      $jsTime = (Get-Item $jsAbs -ErrorAction Stop).LastWriteTime
      $tsTime = (Get-Item $tsAbs -ErrorAction Stop).LastWriteTime
    } catch {
      $stale += "$relInSrc → .js 被并发清理（out 目录共享）: $($_.Exception.Message)"
      continue
    }
    if ($jsTime -lt $tsTime) {
      $stale += ("{0} 比源码旧（js={1:HH:mm:ss} ts={2:HH:mm:ss}）" -f $relInSrc, $jsTime, $tsTime)
    }
  }
  if ($stale.Count -gt 0) {
    Write-Host "FAIL[tsc-gate]: 产物不是本次编译的（跑的是旧 JS）:"
    $stale | Select-Object -First 5 | ForEach-Object { Write-Host "  $_" }
    return $false
  }

  if (-not $Quiet) { Write-Host "  ok[tsc-gate]: 根文件无错、产物新鲜（$($RootTs.Count) 个根）" }
  return $true
}
