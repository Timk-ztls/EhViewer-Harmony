<#
.SYNOPSIS
  对比度风险静态检查：找出"设了背景色、但 Text 没有显式字体色"的视图文件。
.DESCRIPTION
  动机：白字白底这个缺陷在本项目已踩 4 次（登录页 + 3 个 layout-based 视图），每次都靠真机截图才发现。
  本脚本把它变成静态检查 —— 能被机械检出的缺陷，不该靠人眼发现。

  三条判据：
    A（粗筛，默认报 risk）：文件含 backgroundColor，且 `Text(` 个数 > `.fontColor` 个数
    B（精筛，报 warn + 行号）：文件含 backgroundColor，且某处 `Text(` 之后 5 行内没有 `.fontColor`
    C（深色主题风险，报 warn + 行号）：文件**没有** backgroundColor，但存在**字面量**字色
      `.fontColor('#RRGGBB(AA)')` —— 字面量写死深色字，在深色主题下背景由主题变暗后会撞色。
      **排除**：`$r('app.color.X')`（资源随主题切换）与 `this.xxx`（受控属性，值由外部决定）。
      依据：实测本仓库有 47 个"无背景色 + 设 fontColor"的文件，其中 45 个用的是资源/受控属性
      （正确），只有 2 个写字面量（真风险，已修）。**若不过滤会出 47 条噪声 → 闸门会被关掉。**

  实现要点（都是踩过的）：
    ① 先剥注释（本项目已 4 次因"注释污染扫描结果"误判；统计类判断还要限定声明域）
    ② 用 `\bText\s*\(` 并排除 TextInput / TextTimer / TextArea / TextPicker / TextClock
       （前缀相同但不是纯文本组件，颜色由各自组件负责）
    ③ 默认 WARN 只列清单；-Gate 才 exit 1
       —— 判据 A/B 已归零，切 -Gate 是安全的（未来回退会立刻红）；
          判据 C 实测 0 条后同样可切；**"长期红的闸门"会训练人忽略闸门**，所以不要在有已知未修项时切。
.PARAMETER Path
  扫描根，默认 harmony/entry/src/main/ets/hippo/ui
.PARAMETER Gate
  有 risk 时以 exit 1 结束（供 CI）
.PARAMETER ShowOk
  同时打印"通过"的文件（默认只报问题）

.NOTES
  TODO（Lead 入库判据，设备验证期之后做）：**闸门的"有没有问题"只能有一个计算点。**
    本脚本目前有 3 个独立发现集合（$riskFiles / $warnItems / $darkWarnItems），
    而它们在**两处**被枚举：早退条件 与 -Gate 出口。今晚加判据 C 时正是漏了早退那处，
    造成"有命中却静默 OK"的假阴性。两个地方都得改，而它们隔了 28 行。
    漏的方式有两种、都很难查：
      · 只改早退 → 有输出但不阻断（更危险：看起来在管）
      · 只改出口 → 命中时静默 OK
    修法不是"小心一点"，是**消灭第二个枚举点**：
      ① 加 Get-ContrastFindingCount() 聚合函数，早退与出口都调它；或
      ② 更彻底：单个 $findings 列表 + 每条带 Kind（'A'|'B'|'C'），打印时按 Kind 分组。
    下次加判据 D 之前先做这一步，否则同一个 bug 会再来一次。

  fixture 原则：**测试用例必须同时包含"应报"与"不应报"的样本。**
    只造应报样本的 fixture 抓不到"排除规则写过头"（3/3 命中 = 排除失效；0/3 = 判据失效；1/3 = 两者都对）。
    本项目历史 fixture 都只造应报样本，所以从未抓到过"排除规则过头"这一类。
#>
param(
  [string]$Path = 'harmony/entry/src/main/ets/hippo/ui',
  [switch]$Gate,
  [switch]$ShowOk
)

$root = (Resolve-Path $Path).Path
$riskFiles = New-Object System.Collections.ArrayList
$warnItems = New-Object System.Collections.ArrayList
# 判据 C：无背景色但字色是字面量（深色主题风险）
$darkWarnItems = New-Object System.Collections.ArrayList
$okFiles = New-Object System.Collections.ArrayList
$scanned = 0

# 剥注释：块注释 /* */ 与行注释 //（够用即可；本仓库 .ets 没有正则字面量混淆场景）
function Remove-Comments([string[]]$lines) {
  $out = New-Object System.Collections.ArrayList
  $inBlock = $false
  foreach ($line in $lines) {
    $s = $line
    if ($inBlock) {
      $end = $s.IndexOf('*/')
      if ($end -ge 0) { $inBlock = $false; $s = $s.Substring($end + 2) }
      else { [void]$out.Add(''); continue }
    }
    $start = $s.IndexOf('/*')
    while ($start -ge 0) {
      $end = $s.IndexOf('*/', $start + 2)
      if ($end -ge 0) { $s = $s.Substring(0, $start) + $s.Substring($end + 2) }
      else { $s = $s.Substring(0, $start); $inBlock = $true; break }
      $start = $s.IndexOf('/*')
    }
    $lc = $s.IndexOf('//')
    if ($lc -ge 0) { $s = $s.Substring(0, $lc) }
    [void]$out.Add($s)
  }
  return $out
}

