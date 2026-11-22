/*
 * Copyright 2015 Hippo Seven
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

import { InetValidator } from '../../network/InetValidator';

/**
 * 1:1 对位 upstream: app/src/main/java/com/hippo/ehviewer/client/EhConfig.java
 * （inventory S0071，756 行 / 实测 831 行含注释）
 *
 * 「Some configurable stuff about EH. It ends up cookie.」
 * 全部字段最终序列化成一个 uconfig cookie 发给服务端（顺序固定、用 '-' 分隔、字段名用上游短键）。
 *
 * **本文件是分类位（MISC/DOUJINSHI/…/ALL_CATEGORY）与 namespace 位的权威定义**，
 * download-sync 的 `filterDownloadKind`、ui-widget 的 `AdvanceSearchTable` 都按这里的数值对齐。
 * `client/data/Flags.ets` 的 `CategoryFlags` 只是本文件落地前的临时载体，
 * 现在改为 re-export 本文件（消除第二份定义）。
 *
 * ArkTS 映射：
 *   `implements Cloneable` + `clone()` → cloneConfig()（ArkTS 无 Object.clone 协议）
 *   `synchronized`                    → 无锁（单线程假定，同 DiskLruCache）
 *   `null == hahClientPasskey ? ""`   → 显式 null 判断（字段类型保留 `string | null`）
 *   KEY_* 里 22 个 private 短键      → 保留为 private static（uconfig 拼装要用），
 *     其余 public 常量逐个照搬
 */
export class EhConfig {
  /** The Cookie key of uconfig */
  static readonly KEY_UCONFIG: string = 'uconfig';

  private static readonly KEY_LOAD_FROM_HAH: string = 'uh';
  private static readonly KEY_IMAGE_SIZE: string = 'xr';
  private static readonly KEY_SCALE_WIDTH: string = 'rx';
  private static readonly KEY_SCALE_HEIGHT: string = 'ry';
  private static readonly KEY_GALLERY_TITLE: string = 'tl';
  private static readonly KEY_ARCHIVER_DOWNLOAD: string = 'ar';
  private static readonly KEY_LAYOUT_MODE: string = 'dm';
  private static readonly KEY_POPULAR: string = 'prn';
  private static readonly KEY_DEFAULT_CATEGORIES: string = 'cats';
  private static readonly KEY_FAVORITES_SORT: string = 'fs';
  private static readonly KEY_EXCLUDED_NAMESPACES: string = 'xns';
  private static readonly KEY_EXCLUDED_LANGUAGES: string = 'xl';
  private static readonly KEY_RESULT_COUNT: string = 'rc';
  private static readonly KEY_MOUSE_OVER: string = 'lt';
  private static readonly KEY_PREVIEW_SIZE: string = 'ts';
  private static readonly KEY_PREVIEW_ROW: string = 'tr';
  private static readonly KEY_COMMENTS_SORT: string = 'cs';
  private static readonly KEY_COMMENTS_VOTES: string = 'sc';
  private static readonly KEY_TAGS_SORT: string = 'to';
  private static readonly KEY_SHOW_GALLERY_INDEX: string = 'pn';
  private static readonly KEY_HAH_CLIENT_IP_PORT: string = 'hp';
  private static readonly KEY_HAH_CLIENT_PASSKEY: string = 'hk';
  private static readonly KEY_ENABLE_TAG_FLAGGING: string = 'tf';
  private static readonly KEY_ALWAYS_ORIGINAL: string = 'oi';
  private static readonly KEY_MULTI_PAGE: string = 'qb';
  private static readonly KEY_MULTI_PAGE_STYLE: string = 'ms';
  private static readonly KEY_MULTI_PAGE_THUMB: string = 'mt';

  static readonly KEY_LOFI_RESOLUTION: string = 'xres';
  static readonly KEY_CONTENT_WARNING: string = 'nw';

  static readonly LOAD_FROM_HAH_YES: string = 'y';
  static readonly LOAD_FROM_HAH_NO: string = 'n';

