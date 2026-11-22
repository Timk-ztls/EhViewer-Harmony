# Html.toHtml / escapeHtml 运行时断言
$ErrorActionPreference = 'Stop'
$root = (git -C $PSScriptRoot rev-parse --show-toplevel) -replace '/', '\'
$d = Join-Path $env:TEMP 'tscheck'
New-Item -ItemType Directory -Force -Path (Join-Path $d 'src\hippo\text') | Out-Null
Copy-Item "$root\harmony\entry\src\main\ets\hippo\text\Html.ets" (Join-Path $d 'src\hippo\text\Html.ts') -Force
Push-Location $d
node "$d\node_modules\typescript\bin\tsc" --noEmit false --outDir "$d\out6" --rootDir src --strict --skipLibCheck --module commonjs --target es2020 --moduleResolution node --noUnusedLocals false --noUnusedParameters false --noImplicitAny false "src\hippo\text\Html.ts" | Out-Null
Pop-Location
node "$PSScriptRoot/html.test.js" "$d\out6\hippo\text"
exit $LASTEXITCODE
