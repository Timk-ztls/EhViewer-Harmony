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

import { Headers, HeadersBuilder } from './Headers';
import { HttpUrl } from './HttpUrl';
import { MediaType } from './MediaType';
import { MultipartBody } from './MultipartBody';
import { RequestBody } from './RequestBody';

/**
 * okhttp3.Request 等价层。
 *
 * 上游用法：
 *   new Request.Builder().url(url).build()                        EhTagDatabase.save
 *   new EhRequestBuilder(url).post(body).build()                  EhEngine 全量
 *   new EhRequestBuilder(url, referer, origin)                    EhEngine.imageSearch / getGalleryDetail
 *   request.header(...) / request.method() / request.url()
 *
 * 命名差异（ArkTS 不支持嵌套类）：OkHttp 的 `Request.Builder` → 本层 `RequestBuilder`，
 * 调用点写 `new RequestBuilder(url)`；`ChromeRequestBuilder extends Request.Builder`
 * 相应改为 `extends RequestBuilder`。方法的链式形状与名字保持不变。
 */
export class Request {
  private readonly _url: HttpUrl;
  private readonly _method: string;
  private readonly _headers: Headers;
  private readonly _body: RequestBody | null;
  private readonly _tag: string | null;
  private readonly _disallowRedirectFollow: boolean;

  constructor(url: HttpUrl, method: string, headers: Headers, body: RequestBody | null,
    tag: string | null = null, disallowRedirectFollow: boolean = false) {
    this._url = url;
    this._method = method;
    this._headers = headers;
    this._body = body;
    this._tag = tag;
    this._disallowRedirectFollow = disallowRedirectFollow;
  }

  url(): HttpUrl {
    return this._url;
  }

  method(): string {
    return this._method;
  }

  headers(): Headers {
    return this._headers;
  }

  body(): RequestBody | null {
    return this._body;
  }

  /** 对齐 Request.header(String)：取第一个匹配值。 */
  header(name: string): string | null {
    return this._headers.get(name);
  }

  headersOrEmpty(name: string): string[] {
    return this._headers.values(name);
  }

  isHttps(): boolean {
    return this._url.isHttps();
  }

  tag(): string | null {
    return this._tag;
  }

  /** 本地标记：不改变传输引擎选路，仅要求 RedirectInterceptor 与反劫持逻辑拒绝 3xx 跳转。 */
  disallowRedirectFollow(): boolean {
    return this._disallowRedirectFollow;
  }

  newBuilder(): RequestBuilder {
    const b: RequestBuilder = new RequestBuilder();
    b.url(this._url);
    b.methodWithBody(this._method, this._body);
    let i = 0;
    while (i < this._headers.size()) {
      b.addHeader(this._headers.name(i), this._headers.value(i));
      i++;
    }
    if (this._tag !== null) {
      b.tag(this._tag);
    }
    if (this._disallowRedirectFollow) {
      b.disallowRedirectFollow(true);
    }
    return b;
  }

  toString(): string {
    return `Request{method=${this._method}, url=${this._url.toString()}}`;
  }
}

/** okhttp3.Request.Builder 等价。 */
export class RequestBuilder {
  private _url: HttpUrl | null = null;
  private _method: string = 'GET';
  private _headers: HeadersBuilder = new HeadersBuilder();
  private _body: RequestBody | null = null;
  private _tag: string | null = null;
  private _disallowRedirectFollow: boolean = false;

  /** 对齐 url(String)。上游 ChromeRequestBuilder 用 `url.split("/")[2]` 取 host，故这里必须能接受字符串。 */
  url(url: string | HttpUrl): RequestBuilder {
    if (typeof url === 'string') {
      const parsed: HttpUrl | null = HttpUrl.parse(url as string);
      if (parsed === null) {
        throw new Error(`unexpected url: ${url as string}`);
      }
      this._url = parsed;
    } else {
      this._url = url as HttpUrl;
    }
    return this;
  }

  header(name: string, value: string): RequestBuilder {
    this._headers.set(name, value);
    return this;
  }

  addHeader(name: string, value: string): RequestBuilder {
    this._headers.add(name, value);
    return this;
  }

  removeHeader(name: string): RequestBuilder {
    this._headers.remove(name);
    return this;
  }

  headers(headers: Headers): RequestBuilder {
    this._headers = new HeadersBuilder().addAll(headers);
    return this;
  }

  get(): RequestBuilder {
    return this.methodWithBody('GET', null);
  }

  head(): RequestBuilder {
    return this.methodWithBody('HEAD', null);
  }

  post(body: RequestBody): RequestBuilder {
    if (body === null || body === undefined) {
      throw new Error('body == null');
    }
    return this.methodWithBody('POST', body);
  }

  delete(body: RequestBody | null = null): RequestBuilder {
    return this.methodWithBody('DELETE', body);
  }

  put(body: RequestBody): RequestBuilder {
    if (body === null || body === undefined) {
      throw new Error('body == null');
    }
    return this.methodWithBody('PUT', body);
  }

  /** 对齐 method(String, RequestBody)。 */
  methodWithBody(method: string, body: RequestBody | null): RequestBuilder {
    const upper: string = method.toUpperCase();
    if (upper === 'POST' || upper === 'PUT' || upper === 'PATCH' || upper === 'PROPPATCH' ||
      upper === 'REPORT') {
      if (body === null) {
        throw new Error(`method ${upper} must have a request body.`);
      }
    } else if (upper === 'GET' || upper === 'HEAD') {
      if (body !== null) {
        throw new Error(`method ${upper} must not have a request body.`);
      }
    }
    this._method = upper;
    this._body = body;
    return this;
  }

  tag(tag: string): RequestBuilder {
    this._tag = tag;
    return this;
  }

  /** 标记该请求不允许 RedirectInterceptor 跟随 3xx（不影响底层是否走 SystemHttpTransport）。 */
  disallowRedirectFollow(value: boolean = true): RequestBuilder {
    this._disallowRedirectFollow = value;
    return this;
  }

  build(): Request {
    if (this._url === null) {
      throw new Error('url == null');
    }
    let headers: Headers = this._headers.build();
    // 有 body 且没显式给 Content-Type 时补上（与 OkHttp 的 BridgeInterceptor 行为一致）
    if (this._body !== null && headers.get('Content-Type') === null) {
      const ct: string | null = RequestBuilder.contentTypeOf(this._body);
      if (ct !== null) {
        headers = headers.newBuilder().add('Content-Type', ct).build();
      }
    }
    if (this._body !== null && headers.get('Content-Length') === null) {
      const len: number = this._body.contentLength();
      if (len >= 0) {
        headers = headers.newBuilder().add('Content-Length', `${len}`).build();
      }
    }
    return new Request(this._url, this._method, headers, this._body, this._tag,
      this._disallowRedirectFollow);
  }

  private static contentTypeOf(body: RequestBody): string | null {
    // MultipartBody 必须带 boundary，故优先用它自己的头
    if (body instanceof MultipartBody) {
      return body.contentTypeHeader();
    }
    const mt: MediaType | null = body.contentType();
    return mt === null ? null : mt.toString();
  }
}
