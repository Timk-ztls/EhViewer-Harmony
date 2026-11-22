# PathNaturalComparator / ReadingRefreshRate / TextUrl 闭环断言
$ErrorActionPreference = 'Stop'
$root = (git -C $PSScriptRoot rev-parse --show-toplevel) -replace '/', '\'
$d = Join-Path $env:TEMP 'tscheck'
. "$root\scripts\lib\sync_hippo.ps1"
Sync-HippoTree -SrcHippo "$root\harmony\entry\src\main\ets\hippo" -DstHippo "$d\src\hippo"
Push-Location $d
node "$d\node_modules\typescript\bin\tsc" --noEmit false --outDir out9 --rootDir src --strict --skipLibCheck --module commonjs --target es2020 --moduleResolution node --noUnusedLocals false --noUnusedParameters false --noImplicitAny false "src/hippo/util/PathNaturalComparator.ts" "src/hippo/util/TextUrl.ts" "src/hippo/ehviewer/util/ReadingRefreshRate.ts" "src/hippo/text/Html.ts" | Out-Null
Pop-Location
node "$PSScriptRoot/path-reading-texturl.test.js" "$d\out9\hippo"
exit $LASTEXITCODE
