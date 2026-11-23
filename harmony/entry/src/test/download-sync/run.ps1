# download-sync 纯逻辑单测运行器（C-10：harmony/entry/src/test/<module>/）
#
# 沿用 storage-db / gl-render 的约定：把 src/main/ets 与 src/test 整棵树按原结构复制到临时目录、
# 仅把 .ets 改名 .ts，于是测试里的 `../../main/ets/hippo/...` 相对路径原样成立，
# 不做任何 import 改写（改写规则一旦漂移，测试就测不到真实代码）。
#
# 与 storage-db 版的差异：本模块的测试只碰 @ohos.file.fs / @ohos.file.fileuri / @ohos.hilog /
# @ohos.util，且**刻意不 import 自己那 12 个 .ets**（它们现在全部挂起在 ../EhDB、../EhApplication、
# ../callBack/* 上）。等 core-runtime 交付这些文件后，可在同一 run.ps1 下再加 logic.test.ets。
#
# 用法：
#   pwsh -File harmony/entry/src/test/download-sync/run.ps1
#   pwsh -File .../run.ps1 -Filter arc-import
param(
  [string]$Filter = '',
  [switch]$Keep
)
$ErrorActionPreference = 'Stop'

$testDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$entryDir = Resolve-Path (Join-Path $testDir '..\..\..')
. (Join-Path (Resolve-Path (Join-Path $entryDir '..\..')).Path 'scripts\lib\test_assert.ps1')
Initialize-Utf8Console
$srcDir = Join-Path $entryDir 'src'
$work = Join-Path ([System.IO.Path]::GetTempPath()) ('download-sync-tests-' + $PID)

if (Test-Path $work) { Remove-Item $work -Recurse -Force }
New-Item -ItemType Directory -Force -Path $work | Out-Null

# ---- 1) 按原结构把 .ets 镜像成 .ts ----
function Copy-Tree([string]$from) {
  if (-not (Test-Path $from)) { return }
  Get-ChildItem $from -Recurse -File -Filter *.ets | ForEach-Object {
    $rel = $_.FullName.Substring($srcDir.Length + 1) -replace '\.ets$', '.ts'
    $dst = Join-Path $work $rel
    New-Item -ItemType Directory -Force (Split-Path $dst -Parent) | Out-Null
    Copy-Item $_.FullName $dst -Force
  }
}

Copy-Tree (Join-Path $srcDir 'main\ets')
Copy-Tree (Join-Path $srcDir 'test')

# ---- 1.5) 项目内“未交付依赖”的桩（与 staged 编译同思路：只补缺失的，不覆盖真实实现） ----
# 为什么需要：个别测试要 import 的产品文件，其依赖链上还挂着未交付的模块
# （EhApplication / SpiderQueen）。这里只在这些文件**不存在**时补一个最小桩，
# 真实文件一旦落地立即生效、桩自动失效。
$projectStubs = @{
  'main\ets\hippo\ehviewer\EhApplication.ts' = @"
import { DownloadManager } from './download/DownloadManager';
import { OkHttpClient } from '../okhttp/OkHttpClient';
export class EhApplication {
  static async getDownloadManager(context: Object | null): Promise<DownloadManager> { return null as unknown as DownloadManager; }
  static getOkHttpClient(context: Object | null): OkHttpClient { return null as unknown as OkHttpClient; }
  static removeDownloadTorrent(url: string): void { }
}
"@
  'main\ets\hippo\ehviewer\client\data\TorrentDownloadMessage.ts' = @"
export class TorrentDownloadMessage {
  static readonly KEY: string = 'torrent_download_message';
  path: string | null = null;
  dir: string | null = null;
  name: string | null = null;
  progress: number = 0;
  failed: boolean = false;
}
"@
  'main\ets\hippo\ehviewer\spider\SpiderQueen.ts' = @"
import { GalleryInfo } from '../client/data/GalleryInfo';
export interface OnSpiderListener {
  onGetPages(pages: number): void;
  onGet509(index: number): void;
  onPageDownload(index: number, contentLength: number, receivedSize: number, bytesRead: number): void;
  onPageSuccess(index: number, finished: number, downloaded: number, total: number): void;
  onPageFailure(index: number, error: string, finished: number, downloaded: number, total: number): void;
  onFinish(finished: number, downloaded: number, total: number): void;
  onGetImageSuccess(index: number, image: Object): void;
  onGetImageFailure(index: number, error: string): void;
}
export class SpiderQueen {
  static readonly SPIDER_INFO_FILENAME: string = '.ehviewer';
  static readonly MODE_READ: number = 0;
  static readonly MODE_DOWNLOAD: number = 1;
  static async obtainSpiderQueen(info: GalleryInfo, mode: number): Promise<SpiderQueen> { return null as unknown as SpiderQueen; }
  static async releaseSpiderQueen(queen: SpiderQueen, mode: number): Promise<void> { }
  static async resetReadingProgress(gid: number): Promise<void> { }
  addOnSpiderListener(listener: OnSpiderListener): void { }
  removeOnSpiderListener(listener: OnSpiderListener): void { }
}
"@
}
$stubbed = 0
foreach ($k in $projectStubs.Keys) {
  $dst = Join-Path $work $k
  if (Test-Path $dst) { continue }          # 真实实现已存在 → 不覆盖
  New-Item -ItemType Directory -Force (Split-Path $dst -Parent) | Out-Null
  [IO.File]::WriteAllText($dst, $projectStubs[$k], [Text.UTF8Encoding]::new($false))
  $stubbed++
}
if ($stubbed -gt 0) { Write-Host "项目桩：补了 $stubbed 个未交付依赖（EhApplication / SpiderQueen 等）" -ForegroundColor DarkGray }

