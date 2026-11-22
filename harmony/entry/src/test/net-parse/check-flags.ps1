<#
  check-flags.ps1 —— 三方位标志常量交叉校验（Lead 要求：半年后谁改了一位要能查出来）

  校验对象（数值必须逐位一致，否则 f_cats / advsearch 参数静默错位）：
    net-parse   : harmony/entry/src/main/ets/hippo/ehviewer/client/data/Flags.ets      （已落地）
    ui-widget   : harmony/entry/src/main/ets/hippo/ehviewer/widget/AdvanceSearchTable.ets
    core-runtime: harmony/entry/src/main/ets/hippo/ehviewer/client/EhConfig.ets
                  harmony/entry/src/main/ets/hippo/ehviewer/client/EhUtils.ets

  未落地的文件按「待对方实现」跳过（不算失败）；已落地但不一致 → 退出码 1。

  用法：pwsh -File check-flags.ps1
#>
[CmdletBinding()]
param(
  [string]$Root = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..\..\..')).Path
)

$ErrorActionPreference = 'Stop'
$ets = Join-Path $Root 'harmony\entry\src\main\ets\hippo'

# ---- 期望值（来自 origin/upstream，见 Flags.ets 头注释）----
$expected = [ordered]@{
  'SNAME'        = 0x1
  'STAGS'        = 0x2
  'SDESC'        = 0x4
  'STORR'        = 0x8
  'STO'          = 0x10
  'SDT1'         = 0x20
  'SDT2'         = 0x40
  'SH'           = 0x80
  'SFL'          = 0x100
  'SFU'          = 0x200
  'SFT'          = 0x400
  'MISC'         = 0x1
  'DOUJINSHI'    = 0x2
  'MANGA'        = 0x4
  'ARTIST_CG'    = 0x8
  'GAME_CG'      = 0x10
  'IMAGE_SET'    = 0x20
  'COSPLAY'      = 0x40
  'ASIAN_PORN'   = 0x80
  'NON_H'        = 0x100
  'WESTERN'      = 0x200
  'ALL_CATEGORY' = 0x3ff
  'NAMESPACES_RECLASS'   = 0x1
  'NAMESPACES_LANGUAGE'  = 0x2
  'NAMESPACES_PARODY'    = 0x4
  'NAMESPACES_CHARACTER' = 0x8
  'NAMESPACES_GROUP'     = 0x10
  'NAMESPACES_ARTIST'    = 0x20
  'NAMESPACES_MALE'      = 0x40
  'NAMESPACES_FEMALE'    = 0x80
  'DEFAULT_ADVANCE' = 0x3
  'DEFAULT_MIN_RATING' = 2
  'NONE'         = -1
  'UNKNOWN'      = 0x400
}

# ---- 提取某个 .ets 里 `NAME\s*(?::\s*number\s*)?=\s*<数值>` 形式的常量 ----
function Get-ConstMap {
  param([string]$Path)
  $map = @{}
  if (-not (Test-Path $Path)) { return $map }
  $lines = Get-Content $Path
  foreach ($line in $lines) {
    if ($line -match '(?<name>[A-Z][A-Z0-9_]+)\s*(?::\s*number\s*)?=\s*(?<val>-?0x[0-9a-fA-F]+|-?\d+)') {
      $name = $Matches['name']
      $raw = $Matches['val']
      $val = if ($raw -match '^-?0x') {
        $neg = $raw.StartsWith('-')
        $n = [Convert]::ToInt64($raw.Replace('-', ''), 16)
        if ($neg) { -$n } else { $n }
      } else { [int64]$raw }
      if (-not $map.ContainsKey($name)) { $map[$name] = $val }
    }
  }
  return $map
}

$targets = @(
  # 分类位/namespace 位的权威定义在 net-parse 的 EhConfig.ets（S0071）
  @{ Name = 'net-parse(EhConfig)'; Path = (Join-Path $ets 'ehviewer\client\EhConfig.ets'); Keys = @('MISC','DOUJINSHI','MANGA','ARTIST_CG','GAME_CG','IMAGE_SET','COSPLAY','ASIAN_PORN','NON_H','WESTERN','ALL_CATEGORY','NAMESPACES_RECLASS','NAMESPACES_LANGUAGE','NAMESPACES_PARODY','NAMESPACES_CHARACTER','NAMESPACES_GROUP','NAMESPACES_ARTIST','NAMESPACES_MALE','NAMESPACES_FEMALE') },
  # Flags.ets 只承载「高级搜索位 + 两个默认值」（分类位改为引用 EhConfig，不再写字面量）
  @{ Name = 'net-parse(Flags)'; Path = (Join-Path $ets 'ehviewer\client\data\Flags.ets'); Keys = @('SNAME','STAGS','SDESC','STORR','STO','SDT1','SDT2','SH','SFL','SFU','SFT','DEFAULT_MIN_RATING') },
  @{ Name = 'ui-widget(AdvanceSearchTable)'; Path = (Join-Path $ets 'ehviewer\widget\AdvanceSearchTable.ets'); Keys = @('SNAME','STAGS','SDESC','STORR','STO','SDT1','SDT2','SH','SFL','SFU','SFT') },
  @{ Name = 'net-parse(EhUtils)'; Path = (Join-Path $ets 'ehviewer\client\EhUtils.ets'); Keys = @('NONE','UNKNOWN') }
)

