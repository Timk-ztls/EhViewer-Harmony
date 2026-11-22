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
import { Request } from './Request';
import { ResponseBody } from './ResponseBody';

/** 协议枚举，对应 OkHttp 的 Protocol。 */
export enum Protocol {
  HTTP_1_0 = 'http/1.0',
  HTTP_1_1 = 'http/1.1',
  HTTP_2 = 'h2'
}

/**
 * okhttp3.Response 等价层。
 *
 * 上游用到的面：
 *   response.code()                                  全部调用点
 *   response.headers()                               全部调用点
 *   response.headers("Set-Cookie")                   EhApplication WebView cookie 同步
 *   response.headers().get("Content-Disposition")    EhEngine.doThrowException（种马图鉴）
 *   response.body() / response.body().string()       全部调用点
 *   response.request().url()                          EhEngine.imageSearch / downloadArchiver
 *
 * 重载处理：OkHttp 的 `headers()` 与 `headers(String)` 同名，ArkTS 不支持重载 →
 *   headers()          → 全部响应头
 *   headersOf(name)    → 指定名字的全部值（等价 headers(String)）
 */
export class Response {
  private readonly _request: Request;
  private readonly _protocol: Protocol;
  private readonly _code: number;
  private readonly _message: string;
  private readonly _headers: Headers;
  private readonly _body: ResponseBody | null;
  private readonly _receivedResponseAtMillis: number;
  /** 命中本地缓存时的原始响应（OkHttp 的 cacheResponse() 语义）。 */
  private readonly _cacheResponse: Response | null;

  constructor(request: Request, protocol: Protocol, code: number, message: string, headers: Headers,
    body: ResponseBody | null, cacheResponse: Response | null = null,
    receivedResponseAtMillis: number = Date.now()) {
    this._request = request;
    this._protocol = protocol;
    this._code = code;
    this._message = message;
    this._headers = headers;
    this._body = body;
    this._cacheResponse = cacheResponse;
    this._receivedResponseAtMillis = receivedResponseAtMillis;
  }

  request(): Request {
    return this._request;
  }

  protocol(): Protocol {
    return this._protocol;
  }

  code(): number {
    return this._code;
  }

  message(): string {
    return this._message;
  }

  headers(): Headers {
    return this._headers;
  }

  /** 等价 OkHttp 的 headers(String name): List<String>。 */
  headersOf(name: string): string[] {
    return this._headers.values(name);
  }

  body(): ResponseBody | null {
    return this._body;
  }

  /** 对齐 Response.isSuccessful()：200..299。 */
  isSuccessful(): boolean {
    return this._code >= 200 && this._code <= 299;
  }

  /** 对齐 Response.isRedirect()：300..399。imageSearch 依赖 302 分支。 */
  isRedirect(): boolean {
    return this._code >= 300 && this._code <= 399;
  }

  cacheResponse(): Response | null {
    return this._cacheResponse;
  }

  receivedResponseAtMillis(): number {
    return this._receivedResponseAtMillis;
  }

  close(): void {
    if (this._body !== null) {
      this._body.close();
    }
  }

  /** 对齐 Response.newBuilder()，用于缓存层重建 304 响应。 */
  newBuilder(): ResponseBuilder {
    const b: ResponseBuilder = new ResponseBuilder();
    b.request(this._request);
    b.protocol(this._protocol);
    b.code(this._code);
    b.message(this._message);
    b.headers(this._headers);
    b.body(this._body);
    b.cacheResponse(this._cacheResponse);
    b.receivedResponseAtMillis(this._receivedResponseAtMillis);
    return b;
  }

  toString(): string {
    return `Response{protocol=${this._protocol}, code=${this._code}, message=${this._message}, ` +
      `url=${this._request.url().toString()}}`;
  }
}

/** okhttp3.Response.Builder 等价。 */
export class ResponseBuilder {
  private _request: Request | null = null;
  private _protocol: Protocol = Protocol.HTTP_1_1;
  private _code: number = -1;
  private _message: string = '';
  private _headers: Headers = new HeadersBuilder().build();
  private _body: ResponseBody | null = null;
  private _cacheResponse: Response | null = null;
  private _receivedResponseAtMillis: number = -1;

  request(request: Request): ResponseBuilder {
    this._request = request;
    return this;
  }

  protocol(protocol: Protocol): ResponseBuilder {
    this._protocol = protocol;
    return this;
  }

  code(code: number): ResponseBuilder {
    this._code = code;
    return this;
  }

  message(message: string): ResponseBuilder {
    this._message = message;
    return this;
  }

  headers(headers: Headers): ResponseBuilder {
    this._headers = headers;
    return this;
  }

  header(name: string, value: string): ResponseBuilder {
    this._headers = this._headers.newBuilder().set(name, value).build();
    return this;
  }

  addHeader(name: string, value: string): ResponseBuilder {
    this._headers = this._headers.newBuilder().add(name, value).build();
    return this;
  }

  removeHeader(name: string): ResponseBuilder {
    this._headers = this._headers.newBuilder().remove(name).build();
    return this;
  }

  body(body: ResponseBody | null): ResponseBuilder {
    this._body = body;
    return this;
  }

  cacheResponse(cacheResponse: Response | null): ResponseBuilder {
    this._cacheResponse = cacheResponse;
    return this;
  }

  receivedResponseAtMillis(millis: number): ResponseBuilder {
    this._receivedResponseAtMillis = millis;
    return this;
  }

  build(): Response {
    if (this._request === null) {
      throw new Error('request == null');
    }
    if (this._code < 0) {
      throw new Error('code < 0');
    }
    const receivedAt: number = this._receivedResponseAtMillis >= 0
      ? this._receivedResponseAtMillis : Date.now();
    return new Response(this._request, this._protocol, this._code, this._message,
      this._headers, this._body, this._cacheResponse, receivedAt);
  }
}
