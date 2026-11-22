# Register 运行时行为断言
$ErrorActionPreference = 'Stop'
$root = (git -C $PSScriptRoot rev-parse --show-toplevel) -replace '/', '\'
$d = Join-Path $env:TEMP 'tscheck'
$dst = Join-Path $d 'src\lib\yorozuya\collect'
New-Item -ItemType Directory -Force -Path $dst | Out-Null
Get-ChildItem "$root\harmony\entry\src\main\ets\hippo\lib\yorozuya\collect" -Filter *.ets | ForEach-Object {
  Copy-Item $_.FullName (Join-Path $dst ($_.BaseName + '.ts')) -Force
}
Copy-Item "$root\harmony\entry\src\main\ets\hippo\conaco\Register.ets" (Join-Path (New-Item -ItemType Directory -Force -Path (Join-Path $d 'src\conaco')).FullName 'Register.ts') -Force
Push-Location $d
node "$d\node_modules\typescript\bin\tsc" --noEmit false --outDir "$d\out" --strict --skipLibCheck --module commonjs --target es2020 --moduleResolution node --noUnusedLocals false --noUnusedParameters false "src\conaco\Register.ts" | Out-Null
Pop-Location
node "$PSScriptRoot/register.test.js" "$d\out"
exit $LASTEXITCODE
