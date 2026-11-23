# storage-db 纯逻辑单测运行器（C-10：harmony/entry/src/test/<module>/）
#
# 沿用 gl-render 的约定：把 src/main/ets 与 src/test 整棵树按原结构复制到临时目录、
# 仅把 .ets 改名 .ts，于是测试里 `../../main/ets/hippo/...` 的相对路径原样成立，
# 不做任何 import 改写（改写规则一旦漂移，测试就测不到真实代码）。
#
# 与 gl-render 版的差异：本模块用到 @ohos.file.fs / @ohos.file.fileuri / @ohos.hilog /
# @ohos.data.relationalStore / @ohos.app.ability.common，shim 按 SDK d.ts 的
# 「declare namespace X + export default X」形式声明（含类型，供 `fs.File` 这类类型位置使用）。
#
# 用法：
#   pwsh -File harmony/entry/src/test/storage-db/run.ps1
#   pwsh -File .../run.ps1 -Filter spiderinfo
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
# 每个进程用自己的临时目录。
# 为什么：两个 run.ps1 同时跑（例如一个 -Filter 一个全量）时若共用同一目录，会出现
# 「A 进程 Remove-Item、B 进程正在 Copy」→ 镜像残缺 → tsc 报 "Cannot find module xxx"，
# 看起来像代码坏了，其实是测试基础设施的并发冲突（踩过一次，排查半小时）。
$work = Join-Path ([System.IO.Path]::GetTempPath()) ('storage-db-tests-' + $PID)

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

# ---- 2) @ohos.* / ArkTS 装饰器的编译期 shim ----
$shim = @'
declare const Observed: <T extends Function>(target: T) => T;
declare const Entry: <T extends Function>(target: T) => T;
declare const Component: <T extends Function>(target: T) => T;

