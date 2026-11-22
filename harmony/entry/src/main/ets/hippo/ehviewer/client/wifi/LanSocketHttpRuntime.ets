/*
 * Copyright 2026 ehviewer-harmony contributors
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

/**
 * Stage B Track P4 — Platform Runtime Bridge for Same-LAN HTTP Transfer (DEVIATIONS.md D-002).
 *
 * Strictly complies with OpenHarmony SDK 20 (`runtimeOS: "OpenHarmony"`, D-008) and the
 * `apl <= normal` permission iron law (`INTERNET`, `GET_NETWORK_INFO`, `GET_WIFI_INFO`):
 *   - ZERO hotspot / SoftAP APIs, ZERO Wi-Fi scanning or auto-connect APIs.
 *   - `LanTcpHttpServer`: wraps `@ohos.net.socket` `TCPSocketServer` on `0.0.0.0:<port>`.
 *   - `LanHttpClientTransport`: wraps `@ohos.net.http` (`usingProxy: false` for same-LAN).
 *   - `LanNetworkHelper`: read-only local IPv4 + SSID query via `@ohos.net.connection` & `@ohos.wifiManager`.
 *   - `LanStorageBridge`: bridges `EhDB`, `DownloadManager`, `Settings`/`AppConfig`, `@kit.CoreFileKit`
 *     and streaming RFC 1321 `LanMd5Hasher`.
 */

import socket from '@ohos.net.socket';
import http from '@ohos.net.http';
import connection from '@ohos.net.connection';
import wifiManager from '@ohos.wifiManager';
import { fileIo as fs } from '@kit.CoreFileKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { AppConfig } from '../../AppConfig';
import { EhDB } from '../../EhDB';
import { Settings } from '../../Settings';
import { DownloadManager } from '../../download/DownloadManager';
import { GalleryInfo } from '../data/GalleryInfo';
import { DownloadInfo } from '../../dao/DownloadInfo';
import { DownloadLabel } from '../../dao/DownloadLabel';
import { QuickSearch } from '../../dao/QuickSearch';
import { Contracts } from '../../../unifile/Contracts';
import { UniFile } from '../../../unifile/UniFile';
import { MigrationFileSystem } from './WiFiDownloadMigrationHelper';
import {
  FileChunkSource,
  NetworkInterfaceLike,
  WiFiServerActivity
} from '../../ui/wifi/WiFiServerActivity';
import {
  MigrationPersistSink,
  MigrationWriteSink
} from '../../ui/wifi/WiFiClientActivity';
import {
  LanEndpointCodec,
  LanHttpCodec,
  LanHttpFeedResult,
  LanHttpFeedStatus,
  LanHttpRequest,
  LanHttpRequestBuffer,
  LanHttpRequester,
  LanHttpResponse,
  LanHttpTransferRouter,
  LanMd5Hasher,
  LanServerDataProvider,
  LanUtf8
} from './LanHttpProtocol';

const LOG_DOMAIN: number = 0x0000;
const LOG_TAG: string = 'LanSocketHttpRuntime';
const MD5_READ_BLOCK_SIZE: number = 64 * 1024;
const CLIENT_IDLE_TIMEOUT_MS: number = 15000;
const MAX_HTTP_RESPONSE_LIMIT: number = 100 * 1024 * 1024;

// ── Local LAN Network Helper (read-only, D-002 compliant) ───────────────────

export class LanNetworkInfo {
  readonly ipv4: string | null;
  readonly ssid: string;
  readonly wifiActive: boolean;
  readonly interfaceName: string;

  constructor(ipv4: string | null, ssid: string, wifiActive: boolean, interfaceName: string) {
    this.ipv4 = ipv4;
    this.ssid = ssid;
    this.wifiActive = wifiActive;
    this.interfaceName = interfaceName;
  }
}

