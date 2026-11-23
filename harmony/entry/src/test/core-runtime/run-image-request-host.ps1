# DefaultImageRequestHost：可见窗口队列优先、URL 切换孤儿取消、缩略图 Cache-Control: no-store
$ErrorActionPreference = 'Stop'
$root = (git -C $PSScriptRoot rev-parse --show-toplevel) -replace '/', '\'
$d = Join-Path $env:TEMP 'tscheck'
. "$root\scripts\lib\sync_hippo.ps1"
Sync-HippoTree -SrcHippo "$root\harmony\entry\src\main\ets\hippo" -DstHippo "$d\src\hippo"

# 仅剥离 LoadImageView.ts 末尾 @Component struct，保留纯 TS 控制器契约以供 tsc 编译
$lvPath = "$d\src\hippo\widget\LoadImageView.ts"
$lvText = Get-Content $lvPath -Raw
$compMatch = [regex]::Match($lvText, '(?m)^@Component\s*\r?$')
if ($compMatch.Success -and $compMatch.Index -gt 0) {
  $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
  [System.IO.File]::WriteAllText($lvPath, ($lvText.Substring(0, $compMatch.Index) -replace "`r`n", "`n"), $utf8NoBom)
}

. "$root\scripts\lib\tsc_gate.ps1"
if (-not (Invoke-TscGate -WorkDir $d -OutDir 'out_imghost' -RootTs @(
  'src/hippo/ehviewer/image/DefaultImageRequestHost.ts',
  'src/hippo/ehviewer/Settings.ts',
  'src/hippo/okhttp/Response.ts',
  'src/hippo/okhttp/ResponseBody.ts',
  'src/hippo/okhttp/Headers.ts'
) -Quiet)) { exit 1 }
node "$PSScriptRoot/image-request-host.test.js" "$d\out_imghost\hippo"
exit $LASTEXITCODE