declare module '@ohos.file.fs' {
  namespace fs {
    interface File { fd: number; path: string }
    interface Stat { size: number; mtime: number; isDirectory(): boolean; isFile(): boolean }
    interface ReadOptions { offset?: number; length?: number }
    interface WriteOptions { offset?: number; length?: number }
    interface ListFileOptions { recursion?: boolean; listNum?: number }
    const OpenMode: { READ_ONLY: number; WRITE_ONLY: number; READ_WRITE: number; CREATE: number; TRUNC: number; APPEND: number };
    const AccessModeType: { READ: number; WRITE: number; EXECUTE: number };
    function openSync(path: string, mode?: number): File;
    function closeSync(file: File | number): void;
    function statSync(file: string | number): Stat;
    function readSync(fd: number, buffer: ArrayBuffer, options?: ReadOptions): number;
    function writeSync(fd: number, buffer: ArrayBuffer | string, options?: WriteOptions): number;
    enum WhenceType { SEEK_SET = 0, SEEK_CUR = 1, SEEK_END = 2 }
    function lseek(fd: number, offset: number, whence?: WhenceType): number;
    function fsyncSync(fd: number): void;
    function truncateSync(file: string | number, len?: number): void;
    function accessSync(path: string, mode?: number): boolean;
    function listFileSync(path: string, options?: ListFileOptions): string[];
    function mkdirSync(path: string, recursion?: boolean): void;
    function rmdirSync(path: string): void;
    function unlinkSync(path: string): void;
    function renameSync(oldPath: string, newPath: string): void;
    function readTextSync(filePath: string, options?: Object): string;
    function copyFileSync(src: string | number, dest: string | number, mode?: number): void;
    function open(path: string, mode?: number): Promise<File>;
    function close(file: File | number): Promise<void>;
    function stat(file: string | number): Promise<Stat>;
    function read(fd: number, buffer: ArrayBuffer, options?: ReadOptions): Promise<number>;
    function write(fd: number, buffer: ArrayBuffer | string, options?: WriteOptions): Promise<number>;
    function access(path: string, mode?: number): Promise<boolean>;
    function listFile(path: string, options?: ListFileOptions): Promise<string[]>;
    function mkdir(path: string, recursion?: boolean): Promise<void>;
    function unlink(path: string): Promise<void>;
    function rename(oldPath: string, newPath: string): Promise<void>;
  }
  export default fs;
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

declare module '@ohos.data.relationalStore' {
  namespace relationalStore {
    type ValueType = string | number | boolean | null;
    type ValuesBucket = Record<string, ValueType>;
    interface StoreConfig { name: string; securityLevel: SecurityLevel }
    enum SecurityLevel { S1 = 1 }
    enum ConflictResolution { ON_CONFLICT_REPLACE = 5 }
    interface ResultSet {
      rowCount: number;
      getColumnIndex(name: string): number;
      isColumnNull(index: number): boolean;
      getString(index: number): string;
      getLong(index: number): number;
      getDouble(index: number): number;
      goToNextRow(): boolean;
      close(): void;
    }
    class RdbPredicates {
      constructor(table: string);
      equalTo(field: string, value: ValueType): RdbPredicates;
      like(field: string, value: string): RdbPredicates;
      orderByAsc(field: string): RdbPredicates;
      orderByDesc(field: string): RdbPredicates;
      limitAs(value: number): RdbPredicates;
      offsetAs(value: number): RdbPredicates;
    }
    interface RdbStore {
      version: number;
      insert(table: string, values: ValuesBucket, conflict?: ConflictResolution): Promise<number>;
      update(values: ValuesBucket, predicates: RdbPredicates): Promise<number>;
      delete(predicates: RdbPredicates): Promise<number>;
      querySql(sql: string, args?: Array<ValueType>): Promise<ResultSet>;
      executeSql(sql: string, args?: Array<ValueType>): Promise<void>;
      beginTransaction(): void;
      commit(): void;
      rollBack(): void;
      close(): Promise<void>;
    }
    function getRdbStore(context: Object, config: StoreConfig): Promise<RdbStore>;
    function deleteRdbStore(context: Object, name: string): Promise<void>;
  }
  export default relationalStore;
}

declare module '@ohos.app.ability.common' {
  namespace common {
    interface Context { readonly filesDir: string; readonly cacheDir: string; readonly tempDir: string }
    interface UIAbilityContext extends Context { }
  }
  export default common;
}

declare module '@kit.ImageKit' {
  export const image: {
    createImageSource(fd: number | string): { getImageInfoSync(): { size: { width: number; height: number } }; release(): void };
  };
}
declare module '@kit.PerformanceAnalysisKit' {
  export const hilog: { debug(...a: unknown[]): void; info(...a: unknown[]): void; warn(...a: unknown[]): void; error(...a: unknown[]): void };
  export const hiTraceMeter: { startTrace(...a: unknown[]): void; finishTrace(...a: unknown[]): void };
  export const hiAppEvent: { write(...a: unknown[]): void };
}
declare module '@ohos.data.preferences' {
  namespace preferences {
    type ValueType = string | number | boolean;
    interface Preferences { getSync(key: string, def: ValueType): ValueType; putSync(key: string, v: ValueType): void; hasSync(key: string): boolean; deleteSync(key: string): void; getAll(): Promise<Object>; getAllSync(): Object; flush(): Promise<void> }
    function getPreferences(ctx: Object, name: string): Promise<Preferences>;
    function getPreferences(ctx: Object, name: string, cb: Object): void;
    function getPreferencesSync(ctx: Object, name: string): Preferences;
  }
  export default preferences;
}

declare module '@ohos.multimedia.image' {
  namespace image {
    interface Size { width: number; height: number }
    interface ImageInfo { size: Size; density: number; pixelFormat?: number; alphaType?: number }
    interface DecodingOptions { desiredSize?: Size; desiredPixelFormat?: number; editable?: boolean; index?: number; sampleSize?: number; rotate?: number }
    enum AlphaType { UNKNOWN = 0, OPAQUE = 1, PREMUL = 2, UNPREMUL = 3 }
    enum PixelMapFormat { UNKNOWN = 0, RGB_565 = 2, RGBA_8888 = 3 }
    class PixelMap {
      getImageInfo(): ImageInfo;
      getImageInfoSync(): ImageInfo;
      readPixelsToBufferSync(dst: ArrayBuffer): void;
      writeBufferToPixelsSync(src: ArrayBuffer): void;
      release(): Promise<void>;
    }
    class ImageSource {
      getImageInfoSync(): ImageInfo;
      createPixelMapSync(opts?: Object): PixelMap;
      release(): Promise<void>;
    }
    function createImageSource(fd: number | string, opts?: Object): ImageSource;
    function createPixelMapSync(buf: ArrayBuffer, opts?: Object): PixelMap;
  }
  export default image;
}
declare module '@ohos.display' {
  namespace display {
    interface Display { width: number; height: number; densityPixels: number }
    function getDefaultDisplaySync(): Display;
  }
  export default display;
}
declare module '@ohos.hidebug' {
  namespace hidebug {
    interface SystemMemInfo { totalMem: number; freeMem: number; availableMem: number }
    function getPss(): number;
    function getSystemMemInfo(): SystemMemInfo;
  }
  export default hidebug;
}
declare module '@kit.BasicServicesKit' {
  export const systemDateTime: { getCurrentTime(isNano?: boolean): number };
  export const BusinessError: Object;
  export const zlib: {
    decompressFile(srcPath: string, outDir: string, options?: Object): Promise<void>;
  };
}
declare module '@ohos.util' {
  namespace util {
    class TextEncoder { constructor(encoding?: string); encodeInto(input?: string): Uint8Array; encodeIntoUint8Array(input: string, dest: Uint8Array): Object }
    class TextDecoder { constructor(encoding?: string); static create(encoding: string): TextDecoder; decodeToString(input: Uint8Array, options?: Object): string }
  }
  export default util;
}

declare function setTimeout(handler: () => void, timeout?: number): number;
declare function clearTimeout(id: number): void;
declare const console: { log(...args: unknown[]): void };
declare const process: { exit(code: number): never };
'@
[System.IO.File]::WriteAllText((Join-Path $work 'shims.d.ts'), $shim, [Text.UTF8Encoding]::new($false))

# 运行时装饰器：ArkTS 的 @Observed/@Entry/@Component 由编译器处理，Node 里必须自己兜
$decorators = @'
globalThis.Observed = (target) => target;
globalThis.Entry = (target) => target;
globalThis.Component = (target) => target;
'@
[System.IO.File]::WriteAllText((Join-Path $work '__decorators.js'), $decorators, [Text.UTF8Encoding]::new($false))

# ---- 3) 运行时桩：Node 里没有 @ohos.* 模块 ----
function New-StubModule([string]$name, [string]$js) {
  $dir = Join-Path $work "node_modules\$name"
  New-Item -ItemType Directory -Force $dir | Out-Null
  [System.IO.File]::WriteAllText((Join-Path $dir 'index.js'), $js, [Text.UTF8Encoding]::new($false))
  [System.IO.File]::WriteAllText((Join-Path $dir 'package.json'),
    "{ `"name`": `"$name`", `"version`": `"1.0.0`", `"main`": `"index.js`" }", [Text.UTF8Encoding]::new($false))
}

# 装饰器桩：优先用共享位置 harmony/entry/src/test/shared/decorators.js（其他模块复用同一份）
# 共享文件缺失时回落到本模块临时目录里的副本，保证测试仍能跑
$sharedDecorators = Join-Path $entryDir 'src\test\shared\decorators.js'
if (Test-Path $sharedDecorators) {
  $decoratorsJs = $sharedDecorators
} else {
  $decoratorsJs = Join-Path $work '__decorators.js'
}

$tests = Get-ChildItem (Join-Path $work 'test\storage-db') -File -Filter '*.test.ts'
if ($Filter) { $tests = $tests | Where-Object { $_.Name -like "*$Filter*" } }
if (-not $tests) { throw "没有匹配的测试文件（Filter=$Filter）" }

Push-Location $work
try {
  if (-not (Test-Path 'node_modules\typescript')) {
    npm install typescript@5.4.5 --no-save --no-audit --no-fund --loglevel=error 2>&1 | Out-Null
  }
  # 关键：npm install 会 prune 掉 package.json 之外的 node_modules，所以桩必须装完再建
  # fs 桩要足够真：ArchiveGalleryProvider 的 createRandomAccessFile 分支需要 openSync/statSync/readSync。
  # 约定：路径含 "unopenable" 时 openSync 抛错，这样"打不开文件"分支可测。
  $fsStubJs = @'
var __dirs = new Set(["/", "/tmp"]);
var __files = new Map();
var __fds = new Map();
var __fdSeq = 0;
exports.OpenMode = { READ_ONLY: 0, WRITE_ONLY: 1, READ_WRITE: 2, CREATE: 64, TRUNC: 512, APPEND: 1024 };
exports.AccessModeType = { READ: 4, WRITE: 2, EXECUTE: 1 };
exports.WhenceType = { SEEK_SET: 0, SEEK_CUR: 1, SEEK_END: 2 };
exports.__opened = [];
exports.__readCounters = {};
exports.__written = [];
exports.__closedFds = [];
exports.__activeFdCount = function () { return __fds.size; };
exports.__openFdEntries = function () {
  var out = [];
  __fds.forEach(function (v, k) { out.push({ fd: k, path: v.path }); });
  return out;
};
exports.__seedFile = function (p, data) {
  var np = __norm(p);
  var parts = np.split("/");
  var cur = "";
  for (var i = 1; i < parts.length - 1; i++) {
    cur += "/" + parts[i];
    __dirs.add(cur);
  }
  __files.set(np, { data: __toBuf(data) });
};
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
function __isLegacyGalleryDir(np) {
  return np.indexOf("gallery") >= 0 && !/\.[a-zA-Z0-9]+$/.test(np) && !__files.has(np) && !__dirs.has(np);
}
function __isLegacyGalleryFile(np) {
  return np.indexOf("gallery") >= 0 && /\.(jpg|jpeg|png|gif|webp|txt)$/i.test(np) && !__files.has(np) && !__dirs.has(np);
}
function __isLegacyZip(np) {
  return np.endsWith(".zip") && np.indexOf("unopenable") < 0 && !__files.has(np) && !__dirs.has(np);
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
    return __mkStat(rec.synthetic ? 1024 : rec.entry.data.length, false);
  }
  var np = __norm(target);
  if (__dirs.has(np)) { return __mkStat(0, true); }
  if (__files.has(np)) { return __mkStat(__files.get(np).data.length, false); }
  if (__isLegacyGalleryDir(np)) { return __mkStat(0, true); }
  if (__isLegacyGalleryFile(np) || __isLegacyZip(np)) { return __mkStat(1024, false); }
  throw new Error("ENOENT: no such file or directory: " + target);
};
exports.lstatSync = exports.statSync;
exports.accessSync = function (p) {
  var np = __norm(p);
  return __dirs.has(np) || __files.has(np) || __isLegacyGalleryDir(np) || __isLegacyGalleryFile(np) || __isLegacyZip(np);
};
exports.listFileSync = function (p) {
  var np = __norm(p);
  if (__dirs.has(np)) {
    var out = [];
    __dirs.forEach(function (d) { if (d !== np && __parentOf(d) === np) { out.push(d.slice(d.lastIndexOf("/") + 1)); } });
    __files.forEach(function (_v, f) { if (__parentOf(f) === np) { out.push(f.slice(f.lastIndexOf("/") + 1)); } });
    return out;
  }
  if (String(p).indexOf("gallery") >= 0 && !__files.has(np)) {
    return ["b10.jpg", "b2.jpg", "b1.jpg", "note.txt", "c3.PNG"];
  }
  throw new Error("fake: not a directory: " + p);
};
exports.mkdirSync = function (p, recursion) {
  var np = __norm(p);
  if (__files.has(np)) { throw new Error("EEXIST: file exists: " + p); }
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
  var par = __parentOf(np);
  if (par !== "/" && !__dirs.has(par)) { throw new Error("ENOENT: missing parent: " + par); }
  __dirs.add(np);
};
exports.openSync = function (p, mode) {
  if (String(p).indexOf("unopenable") >= 0) { throw new Error("fake open failure"); }
  exports.__opened.push(String(p));
  var np = __norm(p);
  var m = mode === undefined ? 0 : mode;
  if (__dirs.has(np)) { throw new Error("EISDIR: " + p); }
  var entry = __files.get(np);
  var synthetic = false;
  if (!entry) {
    if ((m & exports.OpenMode.CREATE) === 0) {
      if (__isLegacyZip(np) || __isLegacyGalleryFile(np)) {
        synthetic = true;
      } else {
        throw new Error("ENOENT: no such file: " + p);
      }
    } else {
      var par = __parentOf(np);
      if (par === "/tmp/outdir" && !__dirs.has(par) && !__files.has(par)) { __dirs.add(par); }
      if (par !== "/" && !__dirs.has(par)) { throw new Error("ENOENT: missing parent: " + par); }
      entry = { data: Buffer.alloc(0) };
      __files.set(np, entry);
    }
  } else if ((m & exports.OpenMode.TRUNC) !== 0) {
    entry.data = Buffer.alloc(0);
  }
  __fdSeq += 1;
  var fd = __fdSeq;
  exports.__readCounters[fd] = 0;
  __fds.set(fd, {
    path: np,
    entry: entry,
    pos: (!synthetic && (m & exports.OpenMode.APPEND) !== 0) ? entry.data.length : 0,
    mode: m,
    synthetic: synthetic
  });
  return { fd: fd, path: String(p) };
};
exports.closeSync = function (fileOrFd) {
  var fd = typeof fileOrFd === "number" ? fileOrFd : (fileOrFd && typeof fileOrFd.fd === "number" ? fileOrFd.fd : -1);
  if (!__fds.has(fd)) { throw new Error("EBADF: double close or invalid fd: " + fd); }
  __fds.delete(fd);
  exports.__closedFds.push(fd);
};
exports.readSync = function (fd, b, o) {
  var rec = __fds.get(fd);
  if (!rec) { throw new Error("EBADF: " + fd); }
  if (rec.synthetic) {
    var c = exports.__readCounters[fd] === undefined ? 0 : exports.__readCounters[fd];
    if (c >= 1) { return 0; }
    exports.__readCounters[fd] = c + 1;
    var wantSyn = (o && o.length) ? o.length : (b ? b.byteLength : 4);
    var nSyn = Math.min(4, wantSyn);
    var vSyn = new Uint8Array(b);
    for (var j = 0; j < nSyn; j++) { vSyn[j] = 65 + j; }
    return nSyn;
  }
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
  if (rec.synthetic) {
    var lenSyn = (data && data.byteLength) ? data.byteLength : 0;
    exports.__written.push(lenSyn);
    return lenSyn;
  }
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
  exports.__written.push(want);
  return want;
};
exports.lseek = function (fd, offset, whence) {
  var rec = __fds.get(fd);
  if (!rec) { throw new Error("EBADF: " + fd); }
  var w = whence === undefined ? exports.WhenceType.SEEK_SET : whence;
  var len = rec.synthetic ? 1024 : rec.entry.data.length;
  var next = w === exports.WhenceType.SEEK_CUR ? rec.pos + offset : (w === exports.WhenceType.SEEK_END ? len + offset : offset);
  if (next < 0) { throw new Error("EINVAL: negative seek offset: " + next); }
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
  if (nonEmpty) { throw new Error("ENOTEMPTY: directory not empty: " + p); }
  __dirs.delete(np);
};
exports.renameSync = function (oldP, newP) {
  var o = __norm(oldP), n = __norm(newP);
  if (__files.has(o)) { __files.set(n, __files.get(o)); __files.delete(o); return; }
  if (__dirs.has(o)) {
    var toMoveD = [], toMoveF = [];
    __dirs.forEach(function (d) { if (d === o || d.startsWith(o + "/")) { toMoveD.push(d); } });
    __files.forEach(function (_v, f) { if (f.startsWith(o + "/")) { toMoveF.push(f); } });
    toMoveD.forEach(function (d) { __dirs.delete(d); __dirs.add(n + d.slice(o.length)); });
    toMoveF.forEach(function (f) { __files.set(n + f.slice(o.length), __files.get(f)); __files.delete(f); });
    return;
  }
  throw new Error("ENOENT: " + oldP);
};
exports.readTextSync = function (p) { var e = __files.get(__norm(p)); return e ? e.data.toString("utf8") : ""; };
exports.copyFileSync = function (s, d) { var e = __files.get(__norm(s)); if (!e) { throw new Error("ENOENT: " + s); } __files.set(__norm(d), { data: Buffer.from(e.data) }); };
exports.open = function (p, m) { return Promise.resolve(exports.openSync(p, m)); };
exports.close = function (f) { exports.closeSync(f); return Promise.resolve(); };
exports.stat = function (t) { return Promise.resolve(exports.statSync(t)); };
exports.read = function (fd, b, o) { return Promise.resolve(exports.readSync(fd, b, o)); };
exports.write = function (fd, d, o) { return Promise.resolve(exports.writeSync(fd, d, o)); };
exports.access = function (p, m) { return Promise.resolve(exports.accessSync(p, m)); };
exports.listFile = function (p, o) { return Promise.resolve(exports.listFileSync(p, o)); };
exports.mkdir = function (p, r) { exports.mkdirSync(p, r); return Promise.resolve(); };
exports.unlink = function (p) { exports.unlinkSync(p); return Promise.resolve(); };
exports.rename = function (o, n) { exports.renameSync(o, n); return Promise.resolve(); };
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
  New-StubModule '@ohos.data.relationalStore' 'exports.SecurityLevel = { S1: 1 }; exports.ConflictResolution = { ON_CONFLICT_REPLACE: 5 }; exports.RdbPredicates = class {}; exports.default = exports;'
  New-StubModule '@ohos.app.ability.common' 'exports.default = {};'
  New-StubModule '@ohos.data.preferences' 'exports.default = { getPreferencesSync: () => ({ getSync: (k, d) => d, putSync: () => {}, flush: async () => {} }) };'
  New-StubModule '@kit.ImageKit' 'exports.image = { createImageSource: () => ({ getImageInfoSync: () => ({ size: { width: 0, height: 0 } }), release(){} }) };'
  New-StubModule '@ohos.util' 'exports.TextEncoder = class { encodeInto(s){ return new Uint8Array(Buffer.from(String(s === undefined ? "" : s))); } encodeIntoUint8Array(s,d){ return { read: 0, written: 0 }; } }; exports.TextDecoder = class { constructor(){} static create(){ return new exports.TextDecoder(); } decodeToString(b){ return Buffer.from(b === undefined ? new Uint8Array() : b).toString("utf8"); } decodeWithStream(){ return ""; } }; exports.default = exports;'
  New-StubModule '@ohos.hidebug' 'exports.getPss = function(){ return 0; }; exports.getSystemMemInfo = function(){ return { totalMem: 0, freeMem: 0, availableMem: 0 }; }; exports.default = exports;'
  New-StubModule '@ohos.multimedia.image' 'function mkPm(buf, opts){ var w = (opts && opts.size && opts.size.width) || 2; var h = (opts && opts.size && opts.size.height) || 2; var raw = buf ? Buffer.from(new Uint8Array(buf)) : Buffer.alloc(w * h * 4); return { getImageInfoSync: function(){ return { size: { width: w, height: h } }; }, readPixelsToBufferSync: function(dst){ var v = new Uint8Array(dst); v.set(raw.subarray(0, v.length)); }, writeBufferToPixelsSync: function(src){ raw = Buffer.from(new Uint8Array(src)); }, release: async function(){} }; } function src(){ return { getImageInfoSync: function(){ return { size: { width: 0, height: 0 } }; }, createPixelMapSync: function(opts){ return mkPm(null, opts); }, release: async function(){} }; } exports.createImageSource = function(){ return src(); }; exports.createPixelMapSync = function(buf, opts){ return mkPm(buf, opts); }; exports.AlphaType = { UNKNOWN: 0, OPAQUE: 1, PREMUL: 2, UNPREMUL: 3 }; exports.PixelMapFormat = { UNKNOWN: 0, RGBA_8888: 3 }; exports.default = exports;'
  New-StubModule '@ohos.display' 'exports.getDefaultDisplaySync = function(){ return { width: 1080, height: 1920, densityPixels: 3, scaledDensity: 3 }; }; exports.default = exports;'
  New-StubModule '@kit.BasicServicesKit' 'exports.systemDateTime = { getCurrentTime: () => Date.now() }; exports.BusinessError = class {}; exports.zlib = { decompressFile: async () => { throw new Error("zlib stub: not a valid zip"); } };'
  New-StubModule '@kit.PerformanceAnalysisKit' 'exports.hilog = { debug(){}, info(){}, warn(){}, error(){} }; exports.hiTraceMeter = { startTrace(){}, finishTrace(){} }; exports.hiAppEvent = { write(){} };'

