/**
 * `GalleryListClient` —— 把 net-parse 的真实请求层接到 ui-scene 的 `EhClientLike` 契约上。
 *
 * 复用 `AppWiring.OkHttpCallerAdapter`，并按 `ListUrlBuilder` / `EhEngine.getGalleryList`
 * 统一使用 **0 基页码**（`page === 0` 表示第一页，不拼 `?page=`；`page > 0` 拼 `page=${page}`）。
 */
import { hilog } from '@kit.PerformanceAnalysisKit';
import { EhEngine, HttpCaller } from '../ehviewer/client/EhEngine';
import { OkHttpClient } from '../okhttp/OkHttpClient';
import { describeNetworkError, toNetworkError } from '../okhttp/Dns';
import { EhUrl } from '../ehviewer/client/EhUrl';
import { EhUtils } from '../ehviewer/client/EhUtils';
import { ListUrlBuilder } from '../ehviewer/client/data/ListUrlBuilder';
import { CategoryFlags } from '../ehviewer/client/data/Flags';
import { GalleryInfo } from '../ehviewer/client/data/GalleryInfo';
import { ListResult } from '../ehviewer/client/parser/GalleryListParser';
import { OkHttpCallerAdapter } from '../AppWiring';
import { EhClientLike, EhClientMetaProvider } from '../ehviewer/ui/scene/gallery/list/GalleryListScene';

/** 与 `GalleryListScene.ets` 的 `EhClientLike` 同构，保留向后兼容导出。 */
export interface GalleryListClientLike {
  getGalleryList(url: string, page: number): Promise<GalleryInfo[] | null>;
}

export class GalleryListClient implements EhClientLike, EhClientMetaProvider, GalleryListClientLike {
  private readonly caller: HttpCaller;
  private lastError: string = '';
  private totalPages: number = 0;
  private lastBaseUrl: string = '';
  private nextPageHref: string = '';
  private lastLoadedPage: number = -1;
  private pageUrlCache: Map<number, string> = new Map<number, string>();
  private morePagesAvailable: boolean = false;

  constructor(client: OkHttpClient | (() => OkHttpClient)) {
    this.caller = new OkHttpCallerAdapter(client);
  }

  getLastError(): string {
    return this.lastError;
  }

  getTotalPages(): number {
    return this.totalPages;
  }

  hasMorePages(): boolean {
    return this.morePagesAvailable;
  }

  /**
   * 请求第 `page` 页（**0 基**，与 `GalleryListScene.pageIndex` 及 `ListUrlBuilder` 一致）。
   * 空结果返回 `[]`；失败时记录 `lastError` 并抛出异常（绝不静默吞错）。
   */
  async getGalleryList(url: string, page: number): Promise<GalleryInfo[] | null> {
    this.lastError = '';
    if (url.length === 0) {
      this.lastError = 'Gallery list URL is empty';
      throw new Error(this.lastError);
    }
    if (page <= 0 || url !== this.lastBaseUrl) {
      this.lastBaseUrl = url;
      this.nextPageHref = '';
      this.lastLoadedPage = -1;
      this.pageUrlCache.clear();
      this.morePagesAvailable = false;
    }
    const cachedTarget: string | undefined = page > 0 ? this.pageUrlCache.get(page) : undefined;
    const target: string = cachedTarget !== undefined ? cachedTarget : GalleryListClient.withPage(url, page);
    const mode: number = GalleryListClient.parsingMode(target);
    try {
      const r: ListResult = await EhEngine.getGalleryList(null, this.caller, target, mode);
      this.totalPages = r.pages;
      this.nextPageHref = r.nextHref;
      this.lastLoadedPage = page;
      if (r.nextHref.length > 0) {
        this.pageUrlCache.set(page + 1, r.nextHref);
      }
      this.morePagesAvailable = r.nextHref.length > 0 || (r.pages > 0 && page + 1 < r.pages);
      hilog.info(0x0000, 'GalleryListClient',
        'getGalleryList: url=%{public}s page=%{public}d -> items=%{public}d pages=%{public}d '
          + 'customError="%{public}s" noWatchedTags=%{public}s',
        target, page, r.galleryInfoList.length, r.pages, r.customErrorString, String(r.noWatchedTags));

      if (r.customErrorString.length > 0) {
        this.lastError = r.customErrorString;
        throw new Error(r.customErrorString);
      }

      if (r.galleryInfoList.length === 0) {
        hilog.warn(0x0000, 'GalleryListClient',
          'getGalleryList 返回空列表：pages=%{public}d noWatchedTags=%{public}s',
          r.pages, String(r.noWatchedTags));
      }
      return r.galleryInfoList;
    } catch (e) {
      const msg: string = describeNetworkError(e as Object);
      this.lastError = msg;
      hilog.error(0x0000, 'GalleryListClient',
        'getGalleryList failed: url=%{public}s page=%{public}d err=%{public}s',
        target, page, msg);
      throw toNetworkError(e as Object);
    }
  }

