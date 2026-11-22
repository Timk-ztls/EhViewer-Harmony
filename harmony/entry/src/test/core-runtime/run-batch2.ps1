# 批次 2：FavouriteStatusRouter + ShakeDetector
$ErrorActionPreference = 'Stop'
$root = (git -C $PSScriptRoot rev-parse --show-toplevel) -replace '/', '\'
$d = Join-Path $env:TEMP 'tscheck'
New-Item -ItemType Directory -Force -Path "$d\src\hippo\ehviewer\widget" | Out-Null
Copy-Item "$root\harmony\entry\src\main\ets\hippo\ehviewer\FavouriteStatusRouter.ets" "$d\src\hippo\ehviewer\FavouriteStatusRouter.ts" -Force
Copy-Item "$root\harmony\entry\src\main\ets\hippo\ehviewer\widget\ShakeDetector.ets" "$d\src\hippo\ehviewer\widget\ShakeDetector.ts" -Force
. "$root\scripts\lib\tsc_gate.ps1"
if (-not (Invoke-TscGate -WorkDir $d -OutDir 'out11' -RootTs @('src/hippo/ehviewer/FavouriteStatusRouter.ts', 'src/hippo/ehviewer/widget/ShakeDetector.ts') -Quiet)) { exit 1 }
node "$PSScriptRoot/batch2.test.js" "$d\out11\hippo"
exit $LASTEXITCODE
