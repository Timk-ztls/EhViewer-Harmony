# EhDB 历史裁剪 + Settings.getVersionCode
$ErrorActionPreference = 'Stop'
$root = (git -C $PSScriptRoot rev-parse --show-toplevel) -replace '/', '\'
$d = Join-Path $env:TEMP 'tscheck'
Copy-Item "$root\harmony\entry\src\main\ets\hippo\ehviewer\EhDB.ets" "$d\src\hippo\ehviewer\EhDB.ts" -Force
Copy-Item "$root\harmony\entry\src\main\ets\hippo\ehviewer\Settings.ets" "$d\src\hippo\ehviewer\Settings.ts" -Force
. "$root\scripts\lib\tsc_gate.ps1"
if (-not (Invoke-TscGate -WorkDir $d -OutDir 'out11' -RootTs @('src/hippo/ehviewer/EhDB.ts', 'src/hippo/ehviewer/Settings.ts') -Quiet)) { exit 1 }
node "$PSScriptRoot/history-trim-version.test.js" "$d\out11\hippo"
exit $LASTEXITCODE