  $failed = 0
  $totalPass = 0
  $totalFail = 0
  foreach ($t in $tests) {
    $rel = 'test/storage-db/' + ($t.Name -replace '\.ts$', '')
    $out = Join-Path $work ('out/test/storage-db/' + ($t.Name -replace '\.ts$', '.js'))
    Write-Host "`n▶ $($t.Name)" -ForegroundColor Cyan
    # tsc 只对「我自己负责的包 + 测试文件」做门禁。
    # 依赖链上游（beerbelly / okhttp / glview / Settings ...）的报错一律来自我这份 SDK shim 不完整
    # （shim 永远追不上平台 d.ts），不是被测代码的问题 —— 把它们计入会让测试永远跑不起来。
    # 这本身是一条「测量陷阱」：门禁口径必须写清楚，否则"红"和"绿"都没有意义。
    $tscOut = npx tsc "$($rel).ts" shims.d.ts --outDir out --module commonjs --target ES2021 --strict --experimentalDecorators --useUnknownInCatchVariables false --esModuleInterop --skipLibCheck --lib ES2021 2>&1
    $mine = $tscOut | Where-Object { $_ -match 'error TS' -and ($_ -match 'main/ets/hippo/(unifile|io|database|dao|spider|gallery|lib/image)/' -or $_ -match 'test/storage-db/') }
    $foreign = ($tscOut | Where-Object { $_ -match 'error TS' -and $_ -notmatch 'main/ets/hippo/(unifile|io|database|dao|spider|gallery|lib/image)/' -and $_ -notmatch 'test/storage-db/' }).Count
    if ($foreign -gt 0) { Write-Host "  （依赖链 shim 缺失 $foreign 条，不计入门禁）" -ForegroundColor DarkGray }
    if ($mine) {
      $mine | ForEach-Object { Write-Host "  tsc: $_" -ForegroundColor Yellow }
      $failed++; continue
    }
    $res = Invoke-NodeTestFile -NodeArgs @('--require', $decoratorsJs, $out)
    $totalPass += $res.Pass
    $totalFail += $res.Fail
    if ($res.ExitCode -ne 0 -or $res.Fail -gt 0) { $failed++ }
  }
  Write-Host "ASSERT_SUMMARY: PASS=$totalPass FAIL=$totalFail"
  if ($failed -gt 0) { throw "$failed 个测试文件失败" }
  Write-Host "`n全部测试通过（$totalPass 个断言）" -ForegroundColor Green
  exit 0
} finally { Pop-Location }
