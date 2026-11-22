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

import { Request } from '../../okhttp/Request';
import { HttpUrl } from '../../okhttp/HttpUrl';
import { RequestBody, utf8Encode } from '../../okhttp/RequestBody';
import { MediaType } from '../../okhttp/MediaType';
import { Document, Elements, Jsoup } from '../../jsoup/index';
import { FormBody, FormBodyBuilder } from '../../okhttp/FormBody';
import { EhException } from './exception/EhException';
import { CancelledException } from './exception/MarkerExceptions';
import { ParseException } from './exception/ParseException';
import { StatusCodeException } from '../../network/StatusCodeException';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { EhRequestBuilder } from './EhRequestBuilder';
import { EhUrl } from './EhUrl';
import { GalleryInfo } from './data/GalleryInfo';
import { GalleryDetail } from './data/GalleryDetail';
import { EhFilter, FilterLike, FilterStore } from './EhFilter';
import { EhEventParse } from './parser/EhEventParse';
import { FavoritesParser, FavoritesResult } from './parser/FavoritesParser';
import { GalleryDetailParser } from './parser/GalleryDetailParser';
import { GalleryListParser, ListResult } from './parser/GalleryListParser';
import { SignInParser } from './parser/SignInParser';
import { EditCommentResult, GetEditCommentParser } from './parser/GetEditCommentParser';
import { GalleryTokenApiParser } from './parser/GalleryTokenApiParser';
import { TorrentParser } from './parser/TorrentParser';
import { TopListParser } from './parser/TopListParser';
import { ForumsParser } from './parser/ForumsParser';
import { ProfileParser, ProfileResult } from './parser/ProfileParser';
import { VoteCommentParser, VoteCommentResult } from './parser/VoteCommentParser';
import { ArchiveParser, ArchiveResult } from './parser/ArchiveParser';
import { GalleryPageParser, GalleryPageParserResult } from './parser/GalleryPageParser';
import { GalleryPageApiParser, GalleryPageApiParserResult } from './parser/GalleryPageApiParser';
import { GalleryApiParser } from './parser/GalleryApiParser';
import { MyTagLitParser } from './parser/MyTagLitParser';
import { TagPushParam, UserTag, UserTagList } from './data/UserTag';
import { EhNewsDetail } from './data/EhNewsDetail';

import { HomeDetail } from './data/HomeDetail';
import { EhHomeParser } from './parser/EhHomeParser';
import { ArchiverData } from './data/ArchiverData';
import { NoHAtHClientException } from './exception/MarkerExceptions';
import { MultipartBody, MultipartBodyBuilder } from '../../okhttp/MultipartBody';
import { Headers } from '../../okhttp/Headers';
import { ListUrlBuilder } from './data/ListUrlBuilder';
import { EhTopListDetail } from './data/TopList';
import { TorrentInfo } from './data/TorrentInfo';
import { RateGalleryParser, RateGalleryResult } from './parser/RateGalleryParser';
import { GalleryCommentList } from './data/GalleryCommentList';
import { PreviewSet } from './data/PreviewSet';


/** core-runtime 的 Settings / i18n / AppConfig 注入点（默认值与上游默认一致）。 */
export class EhEngineConfig {
  /** 对齐 `Settings.isLogin()`（默认未登录：上游未登录时这两个接口直接返回 null）。 */
  isLogin(): boolean {
    return false;
  }

  getShowGalleryPages(): boolean {
    return false;
  }

  getSaveParseErrorBody(): boolean {
    return false;
  }

  kokomadeTip(): string {
    return 'Kokomade tip';
  }

  errorEmptyHtml(): string {
    return 'Empty html';
  }

  errorParseError(): string {
    return 'Parse error';
  }

  errorIgneousWrong(): string {
    return 'Igneous wrong';
  }

  /** 对齐 `AppConfig.saveParseErrorBody`：默认不写盘（只 warn 一次）。 */
  saveParseErrorBody(e: ParseException): void {
    console.warn('[EhEngine] saveParseErrorBody 未接线：出错页面未落盘。' +
      ` detail=${e.message}`);
  }
}

/** 对齐 `EhApplication.getInstance().showEventPane(html)`。 */
export interface EventPaneHook {
  showEventPane(html: string): void;
}

export class NoopEventPaneHook implements EventPaneHook {
  private static _warned: boolean = false;

  showEventPane(html: string): void {
    if (!NoopEventPaneHook._warned) {
      NoopEventPaneHook._warned = true;
      console.warn('[EhEngine] EventPaneHook 未注入：首页事件条不会显示（html 长度 ' +
        `${html.length}）。`);
    }
  }
}

/**
 * 空过滤器存储（**未注入 FilterStore 时的兜底**）。
 *
 * 审计 L-07：这四条以前是静默 no-op，导致「用户设置的过滤器一条都不生效，且没有任何日志」。
 * 现在 `getAllFilter` 第一次被调用时**打一次 warn**（只打一次，避免刷屏），
 * 让「过滤失效」至少可诊断；真正的存储由 storage-db 的 `EhDB` 通过
 * `EhEngine.setFilterStore(...)` 注入。
 */
class EmptyFilterStore implements FilterStore {
  private static _warned: boolean = false;

  private static warnOnce(): void {
    if (EmptyFilterStore._warned) {
      return;
    }
    EmptyFilterStore._warned = true;
    console.warn('[EhEngine] FilterStore 未注入：本地过滤器（标题/上传者/标签/命名空间）全部不生效，' +
      '用户设置的过滤规则不会落地。请调用 EhEngine.setFilterStore(ehDB) 接线。');
  }

  getAllFilter(): FilterLike[] {
    EmptyFilterStore.warnOnce();
    return [];
  }

  addFilter(filter: FilterLike): void {
    EmptyFilterStore.warnOnce();
  }

  deleteFilter(filter: FilterLike): void {
    EmptyFilterStore.warnOnce();
  }

  triggerFilter(filter: FilterLike): void {
    EmptyFilterStore.warnOnce();
  }
}

/**
 * 1:1 对位 upstream: app/src/main/java/com/hippo/ehviewer/client/EhEngine.java
 * （inventory S0073，1472 行）
 *
 * **分批交付**（Lead 定的策略）：本批是「骨架 + 4 个最简 API」，建立
 * 「API 方法 → RequestBuilder → 执行 → 解析 → 容错」的统一模式，后续批次按 5 个一组填表。
 *
 * 本批内容：
 *   骨架：SAD_PANDA_* / KOKOMADE_URL / MEDIA_TYPE_* / PATTERN_NEED_HATH_CLIENT
 *         `doThrowException` + `throwException`（容错链，纯逻辑可测）
 *         `runApi`（Call → code/headers/body → **解析也在 try 内**，含 task.setCall）
 *   API：`signIn` / `getGalleryList`（含 `fillGalleryList` 过滤与 API 补齐判定）/ `getGalleryDetail`
 *         `getAllFavorites`（不需要 Task 的收藏页全量拉取）
 *
 * 容错链（`doThrowException`）的顺序**就是行为**，逐条照搬：
 *   1. call 已取消 → CancelledException
 *   2. sad panda 三个响应头同时匹配 → EhException("Sad Panda")
 *   3. body 含 kokomade 图 → EhException("今回はここまで\n\n" + i18n)
 *   4. ParseException 三分支：body 无 '<' → 用 body 当消息；body 空 → "empty html"；
 *      否则（可选存盘）+ "parse error"
 *   5. EhException → 原样抛
 *   6. code >= 400 → StatusCodeException(code)
 *   7. 其它 Throwable → 原样抛
 */
export class EhEngine {
  static readonly TAG: string = 'EhEngine';