# ---- 1.6) 运行期装饰器桩（@Observed/@Entry … 在 emit 后是真函数调用） ----
Copy-Item (Join-Path $testDir 'runtime-shims.js') (Join-Path $work 'runtime-shims.js') -Force

# ---- 2) @ohos.* 编译期 shim（只声明测试链路实际用到的） ----
$shim = @'
declare const Observed: <T extends Function>(target: T) => T;

declare module '@ohos.file.fs' {
  namespace fs {
    interface File { fd: number }
    interface Stat { size: number; mtime: number; isDirectory(): boolean; isFile(): boolean }
    const OpenMode: { READ_ONLY: number; WRITE_ONLY: number; READ_WRITE: number; CREATE: number; TRUNC: number; APPEND: number };
    const AccessModeType: { READ: number; WRITE: number; EXECUTE: number };
    function openSync(path: string, mode?: number): File;
    function closeSync(file: File | number): void;
    function statSync(file: string | number): Stat;
    function readSync(fd: number, buffer: ArrayBuffer, options?: { offset?: number; length?: number }): number;
    function writeSync(fd: number, buffer: ArrayBuffer | string, options?: { offset?: number; length?: number }): number;
    function fsyncSync(fd: number): void;
    function accessSync(path: string, mode?: number): boolean;
    function listFileSync(path: string, options?: { recursion?: boolean }): string[];
    function mkdirSync(path: string, recursion?: boolean): void;
    function rmdirSync(path: string): void;
    function unlinkSync(path: string): void;
    function renameSync(oldPath: string, newPath: string): void;
    function truncateSync(file: string | number, len?: number): void;
    function readTextSync(filePath: string, options?: Object): string;
    function copyFileSync(src: string | number, dest: string | number, mode?: number): void;
    function lstatSync(file: string): Stat;
    function open(path: string, mode?: number): Promise<File>;
    function close(file: File | number): Promise<void>;
    function stat(file: string | number): Promise<Stat>;
    function read(fd: number, buffer: ArrayBuffer, options?: { offset?: number; length?: number }): Promise<number>;
    function write(fd: number, buffer: ArrayBuffer | string, options?: { offset?: number; length?: number }): Promise<number>;
    function access(path: string, mode?: number): Promise<boolean>;
    function listFile(path: string, options?: { recursion?: boolean }): Promise<string[]>;
    function mkdir(path: string, recursion?: boolean): Promise<void>;
    function unlink(path: string): Promise<void>;
    function rename(oldPath: string, newPath: string): Promise<void>;
    function truncate(file: string | number, len?: number): Promise<void>;
  }
  export default fs;
}

