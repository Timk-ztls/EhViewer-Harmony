/*
 * Module 7 regression tests: FavoritesScene local/cloud + pagination propagation,
 * GalleryDetailScene actions/navigation, GalleryListScene action switching/tag search,
 * GalleryCommentsScene initial arguments.
 *
 * Run: pwsh -File harmony/entry/src/test/ui-scene/run.ps1 -Filter favorites-detail-wiring
 */

import { SceneArgs, StageHost, SceneResultReceiver, SceneTransitionHelper } from '../../main/ets/hippo/scene/SceneTypes';
import { GalleryInfo } from '../../main/ets/hippo/ehviewer/client/data/GalleryInfo';
import { GalleryDetail } from '../../main/ets/hippo/ehviewer/client/data/GalleryDetail';
import { GalleryComment } from '../../main/ets/hippo/ehviewer/client/data/GalleryComment';
import { GalleryCommentList } from '../../main/ets/hippo/ehviewer/client/data/GalleryCommentList';
import { ListUrlBuilder } from '../../main/ets/hippo/ehviewer/client/data/ListUrlBuilder';
import { EhUrl } from '../../main/ets/hippo/ehviewer/client/EhUrl';
import { FavoritesResult } from '../../main/ets/hippo/ehviewer/client/parser/FavoritesParser';
import {
  FavoritesCategory,
  FavoritesClientLike,
  FavoritesPageResult,
  EhClientFavoritesAdapter,
  LocalFavoritesLike
} from '../../main/ets/hippo/ehviewer/ui/scene/gallery/list/FavoritesScene';
import { FavoritesSceneConcrete } from '../../main/ets/hippo/ehviewer/ui/scene/gallery/list/FavoritesSceneConcrete';
import {
  DetailActionClientLike,
  DetailClientLike,
  GalleryRateOutcome
} from '../../main/ets/hippo/ehviewer/ui/scene/gallery/detail/GalleryDetailScene';
import { GalleryDetailSceneConcrete } from '../../main/ets/hippo/ehviewer/ui/scene/gallery/detail/GalleryDetailSceneConcrete';
import {
  EhClientLike,
  GalleryListAction
} from '../../main/ets/hippo/ehviewer/ui/scene/gallery/list/GalleryListScene';
import { GalleryListSceneConcrete } from '../../main/ets/hippo/ehviewer/ui/scene/gallery/list/GalleryListSceneConcrete';
import { GalleryCommentsSceneConcrete } from '../../main/ets/hippo/ehviewer/ui/scene/GalleryCommentsSceneConcrete';

let pass: number = 0;
const fails: string[] = [];

function eq(name: string, got: Object | null, want: Object | null): void {
  const g: string = JSON.stringify(got);
  const w: string = JSON.stringify(want);
  if (g === w) {
    pass++;
  } else {
    fails.push(`${name}\n    got  ${g}\n    want ${w}`);
  }
}

function ok(name: string, cond: boolean): void {
  if (cond) {
    pass++;
  } else {
    fails.push(`${name}\n    expected true`);
  }
}

interface StartedSceneRecord {
  sceneName: string;
  args: SceneArgs | null;
}

class FakeStageHost implements StageHost {
  started: StartedSceneRecord[] = [];

  startSceneByName(sceneName: string, args: SceneArgs | null, _from: string | null, _code: number): void {
    this.started.push({ sceneName: sceneName, args: args });
  }

  finishSceneByTag(_tag: string, _helper: SceneTransitionHelper | null): void {}
  getSceneIndexByTag(_tag: string): number { return 0; }
  notifySceneViewCreated(_scene: SceneResultReceiver): void {}
  notifySceneViewDestroyed(_scene: SceneResultReceiver): void {}
  notifySceneDestroyed(_scene: SceneResultReceiver): void {}
  findSceneByTag(_tag: string): SceneResultReceiver | null { return null; }
}

