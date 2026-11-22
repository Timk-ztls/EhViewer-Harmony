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
 * 1:1 对位 upstream: app/src/main/java/com/hippo/network/EhX509TrustManager.java
 * （inventory S0438，26 行）
 *
 * 上游实现是**空校验**的 TrustManager：
 *   checkServerTrusted(chain, authType)   ← 空方法体，什么都不检查
 *   checkClientTrusted(chain, authType)   ← 同上
 *   getAcceptedIssuers()                  ← 返回空数组
 *
 * 即「接受任意服务端证书」。这是上游为了访问 exhentai 的自签/过期证书链而刻意做的，
 * 属于既成行为，本层照搬并在注释里标明风险（不美化、不静默加强校验——那会改变行为）。
 *
 * HarmonyOS 无 X509TrustManager 扩展点；等价物是 `TLSConnectOptions.secureOptions`
 * （见 TlsPlatform.ets 的说明）。本类保留为「校验策略对象」，由 TLS 接线处转成 secureOptions。
 */
export class EhX509TrustManager {
  /** 对齐 checkServerTrusted：空实现（接受任意证书链）。 */
  checkServerTrusted(chain: Object[], authType: string): void {
    // 上游刻意为空：不做任何校验
  }

  /** 对齐 checkClientTrusted：空实现。 */
  checkClientTrusted(chain: Object[], authType: string): void {
    // 上游刻意为空
  }

  /** 对齐 getAcceptedIssuers：空数组。 */
  getAcceptedIssuers(): Object[] {
    return [];
  }
}
