# 三个 DialogBuilder 的 Spec 语义
$ErrorActionPreference = 'Stop'
$root = (git -C $PSScriptRoot rev-parse --show-toplevel) -replace '/', '\'
$d = Join-Path $env:TEMP 'tscheck'
New-Item -ItemType Directory -Force -Path "$d\src\hippo\app" | Out-Null
Copy-Item "$root\harmony\entry\src\main\ets\hippo\app\DialogSpecs.ets" "$d\src\hippo\app\DialogSpecs.ts" -Force
. "$root\scripts\lib\tsc_gate.ps1"
if (-not (Invoke-TscGate -WorkDir $d -OutDir 'out11' -RootTs @('src/hippo/app/DialogSpecs.ts') -Quiet)) { exit 1 }
node "$PSScriptRoot/dialogspecs.test.js" "$d\out11\hippo"
exit $LASTEXITCODE
