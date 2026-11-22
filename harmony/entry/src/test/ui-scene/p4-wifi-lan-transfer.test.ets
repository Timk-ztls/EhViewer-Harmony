/*
 * Stage B Track P4 — Unit Tests for Same-LAN HTTP Transfer (DEVIATIONS.md D-002).
 *
 * Covers:
 *   1. Pure-ArkTS RFC 1321 MD5 (one-shot + multi-chunk streaming across block boundaries)
 *   2. Pure-ArkTS UTF-8 codec (ASCII, CJK, 4-byte emoji surrogate pairs)
 *   3. LAN endpoint / IP:port / QR / JSON payload parsing, IPv4 validation, intToIp, pickWlanIpv4
 *   4. HTTP/1.1 request/response framing, binary payloads, 1-byte split stream accumulation,
 *      400/404/405/413/503 error paths, and path-traversal (`..`, `%2e%2e`, `\`, NUL) rejection
 *   5. End-to-end in-memory LanHttpTransferClient <-> LanHttpTransferRouter over HTTP/1.1 wire:
 *      - /api/info handshake
 *      - Bookmarks transfer & persistence
 *      - Favorites transfer & persistence
 *      - Downloads (labels + download infos) transfer & persistence
 *      - Download directory migration: scan -> manifest -> incremental filterFilesNeeded skip ->
 *        multi-chunk >256KiB file -> nested subdir file -> empty 0-byte file ->
 *        MD5 verification pass -> MD5 mismatch deletes corrupt file -> mid-transfer cancel
 *   6. WiFiServerActivity & WiFiClientActivity state transitions integration
 *
 * Run: pwsh -NoProfile -ExecutionPolicy Bypass -File harmony/entry/src/test/ui-scene/run.ps1 -Filter p4-
 */

import {
  LanEndpoint,
  LanEndpointCodec,
  LanHttpCodec,
  LanHttpFeedResult,
  LanHttpFeedStatus,
  LanHttpRequest,
  LanHttpRequestBuffer,
  LanHttpRequester,
  LanHttpResponse,
  LanHttpRoutes,
  LanHttpTransferClient,
  LanHttpTransferRouter,
  LanMd5Hasher,
  LanPullProgress,
  LanPullSummary,
  LanServerDataProvider,
  LanServerInfo,
  LanTextFormatter,
  LanTransferEvent,
  LanUtf8
} from '../../main/ets/hippo/ehviewer/client/wifi/LanHttpProtocol';
import {
  MigrationFileSystem,
  WiFiDownloadMigrationHelper
} from '../../main/ets/hippo/ehviewer/client/wifi/WiFiDownloadMigrationHelper';
import {
  FileChunkSource,
  NetworkInterfaceLike,
  WiFiServerAction,
  WiFiServerActivity,
  WiFiServerMenu
} from '../../main/ets/hippo/ehviewer/ui/wifi/WiFiServerActivity';
import {
  MigrationPersistSink,
  MigrationWriteSink,
  WiFiClientActivity
} from '../../main/ets/hippo/ehviewer/ui/wifi/WiFiClientActivity';
import { GalleryInfo } from '../../main/ets/hippo/ehviewer/client/data/GalleryInfo';
import { DownloadInfo } from '../../main/ets/hippo/ehviewer/dao/DownloadInfo';
import { DownloadLabel } from '../../main/ets/hippo/ehviewer/dao/DownloadLabel';
import { QuickSearch } from '../../main/ets/hippo/ehviewer/dao/QuickSearch';

let pass: number = 0;
const fails: string[] = [];

function eq(name: string, got: Object | null, want: Object | null): void {
  const g: string = JSON.stringify(got);
  const w: string = JSON.stringify(want);
  if (g === w) {
    pass++;
  } else {
    fails.push(`${name}\n    got  ${g}\n    want ${w}`);
  }
}

function ok(name: string, cond: boolean): void {
  if (cond) {
    pass++;
  } else {
    fails.push(`${name}  (want true)`);
  }
}

// ── In-memory test doubles ──────────────────────────────────────────────────

class MemFs implements MigrationFileSystem, FileChunkSource, MigrationWriteSink {
  readonly dirs: Set<string> = new Set<string>();
  readonly files: Map<string, Uint8Array> = new Map<string, Uint8Array>();
  root: string | null = '/downloads';
  ensureFail: boolean = false;
  deletedPaths: string[] = [];
  corruptMd5ForPath: Map<string, string> = new Map<string, string>();

  constructor(rootPath: string | null = '/downloads') {
    this.root = rootPath;
    if (rootPath !== null) {
      this.mkdirp(rootPath);
    }
  }

  mkdirp(dir: string): void {
    const clean: string = MemFs.norm(dir);
    const parts: string[] = clean.split('/');
    let cur: string = '';
    for (let i = 1; i < parts.length; i++) {
      cur += '/' + parts[i];
      this.dirs.add(cur);
    }
  }

  putFile(path: string, content: Uint8Array): void {
    const clean: string = MemFs.norm(path);
    const slash: number = clean.lastIndexOf('/');
    if (slash > 0) {
      this.mkdirp(clean.substring(0, slash));
    }
    const copy: Uint8Array = new Uint8Array(content.byteLength);
    copy.set(content);
    this.files.set(clean, copy);
  }

  putTextFile(path: string, text: string): void {
    this.putFile(path, LanUtf8.encode(text));
  }

