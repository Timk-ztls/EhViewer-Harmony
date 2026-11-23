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

import { webview } from '@kit.ArkWeb';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { EhProxySelector } from '../ehviewer/EhProxySelector';
import { Settings } from '../ehviewer/Settings';
import { describeNetworkError } from '../okhttp/Dns';

const DOMAIN: number = 0x0000;
const TAG: string = 'ArkWebProxyManager';
const OVERRIDE_TIMEOUT_MS: number = 2500;

export interface WebProxyBackend {
  initializeWebEngine(): void;
  applyProxyOverride(type: number, proxyRule: string | null): Promise<void>;
  removeProxyOverride(): Promise<void>;
}

class RealArkWebProxyBackend implements WebProxyBackend {
  private webEngineReady: boolean = false;

  initializeWebEngine(): void {
    if (!this.webEngineReady) {
      webview.WebviewController.initializeWebEngine();
      this.webEngineReady = true;
    }
  }

  applyProxyOverride(type: number, proxyRule: string | null): Promise<void> {
    this.initializeWebEngine();
    const config: webview.ProxyConfig = new webview.ProxyConfig();
    if (type === EhProxySelector.TYPE_DIRECT) {
      config.insertDirectRule(webview.ProxySchemeFilter.MATCH_ALL_SCHEMES);
    } else if (proxyRule !== null && proxyRule.length > 0) {
      config.insertProxyRule(proxyRule, webview.ProxySchemeFilter.MATCH_ALL_SCHEMES);
    } else {
      return this.removeProxyOverride();
    }
    return new Promise<void>((resolve): void => {
      let done: boolean = false;
      const finish = (): void => {
        if (!done) {
          done = true;
          clearTimeout(timer);
          resolve();
        }
      };
      const timer: number = setTimeout((): void => {
        hilog.warn(DOMAIN, TAG, 'applyProxyOverride timed out after %{public}dms', OVERRIDE_TIMEOUT_MS);
        finish();
      }, OVERRIDE_TIMEOUT_MS) as number;
      try {
        webview.ProxyController.applyProxyOverride(config, (): void => {
          finish();
        });
      } catch (e) {
        hilog.warn(DOMAIN, TAG, 'applyProxyOverride threw: %{public}s', describeNetworkError(e as Object));
        finish();
      }
    });
  }

  removeProxyOverride(): Promise<void> {
    this.initializeWebEngine();
    return new Promise<void>((resolve): void => {
      let done: boolean = false;
      const finish = (): void => {
        if (!done) {
          done = true;
          clearTimeout(timer);
          resolve();
        }
      };
      const timer: number = setTimeout((): void => {
        hilog.warn(DOMAIN, TAG, 'removeProxyOverride timed out after %{public}dms', OVERRIDE_TIMEOUT_MS);
        finish();
      }, OVERRIDE_TIMEOUT_MS) as number;
      try {
        webview.ProxyController.removeProxyOverride((): void => {
          finish();
        });
      } catch (e) {
        hilog.warn(DOMAIN, TAG, 'removeProxyOverride threw: %{public}s', describeNetworkError(e as Object));
        finish();
      }
    });
  }
}

/**
 * 统一将 Settings 中的应用内代理配置同步给 `@kit.ArkWeb` 的全局 `ProxyController`。
 * 所有在线 WebView 页面必须在 `Web(...)` 加载 URL 前 await `syncFromSettings()`。
 */
export class ArkWebProxyManager {
  private static sBackend: WebProxyBackend = new RealArkWebProxyBackend();
  private static sPendingChain: Promise<boolean> = Promise.resolve(true);

  static setBackendForTest(backend: WebProxyBackend | null): void {
    ArkWebProxyManager.sBackend = backend === null ? new RealArkWebProxyBackend() : backend;
  }

  /** 根据 Proxy 类型、主机和端口构造 Chromium/ArkWeb 代理规则串；`SYSTEM` 或非法配置返回 null。 */
  static buildProxyRule(type: number, ip: string | null, port: number): string | null {
    if (type === EhProxySelector.TYPE_DIRECT) {
      return 'DIRECT';
    }
    if (type === EhProxySelector.TYPE_SYSTEM) {
      return null;
    }
    const rawHost: string = ip === null ? '' : ip.trim();
    if (rawHost.length === 0 || port <= 0 || port > 65535) {
      return null;
    }
    const cleanHost: string = rawHost.startsWith('[') && rawHost.endsWith(']')
      ? rawHost.substring(1, rawHost.length - 1)
      : rawHost;
    const authorityHost: string = cleanHost.indexOf(':') >= 0 ? `[${cleanHost}]` : cleanHost;
    if (type === EhProxySelector.TYPE_HTTP) {
      return `http://${authorityHost}:${port}`;
    }
    if (type === EhProxySelector.TYPE_SOCKS) {
      return `socks://${authorityHost}:${port}`;
    }
    return null;
  }

  static syncFromSettings(): Promise<boolean> {
    const next: Promise<boolean> = ArkWebProxyManager.sPendingChain.then(
      (): Promise<boolean> => ArkWebProxyManager.applyNow(),
      (): Promise<boolean> => ArkWebProxyManager.applyNow()
    );
    ArkWebProxyManager.sPendingChain = next;
    return next;
  }

  private static async applyNow(): Promise<boolean> {
    const type: number = Settings.getProxyType();
    const ip: string | null = Settings.getProxyIp();
    const port: number = Settings.getProxyPort();
    const rule: string | null = ArkWebProxyManager.buildProxyRule(type, ip, port);
    try {
      if (type === EhProxySelector.TYPE_DIRECT) {
        await ArkWebProxyManager.sBackend.applyProxyOverride(type, 'DIRECT');
        hilog.info(DOMAIN, TAG, 'ArkWeb proxy synced: DIRECT');
        return true;
      }
      if (rule !== null) {
        await ArkWebProxyManager.sBackend.applyProxyOverride(type, rule);
        hilog.info(DOMAIN, TAG, 'ArkWeb proxy synced: rule=%{public}s', rule);
        return true;
      }
      await ArkWebProxyManager.sBackend.removeProxyOverride();
      hilog.info(DOMAIN, TAG, 'ArkWeb proxy synced: SYSTEM (override removed)');
      return true;
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'syncFromSettings failed: %{public}s', describeNetworkError(e as Object));
      return false;
    }
  }
}