export class LanNetworkHelper {
  static async queryLocalLanInfo(): Promise<LanNetworkInfo> {
    let wifiActive: boolean = false;
    let ssid: string = '';
    let ipv4: string | null = null;
    let interfaceName: string = '';

    try {
      wifiActive = wifiManager.isWifiActive();
    } catch (err) {
      const msg: string = err instanceof Error ? err.message : String(err);
      hilog.warn(LOG_DOMAIN, LOG_TAG, 'wifiManager.isWifiActive failed: %{public}s', msg);
    }

    if (wifiActive) {
      try {
        const linked: wifiManager.WifiLinkedInfo = await wifiManager.getLinkedInfo();
        if (linked.ssid !== undefined && linked.ssid !== null) {
          ssid = LanNetworkHelper.stripSsidQuotes(linked.ssid);
        }
      } catch (err) {
        const msg: string = err instanceof Error ? err.message : String(err);
        hilog.warn(LOG_DOMAIN, LOG_TAG, 'wifiManager.getLinkedInfo failed: %{public}s', msg);
      }
    }

    // 1) Primary: read active network interfaces via @ohos.net.connection (returns exact IPv4 strings)
    try {
      const nets: Array<connection.NetHandle> = await LanNetworkHelper.collectActiveNets();
      const interfaces: NetworkInterfaceLike[] = [];
      let fallbackIp: string | null = null;
      let fallbackIf: string = '';

      for (let i = 0; i < nets.length; i++) {
        try {
          const props: connection.ConnectionProperties = await connection.getConnectionProperties(nets[i]);
          const ifName: string = props.interfaceName !== undefined ? props.interfaceName : '';
          const addrs: string[] = [];
          const ipv4Flags: boolean[] = [];
          const links: Array<connection.LinkAddress> =
            props.linkAddresses !== undefined ? props.linkAddresses : [];
          for (let j = 0; j < links.length; j++) {
            const addr: string = links[j].address !== undefined && links[j].address.address !== undefined
              ? links[j].address.address.trim()
              : '';
            if (addr.length === 0) {
              continue;
            }
            const isV4: boolean = LanEndpointCodec.isValidIpv4(addr);
            addrs.push(addr);
            ipv4Flags.push(isV4);
            if (isV4 && !addr.startsWith('127.') && addr !== '0.0.0.0' && fallbackIp === null) {
              fallbackIp = addr;
              fallbackIf = ifName;
            }
          }
          interfaces.push(new NetworkInterfaceLike(ifName, addrs, ipv4Flags));
        } catch (propErr) {
          const msg: string = propErr instanceof Error ? propErr.message : String(propErr);
          hilog.warn(LOG_DOMAIN, LOG_TAG, 'getConnectionProperties failed: %{public}s', msg);
        }
      }

      const wlanIp: string | null = WiFiServerActivity.pickWlanIpv4(interfaces);
      if (wlanIp !== null) {
        ipv4 = wlanIp;
        interfaceName = 'wlan';
      } else if (fallbackIp !== null) {
        ipv4 = fallbackIp;
        interfaceName = fallbackIf;
      }
    } catch (connErr) {
      const msg: string = connErr instanceof Error ? connErr.message : String(connErr);
      hilog.warn(LOG_DOMAIN, LOG_TAG, 'connection interface query failed: %{public}s', msg);
    }

    // 2) Fallback: read wifiManager.getIpInfo() (read-only GET_WIFI_INFO)
    if (ipv4 === null && wifiActive) {
      try {
        const ipInfo: wifiManager.IpInfo = wifiManager.getIpInfo();
        const decoded: string | null = LanEndpointCodec.decodeWifiIpInt(ipInfo.ipAddress);
        if (decoded !== null) {
          ipv4 = decoded;
          interfaceName = 'wlan0';
        }
      } catch (ipErr) {
        const msg: string = ipErr instanceof Error ? ipErr.message : String(ipErr);
        hilog.warn(LOG_DOMAIN, LOG_TAG, 'wifiManager.getIpInfo failed: %{public}s', msg);
      }
    }

    return new LanNetworkInfo(ipv4, ssid, wifiActive, interfaceName);
  }