  list(dir: string): string[] {
    const base: string = MemFs.norm(dir);
    if (!this.dirs.has(base)) {
      return [];
    }
    const out: Set<string> = new Set<string>();
    const prefix: string = base === '/' ? '/' : `${base}/`;
    this.dirs.forEach((d: string): void => {
      if (d !== base && d.startsWith(prefix)) {
        const rest: string = d.substring(prefix.length);
        if (rest.indexOf('/') < 0 && rest.length > 0) {
          out.add(rest);
        }
      }
    });
    this.files.forEach((_v: Uint8Array, f: string): void => {
      if (f.startsWith(prefix)) {
        const rest: string = f.substring(prefix.length);
        if (rest.indexOf('/') < 0 && rest.length > 0) {
          out.add(rest);
        }
      }
    });
    const list: string[] = [];
    out.forEach((n: string): void => {
      list.push(n);
    });
    list.sort();
    return list;
  }

  isDirectory(path: string): boolean {
    return this.dirs.has(MemFs.norm(path));
  }

  isFile(path: string): boolean {
    return this.files.has(MemFs.norm(path));
  }

  size(path: string): number {
    const data: Uint8Array | undefined = this.files.get(MemFs.norm(path));
    return data === undefined ? 0 : data.byteLength;
  }

  computeMd5Hex(path: string): string | null {
    const clean: string = MemFs.norm(path);
    const override: string | undefined = this.corruptMd5ForPath.get(clean);
    if (override !== undefined) {
      return override;
    }
    const data: Uint8Array | undefined = this.files.get(clean);
    if (data === undefined) {
      return null;
    }
    return LanMd5Hasher.md5Hex(data);
  }

  resolveFileInGallery(galleryDir: string, relPath: string): string | null {
    if (!LanHttpCodec.isSafeRelPath(relPath)) {
      return null;
    }
    const full: string = MemFs.norm(`${galleryDir}/${relPath}`);
    return this.files.has(full) ? full : null;
  }

  readChunk(path: string, offset: number, length: number): Uint8Array | null {
    const data: Uint8Array | undefined = this.files.get(MemFs.norm(path));
    if (data === undefined || offset >= data.byteLength || length <= 0) {
      return null;
    }
    const end: number = Math.min(data.byteLength, offset + length);
    const slice: Uint8Array = new Uint8Array(end - offset);
    slice.set(data.subarray(offset, end));
    return slice;
  }

  hasDownloadRoot(): boolean {
    return this.root !== null;
  }

  ensureGalleryDir(_gid: number, dirname: string): string | null {
    if (this.root === null || this.ensureFail || !LanHttpCodec.isSafeDirName(dirname)) {
      return null;
    }
    const full: string = MemFs.norm(`${this.root}/${dirname}`);
    this.mkdirp(full);
    return full;
  }

  deleteFile(path: string): boolean {
    const clean: string = MemFs.norm(path);
    this.deletedPaths.push(clean);
    this.files.delete(clean);
    return true;
  }

  writeChunk(galleryDir: string, name: string, data: Uint8Array, offset: number): boolean {
    if (!LanHttpCodec.isSafeRelPath(name)) {
      return false;
    }
    const full: string = MemFs.norm(`${galleryDir}/${name}`);
    const slash: number = full.lastIndexOf('/');
    if (slash > 0) {
      this.mkdirp(full.substring(0, slash));
    }
    const existing: Uint8Array | undefined = this.files.get(full);
    const base: Uint8Array = existing === undefined || offset === 0 ? new Uint8Array(0) : existing;
    const neededLen: number = Math.max(base.byteLength, offset + data.byteLength);
    const next: Uint8Array = new Uint8Array(neededLen);
    if (base.byteLength > 0) {
      next.set(base, 0);
    }
    if (data.byteLength > 0) {
      next.set(data, offset);
    }
    this.files.set(full, next);
    return true;
  }

  resolveFile(galleryDir: string, relPath: string): string | null {
    return this.resolveFileInGallery(galleryDir, relPath);
  }

  private static norm(p: string): string {
    let s: string = p.replace(/\/+/g, '/');
    if (s.length > 1 && s.endsWith('/')) {
      s = s.substring(0, s.length - 1);
    }
    return s;
  }
}

class MemServerProvider implements LanServerDataProvider {
  quickSearches: QuickSearch[] = [];
  favorites: GalleryInfo[] = [];
  labels: DownloadLabel[] = [];
  downloads: DownloadInfo[] = [];
  downloadRoot: string | null = '/srv-downloads';

  getAppVersion(): string {
    return '2.0.2.6-test';
  }

  getDeviceName(): string {
    return 'TestHarmonyPhone';
  }

  async getQuickSearches(): Promise<QuickSearch[]> {
    return this.quickSearches.slice();
  }

  async getLocalFavorites(): Promise<GalleryInfo[]> {
    return this.favorites.slice();
  }

  async getDownloadLabels(): Promise<DownloadLabel[]> {
    return this.labels.slice();
  }

  async getDownloadInfos(): Promise<DownloadInfo[]> {
    return this.downloads.slice();
  }

  getDownloadRoot(): string | null {
    return this.downloadRoot;
  }
}

class MemPersistSink implements MigrationPersistSink {
  quickSearches: QuickSearch[] = [];
  labels: string[] = [];
  downloads: DownloadInfo[] = [];
  favorites: GalleryInfo[] = [];
  callOrder: string[] = [];

  takeOverQuickSearchList(jsonTexts: string[]): void {
    this.callOrder.push(`quick:${jsonTexts.length}`);
    for (let i = 0; i < jsonTexts.length; i++) {
      this.quickSearches.push(QuickSearch.quickSearchFromJson(jsonTexts[i]));
    }
  }

  addDownloadLabel(label: string): void {
    this.callOrder.push(`label:${label}`);
    this.labels.push(label);
  }

  addDownloadInfo(jsonText: string): void {
    const info: DownloadInfo = DownloadInfo.downloadInfoFromJson(jsonText);
    this.callOrder.push(`dl:${info.gid}`);
    this.downloads.push(info);
  }