declare module '@kit.CoreFileKit' {
  import fs from '@ohos.file.fs';
  export { fs as fileIo };
}

declare module '@kit.NetworkKit' {
  export namespace http {
    interface HttpProxy {
      host: string;
      port: number;
      exclusionList: string[];
    }
    interface HttpRequestOptions {
      method?: string;
      header?: Record<string, string>;
      expectDataType?: number;
      connectTimeout?: number;
      readTimeout?: number;
      usingProxy?: boolean | HttpProxy;
      remoteValidation?: string;
    }
    interface HttpRequest {
      on(event: string, cb: (arg: Object) => void): void;
      off(event: string): void;
      requestInStream(url: string, options?: HttpRequestOptions): Promise<number>;
      destroy(): void;
    }
    const RequestMethod: { GET: string; POST: string };
    const HttpDataType: { STRING: number; OBJECT: number; ARRAY_BUFFER: number };
    function createHttp(): HttpRequest;
  }
}

declare module '@ohos.app.ability.common' {
  namespace common {
    interface Context { filesDir: string; cacheDir: string }
  }
  export default common;
}

declare module '@ohos.data.relationalStore' {
  namespace relationalStore {
    const SecurityLevel: { S1: number; S2: number };
    const ConflictResolution: { ON_CONFLICT_NONE: number; ON_CONFLICT_REPLACE: number };
    class RdbPredicates { constructor(name: string) }
  }
  export default relationalStore;
}

declare module '@ohos.data.preferences' {
  namespace preferences {
    interface Preferences {
      get(key: string, def: Object): Promise<Object>;
      put(key: string, value: Object): Promise<void>;
      flush(): Promise<void>;
      getAll(): Promise<Object>;
      delete(key: string): Promise<void>;
    }
    function getPreferences(context: Object, name: string): Promise<Preferences>;
  }
  export default preferences;
}

declare module '@kit.BasicServicesKit' {
  export class BusinessError extends Error { code: number }
  export namespace systemDateTime {
    function getUptime(timeType: number, startTime?: number): number;
  }
}

declare module '@kit.ImageKit' {
  export namespace image { class PixelMap {} }
}

declare module '@ohos.multimedia.image' {
  namespace image {
    interface Size { width: number; height: number }
    interface ImageInfo { size: Size }
    interface DecodingOptions { desiredSize?: Size; desiredPixelFormat?: number; editable?: boolean }
    interface SourceOptions { sourceDensity?: number; desiredSize?: Size }
    class PixelMap {
      getImageInfoSync(): ImageInfo;
      release(): void;
      readPixelsToBuffer(dst: ArrayBuffer): Promise<void>;
      isEditable(): boolean;
    }
    class ImageSource {
      getImageInfo(): Promise<ImageInfo>;
      createPixelMap(options?: DecodingOptions): Promise<PixelMap>;
      release(): Promise<void>;
    }
    const PixelMapFormat: { RGBA_8888: number; RGB_565: number; BGRA_8888: number };
    const AlphaType: { UNKNOWN: number; OPAQUE: number; PREMUL: number; UNPREMUL: number };
    function createImageSource(buf: ArrayBuffer, options?: SourceOptions): ImageSource;
    function createPixelMap(buf: ArrayBuffer, options?: DecodingOptions): Promise<PixelMap>;
  }
  export default image;
}

declare module '@ohos.display' {
  namespace display {
    interface Display { width: number; height: number; densityPixels: number; scaledDensity: number }
    function getDefaultDisplaySync(): Display;
  }
  export default display;
}

declare module '@ohos.hidebug' {
  namespace hidebug {
    interface SystemMemInfo { totalMem: number; freeMem: number; availableMem: number }
    function getNativeHeapSize(): number;
    function getAppThreadCpuUsage(): Object;
    function getPss(): number;
    function getSystemMemInfo(): SystemMemInfo;
  }
  export default hidebug;
}

declare module '@ohos.file.fileuri' {
  namespace fileUri {
    function getUriFromPath(path: string): string;
  }
  export default fileUri;
}