class FakeLocalRepo implements LocalFavoritesLike {
  list: GalleryInfo[];

  constructor(list: GalleryInfo[]) {
    this.list = list;
  }

  async getLocalFavoritesLazyList(): Promise<GalleryInfo[]> {
    return this.list;
  }
}

class QueuedFavoritesClient implements FavoritesClientLike {
  requestedUrls: string[] = [];
  forceFlags: boolean[] = [];
  private resolvers: ((res: FavoritesPageResult) => void)[] = [];

  getFavorites(url: string, force: boolean): Promise<FavoritesPageResult> {
    this.requestedUrls.push(url);
    this.forceFlags.push(force);
    return new Promise<FavoritesPageResult>((resolve) => {
      this.resolvers.push(resolve);
    });
  }

  resolveAt(index: number, result: FavoritesPageResult): void {
    this.resolvers[index](result);
  }
}

function makeGalleryInfo(gid: number, token: string, title: string, uploader: string): GalleryInfo {
  const gi: GalleryInfo = new GalleryInfo();
  gi.gid = gid;
  gi.token = token;
  gi.title = title;
  gi.uploader = uploader;
  gi.pages = 20;
  return gi;
}

async function flushMicrotasks(): Promise<void> {
  for (let i = 0; i < 6; i++) {
    await Promise.resolve();
  }
}

