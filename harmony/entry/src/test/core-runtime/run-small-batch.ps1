# 小件批断言（TimeUtils / MutableBoolean / SomethingNeedRefresh / GalleryActivityEvent）
$ErrorActionPreference = 'Stop'
$root = (git -C $PSScriptRoot rev-parse --show-toplevel) -replace '/', '\'
$d = Join-Path $env:TEMP 'tscheck'
. "$root\scripts\lib\sync_hippo.ps1"
Sync-HippoTree -SrcHippo "$root\harmony\entry\src\main\ets\hippo" -DstHippo "$d\src\hippo"
Push-Location $d
node "$d\node_modules\typescript\bin\tsc" --noEmit false --outDir out9 --rootDir src --strict --skipLibCheck --module commonjs --target es2020 --moduleResolution node --noUnusedLocals false --noUnusedParameters false --noImplicitAny false "src/hippo/util/TimeUtils.ts" "src/hippo/util/MutableBoolean.ts" "src/hippo/ehviewer/event/SomethingNeedRefresh.ts" "src/hippo/ehviewer/event/GalleryActivityEvent.ts" | Out-Null
Pop-Location
node "$PSScriptRoot/small-batch.test.js" "$d\out9\hippo"
exit $LASTEXITCODE
