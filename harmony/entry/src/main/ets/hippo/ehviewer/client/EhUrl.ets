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

import { HttpUrl } from '../../okhttp/HttpUrl';
import { UrlBuilder } from '../../network/UrlBuilder';

/**
 * 1:1 对位 upstream: app/src/main/java/com/hippo/ehviewer/client/EhUrl.java
 * （inventory S0079，275 行 / 实测 320 行含注释）
 *
 * 上游的「核心资产」：站点域名、API 路径、收藏页/排行页/阅读页 URL 构造。
 * 所有 parser 与 EhEngine 都引用它，因此必须先落地（否则每个 parser 会各自内联域名常量）。
 *
 * ArkTS 映射：
 *   `Settings.getGallerySite()`  → EhUrlSiteConfig 注入（默认 SITE_E，与上游默认一致）。
 *     core-runtime 的 Settings 落地后 `EhUrl.setSiteConfig(...)` 一行接线，调用点不变。
 *   常量拼装（HOST_E = REFERER_E + "/" 等）→ 保持同名常量，值逐字符一致。
 *
 * 上游的「怪异但必须保留」之处：
 *   - `getTopListUrl()` 恒返回 **里站也没入口** 的 URL_TOP_LIST_E（上游注释写着「妈的绝了」）
 *   - `getThumbUrlPrefix()` 恒返回 URL_PREFIX_THUMB_E（SITE_EX 分支被注释掉）
 *   - `getThumbKey` 之类不在这里，见 EhCacheKeyFactory
 */
/**
 * EhUrl 的平台依赖注入点（Settings.getGallerySite）。
 * 默认 SITE_E = 上游默认（未登录、未改设置时的行为）。
 */
export class EhUrlSiteConfig {
  getGallerySite(): number {
    return EhUrl.SITE_E;
  }
}

export class EhUrl {
  static readonly SITE_E: number = 0;
  static readonly SITE_EX: number = 1;

  static readonly DOMAIN_EX: string = 'exhentai.org';
  static readonly DOMAIN_E: string = 'e-hentai.org';
  static readonly DOMAIN_LOFI: string = 'lofi.e-hentai.org';

  static readonly REFERER_EX: string = 'https://' + EhUrl.DOMAIN_EX;
  static readonly REFERER_E: string = 'https://' + EhUrl.DOMAIN_E;

  static readonly HOST_EX: string = EhUrl.REFERER_EX + '/';
  static readonly HOST_E: string = EhUrl.REFERER_E + '/';

  static readonly API_SIGN_IN: string = 'https://forums.e-hentai.org/index.php?act=Login&CODE=01';

  static readonly URL_NEWS_E: string = EhUrl.HOST_E + 'news.php';

  static readonly API_E: string = EhUrl.HOST_E + 'api.php';
  static readonly API_EX: string = EhUrl.HOST_EX + 'api.php';

  static readonly HOME_E: string = EhUrl.HOST_E + 'home.php';
  static readonly HOME_EX: string = EhUrl.HOST_EX + 'home.php';

  static readonly URL_POPULAR_E: string = 'https://e-hentai.org/popular';
  static readonly URL_POPULAR_EX: string = 'https://exhentai.org/popular';

  static readonly URL_TOP_LIST_E: string = EhUrl.HOST_E + 'toplist.php';
  static readonly URL_TOP_LIST_EX: string = EhUrl.HOST_EX + 'toplist.php';

  static readonly URL_IMAGE_SEARCH_E: string = 'https://upld.e-hentai.org/image_lookup.php';
  static readonly URL_IMAGE_SEARCH_EX: string = 'https://upld.exhentai.org/upld/image_lookup.php';

