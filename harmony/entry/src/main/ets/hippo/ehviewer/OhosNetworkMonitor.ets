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

export type NetworkRecoveryListener = (epoch: number) => void;

/**
 * 基于 `@ohos.net.connection` 的系统 VPN 与网络变化监视器。
 *
 * - 当系统激活 VPN（`NetBearType.BEARER_VPN`）且应用内代理为 SYSTEM/DIRECT 时，
 *   自动旁路内置 Hosts / Domain Fronting / DoH，避免硬编码 IP 直连绕过 VPN 分流规则。
 * - 当网络切换或应用回到前台时，通知上层重建连接池、刷新 ArkWeb 代理，并以 400ms 防抖派发恢复事件。
 */
export class OhosNetworkMonitor {
  static readonly NETWORK_RECOVERY_DEBOUNCE_MS: number = 400;
  static readonly OFFLINE_SIGNATURE: string = 'offline';

  private static sTestVpnOverride: boolean | null = null;
  private static sTestCellularOverride: boolean | null = null;
  private static sTestWifiOrEthernetOverride: boolean | null = null;
  private static sTestSignatureOverride: string | null = null;
  private static sNetConn: connection.NetConnection | null = null;
  private static sLastVpnActive: boolean = false;
  private static sLastNetworkSignature: string = '';
  private static sSignatureInitialized: boolean = false;
  private static sPendingChangedSinceLastEmit: boolean = false;
  private static sRecoveryEpoch: number = 0;
  private static sRecoveryTimerId: number = -1;
  private static readonly sRecoveryListeners: Set<NetworkRecoveryListener> = new Set<NetworkRecoveryListener>();

  static setVpnActiveOverrideForTest(value: boolean | null): void {
    OhosNetworkMonitor.sTestVpnOverride = value;
  }

  static setCellularActiveOverrideForTest(value: boolean | null): void {
    OhosNetworkMonitor.sTestCellularOverride = value;
  }

  static setWifiOrEthernetActiveOverrideForTest(value: boolean | null): void {
    OhosNetworkMonitor.sTestWifiOrEthernetOverride = value;
  }

  static setTestSignatureOverride(sig: string | null): void {
    OhosNetworkMonitor.sTestSignatureOverride = sig;
  }

  static classifyWifiOrEthernetBearers(
    defaultBearers: number[] | null | undefined,
    allNetBearers?: number[][]
  ): boolean {
    if (defaultBearers !== undefined && defaultBearers !== null) {
      let sawCellularInDefault: boolean = false;
      for (let i = 0; i < defaultBearers.length; i++) {
        const b: number = defaultBearers[i];
        if (b === connection.NetBearType.BEARER_WIFI || b === connection.NetBearType.BEARER_ETHERNET) {
          return true;
        }
        if (b === connection.NetBearType.BEARER_CELLULAR) {
          sawCellularInDefault = true;
        }
      }
      if (sawCellularInDefault) {
        return false;
      }
    }
    if (allNetBearers !== undefined && allNetBearers !== null) {
      for (let i = 0; i < allNetBearers.length; i++) {
        const list: number[] = allNetBearers[i];
        for (let j = 0; j < list.length; j++) {
          const b: number = list[j];
          if (b === connection.NetBearType.BEARER_WIFI || b === connection.NetBearType.BEARER_ETHERNET) {
            return true;
          }
        }
      }
    }
    return false;
  }

