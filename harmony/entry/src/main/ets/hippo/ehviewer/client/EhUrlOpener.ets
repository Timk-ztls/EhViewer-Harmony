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

import { GalleryDetailUrlParser } from './parser/GalleryDetailUrlParser';
import { GalleryListUrlParser } from './parser/GalleryListUrlParser';
import { GalleryPageUrlParser } from './parser/GalleryPageUrlParser';
import { ListUrlBuilder } from './data/ListUrlBuilder';

/**
 * 1:1 对位 upstream: app/src/main/java/com/hippo/ehviewer/client/EhUrlOpener.kt
 * （inventory S0080，75 行）
 *
 * 「外部链接 → 站内页面」的唯一入口，按优先级依次尝试三个 parser：
 *   1. GalleryListUrlParser  → 列表页（带 ListUrlBuilder）
 *   2. GalleryDetailUrlParser → 详情页（gid + token）
 *   3. GalleryPageUrlParser   → 阅读页（gid + pToken + page）
 * 都不匹配 → null（上游打一条 "Can't parse url: …" 日志）。
 *
 * 上游返回的是 `Announcer`（Android 场景跳转对象，含 Scene class + Bundle）。
 * 本层没有 Scene 体系 → 返回**可判别的目标描述** `OpenTarget`：
 *   kind = 'list' | 'detail' | 'page'，外加对应字段（与 Bundle 的键一一对应，键名常量都在下面）。
 * ui-scene 接线时把 OpenTarget 翻译成自己的路由参数即可，键名保持一致以免二次映射出错。
 */
export class EhUrlOpener {
  /** 与上游 Bundle 键名逐字一致的常量。 */
  static readonly KEY_ACTION: string = 'KEY_ACTION';
  static readonly KEY_LIST_URL_BUILDER: string = 'KEY_LIST_URL_BUILDER';
  static readonly KEY_GID: string = 'KEY_GID';
  static readonly KEY_TOKEN: string = 'KEY_TOKEN';
  static readonly KEY_PTOKEN: string = 'KEY_PTOKEN';
  static readonly KEY_PAGE: string = 'KEY_PAGE';

  static readonly ACTION_LIST_URL_BUILDER: string = 'action_list_url_builder';
  static readonly ACTION_GID_TOKEN: string = 'action_gid_token';
  static readonly ACTION_GALLERY_TOKEN: string = 'action_gallery_token';

  static parseUrl(url: string | null): OpenTarget | null {
    if (url === null || url === undefined || url.length === 0) {
      return null;
    }

    // 1. 列表页（上游 try/catch：解析异常只记日志，继续往下试）
    let listUrlBuilder: ListUrlBuilder | null = null;
    try {
      listUrlBuilder = GalleryListUrlParser.parse(url);
    } catch (e) {
      listUrlBuilder = null;
    }
    if (listUrlBuilder !== null) {
      const target: OpenTarget = new OpenTarget();
      target.kind = 'list';
      target.action = EhUrlOpener.ACTION_LIST_URL_BUILDER;
      target.listUrlBuilder = listUrlBuilder;
      return target;
    }

    // 2. 详情页
    const detail = GalleryDetailUrlParser.parse(url);
    if (detail !== null) {
      const target: OpenTarget = new OpenTarget();
      target.kind = 'detail';
      target.action = EhUrlOpener.ACTION_GID_TOKEN;
      target.gid = detail.gid;
      target.token = detail.token;
      return target;
    }

    // 3. 阅读页
    const page = GalleryPageUrlParser.parse(url);
    if (page !== null) {
      const target: OpenTarget = new OpenTarget();
      target.kind = 'page';
      target.action = EhUrlOpener.ACTION_GALLERY_TOKEN;
      target.gid = page.gid;
      target.pToken = page.pToken;
      target.page = page.page;
      return target;
    }

    return null;
  }
}

/** 对齐上游 `Announcer(Scene.class).setArgs(Bundle)` 的可判别替代。 */
export class OpenTarget {
  kind: string = '';
  action: string = '';
  listUrlBuilder: ListUrlBuilder | null = null;
  gid: number = 0;
  token: string = '';
  pToken: string = '';
  page: number = 0;
}