$files = Get-ChildItem -Path $root -Recurse -Filter *.ets -File
foreach ($f in $files) {
  $scanned++
  $raw = Get-Content -Path $f.FullName -Encoding UTF8
  $code = Remove-Comments $raw

  $hasBg = $false
  foreach ($l in $code) { if ($l -match '\.backgroundColor\s*\(') { $hasBg = $true; break } }
  if (-not $hasBg) {
    [void]$okFiles.Add($f.FullName)
    # 判据 C：没有背景色，但把字色写成了字面量 → 深色主题下会与主题背景撞。
    # 只认 '#RRGGBB' / '#AARRGGBB' 字面量；$r('app.color.X') 与 this.xxx 天然不匹配（它们随主题/外部变化）。
    for ($i = 0; $i -lt $code.Count; $i++) {
      $m = [regex]::Matches($code[$i], "\.fontColor\s*\(\s*'(#[0-9A-Fa-f]{6}|#[0-9A-Fa-f]{8})'\s*\)")
      if ($m.Count -gt 0) {
        foreach ($hit in $m) {
          [void]$darkWarnItems.Add([pscustomobject]@{
            File = $f.FullName.Substring($root.Length + 1).Replace('\','/')
            Line = $i + 1
            Hex = $hit.Groups[1].Value
            Snippet = $code[$i].Trim()
          })
        }
      }
    }
    continue
  }

  # 纯文本组件：\bText\s*\( 且排除前缀相同的其它组件
  $textLines = New-Object System.Collections.ArrayList
  for ($i = 0; $i -lt $code.Count; $i++) {
    if ($code[$i] -match '\bText\s*\(') {
      if ($code[$i] -match '\b(TextInput|TextArea|TextTimer|TextClock|TextPicker|RichText)\s*\(') { continue }
      [void]$textLines.Add($i)
    }
  }
  $fontCount = 0
  foreach ($l in $code) { $fontCount += ([regex]::Matches($l, '\.fontColor\s*\(')).Count }
  $textCount = $textLines.Count

  # 判据 A：Text 比 fontColor 多 → 至少有一个 Text 没设色
  if ($textCount -gt $fontCount) {
    [void]$riskFiles.Add([pscustomobject]@{
      File = $f.FullName.Substring($root.Length + 1).Replace('\','/')
      TextCount = $textCount
      FontCount = $fontCount
      Detail = "含 backgroundColor，Text($textCount) > fontColor($fontCount)"
    })
  }

  # 判据 B：逐个 Text 查其后 5 行内有无 .fontColor（能定位到行号）
  foreach ($idx in $textLines) {
    $found = $false
    $limit = [Math]::Min($idx + 5, $code.Count - 1)
    for ($j = $idx; $j -le $limit; $j++) {
      if ($code[$j] -match '\.fontColor\s*\(') { $found = $true; break }
      # 只在本行起算；若某行出现新的 Text( 则停止（属于下一个 Text）
      if ($j -gt $idx -and $code[$j] -match '\bText\s*\(') { break }
    }
    if (-not $found) {
      [void]$warnItems.Add([pscustomobject]@{
        File = $f.FullName.Substring($root.Length + 1).Replace('\','/')
        Line = $idx + 1
        Snippet = $code[$idx].Trim()
      })
    }
  }
}

Write-Host "check_contrast: 扫描 $scanned 个 .ets，含背景色的文件 $($scanned - $okFiles.Count) 个"

if ($riskFiles.Count -eq 0 -and $warnItems.Count -eq 0 -and $darkWarnItems.Count -eq 0) {
  Write-Host "OK: 未发现对比度风险（判据 A/B：含背景色的文件里每个 Text 都有显式 .fontColor；判据 C：无字面量字色）"
  exit 0
}

if ($riskFiles.Count -gt 0) {
  Write-Host "contrast-risk: $($riskFiles.Count) 个文件（判据 A：Text 数 > fontColor 数）"
  foreach ($r in $riskFiles) { Write-Host ("  {0}  [{1}]" -f $r.File, $r.Detail) }
}

if ($warnItems.Count -gt 0) {
  Write-Host "contrast-warn: $($warnItems.Count) 处（判据 B：Text( 之后 5 行内无 .fontColor）"
  foreach ($w in $warnItems) {
    Write-Host ("  {0}:{1}  {2}" -f $w.File, $w.Line, $w.Snippet)
  }
}

if ($darkWarnItems.Count -gt 0) {
  Write-Host "contrast-dark-warn: $($darkWarnItems.Count) 处（判据 C：无背景色 + 字面量字色 → 深色主题风险）"
  foreach ($w in $darkWarnItems) {
    Write-Host ("  {0}:{1}  {2}  {3}" -f $w.File, $w.Line, $w.Hex, $w.Snippet)
  }
}

if ($ShowOk -and $okFiles.Count -gt 0) {
  Write-Host "ok（无背景色，不适用）: $($okFiles.Count) 个文件"
}

if ($Gate -and ($riskFiles.Count -gt 0 -or $warnItems.Count -gt 0 -or $darkWarnItems.Count -gt 0)) { exit 1 }
exit 0
