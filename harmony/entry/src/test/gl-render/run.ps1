# gl-render 纯逻辑单测运行器（C-10：harmony/entry/src/test/<module>/）
#
# 为什么需要这层转换：ArkTS 源码是 .ets，Node 不能直接执行；而 tsc 不认识 .ets 扩展名。
# 做法：把 src/main/ets 与 src/test 整棵树按原结构复制到临时目录、仅把 .ets 改名 .ts，
# 于是测试里 `../../main/ets/hippo/lib/glview/util/Rect` 这类相对路径原样成立，
# 不需要做任何 import 改写（改写规则一旦漂移，测试就测不到真实代码）。
#
# 用法：
#   pwsh -File harmony/entry/src/test/gl-render/run.ps1
#   pwsh -File .../run.ps1 -Filter commandstream
param(
  [string]$Filter = '',
  [switch]$Keep
)
$ErrorActionPreference = 'Stop'

$testDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$entryDir = Resolve-Path (Join-Path $testDir '..\..\..')   # harmony/entry
. (Join-Path (Resolve-Path (Join-Path $entryDir '..\..')).Path 'scripts\lib\test_assert.ps1')
Initialize-Utf8Console
$srcDir = Join-Path $entryDir 'src'
$work = Join-Path ([System.IO.Path]::GetTempPath()) ('gl-render-tests-' + $PID)

if (Test-Path $work) { Remove-Item $work -Recurse -Force }
New-Item -ItemType Directory -Force -Path $work | Out-Null

# ---- 1) 按原结构把 .ets 镜像成 .ts ----
function Copy-Tree([string]$from, [string]$to) {
  if (-not (Test-Path $from)) { return 0 }
  Get-ChildItem $from -Recurse -File -Filter *.ets | ForEach-Object {
    $rel = $_.FullName.Substring($srcDir.Length + 1) -replace '\.ets$', '.ts'
    $dst = Join-Path $work $rel
    New-Item -ItemType Directory -Force (Split-Path $dst -Parent) | Out-Null
    Copy-Item $_.FullName $dst -Force
  }
  return (Get-ChildItem (Join-Path $work $to) -Recurse -File -Filter *.ts -ErrorAction SilentlyContinue).Count
}

Copy-Tree (Join-Path $srcDir 'main\ets') 'main\ets' | Out-Null
Copy-Tree (Join-Path $srcDir 'test') 'test' | Out-Null

# ---- 2) @kit.* 的编译期 shim（ArkTS 运行时由系统提供，Node 里不需要真实实现） ----
$shim = @'
declare module '@kit.BasicServicesKit' {
  export const deviceInfo: { readonly sdkApiVersion: number; readonly osFullName: string };
  export interface BusinessError { code: number; message: string }
  export namespace systemDateTime {
    enum TimeType { STARTUP = 1, ACTIVE = 2 }
    function getUptime(timeType: TimeType, isNanoseconds?: boolean): number;
  }
}
declare module '@kit.PerformanceAnalysisKit' {
  export const hilog: {
    debug(domain: number, tag: string, format: string, ...args: (string | number)[]): void;
    info(domain: number, tag: string, format: string, ...args: (string | number)[]): void;
    warn(domain: number, tag: string, format: string, ...args: (string | number)[]): void;
    error(domain: number, tag: string, format: string, ...args: (string | number)[]): void;
  };
}
declare module '@kit.ArkGraphics2D' {
  export namespace drawing {
    interface Rect { left: number; top: number; right: number; bottom: number }
    interface FontMetrics { ascent: number; descent: number; leading?: number }
    enum FontEdging { ALIAS = 0, ANTI_ALIAS = 1, SUBPIXEL_ANTI_ALIAS = 2 }
    enum TextEncoding { TEXT_ENCODING_UTF8 = 0 }
    class Font {
      constructor();
      setSize(size: number): void;
      setEdging(edging: FontEdging): void;
      measureText(text: string, encoding: TextEncoding): number;
      getMetrics(): FontMetrics;
    }
    class Brush { setColor(color: common2D.Color): void }
    class Pen { setColor(color: common2D.Color): void; setStrokeWidth(w: number): void }
    class TextBlob { static makeFromString(text: string, font: Font, encoding: TextEncoding): TextBlob }
    class Canvas {
      constructor(pixelMap: object);
      drawRect(rect: common2D.Rect): void;
      drawLine(x1: number, y1: number, x2: number, y2: number): void;
      drawTextBlob(blob: TextBlob, x: number, y: number): void;
      drawImageRect(pm: object, src: common2D.Rect, dst: common2D.Rect): void;
      attachBrush(b: Brush): void;
      detachBrush(): void;
      attachPen(p: Pen): void;
      detachPen(): void;
      translate(dx: number, dy: number): void;
    }
  }
  export namespace common2D {
    interface Color { alpha: number; red: number; green: number; blue: number }
    interface Rect { left: number; top: number; right: number; bottom: number }
  }
}declare module '@kit.ImageKit' {
  export namespace image {
    interface Size { width: number; height: number }
    interface ImageInfo {
      size: Size; stride?: number; density?: number; mimeType?: string; isHdr?: boolean;
      pixelFormat?: number; alphaType?: number;
    }
    interface InitializationOptions {
      size: Size; editable?: boolean; scaleMode?: number;
      pixelFormat?: number; srcPixelFormat?: number; alphaType?: number;
    }
    interface PixelMap { getImageInfoSync(): ImageInfo; release(): void }
    // 值位置也要能用（TextMeasurer/DrawingText 里 `image.PixelMapFormat.RGBA_8888`）
    enum PixelMapFormat { UNKNOWN = 0, RGBA_8888 = 3, RGB_565 = 2 }
    enum AlphaType { UNKNOWN = 0, OPAQUE = 1, PREMUL = 2, UNPREMUL = 3 }
    function createPixelMapSync(options: InitializationOptions | ImageInfo): PixelMap;
  }
}
declare const console: { log(...args: unknown[]): void };
declare const process: { exit(code: number): never };
'@
[System.IO.File]::WriteAllText((Join-Path $work 'shims.d.ts'), $shim, [Text.UTF8Encoding]::new($false))