  private static readonly SAD_PANDA_DISPOSITION: string = 'inline; filename="sadpanda.jpg"';
  private static readonly SAD_PANDA_TYPE: string = 'image/gif';
  private static readonly SAD_PANDA_LENGTH: string = '9615';
  private static readonly KOKOMADE_URL: string = 'https://exhentai.org/img/kokomade.jpg';

  static readonly MEDIA_TYPE_JSON: MediaType = MediaType.parse('application/json; charset=utf-8') as MediaType;
  static readonly MEDIA_TYPE_URLENCODED: MediaType = MediaType.parse('application/x-www-form-urlencoded') as MediaType;

  static readonly PATTERN_NEED_HATH_CLIENT: RegExp =
    /(You must have a H@H client assigned to your account to use this feature\.)/;

  /** 诊断日志域/标签（hilog 常量；与 EhClient 的 0x0000 域一致，便于一起抓）。 */
  static readonly DIAG_DOMAIN: number = 0x0000;
  static readonly DIAG_TAG: string = 'EhEngine';
  /** 可疑短响应的阈值：正常 e-hentai 首页 100 KB 起，低于此值基本不可能是列表页。 */
  static readonly SHORT_BODY_THRESHOLD: number = 10000;

  private static _config: EhEngineConfig = new EhEngineConfig();
  private static _eventPaneHook: EventPaneHook = new NoopEventPaneHook();
  private static _filter: EhFilter | null = null;

  static setConfig(config: EhEngineConfig): void {
    EhEngine._config = config;
  }

  static setEventPaneHook(hook: EventPaneHook): void {
    EhEngine._eventPaneHook = hook;
  }

  /**
   * 注入过滤器存储并重建 `EhFilter`（审计 L-07）。
   *
   * 上游 `EhFilter` 的构造器直接读 `EhDB.getAllFilter()` 按 mode 分四类；
   * ArkTS 侧把「库」抽成 `FilterStore`，由 storage-db 提供实现。
   * 调用点：`AppWiring` 在 EhDB 就绪后注入。
   */
  static setFilterStore(store: FilterStore): void {
    EhEngine._filter = new EhFilter(store);
  }

  /** 对齐 `initialize()`：EhEngine.sEhFilter = EhFilter.getInstance()。 */
  static initialize(filter: EhFilter | null): void {
    EhEngine._filter = filter;
  }

  /** 测试用：当前是否已注入过滤器（区分「注入过」与「用的空存储兜底」）。 */
  static hasFilter(): boolean {
    return EhEngine._filter !== null;
  }

  private static filter(): EhFilter {
    if (EhEngine._filter === null) {
      // 未注入时用空过滤器（等价「没有本地过滤规则」），不崩；EmptyFilterStore 会 warn 一次
      EhEngine._filter = new EhFilter(new EmptyFilterStore());
    }
    return EhEngine._filter as EhFilter;
  }

  // ==================================================================================
  // 骨架：容错链
  // ==================================================================================

  /** 对齐 `doThrowException(...)`：**顺序即行为**，见类注释。 */
  static doThrowException(call: EngineCall, code: number, headers: EngineHeaders | null,
    body: string | null, e: Error | null): void {
    if (call.isCanceled()) {
      throw new CancelledException();
    }
    // sad panda：三个头必须同时匹配
    if (headers !== null
      && EhEngine.SAD_PANDA_DISPOSITION === headers.get('Content-Disposition')
      && EhEngine.SAD_PANDA_TYPE === headers.get('Content-Type')
      && EhEngine.SAD_PANDA_LENGTH === headers.get('Content-Length')) {
      throw new EhException('Sad Panda');
    }
    // kokomade
    if (body !== null && body.indexOf(EhEngine.KOKOMADE_URL) >= 0) {
      throw new EhException('今回はここまで\n\n' + EhEngine._config.kokomadeTip());
    }
    if (e instanceof ParseException) {
      if (body !== null && body.indexOf('<') < 0) {
        throw new EhException(body);
      } else if (body === null || body.length === 0) {
        throw new EhException(EhEngine._config.errorEmptyHtml());
      } else {
        if (EhEngine._config.getSaveParseErrorBody()) {
          EhEngine.saveParseErrorBody(e as ParseException);
        }
        throw new EhException(EhEngine._config.errorParseError());
      }
    }
    if (e instanceof EhException) {
      throw e as EhException;
    }
    if (code >= 400) {
      throw new StatusCodeException(code);
    }
    if (e !== null) {
      throw e;
    }
    // 上游在此**什么都不做**（void 方法自然返回）：容错链走完没命中就不抛
  }

  /** 对齐 `throwException(...)`：只多了一层打印栈，本层同样原样抛。 */
  static throwException(call: EngineCall, code: number, headers: EngineHeaders | null,
    body: string | null, e: Error | null): void {
    EhEngine.doThrowException(call, code, headers, body, e);
  }

  /** 对齐 `AppConfig.saveParseErrorBody`：默认实现（不注入）只打 warn，不写盘。 */
  private static saveParseErrorBody(e: ParseException): void {
    EhEngine._config.saveParseErrorBody(e);
  }

  // ==================================================================================
  // 统一执行：Request → Call → (code, headers, body)
  // ==================================================================================

  /**
   * 统一执行 + 解析：**解析也在 try 内**（这是上游的结构）。
   * 为什么要这样：`GetEditCommentParser` 之类会把 JSON 错误包成 ParseException，
   * 上游的 catch 会用 `throwException` 把 ParseException 变成更贴切的 EhException
   * （body 无 '<' → 消息就是 body）。若解析放在 try 外，就会漏掉这条容错链。
   */
  private static async runApi<T>(task: EngineTask | null, caller: HttpCaller,
    request: Request, handler: (r: EngineCallResult) => T): Promise<T> {
    const call: EngineCall = caller.newCall(request);
    if (task !== null) {
      task.setCall(call);
    }
    const result: EngineCallResult = new EngineCallResult();
    result.call = call;
    try {
      const response: EngineResponse = await call.execute();
      result.code = response.code();
      result.headers = response.headers();
      result.body = response.body();
      return handler(result);
    } catch (e) {
      EhEngine.throwException(call, result.code, result.headers, result.body, e as Error);
      throw e as Error; // ArkTS：throw 只接受 Error 类型
    }
  }

  private static bodyOf(r: EngineCallResult): string {
    return r.body === null ? '' : (r.body as string);
  }

  // ==================================================================================
  // API 1/19：signIn
  // ==================================================================================

  /** 对齐 `signIn(task, okHttpClient, username, password)`。 */
  static async signIn(task: EngineTask | null, caller: HttpCaller,
    username: string, password: string): Promise<string> {
    const url: string = EhUrl.API_SIGN_IN;
    const referer: string = 'https://forums.e-hentai.org/index.php?act=Login&CODE=00';
    const origin: string = 'https://forums.e-hentai.org';
    const request: Request = EhRequestBuilder.ofRefererOrigin(url, referer, origin)
      .post(new FormBodyBuilder()
        .add('UserName', username)
        .add('PassWord', password)
        .add('submit', 'Log me in')
        .add('CookieDate', '1')
        .add('temporary_https', 'off')
        .build())
      .build();
    return EhEngine.runApi(task, caller, request,
      (r: EngineCallResult): string => SignInParser.parse(EhEngine.bodyOf(r)));
  }

  // ==================================================================================
  // API 2/19：getGalleryList（含 fillGalleryList）
  // ==================================================================================

