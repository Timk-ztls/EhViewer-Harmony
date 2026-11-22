# check_silent_failures.ps1
#
# 静默失败静态检查（CI 门禁用）。
#
# 检查三类形态：
#   A. 空 catch（单行 + 多行两种写法）           → 命中即失败（--gate）
#   B. 异步 fire-and-forget 吞失败               → 命中即失败（--gate）
#   C. 条件执行（if (依赖齐全) { 干活() }）        → 只报告，需人工判读（误报多）
#
# 用法：
#   pwsh -File scripts/check_silent_failures.ps1                     # 扫默认目录，报告
#   pwsh -File scripts/check_silent_failures.ps1 -Gate               # CI 模式：A/B 命中则 exit 1
#   pwsh -File scripts/check_silent_failures.ps1 -Root <dir>
#   pwsh -File scripts/check_silent_failures.ps1 -Format markdown
#
# 可选基线对比（不许新增）：
#   pwsh -File scripts/check_silent_failures.ps1 -Gate -Baseline <baseline.txt>
#   pwsh -File scripts/check_silent_failures.ps1 -Baseline <baseline.txt> -Update   # 修完后刷新基线
#
# 退出码：0 = 通过；1 = 命中 A 或 B（仅 -Gate 时）；2 = 参数/路径错误
#
# 已知抓不到（声明边界，避免"跑过 0 命中就等于干净"的误判）：
#   - 动态调用：`const p = pref.flush(); p.catch(...)` 拆成变量后无法静态识别
#   - 日志本身空转：打了 `hilog.warn` 但文案无上下文
#   - 语义型遗漏：`catch` 里 return 了错误值但把三种原因混成一个（需 review，脚本做不到）
#   - C 类只按文本匹配，误报率高，不入 CI 门禁
#   - 基线指纹不含行号（行号会漂移），因此**同一文件里出现完全相同的片段**会合并成 1 条；
#     同一个空 catch 片段重复 6 次时，第 7 次出现不会被判为"新增"（这是有意的近似）

[CmdletBinding()]
param(
  [string]$Root = '',
  [switch]$Gate,
  [ValidateSet('text', 'markdown')]
  [string]$Format = 'text',
  # 基线文件：CI 用「不许新增」而不是「必须清零」。指纹 = 相对路径|代码片段（不含行号，行号会漂移）。
  [string]$Baseline = '',
  # 把当前命中写进基线（修复后重新生成即可让基线下降）
  [switch]$Update
)

$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($Root)) {
  $repoRoot = Split-Path -Parent $PSScriptRoot
  $Root = Join-Path $repoRoot 'harmony/entry/src/main/ets'
}

if (-not (Test-Path $Root)) {
  Write-Error "路径不存在: $Root"
  exit 2
}

$files = Get-ChildItem $Root -Recurse -Filter *.ets -File
if ($files.Count -eq 0) {
  Write-Error "未找到 .ets 文件: $Root"
  exit 2
}

# ---------------- 0. 剥注释（所有检测前必做） ----------------
# 陷阱 32：任何扫源码的工具第一步必须剥注释，防止把注释里的示例代码误判为有效语句。
#
# 实现要求：**必须保持行号不变**（注释行替换为空行，而不是删除），否则报出的行号全错。
function Get-CodeLines {
  param([string[]]$Lines)

  $out = New-Object string[] $Lines.Count
  $inBlock = $false

  for ($i = 0; $i -lt $Lines.Count; $i++) {
    $line = $Lines[$i]
    $code = ''
    $pos = 0

    while ($pos -lt $line.Length) {
      if ($inBlock) {
        $end = $line.IndexOf('*/', $pos)
        if ($end -lt 0) { $pos = $line.Length; break }
        $inBlock = $false
        $pos = $end + 2
        continue
      }
      $lineComment = $line.IndexOf('//', $pos)
      $blockStart = $line.IndexOf('/*', $pos)

      if ($lineComment -ge 0 -and ($blockStart -lt 0 -or $lineComment -lt $blockStart)) {
        $code += $line.Substring($pos, $lineComment - $pos)
        $pos = $line.Length
        break
      }
      if ($blockStart -ge 0) {
        $code += $line.Substring($pos, $blockStart - $pos)
        $inBlock = $true
        $pos = $blockStart + 2
        continue
      }
      $code += $line.Substring($pos)
      $pos = $line.Length
    }

    $out[$i] = $code
  }

  return $out
}