declare module '@ohos.hilog' {
  namespace hilog {
    function debug(domain: number, tag: string, format: string, ...args: (string | number)[]): void;
    function info(domain: number, tag: string, format: string, ...args: (string | number)[]): void;
    function warn(domain: number, tag: string, format: string, ...args: (string | number)[]): void;
    function error(domain: number, tag: string, format: string, ...args: (string | number)[]): void;
  }
  export default hilog;
}

declare module '@kit.PerformanceAnalysisKit' {
  export namespace hilog {
    function debug(domain: number, tag: string, format: string, ...args: (string | number)[]): void;
    function info(domain: number, tag: string, format: string, ...args: (string | number)[]): void;
    function warn(domain: number, tag: string, format: string, ...args: (string | number)[]): void;
    function error(domain: number, tag: string, format: string, ...args: (string | number)[]): void;
  }
}

declare module '@ohos.util' {
  namespace util {
    class TextDecoder {
      constructor(encoding?: string);
      decode(input?: ArrayBuffer | Uint8Array): string;
      decodeToString(input?: ArrayBuffer | Uint8Array, options?: Object): string;
    }
    class TextEncoder {
      constructor(encoding?: string);
      encode(input?: string): Uint8Array;
      encodeInto(input?: string): Uint8Array;
      encodeInto(input: string, dest: Uint8Array): { read: number; written: number };
    }
  }
  export default util;
}

declare module '@ohos.i18n' {
  namespace i18n {
    namespace System {
      function getSystemLocaleInstance(): { toString(): string };
    }
  }
  export default i18n;
}

declare module '@kit.ArkUI' {
  export class UIContext {
    getPromptAction(): { showToast(opts: Object): void };
  }
}
'@
[System.IO.File]::WriteAllText((Join-Path $work 'shims.d.ts'), $shim, [Text.UTF8Encoding]::new($false))

# ---- 3) 运行期桩模块（node 侧真的被 require） ----
function New-StubModule([string]$name, [string]$js) {
  $dir = Join-Path $work "node_modules\$name"
  New-Item -ItemType Directory -Force $dir | Out-Null
  [System.IO.File]::WriteAllText((Join-Path $dir 'index.js'), $js, [Text.UTF8Encoding]::new($false))
  [System.IO.File]::WriteAllText((Join-Path $dir 'package.json'),
    "{ `"name`": `"$name`", `"version`": `"1.0.0`", `"main`": `"index.js`" }", [Text.UTF8Encoding]::new($false))
}

$tests = Get-ChildItem (Join-Path $work 'test\download-sync') -File -Filter '*.test.ts'
if ($Filter) { $tests = $tests | Where-Object { $_.Name -like "*$Filter*" } }
if (-not $tests) { throw "没有匹配的测试文件（Filter=$Filter）" }

