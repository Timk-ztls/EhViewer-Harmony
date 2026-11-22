# CrashObserver 断言
$ErrorActionPreference = 'Stop'
$root = (git -C $PSScriptRoot rev-parse --show-toplevel) -replace '/', '\'
$d = Join-Path $env:TEMP 'tscheck'
Copy-Item "$root\harmony\entry\src\main\ets\hippo\ehviewer\CrashObserver.ets" "$d\src\hippo\ehviewer\CrashObserver.ts" -Force
. "$root\scripts\lib\tsc_gate.ps1"
if (-not (Invoke-TscGate -WorkDir $d -OutDir 'out11' -RootTs @('src/hippo/ehviewer/CrashObserver.ts') -Quiet)) { exit 1 }
node "$PSScriptRoot/crashobserver.test.js" "$d\out11\hippo"
exit $LASTEXITCODE