# ---------------- A. 空 catch ----------------
# 单行：catch((_e: Error) => { });  |  .catch(e => {});
# 多行：.catch((_e: Error) => {        ← 本项目主流写法
#       });
function Find-EmptyCatch {
  param([System.IO.FileInfo[]]$Files)

  $found = [System.Collections.Generic.List[object]]::new()

  foreach ($f in $Files) {
    $raw = [System.IO.File]::ReadAllLines($f.FullName)
    $lines = Get-CodeLines -Lines $raw

    for ($i = 0; $i -lt $lines.Count; $i++) {
      $line = $lines[$i]

      # ---- 形态 A1：单行空 catch（传统 try/catch 与箭头函数都覆盖）
      if ($line -match '(catch\s*\([^)]*\)\s*\{\s*\}|\.catch\s*\([^)]*=>\s*\{\s*\}\s*\))\s*;?\s*$') {
        # 排除 `} catch (e) { ... }` 后紧跟内容的写法（行尾必须有 `}` 收口）
        $found.Add([pscustomobject]@{
            File    = $f.FullName
            Line    = $i + 1
            Kind    = 'A1 单行空 catch'
            Snippet = $raw[$i].Trim()
          })
        continue
      }

      # ---- 形态 A2：多行空 catch（`=> {` 换行后紧跟只有 `});`）
      if ($i + 1 -lt $lines.Count) {
        $opensArrowBody = ($line -match '\.catch\s*\(' ) -and ($line -match '=>\s*\{\s*$')
        $opensTryCatch = ($line -match 'catch\s*\([^)]*\)\s*\{\s*$') -and ($line -notmatch '\}\s*catch')
        if (($opensArrowBody -or $opensTryCatch) -and $lines[$i + 1].Trim() -eq '}') {
          $found.Add([pscustomobject]@{
              File    = $f.FullName
              Line    = $i + 1
              Kind    = 'A2 多行空 catch'
              Snippet = ($line.Trim() + ' ⏎ ' + $lines[$i + 1].Trim())
            })
        }
        elseif (($opensArrowBody -or $opensTryCatch) -and $lines[$i + 1].Trim() -eq '});') {
          $found.Add([pscustomobject]@{
              File    = $f.FullName
              Line    = $i + 1
              Kind    = 'A2 多行空 catch'
              Snippet = ($line.Trim() + ' ⏎ ' + $lines[$i + 1].Trim())
            })
        }
      }
    }
  }
  return $found
}

# ---------------- B. 异步 fire-and-forget ----------------
# 只抓"catch 体内 4 行内没有任何日志/抛出"的形态（A 类已覆盖全空的情况，
# 这里补"catch 里有注释但没日志"——注释不等于痕迹）。
function Find-SilentAsyncCatch {
  param([System.IO.FileInfo[]]$Files)

  $found = [System.Collections.Generic.List[object]]::new()
  # 痕迹判据（二选一即算有痕迹）：
  #   ① 任意方法调用 `xxx(`：封装方法也是痕迹 —— `Settings.logFlushError(key, e)`、
  #      `ExceptionUtils.throwIfFatal(e)`、`Analytics.recordException(e)` 都算。
  #      早期版本只认 hilog/throw 关键字，把"单点化的错误处理方法"误报成无痕迹。
  #   ② `throw` 语句
  # 反例（正确报出）：catch 体只有注释、只有赋值（`this.err = e;`）、完全为空。
  # 注意：不能简单用"任意方法调用"当痕迹 —— 实测会漏掉 9 处真问题
  # （catch 体里只有 `resolve()` / 清理 / 状态复位这类**不产生痕迹**的调用）。
  # 判据取"**有痕迹语义**的方法名 + throw"：logFlushError / hilog.error / recordException /
  # notifyXxx / console.error 都命中；resolve() / cleanup() / 赋值 不命中。
  #
  # ⚠ 第 20 种测量失真（2026-10-25，我踩的）：
  #   原模式 `\b\w*(log|Log|warn|Warn|error|Error|exception|Exception|notify|Notify|record|Record|print|Print|report|Report)\w*\s*\(`
  #   **没有 debug / info**。于是这两行被判成"无痕迹"：
  #       hilog.debug(0x0000, 'X', 'msg %{public}s', e.message)
  #       hilog.info(0x0000, 'X', 'msg')
  #   而 `hilog.error(` 恰好能靠 `error(` 这个以 `.` 为词边界的子串命中 ——
  #   **于是"用 error 级"能过闸门、"用 debug 级"过不了**，这是纯粹的误报方向偏差，
  #   而且它惩罚的是正确的写法（低危失败就该用 debug，避免刷屏）。
  #   实测两处误报：GetGalleryDetailListener.ets（hilog.debug）、Call.ets（hilog.debug）。
  $tracePattern = '\b\w*(log|Log|debug|Debug|info|Info|warn|Warn|error|Error|exception|Exception|notify|Notify|record|Record|print|Print|report|Report)\w*\s*\(|\bthrow\b'

  foreach ($f in $Files) {
    $raw = [System.IO.File]::ReadAllLines($f.FullName)
    $lines = Get-CodeLines -Lines $raw

    for ($i = 0; $i -lt $lines.Count; $i++) {
      if ($lines[$i] -notmatch '\.catch\s*\(') { continue }

      # 从 catch 行往后找到块结束（最多 30 行），统计块内是否有痕迹
      #
      # 第 19 种测量失真的修复（2026-10-25）：
      #   旧写法对「}).catch((e) => {」这种起始行同时含 '}' 和 '{' 的写法，
      #   depth 净变化为 0，于是进入循环后第一个内层 if 结束就 depth<=0 → 窗口截断，
      #   后面的 hilog 永远扫不到。实测 GalleryCommentsScene:112 的 catch 明明有三段式日志，
      #   却被报「B2 catch 无痕迹」。
      #   修：起点行**不计右括号**（那个 '}' 属于上一块的链式写法），并放宽窗口到 30 行。
      $depth = 0
      $body = [System.Collections.Generic.List[string]]::new()
      for ($j = $i; $j -lt [Math]::Min($i + 30, $lines.Count); $j++) {
        $body.Add($lines[$j])
        $open = ([regex]::Matches($lines[$j], '\{')).Count
        $close = ([regex]::Matches($lines[$j], '\}')).Count
        if ($j -eq $i) { $close = 0 }
        $depth += $open - $close
        if ($depth -le 0 -and $j -gt $i) { break }
      }

      $joined = ($body -join ' ')
      if ($joined -match $tracePattern) { continue }

      # 只报告"块内有内容但没有痕迹"或"块内只有注释"的
      $hasComment = $joined -match '//|/\*'
      $found.Add([pscustomobject]@{
          File    = $f.FullName
          Line    = $i + 1
          Kind    = $(if ($hasComment) { 'B1 catch 只有注释无痕迹' } else { 'B2 catch 无痕迹' })
          Snippet = $raw[$i].Trim()
        })
    }
  }
  return $found
}

