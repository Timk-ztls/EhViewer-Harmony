# GZIPUtils 断言
$ErrorActionPreference = 'Stop'
$root = (git -C $PSScriptRoot rev-parse --show-toplevel) -replace '/', '\'
$d = Join-Path $env:TEMP 'tscheck'
New-Item -ItemType Directory -Force -Path "$d\src\hippo\ehviewer\util" | Out-Null
Copy-Item "$root\harmony\entry\src\main\ets\hippo\ehviewer\util\GZIPUtils.ets" "$d\src\hippo\ehviewer\util\GZIPUtils.ts" -Force
. "$root\scripts\lib\tsc_gate.ps1"
if (-not (Invoke-TscGate -WorkDir $d -OutDir 'out11' -RootTs @('src/hippo/ehviewer/util/GZIPUtils.ts') -Quiet)) { exit 1 }
node "$PSScriptRoot/gziputils.test.js" "$d\out11\hippo"
exit $LASTEXITCODE
