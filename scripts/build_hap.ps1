<#
  build_hap.ps1 —— 两段式构建：hvigor 出 unsigned HAP → 可选 hap-sign-tool 签名
  当 harmony/signing/ 下不存在本地签名材料或未设置 HAP_SIGN_PASSWORD 时，
  仍会正常产出 unsigned HAP 并以退出码 0 完成。

  用法：
    pwsh -File scripts/build_hap.ps1
    pwsh -File scripts/build_hap.ps1 -Mode release -Clean
    pwsh -File scripts/build_hap.ps1 -SdkHome <path> -JdkHome <path> -KeyAlias <alias>
#>
[CmdletBinding()]
param(
  [string]$Root = (Split-Path -Parent $PSScriptRoot),
  [ValidateSet('debug','release')][string]$Mode = 'debug',
  [switch]$Clean,
  [string]$JdkHome = '',
  [string]$SdkHome = '',
  [string]$KeyAlias = 'ehviewer_next'
)

$ErrorActionPreference = 'Stop'
$proj = Join-Path $Root 'harmony'
if (-not (Test-Path $proj)) { throw "找不到 harmony/ 工程：$proj" }

# ---- 环境：SDK 与 JDK 必须齐（hvigor 打包与签名都要 java）----
if (-not $SdkHome) { $SdkHome = @($env:DEVECO_SDK_HOME, $env:OHOS_BASE_SDK_HOME) | Where-Object { $_ -and (Test-Path $_) } | Select-Object -First 1 }
if (-not $SdkHome -and $env:LOCALAPPDATA) { $SdkHome = Join-Path $env:LOCALAPPDATA 'Huawei\Sdk' }
if (-not $SdkHome -or -not (Test-Path $SdkHome)) { throw "SDK 路径不存在：$SdkHome（可通过 -SdkHome 或环境变量 DEVECO_SDK_HOME 指定）" }
$env:DEVECO_SDK_HOME = $SdkHome
$env:OHOS_BASE_SDK_HOME = $SdkHome

if (-not $JdkHome) {
  $javaCmd = Get-Command java -ErrorAction SilentlyContinue
  $javaFromPath = if ($javaCmd) { Split-Path -Parent (Split-Path -Parent $javaCmd.Source) } else { $null }
  $jdkProgramFiles = if ($env:ProgramFiles) {
    Get-ChildItem (Join-Path $env:ProgramFiles 'Java') -Directory -Filter 'jdk*' -ErrorAction SilentlyContinue |
      Sort-Object Name -Descending |
      Select-Object -ExpandProperty FullName
  } else { @() }
  $cand = @($env:JAVA_HOME, $javaFromPath) + @($jdkProgramFiles) | Where-Object { $_ -and (Test-Path (Join-Path $_ 'bin\java.exe')) }
  $JdkHome = $cand | Select-Object -First 1
}
if (-not $JdkHome) { throw "未找到 JDK。请设置 JAVA_HOME 或传 -JdkHome（构建最后一步 PackageHap 需要 java）" }
$env:JAVA_HOME = $JdkHome
$env:PATH = "$JdkHome\bin;$env:PATH"

# ---- hvigor 用户缓存目录：必须可写 ----
# 每个 worktree 必须用独立的 hvigor 缓存目录。
# hvigor 的 project_caches 键随工程路径变化；多人共享同一 HVIGOR_USER_HOME 时，
# 某个 worktree 的 cache workspace 可能只装了插件而缺 @ohos/hvigor，
# 于是 hvigorfile.ts 里的 appTasks 注册到另一个 hvigor 实例 ->
# 报 00302013 "The root node is not yet available for build"（storage-db 定位并实测）
if (-not $env:HVIGOR_USER_HOME) { $env:HVIGOR_USER_HOME = Join-Path (Split-Path -Parent $Root) 'tools\hvigor-home' }
New-Item -ItemType Directory -Force -Path $env:HVIGOR_USER_HOME | Out-Null

$hvigor = Join-Path $proj 'hvigorw.bat'
if (-not (Test-Path $hvigor)) { throw "缺少 hvigorw.bat。请先用 DevEco Studio 打开 harmony/ 工程或安装 HarmonyOS Command Line Tools" }

Write-Host "SDK : $SdkHome" -ForegroundColor Cyan
Write-Host "JDK : $JdkHome" -ForegroundColor Cyan
Write-Host "工程: $proj" -ForegroundColor Cyan

if ($Clean) {
  Remove-Item (Join-Path $proj 'entry\build') -Recurse -Force -ErrorAction SilentlyContinue
  Write-Host "已清理 entry/build" -ForegroundColor Yellow
}

$cliArgs = @('assembleHap','--mode','module','-p','product=default','-p',"buildMode=$Mode",'--no-daemon')

function Invoke-Hvigor {
  Push-Location $proj
  try {
    Write-Host "`n▶ hvigorw $($cliArgs -join ' ')" -ForegroundColor Cyan
    $script:HvigorLog = cmd /c "hvigorw.bat $($cliArgs -join ' ')" 2>&1
    $script:HvigorLog | ForEach-Object { Write-Host $_ }
    return $LASTEXITCODE
  } finally { Pop-Location }
}

$code = Invoke-Hvigor

# ---- 自愈：仅当日志明确说找不到插件时才接入 ----
# 不能只看退出码：任何真实编译错误都会被 junction 重试盖成 root node 假错误（成员实测）
$pluginLink = Join-Path $proj 'node_modules\@ohos\hvigor-ohos-plugin'
$logText = ($script:HvigorLog -join "`n")
$missingPlugin = $logText -match "Cannot find module '@ohos/hvigor-ohos-plugin'"

