/*
 * Copyright 2016 Hippo Seven
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

import http from '@ohos.net.http';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { Dns, InetAddress, OverrideAwareDns, SYSTEM_DNS, describeNetworkError } from '../../okhttp/Dns';
import { InetValidator } from '../../network/InetValidator';

const DOMAIN: number = 0x0000;
const TAG: string = 'EhHosts';

/**
 * 1:1 对位 upstream: app/src/main/java/com/hippo/ehviewer/client/EhHosts.java
 * （inventory S0075，175 行）
 *
 * 内置 hosts + 用户 hosts + DoH + 系统 DNS 的四级回落（顺序即优先级）：
 *   1. 用户自定义 hosts（`Settings.getBuiltInHosts` 之外的 `hosts` 文件，由 EhApplication 提供）
 *   2. 内置 hosts（`Settings.getBuiltInHosts()` 开 E 站表、`getBuiltEXHosts()` 开里站表）
 *   3. DoH（`Settings.getDoH()`，`https://77.88.8.1/dns-query`，POST）
 *   4. 系统 `InetAddress.getAllByName`
 * 每一级拿到结果都**先 shuffle**（`new Random(System.currentTimeMillis())`）——
 * 上游刻意的负载打散，照搬。
 *
 * 本层：
 *   - 内置表**逐条照搬**（含被注释掉的历史 IP 不搬）
 *   - 保留同步 `EhHosts.lookup`（纯逻辑测试）及异步 `OkHttpEhHosts implements Dns`（生产网络栈）
 */
export class EhHosts {
  /** 内置 hosts 表（host → IP 列表）。开关由 EhHostsConfig 决定。 */
  static builtInHosts(config: EhHostsConfig): Map<string, string[]> {
    const map: Map<string, string[]> = new Map<string, string[]>();
    if (config.getBuiltInHosts()) {
      map.set('e-hentai.org', [
        '104.20.18.168', '104.20.19.168', '172.66.132.196',
        '172.66.140.62', '104.20.18.168', '172.67.2.238'
      ]);
      map.set('repo.e-hentai.org', ['104.20.18.168', '104.20.19.168', '172.67.2.238']);
      map.set('forums.e-hentai.org', ['172.66.132.196', '172.66.140.62']);
      map.set('upld.e-hentai.org', ['89.149.221.236', '95.211.208.236']);
      map.set('ehgt.org', [
        '185.132.132.79', '62.112.8.152', '185.132.132.76',
        '2a00:7c80:0:123::3a85', '2a00:7c80:0:12d::38a1', '2a00:7c80:0:13b::37a4'
      ]);
      map.set('raw.githubusercontent.com', [
        '151.101.0.133', '151.101.64.133', '151.101.128.133', '151.101.192.133'
      ]);
    }
    if (config.getBuiltEXHosts()) {
      map.set('exhentai.org', [
        '178.175.128.251', '178.175.128.252', '178.175.128.253', '178.175.128.254',
        '178.175.129.251', '178.175.129.252', '178.175.129.253', '178.175.129.254',
        '178.175.132.19', '178.175.132.20', '178.175.132.21', '178.175.132.22'
      ]);
      map.set('upld.exhentai.org', ['178.175.132.22', '178.175.129.254', '178.175.128.254']);
      map.set('s.exhentai.org', [
        '178.175.129.253', '178.175.129.254', '178.175.128.253',
        '178.175.128.254', '178.175.132.21', '178.175.132.22'
      ]);
    }
    return map;
  }

  private _config: EhHostsConfig;
  private _rand: () => number;

  constructor(config: EhHostsConfig, rand?: () => number) {
    this._config = config;
    this._rand = rand === undefined ? (): number => Math.random() : rand;
  }

