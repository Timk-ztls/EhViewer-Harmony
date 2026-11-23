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
import { hilog } from '@kit.PerformanceAnalysisKit';
import { HttpUrl } from './HttpUrl';
import { describeNetworkError } from './Dns';

/** 代理类型，对应 java.net.Proxy.Type。 */
export enum ProxyType {
  DIRECT = 'DIRECT',
  HTTP = 'HTTP',
  SOCKS = 'SOCKS'
}

/** java.net.Proxy + InetSocketAddress 等价。 */
export class Proxy {
  /** 显式禁用代理（对应 java.net.Proxy.NO_PROXY）。 */
  static readonly NO_PROXY: Proxy = new Proxy(ProxyType.DIRECT, '', 0, true);

  private readonly _type: ProxyType;
  private readonly _address: string;
  private readonly _port: number;
  private readonly _noProxy: boolean;

  constructor(type: ProxyType, address: string = '', port: number = 0, noProxy: boolean = false) {
    this._type = type;
    this._address = address;
    this._port = port;
    this._noProxy = noProxy;
  }

  static direct(): Proxy {
    return Proxy.NO_PROXY;
  }

  /** 跟随系统代理设置（DefaultProxySelector 默认返回值）。 */
  static system(): Proxy {
    return new Proxy(ProxyType.DIRECT, '', 0, false);
  }

  type(): ProxyType {
    return this._type;
  }

  isNoProxy(): boolean {
    return this._noProxy;
  }

  address(): string {
    return this._address;
  }

  port(): number {
    return this._port;
  }

  equals(other: Proxy): boolean {
    return this._type === other._type && this._address === other._address &&
      this._port === other._port && this._noProxy === other._noProxy;
  }

  toString(): string {
    if (this._type === ProxyType.DIRECT) {
      return this._noProxy ? 'NO_PROXY' : 'DIRECT';
    }
    return `${this._type} ${this._address}:${this._port}`;
  }
}

/**
 * java.net.ProxySelector 的等价抽象。
 *
 * 上游：EhProxySelector 继承 ProxySelector，按 EhUrl 的 host 决定走直连 / 系统代理 / 手动代理。
 * ArkTS 没有 ProxySelector 基类，这里定义同名抽象类，select() 返回 Proxy[]（Java 返回 List<Proxy>）。
 * 传输层消费方式：OkHttp 在建立 socket 时逐个尝试 select() 的返回值；
 * 本层 socket 引擎同样按顺序尝试（@ohos.net.http 引擎只支持系统/NO_PROXY/HTTP 代理）。
 */
export abstract class ProxySelector {
  abstract select(url: HttpUrl): Proxy[];

  static getDefault(): ProxySelector {
    return new DefaultProxySelector();
  }
}

/** 系统代理默认选择器，等价 ProxySelector.getDefault()。 */
export class DefaultProxySelector extends ProxySelector {
  select(url: HttpUrl): Proxy[] {
    return [Proxy.system()];
  }
}

export type SystemProxyResolverFn = (host: string) => Promise<Proxy | null>;

/** 解析系统 HTTP 代理并支持测试桩注入，供 ConnectInterceptor 与 Http1SocketTransport 复用。 */
export class SystemProxyHelper {
  private static _overrideResolver: SystemProxyResolverFn | null = null;

  static setResolver(resolver: SystemProxyResolverFn | null): void {
    SystemProxyHelper._overrideResolver = resolver;
  }

  static async resolveHttpProxy(host: string): Promise<Proxy | null> {
    if (SystemProxyHelper._overrideResolver !== null) {
      return SystemProxyHelper._overrideResolver(host);
    }
    try {
      const sysProxy: connection.HttpProxy = await connection.getDefaultHttpProxy();
      const proxyHost: string = sysProxy !== undefined && sysProxy !== null && typeof sysProxy.host === 'string'
        ? sysProxy.host.trim() : '';
      const proxyPort: number = sysProxy !== undefined && sysProxy !== null && typeof sysProxy.port === 'number'
        ? sysProxy.port : 0;
      if (proxyHost.length === 0 || proxyPort <= 0) {
        return null;
      }
      const exclusions: string[] = Array.isArray(sysProxy.exclusionList) ? sysProxy.exclusionList : [];
      if (SystemProxyHelper.isHostExcluded(host, exclusions)) {
        return null;
      }
      return new Proxy(ProxyType.HTTP, proxyHost, proxyPort);
    } catch (e) {
      hilog.debug(0x0000, 'SystemProxyHelper',
        'getDefaultHttpProxy unavailable for %{public}s: %{public}s',
        host, describeNetworkError(e as Object));
      return null;
    }
  }

  static isHostExcluded(host: string, exclusionList: string[]): boolean {
    const lower: string = host.trim().toLowerCase();
    for (let i = 0; i < exclusionList.length; i++) {
      const raw: string = exclusionList[i].trim().toLowerCase();
      if (raw.length === 0) {
        continue;
      }
      if (raw === '*') {
        return true;
      }
      const pat: string = raw.startsWith('*.') ? raw.substring(1) : raw;
      if (pat.startsWith('.')) {
        if (lower.endsWith(pat) || lower === pat.substring(1)) {
          return true;
        }
      } else if (lower === pat) {
        return true;
      }
    }
    return false;
  }
}
