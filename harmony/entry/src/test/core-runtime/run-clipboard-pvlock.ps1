# ClipboardUtil + PVLock 断言
$ErrorActionPreference = 'Stop'
$root = (git -C $PSScriptRoot rev-parse --show-toplevel) -replace '/', '\'
$d = Join-Path $env:TEMP 'tscheck'
New-Item -ItemType Directory -Force -Path "$d\src\hippo\lib\yorozuya\thread" | Out-Null
Copy-Item "$root\harmony\entry\src\main\ets\hippo\ehviewer\util\ClipboardUtil.ets" "$d\src\hippo\ehviewer\util\ClipboardUtil.ts" -Force
Copy-Item "$root\harmony\entry\src\main\ets\hippo\lib\yorozuya\thread\PVLock.ets" "$d\src\hippo\lib\yorozuya\thread\PVLock.ts" -Force
. "$root\scripts\lib\tsc_gate.ps1"
if (-not (Invoke-TscGate -WorkDir $d -OutDir 'out11' -RootTs @('src/hippo/ehviewer/util/ClipboardUtil.ts', 'src/hippo/lib/yorozuya/thread/PVLock.ts') -Quiet)) { exit 1 }
node "$PSScriptRoot/clipboard-pvlock.test.js" "$d\out11\hippo"
exit $LASTEXITCODE