  private static async collectActiveNets(): Promise<Array<connection.NetHandle>> {
    const out: Array<connection.NetHandle> = [];
    try {
      const allNets: Array<connection.NetHandle> = await connection.getAllNets();
      for (let i = 0; i < allNets.length; i++) {
        if (allNets[i].netId > 0) {
          out.push(allNets[i]);
        }
      }
    } catch (err) {
      const msg: string = err instanceof Error ? err.message : String(err);
      hilog.warn(LOG_DOMAIN, LOG_TAG, 'connection.getAllNets failed: %{public}s', msg);
    }
    if (out.length === 0) {
      try {
        const defNet: connection.NetHandle = await connection.getDefaultNet();
        if (defNet.netId > 0) {
          out.push(defNet);
        }
      } catch (err) {
        const msg: string = err instanceof Error ? err.message : String(err);
        hilog.warn(LOG_DOMAIN, LOG_TAG, 'connection.getDefaultNet failed: %{public}s', msg);
      }
    }
    return out;
  }

  private static stripSsidQuotes(raw: string): string {
    const t: string = raw.trim();
    if (t.length >= 2 && t.startsWith('"') && t.endsWith('"')) {
      return t.substring(1, t.length - 1);
    }
    return t;
  }
}

// ── TCP HTTP/1.1 Server (@ohos.net.socket TCPSocketServer) ──────────────────

export class LanTcpHttpServer {
  private readonly router: LanHttpTransferRouter;
  private readonly onClientCountChanged: ((count: number) => void) | null;
  private readonly onServerError: ((message: string) => void) | null;
  private server: socket.TCPSocketServer | null = null;
  private readonly activeConnections: Map<number, socket.TCPSocketConnection> =
    new Map<number, socket.TCPSocketConnection>();
  private running: boolean = false;
  private port: number = LanEndpointCodec.DEFAULT_PORT;

  constructor(
    router: LanHttpTransferRouter,
    onClientCountChanged?: (count: number) => void,
    onServerError?: (message: string) => void
  ) {
    this.router = router;
    this.onClientCountChanged = onClientCountChanged !== undefined ? onClientCountChanged : null;
    this.onServerError = onServerError !== undefined ? onServerError : null;
  }

  isRunning(): boolean {
    return this.running;
  }

  getPort(): number {
    return this.port;
  }

  getActiveClientCount(): number {
    return this.activeConnections.size;
  }

  async start(port: number = LanEndpointCodec.DEFAULT_PORT): Promise<void> {
    if (this.running) {
      await this.stop();
    }
    this.port = port;
    const tcpServer: socket.TCPSocketServer = socket.constructTCPSocketServerInstance();
    this.server = tcpServer;

    const listenAddr: socket.NetAddress = {
      address: '0.0.0.0',
      port: port,
      family: 1
    };

    try {
      await tcpServer.listen(listenAddr);
      this.running = true;
      this.router.setServing(true);

      tcpServer.on('connect', (conn: socket.TCPSocketConnection): void => {
        this.handleClientConnection(conn);
      });
      tcpServer.on('error', (err: Object): void => {
        const msg: string = err instanceof Error ? err.message : JSON.stringify(err);
        hilog.error(LOG_DOMAIN, LOG_TAG, 'TCPSocketServer error: %{public}s', msg);
        if (this.onServerError !== null) {
          this.onServerError(msg);
        }
      });
      hilog.info(LOG_DOMAIN, LOG_TAG, 'LAN HTTP server listening on 0.0.0.0:%{public}d', port);
    } catch (err) {
      const msg: string = err instanceof Error ? err.message : String(err);
      hilog.error(LOG_DOMAIN, LOG_TAG, 'LAN HTTP server listen failed on port %{public}d: %{public}s', port, msg);
      await this.stop();
      throw new Error(`Failed to listen on port ${port}: ${msg}`);
    }
  }

  async stop(): Promise<void> {
    this.running = false;
    this.router.setServing(false);

    const conns: socket.TCPSocketConnection[] = [];
    this.activeConnections.forEach((conn: socket.TCPSocketConnection): void => {
      conns.push(conn);
    });
    this.activeConnections.clear();
    this.notifyClientCount();

    for (let i = 0; i < conns.length; i++) {
      this.closeConnectionSafe(conns[i]);
    }

    const tcpServer: socket.TCPSocketServer | null = this.server;
    this.server = null;
    if (tcpServer !== null) {
      try {
        tcpServer.off('connect');
        tcpServer.off('error');
      } catch (offErr) {
        const msg: string = offErr instanceof Error ? offErr.message : String(offErr);
        hilog.warn(LOG_DOMAIN, LOG_TAG, 'TCPSocketServer off listeners failed: %{public}s', msg);
      }
      try {
        await tcpServer.close();
      } catch (closeErr) {
        const msg: string = closeErr instanceof Error ? closeErr.message : String(closeErr);
        hilog.warn(LOG_DOMAIN, LOG_TAG, 'TCPSocketServer close failed: %{public}s', msg);
      }
    }
  }

