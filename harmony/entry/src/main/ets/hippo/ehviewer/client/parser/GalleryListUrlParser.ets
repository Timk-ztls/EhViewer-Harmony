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

import { ListUrlBuilder } from '../data/ListUrlBuilder';
import { EhUrl } from '../EhUrl';

/**
 * 1:1 对位 upstream: app/src/main/java/com/hippo/ehviewer/client/parser/GalleryListUrlParser.java
 * （inventory S0100，134 行）
 *
 * 反向解析：把一个列表页 URL 还原成 `ListUrlBuilder` 的状态（用于「从外部链接跳转到搜索」）。
 *
 * 四种路径形态：
 *   `/` 或空        → MODE_NORMAL，query 交给 setQuery
 *   `/uploader/<名>` → MODE_UPLOADER + keyword（URLDecoder 解码，空则 null）
 *   `/tag/<标签>`    → MODE_TAG + keyword
 *   `/<分类数字>`    → MODE_NORMAL + setQuery + setCategory
 * 其它 → null；域名不在三站之内 → null；URL 非法 → null
 *
 * 注意：分类数字走的是 `setCategory` **直接赋值**（不是取反掩码），因为上游这里
 * 处理的是 `/<cats>` 这种「已经是掩码值」的路径。
 */
export class GalleryListUrlParser {
  private static readonly VALID_HOSTS: string[] = [
    EhUrl.DOMAIN_EX, EhUrl.DOMAIN_E, EhUrl.DOMAIN_LOFI
  ];
  private static readonly PATH_NORMAL: string = '/';
  private static readonly PATH_UPLOADER: string = '/uploader/';
  private static readonly PATH_TAG: string = '/tag/';

  static parse(urlStr: string): ListUrlBuilder | null {
    // 对齐 java.net.URL 的最小子集：scheme://host[:port]/path?query
    const m: RegExpMatchArray | null =
      urlStr.match(/^([a-zA-Z][a-zA-Z0-9+.\-]*):\/\/([^/?#]+)([^?#]*)(?:\?([^#]*))?/);
    if (m === null) {
      return null;
    }
    const hostPort: string = m[2];
    const host: string = hostPort.indexOf(':') >= 0 ? hostPort.substring(0, hostPort.indexOf(':')) : hostPort;
    if (GalleryListUrlParser.VALID_HOSTS.indexOf(host) < 0) {
      return null;
    }
    const path: string = m[3] === undefined || m[3] === null ? '' : m[3];
    const query: string | null = m[4] === undefined ? null : m[4];

    if (path === GalleryListUrlParser.PATH_NORMAL || path.length === 0) {
      const builder: ListUrlBuilder = new ListUrlBuilder();
      builder.setQuery(query);
      return builder;
    } else if (path.startsWith(GalleryListUrlParser.PATH_UPLOADER)) {
      return GalleryListUrlParser.parseUploader(path);
    } else if (path.startsWith(GalleryListUrlParser.PATH_TAG)) {
      return GalleryListUrlParser.parseTag(path);
    } else if (path.startsWith('/')) {
      const category: number = Number.parseInt(path.substring(1), 10);
      if (Number.isNaN(category)) {
        return null;
      }
      const builder: ListUrlBuilder = new ListUrlBuilder();
      builder.setQuery(query);
      builder.setCategory(category);
      return builder;
    }
    return null;
  }

  private static parseUploader(path: string): ListUrlBuilder | null {
    const prefixLength: number = GalleryListUrlParser.PATH_UPLOADER.length;
    const index: number = path.indexOf('/', prefixLength);
    let uploader: string = index < 0 ? path.substring(prefixLength) : path.substring(prefixLength, index);
    uploader = GalleryListUrlParser.decode(uploader);
    if (uploader.length === 0) {
      return null;
    }
    const builder: ListUrlBuilder = new ListUrlBuilder();
    builder.setMode(ListUrlBuilder.MODE_UPLOADER);
    builder.setKeyword(uploader);
    return builder;
  }

  private static parseTag(path: string): ListUrlBuilder | null {
    const prefixLength: number = GalleryListUrlParser.PATH_TAG.length;
    const index: number = path.indexOf('/', prefixLength);
    let tag: string = index < 0 ? path.substring(prefixLength) : path.substring(prefixLength, index);
    tag = GalleryListUrlParser.decode(tag);
    if (tag.length === 0) {
      return null;
    }
    const builder: ListUrlBuilder = new ListUrlBuilder();
    builder.setMode(ListUrlBuilder.MODE_TAG);
    builder.setKeyword(tag);
    return builder;
  }

  /** 对齐 `URLDecoder.decode(s, "utf-8")`：'+' → 空格，非法转义原样保留。 */
  private static decode(s: string): string {
    const plus: string = s.split('+').join(' ');
    try {
      return decodeURIComponent(plus);
    } catch (e) {
      return plus;
    }
  }
}