async function testFavoritesLocalAndCloud(): Promise<void> {
  const stage: FakeStageHost = new FakeStageHost();
  const fav: FavoritesSceneConcrete = new FavoritesSceneConcrete();
  fav.bindHost(stage);
  const localItems: GalleryInfo[] = [
    makeGalleryInfo(101, 'aaaaabbbbb', 'Alpha Manga', 'alice'),
    makeGalleryInfo(102, 'cccccddddd', 'Beta Comic', 'bob')
  ];
  fav.setLocalFavoritesRepo(new FakeLocalRepo(localItems));

  const onlineClient: QueuedFavoritesClient = new QueuedFavoritesClient();
  fav.setClient(onlineClient);

  let stateNotifications: number = 0;
  let updatedCats: string[] = [];
  let updatedCounts: number[] = [];
  fav.setOnStateChangedListener(() => { stateNotifications++; });
  fav.setOnMetaUpdatedListener((cats: string[], counts: number[]) => {
    updatedCats = cats;
    updatedCounts = counts;
  });

  // 1) Initial load -> local favorites
  fav.ensureLoaded();
  await flushMicrotasks();
  eq('local load count', fav.getDataSource().totalCount(), 2);
  eq('local item 0 gid', fav.getDataSource().getData(0)?.gid ?? -1, 101);
  ok('state listener notified on local load', stateNotifications > 0);

  // 2) Keyword search locally
  fav.applySearch('beta');
  await flushMicrotasks();
  eq('local filtered count', fav.getDataSource().totalCount(), 1);
  eq('local filtered item gid', fav.getDataSource().getData(0)?.gid ?? -1, 102);

  // Reset keyword and open gallery detail
  fav.applySearch('');
  await flushMicrotasks();
  const item0: GalleryInfo | null = fav.getDataSource().getData(0);
  ok('local item 0 exists', item0 !== null);
  if (item0 !== null) {
    fav.openGalleryDetail(item0);
  }
  eq('openGalleryDetail pushed 1 scene', stage.started.length, 1);
  eq('target scene = GalleryDetailScene', stage.started[0].sceneName, 'GalleryDetailScene');
  eq('passed gid = 101', stage.started[0].args?.get('gid') ?? -1, 101);

  // 3) Switch to cloud category 3 -> request issued
  fav.setCategory(3);
  eq('cloud category 3 issued 1 request', onlineClient.requestedUrls.length, 1);
  ok('cloud URL contains favcat=3', onlineClient.requestedUrls[0].indexOf('favcat=3') >= 0);

  // Switch to category 4 BEFORE category 3 resolves -> stale guard
  fav.setCategory(4);
  eq('cloud category 4 issued 2nd request', onlineClient.requestedUrls.length, 2);
  ok('cloud URL contains favcat=4', onlineClient.requestedUrls[1].indexOf('favcat=4') >= 0);

  // Resolve stale request 0 (cat 3) -> must be ignored
  const staleRes: FavoritesPageResult = new FavoritesPageResult();
  staleRes.current = 1;
  staleRes.limit = 2;
  staleRes.items = [makeGalleryInfo(999, '1111122222', 'Stale', 'nobody')];
  onlineClient.resolveAt(0, staleRes);
  await flushMicrotasks();
  eq('stale cloud result ignored', fav.getDataSource().getData(0)?.gid ?? -1, 101);

  // Resolve active request 1 (cat 4, page 0 of 2)
  const page0Res: FavoritesPageResult = new FavoritesPageResult();
  page0Res.current = 1;
  page0Res.limit = 2;
  page0Res.count = 1;
  page0Res.items = [makeGalleryInfo(201, 'eeeeefffff', 'Cloud Page 0', 'up0')];
  page0Res.catArray = ['C0', 'C1', 'C2', 'C3', 'C4', 'C5', 'C6', 'C7', 'C8', 'C9'];
  page0Res.countArray = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10];
  onlineClient.resolveAt(1, page0Res);
  await flushMicrotasks();
  eq('active cloud page 0 count', fav.getDataSource().totalCount(), 1);
  eq('active cloud page 0 gid', fav.getDataSource().getData(0)?.gid ?? -1, 201);
  eq('meta callback received 10 cats', updatedCats.length, 10);
  eq('meta cat 4 count', updatedCounts[4], 5);
  eq('hasMore true when pageIndex(1) < limit(2)', fav.hasMore(), true);

  // 4) loadMore appends page 1
  fav.loadMore();
  eq('loadMore issued 3rd request', onlineClient.requestedUrls.length, 3);
  ok('loadMore URL contains page=1', onlineClient.requestedUrls[2].indexOf('page=1') >= 0);
  const page1Res: FavoritesPageResult = new FavoritesPageResult();
  page1Res.current = 2;
  page1Res.limit = 2;
  page1Res.count = 1;
  page1Res.items = [makeGalleryInfo(202, '12345abcde', 'Cloud Page 1', 'up1')];
  onlineClient.resolveAt(2, page1Res);
  await flushMicrotasks();
  eq('cloud list after loadMore has 2 items', fav.getDataSource().totalCount(), 2);
  eq('second item gid = 202', fav.getDataSource().getData(1)?.gid ?? -1, 202);
  eq('hasMore false after last page', fav.hasMore(), false);

  // 5) EhClientFavoritesAdapter preserves items/cats/counts
  const rawParserRes: FavoritesResult = new FavoritesResult();
  rawParserRes.pages = 3;
  rawParserRes.nextPage = 1;
  rawParserRes.catArray = ['A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J'];
  rawParserRes.countArray = [10, 9, 8, 7, 6, 5, 4, 3, 2, 1];
  rawParserRes.galleryInfoList = [makeGalleryInfo(301, 'fedcba9876', 'Adapted', 'u')];
  const adapter: EhClientFavoritesAdapter = new EhClientFavoritesAdapter(
    async (_url: string, _force: boolean): Promise<FavoritesResult> => rawParserRes
  );
  const adapted: FavoritesPageResult = await adapter.getFavorites('https://e-hentai.org/favorites.php', false);
  eq('adapter items preserved', adapted.items.length, 1);
  eq('adapter item gid = 301', adapted.items[0].gid, 301);
  eq('adapter catArray length', adapted.catArray.length, 10);
  eq('adapter countArray[0]', adapted.countArray[0], 10);
}

class FakeDetailClient implements DetailClientLike {
  detail: GalleryDetail;

