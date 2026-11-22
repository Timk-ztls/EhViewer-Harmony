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
 * Stage B Track P4 — Same-LAN HTTP/1.1 Transfer Protocol & Orchestration (DEVIATIONS.md D-002).
 *
 * Pure ArkTS/TypeScript logic with ZERO platform socket/fs/ArkUI imports so the entire
 * protocol codec, RFC 1321 MD5 hasher, endpoint/QR parser, HTTP router, and pull client
 * are 100% deterministic and testable in Node/tsc as well as OpenHarmony SDK 20.
 */

import { hilog } from '@kit.PerformanceAnalysisKit';
import { GalleryInfo } from '../data/GalleryInfo';
import { DownloadInfo } from '../../dao/DownloadInfo';
import { DownloadLabel } from '../../dao/DownloadLabel';
import { QuickSearch } from '../../dao/QuickSearch';
import { JsonArray, JsonObject } from '../parser/Json';
import { WiFiDownloadMigrationHelper, MigrationFileSystem } from './WiFiDownloadMigrationHelper';
import { DirManifest, FileChunk, FileMeta, GalleryDirEntry } from './MigrationTypes';
import {
  FileChunkSource,
  WiFiServerActivity,
  WiFiServerMenu
} from '../../ui/wifi/WiFiServerActivity';
import {
  ManifestPlan,
  MigrationPersistSink,
  MigrationWriteSink,
  PersistBatch,
  ReceiveKind,
  WiFiClientActivity
} from '../../ui/wifi/WiFiClientActivity';

const LOG_DOMAIN: number = 0x0000;
const LOG_TAG: string = 'LanHttpProtocol';

// ── UTF-8 pure codec ────────────────────────────────────────────────────────

export class LanUtf8 {
  static encode(text: string): Uint8Array {
    const out: number[] = [];
    for (let i = 0; i < text.length; i++) {
      let cp: number = text.charCodeAt(i);
      if (cp >= 0xD800 && cp <= 0xDBFF && i + 1 < text.length) {
        const low: number = text.charCodeAt(i + 1);
        if (low >= 0xDC00 && low <= 0xDFFF) {
          cp = 0x10000 + ((cp - 0xD800) << 10) + (low - 0xDC00);
          i++;
        }
      }
      if (cp < 0x80) {
        out.push(cp);
      } else if (cp < 0x800) {
        out.push(0xC0 | (cp >> 6));
        out.push(0x80 | (cp & 0x3F));
      } else if (cp < 0x10000) {
        out.push(0xE0 | (cp >> 12));
        out.push(0x80 | ((cp >> 6) & 0x3F));
        out.push(0x80 | (cp & 0x3F));
      } else {
        out.push(0xF0 | (cp >> 18));
        out.push(0x80 | ((cp >> 12) & 0x3F));
        out.push(0x80 | ((cp >> 6) & 0x3F));
        out.push(0x80 | (cp & 0x3F));
      }
    }
    const bytes: Uint8Array = new Uint8Array(out.length);
    for (let i = 0; i < out.length; i++) {
      bytes[i] = out[i];
    }
    return bytes;
  }

  static encodeToBuffer(text: string): ArrayBuffer {
    const bytes: Uint8Array = LanUtf8.encode(text);
    return LanUtf8.toArrayBuffer(bytes);
  }

  static decode(bytes: Uint8Array, start: number = 0, end: number = -1): string {
    const limit: number = end < 0 || end > bytes.byteLength ? bytes.byteLength : end;
    const parts: string[] = [];
    let i: number = start < 0 ? 0 : start;
    while (i < limit) {
      const b0: number = bytes[i];
      if (b0 < 0x80) {
        parts.push(String.fromCharCode(b0));
        i++;
      } else if ((b0 & 0xE0) === 0xC0 && i + 1 < limit) {
        const b1: number = bytes[i + 1];
        if ((b1 & 0xC0) === 0x80) {
          const cp: number = ((b0 & 0x1F) << 6) | (b1 & 0x3F);
          parts.push(String.fromCharCode(cp));
          i += 2;
        } else {
          parts.push('\uFFFD');
          i++;
        }
      } else if ((b0 & 0xF0) === 0xE0 && i + 2 < limit) {
        const b1: number = bytes[i + 1];
        const b2: number = bytes[i + 2];
        if ((b1 & 0xC0) === 0x80 && (b2 & 0xC0) === 0x80) {
          const cp: number = ((b0 & 0x0F) << 12) | ((b1 & 0x3F) << 6) | (b2 & 0x3F);
          parts.push(String.fromCharCode(cp));
          i += 3;
        } else {
          parts.push('\uFFFD');
          i++;
        }
      } else if ((b0 & 0xF8) === 0xF0 && i + 3 < limit) {
        const b1: number = bytes[i + 1];
        const b2: number = bytes[i + 2];
        const b3: number = bytes[i + 3];
        if ((b1 & 0xC0) === 0x80 && (b2 & 0xC0) === 0x80 && (b3 & 0xC0) === 0x80) {
          let cp: number = ((b0 & 0x07) << 18) | ((b1 & 0x3F) << 12) | ((b2 & 0x3F) << 6) | (b3 & 0x3F);
          if (cp >= 0x10000 && cp <= 0x10FFFF) {
            cp -= 0x10000;
            parts.push(String.fromCharCode(0xD800 + (cp >> 10), 0xDC00 + (cp & 0x3FF)));
          } else {
            parts.push('\uFFFD');
          }
          i += 4;
        } else {
          parts.push('\uFFFD');
          i++;
        }
      } else {
        parts.push('\uFFFD');
        i++;
      }
    }
    return parts.join('');
  }

  static decodeBuffer(buf: ArrayBuffer): string {
    return LanUtf8.decode(new Uint8Array(buf), 0, buf.byteLength);
  }

  static toArrayBuffer(bytes: Uint8Array): ArrayBuffer {
    const copy: Uint8Array = new Uint8Array(bytes.byteLength);
    copy.set(bytes);
    return copy.buffer as ArrayBuffer;
  }
}

// ── Streaming RFC 1321 MD5 hasher ───────────────────────────────────────────

const MD5_SHIFTS: number[] = [
  7, 12, 17, 22, 7, 12, 17, 22, 7, 12, 17, 22, 7, 12, 17, 22,
  5, 9, 14, 20, 5, 9, 14, 20, 5, 9, 14, 20, 5, 9, 14, 20,
  4, 11, 16, 23, 4, 11, 16, 23, 4, 11, 16, 23, 4, 11, 16, 23,
  6, 10, 15, 21, 6, 10, 15, 21, 6, 10, 15, 21, 6, 10, 15, 21
];

const MD5_K: number[] = [
  0xd76aa478, 0xe8c7b756, 0x242070db, 0xc1bdceee,
  0xf57c0faf, 0x4787c62a, 0xa8304613, 0xfd469501,
  0x698098d8, 0x8b44f7af, 0xffff5bb1, 0x895cd7be,
  0x6b901122, 0xfd987193, 0xa679438e, 0x49b40821,
  0xf61e2562, 0xc040b340, 0x265e5a51, 0xe9b6c7aa,
  0xd62f105d, 0x02441453, 0xd8a1e681, 0xe7d3fbc8,
  0x21e1cde6, 0xc33707d6, 0xf4d50d87, 0x455a14ed,
  0xa9e3e905, 0xfcefa3f8, 0x676f02d9, 0x8d2a4c8a,
  0xfffa3942, 0x8771f681, 0x6d9d6122, 0xfde5380c,
  0xa4beea44, 0x4bdecfa9, 0xf6bb4b60, 0xbebfbc70,
  0x289b7ec6, 0xeaa127fa, 0xd4ef3085, 0x04881d05,
  0xd9d4d039, 0xe6db99e5, 0x1fa27cf8, 0xc4ac5665,
  0xf4292244, 0x432aff97, 0xab9423a7, 0xfc93a039,
  0x655b59c3, 0x8f0ccc92, 0xffeff47d, 0x85845dd1,
  0x6fa87e4f, 0xfe2ce6e0, 0xa3014314, 0x4e0811a1,
  0xf7537e82, 0xbd3af235, 0x2ad7d2bb, 0xeb86d391
];

export class LanMd5Hasher {
  private a0: number = 0x67452301;
  private b0: number = 0xefcdab89;
  private c0: number = 0x98badcfe;
  private d0: number = 0x10325476;
  private readonly tail: Uint8Array = new Uint8Array(64);
  private tailLen: number = 0;
  private totalBytes: number = 0;
  private readonly words: Int32Array = new Int32Array(16);

  update(chunk: Uint8Array): void {
    const len: number = chunk.byteLength;
    if (len === 0) {
      return;
    }
    this.totalBytes += len;
    let offset: number = 0;

    if (this.tailLen > 0) {
      const need: number = 64 - this.tailLen;
      if (len < need) {
        this.tail.set(chunk, this.tailLen);
        this.tailLen += len;
        return;
      }
      this.tail.set(chunk.subarray(0, need), this.tailLen);
      this.compressBlock(this.tail, 0);
      this.tailLen = 0;
      offset = need;
    }

    while (offset + 64 <= len) {
      this.compressBlock(chunk, offset);
      offset += 64;
    }

    if (offset < len) {
      const rem: number = len - offset;
      this.tail.set(chunk.subarray(offset, len), 0);
      this.tailLen = rem;
    }
  }

  digestHex(): string {
    const bitLen: number = this.totalBytes * 8;
    const padLen: number = this.tailLen < 56 ? (56 - this.tailLen) : (120 - this.tailLen);
    const pad: Uint8Array = new Uint8Array(padLen + 8);
    pad[0] = 0x80;
    const lo: number = bitLen >>> 0;
    const hi: number = Math.floor(bitLen / 4294967296) >>> 0;
    pad[padLen] = lo & 0xFF;
    pad[padLen + 1] = (lo >>> 8) & 0xFF;
    pad[padLen + 2] = (lo >>> 16) & 0xFF;
    pad[padLen + 3] = (lo >>> 24) & 0xFF;
    pad[padLen + 4] = hi & 0xFF;
    pad[padLen + 5] = (hi >>> 8) & 0xFF;
    pad[padLen + 6] = (hi >>> 16) & 0xFF;
    pad[padLen + 7] = (hi >>> 24) & 0xFF;

    const savedTotal: number = this.totalBytes;
    this.update(pad);
    this.totalBytes = savedTotal;

    const out: Uint8Array = new Uint8Array(16);
    LanMd5Hasher.writeLe32(out, 0, this.a0);
    LanMd5Hasher.writeLe32(out, 4, this.b0);
    LanMd5Hasher.writeLe32(out, 8, this.c0);
    LanMd5Hasher.writeLe32(out, 12, this.d0);
    return WiFiDownloadMigrationHelper.bytesToHex(out);
  }

  static md5Hex(bytes: Uint8Array): string {
    const h: LanMd5Hasher = new LanMd5Hasher();
    h.update(bytes);
    return h.digestHex();
  }

