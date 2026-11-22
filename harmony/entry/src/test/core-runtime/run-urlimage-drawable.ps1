# URLImageGetter + DrawableManager 断言
$ErrorActionPreference = 'Stop'
$root = (git -C $PSScriptRoot rev-parse --show-toplevel) -replace '/', '\'
$d = Join-Path $env:TEMP 'tscheck'
$srcRoot = "$root\harmony\entry\src\main\ets\hippo"
New-Item -ItemType Directory -Force -Path "$d\src\hippo\text", "$d\src\hippo\util" | Out-Null
Copy-Item "$srcRoot\text\URLImageGetter.ets" "$d\src\hippo\text\URLImageGetter.ts" -Force
Copy-Item "$srcRoot\util\DrawableManager.ets" "$d\src\hippo\util\DrawableManager.ts" -Force
Push-Location $d
node "$d\node_modules\typescript\bin\tsc" --noEmit false --outDir out10 --rootDir src --strict --skipLibCheck --module commonjs --target es2020 --moduleResolution node --noUnusedLocals false --noUnusedParameters false --noImplicitAny false "src/hippo/text/URLImageGetter.ts" "src/hippo/util/DrawableManager.ts" | Out-Null
Pop-Location
node "$PSScriptRoot/urlimage-drawable.test.js" "$d\out10\hippo"
exit $LASTEXITCODE