  /**
   * 把 **0 基页码** 拼进 URL（对齐 `ListUrlBuilder.applyCommonQueries`：`pageIndex === 0` 时不拼）。
   */
  static withPage(url: string, page: number): string {
    if (page <= 0) {
      return url;
    }
    if (url.indexOf('/popular') >= 0) {
      return url;
    }
    const pageIdx: number = Math.trunc(page);
    if (url.indexOf('/tag/') >= 0 || url.indexOf('/uploader/') >= 0) {
      const pathMatch: RegExpMatchArray | null = url.match(/^(.*\/(?:tag|uploader)\/[^/?#]+?)(?:\/\d+)?([?#].*)?$/);
      if (pathMatch !== null && pathMatch[1] !== undefined) {
        const suffix: string = pathMatch[2] !== undefined ? pathMatch[2] : '';
        return `${pathMatch[1]}/${pageIdx}${suffix}`;
      }
    }
    if (/([?&])page=\d+/.test(url)) {
      return url.replace(/([?&])page=\d+/, '$1page=' + pageIdx.toString());
    }
    const sep: string = url.indexOf('?') >= 0 ? '&' : '?';
    return `${url}${sep}page=${pageIdx}`;
  }

  private static parsingMode(url: string): number {
    if (url.indexOf('toplist') >= 0) {
      return ListUrlBuilder.MODE_TOP_LIST;
    }
    if (url.indexOf('watched') >= 0 || url.indexOf('subscription') >= 0) {
      return ListUrlBuilder.MODE_SUBSCRIPTION;
    }
    if (url.indexOf('/popular') >= 0) {
      return ListUrlBuilder.MODE_WHATS_HOT;
    }
    if (url.indexOf('/tag/') >= 0) {
      return ListUrlBuilder.MODE_TAG;
    }
    if (url.indexOf('/uploader/') >= 0) {
      return ListUrlBuilder.MODE_UPLOADER;
    }
    return ListUrlBuilder.MODE_NORMAL;
  }

  /** 列表首页 URL（`ListUrlBuilder` MODE_NORMAL -> `EhUrl.getHost()`，而非账户统计页 `home.php`）。 */
  static homeUrl(): string {
    return GalleryListClient.buildHomeUrl(0);
  }

  static buildHomeUrl(pageIndex: number = 0): string {
    const builder: ListUrlBuilder = new ListUrlBuilder();
    builder.setMode(ListUrlBuilder.MODE_NORMAL);
    builder.setPageIndex(pageIndex < 0 ? 0 : Math.trunc(pageIndex));
    return builder.build();
  }

  static popularUrl(): string {
    return GalleryListClient.buildPopularUrl();
  }

  static buildPopularUrl(): string {
    const builder: ListUrlBuilder = new ListUrlBuilder();
    builder.setMode(ListUrlBuilder.MODE_WHATS_HOT);
    return builder.build();
  }

  static buildSearchUrl(keyword: string, category: number = CategoryFlags.NONE, pageIndex: number = 0): string {
    const builder: ListUrlBuilder = new ListUrlBuilder();
    builder.setMode(ListUrlBuilder.MODE_NORMAL);
    const trimmed: string = keyword.trim();
    builder.setKeyword(trimmed.length > 0 ? trimmed : null);
    builder.setCategory(category);
    builder.setPageIndex(pageIndex < 0 ? 0 : Math.trunc(pageIndex));
    return builder.build();
  }

  /** 将 `EhUtils.getCategoryColor(category)`（有符号 32 位 ARGB）格式化为 `#AARRGGBB`。 */
  static formatCategoryColor(category: number): string {
    const argb: number = EhUtils.getCategoryColor(category);
    const hex: string = (argb >>> 0).toString(16).padStart(8, '0').toUpperCase();
    return '#' + hex;
  }

  static formatCategoryLabel(category: number): string {
    return EhUtils.getCategoryByValue(category).toUpperCase();
  }
}