if ($code -ne 0 -and $missingPlugin -and -not (Test-Path (Join-Path $pluginLink 'package.json'))) {
  Write-Host "`n确认缺插件（日志命中 Cannot find module），接入后重试" -ForegroundColor Yellow
  $cached = Get-ChildItem (Join-Path $env:HVIGOR_USER_HOME 'project_caches') -Directory -ErrorAction SilentlyContinue |
    ForEach-Object { Join-Path $_.FullName 'workspace\node_modules\@ohos\hvigor-ohos-plugin' } |
    Where-Object { Test-Path (Join-Path $_ 'package.json') } |
    Select-Object -First 1
  if ($cached) {
    New-Item -ItemType Directory -Force -Path (Split-Path $pluginLink -Parent) | Out-Null
    if (Test-Path $pluginLink) { cmd /c rmdir "$pluginLink" 2>&1 | Out-Null }
    # 用真实目录拷贝而非 mklink：目录联接会让 hvigor 看到两个不同的模块路径，
    # 触发 00302013 root node 假错误（ui-widget 实测：删链接即通，重建链接即挂）
    New-Item -ItemType Directory -Force -Path $pluginLink | Out-Null
    robocopy "$cached" "$pluginLink" /E /NFL /NDL /NJH /NJS /NP | Out-Null
    if (Test-Path (Join-Path $pluginLink 'package.json')) { Write-Host "  已拷贝插件: $cached" -ForegroundColor Green }
  } else {
    Push-Location $proj
    try {
      '{ "name": "hvigor-local", "version": "1.0.0", "private": true }' | Set-Content package.json -Encoding utf8
      npm install '@ohos/hvigor-ohos-plugin@6.26.2' --no-save --no-audit --no-fund --loglevel=error 2>&1 | Write-Host
    } finally { Pop-Location }
  }
  $code = Invoke-Hvigor
}

if ($code -ne 0) {
  Write-Host "`n---- hvigor 输出末尾 ----" -ForegroundColor Red
  ($script:HvigorLog | Select-Object -Last 25) | ForEach-Object { Write-Host $_ -ForegroundColor DarkGray }
  throw "hvigor 构建失败 exit=$code"
}

$outDir = Join-Path $proj "entry\build\default\outputs\default"
$unsigned = Join-Path $outDir 'entry-default-unsigned.hap'
if (-not (Test-Path $unsigned)) { throw "未找到 unsigned HAP：$unsigned" }

# ---- 第二段：可选本地签名（开源仓不含私钥与 profile，缺失则直接输出未签名 HAP） ----
$signing = Join-Path $proj 'signing'
$cert = if (Test-Path $signing) { Get-ChildItem $signing -Filter '*.cer' -File | Select-Object -First 1 -ExpandProperty FullName } else { $null }
$profile = if (Test-Path $signing) { Get-ChildItem $signing -Filter '*.p7b' -File | Select-Object -First 1 -ExpandProperty FullName } else { $null }
$p12 = if (Test-Path $signing) { Get-ChildItem $signing -Filter '*.p12' -File | Select-Object -First 1 -ExpandProperty FullName } else { $null }
$pwdFile = Join-Path $signing 'keystore-password.txt'
$keyPwd = if (-not [string]::IsNullOrWhiteSpace($env:HAP_SIGN_PASSWORD)) { $env:HAP_SIGN_PASSWORD.Trim() } elseif (Test-Path $pwdFile) { (Get-Content $pwdFile -Raw).Trim() } else { '' }
$hasSigning = (-not [string]::IsNullOrWhiteSpace($keyPwd)) -and $cert -and $profile -and $p12
if (-not $hasSigning) {
  Write-Host "`n⚠ 未找到本地签名材料（harmony/signing/*.cer,*.p7b,*.p12 + keystore-password.txt 或环境变量 HAP_SIGN_PASSWORD），输出未签名 HAP。" -ForegroundColor Yellow
  Write-Host "  如需真机安装，请在 DevEco Studio 中配置 Automatic Signing 或放置本地签名证书后重构建。" -ForegroundColor Yellow
  Write-Host "`n✓ 构建完成（未签名）: $unsigned ($([math]::Round((Get-Item $unsigned).Length/1KB,1)) KB)" -ForegroundColor Green
  exit 0
}

$signed = Join-Path $outDir "entry-default-$Mode-signed.hap"
if (Test-Path $signed) { Remove-Item $signed -Force }

$signTool = Get-ChildItem $SdkHome -Filter 'hap-sign-tool.jar' -Recurse -File -ErrorAction SilentlyContinue |
  Select-Object -First 1 -ExpandProperty FullName
if (-not $signTool) { throw "在 SDK 目录未找到 hap-sign-tool.jar：$SdkHome" }

Write-Host "`n▶ hap-sign-tool sign-app" -ForegroundColor Cyan
& "$JdkHome\bin\java.exe" -jar $signTool sign-app `
  -mode localSign -keyAlias $KeyAlias -signAlg 'SHA256withECDSA' `
  -appCertFile $cert -profileFile $profile -keystoreFile $p12 `
  -keystorePwd $keyPwd -keyPwd $keyPwd `
  -inFile $unsigned -outFile $signed 2>&1 | ForEach-Object { Write-Host $_ }
if (-not (Test-Path $signed)) { throw "签名失败，未产出 $signed" }

$size = [math]::Round((Get-Item $signed).Length / 1KB, 1)
Write-Host "`n✓ 构建完成: $signed ($size KB)" -ForegroundColor Green
Write-Host "  未签名产物: $unsigned ($([math]::Round((Get-Item $unsigned).Length/1KB,1)) KB)" -ForegroundColor Gray
Write-Host "  安装: hdc install `"$signed`"" -ForegroundColor Gray