$bad = 0
$pending = 0
foreach ($t in $targets) {
  if (-not (Test-Path $t.Path)) {
    Write-Host ("[待落地] {0,-34} {1}" -f $t.Name, (Split-Path $t.Path -Leaf)) -ForegroundColor Yellow
    $pending++
    continue
  }
  $map = Get-ConstMap -Path $t.Path
  $checked = 0
  foreach ($k in $t.Keys) {
    if (-not $map.ContainsKey($k)) {
      Write-Host ("[缺常量] {0,-34} {1} 未在文件中找到" -f $t.Name, $k) -ForegroundColor Yellow
      $bad++
      continue
    }
    $checked++
    if ($map[$k] -ne $expected[$k]) {
      Write-Host ("[不一致] {0,-34} {1}: 实际 0x{2:X} ≠ 期望 0x{3:X}" -f $t.Name, $k, $map[$k], $expected[$k]) -ForegroundColor Red
      $bad++
    }
  }
  Write-Host ("[已校验] {0,-34} {1} 个常量" -f $t.Name, $checked) -ForegroundColor Green
}


# =====================================================================================
# 自洽性断言（Lead 要求）——防「改了一位忘改派生值 / 新增位撞车 / 跨模块不同步」
# 这类错误不会让任何常量校验报错，但会让 f_cats / xns 参数静默错位。
# =====================================================================================
$ehConfigPath = Join-Path $ets 'ehviewer\client\EhConfig.ets'
$ehUtilsPath = Join-Path $ets 'ehviewer\client\EhUtils.ets'
$flagsPath = Join-Path $ets 'ehviewer\client\data\Flags.ets'