  /** 对齐 `lookup(String hostname)`：四级回落，每级结果先 shuffle。 */
  lookup(hostname: string, hosts: HostsProvider, doh: DohResolver, system: SystemDnsResolver): string[] {
    // 1. 用户 hosts
    const userAddresses: string[] | null = hosts.getList(hostname);
    if (userAddresses !== null && userAddresses.length > 0) {
      return this.shuffle(userAddresses);
    }
    // 2. 内置 hosts
    if (this._config.getBuiltInHosts() || this._config.getBuiltEXHosts()) {
      const builtIn: string[] | undefined = EhHosts.builtInHosts(this._config).get(hostname);
      if (builtIn !== undefined) {
        return this.shuffle(builtIn);
      }
    }
    // 3. DoH
    if (this._config.getDoH()) {
      const dohAddresses: string[] = doh.lookup(hostname);
      if (dohAddresses.length > 0) {
        return this.shuffle(dohAddresses);
      }
    }
    // 4. 系统 DNS（失败抛 UnknownHostException 等价物）
    const systemAddresses: string[] = system.getAllByName(hostname);
    return this.shuffle(systemAddresses);
  }

  /** Fisher–Yates（上游用 Collections.shuffle，语义相同）。 */
  private shuffle(list: string[]): string[] {
    return EhHosts.shuffleArray(list, this._rand);
  }

  static shuffleArray<T>(list: T[], rand: () => number): T[] {
    const out: T[] = list.slice();
    for (let i = out.length - 1; i > 0; i--) {
      const j: number = Math.floor(rand() * (i + 1));
      const tmp: T = out[i];
      out[i] = out[j];
      out[j] = tmp;
    }
    return out;
  }
}

/** `Settings.getBuiltInHosts() / getBuiltEXHosts() / getDoH()` 注入点。默认与上游一致（BuiltIn=true, BuiltEX=true, DoH=false）。 */
export class EhHostsConfig {
  getBuiltInHosts(): boolean {
    return true;
  }

  getBuiltEXHosts(): boolean {
    return true;
  }

  getDoH(): boolean {
    return false;
  }
}

/** 用户自定义 hosts（同步形态，供纯逻辑测试）。 */
export interface HostsProvider {
  getList(hostname: string): string[] | null;
}

/** 用户自定义 hosts（异步形态，适配 storage-db 的 Hosts.getList）。 */
export interface AsyncHostsProvider {
  getList(hostname: string): Promise<string[] | null>;
}

/** DoH 解析器（同步形态，供纯逻辑测试）。 */
export interface DohResolver {
  lookup(hostname: string): string[];
}

/** DoH 解析器（异步形态，POST 到 https://77.88.8.1/dns-query）。 */
export interface AsyncDohResolver {
  lookupAsync(hostname: string): Promise<string[]>;
}

/** 系统 DNS（同步形态，供纯逻辑测试）。 */
export interface SystemDnsResolver {
  getAllByName(hostname: string): string[];
}

/**
 * 基于 `@ohos.net.http` 的 RFC 8484 DoH 解析器（POST `application/dns-message` 到 `https://77.88.8.1/dns-query`）。
 */
export class HttpDohResolver implements AsyncDohResolver {
  static readonly DEFAULT_DOH_URL: string = 'https://77.88.8.1/dns-query';

  private readonly _url: string;
  private readonly _timeoutMs: number;

  constructor(url: string = HttpDohResolver.DEFAULT_DOH_URL, timeoutMs: number = 5000) {
    this._url = url;
    this._timeoutMs = timeoutMs;
  }

  async lookupAsync(hostname: string): Promise<string[]> {
    const query: ArrayBuffer = HttpDohResolver.encodeDnsQuery(hostname, 1); // TYPE A
    const req: http.HttpRequest = http.createHttp();
    try {
      const reqHeaders: Record<string, string> = {};
      reqHeaders['Content-Type'] = 'application/dns-message';
      reqHeaders['Accept'] = 'application/dns-message';
      const options: http.HttpRequestOptions = {
        method: http.RequestMethod.POST,
        header: reqHeaders,
        extraData: query,
        expectDataType: http.HttpDataType.ARRAY_BUFFER,
        usingCache: false,
        connectTimeout: this._timeoutMs,
        readTimeout: this._timeoutMs
      };
      const resp: http.HttpResponse = await req.request(this._url, options);
      if ((resp.responseCode as number) < 200 || (resp.responseCode as number) >= 300) {
        return [];
      }
      if (!(resp.result instanceof ArrayBuffer)) {
        return [];
      }
      return HttpDohResolver.decodeDnsResponse(resp.result as ArrayBuffer);
    } finally {
      req.destroy();
    }
  }

