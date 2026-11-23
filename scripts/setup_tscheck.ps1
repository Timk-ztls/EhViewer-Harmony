<#
  setup_tscheck.ps1 -- Bootstrap `$env:TEMP\tscheck` for standalone / CI unit test runs.
  Installs `typescript@^5.4.5` when missing and writes lightweight CommonJS stubs
  for `@ohos.*` / `@kit.*` modules used by `scripts/run_all_tests.ps1`.
#>
[CmdletBinding()]
param(
  [string]$WorkDir = (Join-Path $env:TEMP 'tscheck'),
  [switch]$Force
)

$ErrorActionPreference = 'Stop'
$utf8NoBom = [System.Text.UTF8Encoding]::new($false)

New-Item -ItemType Directory -Force -Path $WorkDir | Out-Null
$pkgPath = Join-Path $WorkDir 'package.json'
if ($Force -or -not (Test-Path $pkgPath)) {
  [IO.File]::WriteAllText($pkgPath, "{`n  `"private`": true,`n  `"dependencies`": {`n    `"typescript`": `"5.4.5`"`n  }`n}`n", $utf8NoBom)
}

$tscJs = Join-Path $WorkDir 'node_modules\typescript\lib\tsc.js'
if ($Force -or -not (Test-Path $tscJs)) {
  Write-Host "Installing TypeScript into $WorkDir..." -ForegroundColor Cyan
  Push-Location $WorkDir
  try {
    npm install --no-audit --no-fund --loglevel=error
    if ($LASTEXITCODE -ne 0) { throw "npm install typescript failed (exit=$LASTEXITCODE)" }
  } finally {
    Pop-Location
  }
}

$fsStub = @'
'use strict';
const files = new Map();
const dirs = new Set(['/']);
function norm(p) { return p.replace(/\/+/g, '/').replace(/\/$/, '') || '/'; }
function parentOf(p) { const i = p.lastIndexOf('/'); return i <= 0 ? '/' : p.slice(0, i); }
function accessSync(p) { p = norm(p); return files.has(p) || dirs.has(p); }
function statSync(p) {
  p = norm(p);
  if (files.has(p)) { const b = files.get(p); return { size: b.length, mode: 0, isFile: () => true, isDirectory: () => false }; }
  if (dirs.has(p)) { return { size: 0, mode: 0, isFile: () => false, isDirectory: () => true }; }
  throw new Error('ENOENT: ' + p);
}
function mkdirSync(p, recursive) {
  p = norm(p);
  if (dirs.has(p)) { if (recursive) return; throw new Error('EEXIST: ' + p); }
  if (recursive) {
    const parts = p.split('/').filter(Boolean);
    let cur = '';
    for (const part of parts) { cur += '/' + part; dirs.add(cur); }
    return;
  }
  if (!dirs.has(parentOf(p))) throw new Error('ENOENT parent: ' + p);
  dirs.add(p);
}
function openSync(p, mode) { return { fd: { __target: norm(p) }, path: norm(p), close() {} }; }
function readTextSync(p) {
  p = norm(p);
  if (!files.has(p)) throw new Error('ENOENT: ' + p);
  return Buffer.from(files.get(p)).toString('utf8');
}
function writeSync(fd, buffer, options) {
  const target = (fd && fd.__target) ? fd.__target : null;
  if (!target) throw new Error('bad fd');
  const bytes = (typeof buffer === 'string') ? Buffer.from(buffer, 'utf8') : new Uint8Array(buffer);
  let off = 0, len = bytes.length;
  if (options && typeof options.offset === 'number') { off = options.offset; }
  if (options && typeof options.length === 'number') { len = options.length; }
  files.set(target, new Uint8Array(bytes.subarray(off, off + len)));
  return len;
}
function closeSync() {}
function unlinkSync(p) { p = norm(p); if (!files.delete(p)) throw new Error('ENOENT: ' + p); }
function rmdirSync(p) { p = norm(p); if (!dirs.delete(p)) throw new Error('ENOENT: ' + p); }
function listFileSync(p) {
  p = norm(p);
  if (!dirs.has(p)) throw new Error('ENOENT: ' + p);
  const out = [];
  const prefix = p === '/' ? '/' : p + '/';
  for (const k of files.keys()) { if (k.startsWith(prefix) && !k.slice(prefix.length).includes('/')) out.push(k.slice(prefix.length)); }
  for (const k of dirs) { if (k.startsWith(prefix) && k !== p && !k.slice(prefix.length).includes('/')) out.push(k.slice(prefix.length)); }
  return out;
}
function renameSync(a, b) {
  a = norm(a); b = norm(b);
  if (files.has(a)) { files.set(b, files.get(a)); files.delete(a); return; }
  if (dirs.has(a)) { dirs.delete(a); dirs.add(b); return; }
  throw new Error('ENOENT: ' + a);
}
function copyFileSync(a, b) { a = norm(a); b = norm(b); if (!files.has(a)) throw new Error('ENOENT: ' + a); files.set(b, files.get(a)); }
const access = async (p) => accessSync(p);
const stat = async (p) => statSync(p);
const mkdir = async (p, r) => mkdirSync(p, r);
const open = async (p, m) => openSync(p, m);
const write = async (fd, buf, opts) => writeSync(fd, buf, opts);
const close = async (f) => closeSync(f);
const unlink = async (p) => unlinkSync(p);
const rename = async (a, b) => renameSync(a, b);
const listFile = async (p) => listFileSync(p);
const OpenMode = { READ_ONLY: 0, WRITE_ONLY: 1, READ_WRITE: 2, CREATE: 64, TRUNC: 512, APPEND: 1024 };
const fs = {
  accessSync, statSync, mkdirSync, openSync, readTextSync, writeSync, closeSync, unlinkSync, rmdirSync, listFileSync, renameSync, copyFileSync,
  access, stat, mkdir, open, write, close, unlink, rename, listFile,
  OpenMode
};
module.exports = fs;
module.exports.default = fs;
module.exports.__reset = function () { files.clear(); dirs.clear(); dirs.add('/'); };
'@

$stubs = @{
  '@kit.AbilityKit' = @'
const calls = [];
global.__errorManagerOnCalls = calls;
module.exports = { errorManager: { on: (type, obs) => { calls.push([type, obs]); return calls.length; } } };
'@
  '@kit.BasicServicesKit' = "module.exports = { default: {}, BusinessError: class extends Error {} };`n"
  '@kit.PerformanceAnalysisKit' = "module.exports = { default: { hilog: { debug(){}, info(){}, warn(){}, error(){} } }, hilog: { debug(){}, info(){}, warn(){}, error(){} } };`n"
  '@ohos.app.ability.common' = "module.exports = { default: {} };`n"
  '@ohos.bundle.bundleManager' = "module.exports = { default: { getBundleInfoForSelfSync: () => ({ versionName: '0.0.0-test' }), BundleFlag: { GET_BUNDLE_INFO_DEFAULT: 0 } }, getBundleInfoForSelfSync: () => ({ versionName: '0.0.0-test' }), BundleFlag: { GET_BUNDLE_INFO_DEFAULT: 0 } };`n"
  '@ohos.data.preferences' = "class P { getSync(k,d){ return d; } putSync(){} deleteSync(){} getAll(){ return Promise.resolve({}); } flush(){ return Promise.resolve(); } }`nmodule.exports = { default: { getPreferences: () => Promise.resolve(new P()) }, getPreferences: () => Promise.resolve(new P()) };`n"
  '@ohos.data.relationalStore' = "module.exports = { default: { getRdbStore: async () => null } };`n"
  '@ohos.file.environment' = "module.exports = { default: { getUserDownloadDir: () => '/data/dl' }, getUserDownloadDir: () => '/data/dl' };`n"
  '@ohos.file.fileuri' = "class FileUri { constructor(p){ this.p = p; } getUri(){ return this.p; } static createFileUri(p){ return new FileUri(p); } }`nconst getUriFromPath = (p) => 'file://' + p;`nmodule.exports = { default: { FileUri, createFileUri: (p) => new FileUri(p), getUriFromPath }, FileUri, createFileUri: (p) => new FileUri(p), getUriFromPath };`n"
  '@ohos.file.fs' = $fsStub
  '@ohos.file.picker' = "module.exports = { default: {}, DocumentViewPicker: class {}, PhotoViewPicker: class {} };`n"
  '@ohos.hilog' = "function noop(){}`nmodule.exports = { error: noop, info: noop, debug: noop, warn: noop, isLoggable: () => false };`nmodule.exports.default = module.exports;`n"
  '@ohos.i18n' = "const sys = { getSystemLanguage: () => 'zh-Hans', getSystemLocale: () => 'zh-CN', getSystemLocaleInstance: () => ({ toString: () => 'zh-CN' }), setAppPreferredLanguage: () => {}, getAppPreferredLanguage: () => 'default' };`nmodule.exports = { default: { System: sys }, System: sys };`n"
  '@ohos.multimedia.image' = "module.exports = { default: { createImageSource: () => ({ createPixelMap: async () => ({}), release: () => {} }) } };`n"
  '@kit.ImageKit' = "const image = { createImageSource: () => ({ createPixelMap: async () => ({}), createPixelMapSync: () => ({}), getImageInfoSync: () => ({ size: { width: 100, height: 100 } }), release: () => {} }), createImagePacker: () => ({ packing: async () => new ArrayBuffer(0), release: () => {} }) };`nmodule.exports = { default: { image }, image };`n"
  '@kit.LocalizationKit' = "const sys = { getSystemLanguage: () => 'zh-Hans', getSystemLocale: () => 'zh-CN', getSystemLocaleInstance: () => ({ toString: () => 'zh-CN' }), setAppPreferredLanguage: () => {}, getAppPreferredLanguage: () => 'default' };`nconst i18n = { System: sys };`nmodule.exports = { default: { i18n }, i18n };`n"
  '@ohos.net.connection' = "const NetBearType = { BEARER_CELLULAR: 0, BEARER_WIFI: 1, BEARER_BLUETOOTH: 2, BEARER_ETHERNET: 3, BEARER_VPN: 4 };`nconst connMod = { NetBearType, getAddressesByName: async () => [], getAddressesByNameSync: () => [], getDefaultHttpProxy: async () => ({ host: '', port: 0, exclusionList: [] }), getDefaultNetSync: () => ({ netId: 0 }), getAllNetsSync: () => [], getNetCapabilitiesSync: () => ({ bearerTypes: [] }), getConnectionPropertiesSync: () => ({ linkAddresses: [] }), createNetConnection: () => ({ on(){}, register(cb){ if (cb) cb(null); }, unregister(cb){ if (cb) cb(null); } }) };`nmodule.exports = { default: connMod, ...connMod };`n"
  '@kit.ArkWeb' = "const ProxySchemeFilter = { MATCH_ALL_SCHEMES: 0, MATCH_HTTP: 1, MATCH_HTTPS: 2 };`nclass ProxyConfig { insertDirectRule(){} insertProxyRule(){} insertBypassRule(){} }`nconst ProxyController = { applyProxyOverride(_cfg, cb){ if (cb) cb(); }, removeProxyOverride(cb){ if (cb) cb(); } };`nconst WebviewController = { initializeWebEngine(){} };`nconst WebCookieManager = { saveCookieSync(){}, clearAllCookiesSync(){}, clearSessionCookieSync(){}, putAcceptCookieEnabled(){}, putAcceptThirdPartyCookieEnabled(){}, fetchCookieSync(){ return ''; }, configCookieSync(){}, saveCookieAsync(cb){ if (cb) cb(null); } };`nconst webview = { ProxySchemeFilter, ProxyConfig, ProxyController, WebviewController, WebCookieManager };`nmodule.exports = { default: { webview }, webview };`n"
  '@ohos.net.http' = "const createHttp = () => ({ on(){}, off(){}, request: () => Promise.resolve({ responseCode: 200, header: {}, resultType: 0, result: '' }), destroy: () => {} });`nmodule.exports = { default: { createHttp }, createHttp };`n"
  '@ohos.net.socket' = "class TCPSocket { constructor(){} bind(){} connect(){ return Promise.resolve(); } send(){ return Promise.resolve(); } close(){} on(){} off(){} }`nmodule.exports = { default: { TCPSocket, TLSSocket: TCPSocket, constructTCPSocketInstance: () => new TCPSocket() }, TCPSocket, TLSSocket: TCPSocket, constructTCPSocketInstance: () => new TCPSocket() };`n"
  '@ohos.resourceManager' = "module.exports = { default: { ResourceManager: class {} } };`n"
  '@ohos.util' = @'
class TextEncoderShim {
  encodeInto(s, dest) {
    const b = Buffer.from(s === undefined ? '' : String(s), 'utf8');
    if (dest) {
      const n = Math.min(b.length, dest.length);
      for (let i = 0; i < n; i++) dest[i] = b[i];
      return { read: String(s || '').length, written: n };
    }
    return new Uint8Array(b.buffer, b.byteOffset, b.byteLength);
  }
  encode(s) { return this.encodeInto(s); }
}
class TextDecoderShim {
  static create() { return new TextDecoderShim(); }
  decodeToString(u8) { return u8 ? Buffer.from(u8 instanceof Uint8Array ? u8 : new Uint8Array(u8)).toString('utf8') : ''; }
  decode(u8) { return this.decodeToString(u8); }
}
class Base64Helper {
  encodeToStringSync(u8) { return Buffer.from(u8).toString('base64'); }
  decodeSync(s) { return new Uint8Array(Buffer.from(s, 'base64')); }
}
module.exports = { default: { TextEncoder: TextEncoderShim, TextDecoder: TextDecoderShim, Base64Helper }, TextEncoder: TextEncoderShim, TextDecoder: TextDecoderShim, Base64Helper };
'@
}

$nm = Join-Path $WorkDir 'node_modules'
$created = 0
foreach ($pkg in $stubs.Keys) {
  $dir = Join-Path $nm $pkg
  $idx = Join-Path $dir 'index.js'
  if ($Force -or -not (Test-Path $idx)) {
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    [IO.File]::WriteAllText($idx, $stubs[$pkg], $utf8NoBom)
    $created++
  }
}

Write-Host "OK: tscheck ready at $WorkDir (stubs written: $created)" -ForegroundColor Green
