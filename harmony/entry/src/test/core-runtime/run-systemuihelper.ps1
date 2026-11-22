# SystemUiHelper 家族（四档 flag 位运算）断言
$ErrorActionPreference = 'Stop'
$root = (git -C $PSScriptRoot rev-parse --show-toplevel) -replace '/', '\'
$d = Join-Path $env:TEMP 'tscheck'
. "$root\scripts\lib\sync_hippo.ps1"
Sync-HippoTree -SrcHippo "$root\harmony\entry\src\main\ets\hippo" -DstHippo "$d\src\hippo"
Push-Location $d
node "$d\node_modules\typescript\bin\tsc" --noEmit false --outDir out9 --rootDir src --strict --skipLibCheck --module commonjs --target es2020 --moduleResolution node --noUnusedLocals false --noUnusedParameters false --noImplicitAny false "src/hippo/util/SystemUiHelper.ts" "src/hippo/util/SystemUiHelperImplHC.ts" "src/hippo/util/SystemUiHelperImplICS.ts" "src/hippo/util/SystemUiHelperImplJB.ts" "src/hippo/util/SystemUiHelperImplKK.ts" | Out-Null
Pop-Location
node "$PSScriptRoot/systemuihelper.test.js" "$d\out9\hippo"
exit $LASTEXITCODE
