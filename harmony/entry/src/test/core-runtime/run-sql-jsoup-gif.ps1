# SqlUtils / JsoupUtils / GifHandler 断言
$ErrorActionPreference = 'Stop'
$root = (git -C $PSScriptRoot rev-parse --show-toplevel) -replace '/', '\'
$d = Join-Path $env:TEMP 'tscheck'
$srcRoot = "$root\harmony\entry\src\main\ets\hippo"
New-Item -ItemType Directory -Force -Path "$d\src\hippo\util" | Out-Null
foreach ($f in @('SqlUtils','JsoupUtils','GifHandler')) {
  Copy-Item "$srcRoot\util\$f.ets" "$d\src\hippo\util\$f.ts" -Force
}
Push-Location $d
node "$d\node_modules\typescript\bin\tsc" --noEmit false --outDir out10 --rootDir src --strict --skipLibCheck --module commonjs --target es2020 --moduleResolution node --noUnusedLocals false --noUnusedParameters false --noImplicitAny false "src/hippo/util/SqlUtils.ts" "src/hippo/util/JsoupUtils.ts" "src/hippo/util/GifHandler.ts" | Out-Null
Pop-Location
node "$PSScriptRoot/sql-jsoup-gif.test.js" "$d\out10\hippo"
exit $LASTEXITCODE
