# FastBlur 运行时应断言
$ErrorActionPreference = 'Stop'
$root = (git -C $PSScriptRoot rev-parse --show-toplevel) -replace '/', '\'
$d = Join-Path $env:TEMP 'tscheck'
Copy-Item "$root\harmony\entry\src\main\ets\hippo\util\FastBlur.ets" (Join-Path $d 'src\FastBlur.ts') -Force
. "$root\scripts\lib\tsc_gate.ps1"
if (-not (Invoke-TscGate -WorkDir $d -OutDir 'out7' -RootTs @('src/FastBlur.ts') -Quiet)) { exit 1 }
node "$PSScriptRoot/fastblur.test.js" "$d\out7"
exit $LASTEXITCODE