  static readonly IMAGE_SIZE_AUTO: string = 'a';
  static readonly IMAGE_SIZE_780X: string = '780';
  /** 2024-09-11 起 980x 被官方退役（上游 @Deprecated 保留常量）。 */
  static readonly IMAGE_SIZE_980X: string = '980';
  static readonly IMAGE_SIZE_1280X: string = '1280';
  static readonly IMAGE_SIZE_1600X: string = '1600';
  static readonly IMAGE_SIZE_2400X: string = '2400';

  private static readonly GALLERY_TITLE_DEFAULT: string = 'r';
  private static readonly GALLERY_TITLE_JAPANESE: string = 'j';

  static readonly ARCHIVER_DOWNLOAD_MAMS: string = '0';
  static readonly ARCHIVER_DOWNLOAD_AAMS: string = '1';
  static readonly ARCHIVER_DOWNLOAD_MAAS: string = '2';
  static readonly ARCHIVER_DOWNLOAD_AAAS: string = '3';

  static readonly LAYOUT_MODE_LIST: string = 'l';
  static readonly LAYOUT_MODE_THUMB: string = 't';

  private static readonly POPULAR_YES: string = 'y';
  private static readonly POPULAR_NO: string = 'n';

  // ---- 分类位（权威定义）----
  static readonly MISC: number = 0x1;
  static readonly DOUJINSHI: number = 0x2;
  static readonly MANGA: number = 0x4;
  static readonly ARTIST_CG: number = 0x8;
  static readonly GAME_CG: number = 0x10;
  static readonly IMAGE_SET: number = 0x20;
  static readonly COSPLAY: number = 0x40;
  static readonly ASIAN_PORN: number = 0x80;
  static readonly NON_H: number = 0x100;
  static readonly WESTERN: number = 0x200;
  static readonly ALL_CATEGORY: number = 0x3ff;

  // ---- namespace 位（xns 用）----
  static readonly NAMESPACES_RECLASS: number = 0x1;
  static readonly NAMESPACES_LANGUAGE: number = 0x2;
  static readonly NAMESPACES_PARODY: number = 0x4;
  static readonly NAMESPACES_CHARACTER: number = 0x8;
  static readonly NAMESPACES_GROUP: number = 0x10;
  static readonly NAMESPACES_ARTIST: number = 0x20;
  static readonly NAMESPACES_MALE: number = 0x40;
  static readonly NAMESPACES_FEMALE: number = 0x80;

  // ---- 语言 × 类型编码（xl 用，格式 <lang>x<type>）----
  static readonly JAPANESE_ORIGINAL: string = '0';
  static readonly JAPANESE_TRANSLATED: string = '1024';
  static readonly JAPANESE_REWRITE: string = '2048';
  static readonly ENGLISH_ORIGINAL: string = '1';
  static readonly ENGLISH_TRANSLATED: string = '1025';
  static readonly ENGLISH_REWRITE: string = '2049';
  static readonly CHINESE_ORIGINAL: string = '10';
  static readonly CHINESE_TRANSLATED: string = '1034';
  static readonly CHINESE_REWRITE: string = '2058';
  static readonly DUTCH_ORIGINAL: string = '20';
  static readonly DUTCH_TRANSLATED: string = '1044';
  static readonly DUTCH_REWRITE: string = '2068';
  static readonly FRENCH_ORIGINAL: string = '30';
  static readonly FRENCH_TRANSLATED: string = '1054';
  static readonly FRENCH_REWRITE: string = '2078';
  static readonly GERMAN_ORIGINAL: string = '40';
  static readonly GERMAN_TRANSLATED: string = '1064';
  static readonly GERMAN_REWRITE: string = '2088';
  static readonly HUNGARIAN_ORIGINAL: string = '50';
  static readonly HUNGARIAN_TRANSLATED: string = '1074';
  static readonly HUNGARIAN_REWRITE: string = '2098';
  static readonly ITALIAN_ORIGINAL: string = '60';
  static readonly ITALIAN_TRANSLATED: string = '1084';
  static readonly ITALIAN_REWRITE: string = '2108';
  static readonly KOREAN_ORIGINAL: string = '70';
  static readonly KOREAN_TRANSLATED: string = '1094';
  static readonly KOREAN_REWRITE: string = '2118';
  static readonly POLISH_ORIGINAL: string = '80';
  static readonly POLISH_TRANSLATED: string = '1104';
  static readonly POLISH_REWRITE: string = '2128';
  static readonly PORTUGUESE_ORIGINAL: string = '90';
  static readonly PORTUGUESE_TRANSLATED: string = '1114';
  static readonly PORTUGUESE_REWRITE: string = '2138';
  static readonly RUSSIAN_ORIGINAL: string = '100';
  static readonly RUSSIAN_TRANSLATED: string = '1124';
  static readonly RUSSIAN_REWRITE: string = '2148';
  static readonly SPANISH_ORIGINAL: string = '110';
  static readonly SPANISH_TRANSLATED: string = '1134';
  static readonly SPANISH_REWRITE: string = '2158';
  static readonly THAI_ORIGINAL: string = '120';
  static readonly THAI_TRANSLATED: string = '1144';
  static readonly THAI_REWRITE: string = '2168';
  static readonly VIETNAMESE_ORIGINAL: string = '130';
  static readonly VIETNAMESE_TRANSLATED: string = '1154';
  static readonly VIETNAMESE_REWRITE: string = '2178';
  static readonly NA_ORIGINAL: string = '254';
  static readonly NA_TRANSLATED: string = '1278';
  static readonly NA_REWRITE: string = '2302';
  static readonly OTHER_ORIGINAL: string = '255';
  static readonly OTHER_TRANSLATED: string = '1279';
  static readonly OTHER_REWRITE: string = '2303';