# ---- 2b) Node 全局声明（ArkTS 侧用系统计时器；Node 里就是全局 setTimeout） ----
$globals = @'
declare function setTimeout(cb: () => void, ms?: number): number;
declare function clearTimeout(id?: number): void;
declare function setInterval(cb: () => void, ms?: number): number;
declare function clearInterval(id?: number): void;
declare const process: { exit(code?: number): void; argv: string[] };
'@
[System.IO.File]::WriteAllText((Join-Path $work 'globals.d.ts'), $globals, [Text.UTF8Encoding]::new($false))

# ---- 4) tsc + node ----
$tests = Get-ChildItem (Join-Path $work 'test\gl-render') -File -Filter '*.test.ts'
if ($Filter) { $tests = $tests | Where-Object { $_.Name -like "*$Filter*" } }
if (-not $tests) { throw "没有匹配的测试文件（Filter=$Filter）" }

# Node 里没有 @kit 模块，用 node_modules 目录伪造（必须在 npm install 之后建，见下方注释）
#
# 形状要点：ArkTS 的 `import x from '@ohos.foo'` 编译成 `x = _m.default`（esModuleInterop），
# 所以桩必须**同时**导出 `default` 与 CJS 直接属性，否则运行期拿到 undefined 而不是报"模块缺失"，
# 会伪装成业务 bug（踩过：hidebug.getSystemMemInfo is not a function）。
function New-StubModule([string]$name, [string]$js) {
  $dir = Join-Path $work "node_modules\$name"
  New-Item -ItemType Directory -Force $dir | Out-Null
  $full = $js + "`nexports.__esModule = true;`nif (exports.default) { Object.assign(exports, exports.default); }`n"
  [System.IO.File]::WriteAllText((Join-Path $dir 'index.js'), $full, [Text.UTF8Encoding]::new($false))
  [System.IO.File]::WriteAllText((Join-Path $dir 'package.json'),
    "{ `"name`": `"$name`", `"version`": `"1.0.0`", `"main`": `"index.js`" }", [Text.UTF8Encoding]::new($false))
}

