# R-08 / R-10：importDB 逐表合并的去重判据 + migrate 写回 version
$ErrorActionPreference = 'Stop'
$root = (git -C $PSScriptRoot rev-parse --show-toplevel) -replace '/', '\'
$d = Join-Path $env:TEMP 'tscheck'
Copy-Item "$root\harmony\entry\src\main\ets\hippo\ehviewer\EhDB.ets" "$d\src\hippo\ehviewer\EhDB.ts" -Force
Push-Location $d
node "$d\node_modules\typescript\bin\tsc" --noEmit false --outDir out11 --rootDir src --strict --skipLibCheck --module commonjs --target es2020 --moduleResolution node --noUnusedLocals false --noUnusedParameters false --noImplicitAny false "src/hippo/ehviewer/EhDB.ts" | Out-Null
Pop-Location
node "$PSScriptRoot/importdb-merge.test.js" "$d\out11\hippo"
exit $LASTEXITCODE