  putLocalFavorite(jsonText: string): void {
    const gi: GalleryInfo = GalleryInfo.fromJson(jsonText);
    this.callOrder.push(`fav:${gi.gid}`);
    this.favorites.push(gi);
  }
}

/**
 * In-memory HTTP/1.1 wire loopback requester:
 * serializes request -> feeds into LanHttpRequestBuffer -> dispatches via LanHttpTransferRouter ->
 * serializes response -> parses HTTP/1.1 wire response back!
 */
class WireLoopbackRequester implements LanHttpRequester {
  private readonly router: LanHttpTransferRouter;
  requestedUrls: string[] = [];
  aborted: boolean = false;
  corruptNextFileBody: boolean = false;
  onBeforeRequest: ((url: string, count: number) => void) | null = null;

  constructor(router: LanHttpTransferRouter) {
    this.router = router;
  }

  async request(method: string, url: string, _timeoutMs: number): Promise<LanHttpResponse> {
    this.requestedUrls.push(url);
    if (this.onBeforeRequest !== null) {
      this.onBeforeRequest(url, this.requestedUrls.length);
    }
    if (this.aborted) {
      throw new Error('Aborted');
    }
    const schemeEnd: number = url.indexOf('://');
    const afterScheme: string = schemeEnd >= 0 ? url.substring(schemeEnd + 3) : url;
    const slashIdx: number = afterScheme.indexOf('/');
    const host: string = slashIdx >= 0 ? afterScheme.substring(0, slashIdx) : afterScheme;
    const target: string = slashIdx >= 0 ? afterScheme.substring(slashIdx) : '/';

    const reqWire: ArrayBuffer = LanHttpCodec.serializeRequest(method, target, host);
    const buf: LanHttpRequestBuffer = new LanHttpRequestBuffer();
    const feedRes: LanHttpFeedResult = buf.feed(new Uint8Array(reqWire));
    if (feedRes.status !== LanHttpFeedStatus.COMPLETE || feedRes.request === null) {
      return LanHttpResponse.error(400, 'Loopback request framing error');
    }
    const srvResp: LanHttpResponse = await this.router.handleRequest(feedRes.request);
    const respWire: ArrayBuffer = LanHttpCodec.serializeResponse(srvResp);
    const parsedResp: LanHttpResponse = LanHttpCodec.parseResponse(respWire);

    if (this.corruptNextFileBody && target.indexOf(LanHttpRoutes.DIR_FILE) === 0 && parsedResp.body.byteLength > 0) {
      this.corruptNextFileBody = false;
      const tampered: Uint8Array = new Uint8Array(parsedResp.body);
      tampered[0] = (tampered[0] ^ 0xFF) & 0xFF;
      return new LanHttpResponse(
        parsedResp.statusCode,
        parsedResp.reasonPhrase,
        parsedResp.headers,
        LanUtf8.toArrayBuffer(tampered)
      );
    }
    return parsedResp;
  }

  abortAll(): void {
    this.aborted = true;
  }
}

// ── 1. MD5 RFC 1321 & UTF-8 tests ───────────────────────────────────────────

function testMd5AndUtf8(): void {
  // RFC 1321 Appendix A.5 official test suite
  eq('MD5 ""', LanMd5Hasher.md5HexString(''), 'd41d8cd98f00b204e9800998ecf8427e');
  eq('MD5 "a"', LanMd5Hasher.md5HexString('a'), '0cc175b9c0f1b6a831c399e269772661');
  eq('MD5 "abc"', LanMd5Hasher.md5HexString('abc'), '900150983cd24fb0d6963f7d28e17f72');
  eq('MD5 "message digest"', LanMd5Hasher.md5HexString('message digest'), 'f96b697d7cb7938d525a2f31aaf161d0');
  eq('MD5 a-z', LanMd5Hasher.md5HexString('abcdefghijklmnopqrstuvwxyz'), 'c3fcd3d76192e4007dfb496cca67e13b');
  eq(
    'MD5 A-Za-z0-9',
    LanMd5Hasher.md5HexString('ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789'),
    'd174ab98d277d9f5a5611c2c9f419d9f'
  );
  eq(
    'MD5 80 digits',
    LanMd5Hasher.md5HexString('12345678901234567890123456789012345678901234567890123456789012345678901234567890'),
    '57edf4a22be3c955ac49da2e2107b67a'
  );

  // Streaming MD5 across arbitrary chunk boundaries matches one-shot
  const sample: Uint8Array = new Uint8Array(1024);
  for (let i = 0; i < sample.byteLength; i++) {
    sample[i] = (i * 37 + 13) & 0xFF;
  }
  const oneShot: string = LanMd5Hasher.md5Hex(sample);
  const streamHasher: LanMd5Hasher = new LanMd5Hasher();
  streamHasher.update(sample.subarray(0, 7));
  streamHasher.update(sample.subarray(7, 64));
  streamHasher.update(sample.subarray(64, 193));
  streamHasher.update(sample.subarray(193, 555));
  streamHasher.update(sample.subarray(555, 1024));
  eq('Streaming MD5 matches one-shot', streamHasher.digestHex(), oneShot);

  // UTF-8 roundtrip: ASCII + Chinese + Japanese + emoji (4-byte surrogate pair)
  const text: string = 'EhViewer 局域网传书 テスト 🚀📚';
  const encoded: Uint8Array = LanUtf8.encode(text);
  eq('UTF-8 roundtrip with CJK & emoji', LanUtf8.decode(encoded), text);

  // LanTextFormatter handles %1s, %2s (wifi_server_opened), %1$s, %2$d, %s, %d
  eq(
    'Format %1s/%2s',
    LanTextFormatter.format('SSID: %1s \n%2s', ['HomeWiFi', 'http://192.168.1.5:54321']),
    'SSID: HomeWiFi \nhttp://192.168.1.5:54321'
  );
  eq(
    'Format %1$s/%2$d/%3$d/%4$d/%5$d',
    LanTextFormatter.format('%1$s (%2$d/%3$d): skip %4$d, transfer %5$d', ['100-abc', 1, 3, 2, 5]),
    '100-abc (1/3): skip 2, transfer 5'
  );
  eq('Format %s', LanTextFormatter.format('Start Migrate%s', ['(2)']), 'Start Migrate(2)');
}