  /** 对齐 `getGalleryList(task, okHttpClient, url, mode)`。 */
  static async getGalleryList(task: EngineTask | null, caller: HttpCaller,
    url: string, mode: number): Promise<ListResult> {
    const referer: string = EhUrl.getReferer();
    const request: Request = EhRequestBuilder.ofReferer(url, referer).build();
    // 解析放在 runApi 的 handler 里（与上游一致：解析异常也走容错链）
    const parsed = await EhEngine.runApi(task, caller, request,
      (r: EngineCallResult): ListParsed => {
        const body: string = EhEngine.bodyOf(r);
        const p: ListParsed = new ListParsed();
        p.result = GalleryListParser.parse(body, mode);
        p.code = r.code;
        p.bodyLength = body.length;
        // 留头 2000 字符：能覆盖 <title> + 页面前几个 <div class=...>，足以区分
        // Cloudflare 挑战页 / 登录页 / 错误页 / 重定向壳
        p.bodyHead = body.length > 2000 ? body.substring(0, 2000) : body;
        return p;
      });
    await EhEngine.fillGalleryList(task, caller, parsed.result.galleryInfoList, url, true);
    if (parsed.code === 200 && url === 'https://exhentai.org/' && parsed.bodyLength === 0) {
      parsed.result.customErrorString = EhEngine._config.errorIgneousWrong();
    }
    // 诊断（真机排查"能启动但列表为空"）：code / bodyLen / 解析出的条数一次打全。
    // 三者缺一不可 —— `items=0 pages=0` 有四种完全不同的原因（parser 不认结构 / 登录页 /
    // 403·509 / body 为空），只有 code + bodyLen 能区分。
    hilog.info(EhEngine.DIAG_DOMAIN, EhEngine.DIAG_TAG,
      'getGalleryList: url=%{public}s code=%{public}d bodyLen=%{public}d items=%{public}d pages=%{public}d',
      url, parsed.code, parsed.bodyLength, parsed.result.galleryInfoList.length, parsed.result.pages);
    // 可疑短响应（正常首页 100 KB 起，<10000 字节基本不可能是列表页）→ 打 body 头
    if (parsed.code !== 200 || parsed.bodyLength < EhEngine.SHORT_BODY_THRESHOLD) {
      // hilog 单条有长度上限，2000 字符会被截断 → 按 500 分片打，带片号
      const chunkSize: number = 500;
      const total: number = Math.ceil(parsed.bodyHead.length / chunkSize);
      for (let i = 0; i < total; i++) {
        const start: number = i * chunkSize;
        const end: number = Math.min(start + chunkSize, parsed.bodyHead.length);
        hilog.warn(EhEngine.DIAG_DOMAIN, EhEngine.DIAG_TAG,
          'getGalleryList body head [%{public}d/%{public}d]: %{public}s',
          i + 1, total, parsed.bodyHead.substring(start, end));
      }
    }
    return parsed.result;
  }

  /**
   * 对齐 `fillGalleryList(task, okHttpClient, list, url, filter)`。
   * 三件事：① 标题/上传者过滤（就地删除）② 判断是否需要调 API 补齐 tags/pages/rated ③ 标签过滤 + 缩略图修正
   */
  static async fillGalleryList(task: EngineTask | null, caller: HttpCaller,
    list: GalleryInfo[], url: string, filter: boolean): Promise<void> {
    const f: EhFilter = EhEngine.filter();
    if (filter) {
      let i: number = 0;
      while (i < list.length) {
        const info: GalleryInfo = list[i];
        if (!f.filterTitle(info) || !f.filterUploader(info)) {
          list.splice(i, 1);
        } else {
          i++;
        }
      }
    }
    let hasTags: boolean = false;
    let hasPages: boolean = false;
    let hasRated: boolean = false;
    for (let i = 0; i < list.length; i++) {
      const gi: GalleryInfo = list[i];
      if (gi.simpleTags !== null) {
        hasTags = true;
      }
      if (gi.pages !== 0) {
        hasPages = true;
      }
      if (gi.rated) {
        hasRated = true;
      }
    }
    const needApi: boolean = (filter && f.needTags() && !hasTags) ||
      (EhEngine._config.getShowGalleryPages() && !hasPages) ||
      hasRated;
    if (needApi) {
      await EhEngine.fillGalleryListByApi(task, caller, list, url);
    }
    if (filter) {
      let i: number = 0;
      while (i < list.length) {
        const info: GalleryInfo = list[i];
        if (!f.filterUploader(info) || !f.filterTag(info) || !f.filterTagNamespace(info)) {
          list.splice(i, 1);
        } else {
          i++;
        }
      }
    }
    for (let i = 0; i < list.length; i++) {
      const info: GalleryInfo = list[i];
      info.thumb = EhUrl.getFixedPreviewThumbUrl(info.thumb);
    }
  }

  /**
   * 对齐 `fillGalleryListByApi(task, okHttpClient, galleryInfoList, referer)`：
   * **每 25 条**一批（`MAX_REQUEST_SIZE = 25`，api.php 单次上限），逐批调 `doFillGalleryListByApi`。
   * 注意分批条件：凑满 25 条 **或** 已是最后一条就发一批（最后一批可能不满）。
   */
  static async fillGalleryListByApi(task: EngineTask | null, caller: HttpCaller,
    list: GalleryInfo[], referer: string): Promise<GalleryInfo[]> {
    const MAX_REQUEST_SIZE: number = 25;
    let requestItems: GalleryInfo[] = [];
    for (let i = 0; i < list.length; i++) {
      requestItems.push(list[i]);
      if (requestItems.length === MAX_REQUEST_SIZE || i === list.length - 1) {
        await EhEngine.doFillGalleryListByApi(task, caller, requestItems, referer);
        requestItems = [];
      }
    }
    return list;
  }

  /**
   * 对齐 `doFillGalleryListByApi(...)`：POST api.php
   * `{method:"gdata", gidlist:[[gid,token],…], namespace:1}`，
   * 解析结果**就地回填**到传入的列表（`GalleryApiParser.parse(body, list)`）。
   */
  static async doFillGalleryListByApi(task: EngineTask | null, caller: HttpCaller,
    list: GalleryInfo[], referer: string): Promise<void> {
    let gidlist: string = '';
    for (let i = 0; i < list.length; i++) {
      if (i > 0) {
        gidlist += ',';
      }
      gidlist += '[' + list[i].gid + ',"' + list[i].token + '"]';
    }
    const json: string = '{"method":"gdata","gidlist":[' + gidlist + '],"namespace":1}';
    const url: string = EhUrl.getApiUrl();
    const origin: string = EhUrl.getOrigin();
    const request: Request = EhRequestBuilder.ofRefererOrigin(url, referer, origin)
      .post(RequestBody.create(EhEngine.MEDIA_TYPE_JSON, json))
      .build();
    await EhEngine.runApi(task, caller, request, (r: EngineCallResult): void => {
      GalleryApiParser.parse(EhEngine.bodyOf(r), list);
    });
  }

  // ==================================================================================
  // API 3/19：getGalleryDetail
  // ==================================================================================

  /** 对齐 `getGalleryDetail(task, okHttpClient, url)`。 */
  static async getGalleryDetail(task: EngineTask | null, caller: HttpCaller,
    url: string): Promise<GalleryDetail> {
    const referer: string = EhUrl.getReferer();
    const request: Request = EhRequestBuilder.ofReferer(url, referer).build();
    return EhEngine.runApi(task, caller, request, (r: EngineCallResult): GalleryDetail => {
      const body: string = EhEngine.bodyOf(r);
      const html: string | null = EhEventParse.parse(body);
      if (html !== null) {
        EhEngine._eventPaneHook.showEventPane(html);
      }
      return GalleryDetailParser.parse(body);
    });
  }

  // ==================================================================================
  // API 5/19：getPreviewSet
  // ==================================================================================

