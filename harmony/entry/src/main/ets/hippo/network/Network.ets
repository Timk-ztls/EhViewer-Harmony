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

/**
 * 1:1 对位 upstream: app/src/main/java/com/hippo/network/Network.java
 * （inventory S0440，35 行）
 *
 * 唯一职责：取当前活动网络的类型（Android 的 `NetworkInfo.getType()`，无网时 -1）。
 *
 * HarmonyOS 等价：`@ohos.net.connection` 的 `connection.getDefaultNetSync()` +
 * `getNetCapabilitiesSync(net)` 里的 `bearerTypes`。上游返回的是 Android 的
 * `ConnectivityManager.TYPE_*` 数值（0=mobile, 1=wifi, …），本层保留同一套数值：
 *   TYPE_MOBILE = 0, TYPE_WIFI = 1, TYPE_MOBILE_DUN = 4, TYPE_MOBILE_HIPRI = 5,
 *   TYPE_WIMAX = 6, TYPE_BLUETOOTH = 7, TYPE_ETHERNET = 9, TYPE_VPN = 17
 *
 * 平台 API 收敛为 `NetworkBackend` 注入点：默认实现返回 -1（等同「无网」），
 * 平台接线时实现一次即可（见 net-parse 的 NetworkBackend 用法说明）。
 */
/**
 * 平台注入点。默认 -1 = 无网（上游在 `activeNetwork == null` 时也返回 -1），
 * 因此未接线时行为等价于「设备离线」而不是「假装有 wifi」——避免上层做出错误的重试决策。
 */
export class NetworkBackend {
  getActiveNetworkType(): number {
    return Network.TYPE_NONE;
  }
}

export class Network {
  static readonly TYPE_MOBILE: number = 0;
  static readonly TYPE_WIFI: number = 1;
  static readonly TYPE_MOBILE_DUN: number = 4;
  static readonly TYPE_MOBILE_HIPRI: number = 5;
  static readonly TYPE_WIMAX: number = 6;
  static readonly TYPE_BLUETOOTH: number = 7;
  static readonly TYPE_ETHERNET: number = 9;
  static readonly TYPE_VPN: number = 17;

  /** 对齐「无活动网络」的返回值。 */
  static readonly TYPE_NONE: number = -1;

  private static _backend: NetworkBackend = new NetworkBackend();

  static setBackend(backend: NetworkBackend): void {
    Network._backend = backend;
  }

  /** 对齐 `getActiveNetworkType(Context)`。 */
  static getActiveNetworkType(): number {
    return Network._backend.getActiveNetworkType();
  }
}