  static isWifiOrEthernetActive(): boolean {
    if (OhosNetworkMonitor.sTestWifiOrEthernetOverride !== null) {
      return OhosNetworkMonitor.sTestWifiOrEthernetOverride;
    }
    if (OhosNetworkMonitor.sTestCellularOverride === true) {
      return false;
    }
    let defaultBearers: number[] = [];
    try {
      const defNet: connection.NetHandle = connection.getDefaultNetSync();
      if (defNet !== undefined && defNet !== null && defNet.netId > 0) {
        const defCaps: connection.NetCapabilities = connection.getNetCapabilitiesSync(defNet);
        if (defCaps !== undefined && defCaps !== null && Array.isArray(defCaps.bearerTypes)) {
          defaultBearers = defCaps.bearerTypes;
        }
      }
    } catch (e) {
      hilog.debug(DOMAIN, TAG, 'probe default net wifi/eth failed: %{public}s',
        describeNetworkError(e as Object));
    }
    for (let i = 0; i < defaultBearers.length; i++) {
      const b: number = defaultBearers[i];
      if (b === connection.NetBearType.BEARER_WIFI || b === connection.NetBearType.BEARER_ETHERNET) {
        return true;
      }
      if (b === connection.NetBearType.BEARER_CELLULAR) {
        return false;
      }
    }
    const allBearers: number[][] = [];
    try {
      const allNets: connection.NetHandle[] = connection.getAllNetsSync();
      if (Array.isArray(allNets)) {
        for (let i = 0; i < allNets.length; i++) {
          const handle: connection.NetHandle = allNets[i];
          if (handle === undefined || handle === null || handle.netId <= 0) {
            continue;
          }
          const caps: connection.NetCapabilities = connection.getNetCapabilitiesSync(handle);
          if (caps !== undefined && caps !== null && Array.isArray(caps.bearerTypes)) {
            allBearers.push(caps.bearerTypes);
          }
        }
      }
    } catch (e) {
      hilog.debug(DOMAIN, TAG, 'probe all nets wifi/eth failed: %{public}s',
        describeNetworkError(e as Object));
    }
    return OhosNetworkMonitor.classifyWifiOrEthernetBearers(defaultBearers, allBearers);
  }

  static classifyCellularBearers(
    defaultBearers: number[] | null | undefined,
    allNetBearers?: number[][]
  ): boolean {
    let sawCellularInDefault: boolean = false;
    if (defaultBearers !== undefined && defaultBearers !== null) {
      for (let i = 0; i < defaultBearers.length; i++) {
        const b: number = defaultBearers[i];
        if (b === connection.NetBearType.BEARER_WIFI || b === connection.NetBearType.BEARER_ETHERNET) {
          return false;
        }
        if (b === connection.NetBearType.BEARER_CELLULAR) {
          sawCellularInDefault = true;
        }
      }
      if (sawCellularInDefault) {
        return true;
      }
    }
    if (allNetBearers !== undefined && allNetBearers !== null) {
      let sawCellularInAll: boolean = false;
      for (let i = 0; i < allNetBearers.length; i++) {
        const list: number[] = allNetBearers[i];
        for (let j = 0; j < list.length; j++) {
          const b: number = list[j];
          if (b === connection.NetBearType.BEARER_WIFI || b === connection.NetBearType.BEARER_ETHERNET) {
            return false;
          }
          if (b === connection.NetBearType.BEARER_CELLULAR) {
            sawCellularInAll = true;
          }
        }
      }
      return sawCellularInAll;
    }
    return false;
  }

