# FileProvider 断言
$ErrorActionPreference = 'Stop'
$root = (git -C $PSScriptRoot rev-parse --show-toplevel) -replace '/', '\'
$d = Join-Path $env:TEMP 'tscheck'
New-Item -ItemType Directory -Force -Path "$d\src\hippo\content" | Out-Null
Copy-Item "$root\harmony\entry\src\main\ets\hippo\content\FileProvider.ets" "$d\src\hippo\content\FileProvider.ts" -Force
. "$root\scripts\lib\tsc_gate.ps1"
if (-not (Invoke-TscGate -WorkDir $d -OutDir 'out11' -RootTs @('src/hippo/content/FileProvider.ts') -Quiet)) { exit 1 }
node "$PSScriptRoot/fileprovider.test.js" "$d\out11\hippo"
exit $LASTEXITCODE
