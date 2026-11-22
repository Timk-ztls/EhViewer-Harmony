# AppHelper + UrlOpener 断言
$ErrorActionPreference = 'Stop'
$root = (git -C $PSScriptRoot rev-parse --show-toplevel) -replace '/', '\'
$d = Join-Path $env:TEMP 'tscheck'
Copy-Item "$root\harmony\entry\src\main\ets\hippo\util\AppHelper.ets" "$d\src\hippo\util\AppHelper.ts" -Force
Copy-Item "$root\harmony\entry\src\main\ets\hippo\ehviewer\UrlOpener.ets" "$d\src\hippo\ehviewer\UrlOpener.ts" -Force
. "$root\scripts\lib\tsc_gate.ps1"
if (-not (Invoke-TscGate -WorkDir $d -OutDir 'out11' -RootTs @('src/hippo/util/AppHelper.ts', 'src/hippo/ehviewer/UrlOpener.ts') -Quiet)) { exit 1 }
node "$PSScriptRoot/apphelper-urlopener.test.js" "$d\out11\hippo"
exit $LASTEXITCODE