// ── 2. Endpoint / QR / IPv4 / intToIp / pickWlanIpv4 tests ──────────────────

function testEndpointsAndNetworkHelpers(): void {
  eq('Valid IPv4 192.168.1.5', LanEndpointCodec.isValidIpv4('192.168.1.5'), true);
  eq('Valid IPv4 10.0.0.1', LanEndpointCodec.isValidIpv4('10.0.0.1'), true);
  eq('Reject octet > 255', LanEndpointCodec.isValidIpv4('192.168.1.256'), false);
  eq('Reject leading zero octet', LanEndpointCodec.isValidIpv4('192.168.01.5'), false);
  eq('Reject 3-octet IP', LanEndpointCodec.isValidIpv4('192.168.1'), false);

  eq('Private LAN 192.168.x', LanEndpointCodec.isPrivateLanIpv4('192.168.31.12'), true);
  eq('Private LAN 10.x', LanEndpointCodec.isPrivateLanIpv4('10.12.34.56'), true);
  eq('Private LAN 172.16.x', LanEndpointCodec.isPrivateLanIpv4('172.20.10.2'), true);
  eq('Non-private 8.8.8.8', LanEndpointCodec.isPrivateLanIpv4('8.8.8.8'), false);

  // intToIp (little-endian compatibility + big-endian OpenHarmony wifiManager decode)
  eq('intToIp little-endian', LanEndpointCodec.intToIpLittleEndian(0x0501A8C0), '192.168.1.5');
  eq('intToIp big-endian', LanEndpointCodec.intToIpBigEndian(0xC0A80105), '192.168.1.5');
  eq('decodeWifiIpInt OpenHarmony big-endian', LanEndpointCodec.decodeWifiIpInt(0xC0A80105), '192.168.1.5');
  eq('decodeWifiIpInt Android little-endian', LanEndpointCodec.decodeWifiIpInt(0x0501A8C0), '192.168.1.5');
  eq('decodeWifiIpInt zero -> null', LanEndpointCodec.decodeWifiIpInt(0), null);

  // pickWlanIpv4 integration
  eq(
    'pickWlanIpv4 selects wlan0 IPv4',
    WiFiServerActivity.pickWlanIpv4([
      new NetworkInterfaceLike('lo', ['127.0.0.1'], [true]),
      new NetworkInterfaceLike('wlan0', ['fe80::1', '192.168.50.8'], [false, true])
    ]),
    '192.168.50.8'
  );

  // QR / URL / IP:port / IP normalization
  eq('QR payload build', LanEndpointCodec.buildQrPayload('192.168.1.8', 54321), 'http://192.168.1.8:54321');

  const ep1: LanEndpoint | null = LanEndpointCodec.parseEndpoint('192.168.1.8');
  eq('Bare IP uses default port 54321', ep1 === null ? null : ep1.baseUrl, 'http://192.168.1.8:54321');

  const ep2: LanEndpoint | null = LanEndpointCodec.parseEndpoint('192.168.1.8:8080');
  eq('IP:port', ep2 === null ? null : ep2.baseUrl, 'http://192.168.1.8:8080');

  const ep3: LanEndpoint | null = LanEndpointCodec.parseEndpoint('  http://192.168.1.8:54321/api/info?x=1  ');
  eq('Full URL strips path/query', ep3 === null ? null : ep3.baseUrl, 'http://192.168.1.8:54321');

  const ep4: LanEndpoint | null = LanEndpointCodec.parseEndpoint('{"url":"http://10.0.0.9:54321"}');
  eq('JSON QR url payload', ep4 === null ? null : ep4.baseUrl, 'http://10.0.0.9:54321');

  const ep5: LanEndpoint | null = LanEndpointCodec.parseEndpoint('{"ip":"10.0.0.10","port":55555}');
  eq('JSON QR ip/port payload', ep5 === null ? null : ep5.baseUrl, 'http://10.0.0.10:55555');

  // Rejection cases
  eq('Reject empty', LanEndpointCodec.parseEndpoint('   '), null);
  eq('Reject 0.0.0.0', LanEndpointCodec.parseEndpoint('0.0.0.0:54321'), null);
  eq('Reject port 0', LanEndpointCodec.parseEndpoint('192.168.1.5:0'), null);
  eq('Reject port > 65535', LanEndpointCodec.parseEndpoint('192.168.1.5:70000'), null);
  eq('Reject non-http scheme', LanEndpointCodec.parseEndpoint('https://192.168.1.5:54321'), null);
  eq('Reject bad numeric IP', LanEndpointCodec.parseEndpoint('999.168.1.5:54321'), null);
  eq('Reject userinfo injection', LanEndpointCodec.parseEndpoint('http://user@192.168.1.5:54321'), null);
}

// ── 3. HTTP/1.1 framing, binary bodies & path-traversal security tests ──────