# ---------------- C. 条件执行（只报告） ----------------
function Find-ConditionalExecution {
  param([System.IO.FileInfo[]]$Files)

  $found = [System.Collections.Generic.List[object]]::new()

  foreach ($f in $Files) {
    $raw = [System.IO.File]::ReadAllLines($f.FullName)
    $lines = Get-CodeLines -Lines $raw

    for ($i = 0; $i -lt $lines.Count; $i++) {
      $line = $lines[$i]
      if ($line -notmatch 'if \(.*!== null && .*!== null\) \{') { continue }

      $blk = ($lines[$i..([Math]::Min($i + 6, $lines.Count - 1))] -join ' ')
      if ($blk -match 'logW|logE|logI|hilog|throw |notify|Analytics\.') { continue }

      $found.Add([pscustomobject]@{
          File    = $f.FullName
          Line    = $i + 1
          Kind    = 'C 条件执行（需人工判读）'
          Snippet = $raw[$i].Trim()
        })
    }
  }
  return $found
}

$emptyCatch = Find-EmptyCatch -Files $files
$silentAsync = Find-SilentAsyncCatch -Files $files
$conditional = Find-ConditionalExecution -Files $files

# 去重：A 类（空 catch）已命中的位置不再由 B 类重复报告
$seen = @{}
$hardFailures = [System.Collections.Generic.List[object]]::new()
foreach ($h in @($emptyCatch)) {
  $key = "$($h.File):$($h.Line)"
  $seen[$key] = $true
  $hardFailures.Add($h)
}
foreach ($h in @($silentAsync)) {
  $key = "$($h.File):$($h.Line)"
  if ($seen.ContainsKey($key)) { continue }
  $seen[$key] = $true
  $hardFailures.Add($h)
}

# ---------------- 输出 ----------------
# ---------------- 基线（CI 用「不许新增」） ----------------
# 指纹 = 相对路径|代码片段（**不含行号**：行号随代码变动而漂移，指纹不会）。
# 修好一处后重新 -Update，基线自动下降；漏掉未修的则下次检查会报"新增"。
function Get-Fingerprint {
  param([object]$Hit)
  return ((Format-Rel $Hit.File) -replace '\\', '/') + '|' + ($Hit.Snippet -replace '\s+', ' ')
}