  static readonly URL_SIGN_IN: string = 'https://forums.e-hentai.org/index.php?act=Login';
  static readonly URL_REGISTER: string = 'https://forums.e-hentai.org/index.php?act=Reg&CODE=00';
  static readonly URL_FAVORITES_E: string = EhUrl.HOST_E + 'favorites.php';
  static readonly URL_FAVORITES_EX: string = EhUrl.HOST_EX + 'favorites.php';
  static readonly DOMAIN_FORUMS: string = 'forums.e-hentai.org';
  static readonly URL_FORUMS: string = 'https://forums.e-hentai.org/';

  static readonly ORIGIN_EX: string = EhUrl.REFERER_EX;
  static readonly ORIGIN_E: string = EhUrl.REFERER_E;

  static readonly URL_UCONFIG_E: string = EhUrl.HOST_E + 'uconfig.php';
  static readonly URL_UCONFIG_EX: string = EhUrl.HOST_EX + 'uconfig.php';

  static readonly URL_MY_TAGS_E: string = EhUrl.HOST_E + 'mytags';
  static readonly URL_MY_TAGS_EX: string = EhUrl.HOST_EX + 'mytags';

  static readonly URL_WATCHED_E: string = EhUrl.HOST_E + 'watched';
  static readonly URL_WATCHED_EX: string = EhUrl.HOST_EX + 'watched';

  private static readonly URL_PREFIX_THUMB_E: string = 'https://ehgt.org/';
  private static readonly URL_PREFIX_THUMB_EX: string = 'https://exhentai.org/t/';

  /** Settings.getGallerySite() 的注入点（默认 SITE_E，与上游默认一致）。 */
  private static _siteConfig: EhUrlSiteConfig = new EhUrlSiteConfig();

  static setSiteConfig(config: EhUrlSiteConfig): void {
    EhUrl._siteConfig = config;
  }

  /** 当前站点（SITE_E / SITE_EX），供 EhEngine 等需要区分站点结构的调用方使用。 */
  static getGallerySite(): number {
    return EhUrl.site();
  }

  private static site(): number {
    const s: number = EhUrl._siteConfig.getGallerySite();
    return s === EhUrl.SITE_EX ? EhUrl.SITE_EX : EhUrl.SITE_E;
  }

  static getHost(): string {
    return EhUrl.site() === EhUrl.SITE_EX ? EhUrl.HOST_EX : EhUrl.HOST_E;
  }

  static getHomeUrl(): string {
    return EhUrl.HOME_E;
  }

  static getMyTag(): string {
    return EhUrl.site() === EhUrl.SITE_EX ? EhUrl.URL_MY_TAGS_EX : EhUrl.URL_MY_TAGS_E;
  }

  static getFavoritesUrl(): string {
    return EhUrl.site() === EhUrl.SITE_EX ? EhUrl.URL_FAVORITES_EX : EhUrl.URL_FAVORITES_E;
  }

  static getApiUrl(): string {
    return EhUrl.site() === EhUrl.SITE_EX ? EhUrl.API_EX : EhUrl.API_E;
  }

  static getReferer(): string {
    return EhUrl.site() === EhUrl.SITE_EX ? EhUrl.REFERER_EX : EhUrl.REFERER_E;
  }

  static getOrigin(): string {
    return EhUrl.site() === EhUrl.SITE_EX ? EhUrl.ORIGIN_EX : EhUrl.ORIGIN_E;
  }

  static getUConfigUrl(): string {
    return EhUrl.site() === EhUrl.SITE_EX ? EhUrl.URL_UCONFIG_EX : EhUrl.URL_UCONFIG_E;
  }

  static getMyTagsUrl(): string {
    return EhUrl.site() === EhUrl.SITE_EX ? EhUrl.URL_MY_TAGS_EX : EhUrl.URL_MY_TAGS_E;
  }

  /**
   * 对齐 getGalleryDetailUrl(long, String)：单参版本（index=0, allComment=false）。
   * ArkTS 无重载 → 单参版命名 getGalleryDetailUrlSimple。
   */
  static getGalleryDetailUrlSimple(gid: number, token: string): string {
    return EhUrl.getGalleryDetailUrl(gid, token, 0, false);
  }