  private static readonly FAVORITES_SORT_GALLERY_UPDATE_TIME: string = 'p';
  private static readonly FAVORITES_SORT_FAVORITED_TIME: string = 'f';

  static readonly RESULT_COUNT_25: string = '0';
  static readonly RESULT_COUNT_50: string = '1';
  static readonly RESULT_COUNT_100: string = '2';
  static readonly RESULT_COUNT_200: string = '3';

  static readonly MOUSE_OVER_YES: string = 'm';
  static readonly MOUSE_OVER_NO: string = 'p';

  static readonly PREVIEW_SIZE_NORMAL: string = 'm';
  static readonly PREVIEW_SIZE_LARGE: string = 'l';

  static readonly PREVIEW_ROW_4: string = '2';
  static readonly PREVIEW_ROW_10: string = '5';
  static readonly PREVIEW_ROW_20: string = '10';
  static readonly PREVIEW_ROW_40: string = '20';

  static readonly COMMENTS_SORT_OLDEST_FIRST: string = 'a';
  static readonly COMMENTS_SORT_RECENT_FIRST: string = 'd';
  static readonly COMMENTS_SORT_HIGHEST_SCORE_FIRST: string = 's';

  static readonly COMMENTS_VOTES_POP: string = '0';
  static readonly COMMENTS_VOTES_ALWAYS: string = '1';

  static readonly TAGS_SORT_ALPHABETICAL: string = 'a';
  static readonly TAGS_SORT_POWER: string = 'p';

  static readonly SHOW_GALLERY_INDEX_YES: string = '1';
  static readonly SHOW_GALLERY_INDEX_NO: string = '0';

  static readonly ENABLE_TAG_FLAGGING_YES: string = 'y';
  static readonly ENABLE_TAG_FLAGGING_NO: string = 'n';

  static readonly ALWAYS_ORIGINAL_YES: string = 'y';
  static readonly ALWAYS_ORIGINAL_NO: string = 'n';

  static readonly MULTI_PAGE_YES: string = 'y';
  static readonly MULTI_PAGE_NO: string = 'n';

  static readonly MULTI_PAGE_STYLE_N: string = 'n';
  static readonly MULTI_PAGE_STYLE_C: string = 'c';
  static readonly MULTI_PAGE_STYLE_Y: string = 'y';

  static readonly MULTI_PAGE_THUMB_SHOW: string = 'n';
  static readonly MULTI_PAGE_THUMB_HIDE: string = 'y';

