# 检查全仓 $r('app.<type>.<key>') 引用的资源键是否存在于 strings.json / 对应资源文件
#
# 背景：$r 编译期不校验键名（陷阱 90），运行期找不到会静默返回空。
# 全仓 541 处引用 / 103 个文件，肉眼无法核对，必须机器扫。
#
# 用法：
#   check_resource_keys.ps1              只报缺失
#   check_resource_keys.ps1 -Gate        有缺失则 exit 1（进 CI）
#   check_resource_keys.ps1 -Detail      连每处引用的文件:行号一起报
param(
    [switch]$Gate,
    [switch]$Detail
)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$etsRoot = Join-Path $root 'harmony/entry/src/main/ets'
$resRoot = Join-Path $root 'harmony/entry/src/main/resources'
$baseStrings = Join-Path $resRoot 'base/element/strings.json'

if (-not (Test-Path $baseStrings)) {
    Write-Host "SKIP: 找不到 $baseStrings —— 本项不生效" -ForegroundColor Yellow
    exit 0
}

# 1) 读 base 的键集合
$baseJson = Get-Content $baseStrings -Raw | ConvertFrom-Json
$stringKeys = @{}
foreach ($item in $baseJson.string) { $stringKeys[$item.name] = $true }

# 2) 其他资源类型的键 —— 按 JSON 顶层属性名判断类型（不是按文件名）
#    ArkUI 约定：strings.json/color(s).json/dimens.json 等文件的顶层属性名就是资源类型
#      string  ← strings.json(922) + string.json(10) + analytics.json(2) + pathdata.json(92)
#      color   ← colors.json(156) + color.json + 5 个 color_*.json
#      float   ← dimens.json(105)
#      boolean ← bools.json(3)
#      integer ← ids.json(13)
#      strarray← arrays.json(53) + styles.json(43) + themes.json(30)
$typeKeys = @{}
$elemDir = Join-Path $resRoot 'base/element'
if (Test-Path $elemDir) {
    Get-ChildItem $elemDir -Filter '*.json' -File | ForEach-Object {
        try {
            $j = Get-Content $_.FullName -Raw | ConvertFrom-Json
            foreach ($prop in $j.PSObject.Properties) {
                $t = $prop.Name
                if (-not $typeKeys.ContainsKey($t)) { $typeKeys[$t] = @{} }
                if ($prop.Value -is [array]) {
                    foreach ($item in $prop.Value) {
                        if ($item -and $item.name) { $typeKeys[$t][$item.name] = $true }
                    }
                } elseif ($prop.Value -and $prop.Value.name) {
                    $typeKeys[$t][$prop.Value.name] = $true
                }
            }
        } catch { }
    }
}
# media
$mediaDir = Join-Path $resRoot 'base/media'
if (Test-Path $mediaDir) {
    if (-not $typeKeys.ContainsKey('media')) { $typeKeys['media'] = @{} }
    Get-ChildItem $mediaDir -File | ForEach-Object {
        $typeKeys['media'][[IO.Path]::GetFileNameWithoutExtension($_.Name)] = $true
    }
}
# rawfile
$rawDir = Join-Path $resRoot 'rawfile'
if (Test-Path $rawDir) {
    if (-not $typeKeys.ContainsKey('rawfile')) { $typeKeys['rawfile'] = @{} }
    Get-ChildItem $rawDir -Recurse -File | ForEach-Object {
        $typeKeys['rawfile'][[IO.Path]::GetFileNameWithoutExtension($_.Name)] = $true
    }
}
# 3) 扫全仓 .ets 的 $r('app.<type>.<key>')
$pattern = "\`$r\('app\.([a-zA-Z]+)\.([A-Za-z0-9_]+)'\)"
$refs = @()
Get-ChildItem $etsRoot -Recurse -Filter '*.ets' -ErrorAction SilentlyContinue | ForEach-Object {
    $file = $_
    Select-String -Path $file.FullName -Pattern $pattern -AllMatches -ErrorAction SilentlyContinue | ForEach-Object {
        $trimmed = $_.Line.TrimStart()
        if ($trimmed.StartsWith('//') -or $trimmed.StartsWith('*') -or $trimmed.StartsWith('/*')) { return }
        foreach ($m in $_.Matches) {
            $refs += [pscustomobject]@{
                File = $file.FullName.Substring($root.Length + 1)
                Line = $_.LineNumber
                Type = $m.Groups[1].Value
                Key  = $m.Groups[2].Value
            }
        }
    }
}

if ($refs.Count -eq 0) {
    Write-Host "资源键检查：未发现 \$r('app.x.y') 形式的引用" -ForegroundColor Green
    exit 0
}

# 4) 逐条核对
$missing = @()
$unknownType = @()
foreach ($r in $refs) {
    $t = $r.Type
    if (-not $typeKeys.ContainsKey($t)) {
        $unknownType += $r
        continue
    }
    if (-not $typeKeys[$t].ContainsKey($r.Key)) {
        $missing += $r
    }
}

$total = $refs.Count
$uniqKeys = ($refs | ForEach-Object { "$($_.Type).$($_.Key)" } | Select-Object -Unique)
Write-Host "扫描 $total 处引用（$($uniqKeys.Count) 个唯一键），分布 $(($refs | Select-Object -ExpandProperty File -Unique).Count) 个文件"

if ($unknownType.Count -gt 0) {
    Write-Host "`n未知资源类型（$($unknownType.Count) 处）—— 检查器的类型表可能不全，不算失败：" -ForegroundColor Yellow
    $unknownType | Select-Object -First 10 | ForEach-Object { "  [$($_.Type)] $($_.File):$($_.Line)  $($_.Key)" }
}

if ($missing.Count -eq 0) {
    Write-Host "资源键检查通过：所有引用都能在 resources/base 找到" -ForegroundColor Green
    exit 0
}

# 按 key 聚合（同一缺失键可能被多处引用）
$grouped = $missing | Group-Object { "$($_.Type).$($_.Key)" } | Sort-Object Count -Descending
Write-Host "`n缺失的资源键：$($grouped.Count) 个唯一键，共 $($missing.Count) 处引用" -ForegroundColor Red
$grouped | Select-Object -First 30 | ForEach-Object {
    Write-Host "  $($_.Name)  ×$($_.Count)" -ForegroundColor Yellow
    if ($Detail) {
        $_.Group | Select-Object -First 3 | ForEach-Object { "      $($_.File):$($_.Line)" }
    }
}
if ($grouped.Count -gt 30) { Write-Host "  ...（另有 $($grouped.Count - 30) 个唯一键）" }

Write-Host "`n修法：" -ForegroundColor Cyan
Write-Host "  ① 把键加到 harmony/entry/src/main/resources/base/element/strings.json"
Write-Host "  ② 或改成只传标识（如 toast(hintId)），文案由页面 @Component 取"
Write-Host "  ③ 或确认该键是从上游 strings.xml 迁移时漏的，补进迁移脚本"

if ($Gate) { exit 1 }
exit 0
