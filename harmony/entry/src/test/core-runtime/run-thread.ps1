# thread/ 等价层运行时断言
$ErrorActionPreference = 'Stop'
$root = (git -C $PSScriptRoot rev-parse --show-toplevel) -replace '/', '\'
$d = Join-Path $env:TEMP 'tscheck'
$dst = Join-Path $d 'src\lib\yorozuya\thread'
New-Item -ItemType Directory -Force -Path $dst | Out-Null
Get-ChildItem "$root\harmony\entry\src\main\ets\hippo\lib\yorozuya\thread" -Filter *.ets | ForEach-Object {
  Copy-Item $_.FullName (Join-Path $dst ($_.BaseName + '.ts')) -Force
}
Push-Location $d
node "$d\node_modules\typescript\bin\tsc" --noEmit false --outDir "$d\out" --strict --skipLibCheck --module commonjs --target es2020 --moduleResolution node --noUnusedLocals false --noUnusedParameters false "$dst\SerialThreadExecutor.ts" "$dst\InfiniteThreadExecutor.ts" "$dst\PriorityThreadFactory.ts" | Out-Null
Pop-Location
node "$PSScriptRoot/thread.test.js" "$d\out"
exit $LASTEXITCODE