  /** 对齐 `getPreviewSet(task, okHttpClient, url)`：返回 [预览集, 预览页数]。 */
  static async getPreviewSet(task: EngineTask | null, caller: HttpCaller,
    url: string): Promise<PreviewSetResult> {
    const referer: string = EhUrl.getReferer();
    const request: Request = EhRequestBuilder.ofReferer(url, referer).build();
    return EhEngine.runApi(task, caller, request, (r: EngineCallResult): PreviewSetResult => {
      const body: string = EhEngine.bodyOf(r);
      const out: PreviewSetResult = new PreviewSetResult();
      const doc: Document = Jsoup.parse(body);
      out.previewSet = GalleryDetailParser.parsePreviewSetDocument(doc, body);
      let pages: number = 0;
      try {
        pages = GalleryDetailParser.parsePreviewPagesDocument(doc, body);
      } catch (_e) {
        pages = 0;
      }
      if (pages <= 0) {
        try {
          pages = GalleryDetailParser.parsePreviewPages(body);
        } catch (err) {
          if (out.previewSet !== null && out.previewSet.size() > 0) {
            pages = 1;
          } else {
            throw err as Error;
          }
        }
      }
      out.previewPages = pages;
      return out;
    });
  }

  // ==================================================================================
  // API 6/19：rateGallery
  // ==================================================================================

  /**
   * 对齐 `rateGallery(task, okHttpClient, apiUid, apiKey, gid, token, rating)`。
   * 分值转换照搬：`(int) Math.ceil(rating * 2)` —— 5 → 10、4.5 → 9、0.4 → 1。
   */
  static async rateGallery(task: EngineTask | null, caller: HttpCaller,
    apiUid: number, apiKey: string, gid: number, token: string,
    rating: number): Promise<RateGalleryResult> {
    const json: string = '{"method":"rategallery"' +
      ',"apiuid":' + apiUid +
      ',"apikey":"' + apiKey + '"' +
      ',"gid":' + gid +
      ',"token":"' + token + '"' +
      ',"rating":' + Math.ceil(rating * 2) + '}';
    const requestBody: RequestBody = RequestBody.create(EhEngine.MEDIA_TYPE_JSON, json);
    const url: string = EhUrl.getApiUrl();
    const referer: string = EhUrl.getGalleryDetailUrl(gid, token, 0, false);
    const origin: string = EhUrl.getOrigin();
    const request: Request = EhRequestBuilder.ofRefererOrigin(url, referer, origin)
      .post(requestBody)
      .build();
    return EhEngine.runApi(task, caller, request,
      (r: EngineCallResult): RateGalleryResult => RateGalleryParser.parse(EhEngine.bodyOf(r)));
  }

  // ==================================================================================
  // API 7/19：commentGallery
  // ==================================================================================

  /**
   * 对齐 `commentGallery(task, okHttpClient, url, comment, id)`。
   * 表单二选一：id == null → `commenttext_new`；否则 `commenttext_edit` + `edit_comment`。
   * 返回前先看错误位：`#chd + p` 有内容 → 直接抛 EhException（服务端给的原因）。
   */
  static async commentGallery(task: EngineTask | null, caller: HttpCaller,
    url: string, comment: string, id: string | null): Promise<GalleryCommentList> {
    const builder: FormBodyBuilder = new FormBodyBuilder();
    if (id === null) {
      builder.add('commenttext_new', comment);
    } else {
      builder.add('commenttext_edit', comment);
      builder.add('edit_comment', id);
    }
    const origin: string = EhUrl.getOrigin();
    const request: Request = EhRequestBuilder.ofRefererOrigin(url, url, origin)
      .post(builder.build())
      .build();
    return EhEngine.runApi(task, caller, request, (r: EngineCallResult): GalleryCommentList => {
      const document: Document = Jsoup.parse(EhEngine.bodyOf(r));
      const elements: Elements = document.select('#chd + p');
      if (elements.size() > 0) {
        throw new EhException(elements.get(0).text());
      }
      return GalleryDetailParser.parseComments(document);
    });
  }

  // ==================================================================================
  // API 8/19：getEditComment
  // ==================================================================================

  /** 对齐 `getEditComment(task, okHttpClient, apiUid, apiKey, gid, token, commentId)`。 */
  static async getEditComment(task: EngineTask | null, caller: HttpCaller,
    apiUid: number, apiKey: string, gid: number, token: string,
    commentId: number): Promise<EditCommentResult> {
    const json: string = '{"method":"geteditcomment"' +
      ',"apiuid":' + apiUid +
      ',"apikey":"' + apiKey + '"' +
      ',"gid":' + gid +
      ',"token":"' + token + '"' +
      ',"comment_id":' + commentId + '}';
    const requestBody: RequestBody = RequestBody.create(EhEngine.MEDIA_TYPE_JSON, json);
    const url: string = EhUrl.getApiUrl();
    const referer: string = EhUrl.getGalleryDetailUrl(gid, token, 0, false);
    const origin: string = EhUrl.getOrigin();
    const request: Request = EhRequestBuilder.ofRefererOrigin(url, referer, origin)
      .post(requestBody)
      .build();
    return EhEngine.runApi(task, caller, request,
      (r: EngineCallResult): EditCommentResult => GetEditCommentParser.parse(EhEngine.bodyOf(r)));
  }

  // ==================================================================================
  // API 9/19：getGalleryToken
  // ==================================================================================

  /**
   * 对齐 `getGalleryToken(task, okHttpClient, gid, gtoken, page)`。
   * `pagelist` 是**二维数组**，且页码要 **+1**（上游内部 0 基、API 1 基）。
   */
  static async getGalleryToken(task: EngineTask | null, caller: HttpCaller,
    gid: number, gtoken: string, page: number): Promise<string> {
    const json: string = '{"method":"gtoken","pagelist":[[' +
      gid + ',"' + gtoken + '",' + (page + 1) + ']]}';
    const requestBody: RequestBody = RequestBody.create(EhEngine.MEDIA_TYPE_JSON, json);
    const url: string = EhUrl.getApiUrl();
    const referer: string = EhUrl.getReferer();
    const origin: string = EhUrl.getOrigin();
    const request: Request = EhRequestBuilder.ofRefererOrigin(url, referer, origin)
      .post(requestBody)
      .build();
    return EhEngine.runApi(task, caller, request,
      (r: EngineCallResult): string => GalleryTokenApiParser.parse(EhEngine.bodyOf(r)));
  }

  // ==================================================================================
  // API 10/19：getFavorites（带 Task 版本，会走 fillGalleryList）
  // ==================================================================================

  /** 对齐 `getFavorites(task, okHttpClient, url, callApi)`。 */
  static async getFavorites(task: EngineTask | null, caller: HttpCaller,
    url: string, callApi: boolean): Promise<FavoritesResult> {
    const referer: string = EhUrl.getReferer();
    const request: Request = EhRequestBuilder.ofReferer(url, referer).build();
    const result: FavoritesResult = await EhEngine.runApi(task, caller, request,
      (r: EngineCallResult): FavoritesResult => FavoritesParser.parse(EhEngine.bodyOf(r)));
    await EhEngine.fillGalleryList(task, caller, result.galleryInfoList, url, false);
    return result;
  }

  // ==================================================================================
  // API 11/19：addFavorites
  // ==================================================================================

  /**
   * 对齐 `addFavorites(task, okHttpClient, gid, token, dstCat, note)`。
   * `dstCat`：-1 → `favdel`（删除）；0..9 → 分类号；其它 → 直接抛 `EhException("Invalid dstCat: N")`。
   * 表单固定 `submit=Apply Changes` + `update=1`；`favnote` 为 null 时传空串。
   * 注意：**成功路径也会显式走一次 throwException(e=null)**（上游如此），
   * 用来在 code>=400 但页面正常时抛 StatusCodeException。
   */
  static async addFavorites(task: EngineTask | null, caller: HttpCaller,
    gid: number, token: string, dstCat: number, note: string | null): Promise<void> {
    let catStr: string;
    if (dstCat === -1) {
      catStr = 'favdel';
    } else if (dstCat >= 0 && dstCat <= 9) {
      catStr = `${dstCat}`;
    } else {
      throw new EhException('Invalid dstCat: ' + dstCat);
    }
    const builder: FormBodyBuilder = new FormBodyBuilder();
    builder.add('favcat', catStr);
    builder.add('favnote', note === null ? '' : note);
    // 上游注释：submit=Add to Favorites 不需要，统一用 Apply Changes
    builder.add('submit', 'Apply Changes');
    builder.add('update', '1');
    const url: string = EhUrl.getAddFavorites(gid, token);
    const origin: string = EhUrl.getOrigin();
    const request: Request = EhRequestBuilder.ofRefererOrigin(url, url, origin)
      .post(builder.build())
      .build();
    return EhEngine.runApi(task, caller, request, (r: EngineCallResult): void => {
      // 成功路径也过一次容错链（e=null）：code>=400 时抛 StatusCodeException
      EhEngine.throwException(r.call as EngineCall, r.code, r.headers, r.body, null);
    });
  }