  constructor(detail: GalleryDetail) {
    this.detail = detail;
  }

  async getGalleryDetail(_url: string): Promise<GalleryDetail | null> {
    return this.detail;
  }
}

class FakeDetailActionClient implements DetailActionClientLike {
  lastFavSlot: number = -999;
  removedCount: number = 0;
  downloadedGids: number[] = [];
  localFav: boolean = false;
  downloaded: boolean = false;

  async addToFavorite(_gi: GalleryInfo, slot: number, _note: string): Promise<boolean> {
    this.lastFavSlot = slot;
    if (slot === -2) {
      this.localFav = true;
    }
    return true;
  }

  async removeFromFavorite(_gi: GalleryInfo): Promise<boolean> {
    this.removedCount++;
    this.localFav = false;
    return true;
  }

  async rateGallery(_detail: GalleryDetail, rating: number): Promise<GalleryRateOutcome | null> {
    const out: GalleryRateOutcome = new GalleryRateOutcome();
    out.rating = rating;
    out.ratingCount = 42;
    return out;
  }

  async downloadGallery(gi: GalleryInfo): Promise<boolean> {
    this.downloadedGids.push(gi.gid);
    this.downloaded = true;
    return true;
  }

  async isDownloaded(_gid: number): Promise<boolean> {
    return this.downloaded;
  }

  async isLocalFavorited(_gid: number): Promise<boolean> {
    return this.localFav;
  }
}

async function testGalleryDetailActionsAndNavigation(): Promise<void> {
  const stage: FakeStageHost = new FakeStageHost();
  const scene: GalleryDetailSceneConcrete = new GalleryDetailSceneConcrete();
  scene.bindHost(stage);

  const detail: GalleryDetail = new GalleryDetail();
  detail.gid = 555;
  detail.token = 'a1b2c3d4e5';
  detail.title = 'Detail Title';
  detail.apiUid = 123;
  detail.apiKey = 'apikey';
  const c: GalleryComment = new GalleryComment();
  c.id = 77;
  c.user = 'commenter';
  c.comment = 'hello';
  detail.comments = new GalleryCommentList([c], true);

  const actionClient: FakeDetailActionClient = new FakeDetailActionClient();
  actionClient.downloaded = true;
  scene.setDetailClient(new FakeDetailClient(detail));
  scene.setDetailActionClient(actionClient);

  const initArgs: SceneArgs = new Map<string, Object>();
  initArgs.set('gallery_info', detail);
  initArgs.set('gid', detail.gid);
  initArgs.set('api_url', EhUrl.getGalleryDetailUrl(detail.gid, detail.token, 0, false));
  scene.onNewArguments(initArgs);
  await flushMicrotasks();

  eq('detail downloaded flag refreshed', scene.isDownloaded(), true);
  eq('initial favorited false', scene.isFavorited(), false);

  ok('addToFavorite(-2) returns true', await scene.addToFavorite(-2, ''));
  eq('lastFavSlot = -2', actionClient.lastFavSlot, -2);
  eq('isFavorited true after add', scene.isFavorited(), true);

  ok('removeFromFavorite returns true', await scene.removeFromFavorite());
  eq('removedCount = 1', actionClient.removedCount, 1);
  eq('isFavorited false after remove', scene.isFavorited(), false);

  const rateRes: GalleryRateOutcome | null = await scene.rateGallery(4.5);
  ok('rateGallery returns outcome', rateRes !== null);
  eq('detail rating updated', detail.rating, 4.5);
  eq('detail ratingCount updated', detail.ratingCount, 42);
  eq('detail rated true', detail.rated, true);

  ok('downloadGallery returns true', await scene.downloadGallery());
  eq('downloadedGids[0] = 555', actionClient.downloadedGids[0], 555);

  scene.openGalleryInfo();
  scene.openComments();
  scene.openTagSearch('artist', 'foo bar');
  eq('3 navigation pushes recorded', stage.started.length, 3);
  eq('push 0 = GalleryInfoScene', stage.started[0].sceneName, 'GalleryInfoScene');
  eq('push 0 has gallery_detail', stage.started[0].args?.get('gallery_detail') === detail, true);
  eq('push 1 = GalleryCommentsScene', stage.started[1].sceneName, 'GalleryCommentsScene');
  eq('push 1 has comments', stage.started[1].args?.get('comments') === detail.comments, true);
  eq('push 1 has api_uid', stage.started[1].args?.get('api_uid') ?? -1, 123);
  eq('push 2 = GalleryListScene', stage.started[2].sceneName, 'GalleryListScene');
  const tagUrl: string = String(stage.started[2].args?.get('list_url_builder') ?? '');
  ok('tag search URL uses MODE_TAG (/tag/)', tagUrl.indexOf('/tag/') >= 0);
  ok('tag search URL encodes artist query', tagUrl.indexOf('artist') >= 0 && tagUrl.indexOf('foo') >= 0);
  eq('tag search sets SearchBar keyword with wrapTagKeyword',
    stage.started[2].args?.get('search_keyword') ?? '', 'artist:"foo bar$"');
}