  private handleClientConnection(conn: socket.TCPSocketConnection): void {
    if (!this.running) {
      this.closeConnectionSafe(conn);
      return;
    }
    const clientId: number = conn.clientId;
    this.activeConnections.set(clientId, conn);
    this.notifyClientCount();

    const buffer: LanHttpRequestBuffer = new LanHttpRequestBuffer();
    let handled: boolean = false;
    let closed: boolean = false;
    let idleTimer: number = -1;

    const cleanup = (): void => {
      if (idleTimer !== -1) {
        clearTimeout(idleTimer);
        idleTimer = -1;
      }
      if (!closed) {
        closed = true;
        this.activeConnections.delete(clientId);
        this.notifyClientCount();
        this.closeConnectionSafe(conn);
      }
    };

    idleTimer = setTimeout((): void => {
      hilog.warn(LOG_DOMAIN, LOG_TAG, 'Closing idle LAN HTTP client %{public}d', clientId);
      cleanup();
    }, CLIENT_IDLE_TIMEOUT_MS) as number;

    const sendAndClose = (resp: LanHttpResponse): void => {
      const wire: ArrayBuffer = LanHttpCodec.serializeResponse(resp);
      const sendOpts: socket.TCPSendOptions = { data: wire };
      conn.send(sendOpts).then((): void => {
        cleanup();
      }).catch((sendErr: Error): void => {
        hilog.warn(LOG_DOMAIN, LOG_TAG, 'Send response failed for client %{public}d: %{public}s',
          clientId, sendErr instanceof Error ? sendErr.message : String(sendErr));
        cleanup();
      });
    };

    conn.on('message', (info: socket.SocketMessageInfo): void => {
      if (handled || closed) {
        return;
      }
      const chunk: Uint8Array = new Uint8Array(info.message);
      const feedRes: LanHttpFeedResult = buffer.feed(chunk);
      if (feedRes.status === LanHttpFeedStatus.INCOMPLETE) {
        return;
      }
      handled = true;
      if (idleTimer !== -1) {
        clearTimeout(idleTimer);
        idleTimer = -1;
      }
      if (feedRes.status === LanHttpFeedStatus.ERROR || feedRes.request === null) {
        sendAndClose(LanHttpResponse.error(feedRes.errorCode || 400, feedRes.errorMessage || 'Bad Request'));
        return;
      }
      const req: LanHttpRequest = feedRes.request;
      this.router.handleRequest(req).then((resp: LanHttpResponse): void => {
        if (!closed) {
          sendAndClose(resp);
        }
      }).catch((routeErr: Error): void => {
        const msg: string = routeErr instanceof Error ? routeErr.message : String(routeErr);
        hilog.error(LOG_DOMAIN, LOG_TAG, 'Unhandled router error: %{public}s', msg);
        if (!closed) {
          sendAndClose(LanHttpResponse.error(500, msg));
        }
      });
    });

    conn.on('close', (): void => {
      cleanup();
    });

    conn.on('error', (err: Object): void => {
      const msg: string = err instanceof Error ? err.message : JSON.stringify(err);
      hilog.warn(LOG_DOMAIN, LOG_TAG, 'LAN HTTP client %{public}d error: %{public}s', clientId, msg);
      cleanup();
    });
  }

  private closeConnectionSafe(conn: socket.TCPSocketConnection): void {
    try {
      conn.off('message');
      conn.off('close');
      conn.off('error');
    } catch (offErr) {
      const msg: string = offErr instanceof Error ? offErr.message : String(offErr);
      hilog.warn(LOG_DOMAIN, LOG_TAG, 'Client off listeners failed: %{public}s', msg);
    }
    conn.close().catch((closeErr: Error): void => {
      const msg: string = closeErr instanceof Error ? closeErr.message : String(closeErr);
      hilog.warn(LOG_DOMAIN, LOG_TAG, 'Client connection close failed: %{public}s', msg);
    });
  }