  // ==================================================================================
  // API 12/19：addFavoritesRange（循环调 addFavorites）
  // ==================================================================================

  /**
   * 对齐 `addFavoritesRange(task, okHttpClient, gidArray, tokenArray, dstCat)`。
   * 两个数组长度不等 → 上游 `AssertUtils.assertEquals` 失败（本层抛错）；
   * 否则**逐个串行**调用 `addFavorites(..., null)`（note 固定 null）。
   */
  static async addFavoritesRange(task: EngineTask | null, caller: HttpCaller,
    gidArray: number[], tokenArray: string[], dstCat: number): Promise<void> {
    if (gidArray.length !== tokenArray.length) {
      throw new EhException(
        `Assertion failed: gidArray.length(${gidArray.length}) != tokenArray.length(${tokenArray.length})`);
    }
    for (let i = 0; i < gidArray.length; i++) {
      await EhEngine.addFavorites(task, caller, gidArray[i], tokenArray[i], dstCat, null);
    }
  }

  // ==================================================================================
  // API 13/19：modifyFavorites（批量改分类）
  // ==================================================================================

  /**
   * 对齐 `modifyFavorites(task, okHttpClient, url, gidArray, dstCat, callApi)`。
   * `dstCat`：-1 → `delete`；0..9 → `favN`；其它 → `EhException("Invalid dstCat: N")`。
   * 表单：`ddact` + 每个 gid 一个 `modifygids[]` + `apply=Apply`。
   */
  static async modifyFavorites(task: EngineTask | null, caller: HttpCaller,
    url: string, gidArray: number[], dstCat: number, callApi: boolean): Promise<FavoritesResult> {
    let catStr: string;
    if (dstCat === -1) {
      catStr = 'delete';
    } else if (dstCat >= 0 && dstCat <= 9) {
      catStr = 'fav' + dstCat;
    } else {
      throw new EhException('Invalid dstCat: ' + dstCat);
    }
    const builder: FormBodyBuilder = new FormBodyBuilder();
    builder.add('ddact', catStr);
    for (let i = 0; i < gidArray.length; i++) {
      builder.add('modifygids[]', `${gidArray[i]}`);
    }
    builder.add('apply', 'Apply');
    const origin: string = EhUrl.getOrigin();
    const request: Request = EhRequestBuilder.ofRefererOrigin(url, url, origin)
      .post(builder.build())
      .build();
    const result: FavoritesResult = await EhEngine.runApi(task, caller, request,
      (r: EngineCallResult): FavoritesResult => FavoritesParser.parse(EhEngine.bodyOf(r)));
    await EhEngine.fillGalleryList(task, caller, result.galleryInfoList, url, false);
    return result;
  }

  // ==================================================================================
  // API 14/19：getTorrentList
  // ==================================================================================

  /** 对齐 `getTorrentList(task, okHttpClient, url, gid, token)`：Referer 是**详情页**。 */
  static async getTorrentList(task: EngineTask | null, caller: HttpCaller,
    url: string, gid: number, token: string): Promise<TorrentInfo[]> {
    const referer: string = EhUrl.getGalleryDetailUrl(gid, token, 0, false);
    const request: Request = EhRequestBuilder.ofReferer(url, referer).build();
    return EhEngine.runApi(task, caller, request,
      (r: EngineCallResult): TorrentInfo[] => TorrentParser.parse(EhEngine.bodyOf(r)));
  }
  // ==================================================================================
  // API 15/19：getTopList
  // ==================================================================================

  /**
   * 对齐 `getTopList(task, okHttpClient, url)`：Referer 固定取 `EhUrl.getTopListUrl()`（恒 E 站）。
   * 上游这里单独 catch `LinkageError` 并包成 `ParseException("Top list parser runtime error")`；
   * ArkTS 没有 LinkageError（JVM 类装载错误），该分支**平台不适用**，其余路径照搬。
   */
  static async getTopList(task: EngineTask | null, caller: HttpCaller,
    url: string): Promise<EhTopListDetail> {
    const referer: string = EhUrl.getTopListUrl();
    const request: Request = EhRequestBuilder.ofReferer(url, referer).build();
    return EhEngine.runApi(task, caller, request,
      (r: EngineCallResult): EhTopListDetail => TopListParser.parse(EhEngine.bodyOf(r)));
  }

  // ==================================================================================
  // API 16/19：getProfile（两步：论坛首页 → 用户页）
  // ==================================================================================

  /**
   * 对齐 `getProfile(task, okHttpClient)`：
   * ① GET `EhUrl.URL_FORUMS`（**不带 Referer**）→ `ForumsParser.parse` 得到用户页链接
   * ② 用该链接再请求一次（Referer = 论坛首页）→ `ProfileParser.parse`
   */
  static async getProfile(task: EngineTask | null, caller: HttpCaller): Promise<ProfileResult> {
    const url: string = EhUrl.URL_FORUMS;
    const request: Request = EhRequestBuilder.of(url).build();
    const userUrl: string = await EhEngine.runApi(task, caller, request,
      (r: EngineCallResult): string => ForumsParser.parse(EhEngine.bodyOf(r)));
    return EhEngine.getProfileInternal(task, caller, userUrl, url);
  }

  /** 对齐 `getProfileInternal(task, okHttpClient, url, referer)`。 */
  static async getProfileInternal(task: EngineTask | null, caller: HttpCaller,
    url: string, referer: string): Promise<ProfileResult> {
    const request: Request = EhRequestBuilder.ofReferer(url, referer).build();
    return EhEngine.runApi(task, caller, request,
      (r: EngineCallResult): ProfileResult => ProfileParser.parse(EhEngine.bodyOf(r)));
  }

  // ==================================================================================
  // API 17/19：voteComment
  // ==================================================================================

  /**
   * 对齐 `voteComment(task, okHttpClient, apiUid, apiKey, gid, token, commentId, commentVote)`。
   * JSON：`{method:votecomment, apiuid, apikey, gid, token, comment_id, comment_vote}`；
   * 返回体里 `expectVote` 是**回填入参**（不是服务端字段）。
   */
  static async voteComment(task: EngineTask | null, caller: HttpCaller,
    apiUid: number, apiKey: string, gid: number, token: string, commentId: number,
    commentVote: number): Promise<VoteCommentResult> {
    const json: string = '{"method":"votecomment"' +
      ',"apiuid":' + apiUid +
      ',"apikey":"' + apiKey + '"' +
      ',"gid":' + gid +
      ',"token":"' + token + '"' +
      ',"comment_id":' + commentId +
      ',"comment_vote":' + commentVote + '}';
    const requestBody: RequestBody = RequestBody.create(EhEngine.MEDIA_TYPE_JSON, json);
    const url: string = EhUrl.getApiUrl();
    const referer: string = EhUrl.getReferer();
    const origin: string = EhUrl.getOrigin();
    const request: Request = EhRequestBuilder.ofRefererOrigin(url, referer, origin)
      .post(requestBody)
      .build();
    return EhEngine.runApi(task, caller, request,
      (r: EngineCallResult): VoteCommentResult =>
        VoteCommentParser.parse(EhEngine.bodyOf(r), commentVote));
  }