  static readonly LOFI_RESOLUTION_460X: string = '1';
  static readonly LOFI_RESOLUTION_780X: string = '2';
  static readonly LOFI_RESOLUTION_980X: string = '3';

  static readonly CONTENT_WARNING_SHOW: string = '0';
  static readonly CONTENT_WARNING_NOT_SHOW: string = '1';

  static readonly UPDATE_PATH: string = 'Ehviewer/Update/';
  static readonly ARCHIVER_PATH: string = 'Ehviewer/Archiver/';
  static readonly TORRENT_PATH: string = 'Ehviewer/Torrent/';

  static readonly ORDER_BY_FAV_TIME: string = 'f';
  static readonly ORDER_BY_PUB_TIME: string = 'p';

  // ---- 实例字段（默认值与上游一致）----
  loadFromHAH: string = EhConfig.LOAD_FROM_HAH_YES;
  imageSize: string = EhConfig.IMAGE_SIZE_AUTO;
  scaleWidth: number = 0;
  scaleHeight: number = 0;
  galleryTitle: string = EhConfig.GALLERY_TITLE_DEFAULT;
  archiverDownload: string = EhConfig.ARCHIVER_DOWNLOAD_MAMS;
  layoutMode: string = EhConfig.LAYOUT_MODE_LIST;
  popular: string = EhConfig.POPULAR_YES;
  defaultCategories: number = 0;
  favoritesSort: string = EhConfig.FAVORITES_SORT_FAVORITED_TIME;
  excludedNamespaces: number = 0;
  excludedLanguages: string = '';
  resultCount: string = EhConfig.RESULT_COUNT_25;
  mouseOver: string = EhConfig.MOUSE_OVER_YES;
  previewSize: string = EhConfig.PREVIEW_SIZE_LARGE;
  previewRow: string = EhConfig.PREVIEW_ROW_4;
  commentSort: string = EhConfig.COMMENTS_SORT_OLDEST_FIRST;
  commentVotes: string = EhConfig.COMMENTS_VOTES_POP;
  tagSort: string = EhConfig.TAGS_SORT_ALPHABETICAL;
  showGalleryIndex: string = EhConfig.SHOW_GALLERY_INDEX_YES;
  hahClientIp: string = '';
  hahClientPort: number = -1;
  hahClientPasskey: string | null = '';
  enableTagFlagging: string = EhConfig.ENABLE_TAG_FLAGGING_NO;
  alwaysOriginal: string = EhConfig.ALWAYS_ORIGINAL_NO;
  multiPage: string = EhConfig.MULTI_PAGE_NO;
  multiPageStyle: string = EhConfig.MULTI_PAGE_STYLE_N;
  multiPageThumb: string = EhConfig.MULTI_PAGE_THUMB_SHOW;
  lofiResolution: string = EhConfig.LOFI_RESOLUTION_980X;
  contentWarning: string = EhConfig.CONTENT_WARNING_NOT_SHOW;

  private _uconfig: string = '';
  private _dirty: boolean = true;

  /** 对齐 clone()。 */
  cloneConfig(): EhConfig {
    const c: EhConfig = new EhConfig();
    c.loadFromHAH = this.loadFromHAH;
    c.imageSize = this.imageSize;
    c.scaleWidth = this.scaleWidth;
    c.scaleHeight = this.scaleHeight;
    c.galleryTitle = this.galleryTitle;
    c.archiverDownload = this.archiverDownload;
    c.layoutMode = this.layoutMode;
    c.popular = this.popular;
    c.defaultCategories = this.defaultCategories;
    c.favoritesSort = this.favoritesSort;
    c.excludedNamespaces = this.excludedNamespaces;
    c.excludedLanguages = this.excludedLanguages;
    c.resultCount = this.resultCount;
    c.mouseOver = this.mouseOver;
    c.previewSize = this.previewSize;
    c.previewRow = this.previewRow;
    c.commentSort = this.commentSort;
    c.commentVotes = this.commentVotes;
    c.tagSort = this.tagSort;
    c.showGalleryIndex = this.showGalleryIndex;
    c.hahClientIp = this.hahClientIp;
    c.hahClientPort = this.hahClientPort;
    c.hahClientPasskey = this.hahClientPasskey;
    c.enableTagFlagging = this.enableTagFlagging;
    c.alwaysOriginal = this.alwaysOriginal;
    c.multiPage = this.multiPage;
    c.multiPageStyle = this.multiPageStyle;
    c.multiPageThumb = this.multiPageThumb;
    c.lofiResolution = this.lofiResolution;
    c.contentWarning = this.contentWarning;
    c._dirty = true;
    return c;
  }