Push-Location $work
try {
  if (-not (Test-Path 'node_modules\typescript')) {
    npm install typescript@5.4.5 --no-save --no-audit --no-fund --loglevel=error 2>&1 | Out-Null
  }
  New-StubModule '@ohos.file.fs' 'const stat = () => ({ size: 0, mtime: 0, isDirectory: () => false, isFile: () => true }); exports.OpenMode = { READ_ONLY: 0, WRITE_ONLY: 1, READ_WRITE: 2, CREATE: 64, TRUNC: 512, APPEND: 1024 }; exports.AccessModeType = { READ: 4, WRITE: 2, EXECUTE: 1 }; exports.fsyncSync = () => {}; exports.truncateSync = () => {}; exports.readTextSync = () => ""; exports.copyFileSync = () => {}; exports.statSync = stat; exports.lstatSync = stat; exports.accessSync = () => false; exports.listFileSync = () => []; exports.mkdirSync = () => {}; exports.unlinkSync = () => {}; exports.rmdirSync = () => {}; exports.renameSync = () => {}; exports.openSync = () => ({ fd: -1 }); exports.closeSync = () => {}; exports.open = async () => ({ fd: -1 }); exports.close = async () => {}; exports.stat = async () => stat(); exports.read = async () => 0; exports.write = async () => 0; exports.access = async () => false; exports.listFile = async () => []; exports.mkdir = async () => {}; exports.unlink = async () => {}; exports.rename = async () => {}; exports.truncate = async () => {}; exports.default = exports;'
  New-StubModule '@kit.CoreFileKit' 'exports.fileIo = require("@ohos.file.fs");'
  New-StubModule '@ohos.file.fileuri' 'exports.getUriFromPath = (p) => "file://" + p; exports.default = exports;'
  New-StubModule '@ohos.hilog' 'exports.debug = () => {}; exports.info = () => {}; exports.warn = () => {}; exports.error = () => {}; exports.default = exports;'
  New-StubModule '@ohos.util' 'exports.TextEncoder = class { encodeInto(s, dest) { const b = Buffer.from(s === undefined ? "" : s); if (dest) { const n = Math.min(b.length, dest.length); for (let i = 0; i < n; i++) { dest[i] = b[i]; } return { read: String(s || "").length, written: n }; } return new Uint8Array(b.buffer, b.byteOffset, b.byteLength); } encode(s) { return this.encodeInto(s); } }; exports.TextDecoder = class { decodeToString(buf) { if (!buf) { return ""; } const v = buf instanceof Uint8Array ? buf : new Uint8Array(buf); return Buffer.from(v).toString("utf8"); } decode(buf) { return this.decodeToString(buf); } }; exports.default = exports;'
  New-StubModule '@ohos.i18n' 'exports.System = { getSystemLocaleInstance: () => ({ toString: () => "zh-CN" }) }; exports.default = exports;'
  New-StubModule '@ohos.app.ability.common' 'exports.default = {};'
  New-StubModule '@ohos.data.relationalStore' 'exports.SecurityLevel = { S1: 1, S2: 2 }; exports.ConflictResolution = { ON_CONFLICT_NONE: 0, ON_CONFLICT_REPLACE: 5 }; exports.RdbPredicates = class { constructor(n) {} }; exports.default = exports;'
  New-StubModule '@ohos.data.preferences' 'exports.getPreferences = async () => ({ get: async () => undefined, put: async () => {}, flush: async () => {}, getAll: async () => ({}), delete: async () => {} }); exports.default = exports;'
  New-StubModule '@kit.BasicServicesKit' 'exports.BusinessError = class extends Error { constructor(m) { super(m); this.name = "BusinessError"; this.code = 0; } }; exports.systemDateTime = { getUptime: () => 0 };'
  New-StubModule '@kit.ImageKit' 'exports.image = {};'
  New-StubModule '@ohos.multimedia.image' 'exports.PixelMapFormat = { RGBA_8888: 3, RGB_565: 2, BGRA_8888: 4 }; exports.AlphaType = { UNKNOWN: 0, OPAQUE: 1, PREMUL: 2, UNPREMUL: 3 }; exports.createPixelMap = async () => ({}); exports.createImageSource = () => ({ getImageInfo: async () => ({ size: { width: 0, height: 0 } }), createPixelMap: async () => ({}), release: async () => {} }); exports.default = exports;'
  New-StubModule '@ohos.display' 'exports.getDefaultDisplaySync = () => ({ width: 1080, height: 1920, densityPixels: 3, scaledDensity: 3 }); exports.default = exports;'
  New-StubModule '@ohos.hidebug' 'exports.getNativeHeapSize = () => 0; exports.getAppThreadCpuUsage = () => ({}); exports.getPss = () => 0; exports.getSystemMemInfo = () => ({ totalMem: 0, freeMem: 0, availableMem: 0 }); exports.default = exports;'
  New-StubModule '@kit.PerformanceAnalysisKit' 'exports.hilog = { debug: () => {}, info: () => {}, warn: () => {}, error: () => {}, fatal: () => {}, isLoggable: () => false };'
  New-StubModule '@kit.ArkUI' 'exports.UIContext = class { getPromptAction() { return { showToast: () => {} }; } }; exports.promptAction = { showToast: () => {}, showDialog: async () => ({}), openCustomDialog: async () => 0 }; exports.router = { pushUrl: () => {}, back: () => {} }; exports.window = {};'
  New-StubModule '@kit.AbilityKit' 'exports.wantAgent = { getWantAgent: async () => ({}), OperationType: { START_ABILITY: 1 }, WantAgentFlags: { UPDATE_PRESENT_FLAG: 1 } }; exports.common = {}; exports.UIAbility = class {};'
  New-StubModule '@kit.NetworkKit' 'exports.connection = { createNetConnection: () => ({ on: () => {}, register: () => {}, unregister: () => {} }) }; exports.http = { createHttp: () => ({ on: () => {}, off: () => {}, requestInStream: async () => 200, destroy: () => {} }), RequestMethod: { GET: "GET" }, HttpDataType: { ARRAY_BUFFER: 2 } };'
  New-StubModule '@kit.BackgroundTasksKit' 'exports.backgroundTaskManager = { startBackgroundRunning: async () => {}, stopBackgroundRunning: async () => {}, BackgroundMode: { DATA_TRANSFER: 1 } };'
  New-StubModule '@ohos.notificationManager' 'exports.SlotType = { SERVICE_INFORMATION: 2, SOCIAL_COMMUNICATION: 1 }; exports.SlotLevel = { LEVEL_LOW: 2 }; exports.ContentType = { NOTIFICATION_CONTENT_BASIC_TEXT: 0, NOTIFICATION_CONTENT_LONG_TEXT: 1 }; exports.addSlot = async () => {}; exports.publish = async () => {}; exports.cancel = async () => {}; exports.default = exports;'
  New-StubModule '@ohos.app.ability.wantAgent' 'exports.getWantAgent = async () => ({}); exports.OperationType = { START_ABILITY: 1 }; exports.WantAgentFlags = { UPDATE_PRESENT_FLAG: 1 }; exports.default = exports;'
  New-StubModule '@ohos.zlib' 'exports.decompressFile = async () => {}; exports.compressFile = async () => {}; exports.default = exports;'
  New-StubModule '@ohos.file.picker' 'exports.DocumentViewPicker = class {}; exports.PhotoViewPicker = class {}; exports.default = exports;'

  $failed = 0
  $totalPass = 0
  $totalFail = 0
  foreach ($t in $tests) {
    $rel = 'test/download-sync/' + ($t.Name -replace '\.ts$', '')
    $out = Join-Path $work ('out/test/download-sync/' + ($t.Name -replace '\.ts$', '.js'))
    Write-Host "`n▶ $($t.Name)" -ForegroundColor Cyan

    # tsc 只对**本测试文件自身**的类型错误判失败；其它模块（unifile / glview / image 等）的
    # shim 覆盖不全只作告警 —— 那些文件的真实验证由 build_hap.ps1 负责，本运行器的职责是跑断言。
    $tscOut = npx tsc "$($rel).ts" shims.d.ts --outDir out --module commonjs --target ES2021 --strict `
      --experimentalDecorators --useUnknownInCatchVariables false --esModuleInterop --skipLibCheck `
      --lib ES2021,ES2021.String,DOM 2>&1
    $tscOut | Where-Object { $_ -match 'error TS' -and $_ -notmatch 'TS7016|TS2580|TS2584' } |
      ForEach-Object { Write-Host "  tsc(warn): $_" -ForegroundColor DarkYellow }
    $ownErrors = $tscOut | Where-Object { $_ -match 'error TS' -and $_ -match 'test[/\\]download-sync' }
    if ($ownErrors) {
      $ownErrors | ForEach-Object { Write-Host "  tsc: $_" -ForegroundColor Red }
      $failed++
      continue
    }
    if (-not (Test-Path $out)) {
      Write-Host "  tsc 未产出 JS（其它模块 shim 缺失导致整体失败）" -ForegroundColor Red
      $failed++
      continue
    }
    $res = Invoke-NodeTestFile -NodeArgs @('-r', './runtime-shims.js', $out)
    $totalPass += $res.Pass
    $totalFail += $res.Fail
    if ($res.ExitCode -ne 0 -or $res.Fail -gt 0) { $failed++ }
  }
  Write-Host "ASSERT_SUMMARY: PASS=$totalPass FAIL=$totalFail"
  if ($failed -gt 0) { throw "$failed 个测试文件失败" }
  Write-Host "`n全部测试通过（$totalPass 个断言）" -ForegroundColor Green
  exit 0
} finally {
  Pop-Location
  if (-not $Keep) { Remove-Item $work -Recurse -Force -ErrorAction SilentlyContinue }
}