async function testHttpFramingAndSecurity(): Promise<void> {
  // 1-byte incremental TCP chunk split (header + binary body)
  const payload: Uint8Array = new Uint8Array([0x00, 0xFF, 0x10, 0x20, 0x7F, 0x80]);
  const wire: ArrayBuffer = LanHttpCodec.serializeRequest(
    'POST',
    '/api/test?a=1&name=%E4%B8%AD%E6%96%87+dir',
    '192.168.1.5:54321',
    LanUtf8.toArrayBuffer(payload)
  );
  const wireBytes: Uint8Array = new Uint8Array(wire);
  const buf: LanHttpRequestBuffer = new LanHttpRequestBuffer();
  let lastResult: LanHttpFeedResult = LanHttpFeedResult.incomplete();
  for (let i = 0; i < wireBytes.byteLength; i++) {
    lastResult = buf.feed(wireBytes.subarray(i, i + 1));
    if (i < wireBytes.byteLength - 1) {
      ok(`Partial feed byte ${i} stays INCOMPLETE`, lastResult.status === LanHttpFeedStatus.INCOMPLETE);
    }
  }
  eq('Final byte completes request', lastResult.status, LanHttpFeedStatus.COMPLETE);
  const parsedReq: LanHttpRequest = lastResult.request as LanHttpRequest;
  eq('Method POST', parsedReq.method, 'POST');
  eq('Path /api/test', parsedReq.path, '/api/test');
  eq('Query a=1', parsedReq.getQuery('a'), '1');
  eq('Query UTF-8 + plus decode', parsedReq.getQuery('name'), '中文 dir');
  eq('Binary body byte length', parsedReq.body.byteLength, 6);
  eq('Binary body intact', Array.from(new Uint8Array(parsedReq.body)), [0x00, 0xFF, 0x10, 0x20, 0x7F, 0x80]);

  // Malformed request -> 400 error
  const badBuf: LanHttpRequestBuffer = new LanHttpRequestBuffer();
  const badRes: LanHttpFeedResult = badBuf.feed(LanUtf8.encode('NOT_A_VALID_REQUEST\r\n\r\n'));
  eq('Malformed request -> ERROR', badRes.status, LanHttpFeedStatus.ERROR);
  eq('Malformed request -> 400', badRes.errorCode, 400);

  // Oversized Content-Length -> 413 error
  const bigBuf: LanHttpRequestBuffer = new LanHttpRequestBuffer();
  const bigRes: LanHttpFeedResult = bigBuf.feed(
    LanUtf8.encode('POST /api/info HTTP/1.1\r\nHost: x\r\nContent-Length: 99999999\r\n\r\n')
  );
  eq('Oversized Content-Length -> 413', bigRes.errorCode, 413);

  // Path traversal defense unit checks
  eq('Safe rel path 001.jpg', LanHttpCodec.isSafeRelPath('001.jpg'), true);
  eq('Safe nested rel path sub/001.jpg', LanHttpCodec.isSafeRelPath('sub/001.jpg'), true);
  eq('Reject .. traversal', LanHttpCodec.isSafeRelPath('../secret.db'), false);
  eq('Reject nested .. traversal', LanHttpCodec.isSafeRelPath('a/../../etc/passwd'), false);
  eq('Reject percent-encoded ..', LanHttpCodec.isSafeRelPath('%2e%2e/secret'), false);
  eq('Reject leading slash', LanHttpCodec.isSafeRelPath('/etc/passwd'), false);
  eq('Reject backslash', LanHttpCodec.isSafeRelPath('a\\b.jpg'), false);
  eq('Reject NUL byte', LanHttpCodec.isSafeRelPath('a.jpg\0.png'), false);

  eq('Safe dirname 123-abc', LanHttpCodec.isSafeDirName('123-abc'), true);
  eq('Reject dirname ..', LanHttpCodec.isSafeDirName('..'), false);
  eq('Reject dirname with slash', LanHttpCodec.isSafeDirName('123-a/b'), false);
  eq('Reject dirname with encoded ..', LanHttpCodec.isSafeDirName('%2e%2e'), false);

  // Router status codes: 405, 404, 503, 400 path traversal
  const srvFs: MemFs = new MemFs('/srv');
  const provider: MemServerProvider = new MemServerProvider();
  provider.downloadRoot = '/srv';
  srvFs.putTextFile('/srv/100-gallery/001.jpg', 'hello');
  const router: LanHttpTransferRouter = new LanHttpTransferRouter(provider, srvFs, srvFs);

  const postResp: LanHttpResponse = await router.handleRequest(
    new LanHttpRequest('POST', '/api/info', '/api/info', new Map(), new Map(), new ArrayBuffer(0))
  );
  eq('POST returns 405', postResp.statusCode, 405);

  const notFoundResp: LanHttpResponse = await router.handleRequest(
    new LanHttpRequest('GET', '/api/nope', '/api/nope', new Map(), new Map(), new ArrayBuffer(0))
  );
  eq('Unknown route returns 404', notFoundResp.statusCode, 404);

  const travQuery: Map<string, string> = new Map<string, string>();
  travQuery.set('gid', '100');
  travQuery.set('dirname', '100-gallery');
  travQuery.set('name', '../secret.txt');
  const travResp: LanHttpResponse = await router.handleRequest(
    new LanHttpRequest('GET', '/api/dir/file', '/api/dir/file', travQuery, new Map(), new ArrayBuffer(0))
  );
  eq('Path traversal file request returns 400', travResp.statusCode, 400);

  const dirTravQuery: Map<string, string> = new Map<string, string>();
  dirTravQuery.set('gid', '100');
  dirTravQuery.set('dirname', '../etc');
  const dirTravResp: LanHttpResponse = await router.handleRequest(
    new LanHttpRequest('GET', '/api/dir/manifest', '/api/dir/manifest', dirTravQuery, new Map(), new ArrayBuffer(0))
  );
  eq('Path traversal manifest request returns 400', dirTravResp.statusCode, 400);

  // Serving paused -> /api/ping still 200, /api/info returns 503
  router.setServing(false);
  const pingPaused: LanHttpResponse = await router.handleRequest(
    new LanHttpRequest('GET', '/api/ping', '/api/ping', new Map(), new Map(), new ArrayBuffer(0))
  );
  eq('Paused /api/ping returns 200', pingPaused.statusCode, 200);
  const infoPaused: LanHttpResponse = await router.handleRequest(
    new LanHttpRequest('GET', '/api/info', '/api/info', new Map(), new Map(), new ArrayBuffer(0))
  );
  eq('Paused /api/info returns 503', infoPaused.statusCode, 503);
}