  // ==================================================================================
  // API 18/19：getArchiveList
  // ==================================================================================

  /** 对齐 `getArchiveList(task, okHttpClient, url, gid, token)`：Referer = 详情页。 */
  static async getArchiveList(task: EngineTask | null, caller: HttpCaller,
    url: string, gid: number, token: string): Promise<ArchiveResult> {
    const referer: string = EhUrl.getGalleryDetailUrl(gid, token, 0, false);
    const request: Request = EhRequestBuilder.ofReferer(url, referer).build();
    return EhEngine.runApi(task, caller, request,
      (r: EngineCallResult): ArchiveResult => ArchiveParser.parse(EhEngine.bodyOf(r)));
  }
  // ==================================================================================
  // API 19/19：imageSearch（multipart + 302 跟随 + 临时文件清理）
  // ==================================================================================

  /**
   * 对齐 `imageSearch(task, okHttpClient, imagePath, uss, osc, se)`。
   *
   * 注意：`imageCaller`（未传时回落 `caller`）应为**禁止自动跟随重定向**（`followRedirects(false)`）
   * 的客户端（上游传 `mImageOkHttpClient`），以便捕获 302 与 `Location` 头再发第二步请求。
   *
   * 分支组合（**嵌套**，这也是它单独一批的原因）：
   *   - 文件名：**含 `.` → 直接用**（不看扩展名）；否则在名字后加 `.jpg` 并复制（`shouldDelete = true`）
   *   - 三个可选 part：`fs_similar`(uss) / `fs_covers`(osc) / `fs_exp`(se)，都为 `"on"`
   *   - 必有 part：`sfile`（带 filename 与 `size="40"` 的 Content-Disposition）+ `f_sfile`=`File Search`
   *   - 发请求后 **code == 302** → 校验并解析 `Location`（支持相对 URL）再发一次；
   *     **第二次失败的 throwException 只传 code，headers/body 都是 null**（上游如此），
   *     外层 catch 里先删临时文件再抛
   *   - 成功/失败两条路径都要删临时文件（成功路径在 try 之后删）
   */
  static async imageSearch(task: EngineTask | null, caller: HttpCaller,
    imagePath: string, uss: boolean, osc: boolean, se: boolean,
    fileOps: ImageSearchFileOps, imageCaller?: HttpCaller): Promise<ListResult> {
    const searchCaller: HttpCaller = imageCaller !== undefined ? imageCaller : caller;
    const imageName: string = fileOps.getName(imagePath);
    let fileName: string;
    let imageFile: string;
    let shouldDelete: boolean = false;
    if (imageName.indexOf('.') >= 0) {
      fileName = imageName;
      imageFile = imagePath;
    } else {
      fileName = imageName + '.jpg';
      imageFile = fileOps.siblingPath(imagePath, fileName);
      fileOps.copyFile(imagePath, imageFile);
      shouldDelete = true;
    }

    const builder: MultipartBodyBuilder = new MultipartBodyBuilder();
    builder.setType(MultipartBody.FORM);
    builder.addPart(
      Headers.of('Content-Disposition',
        'form-data; name="sfile"; filename="' + fileName + '"; size="40"'),
      RequestBody.createFromFile(MediaType.parse('file') as MediaType, imageFile));
    if (uss) {
      builder.addPart(Headers.of('Content-Disposition', 'form-data; name="fs_similar"'),
        RequestBody.create(null, 'on'));
    }
    if (osc) {
      builder.addPart(Headers.of('Content-Disposition', 'form-data; name="fs_covers"'),
        RequestBody.create(null, 'on'));
    }
    if (se) {
      builder.addPart(Headers.of('Content-Disposition', 'form-data; name="fs_exp"'),
        RequestBody.create(null, 'on'));
    }
    builder.addPart(Headers.of('Content-Disposition', 'form-data; name="f_sfile"'),
      RequestBody.create(MediaType.parse('submit') as MediaType, 'File Search'));

    const url: string = EhUrl.getImageSearchUrl();
    const referer: string = EhUrl.getReferer() + '/';
    const origin: string = EhUrl.getOrigin();
    let request: Request = EhRequestBuilder.ofRefererOrigin(url, referer, origin)
      .post(builder.build())
      .build();

    let call: EngineCall = searchCaller.newCall(request);
    if (task !== null) {
      task.setCall(call);
    }
    let code: number = -1;
    let headers: EngineHeaders | null = null;
    let body: string | null = null;
    try {
      let response: EngineResponse = await call.execute();
      code = response.code();
      if (code === 302) {
        let location: string | null = response.headers().get('Location');
        if (location === null) {
          location = response.headers().get('location');
        }
        if (location === null || location.trim().length === 0) {
          throw new EhException('Missing Location header in 302 redirect');
        }
        const baseUrl: HttpUrl | null = HttpUrl.parse(url);
        const resolvedUrl: HttpUrl | null = baseUrl !== null
          ? baseUrl.resolve(location.trim())
          : HttpUrl.parse(location.trim());
        if (resolvedUrl === null) {
          throw new EhException('Invalid Location header: ' + location);
        }
        request = EhRequestBuilder.ofReferer(resolvedUrl.toString(), referer).build();
        call = searchCaller.newCall(request);
        if (task !== null) {
          task.setCall(call);
        }
        try {
          response = await call.execute();
          code = response.code();
        } catch (e) {
          // 上游：第二次失败只传 code，headers/body 均为 null
          EhEngine.throwException(call, code, null, null, e as Error);
          throw e as Error;
        }
      }
      headers = response.headers();
      body = response.body();
      const result: ListResult = GalleryListParser.parse(body, ListUrlBuilder.MODE_NORMAL);
      if (shouldDelete) {
        fileOps.delete(imageFile);
      }
      await EhEngine.fillGalleryList(task, caller, result.galleryInfoList, url, true);
      return result;
    } catch (e) {
      EhEngine.throwException(call, code, headers, body, e as Error);
      if (shouldDelete) {
        fileOps.delete(imageFile);
      }
      throw e as Error;
    }
  }

  // ==================================================================================
  // API 20/22：getArchiver
  // ==================================================================================

  /** 对齐 `getArchiver(task, okHttpClient, url, gid, token)`：Referer = 详情页。 */
  static async getArchiver(task: EngineTask | null, caller: HttpCaller,
    url: string, gid: number, token: string): Promise<ArchiverData> {
    const referer: string = EhUrl.getGalleryDetailUrl(gid, token, 0, false);
    const request: Request = EhRequestBuilder.ofReferer(url, referer).build();
    return EhEngine.runApi(task, caller, request,
      (r: EngineCallResult): ArchiverData => ArchiveParser.parseArchiver(EhEngine.bodyOf(r), EhUrl.getGallerySite()));
  }

  // ==================================================================================
  // API 21/22：downloadArchive
  // ==================================================================================

