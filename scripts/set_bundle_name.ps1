<#
  set_bundle_name.ps1 -- Validate and update the HarmonyOS bundleName across all 4 repository locations.
  Compatible with Windows PowerShell 5.1 and PowerShell 7+ (pwsh).
  Always writes files in UTF-8 without BOM and LF line endings.

  Usage:
    pwsh -File scripts/set_bundle_name.ps1 -BundleName com.yourname.ehviewer
    pwsh -File scripts/set_bundle_name.ps1 -BundleName com.yourname.ehviewer -DryRun
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)]
  [string]$BundleName,
  [string]$Root = '',
  [switch]$DryRun
)

$ErrorActionPreference = 'Stop'

try {
if ([string]::IsNullOrWhiteSpace($Root)) {
  $Root = Split-Path -Parent $PSScriptRoot
}
if ($BundleName.Length -lt 7 -or $BundleName.Length -gt 128) {
  throw "Invalid BundleName '$BundleName': length must be 7..128 characters (got $($BundleName.Length))."
}

if ($BundleName -cnotmatch '^[a-z][a-z0-9_]*(\.[a-z][a-z0-9_]*){2,}$') {
  throw "Invalid BundleName '$BundleName': use lowercase letters, digits, '_' and at least 3 dot-separated segments (e.g. com.yourname.ehviewer). Hyphens '-' and uppercase letters are not allowed."
}

$reservedSegments = @('oh', 'ohos', 'harmony', 'harmonyos', 'openharmony', 'system')
foreach ($seg in $BundleName.Split('.')) {
  if ($reservedSegments -contains $seg.ToLowerInvariant()) {
    throw "Invalid BundleName '$BundleName': segment '$seg' is reserved by Huawei AGC (forbidden segments: $($reservedSegments -join ', '))."
  }
}

if ($BundleName -eq 'com.ehviewer.next') {
  Write-Host 'NOTE: com.ehviewer.next is already registered on Huawei AGC by the upstream HarmonyOS maintainer. If you are building your own copy with Automatic Signing or AGC, pick your own unique bundleName (e.g. com.yourname.ehviewer).' -ForegroundColor Yellow
}

$utf8NoBom = New-Object System.Text.UTF8Encoding($false)

function Write-Utf8Lf([string]$Path, [string]$Text) {
  $lfText = $Text -replace "`r`n", "`n"
  [System.IO.File]::WriteAllText($Path, $lfText, $utf8NoBom)
}

function Replace-Pattern([string]$Text, [string]$Pattern, [string]$Value, [string]$FileLabel) {
  $rx = New-Object System.Text.RegularExpressions.Regex($Pattern)
  $rxMatches = $rx.Matches($Text)
  if ($rxMatches.Count -eq 0) {
    throw "Expected pattern '$Pattern' not found in $FileLabel"
  }
  $evaluator = [System.Text.RegularExpressions.MatchEvaluator]{
    param($m)
    return ($m.Groups[1].Value + $Value + $m.Groups[2].Value)
  }
  return $rx.Replace($Text, $evaluator)
}

$appJsonPath = Join-Path $Root 'harmony\AppScope\app.json5'
$shortcutsPath = Join-Path $Root 'harmony\entry\src\main\resources\base\profile\shortcuts_config.json'
$dlServicePath = Join-Path $Root 'harmony\entry\src\main\ets\hippo\ehviewer\download\DownloadService.ets'
$archServicePath = Join-Path $Root 'harmony\entry\src\main\ets\hippo\ehviewer\download\ArchiverDownloadService.ets'

foreach ($p in @($appJsonPath, $shortcutsPath, $dlServicePath, $archServicePath)) {
  if (-not (Test-Path $p)) { throw "Target file not found: $p" }
}

$appRaw = [System.IO.File]::ReadAllText($appJsonPath, $utf8NoBom)
$oldMatch = [regex]::Match($appRaw, '"bundleName"\s*:\s*"([^"]+)"')
if (-not $oldMatch.Success) { throw "Could not read current bundleName from $appJsonPath" }
$oldBundleName = $oldMatch.Groups[1].Value

$specs = @(
  @{
    Path = $appJsonPath
    Rel = 'harmony/AppScope/app.json5'
    Rules = @( @{ Pattern = '("bundleName"\s*:\s*")[^"]+(")'; Value = $BundleName } )
  },
  @{
    Path = $shortcutsPath
    Rel = 'harmony/entry/src/main/resources/base/profile/shortcuts_config.json'
    Rules = @( @{ Pattern = '("bundleName"\s*:\s*")[^"]+(")'; Value = $BundleName } )
  },
  @{
    Path = $dlServicePath
    Rel = 'harmony/entry/src/main/ets/hippo/ehviewer/download/DownloadService.ets'
    Rules = @(
      @{ Pattern = "(const SLOT_ID:\s*string\s*=\s*')[^']+(\.download';)"; Value = $BundleName },
      @{ Pattern = "(this\.context === null \? ')[^']+(' : this\.context\.abilityInfo\.bundleName;)"; Value = $BundleName }
    )
  },
  @{
    Path = $archServicePath
    Rel = 'harmony/entry/src/main/ets/hippo/ehviewer/download/ArchiverDownloadService.ets'
    Rules = @(
      @{ Pattern = "(const SLOT_ID:\s*string\s*=\s*')[^']+(\.archiver_download';)"; Value = $BundleName },
      @{ Pattern = "(this\.context === null \? ')[^']+(' : this\.context\.abilityInfo\.bundleName;)"; Value = $BundleName }
    )
  }
)

Write-Host "BundleName: $oldBundleName -> $BundleName$(if ($DryRun) { ' [DryRun]' } else { '' })" -ForegroundColor Cyan

foreach ($spec in $specs) {
  $orig = [System.IO.File]::ReadAllText($spec.Path, $utf8NoBom)
  $next = $orig
  foreach ($r in $spec.Rules) {
    $next = Replace-Pattern -Text $next -Pattern $r.Pattern -Value $r.Value -FileLabel $spec.Rel
  }
  if ($DryRun) {
    $state = if (($orig -replace "`r`n", "`n") -ceq ($next -replace "`r`n", "`n")) { 'unchanged' } else { 'would-update' }
    Write-Host "  [DryRun] $($spec.Rel): $state"
  } else {
    Write-Utf8Lf -Path $spec.Path -Text $next
    Write-Host "  [OK] $($spec.Rel)" -ForegroundColor Green
  }
}

if (-not $DryRun) {
  Write-Host "`nDone. Remember to regenerate or select a matching signing profile (.p7b) for '$BundleName' before installing to a device." -ForegroundColor Green
}
} catch {
  Write-Host ("ERROR: " + $_.Exception.Message) -ForegroundColor Red
  exit 1
}
