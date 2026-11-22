# ui-scene 纯逻辑单测运行器（C-10：harmony/entry/src/test/<module>/）
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
#   pwsh -File harmony/entry/src/test/ui-scene/run.ps1
#   pwsh -File .../run.ps1 -Filter arc-import
param(
  [string]$Filter = '',
  [switch]$Keep
)
$ErrorActionPreference = 'Stop'

$testDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$entryDir = Resolve-Path (Join-Path $testDir '..\..\..')
$srcDir = Join-Path $entryDir 'src'
$work = Join-Path ([System.IO.Path]::GetTempPath()) ('ui-scene-tests-' + $PID)

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
declare type ResourceStr = string | number;
declare type ResourceColor = string;
declare function $r(resource: string): string;
declare function $rawfile(name: string): string;

declare module '@ohos.file.fs' {
  namespace fs {
    interface File { fd: number; path: string }
    interface Stat { size: number; mtime: number; isDirectory(): boolean; isFile(): boolean }
    interface ReadOptions { offset?: number; length?: number }
    interface WriteOptions { offset?: number; length?: number }
    interface ListFileOptions { recursion?: boolean; listNum?: number }
    enum WhenceType { SEEK_SET = 0, SEEK_CUR = 1, SEEK_END = 2 }
    const OpenMode: { READ_ONLY: number; WRITE_ONLY: number; READ_WRITE: number; CREATE: number; TRUNC: number; APPEND: number };
    const AccessModeType: { READ: number; WRITE: number; EXECUTE: number };
    function openSync(path: string, mode?: number): File;
    function closeSync(file: File | number): void;
    function statSync(file: string | number): Stat;
    function readSync(fd: number, buffer: ArrayBuffer, options?: ReadOptions): number;
    function writeSync(fd: number, buffer: ArrayBuffer | string, options?: WriteOptions): number;
    function lseek(fd: number, offset: number, whence?: WhenceType): number;
    function fsyncSync(fd: number): void;
    function accessSync(path: string, mode?: number): boolean;
    function listFileSync(path: string, options?: ListFileOptions): string[];
    function mkdirSync(path: string, recursion?: boolean): void;
    function rmdirSync(path: string): void;
    function unlinkSync(path: string): void;
    function renameSync(oldPath: string, newPath: string): void;
    function truncateSync(file: string | number, len?: number): void;
    function readTextSync(filePath: string, options?: Object): string;
    function copyFileSync(src: string | number, dest: string | number, mode?: number): void;
    function lstatSync(file: string): Stat;
  }
  export default fs;
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

declare module '@kit.AbilityKit' {
  export class Want {
    bundleName?: string;
    abilityName?: string;
    moduleName?: string;
    action?: string;
    uri?: string;
    type?: string;
    parameters?: Record<string, Object>;
  }
  export namespace common {
    interface Context { filesDir: string; cacheDir: string }
    interface UIAbilityContext extends Context {}
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
    class FileUri {
      constructor(uriOrPath: string);
      readonly path: string;
      readonly name: string;
    }
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
    }
    class TextEncoder {
      constructor(encoding?: string);
      encode(input?: string): Uint8Array;
      encodeInto(input: string, dest: Uint8Array): { read: number; written: number };
    }
  }
  export default util;
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

$tests = Get-ChildItem (Join-Path $work 'test\ui-scene') -File -Filter '*.test.ts'
if ($Filter) { $tests = $tests | Where-Object { $_.Name -like "*$Filter*" } }
if (-not $tests) { throw "没有匹配的测试文件（Filter=$Filter）" }

Push-Location $work
try {
  if (-not (Test-Path 'node_modules\typescript')) {
    npm install typescript@5.4.5 --no-save --no-audit --no-fund --loglevel=error 2>&1 | Out-Null
  }
  $fsStubJs = @'
var __dirs = new Set(["/", "/tmp"]);
var __files = new Map();
var __fds = new Map();
var __fdSeq = 0;
exports.OpenMode = { READ_ONLY: 0, WRITE_ONLY: 1, READ_WRITE: 2, CREATE: 64, TRUNC: 512, APPEND: 1024 };
exports.AccessModeType = { READ: 4, WRITE: 2, EXECUTE: 1 };
exports.WhenceType = { SEEK_SET: 0, SEEK_CUR: 1, SEEK_END: 2 };
exports.__activeFdCount = function () { return __fds.size; };
function __norm(p) {
  var s = String(p || "").replace(/\\/g, "/");
  if (!s.startsWith("file://")) {
    s = s.replace(/\/+/g, "/");
    if (s.length > 1 && s.endsWith("/")) { s = s.slice(0, -1); }
  }
  return s;
}
function __parentOf(np) {
  var idx = np.lastIndexOf("/");
  return idx <= 0 ? "/" : np.slice(0, idx);
}
function __mkStat(size, isDir) {
  return { size: size, mtime: 0, isDirectory: function () { return isDir; }, isFile: function () { return !isDir; } };
}
function __toBuf(data) {
  if (typeof data === "string") { return Buffer.from(data, "utf8"); }
  if (Buffer.isBuffer(data)) { return Buffer.from(data); }
  if (ArrayBuffer.isView(data)) { return Buffer.from(data.buffer, data.byteOffset, data.byteLength); }
  if (data instanceof ArrayBuffer) { return Buffer.from(new Uint8Array(data)); }
  return Buffer.alloc(0);
}
exports.statSync = function (target) {
  if (typeof target === "number") {
    var rec = __fds.get(target);
    if (!rec) { throw new Error("EBADF: " + target); }
    return __mkStat(rec.entry.data.length, false);
  }
  var np = __norm(target);
  if (__dirs.has(np)) { return __mkStat(0, true); }
  if (__files.has(np)) { return __mkStat(__files.get(np).data.length, false); }
  return __mkStat(0, false);
};
exports.lstatSync = exports.statSync;
exports.accessSync = function (p) {
  var np = __norm(p);
  return __dirs.has(np) || __files.has(np);
};
exports.listFileSync = function (p) {
  var np = __norm(p);
  if (!__dirs.has(np)) { return []; }
  var out = [];
  __dirs.forEach(function (d) { if (d !== np && __parentOf(d) === np) { out.push(d.slice(d.lastIndexOf("/") + 1)); } });
  __files.forEach(function (_v, f) { if (__parentOf(f) === np) { out.push(f.slice(f.lastIndexOf("/") + 1)); } });
  return out;
};
exports.mkdirSync = function (p, recursion) {
  var np = __norm(p);
  if (__files.has(np)) { throw new Error("EEXIST: " + p); }
  if (recursion) {
    var parts = np.split("/");
    var cur = "";
    for (var i = 1; i < parts.length; i++) {
      cur += "/" + parts[i];
      if (__files.has(cur)) { throw new Error("ENOTDIR: " + cur); }
      __dirs.add(cur);
    }
    return;
  }
  if (__dirs.has(np)) { throw new Error("EEXIST: " + p); }
  __dirs.add(np);
};
exports.openSync = function (p, mode) {
  var np = __norm(p);
  var m = mode === undefined ? 0 : mode;
  if (__dirs.has(np)) { throw new Error("EISDIR: " + p); }
  var entry = __files.get(np);
  if (!entry) {
    if ((m & exports.OpenMode.CREATE) === 0) { throw new Error("ENOENT: " + p); }
    entry = { data: Buffer.alloc(0) };
    __files.set(np, entry);
  } else if ((m & exports.OpenMode.TRUNC) !== 0) {
    entry.data = Buffer.alloc(0);
  }
  __fdSeq += 1;
  var fd = __fdSeq;
  __fds.set(fd, { path: np, entry: entry, pos: (m & exports.OpenMode.APPEND) !== 0 ? entry.data.length : 0, mode: m });
  return { fd: fd, path: String(p) };
};
exports.closeSync = function (fileOrFd) {
  var fd = typeof fileOrFd === "number" ? fileOrFd : (fileOrFd && typeof fileOrFd.fd === "number" ? fileOrFd.fd : -1);
  if (fd < 0) { return; }
  if (!__fds.has(fd)) { throw new Error("EBADF: " + fd); }
  __fds.delete(fd);
};
exports.readSync = function (fd, b, o) {
  var rec = __fds.get(fd);
  if (!rec) { throw new Error("EBADF: " + fd); }
  var offOpt = (o && typeof o.offset === "number") ? o.offset : 0;
  var startPos = rec.pos + offOpt;
  var avail = rec.entry.data.length - startPos;
  if (avail <= 0) { return 0; }
  var dstLen = b ? b.byteLength : 0;
  var want = (o && typeof o.length === "number") ? Math.min(o.length, dstLen) : dstLen;
  var n = Math.max(0, Math.min(avail, want));
  var view = new Uint8Array(b);
  for (var i = 0; i < n; i++) { view[i] = rec.entry.data[startPos + i]; }
  rec.pos += n;
  return n;
};
exports.writeSync = function (fd, data, o) {
  var rec = __fds.get(fd);
  if (!rec) { throw new Error("EBADF: " + fd); }
  var src = __toBuf(data);
  var offOpt = (o && typeof o.offset === "number") ? o.offset : 0;
  var want = (o && typeof o.length === "number") ? Math.min(o.length, src.length) : src.length;
  var cur = rec.entry.data;
  var startPos = ((rec.mode & exports.OpenMode.APPEND) !== 0) ? cur.length : (rec.pos + offOpt);
  var endPos = startPos + want;
  var out = endPos > cur.length ? Buffer.concat([cur, Buffer.alloc(endPos - cur.length)]) : Buffer.from(cur);
  src.copy(out, startPos, 0, want);
  rec.entry.data = out;
  rec.pos = endPos;
  return want;
};
exports.lseek = function (fd, offset, whence) {
  var rec = __fds.get(fd);
  if (!rec) { throw new Error("EBADF: " + fd); }
  var w = whence === undefined ? exports.WhenceType.SEEK_SET : whence;
  var next = w === exports.WhenceType.SEEK_CUR ? rec.pos + offset : (w === exports.WhenceType.SEEK_END ? rec.entry.data.length + offset : offset);
  if (next < 0) { throw new Error("EINVAL: negative seek"); }
  rec.pos = next;
  return next;
};
exports.fsyncSync = function () {};
exports.truncateSync = function (target, len) {
  var entry = typeof target === "number" ? (__fds.get(target) ? __fds.get(target).entry : null) : __files.get(__norm(target));
  if (!entry) { throw new Error("ENOENT: " + target); }
  var n = Math.max(0, len || 0);
  if (n < entry.data.length) { entry.data = entry.data.slice(0, n); }
  else if (n > entry.data.length) { entry.data = Buffer.concat([entry.data, Buffer.alloc(n - entry.data.length)]); }
};
exports.unlinkSync = function (p) {
  var np = __norm(p);
  if (__dirs.has(np)) { throw new Error("EISDIR: " + p); }
  if (!__files.has(np)) { throw new Error("ENOENT: " + p); }
  __files.delete(np);
};
exports.rmdirSync = function (p) {
  var np = __norm(p);
  if (__files.has(np)) { throw new Error("ENOTDIR: " + p); }
  if (!__dirs.has(np)) { throw new Error("ENOENT: " + p); }
  var nonEmpty = false;
  __dirs.forEach(function (d) { if (d !== np && __parentOf(d) === np) { nonEmpty = true; } });
  __files.forEach(function (_v, f) { if (__parentOf(f) === np) { nonEmpty = true; } });
  if (nonEmpty) { throw new Error("ENOTEMPTY: " + p); }
  __dirs.delete(np);
};
exports.renameSync = function (oldP, newP) {
  var o = __norm(oldP), n = __norm(newP);
  if (__files.has(o)) { __files.set(n, __files.get(o)); __files.delete(o); return; }
  if (__dirs.has(o)) { __dirs.delete(o); __dirs.add(n); return; }
  throw new Error("ENOENT: " + oldP);
};
exports.readTextSync = function (p) { var e = __files.get(__norm(p)); return e ? e.data.toString("utf8") : ""; };
exports.copyFileSync = function (s, d) { var e = __files.get(__norm(s)); if (!e) { throw new Error("ENOENT: " + s); } __files.set(__norm(d), { data: Buffer.from(e.data) }); };
exports.default = exports;
'@
  $fileUriStubJs = @'
exports.getUriFromPath = function (p) { return "file://" + p; };
exports.FileUri = function FileUri(u) {
  var s = String(u || "");
  if (s.startsWith("file://")) {
    var r = s.slice(7);
    var idx = r.indexOf("/");
    this.path = idx >= 0 ? r.slice(idx) : "/";
  } else {
    this.path = s;
  }
  var seg = this.path.lastIndexOf("/");
  this.name = seg >= 0 ? this.path.slice(seg + 1) : this.path;
};
exports.default = exports;
'@
  New-StubModule '@ohos.file.fs' $fsStubJs
  New-StubModule '@ohos.file.fileuri' $fileUriStubJs
  New-StubModule '@ohos.hilog' 'exports.debug = () => {}; exports.info = () => {}; exports.warn = () => {}; exports.error = () => {}; exports.default = exports;'
  New-StubModule '@ohos.util' 'exports.TextEncoder = class { encode(s) { const b = Buffer.from(s === undefined ? "" : s); return new Uint8Array(b.buffer, b.byteOffset, b.byteLength); } encodeInto(s, dest) { const b = Buffer.from(s === undefined ? "" : s); if (dest) { const n = Math.min(b.length, dest.length); for (let i = 0; i < n; i++) { dest[i] = b[i]; } return { read: String(s || "").length, written: n }; } return new Uint8Array(b.buffer, b.byteOffset, b.byteLength); } }; exports.TextDecoder = class { decode(buf) { if (!buf) { return ""; } const v = buf instanceof Uint8Array ? buf : new Uint8Array(buf); return Buffer.from(v).toString("utf8"); } }; exports.default = exports;'
  New-StubModule '@ohos.app.ability.common' 'exports.default = {};'
  New-StubModule '@ohos.data.relationalStore' 'exports.SecurityLevel = { S1: 1, S2: 2 }; exports.ConflictResolution = { ON_CONFLICT_NONE: 0, ON_CONFLICT_REPLACE: 5 }; exports.RdbPredicates = class { constructor(n) {} }; exports.default = exports;'
  New-StubModule '@ohos.data.preferences' 'exports.getPreferences = async () => ({ get: async () => undefined, put: async () => {}, flush: async () => {}, getAll: async () => ({}), delete: async () => {} }); exports.default = exports;'
  New-StubModule '@kit.BasicServicesKit' 'exports.BusinessError = class extends Error { constructor(m) { super(m); this.name = "BusinessError"; this.code = 0; } }; exports.systemDateTime = { getUptime: () => 0 };'
  New-StubModule '@kit.ImageKit' 'exports.image = {};'
  New-StubModule '@ohos.multimedia.image' 'exports.PixelMapFormat = { RGBA_8888: 3, RGB_565: 2, BGRA_8888: 4 }; exports.AlphaType = { UNKNOWN: 0, OPAQUE: 1, PREMUL: 2, UNPREMUL: 3 }; exports.createPixelMap = async () => ({}); exports.createImageSource = () => ({ getImageInfo: async () => ({ size: { width: 0, height: 0 } }), createPixelMap: async () => ({}), release: async () => {} }); exports.default = exports;'
  New-StubModule '@ohos.display' 'exports.getDefaultDisplaySync = () => ({ width: 1080, height: 1920, densityPixels: 3, scaledDensity: 3 }); exports.default = exports;'
  New-StubModule '@ohos.hidebug' 'exports.getNativeHeapSize = () => 0; exports.getAppThreadCpuUsage = () => ({}); exports.getPss = () => 0; exports.getSystemMemInfo = () => ({ totalMem: 0, freeMem: 0, availableMem: 0 }); exports.default = exports;'
  New-StubModule '@kit.PerformanceAnalysisKit' 'exports.hilog = { debug: () => {}, info: () => {}, warn: () => {}, error: () => {}, fatal: () => {}, isLoggable: () => false };'
  New-StubModule '@kit.ArkUI' 'exports.promptAction = { showToast: () => {}, showDialog: async () => ({}), openCustomDialog: async () => 0 }; exports.router = { pushUrl: () => {}, back: () => {} }; exports.window = {};'
  New-StubModule '@kit.AbilityKit' 'exports.wantAgent = { getWantAgent: async () => ({}), OperationType: { START_ABILITY: 1 }, WantAgentFlags: { UPDATE_PRESENT_FLAG: 1 } }; exports.common = {}; exports.UIAbility = class {};'
  New-StubModule '@kit.NetworkKit' 'exports.connection = { createNetConnection: () => ({ on: () => {}, register: () => {}, unregister: () => {} }) }; exports.http = { createHttp: () => ({ on: () => {}, off: () => {}, requestInStream: async () => 200, destroy: () => {} }), RequestMethod: { GET: "GET" }, HttpDataType: { ARRAY_BUFFER: 2 } };'
  New-StubModule '@kit.BackgroundTasksKit' 'exports.backgroundTaskManager = { startBackgroundRunning: async () => {}, stopBackgroundRunning: async () => {}, BackgroundMode: { DATA_TRANSFER: 1 } };'
  New-StubModule '@ohos.notificationManager' 'exports.SlotType = { SERVICE_INFORMATION: 2, SOCIAL_COMMUNICATION: 1 }; exports.SlotLevel = { LEVEL_LOW: 2 }; exports.ContentType = { NOTIFICATION_CONTENT_BASIC_TEXT: 0, NOTIFICATION_CONTENT_LONG_TEXT: 1 }; exports.addSlot = async () => {}; exports.publish = async () => {}; exports.cancel = async () => {}; exports.default = exports;'
  New-StubModule '@ohos.app.ability.wantAgent' 'exports.getWantAgent = async () => ({}); exports.OperationType = { START_ABILITY: 1 }; exports.WantAgentFlags = { UPDATE_PRESENT_FLAG: 1 }; exports.default = exports;'
  New-StubModule '@ohos.zlib' 'exports.decompressFile = async () => {}; exports.compressFile = async () => {}; exports.default = exports;'
  New-StubModule '@ohos.file.picker' 'exports.DocumentViewPicker = class {}; exports.PhotoViewPicker = class {}; exports.default = exports;'

  $failed = 0
  foreach ($t in $tests) {
    $rel = 'test/ui-scene/' + ($t.Name -replace '\.ts$', '')
    $out = Join-Path $work ('out/test/ui-scene/' + ($t.Name -replace '\.ts$', '.js'))
    Write-Host "`n▶ $($t.Name)" -ForegroundColor Cyan

    # tsc 只对**本测试文件自身**的类型错误判失败；其它模块（unifile / glview / image 等）的
    # shim 覆盖不全只作告警 —— 那些文件的真实验证由 build_hap.ps1 负责，本运行器的职责是跑断言。
    $tscOut = npx tsc "$($rel).ts" shims.d.ts --outDir out --module commonjs --target ES2021 --strict `
      --experimentalDecorators --useUnknownInCatchVariables false --esModuleInterop --skipLibCheck `
      --lib ES2021,ES2021.String,DOM 2>&1
    $tscOut | Where-Object { $_ -match 'error TS' -and $_ -notmatch 'TS7016|TS2580|TS2584' } |
      ForEach-Object { Write-Host "  tsc(warn): $_" -ForegroundColor DarkYellow }
    $ownErrors = $tscOut | Where-Object { $_ -match 'error TS' -and $_ -match 'test[/\\]ui-scene' }
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
    node -r ./runtime-shims.js $out
    if ($LASTEXITCODE -ne 0) { $failed++ }
  }
  if ($failed -gt 0) { throw "$failed 个测试文件失败" }
  Write-Host "`n全部测试通过" -ForegroundColor Green
  exit 0
} finally {
  Pop-Location
  if (-not $Keep) { Remove-Item $work -Recurse -Force -ErrorAction SilentlyContinue }
}