  /**
   * 对齐 `downloadArchive(task, okHttpClient, gid, token, or, res)`。
   * 参数校验：`or == null` → `Invalid form param or: null`；`res` 空 → `Invalid res: x`。
   * 成功后仍走一次 `throwException(e=null)`（捕获 HTTP 200 但业务失败），
   * 再看 body 是否命中 `PATTERN_NEED_HATH_CLIENT` → `NoHAtHClientException`。
   */
  static async downloadArchive(task: EngineTask | null, caller: HttpCaller,
    gid: number, token: string, or: string | null, res: string): Promise<void> {
    if (or === null) {
      throw new EhException('Invalid form param or: ' + or);
    }
    if (res === null || res.length === 0) {
      throw new EhException('Invalid res: ' + res);
    }
    const builder: FormBodyBuilder = new FormBodyBuilder();
    builder.add('hathdl_xres', res);
    const url: string = EhUrl.getDownloadArchive(gid, token, or);
    const referer: string = EhUrl.getGalleryDetailUrl(gid, token, 0, false);
    const origin: string = EhUrl.getOrigin();
    const request: Request = EhRequestBuilder.ofRefererOrigin(url, referer, origin)
      .post(builder.build())
      .build();
    return EhEngine.runApi(task, caller, request, (r: EngineCallResult): void => {
      EhEngine.throwException(r.call as EngineCall, r.code, r.headers, r.body, null);
      const body: string = EhEngine.bodyOf(r);
      if (EhEngine.PATTERN_NEED_HATH_CLIENT.test(body)) {
        throw new NoHAtHClientException();
      }
    });
  }

  // ==================================================================================
  // API 22/22：downloadArchiver
  // ==================================================================================

  /**
   * 对齐 `downloadArchiver(task, okHttpClient, url, referer, dltype, dlcheck)`。
   * 两步：① POST `dltype`/`dlcheck` → body 里 `document.location = "…"` 取 continueUrl；
   * ② GET continueUrl（**Referer = origin**）→ `ArchiveParser.parseArchiverDownloadUrl` 取 path →
   *    拼成 `https://<第二次请求的 host><path>`（host 取自**第二次响应**，不是原 URL）。
   * ①② 任一取不到 → 返回 null（不抛）。
   */
  static async downloadArchiver(task: EngineTask | null, caller: HttpCaller,
    url: string, referer: string, dltype: string, dlcheck: string): Promise<string | null> {
    if (url === null || url.length === 0) {
      throw new EhException('Invalid form param url: ' + url);
    }
    if (referer === null || referer.length === 0) {
      throw new EhException('Invalid form param referer: ' + referer);
    }
    const origin: string = EhUrl.getOrigin();
    const builder: FormBodyBuilder = new FormBodyBuilder();
    builder.add('dltype', dltype);
    builder.add('dlcheck', dlcheck);
    const request: Request = EhRequestBuilder.ofRefererOrigin(url, referer, origin)
      .post(builder.build())
      .build();
    let call: EngineCall = caller.newCall(request);
    if (task !== null) {
      task.setCall(call);
    }
    let code: number = -1;
    let headers: EngineHeaders | null = null;
    let body: string | null = null;
    try {
      let response: EngineResponse = await call.execute();
      code = response.code();
      headers = response.headers();
      body = response.body();
      const m: RegExpMatchArray | null = body.match(/document\.location = "(.*)"/);
      if (m === null) {
        return null;
      }
      const continueUrl: string = m[1];
      const requestContinue: Request = EhRequestBuilder.ofReferer(continueUrl, origin).build();
      const callContinue: EngineCall = caller.newCall(requestContinue);
      const responseC: EngineResponse = await callContinue.execute();
      const bodyC: string = responseC.body();
      const downloadPath: string | null = ArchiveParser.parseArchiverDownloadUrl(bodyC);
      if (downloadPath === null) {
        return null;
      }
      if (downloadPath.startsWith('http://') || downloadPath.startsWith('https://')) {
        return downloadPath;
      }
      // host 取自第二次响应（上游 responseC.request().url().host()）
      const rawUrlHost: string | undefined = responseC.urlHost;
      const fallbackHost: string = HttpUrl.parse(continueUrl)?.host() ?? '';
      const host: string = (rawUrlHost !== undefined && rawUrlHost !== null && rawUrlHost.length > 0)
        ? rawUrlHost
        : fallbackHost;
      if (host.length === 0) {
        return null;
      }
      const normalizedPath: string = downloadPath.startsWith('/') ? downloadPath : '/' + downloadPath;
      return 'https://' + host + normalizedPath;
    } catch (e) {
      EhEngine.throwException(call, code, headers, body, e as Error);
      return null;
    }
  }
  // ==================================================================================
  // API：getGalleryPage（阅读页 HTML，storage-db 的 SpiderQueen 依赖）
  // ==================================================================================

  /**
   * 对齐 `getGalleryPage(task, okHttpClient, url, gid, token)`。
   * Referer = `EhUrl.getGalleryDetailUrl(gid, token)`；解析用 `GalleryPageParser`（四正则 + showKey）。
   */
  static async getGalleryPage(task: EngineTask | null, caller: HttpCaller,
    url: string, gid: number, token: string): Promise<GalleryPageParserResult> {
    const referer: string = EhUrl.getGalleryDetailUrl(gid, token, 0, false);
    const request: Request = EhRequestBuilder.ofReferer(url, referer).build();
    return EhEngine.runApi(task, caller, request,
      (r: EngineCallResult): GalleryPageParserResult =>
        GalleryPageParser.parse(EhEngine.bodyOf(r)));
  }

  // ==================================================================================
  // API：getGalleryPageApi（阅读页 api.php，storage-db 的 SpiderQueen 依赖）
  // ==================================================================================

  /**
   * 对齐 `getGalleryPageApi(task, okHttpClient, gid, index, pToken, showKey, previousPToken)`。
   *
   * 两处容易写错的地方：
   *   1. JSON 里 `page` 要 **+1**（内部 0 基、API 1 基）
   *   2. **Referer 只在 `index > 0 && previousPToken != null` 时才设**，
   *      且指向「上一页」`getPageUrl(gid, index - 1, previousPToken)`；否则 referer 为 null（不加头）
   */
  static async getGalleryPageApi(task: EngineTask | null, caller: HttpCaller,
    gid: number, index: number, pToken: string, showKey: string,
    previousPToken: string | null): Promise<GalleryPageApiParserResult> {
    const json: string = '{"method":"showpage"' +
      ',"gid":' + gid +
      ',"page":' + (index + 1) +
      ',"imgkey":"' + pToken + '"' +
      ',"showkey":"' + showKey + '"}';
    const requestBody: RequestBody = RequestBody.create(EhEngine.MEDIA_TYPE_JSON, json);
    const url: string = EhUrl.getApiUrl();
    let referer: string | null = null;
    if (index > 0 && previousPToken !== null) {
      referer = EhUrl.getPageUrl(gid, index - 1, previousPToken);
    }
    const origin: string = EhUrl.getOrigin();
    const request: Request = EhRequestBuilder.ofRefererOrigin(url, referer, origin)
      .post(requestBody)
      .build();
    return EhEngine.runApi(task, caller, request,
      (r: EngineCallResult): GalleryPageApiParserResult =>
        GalleryPageApiParser.parse(EhEngine.bodyOf(r)));
  }
  // ==================================================================================
  // API：getWatchedList（需要登录）
  // ==================================================================================

  /**
   * 对齐 `getWatchedList(task, okHttpClient, url)`。
   * **未登录直接返回 null**（不发请求）；发起后走 `MyTagLitParser.parse`。
   */
  static async getWatchedList(task: EngineTask | null, caller: HttpCaller,
    url: string): Promise<UserTagList | null> {
    if (!EhEngine._config.isLogin()) {
      return null;
    }
    const request: Request = EhRequestBuilder.of(url).build();
    return EhEngine.runApi(task, caller, request,
      (r: EngineCallResult): UserTagList => MyTagLitParser.parse(EhEngine.bodyOf(r)));
  }

  // ==================================================================================
  // API：addTag（需要登录）
  // ==================================================================================

