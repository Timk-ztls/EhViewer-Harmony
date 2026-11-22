# Crash 断言
$ErrorActionPreference = 'Stop'
$root = (git -C $PSScriptRoot rev-parse --show-toplevel) -replace '/', '\'
$d = Join-Path $env:TEMP 'tscheck'
New-Item -ItemType Directory -Force -Path "$d\src\hippo\ehviewer" | Out-Null
Copy-Item "$root\harmony\entry\src\main\ets\hippo\ehviewer\Crash.ets" "$d\src\hippo\ehviewer\Crash.ts" -Force
Copy-Item "$root\harmony\entry\src\main\ets\hippo\ehviewer\CrashTypes.ets" "$d\src\hippo\ehviewer\CrashTypes.ts" -Force
. "$root\scripts\lib\tsc_gate.ps1"
if (-not (Invoke-TscGate -WorkDir $d -OutDir 'out11' -RootTs @('src/hippo/ehviewer/Crash.ts') -Quiet)) { exit 1 }
node "$PSScriptRoot/crash.test.js" "$d\out11\hippo"
exit $LASTEXITCODE
