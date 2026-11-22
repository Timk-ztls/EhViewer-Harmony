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

import { HttpUrl } from './HttpUrl';

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