  /**
   * 对齐 `addTag(task, okHttpClient, url, param)`。
   * - 未登录 → null
   * - body 用 `param.addTagParam()`（**urlencoded 字符串，不是 FormBody**）
   * - 失败时上游 `catch` 里 **return null**（不是 throw）——注释掉的 `throw e` 说明是故意的
   */
  static async addTag(task: EngineTask | null, caller: HttpCaller,
    url: string, param: TagPushParam): Promise<UserTagList | null> {
    if (!EhEngine._config.isLogin()) {
      return null;
    }
    const requestBody: RequestBody =
      RequestBody.create(EhEngine.MEDIA_TYPE_URLENCODED, param.addTagParam());
    const request: Request = EhRequestBuilder.of(url).post(requestBody).build();
    try {
      return await EhEngine.runApi(task, caller, request,
        (r: EngineCallResult): UserTagList => MyTagLitParser.parse(EhEngine.bodyOf(r)));
    } catch (e) {
      // 上游如此：吞掉异常返回 null
      return null;
    }
  }

  // ==================================================================================
  // API：deleteWatchedTag（需要登录）
  // ==================================================================================

  /**
   * 对齐 `deleteWatchedTag(task, okHttpClient, url, param)`。
   * 与 `addTag` 同构，差别是 body 用 `param.deleteParam()`；失败同样 return null。
   */
  static async deleteWatchedTag(task: EngineTask | null, caller: HttpCaller,
    url: string, param: UserTag): Promise<UserTagList | null> {
    if (!EhEngine._config.isLogin()) {
      return null;
    }
    const requestBody: RequestBody =
      RequestBody.create(EhEngine.MEDIA_TYPE_URLENCODED, param.deleteParam());
    const request: Request = EhRequestBuilder.of(url).post(requestBody).build();
    try {
      return await EhEngine.runApi(task, caller, request,
        (r: EngineCallResult): UserTagList => MyTagLitParser.parse(EhEngine.bodyOf(r)));
    } catch (e) {
      return null;
    }
  }

  // ==================================================================================
  // API：getEhNews（失败返回空 EhNewsDetail，不抛）
  // ==================================================================================

  /**
   * 对齐 `getEhNews(task, okHttpClient)`：
   * GET `EhUrl.getEhNewsUrl()`（**不带 Referer**）；
   * body 为 null → 返回 null；成功 → `new EhNewsDetail(body)`；
   * `IOException` 分支 → 走容错链后**返回空 EhNewsDetail**（不抛）。
   */
  static async getEhNews(task: EngineTask | null, caller: HttpCaller): Promise<EhNewsDetail | null> {
    const url: string = EhUrl.getEhNewsUrl();
    const request: Request = EhRequestBuilder.of(url).build();
    const call: EngineCall = caller.newCall(request);
    if (task !== null) {
      task.setCall(call);
    }
    let code: number = -1;
    let headers: EngineHeaders | null = null;
    try {
      const response: EngineResponse = await call.execute();
      code = response.code();
      headers = response.headers();
      const body: string = response.body();
      if (body === null) {
        return null;
      }
      return new EhNewsDetail(body);
    } catch (e) {
      EhEngine.throwException(call, code, headers, null, e as Error);
      return new EhNewsDetail();
    }
  }

  // ==================================================================================
  // API：getHomeDetail
  // ==================================================================================

  /** 对齐 `getHomeDetail(task, okHttpClient)`：Referer = `EhUrl.getReferer()`；会展示事件条。 */
  static async getHomeDetail(task: EngineTask | null, caller: HttpCaller): Promise<HomeDetail> {
    const referer: string = EhUrl.getReferer();
    const url: string = EhUrl.getHomeUrl();
    const request: Request = EhRequestBuilder.ofReferer(url, referer).build();
    return EhEngine.runApi(task, caller, request, (r: EngineCallResult): HomeDetail => {
      const body: string = EhEngine.bodyOf(r);
      const html: string | null = EhEventParse.parse(body);
      if (html !== null) {
        EhEngine._eventPaneHook.showEventPane(html);
      }
      return EhHomeParser.parse(body);
    });
  }

  // ==================================================================================
  // API：resetLimit
  // ==================================================================================

  /**
   * 对齐 `resetLimit(task, okHttpClient)`：POST 首页，表单只有
   * `reset_imagelimit=Reset Limit`；之后与 `getHomeDetail` 同构（事件条 + `EhHomeParser`）。
   */
  static async resetLimit(task: EngineTask | null, caller: HttpCaller): Promise<HomeDetail> {
    const builder: FormBodyBuilder = new FormBodyBuilder();
    builder.add('reset_imagelimit', 'Reset Limit');
    const referer: string = EhUrl.getReferer();
    const url: string = EhUrl.getHomeUrl();
    const request: Request = EhRequestBuilder.ofReferer(url, referer)
      .post(builder.build())
      .build();
    return EhEngine.runApi(task, caller, request, (r: EngineCallResult): HomeDetail => {
      const body: string = EhEngine.bodyOf(r);
      const html: string | null = EhEventParse.parse(body);
      if (html !== null) {
        EhEngine._eventPaneHook.showEventPane(html);
      }
      return EhHomeParser.parse(body);
    });
  }
  // ==================================================================================
  // API 4/19：getAllFavorites（无 Task 版本）
  // ==================================================================================

  /** 对齐 `getAllFavorites(okHttpClient, url)`。 */
  static async getAllFavorites(caller: HttpCaller, url: string): Promise<FavoritesResult> {
    const referer: string = EhUrl.getReferer();
    const request: Request = EhRequestBuilder.ofReferer(url, referer).build();
    return EhEngine.runApi(null, caller, request,
      (r: EngineCallResult): FavoritesResult => FavoritesParser.parse(EhEngine.bodyOf(r)));
  }
}

// ==================================================================================
// 依赖抽象（平台/跨模块）
// ==================================================================================

/** 一次调用的结果（对齐上游的 code/headers/body 三个局部变量）。 */
export class EngineCallResult {
  call: EngineCall | null = null;
  code: number = -1;
  headers: EngineHeaders | null = null;
  body: string | null = null;
}

/** 对齐 okhttp `Call` 的最小形状。 */
export interface EngineCall {
  execute(): Promise<EngineResponse>;

  isCanceled(): boolean;

  cancel(): void;
}

/** 对齐 okhttp `Response`（本层只取 code/headers/body 字符串）。 */
export interface EngineResponse {
  code(): number;

  headers(): EngineHeaders;

  body(): string;

  /** 对齐 `response.request().url().host()`（downloadArchiver 拼下载链接要用）。 */
  urlHost?: string;
}

/** 对齐 okhttp `Headers`（只用到 get）。 */
export interface EngineHeaders {
  get(name: string): string | null;
}

/** 对齐 okhttp `OkHttpClient.newCall` 的最小入口。 */
export interface HttpCaller {
  newCall(request: Request): EngineCall;
}

/** EhClient.Task 在本文件用到的两个方法。 */
export interface EngineTask {
  setCall(call: Object | null): void;
}

/** 对齐 upstream 的 `Pair<PreviewSet, Integer>`。 */
export class PreviewSetResult {
  previewSet: PreviewSet | null = null;
  previewPages: number = 0;
}
/** getGalleryList 的中间结果（解析 + 状态码 + body 长度，供 igneous 判定与真机诊断）。 */
class ListParsed {
  result: ListResult = new ListResult();
  code: number = -1;
  bodyLength: number = 0;
  /** body 头 200 字符（仅诊断用；非 200 或空 body 时打进日志）。 */
  bodyHead: string = '';
}
/**
 * imageSearch 需要的文件系统能力（上游用 java.io.File + FileUtils.copyFile）。
 * 生产实现由 storage-db 的 unifile 提供；测试用内存实现。
 */
export interface ImageSearchFileOps {
  /** 对齐 `File.getName()`。 */
  getName(path: string): string;

  /** 与 path 同目录下的另一个文件路径（对齐 `new File(image.getParent()+"/"+name)`）。 */
  siblingPath(path: string, name: string): string;

  /** 对齐 `FileUtils.copyFile`。 */
  copyFile(from: string, to: string): void;

  /** 对齐 `File.delete()`。 */
  delete(path: string): void;
}