function testListActionAndCommentsInitialArgs(): void {
  const listScene: GalleryListSceneConcrete = new GalleryListSceneConcrete();
  const a1: SceneArgs = new Map<string, Object>();
  a1.set(GalleryListAction.KEY_ACTION, GalleryListAction.WHATS_HOT);
  listScene.onNewArguments(a1);
  eq('action 1 = WHATS_HOT', listScene.getAction(), GalleryListAction.WHATS_HOT);
  ok('url 1 = popular', listScene.getListUrl().indexOf('popular') >= 0);

  const a2: SceneArgs = new Map<string, Object>();
  a2.set(GalleryListAction.KEY_ACTION, GalleryListAction.SUBSCRIPTION);
  listScene.onNewArguments(a2);
  eq('action 2 = SUBSCRIPTION', listScene.getAction(), GalleryListAction.SUBSCRIPTION);
  ok('url 2 = watched (non-empty overwrite)', listScene.getListUrl().indexOf('watched') >= 0);

  listScene.searchTag('language', 'chinese');
  eq('searchTag sets LIST_URL_BUILDER action', listScene.getAction(), GalleryListAction.LIST_URL_BUILDER);
  ok('searchTag URL uses /tag/ and contains language:chinese',
    listScene.getListUrl().indexOf('/tag/') >= 0 &&
    listScene.getListUrl().indexOf('language') >= 0 && listScene.getListUrl().indexOf('chinese') >= 0);
  eq('searchTag sets searchKey', listScene.getSearchKey(), 'language:chinese');
  eq('extractSearchKeywordFromUrl extracts wrapped tag',
    ListUrlBuilder.extractSearchKeywordFromUrl('https://e-hentai.org/tag/artist%3Afoo+bar/1'),
    'artist:"foo bar$"');
  eq('extractSearchKeywordFromUrl extracts uploader',
    ListUrlBuilder.extractSearchKeywordFromUrl('https://e-hentai.org/uploader/someone+here'),
    'uploader:"someone here"');

  const commentsScene: GalleryCommentsSceneConcrete = new GalleryCommentsSceneConcrete();
  const gc: GalleryComment = new GalleryComment();
  gc.id = 88;
  gc.user = 'u88';
  gc.comment = 'cached comment';
  const cl: GalleryCommentList = new GalleryCommentList([gc], true);
  const cArgs: SceneArgs = new Map<string, Object>();
  cArgs.set('api_url', 'https://e-hentai.org/g/1/abcdef1234/');
  cArgs.set('gid', 1);
  cArgs.set('comments', cl);
  commentsScene.onNewArguments(cArgs);
  eq('comments pre-populated without network', commentsScene.getDataSource().totalCount(), 1);
  eq('comments hasMore = true', commentsScene.isHasMore(), true);
}