  /** 构造 RFC 1035 二进制 DNS 查询报文（RD=1, QDCOUNT=1）。 */
  static encodeDnsQuery(hostname: string, qtype: number = 1): ArrayBuffer {
    const clean: string = hostname.trim().toLowerCase().replace(/\.+$/, '');
    const labels: string[] = clean.length === 0 ? [] : clean.split('.');
    const bytes: number[] = [
      0x00, 0x00, // ID
      0x01, 0x00, // Flags: standard query, recursion desired
      0x00, 0x01, // QDCOUNT = 1
      0x00, 0x00, // ANCOUNT = 0
      0x00, 0x00, // NSCOUNT = 0
      0x00, 0x00  // ARCOUNT = 0
    ];
    for (let i = 0; i < labels.length; i++) {
      const label: string = labels[i];
      if (label.length === 0 || label.length > 63) {
        continue;
      }
      bytes.push(label.length);
      for (let j = 0; j < label.length; j++) {
        bytes.push(label.charCodeAt(j) & 0xff);
      }
    }
    bytes.push(0x00); // Root label
    bytes.push((qtype >> 8) & 0xff, qtype & 0xff);
    bytes.push(0x00, 0x01); // QCLASS IN = 1
    return new Uint8Array(bytes).buffer as ArrayBuffer;
  }

  /** 解析 RFC 1035 二进制 DNS 响应报文中的 A (4B) 与 AAAA (16B) 记录。 */
  static decodeDnsResponse(buffer: ArrayBuffer): string[] {
    const u8: Uint8Array = new Uint8Array(buffer);
    if (u8.byteLength < 12) {
      return [];
    }
    const rcode: number = u8[3] & 0x0f;
    if (rcode !== 0) {
      return [];
    }
    const qdCount: number = (u8[4] << 8) | u8[5];
    const anCount: number = (u8[6] << 8) | u8[7];
    let pos: number = 12;

    for (let i = 0; i < qdCount; i++) {
      pos = HttpDohResolver.skipDnsName(u8, pos);
      if (pos < 0 || pos + 4 > u8.byteLength) {
        return [];
      }
      pos += 4;
    }

    const ips: string[] = [];
    for (let i = 0; i < anCount; i++) {
      pos = HttpDohResolver.skipDnsName(u8, pos);
      if (pos < 0 || pos + 10 > u8.byteLength) {
        break;
      }
      const rtype: number = (u8[pos] << 8) | u8[pos + 1];
      const rdLength: number = (u8[pos + 8] << 8) | u8[pos + 9];
      pos += 10;
      if (pos + rdLength > u8.byteLength) {
        break;
      }
      if (rtype === 1 && rdLength === 4) {
        ips.push(`${u8[pos]}.${u8[pos + 1]}.${u8[pos + 2]}.${u8[pos + 3]}`);
      } else if (rtype === 28 && rdLength === 16) {
        const groups: string[] = [];
        for (let g = 0; g < 16; g += 2) {
          const val: number = (u8[pos + g] << 8) | u8[pos + g + 1];
          groups.push(val.toString(16));
        }
        ips.push(groups.join(':'));
      }
      pos += rdLength;
    }
    return ips;
  }

  private static skipDnsName(u8: Uint8Array, start: number): number {
    let pos: number = start;
    while (pos < u8.byteLength) {
      const len: number = u8[pos];
      if (len === 0) {
        return pos + 1;
      }
      if ((len & 0xc0) === 0xc0) {
        return pos + 2 <= u8.byteLength ? pos + 2 : -1;
      }
      pos += 1 + len;
    }
    return -1;
  }
}

/**
 * `okhttp/Dns` 适配器：把 EhHosts 的四级回落（用户 hosts → 内置 hosts → DoH → 系统 DNS）
 * 接入 `OkHttpClientBuilder.dns(...)`，并标注 `isHostOverride=true` 供 TLS Domain Fronting 识别。
 */
export class OkHttpEhHosts implements OverrideAwareDns {
  readonly reportsOverrideFlag: boolean = true;
  private readonly _config: EhHostsConfig;
  private readonly _syncHosts: HostsProvider | null;
  private readonly _asyncHosts: AsyncHostsProvider | null;
  private readonly _doh: AsyncDohResolver | null;
  private readonly _systemDns: Dns;
  private readonly _rand: () => number;