  static md5HexString(text: string): string {
    return LanMd5Hasher.md5Hex(LanUtf8.encode(text));
  }

  private compressBlock(buf: Uint8Array, off: number): void {
    const w: Int32Array = this.words;
    for (let i = 0; i < 16; i++) {
      const idx: number = off + i * 4;
      w[i] = (buf[idx] | (buf[idx + 1] << 8) | (buf[idx + 2] << 16) | (buf[idx + 3] << 24)) | 0;
    }

    let a: number = this.a0;
    let b: number = this.b0;
    let c: number = this.c0;
    let d: number = this.d0;

    for (let i = 0; i < 64; i++) {
      let f: number = 0;
      let g: number = 0;
      if (i < 16) {
        f = (b & c) | ((~b) & d);
        g = i;
      } else if (i < 32) {
        f = (d & b) | ((~d) & c);
        g = (5 * i + 1) & 15;
      } else if (i < 48) {
        f = b ^ c ^ d;
        g = (3 * i + 5) & 15;
      } else {
        f = c ^ (b | (~d));
        g = (7 * i) & 15;
      }
      const nextD: number = c;
      const nextC: number = b;
      const x: number = (a + f + MD5_K[i] + w[g]) | 0;
      const s: number = MD5_SHIFTS[i];
      const rot: number = (x << s) | (x >>> (32 - s));
      b = (b + rot) | 0;
      a = d;
      c = nextC;
      d = nextD;
    }

    this.a0 = (this.a0 + a) | 0;
    this.b0 = (this.b0 + b) | 0;
    this.c0 = (this.c0 + c) | 0;
    this.d0 = (this.d0 + d) | 0;
  }

  private static writeLe32(dst: Uint8Array, off: number, val: number): void {
    dst[off] = val & 0xFF;
    dst[off + 1] = (val >>> 8) & 0xFF;
    dst[off + 2] = (val >>> 16) & 0xFF;
    dst[off + 3] = (val >>> 24) & 0xFF;
  }
}

// ── String resource formatter ───────────────────────────────────────────────

export class LanTextFormatter {
  /**
   * Formats `%1$s`, `%1$d`, `%1s`, `%1d`, `%s`, `%d` placeholders from `strings.json`.
   */
  static format(template: string, args: Array<string | number>): string {
    if (args.length === 0) {
      return template;
    }
    let out: string = template;
    for (let i = 0; i < args.length; i++) {
      const val: string = `${args[i]}`;
      const pos: number = i + 1;
      const tokens: string[] = [`%${pos}$s`, `%${pos}$d`, `%${pos}s`, `%${pos}d`];
      let replaced: boolean = false;
      for (let t = 0; t < tokens.length; t++) {
        const tok: string = tokens[t];
        if (out.indexOf(tok) >= 0) {
          out = out.split(tok).join(val);
          replaced = true;
          break;
        }
      }
      if (replaced) {
        continue;
      }
      const sIdx: number = out.indexOf('%s');
      const dIdx: number = out.indexOf('%d');
      if (sIdx >= 0 && (dIdx < 0 || sIdx < dIdx)) {
        out = out.substring(0, sIdx) + val + out.substring(sIdx + 2);
      } else if (dIdx >= 0) {
        out = out.substring(0, dIdx) + val + out.substring(dIdx + 2);
      }
    }
    return out;
  }
}

// ── LAN Endpoint & QR Payload Codec ─────────────────────────────────────────

export class LanEndpoint {
  readonly host: string;
  readonly port: number;
  readonly baseUrl: string;

  constructor(host: string, port: number) {
    this.host = host;
    this.port = port;
    this.baseUrl = `http://${host}:${port}`;
  }
}

export class LanEndpointCodec {
  static readonly DEFAULT_PORT: number = WiFiServerActivity.PORT;
  static readonly PROTOCOL_ID: string = 'ehviewer-lan-http/1';
  static readonly MODE_D002: string = 'lan-http-d002';

  static isValidIpv4(ip: string): boolean {
    const trimmed: string = ip.trim();
    const parts: string[] = trimmed.split('.');
    if (parts.length !== 4) {
      return false;
    }
    for (let i = 0; i < 4; i++) {
      const seg: string = parts[i];
      if (!/^\d{1,3}$/.test(seg)) {
        return false;
      }
      if (seg.length > 1 && seg.charAt(0) === '0') {
        return false;
      }
      const n: number = Number.parseInt(seg, 10);
      if (Number.isNaN(n) || n < 0 || n > 255) {
        return false;
      }
    }
    return true;
  }

  static isPrivateLanIpv4(ip: string): boolean {
    if (!LanEndpointCodec.isValidIpv4(ip)) {
      return false;
    }
    const parts: string[] = ip.split('.');
    const a: number = Number.parseInt(parts[0], 10);
    const b: number = Number.parseInt(parts[1], 10);
    if (a === 10) {
      return true;
    }
    if (a === 192 && b === 168) {
      return true;
    }
    if (a === 172 && b >= 16 && b <= 31) {
      return true;
    }
    if (a === 169 && b === 254) {
      return true;
    }
    if (a === 100 && b >= 64 && b <= 127) {
      return true;
    }
    return false;
  }

  static isValidPort(port: number): boolean {
    return Number.isInteger(port) && port >= 1 && port <= 65535;
  }

  static intToIpBigEndian(ipInt: number): string {
    const b0: number = (ipInt >>> 24) & 0xFF;
    const b1: number = (ipInt >>> 16) & 0xFF;
    const b2: number = (ipInt >>> 8) & 0xFF;
    const b3: number = ipInt & 0xFF;
    return `${b0}.${b1}.${b2}.${b3}`;
  }

  static intToIpLittleEndian(ipInt: number): string {
    return WiFiClientActivity.intToIp(ipInt);
  }

  /**
   * Decodes a 32-bit IPv4 integer returned by platform Wi-Fi APIs.
   * OpenHarmony `wifiManager.getIpInfo().ipAddress` uses big-endian (host byte order),
   * whereas Android `WifiInfo.getIpAddress()` uses little-endian (`WiFiClientActivity.intToIp`).
   */
  static decodeWifiIpInt(ipInt: number): string | null {
    if (!Number.isFinite(ipInt) || ipInt === 0) {
      return null;
    }
    const big: string = LanEndpointCodec.intToIpBigEndian(ipInt);
    const little: string = LanEndpointCodec.intToIpLittleEndian(ipInt);
    if (LanEndpointCodec.isPrivateLanIpv4(big)) {
      return big;
    }
    if (LanEndpointCodec.isPrivateLanIpv4(little)) {
      return little;
    }
    if (LanEndpointCodec.isValidIpv4(big) && !big.startsWith('0.') && !big.startsWith('127.')) {
      return big;
    }
    if (LanEndpointCodec.isValidIpv4(little) && !little.startsWith('0.') && !little.startsWith('127.')) {
      return little;
    }
    return null;
  }

  static buildServerUrl(ip: string, port: number = LanEndpointCodec.DEFAULT_PORT): string {
    return `http://${ip.trim()}:${port}`;
  }

  static buildQrPayload(ip: string, port: number = LanEndpointCodec.DEFAULT_PORT): string {
    return LanEndpointCodec.buildServerUrl(ip, port);
  }

  /**
   * Normalizes user-typed or QR-pasted endpoints into `LanEndpoint`:
   *   - `http://192.168.1.5:54321`
   *   - `http://192.168.1.5:54321/api/info`
   *   - `http://192.168.1.5`
   *   - `192.168.1.5:54321`
   *   - `192.168.1.5`
   *   - `{"url":"http://192.168.1.5:54321"}` or `{"ip":"192.168.1.5","port":54321}`
   */
  static parseEndpoint(rawInput: string, defaultPort: number = LanEndpointCodec.DEFAULT_PORT): LanEndpoint | null {
    const trimmed: string = rawInput.trim();
    if (trimmed.length === 0) {
      return null;
    }
    if (trimmed.startsWith('{') && trimmed.endsWith('}')) {
      return LanEndpointCodec.parseJsonEndpoint(trimmed, defaultPort);
    }

    let rest: string = trimmed;
    const schemeIdx: number = rest.indexOf('://');
    if (schemeIdx >= 0) {
      const scheme: string = rest.substring(0, schemeIdx).toLowerCase();
      if (scheme !== 'http') {
        return null;
      }
      rest = rest.substring(schemeIdx + 3);
    }

    // Strip path / query / fragment
    const cutSlash: number = rest.indexOf('/');
    if (cutSlash >= 0) {
      rest = rest.substring(0, cutSlash);
    }
    const cutQuery: number = rest.indexOf('?');
    if (cutQuery >= 0) {
      rest = rest.substring(0, cutQuery);
    }
    const cutHash: number = rest.indexOf('#');
    if (cutHash >= 0) {
      rest = rest.substring(0, cutHash);
    }
    rest = rest.trim();
    if (rest.length === 0) {
      return null;
    }

    // Reject userinfo or whitespace
    if (rest.indexOf('@') >= 0 || /\s/.test(rest)) {
      return null;
    }

    let host: string = rest;
    let port: number = defaultPort;
    const colonIdx: number = rest.indexOf(':');
    if (colonIdx >= 0) {
      // Reject multiple colons (e.g. raw IPv6 without brackets or bad syntax)
      if (rest.indexOf(':', colonIdx + 1) >= 0) {
        return null;
      }
      host = rest.substring(0, colonIdx).trim();
      const portStr: string = rest.substring(colonIdx + 1).trim();
      if (!/^\d{1,5}$/.test(portStr)) {
        return null;
      }
      port = Number.parseInt(portStr, 10);
    }

    if (!LanEndpointCodec.isValidPort(port)) {
      return null;
    }
    if (!LanEndpointCodec.isConnectableHost(host)) {
      return null;
    }
    return new LanEndpoint(host, port);
  }

  private static parseJsonEndpoint(text: string, defaultPort: number): LanEndpoint | null {
    try {
      const obj: JsonObject = JsonObject.parse(text);
      if (obj.has('url') && !obj.isNull('url')) {
        return LanEndpointCodec.parseEndpoint(obj.getString('url'), defaultPort);
      }
      const host: string = obj.optString('ip', obj.optString('host', ''));
      if (host.length === 0) {
        return null;
      }
      const port: number = obj.has('port') && !obj.isNull('port') ? obj.getInt('port') : defaultPort;
      if (!LanEndpointCodec.isValidPort(port) || !LanEndpointCodec.isConnectableHost(host)) {
        return null;
      }
      return new LanEndpoint(host.trim(), port);
    } catch (err) {
      const msg: string = err instanceof Error ? err.message : String(err);
      hilog.warn(LOG_DOMAIN, LOG_TAG, 'parseJsonEndpoint failed: %{public}s', msg);
      return null;
    }
  }

