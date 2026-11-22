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

import connection from '@ohos.net.connection';

/**
 * okhttp3.Dns / InetAddress 等价层。
 *
 * 上游：EhHosts implements Dns，注入 OkHttpClient.Builder.dns()，用于
 *   1) 内置 hosts（Settings.getBuiltInHosts / getBuiltEXHosts 的 IP 表）
 *   2) 用户自定义 Hosts
 *   3) DoH（DnsOverHttps）兜底
 * 返回的 InetAddress 只被 OkHttp 内部用来建连，上游只构造不读字段。
 *
 * 关键差异：OkHttp 3.14 的 Dns.lookup(String) 是同步阻塞方法；
 * ArkTS 不能在网络线程同步阻塞，故改为 Promise<InetAddress[]>，
 * EhHosts.lookup 相应地变成 async（内部 await dnsOverHttps.lookup）。
 */
export class InetAddress {
  private readonly _hostName: string;
  private readonly _hostAddress: string;
  private readonly _isHostOverride: boolean;

  constructor(hostName: string, hostAddress: string, isHostOverride: boolean = false) {
    this._hostName = hostName;
    this._hostAddress = hostAddress;
    this._isHostOverride = isHostOverride;
  }

  /** 对齐 InetAddress.getHostName()：hosts 表里存的是域名。 */
  hostName(): string {
    return this._hostName;
  }

  /** 对齐 InetAddress.getHostAddress()：点分 IPv4 或 IPv6 文本。 */
  hostAddress(): string {
    return this._hostAddress;
  }

  /** true 表示来自自定义/内置 hosts 或 DoH 覆写（而非系统 DNS），TLS 需要启用 Domain Fronting 校验策略。 */
  isHostOverride(): boolean {
    return this._isHostOverride;
  }

  isIpv6(): boolean {
    return this._hostAddress.indexOf(':') >= 0;
  }

  toString(): string {
    return `${this._hostName}/${this._hostAddress}`;
  }
}

/** okhttp3.Dns 等价接口（同步 → 异步，见文件头说明）。 */
export interface Dns {
  lookup(hostname: string): Promise<InetAddress[]>;
}

/** 显式区分「逐地址标明是否覆写」的 Dns 实现（如 OkHttpEhHosts），避免系统 DNS 兜底误走 Domain Fronting。 */
export interface OverrideAwareDns extends Dns {
  readonly reportsOverrideFlag: boolean;
}

/**
 * 将 HarmonyOS BusinessError ({code, message})、标准 Error 或裸对象安全格式化为可读错误串。
 */
export function describeNetworkError(e: Object | null | undefined): string {
  if (e === null || e === undefined) {
    return 'Unknown network error';
  }
  if (typeof e === 'string') {
    return e as string;
  }
  let codeStr: string = '';
  let msgStr: string = '';
  if (typeof e === 'object') {
    const rec: Record<string, Object> = e as Record<string, Object>;
    const rawCode: Object | undefined = rec['code'];
    if (typeof rawCode === 'number' || typeof rawCode === 'string') {
      codeStr = String(rawCode);
    }
    const rawMsg: Object | undefined = rec['message'];
    if (typeof rawMsg === 'string') {
      msgStr = rawMsg as string;
    }
  }
  if (msgStr.length === 0 && e instanceof Error && e.message !== undefined && e.message !== null) {
    msgStr = e.message;
  }
  if (codeStr.length > 0 && msgStr.length > 0) {
    return `[${codeStr}] ${msgStr}`;
  }
  if (msgStr.length > 0) {
    return msgStr;
  }
  if (codeStr.length > 0) {
    return `BusinessError ${codeStr}`;
  }
  if (typeof e === 'object') {
    try {
      const json: string = JSON.stringify(e);
      if (json !== undefined && json.length > 0 && json !== '{}') {
        return json;
      }
    } catch (_ignored) {
      // 忽略循环引用或不可序列化对象
    }
  }
  return String(e);
}

/**
 * 统一将传输层/DNS 抛出的 BusinessError 或异常归一化为 Error，保留 'Canceled' / 'timeout' 哨兵。
 */
export function toNetworkError(e: Object | null | undefined, prefix?: string): Error {
  if (e instanceof Error) {
    if (e.message === 'Canceled' || e.message === 'timeout') {
      return e;
    }
    const rec: Record<string, Object> = (e as Object) as Record<string, Object>;
    const rawCode: Object | undefined = rec['code'];
    const hasCode: boolean = typeof rawCode === 'number' || typeof rawCode === 'string';
    if (!hasCode && (prefix === undefined || prefix.length === 0) &&
      e.message !== undefined && e.message !== null && e.message.length > 0) {
      return e;
    }
  }
  const detail: string = describeNetworkError(e);
  const fullMsg: string = prefix !== undefined && prefix.length > 0 ? `${prefix}: ${detail}` : detail;
  return new Error(fullMsg);
}

/** okhttp3.Dns.SYSTEM 等价：交给系统解析（@ohos.net.connection）。 */
export class SystemDns implements Dns {
  async lookup(hostname: string): Promise<InetAddress[]> {
    // getAddressesByName 是异步 API，返回地址字符串数组
    let addresses: connection.NetAddress[];
    try {
      addresses = await connection.getAddressesByName(hostname);
    } catch (e) {
      throw toNetworkError(e as Object, `DNS lookup(${hostname})`);
    }
    const result: InetAddress[] = [];
    for (let i = 0; i < addresses.length; i++) {
      result.push(new InetAddress(hostname, addresses[i].address));
    }
    return result;
  }
}

/** okhttp3.Dns.SYSTEM 的静态单例。 */
export const SYSTEM_DNS: Dns = new SystemDns();