Push-Location $work
try {
  if (-not (Test-Path 'node_modules\typescript')) {
    npm install typescript@5.4.5 --no-save --no-audit --no-fund --loglevel=error 2>&1 | Out-Null
  }
  # 关键：npm install 会 prune 掉 package.json 之外的 node_modules，所以桩必须装完再建
  New-StubModule '@kit.PerformanceAnalysisKit' 'exports.hilog = { debug(){}, info(){}, warn(){}, error(){} };'
  New-StubModule '@kit.BasicServicesKit' 'exports.deviceInfo = { sdkApiVersion: 20, osFullName: "OpenHarmony" }; exports.systemDateTime = { getUptime: function () { return Date.now(); }, TimeType: { STARTUP: 1, ACTIVE: 2 } };'
  New-StubModule '@kit.ImageKit' 'exports.image = { PixelMapFormat: { RGBA_8888: 3 }, AlphaType: { PREMUL: 2, OPAQUE: 0 }, createPixelMapSync: function () { return {}; } };'
  New-StubModule '@kit.ArkUI' 'exports.display = { getDefaultDisplaySync: function () { return { densityPixels: 2.0, width: 1080, height: 2340 }; } };'
  New-StubModule '@kit.ArkGraphics2D' 'var d = { Canvas: function () { this.drawRect = function(){}; this.drawLine = function(){}; this.drawTextBlob = function(){}; this.drawImageRect = function(){}; this.attachBrush = function(){}; this.detachBrush = function(){}; this.attachPen = function(){}; this.detachPen = function(){}; this.translate = function(){}; }, Font: function () { this.setSize=function(){}; this.setEdging=function(){}; this.measureText=function(){ return 0; }; this.getMetrics=function(){ return { ascent: -1, descent: 1 }; }; }, Brush: function(){ this.setColor=function(){}; }, Pen: function(){ this.setColor=function(){}; this.setStrokeWidth=function(){}; }, TextBlob: { makeFromString: function(){ return {}; } }, Typeface: function(){}, FontEdging: { ALIAS: 0, ANTI_ALIAS: 1, SUBPIXEL_ANTI_ALIAS: 2 }, TextEncoding: { TEXT_ENCODING_UTF8: 0 } }; exports.drawing = d; exports.common2D = { Rect: function(){} };'
  New-StubModule '@ohos.hilog' 'var h = { debug(){}, info(){}, warn(){}, error(){}, isLoggable: function(){ return false; } }; exports.default = h; module.exports = h; module.exports.default = h;'
  New-StubModule '@ohos.display' 'var d = { getDefaultDisplaySync: function () { return { densityPixels: 2.0, width: 1080, height: 2340, densityDPI: 320, scaledDensity: 2.0 }; } }; exports.default = d; module.exports = d; module.exports.default = d;'
  # Image.ets (storage-db) / LayoutUtils 依赖的 @ohos.* 模块：Node 里只需存在，不调用
  # 注意：不要包含 '@ohos.display'（上面已有带 densityPixels 的实现，重复建会被覆盖）
  foreach ($m in @('@ohos.multimedia.image','@ohos.file.fs','@ohos.util','@ohos.app.ability.common')) {
    New-StubModule $m 'exports.default = {};'
  }
  # hidebug 要给真实形状：OSUtils.getTotalMemory() 会调 getSystemMemInfo()，
  # 返回一个"总内存 8GB"的假值，让 ImageCache 的 clamp(总内存/16, 32MB, 128MB) 得到 128MB
  New-StubModule '@ohos.hidebug' 'exports.default = { getSystemMemInfo: function () { return { totalMem: 8 * 1024 * 1024 * 1024 }; } };'
  $failed = 0
  $totalPass = 0
  $totalFail = 0
  foreach ($t in $tests) {
    $rel = 'test/gl-render/' + ($t.Name -replace '\.ts$', '')
    $out = Join-Path $work ('out/test/gl-render/' + ($t.Name -replace '\.ts$', '.js'))
    Write-Host "`n▶ $($t.Name)" -ForegroundColor Cyan
    # 只把「本模块作用域内」的类型错误算失败：test/gl-render、lib/glview、lib/glgallery。
    # 其它模块（storage-db 的 Image/Utils 等）在 ArkTS 下合法、但在 tsc 严格模式下会报
    # useUnknownInCatchVariables 之类的差异，那是他们的门禁，不是本模块的。
    $diag = npx tsc "$($rel).ts" shims.d.ts --outDir out --module commonjs --target ES2021 --strict --esModuleInterop --skipLibCheck --lib ES2021 globals.d.ts 2>&1 |
      Where-Object { $_ -match 'error TS' -and $_ -notmatch 'TS7016|TS2580|TS2584|TS2307|TS2503' }
    $mine = @($diag | Where-Object { $_ -match 'test[\\/]gl-render' -or $_ -match 'lib[\\/]glview' -or $_ -match 'lib[\\/]glgallery' })
    $others = @($diag | Where-Object { $mine -notcontains $_ })
    if ($others.Count -gt 0) {
      Write-Host ("  (其它模块 {0} 条类型差异，非本模块门禁，已忽略)" -f $others.Count) -ForegroundColor DarkGray
    }
    if ($mine.Count -gt 0) {
      $mine | ForEach-Object { Write-Host "  tsc: $_" -ForegroundColor Red }
      $failed++
      continue
    }
    $res = Invoke-NodeTestFile -NodeArgs @($out)
    $totalPass += $res.Pass
    $totalFail += $res.Fail
    if ($res.ExitCode -ne 0 -or $res.Fail -gt 0) { $failed++ }
  }
  Write-Host "ASSERT_SUMMARY: PASS=$totalPass FAIL=$totalFail"
  if (-not $Keep) { }
  if ($failed -gt 0) { throw "$failed 个测试文件失败" }
  Write-Host "`n全部测试通过（$totalPass 个断言）" -ForegroundColor Green
  exit 0
} finally { Pop-Location }