  static isCellularActive(): boolean {
    if (OhosNetworkMonitor.sTestCellularOverride !== null) {
      return OhosNetworkMonitor.sTestCellularOverride;
    }
    let defaultBearers: number[] = [];
    try {
      const defNet: connection.NetHandle = connection.getDefaultNetSync();
      if (defNet !== undefined && defNet !== null && defNet.netId > 0) {
        const defCaps: connection.NetCapabilities = connection.getNetCapabilitiesSync(defNet);
        if (defCaps !== undefined && defCaps !== null && Array.isArray(defCaps.bearerTypes)) {
          defaultBearers = defCaps.bearerTypes;
        }
      }
    } catch (e) {
      hilog.debug(DOMAIN, TAG, 'probe default net cellular failed: %{public}s',
        describeNetworkError(e as Object));
    }
    for (let i = 0; i < defaultBearers.length; i++) {
      const b: number = defaultBearers[i];
      if (b === connection.NetBearType.BEARER_WIFI || b === connection.NetBearType.BEARER_ETHERNET) {
        return false;
      }
      if (b === connection.NetBearType.BEARER_CELLULAR) {
        return true;
      }
    }
    const allBearers: number[][] = [];
    try {
      const allNets: connection.NetHandle[] = connection.getAllNetsSync();
      if (Array.isArray(allNets)) {
        for (let i = 0; i < allNets.length; i++) {
          const handle: connection.NetHandle = allNets[i];
          if (handle === undefined || handle === null || handle.netId <= 0) {
            continue;
          }
          const caps: connection.NetCapabilities = connection.getNetCapabilitiesSync(handle);
          if (caps !== undefined && caps !== null && Array.isArray(caps.bearerTypes)) {
            allBearers.push(caps.bearerTypes);
          }
        }
      }
    } catch (e) {
      hilog.debug(DOMAIN, TAG, 'probe all nets cellular failed: %{public}s',
        describeNetworkError(e as Object));
    }
    return OhosNetworkMonitor.classifyCellularBearers(defaultBearers, allBearers);
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

  private static appendSortedUniqueNumbers(src: number[] | null | undefined, target: number[], excludeVpn: boolean): void {
    if (src === undefined || src === null) {
      return;
    }
    for (let i = 0; i < src.length; i++) {
      const v: number = src[i];
      if (!Number.isFinite(v)) {
        continue;
      }
      if (excludeVpn && v === connection.NetBearType.BEARER_VPN) {
        continue;
      }
      if (target.indexOf(v) < 0) {
        target.push(v);
      }
    }
  }

  static buildNetworkSignature(
    defaultNetId: number,
    defaultBearers: number[] | null | undefined,
    vpnActive: boolean,
    allNetBearers?: number[][],
    linkAddresses?: string[]
  ): string {
    const defaultList: number[] = [];
    OhosNetworkMonitor.appendSortedUniqueNumbers(defaultBearers, defaultList, false);
    defaultList.sort((a: number, b: number): number => a - b);

    const underlyingList: number[] = [];
    OhosNetworkMonitor.appendSortedUniqueNumbers(defaultBearers, underlyingList, true);
    if (allNetBearers !== undefined && allNetBearers !== null) {
      for (let i = 0; i < allNetBearers.length; i++) {
        OhosNetworkMonitor.appendSortedUniqueNumbers(allNetBearers[i], underlyingList, true);
      }
    }
    underlyingList.sort((a: number, b: number): number => a - b);

    const addrList: string[] = [];
    if (linkAddresses !== undefined && linkAddresses !== null) {
      for (let i = 0; i < linkAddresses.length; i++) {
        const addr: string = linkAddresses[i];
        if (addr.length > 0 && addrList.indexOf(addr) < 0) {
          addrList.push(addr);
        }
      }
    }
    addrList.sort();

    if (defaultNetId <= 0 && defaultList.length === 0 && underlyingList.length === 0 && !vpnActive) {
      return OhosNetworkMonitor.OFFLINE_SIGNATURE;
    }
    return `net=${defaultNetId}|b=${defaultList.join(',')}|vpn=${vpnActive ? 1 : 0}|u=${underlyingList.join(',')}|ip=${addrList.join(',')}`;
  }

  static computeCurrentNetworkSignature(): string {
    if (OhosNetworkMonitor.sTestSignatureOverride !== null) {
      return OhosNetworkMonitor.sTestSignatureOverride;
    }
    let defaultNetId: number = 0;
    let defaultBearers: number[] = [];
    const linkAddresses: string[] = [];
    try {
      const defNet: connection.NetHandle = connection.getDefaultNetSync();
      if (defNet !== undefined && defNet !== null && defNet.netId > 0) {
        defaultNetId = defNet.netId;
        const defCaps: connection.NetCapabilities = connection.getNetCapabilitiesSync(defNet);
        if (defCaps !== undefined && defCaps !== null && Array.isArray(defCaps.bearerTypes)) {
          defaultBearers = defCaps.bearerTypes;
        }
        try {
          const props: connection.ConnectionProperties = connection.getConnectionPropertiesSync(defNet);
          if (props !== undefined && props !== null && Array.isArray(props.linkAddresses)) {
            for (let i = 0; i < props.linkAddresses.length; i++) {
              const la: connection.LinkAddress = props.linkAddresses[i];
              if (la !== undefined && la !== null && la.address !== undefined && la.address !== null &&
                typeof la.address.address === 'string' && la.address.address.length > 0) {
                linkAddresses.push(la.address.address);
              }
            }
          }
        } catch (propErr) {
          hilog.debug(DOMAIN, TAG, 'probe connection props failed: %{public}s',
            describeNetworkError(propErr as Object));
        }
      }
    } catch (e) {
      hilog.debug(DOMAIN, TAG, 'computeCurrentNetworkSignature default net failed: %{public}s',
        describeNetworkError(e as Object));
    }

    const allBearers: number[][] = [];
    try {
      const allNets: connection.NetHandle[] = connection.getAllNetsSync();
      if (Array.isArray(allNets)) {
        for (let i = 0; i < allNets.length; i++) {
          const handle: connection.NetHandle = allNets[i];
          if (handle === undefined || handle === null || handle.netId <= 0) {
            continue;
          }
          const caps: connection.NetCapabilities = connection.getNetCapabilitiesSync(handle);
          if (caps !== undefined && caps !== null && Array.isArray(caps.bearerTypes)) {
            allBearers.push(caps.bearerTypes);
          }
        }
      }
    } catch (e) {
      hilog.debug(DOMAIN, TAG, 'computeCurrentNetworkSignature all nets failed: %{public}s',
        describeNetworkError(e as Object));
    }

    const vpnActive: boolean = OhosNetworkMonitor.isVpnActive();
    return OhosNetworkMonitor.buildNetworkSignature(
      defaultNetId,
      defaultBearers,
      vpnActive,
      allBearers,
      linkAddresses
    );
  }

  static addNetworkRecoveryListener(listener: NetworkRecoveryListener): void {
    OhosNetworkMonitor.sRecoveryListeners.add(listener);
  }

  static removeNetworkRecoveryListener(listener: NetworkRecoveryListener): void {
    OhosNetworkMonitor.sRecoveryListeners.delete(listener);
  }

  static getRecoveryEpoch(): number {
    return OhosNetworkMonitor.sRecoveryEpoch;
  }

  static resetRecoveryForTest(): void {
    if (OhosNetworkMonitor.sRecoveryTimerId !== -1) {
      clearTimeout(OhosNetworkMonitor.sRecoveryTimerId);
      OhosNetworkMonitor.sRecoveryTimerId = -1;
    }
    OhosNetworkMonitor.sRecoveryListeners.clear();
    OhosNetworkMonitor.sLastNetworkSignature = '';
    OhosNetworkMonitor.sSignatureInitialized = false;
    OhosNetworkMonitor.sPendingChangedSinceLastEmit = false;
    OhosNetworkMonitor.sRecoveryEpoch = 0;
    OhosNetworkMonitor.sTestSignatureOverride = null;
  }

  static notifyNetworkSignatureForRecovery(
    nextSig: string,
    debounceMs: number = OhosNetworkMonitor.NETWORK_RECOVERY_DEBOUNCE_MS
  ): boolean {
    if (!OhosNetworkMonitor.sSignatureInitialized) {
      OhosNetworkMonitor.sSignatureInitialized = true;
      OhosNetworkMonitor.sLastNetworkSignature = nextSig;
      OhosNetworkMonitor.sPendingChangedSinceLastEmit = false;
      return false;
    }
    if (nextSig === OhosNetworkMonitor.OFFLINE_SIGNATURE) {
      if (OhosNetworkMonitor.sLastNetworkSignature !== OhosNetworkMonitor.OFFLINE_SIGNATURE) {
        OhosNetworkMonitor.sLastNetworkSignature = OhosNetworkMonitor.OFFLINE_SIGNATURE;
        OhosNetworkMonitor.sPendingChangedSinceLastEmit = true;
      }
      if (OhosNetworkMonitor.sRecoveryTimerId !== -1) {
        clearTimeout(OhosNetworkMonitor.sRecoveryTimerId);
        OhosNetworkMonitor.sRecoveryTimerId = -1;
      }
      return false;
    }
    const changed: boolean = nextSig !== OhosNetworkMonitor.sLastNetworkSignature ||
      OhosNetworkMonitor.sPendingChangedSinceLastEmit;
    if (!changed) {
      return false;
    }
    OhosNetworkMonitor.sLastNetworkSignature = nextSig;
    OhosNetworkMonitor.sPendingChangedSinceLastEmit = true;
    if (OhosNetworkMonitor.sRecoveryTimerId !== -1) {
      clearTimeout(OhosNetworkMonitor.sRecoveryTimerId);
      OhosNetworkMonitor.sRecoveryTimerId = -1;
    }
    const waitMs: number = debounceMs > 0 ? debounceMs : 0;
    OhosNetworkMonitor.sRecoveryTimerId = setTimeout((): void => {
      OhosNetworkMonitor.sRecoveryTimerId = -1;
      const latestSig: string = OhosNetworkMonitor.sTestSignatureOverride !== null
        ? OhosNetworkMonitor.sTestSignatureOverride
        : OhosNetworkMonitor.sLastNetworkSignature;
      if (latestSig === OhosNetworkMonitor.OFFLINE_SIGNATURE) {
        return;
      }
      OhosNetworkMonitor.sPendingChangedSinceLastEmit = false;
      OhosNetworkMonitor.sRecoveryEpoch++;
      const epoch: number = OhosNetworkMonitor.sRecoveryEpoch;
      hilog.info(DOMAIN, TAG, 'network recovery settled: epoch=%{public}d sig=%{public}s listeners=%{public}d',
        epoch, latestSig, OhosNetworkMonitor.sRecoveryListeners.size);
      const snapshot: NetworkRecoveryListener[] = [];
      OhosNetworkMonitor.sRecoveryListeners.forEach((cb: NetworkRecoveryListener): void => {
        snapshot.push(cb);
      });
      for (let i = 0; i < snapshot.length; i++) {
        try {
          snapshot[i](epoch);
        } catch (cbErr) {
          hilog.warn(DOMAIN, TAG, 'network recovery listener failed: %{public}s',
            describeNetworkError(cbErr as Object));
        }
      }
    }, waitMs) as number;
    return true;
  }

  static checkAndScheduleRecovery(
    debounceMs: number = OhosNetworkMonitor.NETWORK_RECOVERY_DEBOUNCE_MS
  ): boolean {
    const nextSig: string = OhosNetworkMonitor.computeCurrentNetworkSignature();
    return OhosNetworkMonitor.notifyNetworkSignatureForRecovery(nextSig, debounceMs);
  }

  static start(onChange: () => void): void {
    OhosNetworkMonitor.stop();
    OhosNetworkMonitor.sLastVpnActive = OhosNetworkMonitor.isVpnActive();
    OhosNetworkMonitor.sLastNetworkSignature = OhosNetworkMonitor.computeCurrentNetworkSignature();
    OhosNetworkMonitor.sSignatureInitialized = true;
    OhosNetworkMonitor.sPendingChangedSinceLastEmit = false;
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
    if (OhosNetworkMonitor.sRecoveryTimerId !== -1) {
      clearTimeout(OhosNetworkMonitor.sRecoveryTimerId);
      OhosNetworkMonitor.sRecoveryTimerId = -1;
    }
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

/** 会话内按蜂窝周期去重的移动网络提示守卫：连接 Wi-Fi / 以太网时自动重置（对应 upstream MainActivity.checkCellularNetwork 扩展）。 */
export class CellularNetworkWarningGuard {
  private static sWarnedThisSession: boolean = false;
  private static sListener: (() => void) | null = null;

  static syncNetworkState(): void {
    if (OhosNetworkMonitor.isWifiOrEthernetActive()) {
      CellularNetworkWarningGuard.sWarnedThisSession = false;
    }
  }

  static shouldWarnNow(): boolean {
    CellularNetworkWarningGuard.syncNetworkState();
    if (OhosNetworkMonitor.isWifiOrEthernetActive()) {
      return false;
    }
    if (CellularNetworkWarningGuard.sWarnedThisSession) {
      return false;
    }
    if (!Settings.getCellularNetworkWarning()) {
      return false;
    }
    if (!OhosNetworkMonitor.isCellularActive()) {
      return false;
    }
    CellularNetworkWarningGuard.sWarnedThisSession = true;
    return true;
  }

  static hasWarnedThisSession(): boolean {
    return CellularNetworkWarningGuard.sWarnedThisSession;
  }

  static setWarningListener(listener: (() => void) | null): void {
    CellularNetworkWarningGuard.sListener = listener;
  }

  static checkAndNotify(): boolean {
    CellularNetworkWarningGuard.syncNetworkState();
    const listener: (() => void) | null = CellularNetworkWarningGuard.sListener;
    if (listener === null) {
      return false;
    }
    if (!CellularNetworkWarningGuard.shouldWarnNow()) {
      return false;
    }
    listener();
    return true;
  }

  static resetForTest(): void {
    CellularNetworkWarningGuard.sWarnedThisSession = false;
    CellularNetworkWarningGuard.sListener = null;
    OhosNetworkMonitor.setWifiOrEthernetActiveOverrideForTest(null);
  }
}