function Format-Rel([string]$path) {
  $rel = $path.Replace($Root, '').TrimStart('\', '/')
  return $rel
}

if ($Format -eq 'markdown') {
  Write-Output '# 静默失败检查报告'
  Write-Output ''
  Write-Output ("扫描：{0} 个 .ets（{1}）" -f $files.Count, $Root)
  Write-Output ''
  Write-Output '## A/B 硬性命中（CI 门禁）'
  Write-Output ''
  if ($hardFailures.Count -eq 0) {
    Write-Output '无。'
  }
  else {
    Write-Output '| 文件:行 | 类型 | 片段 |'
    Write-Output '|---|---|---|'
    foreach ($h in $hardFailures) {
      Write-Output ("| {0}:{1} | {2} | ``{3}`` |" -f (Format-Rel $h.File), $h.Line, $h.Kind, ($h.Snippet -replace '\|', '\|'))
    }
  }
  Write-Output ''
  Write-Output ("## C 需人工判读（{0} 处，误报率高，不入 CI）" -f @($conditional).Count)
}
else {
  Write-Output "扫描 $($files.Count) 个 .ets：$Root"
  Write-Output ''
  Write-Output "=== A/B 硬性命中：$($hardFailures.Count) 处 ==="
  foreach ($h in $hardFailures) {
    Write-Output ("{0}:{1}  [{2}]  {3}" -f (Format-Rel $h.File), $h.Line, $h.Kind, $h.Snippet)
  }
  Write-Output ''
  Write-Output "=== C 条件执行（需人工判读，误报率高，不入 CI）：$(@($conditional).Count) 处 ==="
  foreach ($c in $conditional) {
    Write-Output ("{0}:{1}  {2}" -f (Format-Rel $c.File), $c.Line, $c.Snippet)
  }
  Write-Output ''
  Write-Output '注：C 类中 `if (a !== null && b !== null) { 使用两者 }` 是合法判空；'
  Write-Output '    危险形态是块内为「启动/执行」动作。逐个看，别只看命中数。'
}

# ---------------- 基线比对 ----------------
$baselinePath = $Baseline
if (-not [string]::IsNullOrWhiteSpace($baselinePath)) {
  if (-not [System.IO.Path]::IsPathRooted($baselinePath)) {
    $baselinePath = Join-Path (Split-Path -Parent $PSScriptRoot) $baselinePath
  }

  $current = @($hardFailures | ForEach-Object { Get-Fingerprint -Hit $_ })

  if ($Update) {
    $dir = Split-Path -Parent $baselinePath
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    $current | Sort-Object -Unique | Set-Content -Path $baselinePath -Encoding utf8NoBOM
    Write-Output ''
    Write-Output ("基线已更新：{0}（{1} 条）" -f $baselinePath, @($current | Sort-Object -Unique).Count)
    exit 0
  }
  elseif (Test-Path $baselinePath) {
    $known = @{}
    foreach ($line in [System.IO.File]::ReadAllLines($baselinePath)) {
      $trimmed = $line.Trim()
      if ($trimmed.Length -gt 0) { $known[$trimmed] = $true }
    }

    $newOnes = [System.Collections.Generic.List[object]]::new()
    foreach ($h in $hardFailures) {
      $fp = Get-Fingerprint -Hit $h
      if (-not $known.ContainsKey($fp)) { $newOnes.Add($h) }
    }

    Write-Output ''
    if ($newOnes.Count -eq 0) {
      Write-Output ("基线比对：无新增（基线 {0} 条，当前 {1} 条）" -f $known.Count, $current.Count)
    }
    else {
      Write-Output ("=== 新增（不在基线里）：{0} 处 ===" -f $newOnes.Count)
      foreach ($n in $newOnes) {
        Write-Output ("{0}:{1}  [{2}]  {3}" -f (Format-Rel $n.File), $n.Line, $n.Kind, $n.Snippet)
      }
    }

    if ($Gate -and $newOnes.Count -gt 0) {
      Write-Output ''
      Write-Output ("门禁失败：新增 {0} 处静默失败（禁止空 catch 或 fire-and-forget 吞错）。" -f $newOnes.Count)
      exit 1
    }
    exit 0
  }
  else {
    Write-Output ''
    Write-Output ("基线文件不存在：{0}`n先用 -Update 生成，已跳过基线比对。" -f $baselinePath)
  }
}

if ($Gate -and $hardFailures.Count -gt 0) {
  Write-Output ''
  Write-Output "门禁失败：A/B 命中 $($hardFailures.Count) 处（禁止空 catch 或 fire-and-forget 吞错）。"
  exit 1
}

exit 0
