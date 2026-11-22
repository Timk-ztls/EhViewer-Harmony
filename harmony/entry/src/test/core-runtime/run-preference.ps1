# preference 纯逻辑断言（CleanRedundancy / VersionPreference）
$ErrorActionPreference = 'Stop'
$root = (git -C $PSScriptRoot rev-parse --show-toplevel) -replace '/', '\'
$d = Join-Path $env:TEMP 'tscheck'
. "$root\scripts\lib\sync_hippo.ps1"
Sync-HippoTree -SrcHippo "$root\harmony\entry\src\main\ets\hippo" -DstHippo "$d\src\hippo"
. "$root\scripts\lib\tsc_gate.ps1"
if (-not (Invoke-TscGate -WorkDir $d -OutDir 'out5' -RootTs @('src/hippo/ehviewer/preference/CleanRedundancyPreference.ts', 'src/hippo/ehviewer/preference/VersionPreference.ts') -Quiet)) { exit 1 }
node "$PSScriptRoot/preference.test.js" "$d\out5\hippo\ehviewer\preference"
exit $LASTEXITCODE
