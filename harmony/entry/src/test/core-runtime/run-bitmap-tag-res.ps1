# BitmapUtils / ResourcesUtils / TagTranslationUtil 断言
$ErrorActionPreference = 'Stop'
$root = (git -C $PSScriptRoot rev-parse --show-toplevel) -replace '/', '\'
$d = Join-Path $env:TEMP 'tscheck'
. "$root\scripts\lib\sync_hippo.ps1"
Sync-HippoTree -SrcHippo "$root\harmony\entry\src\main\ets\hippo" -DstHippo "$d\src\hippo"
. "$root\scripts\lib\tsc_gate.ps1"
if (-not (Invoke-TscGate -WorkDir $d -OutDir 'out10' -RootTs @('src/hippo/util/BitmapUtils.ts', 'src/hippo/lib/yorozuya/ResourcesUtils.ts', 'src/hippo/ehviewer/util/TagTranslationUtil.ts') -Quiet)) { exit 1 }
node "$PSScriptRoot/bitmap-tag-res.test.js" "$d\out10\hippo"
exit $LASTEXITCODE
