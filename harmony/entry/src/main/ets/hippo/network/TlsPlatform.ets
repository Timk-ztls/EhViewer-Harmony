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
 * 平台删除说明（不是代码，是判定记录）—— 三个 Android TLS 兼容层
 *
 *   inventory S0436  network/EhSSLSocketFactory.java          (414 行)
 *   inventory S0437  network/EhSSLSocketFactoryLowSDK.java     (73 行)
 *   inventory S0442  network/Tls12SocketFactory.java           (68 行)
 *
 * ## 它们在上游做什么
 * Android 4.4 及更早的系统 TLS 栈默认不启用 TLS 1.2。这三个类是当年的「打开 TLS 1.2 并
 * 允许老协议回退」补丁：反射拿 `SSLSocketFactory` 的内部 delegate、按 SDK 版本选择
 * `SSLContext.getInstance("TLSv1.2")` / `setEnabledProtocols`、套一层 TrustManager。
 *
 * ## 为什么本层不做等价移植
 * 1. **HarmonyOS 的系统 TLS 栈默认 TLS 1.2/1.3**，不存在「需要手动开 1.2」的场景；
 *    `@ohos.net.socket` 的 `TLSConnectOptions` 也没有「自定义 SSLSocketFactory」这种扩展点，
 *    只有 `secureOptions`（证书校验策略）与 `ALPNProtocols`。
 * 2. 上游这三个类**全部是 `SSLSocketFactory` 子类 / 包装器**，其 API 形状（
 *    `createSocket(Socket, host, port, autoClose)`）在 ArkTS 侧没有对应物。硬造一个同名类
 *    只会得到一个「名字一样、行为为空」的假等价物。
 * 3. 真正需要保留的**行为**只有两个，且已经在别处落地：
 *    - 「接受任意证书」→ `EhX509TrustManager.ets`（S0438，已移植）
 *    - 「优先 HTTP/1.1 并显式指定 ALPN」→ `okhttp/Http1SocketTransport.ets` 里的
 *      `ALPNProtocols: ['http/1.1']`（已落地）
 *
 * ## 验收口径
 * 这三条按 **平台删除** 记入验收公式的扣减项（`(portted - 死代码) / (总数 - 死代码 - 平台删除)`），
 * 相关 inventory 行标 `na` 并在 MR 描述里列出，不计入 ported。
 *
 * ## 如果将来需要更强等价
 * 唯一有意义的补法是：在 TLS 接线处把「证书校验策略」做成可注入对象
 * （`secureOptions` 的 `certificate` / `remoteValidation`），并由 `EhX509TrustManager`
 * 提供「全信任」策略。这属于接线层的选择，不是本类的移植。
 */
export const TLS_PLATFORM_DELETED: string[] = [
  'network/EhSSLSocketFactory.java',
  'network/EhSSLSocketFactoryLowSDK.java',
  'network/Tls12SocketFactory.java'
];

/** 行为等价物对照（供验收核对，不参与运行）。 */
export class TlsPlatformEquivalence {
  static readonly ACCEPT_ANY_CERT: string = 'EhX509TrustManager.ets（S0438）';
  static readonly ALPN_HTTP1: string = 'okhttp/Http1SocketTransport.ets（ALPNProtocols: [\'http/1.1\'])';
}