  private notifyClientCount(): void {
    if (this.onClientCountChanged !== null) {
      this.onClientCountChanged(this.activeConnections.size);
    }
  }
}

// ── HTTP Client Transport (@ohos.net.http, LAN direct without proxy) ────────

export class LanHttpClientTransport implements LanHttpRequester {
  private readonly activeRequests: Set<http.HttpRequest> = new Set<http.HttpRequest>();

  async request(method: string, url: string, timeoutMs: number): Promise<LanHttpResponse> {
    const req: http.HttpRequest = http.createHttp();
    this.activeRequests.add(req);
    const httpOptions: http.HttpRequestOptions = {
      method: method.toUpperCase() === 'POST' ? http.RequestMethod.POST : http.RequestMethod.GET,
      expectDataType: http.HttpDataType.ARRAY_BUFFER,
      usingCache: false,
      usingProxy: false,
      connectTimeout: timeoutMs,
      readTimeout: timeoutMs,
      maxLimit: MAX_HTTP_RESPONSE_LIMIT
    };

    try {
      const resp: http.HttpResponse = await req.request(url, httpOptions);
      const code: number = resp.responseCode as number;
      const headers: Map<string, string> = LanHttpClientTransport.parseHeaders(resp.header);
      const body: ArrayBuffer = LanHttpClientTransport.extractBody(resp.result);
      return new LanHttpResponse(code, LanHttpCodec.reasonPhrase(code), headers, body);
    } finally {
      this.activeRequests.delete(req);
      try {
        req.destroy();
      } catch (destroyErr) {
        const msg: string = destroyErr instanceof Error ? destroyErr.message : String(destroyErr);
        hilog.warn(LOG_DOMAIN, LOG_TAG, 'http.HttpRequest destroy failed: %{public}s', msg);
      }
    }
  }

  abortAll(): void {
    const list: http.HttpRequest[] = [];
    this.activeRequests.forEach((req: http.HttpRequest): void => {
      list.push(req);
    });
    this.activeRequests.clear();
    for (let i = 0; i < list.length; i++) {
      try {
        list[i].destroy();
      } catch (err) {
        const msg: string = err instanceof Error ? err.message : String(err);
        hilog.warn(LOG_DOMAIN, LOG_TAG, 'abortAll destroy failed: %{public}s', msg);
      }
    }
  }

  private static parseHeaders(raw: Object): Map<string, string> {
    const out: Map<string, string> = new Map<string, string>();
    if (raw === null || raw === undefined) {
      return out;
    }
    const rec: Record<string, Object> = raw as Record<string, Object>;
    const keys: string[] = Object.keys(rec);
    for (let i = 0; i < keys.length; i++) {
      const k: string = keys[i];
      const v: Object = rec[k];
      if (v instanceof Array) {
        const arr: string[] = v as string[];
        out.set(k, arr.join(', '));
      } else if (v !== null && v !== undefined) {
        out.set(k, `${v}`);
      }
    }
    return out;
  }

  private static extractBody(result: string | Object | ArrayBuffer): ArrayBuffer {
    if (result instanceof ArrayBuffer) {
      return result;
    }
    if (typeof result === 'string') {
      return LanUtf8.encodeToBuffer(result as string);
    }
    return new ArrayBuffer(0);
  }
}

// ── Storage Bridge (EhDB + DownloadManager + CoreFileKit + Pure MD5) ────────