class DeferredGalleryRequest {
  url: string;
  page: number;
  resolveFn: (res: GalleryInfo[] | null) => void;
  rejectFn: (err: Error) => void;

  constructor(url: string, page: number,
    resolveFn: (res: GalleryInfo[] | null) => void,
    rejectFn: (err: Error) => void) {
    this.url = url;
    this.page = page;
    this.resolveFn = resolveFn;
    this.rejectFn = rejectFn;
  }
}

class QueuedGalleryListClient implements EhClientLike {
  requests: DeferredGalleryRequest[] = [];

  getGalleryList(url: string, page: number): Promise<GalleryInfo[] | null> {
    return new Promise<GalleryInfo[] | null>((resolve, reject) => {
      this.requests.push(new DeferredGalleryRequest(url, page, resolve, reject));
    });
  }
}

class RejectOnceFavoritesClient implements FavoritesClientLike {
  rejectNext: boolean = false;
  resToReturn: FavoritesPageResult = new FavoritesPageResult();

  getFavorites(_url: string, _force: boolean): Promise<FavoritesPageResult> {
    if (this.rejectNext) {
      this.rejectNext = false;
      return Promise.reject(new Error('network error'));
    }
    return Promise.resolve(this.resToReturn);
  }
}

function makePage(startGid: number, count: number): GalleryInfo[] {
  const out: GalleryInfo[] = [];
  for (let i = 0; i < count; i++) {
    out.push(makeGalleryInfo(startGid + i, `tok${startGid + i}ab`, `Title ${startGid + i}`, 'u'));
  }
  return out;
}

