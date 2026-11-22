# RestoreDownload 扫描/应用断言
$ErrorActionPreference = 'Stop'
$root = (git -C $PSScriptRoot rev-parse --show-toplevel) -replace '/', '\'
$d = Join-Path $env:TEMP 'tscheck'
. "$root\scripts\lib\sync_hippo.ps1"
Sync-HippoTree -SrcHippo "$root\harmony\entry\src\main\ets\hippo" -DstHippo "$d\src\hippo"
. "$root\scripts\lib\tsc_gate.ps1"
if (-not (Invoke-TscGate -WorkDir $d -OutDir 'out9' -RootTs @('src/hippo/ehviewer/preference/RestoreDownloadPreference.ts') -Quiet)) { exit 1 }
node "$PSScriptRoot/restore-download.test.js" "$d\out9\hippo\ehviewer\preference"
exit $LASTEXITCODE