  /** 对齐 getGalleryDetailUrl(long gid, String token, int index, boolean allComment)。 */
  static getGalleryDetailUrl(gid: number, token: string, index: number, allComment: boolean): string {
    const builder: UrlBuilder = new UrlBuilder(EhUrl.getHost() + 'g/' + gid + '/' + token + '/');
    if (index !== 0) {
      builder.addQuery('p', index);
    }
    if (allComment) {
      builder.addQuery('hc', 1);
    }
    return builder.build();
  }

  /** 对齐 getPageUrl(long gid, int index, String pToken)：注意 index 是 0 基，URL 里 +1。 */
  static getPageUrl(gid: number, index: number, pToken: string): string {
    return EhUrl.getHost() + 's/' + pToken + '/' + gid + '-' + (index + 1);
  }

  static getAddFavorites(gid: number, token: string): string {
    return EhUrl.getHost() + 'gallerypopups.php?gid=' + gid + '&t=' + token + '&act=addfav';
  }

  static getDownloadArchive(gid: number, token: string, or: string): string {
    if (or.length === 0) {
      return EhUrl.getHost() + 'archiver.php?gid=' + gid + '&token=' + token;
    }
    return EhUrl.getHost() + 'archiver.php?gid=' + gid + '&token=' + token + '&or=' + or;
  }

  static getTagDefinitionUrl(tag: string): string {
    return 'https://ehwiki.org/wiki/' + tag.replace(/ /g, '_');
  }

  static getPopularUrl(): string {
    return EhUrl.site() === EhUrl.SITE_EX ? EhUrl.URL_POPULAR_EX : EhUrl.URL_POPULAR_E;
  }

  /** 恒返回 URL_TOP_LIST_E（上游注释：里站没排行榜入口，刻意保留）。 */
  static getTopListUrl(): string {
    return EhUrl.URL_TOP_LIST_E;
  }

  static getEhNewsUrl(): string {
    return EhUrl.URL_NEWS_E;
  }

  static getImageSearchUrl(): string {
    return EhUrl.site() === EhUrl.SITE_EX ? EhUrl.URL_IMAGE_SEARCH_EX : EhUrl.URL_IMAGE_SEARCH_E;
  }

  static getWatchedUrl(): string {
    return EhUrl.site() === EhUrl.SITE_EX ? EhUrl.URL_WATCHED_EX : EhUrl.URL_WATCHED_E;
  }

  /** 恒返回 URL_PREFIX_THUMB_E（上游把 SITE_EX 分支注释掉了）。 */
  static getThumbUrlPrefix(): string {
    return EhUrl.URL_PREFIX_THUMB_E;
  }

  /**
   * 对齐 getFixedPreviewThumbUrl(String)：把「末段以倒数第二段为前缀、且以倒数第三段开头」的
   * 缩略图路径重写到 ehgt.org 前缀。
   * 例：`.../31/7a/317a1a...-250.jpg` → `https://ehgt.org/31/7a/317a1a...-250.jpg`
   * 路径段不足 3 段或前缀关系不成立 → 原样返回。
   */
  static getFixedPreviewThumbUrl(originUrl: string): string {
    const url: HttpUrl | null = HttpUrl.parse(originUrl);
    if (url === null) {
      return originUrl;
    }
    const segs: string[] = url.pathSegments();
    if (segs.length < 3) {
      return originUrl;
    }
    const last: string = segs[segs.length - 1];
    const secondLast: string = segs[segs.length - 2];
    const thirdLast: string = segs[segs.length - 3];
    if (last.startsWith(thirdLast) && last.substring(thirdLast.length).startsWith(secondLast)) {
      return EhUrl.getThumbUrlPrefix() + thirdLast + '/' + secondLast + '/' + last;
    }
    return originUrl;
  }
}