// ── 4. End-to-end Client <-> Router migration tests ─────────────────────────

async function testEndToEndLanMigration(): Promise<void> {
  const srvFs: MemFs = new MemFs('/srv-dl');
  const provider: MemServerProvider = new MemServerProvider();
  provider.downloadRoot = '/srv-dl';

  // Populate bookmarks
  const qs1: QuickSearch = new QuickSearch(1, 'Manga Favs', 0, 2, 'language:chinese', 1, 4, 1, 5, 1700000001);
  const qs2: QuickSearch = new QuickSearch(2, 'Artist Tag', 1, 4, 'artist:test', 0, 0, 0, 0, 1700000002);
  provider.quickSearches = [qs1, qs2];

  // Populate favorites
  const fav1: GalleryInfo = new GalleryInfo();
  fav1.gid = 10001;
  fav1.token = 'tok10001';
  fav1.title = 'Local Fav One';
  fav1.posted = '2026-01-01 12:00';
  fav1.rating = 4.5;
  const fav2: GalleryInfo = new GalleryInfo();
  fav2.gid = 10002;
  fav2.token = 'tok10002';
  fav2.title = '本地收藏二';
  fav2.posted = '2026-02-02 12:00';
  provider.favorites = [fav1, fav2];

  // Populate download labels + download infos
  const lbl1: DownloadLabel = new DownloadLabel(1, 'Completed', 1000);
  const lbl2: DownloadLabel = new DownloadLabel(2, 'Reading', 2000);
  provider.labels = [lbl1, lbl2];

  const dl1: DownloadInfo = new DownloadInfo(20001);
  dl1.token = 'dtok1';
  dl1.title = 'Downloaded Gallery 1';
  dl1.label = 'Completed';
  dl1.state = DownloadInfo.STATE_FINISH;
  dl1.time = 3000;
  const dl2: DownloadInfo = new DownloadInfo(20002);
  dl2.token = 'dtok2';
  dl2.title = 'Downloaded Gallery 2';
  dl2.label = 'Reading';
  dl2.state = DownloadInfo.STATE_NONE;
  dl2.time = 4000;
  provider.downloads = [dl1, dl2];

  // Populate gallery download directories on server:
  //   - 20001-Alpha:
  //     - same.jpg (already exists on client with identical MD5 -> MUST be skipped!)
  //     - big.bin (300 KiB > 256 KiB FILE_CHUNK_SIZE -> tests multi-chunk range HTTP transfer!)
  //     - empty.dat (0 bytes -> tests empty file creation + MD5 d41d8cd98f00b204e9800998ecf8427e!)
  //     - sub/nested.jpg (tests nested subdirectory creation + transfer!)
  //   - 20002-Beta:
  //     - stale.jpg (exists on client with OLD content -> MUST be replaced cleanly!)
  //   - not-a-gallery (invalid dirname without gid -> MUST be ignored by scanGalleryDirs!)
  const sameContent: Uint8Array = LanUtf8.encode('IDENTICAL_ALREADY_ON_CLIENT');
  const bigSize: number = WiFiDownloadMigrationHelper.FILE_CHUNK_SIZE + 44 * 1024; // 300 KiB
  const bigContent: Uint8Array = new Uint8Array(bigSize);
  for (let i = 0; i < bigSize; i++) {
    bigContent[i] = (i * 17 + 5) & 0xFF;
  }
  const emptyContent: Uint8Array = new Uint8Array(0);
  const nestedContent: Uint8Array = LanUtf8.encode('NESTED_SUBDIR_IMAGE_BYTES');
  const freshBetaContent: Uint8Array = LanUtf8.encode('NEW_CONTENT_REPLACES_STALE');

  srvFs.putFile('/srv-dl/20001-Alpha/same.jpg', sameContent);
  srvFs.putFile('/srv-dl/20001-Alpha/big.bin', bigContent);
  srvFs.putFile('/srv-dl/20001-Alpha/empty.dat', emptyContent);
  srvFs.putFile('/srv-dl/20001-Alpha/sub/nested.jpg', nestedContent);
  srvFs.putFile('/srv-dl/20002-Beta/stale.jpg', freshBetaContent);
  srvFs.putTextFile('/srv-dl/not-a-gallery/ignore.txt', 'ignored');

  // Client storage pre-seeded with matching same.jpg and mismatched stale.jpg
  const cliFs: MemFs = new MemFs('/cli-dl');
  cliFs.putFile('/cli-dl/20001-Alpha/same.jpg', sameContent);
  cliFs.putTextFile('/cli-dl/20002-Beta/stale.jpg', 'OLD_STALE_CONTENT_LONGER_THAN_NEW_CONTENT_1234567890');

  const events: LanTransferEvent[] = [];
  const router: LanHttpTransferRouter = new LanHttpTransferRouter(
    provider,
    srvFs,
    srvFs,
    (ev: LanTransferEvent): void => {
      events.push(ev);
    }
  );
  const requester: WireLoopbackRequester = new WireLoopbackRequester(router);
  const persistSink: MemPersistSink = new MemPersistSink();
  let flushCount: number = 0;
  const client: LanHttpTransferClient = new LanHttpTransferClient(
    requester,
    persistSink,
    cliFs,
    cliFs,
    async (): Promise<void> => {
      flushCount++;
    }
  );

  // Step 1: /api/info handshake
  const info: LanServerInfo = await client.connectAndInspect('192.168.1.99:54321');
  eq('Info protocol', info.protocol, LanEndpointCodec.PROTOCOL_ID);
  eq('Info mode D-002', info.mode, LanEndpointCodec.MODE_D002);
  eq('Info bookmarkCount', info.bookmarkCount, 2);
  eq('Info favoriteCount', info.favoriteCount, 2);
  eq('Info downloadLabelCount', info.downloadLabelCount, 2);
  eq('Info downloadCount', info.downloadCount, 2);
  eq('Info downloadDirCount (ignores non-gid dir)', info.downloadDirCount, 2);
  eq('Info hasDownloadRoot', info.hasDownloadRoot, true);

  // Step 2: Pull bookmarks
  const bmSum: LanPullSummary = await client.pullBookmarks();
  eq('Bookmarks pull ok', bmSum.ok, true);
  eq('Bookmarks imported count', bmSum.itemsImported, 2);
  eq('Bookmarks persisted names', [persistSink.quickSearches[0].name, persistSink.quickSearches[1].name],
    ['Manga Favs', 'Artist Tag']);
  eq('Bookmarks keyword preserved', persistSink.quickSearches[0].keyword, 'language:chinese');

  // Step 3: Pull favorites
  const favSum: LanPullSummary = await client.pullFavorites();
  eq('Favorites pull ok', favSum.ok, true);
  eq('Favorites imported count', favSum.itemsImported, 2);
  eq('Favorites gids persisted', [persistSink.favorites[0].gid, persistSink.favorites[1].gid], [10001, 10002]);
  eq('Favorites UTF-8 title preserved', persistSink.favorites[1].title, '本地收藏二');

  // Step 4: Pull downloads (labels must persist BEFORE download infos)
  persistSink.callOrder = [];
  const dlSum: LanPullSummary = await client.pullDownloads();
  eq('Downloads pull ok', dlSum.ok, true);
  eq('Downloads labels count', dlSum.labelsImported, 2);
  eq('Downloads infos count', dlSum.itemsImported, 2);
  eq('Labels persisted before infos', persistSink.callOrder, [
    'label:Completed',
    'label:Reading',
    'dl:20001',
    'dl:20002'
  ]);
  eq('Download info label preserved', persistSink.downloads[0].label, 'Completed');

  // Step 5: Pull download directories with incremental diff, multi-chunk, empty file, nested file
  requester.requestedUrls = [];
  const progressEvents: LanPullProgress[] = [];
  const dirSum: LanPullSummary = await client.pullDownloadDirs((p: LanPullProgress): void => {
    progressEvents.push(p);
  });
  eq('Dir migration ok', dirSum.ok, true);
  eq('Dirs processed', dirSum.dirsProcessed, 2);
  eq('Incremental skip count (same.jpg skipped)', dirSum.filesSkipped, 1);
  eq('Files transferred (big, empty, nested, stale)', dirSum.filesTransferred, 4);
  eq('Files failed = 0', dirSum.filesFailed, 0);

  // Confirm same.jpg was NEVER fetched over HTTP!
  const fetchedSame: boolean = requester.requestedUrls.some((u: string): boolean => u.indexOf('same.jpg') >= 0);
  eq('Already-matching same.jpg was skipped (no HTTP GET)', fetchedSame, false);

  // Confirm big.bin fetched in 2 HTTP chunk requests (256KiB + 44KiB) and byte-identical + MD5 verified
  const bigChunksFetched: number = requester.requestedUrls.filter((u: string): boolean => u.indexOf('big.bin') >= 0).length;
  eq('300KiB big.bin transferred in 2 chunks', bigChunksFetched, 2);
  eq('big.bin size matches on client', cliFs.size('/cli-dl/20001-Alpha/big.bin'), bigSize);
  eq(
    'big.bin MD5 matches server',
    cliFs.computeMd5Hex('/cli-dl/20001-Alpha/big.bin'),
    LanMd5Hasher.md5Hex(bigContent)
  );

  // Confirm 0-byte empty.dat exists on client with empty MD5
  eq('empty.dat exists on client', cliFs.isFile('/cli-dl/20001-Alpha/empty.dat'), true);
  eq('empty.dat size is 0', cliFs.size('/cli-dl/20001-Alpha/empty.dat'), 0);
  eq('empty.dat MD5 matches empty', cliFs.computeMd5Hex('/cli-dl/20001-Alpha/empty.dat'),
    'd41d8cd98f00b204e9800998ecf8427e');

  // Confirm nested subdirectory file exists & matches
  eq(
    'sub/nested.jpg content matches',
    LanUtf8.decode(cliFs.files.get('/cli-dl/20001-Alpha/sub/nested.jpg') as Uint8Array),
    'NESTED_SUBDIR_IMAGE_BYTES'
  );

  // Confirm stale.jpg was deleted & replaced cleanly (not appended to old longer file!)
  eq(
    'stale.jpg replaced without trailing old bytes',
    LanUtf8.decode(cliFs.files.get('/cli-dl/20002-Beta/stale.jpg') as Uint8Array),
    'NEW_CONTENT_REPLACES_STALE'
  );

  // Re-running pullDownloadDirs now skips ALL 5 files (0 transferred, 5 skipped!)
  requester.requestedUrls = [];
  const secondRun: LanPullSummary = await client.pullDownloadDirs();
  eq('Second run ok', secondRun.ok, true);
  eq('Second run skips all 5 files', secondRun.filesSkipped, 5);
  eq('Second run transfers 0 files', secondRun.filesTransferred, 0);
  ok('Server transfer events emitted', events.length >= 10);
  ok('Persist flusher invoked', flushCount >= 4);
  ok('Progress events emitted', progressEvents.length >= 4);
}