  constructor(
    config: EhHostsConfig = new EhHostsConfig(),
    syncHosts: HostsProvider | null = null,
    asyncHosts: AsyncHostsProvider | null = null,
    doh: AsyncDohResolver | null = new HttpDohResolver(),
    systemDns: Dns = SYSTEM_DNS,
    rand?: () => number
  ) {
    this._config = config;
    this._syncHosts = syncHosts;
    this._asyncHosts = asyncHosts;
    this._doh = doh;
    this._systemDns = systemDns;
    this._rand = rand === undefined ? (): number => Math.random() : rand;
  }

  async lookup(hostname: string): Promise<InetAddress[]> {
    const trimmed: string = hostname.trim();
    const unbracketed: string = trimmed.startsWith('[') && trimmed.endsWith(']')
      ? trimmed.substring(1, trimmed.length - 1) : trimmed;
    const lower: string = unbracketed.toLowerCase();

    // IP 字面量直返，不走 hosts/DoH
    if (InetValidator.isValidInet4Address(unbracketed) || unbracketed.indexOf(':') >= 0) {
      return [new InetAddress(hostname, unbracketed, false)];
    }

    // 1. 用户自定义 hosts（异步优先，同步兼容）
    if (this._asyncHosts !== null) {
      const userAsync: string[] | null = await this._asyncHosts.getList(lower);
      if (userAsync !== null && userAsync.length > 0) {
        hilog.info(DOMAIN, TAG, 'lookup host=%{public}s tier=user count=%{public}d', lower, userAsync.length);
        return this.toOverrideAddresses(hostname, userAsync);
      }
    }
    if (this._syncHosts !== null) {
      const userSync: string[] | null = this._syncHosts.getList(lower);
      if (userSync !== null && userSync.length > 0) {
        hilog.info(DOMAIN, TAG, 'lookup host=%{public}s tier=user count=%{public}d', lower, userSync.length);
        return this.toOverrideAddresses(hostname, userSync);
      }
    }

    // 2. 内置 hosts
    if (this._config.getBuiltInHosts() || this._config.getBuiltEXHosts()) {
      const builtIn: string[] | undefined = EhHosts.builtInHosts(this._config).get(lower);
      if (builtIn !== undefined && builtIn.length > 0) {
        hilog.info(DOMAIN, TAG, 'lookup host=%{public}s tier=builtin count=%{public}d', lower, builtIn.length);
        return this.toOverrideAddresses(hostname, builtIn);
      }
    }

    // 3. DoH
    if (this._config.getDoH() && this._doh !== null) {
      try {
        const dohIps: string[] = await this._doh.lookupAsync(lower);
        if (dohIps.length > 0) {
          hilog.info(DOMAIN, TAG, 'lookup host=%{public}s tier=doh count=%{public}d', lower, dohIps.length);
          return this.toOverrideAddresses(hostname, dohIps);
        }
      } catch (e) {
        const msg: string = describeNetworkError(e as Object);
        hilog.warn(DOMAIN, TAG, 'DoH lookup failed for %{public}s: %{public}s', lower, msg);
      }
    }

    // 4. 系统 DNS（非覆写）
    const sysAddresses: InetAddress[] = await this._systemDns.lookup(hostname);
    hilog.info(DOMAIN, TAG,
      'lookup host=%{public}s tier=system builtIn=%{public}s builtEx=%{public}s doh=%{public}s sysCount=%{public}d',
      lower, String(this._config.getBuiltInHosts()), String(this._config.getBuiltEXHosts()),
      String(this._config.getDoH()), sysAddresses.length);
    return EhHosts.shuffleArray(sysAddresses, this._rand);
  }

  private toOverrideAddresses(hostname: string, ips: string[]): InetAddress[] {
    const shuffled: string[] = EhHosts.shuffleArray(ips, this._rand);
    const out: InetAddress[] = [];
    for (let i = 0; i < shuffled.length; i++) {
      out.push(new InetAddress(hostname, shuffled[i], true));
    }
    return out;
  }
}