if ((Test-Path $ehConfigPath) -and (Test-Path $ehUtilsPath)) {
  $cfg = Get-ConstMap -Path $ehConfigPath
  $utils = Get-ConstMap -Path $ehUtilsPath
  $flags = if (Test-Path $flagsPath) { Get-ConstMap -Path $flagsPath } else { @{} }

  $categoryBits = @('MISC', 'DOUJINSHI', 'MANGA', 'ARTIST_CG', 'GAME_CG', 'IMAGE_SET', 'COSPLAY', 'ASIAN_PORN', 'NON_H', 'WESTERN')
  $missing = @($categoryBits | Where-Object { -not $cfg.ContainsKey($_) })
  if ($missing.Count -eq 0 -and $cfg.ContainsKey('ALL_CATEGORY')) {
    # 1) ALL_CATEGORY == 11 个分类位的并
    $orAll = 0
    foreach ($b in $categoryBits) { $orAll = $orAll -bor [int]$cfg[$b] }
    if ([int]$cfg['ALL_CATEGORY'] -ne $orAll) {
      Write-Host ("[自洽X] EhConfig.ALL_CATEGORY=0x{0:X} != 11 个分类位的并 0x{1:X}" -f $cfg['ALL_CATEGORY'], $orAll) -ForegroundColor Red
      $bad++
    } else {
      Write-Host ("[自洽OK] EhConfig.ALL_CATEGORY == 11 个分类位的并 (0x{0:X})" -f $orAll) -ForegroundColor Green
    }

    # 2) 分类位两两互不重叠
    $overlap = @()
    for ($i = 0; $i -lt $categoryBits.Length; $i++) {
      for ($j = $i + 1; $j -lt $categoryBits.Length; $j++) {
        $x = [int]$cfg[$categoryBits[$i]]
        $y = [int]$cfg[$categoryBits[$j]]
        if (($x -band $y) -ne 0) { $overlap += "$($categoryBits[$i]) & $($categoryBits[$j])" }
      }
    }
    if ($overlap.Count -gt 0) {
      Write-Host ("[自洽X] 分类位重叠 {0} 处：{1}" -f $overlap.Count, ($overlap -join '; ')) -ForegroundColor Red
      $bad += $overlap.Count
    } else {
      Write-Host "[自洽OK] 11 个分类位两两互不重叠" -ForegroundColor Green
    }
  } else {
    Write-Host ("[自洽-] 跳过分类位自洽检查（缺常量：{0}）" -f ($missing -join ',')) -ForegroundColor Yellow
  }

  # namespace 位同样要互不重叠（xns 参数按位或）
  $nsBits = @('NAMESPACES_RECLASS', 'NAMESPACES_LANGUAGE', 'NAMESPACES_PARODY', 'NAMESPACES_CHARACTER', 'NAMESPACES_GROUP', 'NAMESPACES_ARTIST', 'NAMESPACES_MALE', 'NAMESPACES_FEMALE')
  $nsMissing = @($nsBits | Where-Object { -not $cfg.ContainsKey($_) })
  if ($nsMissing.Count -eq 0) {
    $nsOverlap = @()
    for ($i = 0; $i -lt $nsBits.Length; $i++) {
      for ($j = $i + 1; $j -lt $nsBits.Length; $j++) {
        $x = [int]$cfg[$nsBits[$i]]
        $y = [int]$cfg[$nsBits[$j]]
        if (($x -band $y) -ne 0) { $nsOverlap += "$($nsBits[$i]) & $($nsBits[$j])" }
      }
    }
    if ($nsOverlap.Count -gt 0) {
      Write-Host ("[自洽X] namespace 位重叠：{0}" -f ($nsOverlap -join '; ')) -ForegroundColor Red
      $bad += $nsOverlap.Count
    } else {
      Write-Host "[自洽OK] 8 个 namespace 位两两互不重叠" -ForegroundColor Green
    }
  }

  # 3) DEFAULT_ADVANCE 必须等于 SNAME | STAGS（= 0x3），且必须是表达式而非硬编码
  if ($flags.ContainsKey('SNAME') -and $flags.ContainsKey('STAGS')) {
    $expectedDefault = [int]$flags['SNAME'] -bor [int]$flags['STAGS']
    $flagsText = Get-Content $flagsPath -Raw
    $declaresExpr = $flagsText -match 'DEFAULT_ADVANCE\s*:\s*number\s*=\s*AdvanceSearchFlags\.SNAME\s*\|\s*AdvanceSearchFlags\.STAGS'
    if ($expectedDefault -ne 0x3) {
      Write-Host ("[自洽X] SNAME|STAGS=0x{0:X} != 0x3（上游 DEFAULT_ADVANCE 必须是 0x3）" -f $expectedDefault) -ForegroundColor Red
      $bad++
    } elseif (-not $declaresExpr) {
      Write-Host "[自洽X] DEFAULT_ADVANCE 不是 SNAME|STAGS 表达式（可能被硬编码后漂移）" -ForegroundColor Red
      $bad++
    } else {
      Write-Host "[自洽OK] DEFAULT_ADVANCE == SNAME | STAGS (0x3)" -ForegroundColor Green
    }
  }

  # 4) EhUtils.ALL_CATEGORY（= UNKNOWN - 1 推导）必须等于 EhConfig.ALL_CATEGORY（硬编码 0x3ff）
  if ($utils.ContainsKey('UNKNOWN') -and $cfg.ContainsKey('ALL_CATEGORY')) {
    $utilsAll = [int]$utils['UNKNOWN'] - 1
    if ($utilsAll -ne [int]$cfg['ALL_CATEGORY']) {
      Write-Host ("[自洽X] EhUtils.ALL_CATEGORY(UNKNOWN-1=0x{0:X}) != EhConfig.ALL_CATEGORY(0x{1:X})" -f $utilsAll, $cfg['ALL_CATEGORY']) -ForegroundColor Red
      $bad++
    } else {
      Write-Host ("[自洽OK] EhUtils.ALL_CATEGORY(UNKNOWN-1) == EhConfig.ALL_CATEGORY (0x{0:X})" -f $utilsAll) -ForegroundColor Green
    }
  }
} else {
  Write-Host "[自洽-] EhConfig.ets / EhUtils.ets 未落地，跳过自洽检查" -ForegroundColor Yellow
}

Write-Host ""
if ($bad -gt 0) {
  Write-Host "✗ 位标志不一致 $bad 处 —— f_cats / advsearch 会静默错位（服务端不报错）" -ForegroundColor Red
  exit 1
}
if ($pending -gt 0) {
  Write-Host "✓ 已落地的常量全部一致；$pending 个文件待对方实现（届时重跑本脚本即可）" -ForegroundColor Green
} else {
  Write-Host "✓ 三方常量全部一致" -ForegroundColor Green
}