  private static isConnectableHost(host: string): boolean {
    if (host.length === 0 || host === '0.0.0.0') {
      return false;
    }
    if (LanEndpointCodec.isValidIpv4(host)) {
      return true;
    }
    if (host.toLowerCase() === 'localhost') {
      return true;
    }
    // Reject all-numeric dotted strings that failed IPv4 validation (e.g. 999.1.2.3 or 1.2.3)
    if (/^[\d.]+$/.test(host)) {
      return false;
    }
    // Local hostname (mDNS .local or LAN hostname)
    return /^[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(?:\.[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)*$/.test(host);
  }
}

// ── HTTP/1.1 Request / Response / Framing Codec ─────────────────────────────

export class LanHttpRequest {
  readonly method: string;
  readonly rawTarget: string;
  readonly path: string;
  readonly query: Map<string, string>;
  readonly headers: Map<string, string>;
  readonly body: ArrayBuffer;

  constructor(
    method: string,
    rawTarget: string,
    path: string,
    query: Map<string, string>,
    headers: Map<string, string>,
    body: ArrayBuffer
  ) {
    this.method = method;
    this.rawTarget = rawTarget;
    this.path = path;
    this.query = query;
    this.headers = headers;
    this.body = body;
  }

  getQuery(name: string): string | null {
    const v: string | undefined = this.query.get(name);
    return v === undefined ? null : v;
  }

  getHeader(name: string): string | null {
    const v: string | undefined = this.headers.get(name.toLowerCase());
    return v === undefined ? null : v;
  }

  bodyText(): string {
    return LanUtf8.decodeBuffer(this.body);
  }
}

export class LanHttpResponse {
  readonly statusCode: number;
  readonly reasonPhrase: string;
  readonly headers: Map<string, string>;
  readonly body: ArrayBuffer;

  constructor(statusCode: number, reasonPhrase: string, headers: Map<string, string>, body: ArrayBuffer) {
    this.statusCode = statusCode;
    this.reasonPhrase = reasonPhrase;
    this.headers = headers;
    this.body = body;
  }

  static json(statusCode: number, jsonText: string): LanHttpResponse {
    const headers: Map<string, string> = new Map<string, string>();
    headers.set('Content-Type', 'application/json; charset=utf-8');
    return new LanHttpResponse(
      statusCode,
      LanHttpCodec.reasonPhrase(statusCode),
      headers,
      LanUtf8.encodeToBuffer(jsonText)
    );
  }

  static binary(statusCode: number, data: ArrayBuffer, extraHeaders?: Map<string, string>): LanHttpResponse {
    const headers: Map<string, string> = new Map<string, string>();
    headers.set('Content-Type', 'application/octet-stream');
    if (extraHeaders !== undefined) {
      extraHeaders.forEach((v: string, k: string): void => {
        headers.set(k, v);
      });
    }
    return new LanHttpResponse(statusCode, LanHttpCodec.reasonPhrase(statusCode), headers, data);
  }

  static error(statusCode: number, message: string): LanHttpResponse {
    const json: string = `{"ok":false,"error":${JSON.stringify(message)},"status":${statusCode}}`;
    return LanHttpResponse.json(statusCode, json);
  }

  getHeader(name: string): string | null {
    const target: string = name.toLowerCase();
    let found: string | null = null;
    this.headers.forEach((v: string, k: string): void => {
      if (k.toLowerCase() === target) {
        found = v;
      }
    });
    return found;
  }

  bodyText(): string {
    return LanUtf8.decodeBuffer(this.body);
  }
}

export class ParsedRequestHead {
  readonly method: string;
  readonly rawTarget: string;
  readonly path: string;
  readonly query: Map<string, string>;
  readonly headers: Map<string, string>;
  readonly contentLength: number;

  constructor(
    method: string,
    rawTarget: string,
    path: string,
    query: Map<string, string>,
    headers: Map<string, string>,
    contentLength: number
  ) {
    this.method = method;
    this.rawTarget = rawTarget;
    this.path = path;
    this.query = query;
    this.headers = headers;
    this.contentLength = contentLength;
  }
}

export enum LanHttpFeedStatus {
  INCOMPLETE = 0,
  COMPLETE = 1,
  ERROR = 2
}

export class LanHttpFeedResult {
  readonly status: LanHttpFeedStatus;
  readonly request: LanHttpRequest | null;
  readonly errorCode: number;
  readonly errorMessage: string;

  constructor(
    status: LanHttpFeedStatus,
    request: LanHttpRequest | null,
    errorCode: number,
    errorMessage: string
  ) {
    this.status = status;
    this.request = request;
    this.errorCode = errorCode;
    this.errorMessage = errorMessage;
  }

  static incomplete(): LanHttpFeedResult {
    return new LanHttpFeedResult(LanHttpFeedStatus.INCOMPLETE, null, 0, '');
  }

  static complete(req: LanHttpRequest): LanHttpFeedResult {
    return new LanHttpFeedResult(LanHttpFeedStatus.COMPLETE, req, 0, '');
  }

  static error(code: number, msg: string): LanHttpFeedResult {
    return new LanHttpFeedResult(LanHttpFeedStatus.ERROR, null, code, msg);
  }
}

export class LanHttpCodec {
  static reasonPhrase(code: number): string {
    switch (code) {
      case 200:
        return 'OK';
      case 400:
        return 'Bad Request';
      case 404:
        return 'Not Found';
      case 405:
        return 'Method Not Allowed';
      case 413:
        return 'Payload Too Large';
      case 500:
        return 'Internal Server Error';
      case 503:
        return 'Service Unavailable';
      default:
        return 'Unknown';
    }
  }

  static decodeComponentSafe(raw: string): string {
    const plusToSpace: string = raw.split('+').join(' ');
    try {
      return decodeURIComponent(plusToSpace);
    } catch (err) {
      const msg: string = err instanceof Error ? err.message : String(err);
      hilog.warn(LOG_DOMAIN, LOG_TAG, 'decodeURIComponent failed for %{public}s: %{public}s', raw, msg);
      return plusToSpace;
    }
  }

  static parseQueryString(query: string): Map<string, string> {
    const out: Map<string, string> = new Map<string, string>();
    if (query.length === 0) {
      return out;
    }
    const pairs: string[] = query.split('&');
    for (let i = 0; i < pairs.length; i++) {
      const pair: string = pairs[i];
      if (pair.length === 0) {
        continue;
      }
      const eqIdx: number = pair.indexOf('=');
      if (eqIdx < 0) {
        out.set(LanHttpCodec.decodeComponentSafe(pair), '');
      } else {
        const key: string = LanHttpCodec.decodeComponentSafe(pair.substring(0, eqIdx));
        const val: string = LanHttpCodec.decodeComponentSafe(pair.substring(eqIdx + 1));
        out.set(key, val);
      }
    }
    return out;
  }

  static parseRequestHead(headerText: string): ParsedRequestHead {
    const lines: string[] = headerText.split('\r\n');
    if (lines.length === 0 || lines[0].length === 0) {
      throw new Error('Empty HTTP request line');
    }
    const reqLine: string = lines[0];
    const parts: string[] = reqLine.split(' ');
    if (parts.length !== 3) {
      throw new Error(`Malformed request line: ${reqLine}`);
    }
    const method: string = parts[0].trim().toUpperCase();
    const rawTarget: string = parts[1].trim();
    const version: string = parts[2].trim();
    if (!/^[A-Z]+$/.test(method) || !rawTarget.startsWith('/') || !/^HTTP\/1\.[01]$/.test(version)) {
      throw new Error(`Unsupported HTTP request line: ${reqLine}`);
    }

    const qIdx: number = rawTarget.indexOf('?');
    const rawPath: string = qIdx >= 0 ? rawTarget.substring(0, qIdx) : rawTarget;
    const rawQuery: string = qIdx >= 0 ? rawTarget.substring(qIdx + 1) : '';
    const path: string = LanHttpCodec.decodeComponentSafe(rawPath);
    const query: Map<string, string> = LanHttpCodec.parseQueryString(rawQuery);

    const headers: Map<string, string> = new Map<string, string>();
    for (let i = 1; i < lines.length; i++) {
      const line: string = lines[i];
      if (line.length === 0) {
        continue;
      }
      const colon: number = line.indexOf(':');
      if (colon <= 0) {
        throw new Error(`Malformed header line: ${line}`);
      }
      const key: string = line.substring(0, colon).trim().toLowerCase();
      const val: string = line.substring(colon + 1).trim();
      headers.set(key, val);
    }

    let contentLength: number = 0;
    const clHeader: string | undefined = headers.get('content-length');
    if (clHeader !== undefined) {
      if (!/^\d+$/.test(clHeader)) {
        throw new Error(`Invalid Content-Length: ${clHeader}`);
      }
      contentLength = Number.parseInt(clHeader, 10);
      if (!Number.isSafeInteger(contentLength) || contentLength < 0) {
        throw new Error(`Invalid Content-Length: ${clHeader}`);
      }
    }

    return new ParsedRequestHead(method, rawTarget, path, query, headers, contentLength);
  }

  static serializeResponse(resp: LanHttpResponse): ArrayBuffer {
    const lines: string[] = [];
    lines.push(`HTTP/1.1 ${resp.statusCode} ${resp.reasonPhrase}\r\n`);
    let hasContentLength: boolean = false;
    let hasConnection: boolean = false;
    resp.headers.forEach((value: string, key: string): void => {
      const lower: string = key.toLowerCase();
      if (lower === 'content-length') {
        hasContentLength = true;
      } else if (lower === 'connection') {
        hasConnection = true;
      }
      lines.push(`${key}: ${value}\r\n`);
    });
    if (!hasContentLength) {
      lines.push(`Content-Length: ${resp.body.byteLength}\r\n`);
    }
    if (!hasConnection) {
      lines.push('Connection: close\r\n');
    }
    lines.push('\r\n');

    const headBytes: Uint8Array = LanUtf8.encode(lines.join(''));
    const bodyBytes: Uint8Array = new Uint8Array(resp.body);
    const wire: Uint8Array = new Uint8Array(headBytes.byteLength + bodyBytes.byteLength);
    wire.set(headBytes, 0);
    if (bodyBytes.byteLength > 0) {
      wire.set(bodyBytes, headBytes.byteLength);
    }
    return wire.buffer as ArrayBuffer;
  }

  static serializeRequest(
    method: string,
    target: string,
    host: string,
    body?: ArrayBuffer,
    headers?: Map<string, string>
  ): ArrayBuffer {
    const bodyBytes: Uint8Array = body !== undefined ? new Uint8Array(body) : new Uint8Array(0);
    const lines: string[] = [];
    lines.push(`${method.toUpperCase()} ${target} HTTP/1.1\r\n`);
    lines.push(`Host: ${host}\r\n`);
    lines.push('Connection: close\r\n');
    if (headers !== undefined) {
      headers.forEach((v: string, k: string): void => {
        const lower: string = k.toLowerCase();
        if (lower !== 'host' && lower !== 'content-length' && lower !== 'connection') {
          lines.push(`${k}: ${v}\r\n`);
        }
      });
    }
    if (bodyBytes.byteLength > 0) {
      lines.push(`Content-Length: ${bodyBytes.byteLength}\r\n`);
    }
    lines.push('\r\n');

    const headBytes: Uint8Array = LanUtf8.encode(lines.join(''));
    const wire: Uint8Array = new Uint8Array(headBytes.byteLength + bodyBytes.byteLength);
    wire.set(headBytes, 0);
    if (bodyBytes.byteLength > 0) {
      wire.set(bodyBytes, headBytes.byteLength);
    }
    return wire.buffer as ArrayBuffer;
  }

  static parseResponse(rawWire: ArrayBuffer): LanHttpResponse {
    const bytes: Uint8Array = new Uint8Array(rawWire);
    const sepIdx: number = LanHttpCodec.indexOfCrlfCrlf(bytes);
    if (sepIdx < 0) {
      throw new Error('Incomplete HTTP response headers');
    }
    const headText: string = LanUtf8.decode(bytes, 0, sepIdx);
    const lines: string[] = headText.split('\r\n');
    if (lines.length === 0) {
      throw new Error('Empty HTTP response');
    }
    const m: RegExpMatchArray | null = lines[0].match(/^HTTP\/1\.[01]\s+(\d{3})(?:\s+(.*))?$/);
    if (m === null) {
      throw new Error(`Malformed HTTP response status line: ${lines[0]}`);
    }
    const code: number = Number.parseInt(m[1], 10);
    const reason: string = m[2] !== undefined ? m[2] : LanHttpCodec.reasonPhrase(code);
    const headers: Map<string, string> = new Map<string, string>();
    for (let i = 1; i < lines.length; i++) {
      const line: string = lines[i];
      if (line.length === 0) {
        continue;
      }
      const colon: number = line.indexOf(':');
      if (colon <= 0) {
        continue;
      }
      headers.set(line.substring(0, colon).trim(), line.substring(colon + 1).trim());
    }
    const bodyStart: number = sepIdx + 4;
    const bodySlice: Uint8Array = bytes.subarray(bodyStart);
    return new LanHttpResponse(code, reason, headers, LanUtf8.toArrayBuffer(bodySlice));
  }

  static indexOfCrlfCrlf(bytes: Uint8Array): number {
    for (let i = 0; i <= bytes.byteLength - 4; i++) {
      if (bytes[i] === 13 && bytes[i + 1] === 10 && bytes[i + 2] === 13 && bytes[i + 3] === 10) {
        return i;
      }
    }
    return -1;
  }

  /** Rejects absolute paths, backslashes, NUL bytes, and `.` / `..` segments (including encoded `..`). */
  static isSafeRelPath(relPath: string): boolean {
    if (relPath.length === 0 || relPath.indexOf('\0') >= 0 || relPath.indexOf('\\') >= 0) {
      return false;
    }
    if (relPath.startsWith('/') || relPath.endsWith('/')) {
      return false;
    }
    const decoded: string = LanHttpCodec.decodeComponentSafe(relPath);
    if (decoded.indexOf('\0') >= 0 || decoded.indexOf('\\') >= 0 || decoded.startsWith('/')) {
      return false;
    }
    const checks: string[] = [relPath, decoded];
    for (let c = 0; c < checks.length; c++) {
      const segs: string[] = checks[c].split('/');
      for (let i = 0; i < segs.length; i++) {
        const s: string = segs[i];
        if (s.length === 0 || s === '.' || s === '..') {
          return false;
        }
      }
    }
    return true;
  }

  /** Rejects path separators and traversal segments in a gallery directory name. */
  static isSafeDirName(dirname: string): boolean {
    if (dirname.length === 0 || dirname === '.' || dirname === '..') {
      return false;
    }
    if (dirname.indexOf('/') >= 0 || dirname.indexOf('\\') >= 0 || dirname.indexOf('\0') >= 0) {
      return false;
    }
    const decoded: string = LanHttpCodec.decodeComponentSafe(dirname);
    if (decoded === '.' || decoded === '..' || decoded.indexOf('/') >= 0 ||
      decoded.indexOf('\\') >= 0 || decoded.indexOf('\0') >= 0 || decoded.indexOf('..') >= 0) {
      return false;
    }
    return true;
  }
}

/**
 * Incremental HTTP/1.1 request framing buffer for raw TCP stream chunks.
 */
export class LanHttpRequestBuffer {
  static readonly MAX_HEADER_BYTES: number = 16 * 1024;
  static readonly MAX_BODY_BYTES: number = 4 * 1024 * 1024;

  private readonly chunks: Uint8Array[] = [];
  private bufferedLen: number = 0;
  private parsedHead: ParsedRequestHead | null = null;
  private bodyOffset: number = 0;

  feed(chunk: Uint8Array): LanHttpFeedResult {
    if (chunk.byteLength > 0) {
      this.chunks.push(chunk);
      this.bufferedLen += chunk.byteLength;
    }

    if (this.parsedHead === null) {
      const merged: Uint8Array = this.flatten();
      const sepIdx: number = LanHttpCodec.indexOfCrlfCrlf(merged);
      if (sepIdx < 0) {
        if (merged.byteLength > LanHttpRequestBuffer.MAX_HEADER_BYTES) {
          return LanHttpFeedResult.error(413, 'HTTP request header too large');
        }
        return LanHttpFeedResult.incomplete();
      }
      if (sepIdx > LanHttpRequestBuffer.MAX_HEADER_BYTES) {
        return LanHttpFeedResult.error(413, 'HTTP request header too large');
      }
      const headText: string = LanUtf8.decode(merged, 0, sepIdx);
      try {
        const head: ParsedRequestHead = LanHttpCodec.parseRequestHead(headText);
        if (head.contentLength > LanHttpRequestBuffer.MAX_BODY_BYTES) {
          return LanHttpFeedResult.error(413, 'HTTP request body too large');
        }
        this.parsedHead = head;
        this.bodyOffset = sepIdx + 4;
      } catch (err) {
        const msg: string = err instanceof Error ? err.message : String(err);
        hilog.warn(LOG_DOMAIN, LOG_TAG, 'parseRequestHead rejected request: %{public}s', msg);
        return LanHttpFeedResult.error(400, msg);
      }
    }

    const head: ParsedRequestHead = this.parsedHead as ParsedRequestHead;
    const needed: number = this.bodyOffset + head.contentLength;
    if (this.bufferedLen < needed) {
      return LanHttpFeedResult.incomplete();
    }

    const merged: Uint8Array = this.flatten();
    const bodySlice: Uint8Array = merged.subarray(this.bodyOffset, needed);
    const req: LanHttpRequest = new LanHttpRequest(
      head.method,
      head.rawTarget,
      head.path,
      head.query,
      head.headers,
      LanUtf8.toArrayBuffer(bodySlice)
    );
    return LanHttpFeedResult.complete(req);
  }

  private flatten(): Uint8Array {
    if (this.chunks.length === 0) {
      return new Uint8Array(0);
    }
    if (this.chunks.length === 1) {
      return this.chunks[0];
    }
    const merged: Uint8Array = new Uint8Array(this.bufferedLen);
    let off: number = 0;
    for (let i = 0; i < this.chunks.length; i++) {
      merged.set(this.chunks[i], off);
      off += this.chunks[i].byteLength;
    }
    this.chunks.length = 0;
    this.chunks.push(merged);
    return merged;
  }
}

// ── Route definitions & DTOs ────────────────────────────────────────────────

export class LanHttpRoutes {
  static readonly PING: string = '/api/ping';
  static readonly INFO: string = '/api/info';
  static readonly BOOKMARKS: string = '/api/bookmarks';
  static readonly FAVORITES: string = '/api/favorites';
  static readonly DOWNLOADS: string = '/api/downloads';
  static readonly DIRS: string = '/api/dirs';
  static readonly DIR_MANIFEST: string = '/api/dir/manifest';
  static readonly DIR_FILE: string = '/api/dir/file';
}

export class LanServerInfo {
  protocol: string = LanEndpointCodec.PROTOCOL_ID;
  mode: string = LanEndpointCodec.MODE_D002;
  appVersion: string = '2.0.2.6';
  deviceName: string = 'EhViewer-Harmony';
  bookmarkCount: number = 0;
  favoriteCount: number = 0;
  downloadCount: number = 0;
  downloadLabelCount: number = 0;
  downloadDirCount: number = 0;
  hasDownloadRoot: boolean = false;
  enabledCategories: number[] = [
    WiFiServerMenu.BOOKMARK,
    WiFiServerMenu.FAVORITE,
    WiFiServerMenu.DOWNLOAD,
    WiFiServerMenu.DOWNLOAD_DIR
  ];

  toJson(): string {
    return `{"protocol":${JSON.stringify(this.protocol)},` +
      `"mode":${JSON.stringify(this.mode)},` +
      `"appVersion":${JSON.stringify(this.appVersion)},` +
      `"deviceName":${JSON.stringify(this.deviceName)},` +
      `"bookmarkCount":${this.bookmarkCount},` +
      `"favoriteCount":${this.favoriteCount},` +
      `"downloadCount":${this.downloadCount},` +
      `"downloadLabelCount":${this.downloadLabelCount},` +
      `"downloadDirCount":${this.downloadDirCount},` +
      `"hasDownloadRoot":${this.hasDownloadRoot},` +
      `"enabledCategories":[${this.enabledCategories.join(',')}]}`;
  }

  static fromJson(text: string): LanServerInfo {
    const obj: JsonObject = JsonObject.parse(text);
    const info: LanServerInfo = new LanServerInfo();
    info.protocol = obj.optString('protocol', LanEndpointCodec.PROTOCOL_ID);
    info.mode = obj.optString('mode', LanEndpointCodec.MODE_D002);
    info.appVersion = obj.optString('appVersion', '2.0.2.6');
    info.deviceName = obj.optString('deviceName', 'EhViewer-Harmony');
    info.bookmarkCount = obj.has('bookmarkCount') && !obj.isNull('bookmarkCount') ? obj.getInt('bookmarkCount') : 0;
    info.favoriteCount = obj.has('favoriteCount') && !obj.isNull('favoriteCount') ? obj.getInt('favoriteCount') : 0;
    info.downloadCount = obj.has('downloadCount') && !obj.isNull('downloadCount') ? obj.getInt('downloadCount') : 0;
    info.downloadLabelCount =
      obj.has('downloadLabelCount') && !obj.isNull('downloadLabelCount') ? obj.getInt('downloadLabelCount') : 0;
    info.downloadDirCount =
      obj.has('downloadDirCount') && !obj.isNull('downloadDirCount') ? obj.getInt('downloadDirCount') : 0;
    if (obj.has('hasDownloadRoot') && !obj.isNull('hasDownloadRoot')) {
      info.hasDownloadRoot = obj.getString('hasDownloadRoot').toLowerCase() === 'true';
    }
    if (obj.has('enabledCategories') && !obj.isNull('enabledCategories')) {
      const arr: JsonArray = obj.getJSONArray('enabledCategories');
      const cats: number[] = [];
      for (let i = 0; i < arr.length(); i++) {
        const parsed: number = Number.parseInt(arr.getString(i), 10);
        if (!Number.isNaN(parsed)) {
          cats.push(parsed);
        }
      }
      info.enabledCategories = cats;
    }
    return info;
  }
}

export interface LanServerDataProvider {
  getAppVersion(): string;
  getDeviceName(): string;
  getQuickSearches(): Promise<QuickSearch[]>;
  getLocalFavorites(): Promise<GalleryInfo[]>;
  getDownloadLabels(): Promise<DownloadLabel[]>;
  getDownloadInfos(): Promise<DownloadInfo[]>;
  getDownloadRoot(): string | null;
}

export class LanTransferEvent {
  readonly kind: string;
  readonly path: string;
  readonly detail: string;
  readonly bytes: number;
  readonly statusCode: number;
  readonly timestamp: number;

  constructor(kind: string, path: string, detail: string, bytes: number, statusCode: number) {
    this.kind = kind;
    this.path = path;
    this.detail = detail;
    this.bytes = bytes;
    this.statusCode = statusCode;
    this.timestamp = Date.now();
  }
}

// ── Server HTTP Transfer Router ─────────────────────────────────────────────

export class LanHttpTransferRouter {
  private readonly provider: LanServerDataProvider;
  private readonly fs: MigrationFileSystem;
  private readonly chunkSource: FileChunkSource;
  private readonly onEvent: ((ev: LanTransferEvent) => void) | null;
  private serving: boolean = true;
  private readonly enabledCategories: Set<number> = new Set<number>([
    WiFiServerMenu.BOOKMARK,
    WiFiServerMenu.FAVORITE,
    WiFiServerMenu.DOWNLOAD,
    WiFiServerMenu.DOWNLOAD_DIR
  ]);

  constructor(
    provider: LanServerDataProvider,
    fs: MigrationFileSystem,
    chunkSource: FileChunkSource,
    onEvent?: (ev: LanTransferEvent) => void
  ) {
    this.provider = provider;
    this.fs = fs;
    this.chunkSource = chunkSource;
    this.onEvent = onEvent !== undefined ? onEvent : null;
  }

  setServing(serving: boolean): void {
    this.serving = serving;
  }

  isServing(): boolean {
    return this.serving;
  }

  setCategoryEnabled(menu: WiFiServerMenu, enabled: boolean): void {
    if (enabled) {
      this.enabledCategories.add(menu);
    } else {
      this.enabledCategories.delete(menu);
    }
  }

  isCategoryEnabled(menu: WiFiServerMenu): boolean {
    return this.enabledCategories.has(menu);
  }

  private getEnabledCategoryList(): number[] {
    const out: number[] = [];
    const all: number[] = [
      WiFiServerMenu.BOOKMARK,
      WiFiServerMenu.FAVORITE,
      WiFiServerMenu.DOWNLOAD,
      WiFiServerMenu.DOWNLOAD_DIR
    ];
    for (let i = 0; i < all.length; i++) {
      if (this.enabledCategories.has(all[i])) {
        out.push(all[i]);
      }
    }
    return out;
  }

  async handleRequest(req: LanHttpRequest): Promise<LanHttpResponse> {
    if (req.method !== 'GET') {
      const resp: LanHttpResponse = LanHttpResponse.error(405, `Method not allowed: ${req.method}`);
      this.emit('error', req.path, resp.reasonPhrase, 0, 405);
      return resp;
    }

    if (req.path === LanHttpRoutes.PING) {
      const body: string = `{"ok":true,"protocol":${JSON.stringify(LanEndpointCodec.PROTOCOL_ID)},` +
        `"mode":${JSON.stringify(LanEndpointCodec.MODE_D002)},"serving":${this.serving}}`;
      const resp: LanHttpResponse = LanHttpResponse.json(200, body);
      this.emit('ping', req.path, 'ping', resp.body.byteLength, 200);
      return resp;
    }

    if (!this.serving) {
      const resp: LanHttpResponse = LanHttpResponse.error(503, 'Server paused');
      this.emit('error', req.path, 'paused', 0, 503);
      return resp;
    }

    try {
      switch (req.path) {
        case LanHttpRoutes.INFO:
          return await this.handleInfo(req);
        case LanHttpRoutes.BOOKMARKS:
          return await this.handleBookmarks(req);
        case LanHttpRoutes.FAVORITES:
          return await this.handleFavorites(req);
        case LanHttpRoutes.DOWNLOADS:
          return await this.handleDownloads(req);
        case LanHttpRoutes.DIRS:
          return this.handleDirs(req);
        case LanHttpRoutes.DIR_MANIFEST:
          return this.handleDirManifest(req);
        case LanHttpRoutes.DIR_FILE:
          return this.handleDirFile(req);
        default: {
          const resp: LanHttpResponse = LanHttpResponse.error(404, `Route not found: ${req.path}`);
          this.emit('error', req.path, 'not found', 0, 404);
          return resp;
        }
      }
    } catch (err) {
      const msg: string = err instanceof Error ? err.message : String(err);
      hilog.error(LOG_DOMAIN, LOG_TAG, 'Router error on %{public}s: %{public}s', req.path, msg);
      const resp: LanHttpResponse = LanHttpResponse.error(500, msg);
      this.emit('error', req.path, msg, 0, 500);
      return resp;
    }
  }

  private async handleInfo(req: LanHttpRequest): Promise<LanHttpResponse> {
    const bookmarks: QuickSearch[] = await this.provider.getQuickSearches();
    const favorites: GalleryInfo[] = await this.provider.getLocalFavorites();
    const labels: DownloadLabel[] = await this.provider.getDownloadLabels();
    const downloads: DownloadInfo[] = await this.provider.getDownloadInfos();
    const root: string | null = this.provider.getDownloadRoot();
    const dirs: GalleryDirEntry[] = root !== null ? WiFiDownloadMigrationHelper.scanGalleryDirs(this.fs, root) : [];

    const info: LanServerInfo = new LanServerInfo();
    info.appVersion = this.provider.getAppVersion();
    info.deviceName = this.provider.getDeviceName();
    info.bookmarkCount = bookmarks.length;
    info.favoriteCount = favorites.length;
    info.downloadLabelCount = labels.length;
    info.downloadCount = downloads.length;
    info.downloadDirCount = dirs.length;
    info.hasDownloadRoot = root !== null;
    info.enabledCategories = this.getEnabledCategoryList();

    const resp: LanHttpResponse = LanHttpResponse.json(200, info.toJson());
    this.emit('info', req.path, `${dirs.length}`, resp.body.byteLength, 200);
    return resp;
  }

  private async handleBookmarks(req: LanHttpRequest): Promise<LanHttpResponse> {
    if (!this.enabledCategories.has(WiFiServerMenu.BOOKMARK)) {
      return LanHttpResponse.error(503, 'Bookmarks category disabled');
    }
    const list: QuickSearch[] = await this.provider.getQuickSearches();
    const items: string[] = [];
    for (let i = 0; i < list.length; i++) {
      items.push(WiFiServerActivity.quickSearchToJson(list[i]));
    }
    const json: string = `{"count":${items.length},"items":[${items.join(',')}]}`;
    const resp: LanHttpResponse = LanHttpResponse.json(200, json);
    this.emit('bookmarks', req.path, `${items.length}`, resp.body.byteLength, 200);
    return resp;
  }

  private async handleFavorites(req: LanHttpRequest): Promise<LanHttpResponse> {
    if (!this.enabledCategories.has(WiFiServerMenu.FAVORITE)) {
      return LanHttpResponse.error(503, 'Favorites category disabled');
    }
    const list: GalleryInfo[] = await this.provider.getLocalFavorites();
    const items: string[] = [];
    for (let i = 0; i < list.length; i++) {
      items.push(list[i].toJson());
    }
    const json: string = `{"count":${items.length},"items":[${items.join(',')}]}`;
    const resp: LanHttpResponse = LanHttpResponse.json(200, json);
    this.emit('favorites', req.path, `${items.length}`, resp.body.byteLength, 200);
    return resp;
  }

  private async handleDownloads(req: LanHttpRequest): Promise<LanHttpResponse> {
    if (!this.enabledCategories.has(WiFiServerMenu.DOWNLOAD)) {
      return LanHttpResponse.error(503, 'Downloads category disabled');
    }
    const labels: DownloadLabel[] = await this.provider.getDownloadLabels();
    const infos: DownloadInfo[] = await this.provider.getDownloadInfos();
    const labelStrs: string[] = [];
    for (let i = 0; i < labels.length; i++) {
      const label: string | null = labels[i].getLabel();
      labelStrs.push(label === null ? '' : label);
    }
    const infoJsons: string[] = [];
    for (let i = 0; i < infos.length; i++) {
      infoJsons.push(infos[i].toJson());
    }
    const json: string = `{"labelCount":${labelStrs.length},"infoCount":${infoJsons.length},` +
      `"labels":${JSON.stringify(labelStrs)},"infos":[${infoJsons.join(',')}]}`;
    const resp: LanHttpResponse = LanHttpResponse.json(200, json);
    this.emit('downloads', req.path, `${infoJsons.length}`, resp.body.byteLength, 200);
    return resp;
  }

  private handleDirs(req: LanHttpRequest): LanHttpResponse {
    if (!this.enabledCategories.has(WiFiServerMenu.DOWNLOAD_DIR)) {
      return LanHttpResponse.error(503, 'Download dirs category disabled');
    }
    const root: string | null = this.provider.getDownloadRoot();
    if (root === null) {
      const resp: LanHttpResponse = LanHttpResponse.json(200, '{"hasRoot":false,"count":0,"dirs":[]}');
      this.emit('dirs', req.path, '0', resp.body.byteLength, 200);
      return resp;
    }
    const entries: GalleryDirEntry[] = WiFiDownloadMigrationHelper.scanGalleryDirs(this.fs, root);
    const parts: string[] = [];
    for (let i = 0; i < entries.length; i++) {
      const e: GalleryDirEntry = entries[i];
      parts.push(`{"gid":${e.gid},"dirname":${JSON.stringify(e.dirname)}}`);
    }
    const json: string = `{"hasRoot":true,"count":${entries.length},"dirs":[${parts.join(',')}]}`;
    const resp: LanHttpResponse = LanHttpResponse.json(200, json);
    this.emit('dirs', req.path, `${entries.length}`, resp.body.byteLength, 200);
    return resp;
  }

  private handleDirManifest(req: LanHttpRequest): LanHttpResponse {
    if (!this.enabledCategories.has(WiFiServerMenu.DOWNLOAD_DIR)) {
      return LanHttpResponse.error(503, 'Download dirs category disabled');
    }
    const root: string | null = this.provider.getDownloadRoot();
    if (root === null) {
      return LanHttpResponse.error(404, 'Download root unavailable');
    }
    const gidRaw: string | null = req.getQuery('gid');
    const dirname: string | null = req.getQuery('dirname');
    if (gidRaw === null || dirname === null || !/^\d+$/.test(gidRaw) || !LanHttpCodec.isSafeDirName(dirname)) {
      return LanHttpResponse.error(400, 'Invalid gid or dirname');
    }
    const gid: number = Number.parseInt(gidRaw, 10);
    const parsedGid: number = WiFiDownloadMigrationHelper.parseGidFromDirname(dirname);
    if (parsedGid !== gid) {
      return LanHttpResponse.error(400, 'gid does not match dirname');
    }
    const dirPath: string = LanHttpTransferRouter.joinPath(root, dirname);
    if (!this.fs.isDirectory(dirPath)) {
      return LanHttpResponse.error(404, 'Gallery directory not found');
    }
    const files: FileMeta[] = WiFiDownloadMigrationHelper.scanGalleryDir(this.fs, dirPath);
    const fileParts: string[] = [];
    for (let i = 0; i < files.length; i++) {
      const f: FileMeta = files[i];
      fileParts.push(
        `{"name":${JSON.stringify(f.name)},"md5":${JSON.stringify(f.md5)},"size":${f.size}}`
      );
    }
    const json: string = `{"gid":${gid},"dirname":${JSON.stringify(dirname)},` +
      `"fileCount":${files.length},"files":[${fileParts.join(',')}]}`;
    const resp: LanHttpResponse = LanHttpResponse.json(200, json);
    this.emit('manifest', req.path, dirname, resp.body.byteLength, 200);
    return resp;
  }

  private handleDirFile(req: LanHttpRequest): LanHttpResponse {
    if (!this.enabledCategories.has(WiFiServerMenu.DOWNLOAD_DIR)) {
      return LanHttpResponse.error(503, 'Download dirs category disabled');
    }
    const root: string | null = this.provider.getDownloadRoot();
    if (root === null) {
      return LanHttpResponse.error(404, 'Download root unavailable');
    }
    const gidRaw: string | null = req.getQuery('gid');
    const dirname: string | null = req.getQuery('dirname');
    const relName: string | null = req.getQuery('name');
    if (gidRaw === null || dirname === null || relName === null) {
      return LanHttpResponse.error(400, 'Missing gid, dirname, or name');
    }
    if (!/^\d+$/.test(gidRaw) || !LanHttpCodec.isSafeDirName(dirname) || !LanHttpCodec.isSafeRelPath(relName)) {
      return LanHttpResponse.error(400, 'Unsafe path or invalid parameters');
    }
    const gid: number = Number.parseInt(gidRaw, 10);
    if (WiFiDownloadMigrationHelper.parseGidFromDirname(dirname) !== gid) {
      return LanHttpResponse.error(400, 'gid does not match dirname');
    }
    const dirPath: string = LanHttpTransferRouter.joinPath(root, dirname);
    const filePath: string | null = this.fs.resolveFileInGallery(dirPath, relName);
    if (filePath === null || !this.fs.isFile(filePath)) {
      return LanHttpResponse.error(404, 'File not found');
    }

    const totalSize: number = this.fs.size(filePath);
    const md5Hex: string | null = this.fs.computeMd5Hex(filePath);
    const expectedMd5: string = md5Hex === null ? '' : md5Hex;

    let reqOffset: number = 0;
    let reqLength: number = totalSize;
    const offRaw: string | null = req.getQuery('offset');
    const lenRaw: string | null = req.getQuery('length');
    if (offRaw !== null) {
      if (!/^\d+$/.test(offRaw)) {
        return LanHttpResponse.error(400, 'Invalid offset');
      }
      reqOffset = Number.parseInt(offRaw, 10);
    }
    if (lenRaw !== null) {
      if (!/^\d+$/.test(lenRaw)) {
        return LanHttpResponse.error(400, 'Invalid length');
      }
      reqLength = Number.parseInt(lenRaw, 10);
    }
    if (reqOffset > totalSize) {
      return LanHttpResponse.error(400, 'Offset beyond end of file');
    }
    const clampedLen: number = Math.min(reqLength, totalSize - reqOffset);

    let payload: ArrayBuffer;
    if (clampedLen === 0) {
      payload = new ArrayBuffer(0);
    } else {
      payload = this.readRange(filePath, reqOffset, clampedLen);
    }

    const extra: Map<string, string> = new Map<string, string>();
    extra.set('X-File-Md5', expectedMd5);
    extra.set('X-File-Size', `${totalSize}`);
    extra.set('X-Chunk-Offset', `${reqOffset}`);
    extra.set('X-Chunk-Length', `${payload.byteLength}`);
    const resp: LanHttpResponse = LanHttpResponse.binary(200, payload, extra);
    this.emit('file', req.path, `${dirname}/${relName}`, payload.byteLength, 200);
    return resp;
  }

  private readRange(filePath: string, offset: number, length: number): ArrayBuffer {
    const out: Uint8Array = new Uint8Array(length);
    let written: number = 0;
    const step: number = WiFiDownloadMigrationHelper.FILE_CHUNK_SIZE;
    while (written < length) {
      const want: number = Math.min(step, length - written);
      const chunk: Uint8Array | null = this.chunkSource.readChunk(filePath, offset + written, want);
      if (chunk === null || chunk.byteLength === 0) {
        break;
      }
      const copyLen: number = Math.min(chunk.byteLength, length - written);
      out.set(chunk.subarray(0, copyLen), written);
      written += copyLen;
    }
    if (written === length) {
      return out.buffer as ArrayBuffer;
    }
    return LanUtf8.toArrayBuffer(out.subarray(0, written));
  }

  private emit(kind: string, path: string, detail: string, bytes: number, statusCode: number): void {
    if (this.onEvent !== null) {
      this.onEvent(new LanTransferEvent(kind, path, detail, bytes, statusCode));
    }
  }

  private static joinPath(dir: string, name: string): string {
    return dir.length > 0 && dir.charAt(dir.length - 1) === '/' ? dir + name : dir + '/' + name;
  }
}

// ── Client HTTP Pull Orchestrator ───────────────────────────────────────────

export interface LanHttpRequester {
  request(method: string, url: string, timeoutMs: number): Promise<LanHttpResponse>;
  abortAll(): void;
}

export class LanPullProgress {
  category: WiFiServerMenu;
  phase: string;
  current: number;
  total: number;
  currentDirIndex: number;
  totalDirs: number;
  currentDirName: string;
  currentFileName: string;
  skippedFiles: number;
  neededFiles: number;
  completedFiles: number;
  failedFiles: number;
  bytesTransferred: number;
  resKey: string;
  resArgs: Array<string | number>;

  constructor(category: WiFiServerMenu, phase: string, resKey: string, resArgs: Array<string | number>) {
    this.category = category;
    this.phase = phase;
    this.current = 0;
    this.total = 0;
    this.currentDirIndex = 0;
    this.totalDirs = 0;
    this.currentDirName = '';
    this.currentFileName = '';
    this.skippedFiles = 0;
    this.neededFiles = 0;
    this.completedFiles = 0;
    this.failedFiles = 0;
    this.bytesTransferred = 0;
    this.resKey = resKey;
    this.resArgs = resArgs;
  }
}

export class LanPullSummary {
  category: WiFiServerMenu;
  ok: boolean = false;
  cancelled: boolean = false;
  itemsImported: number = 0;
  labelsImported: number = 0;
  dirsProcessed: number = 0;
  filesSkipped: number = 0;
  filesTransferred: number = 0;
  filesFailed: number = 0;
  bytesTransferred: number = 0;
  errorMessage: string = '';
  errorResKey: string = '';

  constructor(category: WiFiServerMenu) {
    this.category = category;
  }
}

export class LanHttpTransferClient {
  static readonly DEFAULT_TIMEOUT_MS: number = 15000;
  static readonly FILE_CHUNK_TIMEOUT_MS: number = 30000;

  private readonly requester: LanHttpRequester;
  private readonly persistSink: MigrationPersistSink;
  private readonly writeSink: MigrationWriteSink;
  private readonly fs: MigrationFileSystem;
  private readonly persistFlusher: (() => Promise<void>) | null;
  private readonly clientState: WiFiClientActivity = new WiFiClientActivity();
  private connectedEndpoint: LanEndpoint | null = null;
  private lastServerInfo: LanServerInfo | null = null;
  private cancelled: boolean = false;

  constructor(
    requester: LanHttpRequester,
    persistSink: MigrationPersistSink,
    writeSink: MigrationWriteSink,
    fs: MigrationFileSystem,
    persistFlusher?: () => Promise<void>
  ) {
    this.requester = requester;
    this.persistSink = persistSink;
    this.writeSink = writeSink;
    this.fs = fs;
    this.persistFlusher = persistFlusher !== undefined ? persistFlusher : null;
  }

  getConnectedEndpoint(): LanEndpoint | null {
    return this.connectedEndpoint;
  }

  getLastServerInfo(): LanServerInfo | null {
    return this.lastServerInfo;
  }

  getClientActivityState(): WiFiClientActivity {
    return this.clientState;
  }

  isCancelled(): boolean {
    return this.cancelled;
  }

  resetCancel(): void {
    this.cancelled = false;
  }

  cancel(): void {
    this.cancelled = true;
    this.requester.abortAll();
  }

  destroy(): void {
    this.cancel();
    this.clientState.destroy();
  }

  async connectAndInspect(rawTarget: string): Promise<LanServerInfo> {
    const endpoint: LanEndpoint | null = LanEndpointCodec.parseEndpoint(rawTarget);
    if (endpoint === null) {
      throw new Error(`Invalid LAN server address: ${rawTarget}`);
    }
    this.cancelled = false;
    const resp: LanHttpResponse = await this.requester.request(
      'GET',
      `${endpoint.baseUrl}${LanHttpRoutes.INFO}`,
      LanHttpTransferClient.DEFAULT_TIMEOUT_MS
    );
    if (resp.statusCode !== 200) {
      throw new Error(`Server returned HTTP ${resp.statusCode}: ${resp.reasonPhrase}`);
    }
    const info: LanServerInfo = LanServerInfo.fromJson(resp.bodyText());
    this.connectedEndpoint = endpoint;
    this.lastServerInfo = info;
    return info;
  }

  async pullBookmarks(onProgress?: (p: LanPullProgress) => void): Promise<LanPullSummary> {
    const summary: LanPullSummary = new LanPullSummary(WiFiServerMenu.BOOKMARK);
    const ep: LanEndpoint | null = this.connectedEndpoint;
    if (ep === null) {
      summary.errorResKey = 'wifi_server_connect_unable';
      summary.errorMessage = 'Not connected';
      return summary;
    }
    this.cancelled = false;
    this.notify(onProgress, new LanPullProgress(WiFiServerMenu.BOOKMARK, 'fetching', 'wifi_sending', []));
    try {
      const resp: LanHttpResponse = await this.requester.request(
        'GET',
        `${ep.baseUrl}${LanHttpRoutes.BOOKMARKS}`,
        LanHttpTransferClient.DEFAULT_TIMEOUT_MS
      );
      if (this.cancelled) {
        summary.cancelled = true;
        return summary;
      }
      if (resp.statusCode !== 200) {
        summary.errorResKey = 'wifi_server_connection_fail';
        summary.errorMessage = `HTTP ${resp.statusCode}`;
        return summary;
      }
      summary.bytesTransferred = resp.body.byteLength;
      const obj: JsonObject = JsonObject.parse(resp.bodyText());
      const items: string[] = LanHttpTransferClient.extractObjectJsonItems(obj, 'items');
      const batch: PersistBatch | null = WiFiClientActivity.planPersist(ReceiveKind.QUICK_SEARCH, items);
      if (batch !== null && batch.items.length > 0) {
        WiFiClientActivity.persist(batch, this.persistSink);
        await this.flushPersist();
      }
      summary.itemsImported = items.length;
      summary.ok = true;
      const doneProg: LanPullProgress = new LanPullProgress(WiFiServerMenu.BOOKMARK, 'done', 'wifi_send_done', []);
      doneProg.current = items.length;
      doneProg.total = items.length;
      doneProg.bytesTransferred = summary.bytesTransferred;
      this.notify(onProgress, doneProg);
      return summary;
    } catch (err) {
      const msg: string = err instanceof Error ? err.message : String(err);
      hilog.error(LOG_DOMAIN, LOG_TAG, 'pullBookmarks failed: %{public}s', msg);
      summary.cancelled = this.cancelled;
      summary.errorResKey = 'wifi_server_connection_fail';
      summary.errorMessage = msg;
      return summary;
    }
  }

  async pullFavorites(onProgress?: (p: LanPullProgress) => void): Promise<LanPullSummary> {
    const summary: LanPullSummary = new LanPullSummary(WiFiServerMenu.FAVORITE);
    const ep: LanEndpoint | null = this.connectedEndpoint;
    if (ep === null) {
      summary.errorResKey = 'wifi_server_connect_unable';
      summary.errorMessage = 'Not connected';
      return summary;
    }
    this.cancelled = false;
    this.notify(onProgress, new LanPullProgress(WiFiServerMenu.FAVORITE, 'fetching', 'wifi_sending', []));
    try {
      const resp: LanHttpResponse = await this.requester.request(
        'GET',
        `${ep.baseUrl}${LanHttpRoutes.FAVORITES}`,
        LanHttpTransferClient.DEFAULT_TIMEOUT_MS
      );
      if (this.cancelled) {
        summary.cancelled = true;
        return summary;
      }
      if (resp.statusCode !== 200) {
        summary.errorResKey = 'wifi_server_connection_fail';
        summary.errorMessage = `HTTP ${resp.statusCode}`;
        return summary;
      }
      summary.bytesTransferred = resp.body.byteLength;
      const obj: JsonObject = JsonObject.parse(resp.bodyText());
      const items: string[] = LanHttpTransferClient.extractObjectJsonItems(obj, 'items');
      const batch: PersistBatch | null = WiFiClientActivity.planPersist(ReceiveKind.FAVORITE_INFO, items);
      if (batch !== null && batch.items.length > 0) {
        WiFiClientActivity.persist(batch, this.persistSink);
        await this.flushPersist();
      }
      summary.itemsImported = items.length;
      summary.ok = true;
      const doneProg: LanPullProgress = new LanPullProgress(WiFiServerMenu.FAVORITE, 'done', 'wifi_send_done', []);
      doneProg.current = items.length;
      doneProg.total = items.length;
      doneProg.bytesTransferred = summary.bytesTransferred;
      this.notify(onProgress, doneProg);
      return summary;
    } catch (err) {
      const msg: string = err instanceof Error ? err.message : String(err);
      hilog.error(LOG_DOMAIN, LOG_TAG, 'pullFavorites failed: %{public}s', msg);
      summary.cancelled = this.cancelled;
      summary.errorResKey = 'wifi_server_connection_fail';
      summary.errorMessage = msg;
      return summary;
    }
  }

  async pullDownloads(onProgress?: (p: LanPullProgress) => void): Promise<LanPullSummary> {
    const summary: LanPullSummary = new LanPullSummary(WiFiServerMenu.DOWNLOAD);
    const ep: LanEndpoint | null = this.connectedEndpoint;
    if (ep === null) {
      summary.errorResKey = 'wifi_server_connect_unable';
      summary.errorMessage = 'Not connected';
      return summary;
    }
    this.cancelled = false;
    this.notify(onProgress, new LanPullProgress(WiFiServerMenu.DOWNLOAD, 'fetching', 'wifi_sending', []));
    try {
      const resp: LanHttpResponse = await this.requester.request(
        'GET',
        `${ep.baseUrl}${LanHttpRoutes.DOWNLOADS}`,
        LanHttpTransferClient.DEFAULT_TIMEOUT_MS
      );
      if (this.cancelled) {
        summary.cancelled = true;
        return summary;
      }
      if (resp.statusCode !== 200) {
        summary.errorResKey = 'wifi_server_connection_fail';
        summary.errorMessage = `HTTP ${resp.statusCode}`;
        return summary;
      }
      summary.bytesTransferred = resp.body.byteLength;
      const obj: JsonObject = JsonObject.parse(resp.bodyText());
      const labels: string[] = LanHttpTransferClient.extractStringItems(obj, 'labels');
      const infos: string[] = LanHttpTransferClient.extractObjectJsonItems(obj, 'infos');

      const labelBatch: PersistBatch | null = WiFiClientActivity.planPersist(ReceiveKind.DOWNLOAD_LABEL, labels);
      if (labelBatch !== null && labelBatch.items.length > 0) {
        WiFiClientActivity.persist(labelBatch, this.persistSink);
        await this.flushPersist();
      }
      const infoBatch: PersistBatch | null = WiFiClientActivity.planPersist(ReceiveKind.DOWNLOAD_INFO, infos);
      if (infoBatch !== null && infoBatch.items.length > 0) {
        WiFiClientActivity.persist(infoBatch, this.persistSink);
        await this.flushPersist();
      }

      summary.labelsImported = labels.length;
      summary.itemsImported = infos.length;
      summary.ok = true;
      const doneProg: LanPullProgress = new LanPullProgress(WiFiServerMenu.DOWNLOAD, 'done', 'wifi_send_done', []);
      doneProg.current = infos.length;
      doneProg.total = infos.length;
      doneProg.bytesTransferred = summary.bytesTransferred;
      this.notify(onProgress, doneProg);
      return summary;
    } catch (err) {
      const msg: string = err instanceof Error ? err.message : String(err);
      hilog.error(LOG_DOMAIN, LOG_TAG, 'pullDownloads failed: %{public}s', msg);
      summary.cancelled = this.cancelled;
      summary.errorResKey = 'wifi_server_connection_fail';
      summary.errorMessage = msg;
      return summary;
    }
  }

  async pullDownloadDirs(onProgress?: (p: LanPullProgress) => void): Promise<LanPullSummary> {
    const summary: LanPullSummary = new LanPullSummary(WiFiServerMenu.DOWNLOAD_DIR);
    const ep: LanEndpoint | null = this.connectedEndpoint;
    if (ep === null) {
      summary.errorResKey = 'wifi_server_connect_unable';
      summary.errorMessage = 'Not connected';
      return summary;
    }
    if (!this.writeSink.hasDownloadRoot()) {
      summary.errorResKey = 'wifi_download_dir_no_location';
      summary.errorMessage = 'Download directory is not set';
      return summary;
    }

    this.cancelled = false;
    this.notify(onProgress, new LanPullProgress(WiFiServerMenu.DOWNLOAD_DIR, 'fetching', 'wifi_sending', []));

    try {
      const dirsResp: LanHttpResponse = await this.requester.request(
        'GET',
        `${ep.baseUrl}${LanHttpRoutes.DIRS}`,
        LanHttpTransferClient.DEFAULT_TIMEOUT_MS
      );
      if (this.cancelled) {
        summary.cancelled = true;
        return summary;
      }
      if (dirsResp.statusCode !== 200) {
        summary.errorResKey = 'wifi_server_connection_fail';
        summary.errorMessage = `HTTP ${dirsResp.statusCode}`;
        return summary;
      }

      const dirsObj: JsonObject = JsonObject.parse(dirsResp.bodyText());
      const dirs: GalleryDirEntry[] = LanHttpTransferClient.parseDirEntries(dirsObj);
      if (dirs.length === 0) {
        summary.ok = true;
        summary.errorResKey = 'wifi_download_dir_empty';
        this.notify(onProgress, new LanPullProgress(WiFiServerMenu.DOWNLOAD_DIR, 'done', 'wifi_download_dir_empty', []));
        return summary;
      }

      const chunkSize: number = WiFiDownloadMigrationHelper.FILE_CHUNK_SIZE;
      for (let dIdx = 0; dIdx < dirs.length; dIdx++) {
        if (this.cancelled) {
          summary.cancelled = true;
          return summary;
        }
        const entry: GalleryDirEntry = dirs[dIdx];
        if (!LanHttpCodec.isSafeDirName(entry.dirname)) {
          hilog.warn(LOG_DOMAIN, LOG_TAG, 'Skipping unsafe remote dirname: %{public}s', entry.dirname);
          continue;
        }

        const manifestUrl: string =
          `${ep.baseUrl}${LanHttpRoutes.DIR_MANIFEST}?gid=${entry.gid}&dirname=${encodeURIComponent(entry.dirname)}`;
        const manifestResp: LanHttpResponse = await this.requester.request(
          'GET',
          manifestUrl,
          LanHttpTransferClient.DEFAULT_TIMEOUT_MS
        );
        if (this.cancelled) {
          summary.cancelled = true;
          return summary;
        }
        if (manifestResp.statusCode !== 200) {
          hilog.warn(LOG_DOMAIN, LOG_TAG, 'Manifest fetch failed for %{public}s: HTTP %{public}d',
            entry.dirname, manifestResp.statusCode);
          summary.filesFailed++;
          continue;
        }

        const manifest: DirManifest = LanHttpTransferClient.parseManifest(
          JsonObject.parse(manifestResp.bodyText()),
          dIdx + 1,
          dirs.length
        );
        const plan: ManifestPlan = this.clientState.onDirManifest(manifest, this.writeSink, this.fs);
        if (plan.sendEmptyAck) {
          summary.errorResKey = 'wifi_download_dir_no_location';
          summary.errorMessage = `Cannot create gallery directory: ${entry.dirname}`;
          return summary;
        }

        const skippedCount: number = manifest.files.length - plan.needed.length;
        summary.filesSkipped += skippedCount;
        summary.dirsProcessed++;

        const manifestProg: LanPullProgress = new LanPullProgress(
          WiFiServerMenu.DOWNLOAD_DIR,
          'manifest',
          'wifi_download_dir_manifest_received',
          [entry.dirname, dIdx + 1, dirs.length, skippedCount, plan.needed.length]
        );
        manifestProg.current = dIdx + 1;
        manifestProg.total = dirs.length;
        manifestProg.currentDirIndex = dIdx + 1;
        manifestProg.totalDirs = dirs.length;
        manifestProg.currentDirName = entry.dirname;
        manifestProg.skippedFiles = skippedCount;
        manifestProg.neededFiles = plan.needed.length;
        manifestProg.completedFiles = summary.filesTransferred;
        manifestProg.failedFiles = summary.filesFailed;
        manifestProg.bytesTransferred = summary.bytesTransferred;
        this.notify(onProgress, manifestProg);

        const metaByName: Map<string, FileMeta> = new Map<string, FileMeta>();
        for (let m = 0; m < manifest.files.length; m++) {
          metaByName.set(manifest.files[m].name, manifest.files[m]);
        }

        const galleryDir: string | null = this.writeSink.ensureGalleryDir(entry.gid, entry.dirname);
        if (galleryDir === null) {
          summary.errorResKey = 'wifi_download_dir_no_location';
          summary.errorMessage = `ensureGalleryDir failed for ${entry.dirname}`;
          return summary;
        }

        for (let fIdx = 0; fIdx < plan.needed.length; fIdx++) {
          if (this.cancelled) {
            summary.cancelled = true;
            return summary;
          }
          const relName: string = plan.needed[fIdx];
          if (!LanHttpCodec.isSafeRelPath(relName)) {
            hilog.warn(LOG_DOMAIN, LOG_TAG, 'Skipping unsafe remote relPath: %{public}s', relName);
            summary.filesFailed++;
            continue;
          }
          const meta: FileMeta | undefined = metaByName.get(relName);
          if (meta === undefined) {
            continue;
          }

          const fileOk: boolean = await this.pullSingleFile(
            ep.baseUrl,
            entry,
            galleryDir,
            meta,
            chunkSize,
            summary
          );
          if (this.cancelled) {
            summary.cancelled = true;
            return summary;
          }
          if (fileOk) {
            summary.filesTransferred++;
            const fileProg: LanPullProgress = new LanPullProgress(
              WiFiServerMenu.DOWNLOAD_DIR,
              'file',
              'wifi_download_dir_file_done',
              [relName]
            );
            fileProg.current = fIdx + 1;
            fileProg.total = plan.needed.length;
            fileProg.currentDirIndex = dIdx + 1;
            fileProg.totalDirs = dirs.length;
            fileProg.currentDirName = entry.dirname;
            fileProg.currentFileName = relName;
            fileProg.completedFiles = summary.filesTransferred;
            fileProg.failedFiles = summary.filesFailed;
            fileProg.bytesTransferred = summary.bytesTransferred;
            this.notify(onProgress, fileProg);
          } else {
            summary.filesFailed++;
            const failProg: LanPullProgress = new LanPullProgress(
              WiFiServerMenu.DOWNLOAD_DIR,
              'file',
              'wifi_download_dir_file_failed',
              []
            );
            failProg.current = fIdx + 1;
            failProg.total = plan.needed.length;
            failProg.currentDirIndex = dIdx + 1;
            failProg.totalDirs = dirs.length;
            failProg.currentDirName = entry.dirname;
            failProg.currentFileName = relName;
            failProg.completedFiles = summary.filesTransferred;
            failProg.failedFiles = summary.filesFailed;
            failProg.bytesTransferred = summary.bytesTransferred;
            this.notify(onProgress, failProg);
          }
        }
      }

      await this.flushPersist();
      summary.ok = summary.filesFailed === 0;
      const doneProg: LanPullProgress = new LanPullProgress(
        WiFiServerMenu.DOWNLOAD_DIR,
        'done',
        'wifi_send_done',
        []
      );
      doneProg.current = dirs.length;
      doneProg.total = dirs.length;
      doneProg.currentDirIndex = dirs.length;
      doneProg.totalDirs = dirs.length;
      doneProg.completedFiles = summary.filesTransferred;
      doneProg.failedFiles = summary.filesFailed;
      doneProg.bytesTransferred = summary.bytesTransferred;
      this.notify(onProgress, doneProg);
      return summary;
    } catch (err) {
      const msg: string = err instanceof Error ? err.message : String(err);
      hilog.error(LOG_DOMAIN, LOG_TAG, 'pullDownloadDirs failed: %{public}s', msg);
      summary.cancelled = this.cancelled;
      summary.errorResKey = 'wifi_server_connection_fail';
      summary.errorMessage = msg;
      return summary;
    }
  }

  private async pullSingleFile(
    baseUrl: string,
    entry: GalleryDirEntry,
    galleryDir: string,
    meta: FileMeta,
    chunkSize: number,
    summary: LanPullSummary
  ): Promise<boolean> {
    const fileSize: number = meta.size;
    // Empty file path: still fetch from server to confirm existence & create 0-byte file, then verify MD5
    if (fileSize <= 0) {
      const url: string = `${baseUrl}${LanHttpRoutes.DIR_FILE}?gid=${entry.gid}` +
        `&dirname=${encodeURIComponent(entry.dirname)}&name=${encodeURIComponent(meta.name)}&offset=0&length=0`;
      const resp: LanHttpResponse = await this.requester.request(
        'GET',
        url,
        LanHttpTransferClient.FILE_CHUNK_TIMEOUT_MS
      );
      if (this.cancelled || resp.statusCode !== 200) {
        return false;
      }
      const headerMd5: string | null = resp.getHeader('X-File-Md5');
      const expectedMd5: string = headerMd5 !== null && headerMd5.length > 0 ? headerMd5 : meta.md5;

      const existing: string | null = this.writeSink.resolveFile(galleryDir, meta.name);
      if (existing !== null) {
        this.writeSink.deleteFile(existing);
      }
      const wroteEmpty: boolean = this.writeSink.writeChunk(galleryDir, meta.name, new Uint8Array(0), 0);
      if (!wroteEmpty) {
        return false;
      }
      const writtenPath: string | null = this.writeSink.resolveFile(galleryDir, meta.name);
      if (writtenPath === null) {
        return false;
      }
      if (!WiFiDownloadMigrationHelper.verifyFileMd5(this.fs, writtenPath, expectedMd5)) {
        this.writeSink.deleteFile(writtenPath);
        hilog.error(LOG_DOMAIN, LOG_TAG, 'Empty file MD5 mismatch, deleted: %{public}s', meta.name);
        return false;
      }
      return true;
    }

    const chunkTotal: number = Math.max(1, Math.ceil(fileSize / chunkSize));
    let offset: number = 0;
    let chunkIndex: number = 0;

    while (offset < fileSize) {
      if (this.cancelled) {
        const partial: string | null = this.writeSink.resolveFile(galleryDir, meta.name);
        if (partial !== null) {
          this.writeSink.deleteFile(partial);
        }
        return false;
      }
      const want: number = Math.min(chunkSize, fileSize - offset);
      const url: string = `${baseUrl}${LanHttpRoutes.DIR_FILE}?gid=${entry.gid}` +
        `&dirname=${encodeURIComponent(entry.dirname)}&name=${encodeURIComponent(meta.name)}` +
        `&offset=${offset}&length=${want}`;
      const resp: LanHttpResponse = await this.requester.request(
        'GET',
        url,
        LanHttpTransferClient.FILE_CHUNK_TIMEOUT_MS
      );
      if (this.cancelled) {
        const partial: string | null = this.writeSink.resolveFile(galleryDir, meta.name);
        if (partial !== null) {
          this.writeSink.deleteFile(partial);
        }
        return false;
      }
      if (resp.statusCode !== 200) {
        hilog.warn(LOG_DOMAIN, LOG_TAG, 'Chunk fetch failed for %{public}s@%{public}d: HTTP %{public}d',
          meta.name, offset, resp.statusCode);
        const partial: string | null = this.writeSink.resolveFile(galleryDir, meta.name);
        if (partial !== null) {
          this.writeSink.deleteFile(partial);
        }
        return false;
      }

      const headerMd5: string | null = resp.getHeader('X-File-Md5');
      const expectedMd5: string = headerMd5 !== null && headerMd5.length > 0 ? headerMd5 : meta.md5;
      const gotLen: number = resp.body.byteLength;
      summary.bytesTransferred += gotLen;

      const nextOffset: number = offset + gotLen;
      const isLast: boolean = nextOffset >= fileSize || gotLen === 0;

      const chunk: FileChunk = new FileChunk();
      chunk.gid = entry.gid;
      chunk.name = meta.name;
      chunk.fileMd5 = expectedMd5;
      chunk.chunkIndex = chunkIndex;
      chunk.chunkTotal = chunkTotal;
      chunk.data = resp.body;
      chunk.lastChunk = isLast;

      const md5Mismatch: boolean = this.clientState.applyFileChunk(chunk, this.writeSink, this.fs);
      if (md5Mismatch) {
        return false;
      }
      if (isLast) {
        return true;
      }
      offset = nextOffset;
      chunkIndex++;
    }
    return true;
  }

  private async flushPersist(): Promise<void> {
    if (this.persistFlusher !== null) {
      await this.persistFlusher();
    }
  }

  private notify(onProgress: ((p: LanPullProgress) => void) | undefined, progress: LanPullProgress): void {
    if (onProgress !== undefined) {
      onProgress(progress);
    }
  }

  private static extractObjectJsonItems(obj: JsonObject, key: string): string[] {
    if (!obj.has(key) || obj.isNull(key)) {
      return [];
    }
    const arr: JsonArray = obj.getJSONArray(key);
    const out: string[] = [];
    for (let i = 0; i < arr.length(); i++) {
      out.push(arr.getJSONObject(i).rawText());
    }
    return out;
  }

  private static extractStringItems(obj: JsonObject, key: string): string[] {
    if (!obj.has(key) || obj.isNull(key)) {
      return [];
    }
    const arr: JsonArray = obj.getJSONArray(key);
    const out: string[] = [];
    for (let i = 0; i < arr.length(); i++) {
      out.push(arr.getString(i));
    }
    return out;
  }

  private static parseDirEntries(obj: JsonObject): GalleryDirEntry[] {
    if (!obj.has('dirs') || obj.isNull('dirs')) {
      return [];
    }
    const arr: JsonArray = obj.getJSONArray('dirs');
    const out: GalleryDirEntry[] = [];
    for (let i = 0; i < arr.length(); i++) {
      const item: JsonObject = arr.getJSONObject(i);
      const entry: GalleryDirEntry = new GalleryDirEntry();
      entry.gid = item.getLong('gid');
      entry.dirname = item.getString('dirname');
      out.push(entry);
    }
    return out;
  }

  private static parseManifest(obj: JsonObject, pageIndex: number, pageSize: number): DirManifest {
    const manifest: DirManifest = new DirManifest();
    manifest.gid = obj.getLong('gid');
    manifest.dirname = obj.getString('dirname');
    manifest.pageIndex = pageIndex;
    manifest.pageSize = pageSize;
    const files: FileMeta[] = [];
    if (obj.has('files') && !obj.isNull('files')) {
      const arr: JsonArray = obj.getJSONArray('files');
      for (let i = 0; i < arr.length(); i++) {
        const fObj: JsonObject = arr.getJSONObject(i);
        const meta: FileMeta = new FileMeta();
        meta.name = fObj.getString('name');
        meta.md5 = fObj.optString('md5', '');
        meta.size = fObj.getLong('size');
        files.push(meta);
      }
    }
    manifest.files = files;
    return manifest;
  }
}
