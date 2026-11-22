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

/**
 * hippo/okhttp —— OkHttp 3.14.7 的 ArkTS 兼容壳。
 *
 * 为什么需要它：上游 41 个 Gradle 依赖里 OkHttp 渗透到 net-parse / download-sync /
 * storage-db 三个模块（EhEngine 60+ 个调用点、下载器、图片加载器）。ArkTS 侧
 * `@ohos.net.http` 是「一次调用拿完整响应」的 API，没有 Call/Interceptor/CookieJar/Cache
 * 这一层结构。为了让上层 Java/Kotlin 代码可以逐行搬过来（而不是重写业务逻辑），
 * 本层提供同形状的 API：
 *
 *   OkHttpClient.newCall(Request).execute()      → Promise<Response>（调用点 await）
 *   OkHttpClient.newCall(Request).enqueue(Callback)
 *   Interceptor / Interceptor.Chain（proceed 返回 Promise）
 *   CookieJar / Cookie / Cookie.Builder
 *   Cache（磁盘 HTTP 缓存 + CacheInterceptor）
 *   Response.body().string()
 *   FormBody / MultipartBody / RequestBody.createFromFile
 *
 * 命名映射（ArkTS 不支持嵌套类与方法重载，故这两处必须改名，调用点机械替换）：
 *   okhttp3.Request.Builder          → RequestBuilder
 *   okhttp3.FormBody.Builder         → FormBodyBuilder
 *   okhttp3.MultipartBody.Builder    → MultipartBodyBuilder
 *   okhttp3.MediaType                 → MediaType（同名）
 *   Response.headers(String)          → Response.headersOf(name)
 *   RequestBody.create(MediaType, File) → RequestBody.createFromFile(MediaType, path)
 *
 * 传输实现（两套，按需切换，见 OkHttpClient.transportFor）：
 *   SystemHttpTransport（@ohos.net.http）—— 默认，HTTP/2 + TLS + 自动解压 + 系统连接池
 *   Http1SocketTransport（@ohos.net.socket）—— followRedirects=false 时启用，可拿到原始 302
 */
export { Headers, HeadersBuilder } from './Headers';
export { HttpUrl, HttpUrlBuilder } from './HttpUrl';
export { MediaType, MediaTypes } from './MediaType';
export { Request, RequestBuilder } from './Request';
export { RequestBody, StringRequestBody, BytesRequestBody, FileRequestBody } from './RequestBody';
export { FormBody, FormBodyBuilder } from './FormBody';
export { MultipartBody, MultipartBodyBuilder, Part } from './MultipartBody';
export { ResponseBody } from './ResponseBody';
export { Response, ResponseBuilder, Protocol } from './Response';
export { Cookie, CookieBuilder, LongMaxValue } from './Cookie';
export { CookieJar, NoCookies } from './CookieJar';
export { Call, Callback, RealCall } from './Call';
export { Interceptor, Chain, Connection, RealInterceptorChain, LambdaInterceptor, InterceptorEntry, CallAbortController } from './Interceptor';
export { Cache, CacheInterceptor, CacheRecord } from './Cache';
export { ConnectionPool, CloseableSocket } from './ConnectionPool';
export { Dns, OverrideAwareDns, InetAddress, SystemDns, SYSTEM_DNS } from './Dns';
export { Proxy, ProxySelector, ProxyType } from './ProxySelector';
export { OkHttpClient, OkHttpClientBuilder, TimeUnit } from './OkHttpClient';
export { Transport, TransportExecuteOptions, SystemHttpTransport } from './SystemHttpTransport';
export { Http1SocketTransport, RawResponse, ChunkedResult } from './Http1SocketTransport';
export { ChromeRequestBuilder } from './ChromeRequestBuilder';