// ── 5. MD5 mismatch deletion, missing download root & mid-transfer cancel ───

async function testMd5MismatchAndCancel(): Promise<void> {
  const srvFs: MemFs = new MemFs('/srv-err');
  const provider: MemServerProvider = new MemServerProvider();
  provider.downloadRoot = '/srv-err';
  srvFs.putTextFile('/srv-err/30001-Gamma/pic1.jpg', 'GENUINE_PAYLOAD_1');
  srvFs.putTextFile('/srv-err/30001-Gamma/pic2.jpg', 'GENUINE_PAYLOAD_2');
  srvFs.putTextFile('/srv-err/30001-Gamma/pic3.jpg', 'GENUINE_PAYLOAD_3');

  const router: LanHttpTransferRouter = new LanHttpTransferRouter(provider, srvFs, srvFs);

  // 5a. Corrupt payload in transit -> MD5 mismatch -> corrupt file MUST be deleted!
  const cliFs1: MemFs = new MemFs('/cli-err1');
  const req1: WireLoopbackRequester = new WireLoopbackRequester(router);
  req1.corruptNextFileBody = true;
  const cli1: LanHttpTransferClient = new LanHttpTransferClient(req1, new MemPersistSink(), cliFs1, cliFs1);
  await cli1.connectAndInspect('192.168.1.50');
  const badSum: LanPullSummary = await cli1.pullDownloadDirs();
  eq('Corrupt file marks ok=false', badSum.ok, false);
  eq('Corrupt file increments filesFailed=1', badSum.filesFailed, 1);
  eq('Remaining 2 valid files succeed', badSum.filesTransferred, 2);
  eq('Corrupt pic1.jpg deleted from client', cliFs1.isFile('/cli-err1/30001-Gamma/pic1.jpg'), false);
  eq('Valid pic2.jpg kept on client', cliFs1.isFile('/cli-err1/30001-Gamma/pic2.jpg'), true);

  // 5b. No download root configured on client -> errorResKey = wifi_download_dir_no_location
  const noRootFs: MemFs = new MemFs(null);
  const req2: WireLoopbackRequester = new WireLoopbackRequester(router);
  const cli2: LanHttpTransferClient = new LanHttpTransferClient(req2, new MemPersistSink(), noRootFs, noRootFs);
  await cli2.connectAndInspect('192.168.1.50');
  const noRootSum: LanPullSummary = await cli2.pullDownloadDirs();
  eq('No download root -> ok=false', noRootSum.ok, false);
  eq('No download root -> resKey', noRootSum.errorResKey, 'wifi_download_dir_no_location');

  // 5c. Mid-transfer cancel aborts cleanly without transferring remaining files
  const cliFs3: MemFs = new MemFs('/cli-cancel');
  const req3: WireLoopbackRequester = new WireLoopbackRequester(router);
  const cli3: LanHttpTransferClient = new LanHttpTransferClient(req3, new MemPersistSink(), cliFs3, cliFs3);
  await cli3.connectAndInspect('192.168.1.50');
  req3.requestedUrls = [];
  req3.onBeforeRequest = (url: string, _count: number): void => {
    if (url.indexOf('pic2.jpg') >= 0) {
      cli3.cancel();
    }
  };
  const cancelSum: LanPullSummary = await cli3.pullDownloadDirs();
  eq('Mid-transfer cancel -> cancelled=true', cancelSum.cancelled, true);
  eq('Mid-transfer cancel -> ok=false', cancelSum.ok, false);
  eq('pic1.jpg completed before cancel', cliFs3.isFile('/cli-cancel/30001-Gamma/pic1.jpg'), true);
  eq('pic3.jpg never downloaded after cancel', cliFs3.isFile('/cli-cancel/30001-Gamma/pic3.jpg'), false);
}

