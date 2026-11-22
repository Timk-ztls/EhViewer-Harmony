# 批次 3：FileUtils / PackageUtils / PermissionRequester + %.1f 修正
$ErrorActionPreference = 'Stop'
$root = (git -C $PSScriptRoot rev-parse --show-toplevel) -replace '/', '\'
$d = Join-Path $env:TEMP 'tscheck'
$srcRoot = "$root\harmony\entry\src\main\ets\hippo"
New-Item -ItemType Directory -Force -Path "$d\src\hippo\util", "$d\src\hippo\lib\yorozuya" | Out-Null
foreach ($f in @('FileUtils','PackageUtils','PermissionRequester','PermissionRequesterIo')) {
  Copy-Item "$srcRoot\util\$f.ets" "$d\src\hippo\util\$f.ts" -Force
}
Copy-Item "$srcRoot\lib\yorozuya\FileUtils.ets" "$d\src\hippo\lib\yorozuya\FileUtils.ts" -Force
. "$root\scripts\lib\tsc_gate.ps1"
if (-not (Invoke-TscGate -WorkDir $d -OutDir 'out11' -RootTs @('src/hippo/util/FileUtils.ts', 'src/hippo/util/PackageUtils.ts', 'src/hippo/util/PermissionRequester.ts', 'src/hippo/lib/yorozuya/FileUtils.ts') -Quiet)) { exit 1 }
node "$PSScriptRoot/batch3.test.js" "$d\out11\hippo"
exit $LASTEXITCODE