export class LanStorageBridge implements
  LanServerDataProvider,
  MigrationFileSystem,
  FileChunkSource,
  MigrationWriteSink,
  MigrationPersistSink {

  private persistQueue: Promise<void> = Promise.resolve();
  private lastPersistError: Error | null = null;

  resolveDownloadRootPath(): string | null {
    try {
      const loc: UniFile | null = Settings.getDownloadLocation();
      if (loc !== null) {
        const p: string = Contracts.normalize(loc.getUri());
        if (p.length > 0) {
          this.ensureDirExists(p);
          return p;
        }
      }
    } catch (err) {
      const msg: string = err instanceof Error ? err.message : String(err);
      hilog.warn(LOG_DOMAIN, LOG_TAG, 'Settings.getDownloadLocation failed: %{public}s', msg);
    }
    const defDir: string | null = AppConfig.getDefaultDownloadDir();
    if (defDir !== null && defDir.length > 0) {
      this.ensureDirExists(defDir);
      return defDir;
    }
    return null;
  }

  // ---- LanServerDataProvider ----

  getAppVersion(): string {
    return '2.0.2.6';
  }

  getDeviceName(): string {
    return 'EhViewer-Harmony';
  }

  async getQuickSearches(): Promise<QuickSearch[]> {
    if (!EhDB.isAttached()) {
      hilog.warn(LOG_DOMAIN, LOG_TAG, 'EhDB not attached during getQuickSearches');
      return [];
    }
    return await EhDB.getAllQuickSearch();
  }

  async getLocalFavorites(): Promise<GalleryInfo[]> {
    if (!EhDB.isAttached()) {
      hilog.warn(LOG_DOMAIN, LOG_TAG, 'EhDB not attached during getLocalFavorites');
      return [];
    }
    return await EhDB.getAllLocalFavorites();
  }

  async getDownloadLabels(): Promise<DownloadLabel[]> {
    if (!EhDB.isAttached()) {
      hilog.warn(LOG_DOMAIN, LOG_TAG, 'EhDB not attached during getDownloadLabels');
      return [];
    }
    return await EhDB.getAllDownloadLabelList();
  }

  async getDownloadInfos(): Promise<DownloadInfo[]> {
    if (!EhDB.isAttached()) {
      hilog.warn(LOG_DOMAIN, LOG_TAG, 'EhDB not attached during getDownloadInfos');
      return [];
    }
    return await EhDB.getAllDownloadInfo();
  }

  getDownloadRoot(): string | null {
    return this.resolveDownloadRootPath();
  }

  // ---- MigrationFileSystem ----

  list(dir: string): string[] {
    try {
      return fs.listFileSync(dir, { recursion: false });
    } catch (err) {
      const msg: string = err instanceof Error ? err.message : String(err);
      hilog.warn(LOG_DOMAIN, LOG_TAG, 'fs.listFileSync failed for %{public}s: %{public}s', dir, msg);
      return [];
    }
  }

  isDirectory(path: string): boolean {
    try {
      return fs.statSync(path).isDirectory();
    } catch (err) {
      const msg: string = err instanceof Error ? err.message : String(err);
      hilog.debug(LOG_DOMAIN, LOG_TAG, 'isDirectory stat failed for %{public}s: %{public}s', path, msg);
      return false;
    }
  }

  isFile(path: string): boolean {
    try {
      return fs.statSync(path).isFile();
    } catch (err) {
      const msg: string = err instanceof Error ? err.message : String(err);
      hilog.debug(LOG_DOMAIN, LOG_TAG, 'isFile stat failed for %{public}s: %{public}s', path, msg);
      return false;
    }
  }

  size(path: string): number {
    try {
      return fs.statSync(path).size;
    } catch (err) {
      const msg: string = err instanceof Error ? err.message : String(err);
      hilog.warn(LOG_DOMAIN, LOG_TAG, 'size stat failed for %{public}s: %{public}s', path, msg);
      return 0;
    }
  }

  computeMd5Hex(path: string): string | null {
    let file: fs.File | null = null;
    try {
      file = fs.openSync(path, fs.OpenMode.READ_ONLY);
      const hasher: LanMd5Hasher = new LanMd5Hasher();
      const buf: ArrayBuffer = new ArrayBuffer(MD5_READ_BLOCK_SIZE);
      const view: Uint8Array = new Uint8Array(buf);
      while (true) {
        // Never pass running offset to fs.readSync (F-3 ruling: offset is relative to kernel file pointer)
        const n: number = fs.readSync(file.fd, buf, { length: MD5_READ_BLOCK_SIZE });
        if (n <= 0) {
          break;
        }
        hasher.update(n === MD5_READ_BLOCK_SIZE ? view : view.subarray(0, n));
      }
      return hasher.digestHex();
    } catch (err) {
      const msg: string = err instanceof Error ? err.message : String(err);
      hilog.warn(LOG_DOMAIN, LOG_TAG, 'computeMd5Hex failed for %{public}s: %{public}s', path, msg);
      return null;
    } finally {
      if (file !== null) {
        try {
          fs.closeSync(file);
        } catch (closeErr) {
          const msg: string = closeErr instanceof Error ? closeErr.message : String(closeErr);
          hilog.warn(LOG_DOMAIN, LOG_TAG, 'closeSync after MD5 failed: %{public}s', msg);
        }
      }
    }
  }

  resolveFileInGallery(galleryDir: string, relPath: string): string | null {
    if (!LanHttpCodec.isSafeRelPath(relPath)) {
      return null;
    }
    const full: string = LanStorageBridge.joinPath(galleryDir, relPath);
    try {
      return fs.accessSync(full) ? full : null;
    } catch (err) {
      const msg: string = err instanceof Error ? err.message : String(err);
      hilog.debug(LOG_DOMAIN, LOG_TAG, 'resolveFileInGallery access failed for %{public}s: %{public}s', full, msg);
      return null;
    }
  }

  // ---- FileChunkSource ----

  readChunk(path: string, offset: number, length: number): Uint8Array | null {
    if (length <= 0) {
      return null;
    }
    let file: fs.File | null = null;
    try {
      file = fs.openSync(path, fs.OpenMode.READ_ONLY);
      if (offset > 0) {
        fs.lseek(file.fd, offset, fs.WhenceType.SEEK_SET);
      }
      const buf: ArrayBuffer = new ArrayBuffer(length);
      const n: number = fs.readSync(file.fd, buf, { length: length });
      if (n <= 0) {
        return null;
      }
      const view: Uint8Array = new Uint8Array(buf);
      if (n === length) {
        return view;
      }
      const trimmed: Uint8Array = new Uint8Array(n);
      trimmed.set(view.subarray(0, n));
      return trimmed;
    } catch (err) {
      const msg: string = err instanceof Error ? err.message : String(err);
      hilog.warn(LOG_DOMAIN, LOG_TAG, 'readChunk failed for %{public}s@%{public}d: %{public}s', path, offset, msg);
      return null;
    } finally {
      if (file !== null) {
        try {
          fs.closeSync(file);
        } catch (closeErr) {
          const msg: string = closeErr instanceof Error ? closeErr.message : String(closeErr);
          hilog.warn(LOG_DOMAIN, LOG_TAG, 'closeSync after readChunk failed: %{public}s', msg);
        }
      }
    }
  }

  // ---- MigrationWriteSink ----

  hasDownloadRoot(): boolean {
    return this.resolveDownloadRootPath() !== null;
  }

  ensureGalleryDir(gid: number, dirname: string): string | null {
    const root: string | null = this.resolveDownloadRootPath();
    if (root === null || !LanHttpCodec.isSafeDirName(dirname)) {
      return null;
    }
    const dirPath: string = LanStorageBridge.joinPath(root, dirname);
    if (!this.ensureDirExists(dirPath)) {
      return null;
    }
    if (EhDB.isAttached()) {
      this.enqueuePersist(async (): Promise<void> => {
        await EhDB.putDownloadDirname(gid, dirname);
      });
    }
    return dirPath;
  }

  deleteFile(path: string): boolean {
    try {
      if (!fs.accessSync(path)) {
        return true;
      }
      fs.unlinkSync(path);
      return true;
    } catch (err) {
      const msg: string = err instanceof Error ? err.message : String(err);
      hilog.warn(LOG_DOMAIN, LOG_TAG, 'deleteFile failed for %{public}s: %{public}s', path, msg);
      return false;
    }
  }

  writeChunk(galleryDir: string, name: string, data: Uint8Array, offset: number): boolean {
    if (!LanHttpCodec.isSafeRelPath(name)) {
      hilog.warn(LOG_DOMAIN, LOG_TAG, 'Refused unsafe writeChunk path: %{public}s', name);
      return false;
    }
    const fullPath: string = LanStorageBridge.joinPath(galleryDir, name);
    const slashIdx: number = fullPath.lastIndexOf('/');
    if (slashIdx > 0) {
      const parentDir: string = fullPath.substring(0, slashIdx);
      if (!this.ensureDirExists(parentDir)) {
        return false;
      }
    }

    let file: fs.File | null = null;
    try {
      let mode: number = fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY;
      if (offset === 0) {
        mode = mode | fs.OpenMode.TRUNC;
      }
      file = fs.openSync(fullPath, mode);
      if (offset > 0) {
        fs.lseek(file.fd, offset, fs.WhenceType.SEEK_SET);
      }
      if (data.byteLength > 0) {
        const buf: ArrayBuffer = LanUtf8.toArrayBuffer(data);
        fs.writeSync(file.fd, buf, { length: data.byteLength });
      }
      return true;
    } catch (err) {
      const msg: string = err instanceof Error ? err.message : String(err);
      hilog.error(LOG_DOMAIN, LOG_TAG, 'writeChunk failed for %{public}s@%{public}d: %{public}s',
        fullPath, offset, msg);
      return false;
    } finally {
      if (file !== null) {
        try {
          fs.closeSync(file);
        } catch (closeErr) {
          const msg: string = closeErr instanceof Error ? closeErr.message : String(closeErr);
          hilog.warn(LOG_DOMAIN, LOG_TAG, 'closeSync after writeChunk failed: %{public}s', msg);
        }
      }
    }
  }

  resolveFile(galleryDir: string, relPath: string): string | null {
    return this.resolveFileInGallery(galleryDir, relPath);
  }

  // ---- MigrationPersistSink (FIFO serialized async DB/DownloadManager writes) ----

  takeOverQuickSearchList(jsonTexts: string[]): void {
    const copies: string[] = jsonTexts.slice();
    this.enqueuePersist(async (): Promise<void> => {
      if (!EhDB.isAttached()) {
        throw new Error('EhDB is not attached');
      }
      const list: QuickSearch[] = [];
      for (let i = 0; i < copies.length; i++) {
        list.push(QuickSearch.quickSearchFromJson(copies[i]));
      }
      await EhDB.takeOverQuickSearchList(list);
    });
  }

  addDownloadLabel(label: string): void {
    if (label.length === 0) {
      return;
    }
    this.enqueuePersist(async (): Promise<void> => {
      const dm: DownloadManager = await DownloadManager.getInstance();
      await dm.addLabelInSyncThread(label);
    });
  }

  addDownloadInfo(jsonText: string): void {
    this.enqueuePersist(async (): Promise<void> => {
      const info: DownloadInfo = DownloadInfo.downloadInfoFromJson(jsonText);
      const dm: DownloadManager = await DownloadManager.getInstance();
      if (info.label !== null && info.label.length > 0 && !dm.containLabel(info.label)) {
        await dm.addLabelInSyncThread(info.label);
      }
      await dm.addDownloadList([info]);
    });
  }

  putLocalFavorite(jsonText: string): void {
    this.enqueuePersist(async (): Promise<void> => {
      if (!EhDB.isAttached()) {
        throw new Error('EhDB is not attached');
      }
      const gi: GalleryInfo = GalleryInfo.fromJson(jsonText);
      await EhDB.putLocalFavorite(gi);
    });
  }

  async flushPersistence(): Promise<void> {
    await this.persistQueue;
    const err: Error | null = this.lastPersistError;
    this.lastPersistError = null;
    if (err !== null) {
      throw err;
    }
  }

  private enqueuePersist(task: () => Promise<void>): void {
    this.persistQueue = this.persistQueue.then(async (): Promise<void> => {
      try {
        await task();
      } catch (err) {
        const errorObj: Error = err instanceof Error ? err : new Error(String(err));
        hilog.error(LOG_DOMAIN, LOG_TAG, 'LAN migration persist failed: %{public}s', errorObj.message);
        if (this.lastPersistError === null) {
          this.lastPersistError = errorObj;
        }
      }
    });
  }

  private ensureDirExists(dirPath: string): boolean {
    try {
      if (fs.accessSync(dirPath)) {
        return true;
      }
      fs.mkdirSync(dirPath, true);
      return true;
    } catch (err) {
      const msg: string = err instanceof Error ? err.message : String(err);
      hilog.warn(LOG_DOMAIN, LOG_TAG, 'ensureDirExists failed for %{public}s: %{public}s', dirPath, msg);
      return false;
    }
  }

  private static joinPath(dir: string, name: string): string {
    return dir.length > 0 && dir.charAt(dir.length - 1) === '/' ? dir + name : dir + '/' + name;
  }
}