  setDirty(): void {
    this._dirty = true;
  }

  /** 对齐 private updateUconfig()：短键 + '-' 分隔，顺序逐个照搬（服务端按顺序解析）。 */
  private updateUconfig(): void {
    const hahClientIpPort: string =
      (InetValidator.isValidInet4Address(this.hahClientIp) &&
        InetValidator.isValidInetPort(this.hahClientPort))
        ? this.hahClientIp + '%3A' + this.hahClientPort
        : '';
    const passkey: string = this.hahClientPasskey === null ? '' : (this.hahClientPasskey as string);
    this._uconfig = EhConfig.KEY_LOAD_FROM_HAH + '_' + this.loadFromHAH + '-' +
      EhConfig.KEY_IMAGE_SIZE + '_' + this.imageSize + '-' +
      EhConfig.KEY_SCALE_WIDTH + '_' + this.scaleWidth + '-' +
      EhConfig.KEY_SCALE_HEIGHT + '_' + this.scaleHeight + '-' +
      EhConfig.KEY_GALLERY_TITLE + '_' + this.galleryTitle + '-' +
      EhConfig.KEY_ARCHIVER_DOWNLOAD + '_' + this.archiverDownload + '-' +
      EhConfig.KEY_LAYOUT_MODE + '_' + this.layoutMode + '-' +
      EhConfig.KEY_POPULAR + '_' + this.popular + '-' +
      EhConfig.KEY_DEFAULT_CATEGORIES + '_' + this.defaultCategories + '-' +
      EhConfig.KEY_FAVORITES_SORT + '_' + this.favoritesSort + '-' +
      EhConfig.KEY_EXCLUDED_NAMESPACES + '_' + this.excludedNamespaces + '-' +
      EhConfig.KEY_EXCLUDED_LANGUAGES + '_' + this.excludedLanguages + '-' +
      EhConfig.KEY_RESULT_COUNT + '_' + this.resultCount + '-' +
      EhConfig.KEY_MOUSE_OVER + '_' + this.mouseOver + '-' +
      EhConfig.KEY_PREVIEW_SIZE + '_' + this.previewSize + '-' +
      EhConfig.KEY_PREVIEW_ROW + '_' + this.previewRow + '-' +
      EhConfig.KEY_COMMENTS_SORT + '_' + this.commentSort + '-' +
      EhConfig.KEY_COMMENTS_VOTES + '_' + this.commentVotes + '-' +
      EhConfig.KEY_TAGS_SORT + '_' + this.tagSort + '-' +
      EhConfig.KEY_SHOW_GALLERY_INDEX + '_' + this.showGalleryIndex + '-' +
      EhConfig.KEY_HAH_CLIENT_IP_PORT + '_' + hahClientIpPort + '-' +
      EhConfig.KEY_HAH_CLIENT_PASSKEY + '_' + passkey + '-' +
      EhConfig.KEY_ENABLE_TAG_FLAGGING + '_' + this.enableTagFlagging + '-' +
      EhConfig.KEY_ALWAYS_ORIGINAL + '_' + this.alwaysOriginal + '-' +
      EhConfig.KEY_MULTI_PAGE + '_' + this.multiPage + '-' +
      EhConfig.KEY_MULTI_PAGE_STYLE + '_' + this.multiPageStyle + '-' +
      EhConfig.KEY_MULTI_PAGE_THUMB + '_' + this.multiPageThumb;
  }

  /** 对齐 uconfig()：脏则重算，返回 cookie 值。 */
  uconfig(): string {
    if (this._dirty) {
      this._dirty = false;
      this.updateUconfig();
    }
    return this._uconfig;
  }
}
