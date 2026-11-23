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

import connection from '@ohos.net.connection';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { Network, NetworkBackend } from '../network/Network';
import { describeNetworkError } from '../okhttp/Dns';
import { EhProxySelector } from './EhProxySelector';
import { Settings } from './Settings';

const DOMAIN: number = 0x0000;
const TAG: string = 'OhosNetworkMonitor';

/**
 * 基于 `@ohos.net.connection` 的系统 VPN 与网络变化监视器。
 *
 * - 当系统激活 VPN（`NetBearType.BEARER_VPN`）且应用内代理为 SYSTEM/DIRECT 时，
 *   自动旁路内置 Hosts / Domain Fronting / DoH，避免硬编码 IP 直连绕过 VPN 分流规则。
 * - 当网络切换或应用回到前台时，通知上层重建连接池与刷新 ArkWeb 代理。
 */
export class OhosNetworkMonitor {
  private static sTestVpnOverride: boolean | null = null;
  private static sNetConn: connection.NetConnection | null = null;
  private static sLastVpnActive: boolean = false;

  static setVpnActiveOverrideForTest(value: boolean | null): void {
    OhosNetworkMonitor.sTestVpnOverride = value;
  }

  static hasVpnBearer(caps: connection.NetCapabilities | null | undefined): boolean {
    if (caps === undefined || caps === null || !Array.isArray(caps.bearerTypes)) {
      return false;
    }
    for (let i = 0; i < caps.bearerTypes.length; i++) {
      if (caps.bearerTypes[i] === connection.NetBearType.BEARER_VPN) {
        return true;
      }
    }
    return false;
  }

  static isVpnActive(): boolean {
    if (OhosNetworkMonitor.sTestVpnOverride !== null) {
      return OhosNetworkMonitor.sTestVpnOverride;
    }
    try {
      const defNet: connection.NetHandle = connection.getDefaultNetSync();
      if (defNet !== undefined && defNet !== null && defNet.netId > 0) {
        const defCaps: connection.NetCapabilities = connection.getNetCapabilitiesSync(defNet);
        if (OhosNetworkMonitor.hasVpnBearer(defCaps)) {
          return true;
        }
      }
    } catch (e) {
      hilog.debug(DOMAIN, TAG, 'probe default net VPN failed: %{public}s',
        describeNetworkError(e as Object));
    }
    try {
      const allNets: connection.NetHandle[] = connection.getAllNetsSync();
      if (Array.isArray(allNets)) {
        for (let i = 0; i < allNets.length; i++) {
          const handle: connection.NetHandle = allNets[i];
          if (handle === undefined || handle === null || handle.netId <= 0) {
            continue;
          }
          const caps: connection.NetCapabilities = connection.getNetCapabilitiesSync(handle);
          if (OhosNetworkMonitor.hasVpnBearer(caps)) {
            return true;
          }
        }
      }
    } catch (e) {
      hilog.debug(DOMAIN, TAG, 'probe all nets VPN failed: %{public}s',
        describeNetworkError(e as Object));
    }
    return false;
  }

  static shouldBypassBuiltInRouting(): boolean {
    if (!OhosNetworkMonitor.isVpnActive()) {
      return false;
    }
    const proxyType: number = Settings.getProxyType();
    return proxyType === EhProxySelector.TYPE_SYSTEM || proxyType === EhProxySelector.TYPE_DIRECT;
  }

  static refreshNow(): boolean {
    const active: boolean = OhosNetworkMonitor.isVpnActive();
    const changed: boolean = active !== OhosNetworkMonitor.sLastVpnActive;
    OhosNetworkMonitor.sLastVpnActive = active;
    return changed;
  }

  static start(onChange: () => void): void {
    OhosNetworkMonitor.stop();
    OhosNetworkMonitor.sLastVpnActive = OhosNetworkMonitor.isVpnActive();
    try {
      const netConn: connection.NetConnection = connection.createNetConnection();
      netConn.on('netAvailable', (_handle: connection.NetHandle): void => {
        hilog.info(DOMAIN, TAG, 'netAvailable -> refresh network');
        onChange();
      });
      netConn.on('netCapabilitiesChange', (_info: connection.NetCapabilityInfo): void => {
        hilog.info(DOMAIN, TAG, 'netCapabilitiesChange -> refresh network');
        onChange();
      });
      netConn.on('netConnectionPropertiesChange', (_info: connection.NetConnectionPropertyInfo): void => {
        hilog.info(DOMAIN, TAG, 'netConnectionPropertiesChange -> refresh network');
        onChange();
      });
      netConn.on('netLost', (_handle: connection.NetHandle): void => {
        hilog.info(DOMAIN, TAG, 'netLost -> refresh network');
        onChange();
      });
      netConn.register((err: Object): void => {
        if (err !== undefined && err !== null) {
          hilog.warn(DOMAIN, TAG, 'netConnection.register error: %{public}s',
            describeNetworkError(err));
        }
      });
      OhosNetworkMonitor.sNetConn = netConn;
    } catch (e) {
      hilog.warn(DOMAIN, TAG, 'start NetConnection failed: %{public}s',
        describeNetworkError(e as Object));
    }
  }

  static stop(): void {
    const conn: connection.NetConnection | null = OhosNetworkMonitor.sNetConn;
    OhosNetworkMonitor.sNetConn = null;
    if (conn !== null) {
      try {
        conn.unregister((err: Object): void => {
          if (err !== undefined && err !== null) {
            hilog.debug(DOMAIN, TAG, 'netConnection.unregister error: %{public}s',
              describeNetworkError(err));
          }
        });
      } catch (e) {
        hilog.debug(DOMAIN, TAG, 'stop NetConnection failed: %{public}s',
          describeNetworkError(e as Object));
      }
    }
  }
}

/** 接入 `Network.setBackend()` 的 HarmonyOS 实现。 */
export class OhosNetworkBackend extends NetworkBackend {
  getActiveNetworkType(): number {
    if (OhosNetworkMonitor.isVpnActive()) {
      return Network.TYPE_VPN;
    }
    try {
      const defNet: connection.NetHandle = connection.getDefaultNetSync();
      if (defNet === undefined || defNet === null || defNet.netId <= 0) {
        return Network.TYPE_NONE;
      }
      const caps: connection.NetCapabilities = connection.getNetCapabilitiesSync(defNet);
      if (caps === undefined || caps === null || !Array.isArray(caps.bearerTypes)) {
        return Network.TYPE_NONE;
      }
      if (OhosNetworkMonitor.hasVpnBearer(caps)) {
        return Network.TYPE_VPN;
      }
      for (let i = 0; i < caps.bearerTypes.length; i++) {
        switch (caps.bearerTypes[i]) {
          case connection.NetBearType.BEARER_WIFI:
            return Network.TYPE_WIFI;
          case connection.NetBearType.BEARER_CELLULAR:
            return Network.TYPE_MOBILE;
          case connection.NetBearType.BEARER_ETHERNET:
            return Network.TYPE_ETHERNET;
          case connection.NetBearType.BEARER_BLUETOOTH:
            return Network.TYPE_BLUETOOTH;
          default:
            break;
        }
      }
    } catch (e) {
      hilog.debug(DOMAIN, TAG, 'getActiveNetworkType failed: %{public}s',
        describeNetworkError(e as Object));
    }
    return Network.TYPE_NONE;
  }
}