async function testListResetSeqAndPreemption(): Promise<void> {
  // 1) GalleryListSceneConcrete listResetSeq + preemption
  const gl: GalleryListSceneConcrete = new GalleryListSceneConcrete();
  const glClient: QueuedGalleryListClient = new QueuedGalleryListClient();
  gl.setGalleryListClient(glClient);
  eq('initial GalleryListScene listResetSeq = 0', gl.getListResetSeq(), 0);

  // 搜索刷新(满 25 条保证未触底) -> seq 递增
  gl.applySearchAndCategory('remilia', 0);
  eq('applySearchAndCategory issued req 0 (page 0)', glClient.requests[0].page, 0);
  glClient.requests[0].resolveFn(makePage(1001, 25));
  await flushMicrotasks();
  eq('refresh load increments listResetSeq -> 1', gl.getListResetSeq(), 1);
  eq('search item 0 gid = 1001', gl.getItem(0)?.gid ?? -1, 1001);

  // 滑到底部加载下一页 (append) -> seq 不变，且可被新搜索抢占
  gl.onReachEndList();
  eq('onReachEndList issued req 1 (page 1)', glClient.requests[1].page, 1);
  eq('while loading next page, isLoadingList = true', gl.isLoadingList(), true);

  // 在第 2 页尚未返回时切动作并强制刷新 -> 抢占成功且丢弃迟到的第 2 页响应
  gl.switchToAction(GalleryListAction.SUBSCRIPTION);
  gl.refreshGalleryList(true);
  eq('switchToAction + refreshGalleryList(true) preempted -> req 2', glClient.requests.length, 3);
  eq('preempted req 2 is page 0', glClient.requests[2].page, 0);

  glClient.requests[1].resolveFn(makePage(9900, 5));
  await flushMicrotasks();
  eq('stale page 1 response discarded -> listResetSeq stays 1', gl.getListResetSeq(), 1);

  glClient.requests[2].resolveFn(makePage(2001, 25));
  await flushMicrotasks();
  eq('preempting refresh increments listResetSeq -> 2', gl.getListResetSeq(), 2);
  eq('list replaced with Hot 0', gl.getItem(0)?.gid ?? -1, 2001);

  // 正常 append 不递增 listResetSeq
  gl.onReachEndList();
  eq('append req 3 issued (page 1)', glClient.requests[3].page, 1);
  glClient.requests[3].resolveFn([makeGalleryInfo(2099, 'tok2099abc', 'Hot 1', 'u2')]);
  await flushMicrotasks();
  eq('append does NOT increment listResetSeq (still 2)', gl.getListResetSeq(), 2);
  eq('append total items = 26', gl.getItemCount(), 26);

  // 请求失败不递增 listResetSeq
  gl.refreshGalleryList(true);
  glClient.requests[4].rejectFn(new Error('timeout'));
  await flushMicrotasks();
  eq('refresh failure does NOT increment listResetSeq (still 2)', gl.getListResetSeq(), 2);

  // jumpToPage 在 loading 时仍能抢占并递增 listResetSeq
  gl.refreshGalleryList(true);
  gl.jumpToPage(3);
  eq('jumpToPage preempted req 5 -> issued req 6 (page 2)', glClient.requests[6].page, 2);
  glClient.requests[6].resolveFn([makeGalleryInfo(3001, 'tok3001abc', 'Page 3', 'u3')]);
  await flushMicrotasks();
  eq('jumpToPage increments listResetSeq -> 3', gl.getListResetSeq(), 3);

  // 2) FavoritesSceneConcrete listResetSeq
  const fav: FavoritesSceneConcrete = new FavoritesSceneConcrete();
  fav.setLocalFavoritesRepo(new FakeLocalRepo([
    makeGalleryInfo(4001, 'tok4001abc', 'Fav A', 'ua'),
    makeGalleryInfo(4002, 'tok4002abc', 'Fav B', 'ub')
  ]));
  eq('initial FavoritesScene listResetSeq = 0', fav.getListResetSeq(), 0);
  fav.ensureLoaded();
  await flushMicrotasks();
  eq('Favorites local load increments listResetSeq -> 1', fav.getListResetSeq(), 1);
  fav.applySearch('fav b');
  await flushMicrotasks();
  eq('Favorites local search increments listResetSeq -> 2', fav.getListResetSeq(), 2);

  const cloudFavClient: RejectOnceFavoritesClient = new RejectOnceFavoritesClient();
  cloudFavClient.resToReturn.current = 1;
  cloudFavClient.resToReturn.limit = 3;
  cloudFavClient.resToReturn.items = [makeGalleryInfo(5001, 'tok5001abc', 'Cloud 0', 'uc')];
  fav.setClient(cloudFavClient);

  fav.setCategory(1);
  await flushMicrotasks();
  eq('Favorites cloud refresh (!append) increments listResetSeq -> 3', fav.getListResetSeq(), 3);

  cloudFavClient.resToReturn.current = 2;
  cloudFavClient.resToReturn.items = [makeGalleryInfo(5002, 'tok5002abc', 'Cloud 1', 'uc')];
  fav.loadMore();
  await flushMicrotasks();
  eq('Favorites cloud loadMore (append=true) does NOT increment listResetSeq (still 3)', fav.getListResetSeq(), 3);

  cloudFavClient.rejectNext = true;
  fav.applySearch('fail');
  await flushMicrotasks();
  eq('Favorites cloud error does NOT increment listResetSeq (still 3)', fav.getListResetSeq(), 3);
}

async function main(): Promise<void> {
  await testFavoritesLocalAndCloud();
  await testGalleryDetailActionsAndNavigation();
  testListActionAndCommentsInitialArgs();
  await testListResetSeqAndPreemption();

  if (fails.length > 0) {
    console.error(`\n✗ ${fails.length} 条失败 / ${pass + fails.length} 条断言`);
    for (const f of fails) {
      console.error('  - ' + f);
    }
    throw new Error('favorites-detail-wiring test failed');
  }
  console.log(`✓ Module 7 favorites-detail-wiring 批: ${pass} 条断言全部通过`);
}

main();
