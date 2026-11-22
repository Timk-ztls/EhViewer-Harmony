# MiuiOptimizationHelper 断言
$ErrorActionPreference = 'Stop'
$root = (git -C $PSScriptRoot rev-parse --show-toplevel) -replace '/', '\'
$d = Join-Path $env:TEMP 'tscheck'
New-Item -ItemType Directory -Force -Path "$d\src\hippo\ehviewer\util" | Out-Null
Copy-Item "$root\harmony\entry\src\main\ets\hippo\ehviewer\util\MiuiOptimizationHelper.ets" "$d\src\hippo\ehviewer\util\MiuiOptimizationHelper.ts" -Force
Push-Location $d
node "$d\node_modules\typescript\bin\tsc" --noEmit false --outDir out11 --rootDir src --strict --skipLibCheck --module commonjs --target es2020 --moduleResolution node --noUnusedLocals false --noUnusedParameters false --noImplicitAny false "src/hippo/ehviewer/util/MiuiOptimizationHelper.ts" | Out-Null
Pop-Location
node "$PSScriptRoot/miui-optimization.test.js" "$d\out11\hippo"
exit $LASTEXITCODE