// ── 6. WiFiServerActivity & WiFiClientActivity state transition integration ─

function testActivityStateIntegration(): void {
  const srv: WiFiServerActivity = new WiFiServerActivity();
  srv.onItemSelected(WiFiServerMenu.DOWNLOAD_DIR);
  eq('Server action BUILD_DOWNLOAD_DIR', srv.onStatusChange(), WiFiServerAction.BUILD_DOWNLOAD_DIR);
  eq('Server sending=true', srv.isSending(), true);
  eq('Server status button wifi_send_stop', srv.statusButton().resKey, 'wifi_send_stop');
  eq('Server stop action', srv.onStatusChange(), WiFiServerAction.STOP);
  eq('Server sending=false after stop', srv.isSending(), false);
  eq('Server status button wifi_send_start', srv.statusButton().resKey, 'wifi_send_start');
  srv.destroy();

  const cli: WiFiClientActivity = new WiFiClientActivity();
  eq('Client initial completedFiles=0', cli.completedFiles(), 0);
  cli.destroy();
}

// ── Main entry ──────────────────────────────────────────────────────────────

async function main(): Promise<void> {
  testMd5AndUtf8();
  testEndpointsAndNetworkHelpers();
  await testHttpFramingAndSecurity();
  await testEndToEndLanMigration();
  await testMd5MismatchAndCancel();
  testActivityStateIntegration();

  if (fails.length > 0) {
    console.error(`\n✗ ${fails.length} failed / ${pass + fails.length} assertions`);
    for (let i = 0; i < fails.length; i++) {
      console.error('  - ' + fails[i]);
    }
    throw new Error('p4-wifi-lan-transfer test failed');
  }
  console.log(`✓ p4-wifi-lan-transfer: ${pass} assertions passed`);
}

main().catch((err: Error): void => {
  console.error(err);
  throw err;
});
