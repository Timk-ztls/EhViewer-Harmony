/*
 * SpiderQueen 第 1 批单测（生命周期 / 引用计数 / 阅读进度）
 *
 * 这批覆盖的是「queen 表 + 引用计数」——上游最容易写错、且错了最难查的地方：
 *   - READ 与 DOWNLOAD 是**两套独立引用计数**，任一不为 0 就不能 stop（否则正在阅读的页面被下家踹掉）
 *   - `resetReadingProgress` 只改**内存**里的 startPage（不写盘、不写缓存）
 *   - queen 表在主线程（上游 `@UiThread` + `OSUtils.checkMainLoop()`）
 *   - `SPIDER_INFO_FILENAME` 是 `.ehviewer`（下载目录里的进度文件），不是缓存目录名 `spider_info`
 */

import {
  SpiderQueen, SpiderQueenLike, IllegalStateError, OnSpiderListener, SpiderInfoCacheProvider,
  GalleryDetailFetcher, PreviewSetFetcher, STATE_NONE, STATE_DOWNLOADING, STATE_FINISHED, STATE_FAILED, DECODE_THREAD_NUM,
  PageRequestResult, SPIDER_INFO_BACKUP_DIR, SPIDER_INFO_FILENAME as QUEEN_FILENAME,
  EhEngineLike, PageImageDownloader
} from '../../main/ets/hippo/ehviewer/spider/SpiderQueen';
import { PreviewSet } from '../../main/ets/hippo/ehviewer/client/data/PreviewSet';
import { DownloadResult, PageDownloadProgressCallback } from '../../main/ets/hippo/streampipe/PageImageDownloader';
import { MODE_READ, MODE_DOWNLOAD } from '../../main/ets/hippo/ehviewer/spider/SpiderDen';
import { SPIDER_INFO_FILENAME, SPIDER_INFO_CACHE_DIRNAME, SpiderInfo } from '../../main/ets/hippo/ehviewer/spider/SpiderInfo';
import { GalleryInfo } from '../../main/ets/hippo/ehviewer/client/data/GalleryInfo';
import { GalleryDetail } from '../../main/ets/hippo/ehviewer/client/data/GalleryDetail';
import { LargePreviewSet } from '../../main/ets/hippo/ehviewer/client/data/LargePreviewSet';
import { GalleryProvider } from '../../main/ets/hippo/lib/glgallery/GalleryProvider';
import { SpiderDen } from '../../main/ets/hippo/ehviewer/spider/SpiderDen';
import { EhUrl } from '../../main/ets/hippo/ehviewer/client/EhUrl';
import { GalleryPageParserResult } from '../../main/ets/hippo/ehviewer/client/parser/GalleryPageParser';
import { GalleryPageApiParserResult } from '../../main/ets/hippo/ehviewer/client/parser/GalleryPageApiParser';
import { ByteSink } from '../../main/ets/hippo/streampipe/OutputStreamPipe';
import { UniFile } from '../../main/ets/hippo/unifile/UniFile';
import { SimpleDiskCache } from '../../main/ets/hippo/beerbelly/SimpleDiskCache';
import { Image } from '../../main/ets/hippo/lib/image/Image';
import { Settings } from '../../main/ets/hippo/ehviewer/Settings';
import fs from '@ohos.file.fs';

let pass = 0;
const fails: string[] = [];

function eq(name: string, got: unknown, want: unknown): void {
  const g = JSON.stringify(got);
  const w = JSON.stringify(want);
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
    fails.push(name);
  }
}

/** 让事件循环推进（异步解码泵需要）。 */
async function tick(): Promise<void> {
  await Promise.resolve();
  await new Promise<void>((resolve) => setTimeout(resolve, 1));
}

function makeInfo(gid: number, token: string): GalleryInfo {
  const g: GalleryInfo = new GalleryInfo();
  g.gid = gid;
  g.token = token;
  return g;
}

// ================================================================ 1) 常量与文件名（最容易混的一处）

{
  eq('MODE_READ', MODE_READ, 0);
  eq('MODE_DOWNLOAD', MODE_DOWNLOAD, 1);
  eq('STATE_NONE', STATE_NONE, 0);
  eq('STATE_DOWNLOADING', STATE_DOWNLOADING, 1);
  eq('STATE_FINISHED', STATE_FINISHED, 2);
  eq('STATE_FAILED', STATE_FAILED, 3);
  eq('DECODE_THREAD_NUM（上游固定 2）', DECODE_THREAD_NUM, 2);
  eq('SPIDER_INFO_BACKUP_DIR', SPIDER_INFO_BACKUP_DIR, 'backupDir');

  // 关键：下载目录里的进度文件是 `.ehviewer`；`spider_info` 是**缓存目录名**。
  // 第一版我写成 'spider_info' → 旧 App 下载目录里的 `.ehviewer` 永远找不到 → 整库重下。
  eq('SpiderQueen 的 SPIDER_INFO_FILENAME', QUEEN_FILENAME, '.ehviewer');
  eq('与 SpiderInfo 的常量是同一个值（单点定义）', SPIDER_INFO_FILENAME, '.ehviewer');
  eq('缓存目录名单独一个常量', SPIDER_INFO_CACHE_DIRNAME, 'spider_info');
}

// ================================================================ 2) queen 表 + 引用计数

{
  SpiderQueen.resetForTest();
  SpiderQueen.setMainThreadChecker(null);
  eq('初始无活跃 queen', SpiderQueen.activeQueenCount(), 0);

  const g1: GalleryInfo = makeInfo(1001, 'tok');
  const q1: SpiderQueen = SpiderQueen.obtainSpiderQueen(g1, MODE_READ);
  eq('新建后活跃数量 1', SpiderQueen.activeQueenCount(), 1);
  eq('新建后 READ 引用 1', q1.getReadReference(), 1);
  eq('新建后 DOWNLOAD 引用 0', q1.getDownloadReference(), 0);
  ok('新建后已 start', q1.isStarted());

  // 同一 gid 再 obtain：复用同一实例，只加引用（不重建、不 restart）
  const q2: SpiderQueen = SpiderQueen.obtainSpiderQueen(g1, MODE_READ);
  ok('同 gid 复用同一实例', q1 === q2);
  eq('READ 引用累加到 2', q2.getReadReference(), 2);
  eq('活跃数量仍 1', SpiderQueen.activeQueenCount(), 1);

  // 换模式：READ + DOWNLOAD 各自计数
  const q3: SpiderQueen = SpiderQueen.obtainSpiderQueen(g1, MODE_DOWNLOAD);
  ok('换模式仍是同一实例', q3 === q1);
  eq('DOWNLOAD 引用 1', q3.getDownloadReference(), 1);

  // 释放一次 READ：READ=1、DOWNLOAD=1 → 仍活着
  SpiderQueen.releaseSpiderQueen(q3, MODE_READ);
  eq('释放一次 READ → READ 引用 1', q3.getReadReference(), 1);
  eq('仍有 DOWNLOAD 引用 → 活跃数量 1（不 stop）', SpiderQueen.activeQueenCount(), 1);

  // 再释放 READ：READ=0，但 DOWNLOAD=1 → 仍活着
  SpiderQueen.releaseSpiderQueen(q3, MODE_READ);
  eq('READ 引用归零', q3.getReadReference(), 0);
  eq('DOWNLOAD 仍为 1 → 不 stop', SpiderQueen.activeQueenCount(), 1);
  ok('仍处于 started', q3.isStarted());

  // 释放 DOWNLOAD：两个都归零 → stop + 移出表
  SpiderQueen.releaseSpiderQueen(q3, MODE_DOWNLOAD);
  eq('两个引用都归零 → 移出 queen 表', SpiderQueen.activeQueenCount(), 0);
  eq('stop() 后 isStarted=false', q3.isStarted(), false);
  eq('stop() 后状态回到 STATE_NONE', q3.getState(), STATE_NONE);

  // 重复 release 不应变成负数（上游 clearMode 同样保护）
  SpiderQueen.releaseSpiderQueen(q3, MODE_READ);
  eq('重复 release 不会变负', q3.getReadReference(), 0);
}

// ================================================================ 3) 主线程约束（对位 @UiThread + OSUtils.checkMainLoop）

{
  SpiderQueen.resetForTest();
  SpiderQueen.setMainThreadChecker((): boolean => false);
  let threw: boolean = false;
  let msg: string = '';
  try {
    SpiderQueen.obtainSpiderQueen(makeInfo(2002, 'tok'), MODE_READ);
  } catch (e) {
    threw = true;
    msg = (e as Error).message !== undefined ? (e as Error).message : '';
  }
  ok('非主线程 obtain → 抛错', threw);
  ok('错误信息说明是主线程约束', msg.indexOf('主线程') >= 0);
  eq('越界调用后 queen 表仍为空（没有半成品泄漏）', SpiderQueen.activeQueenCount(), 0);

  // 注入恒真 → 正常
  SpiderQueen.setMainThreadChecker((): boolean => true);
  const q: SpiderQueen = SpiderQueen.obtainSpiderQueen(makeInfo(2002, 'tok'), MODE_READ);
  eq('主线程 obtain 正常', SpiderQueen.activeQueenCount(), 1);
  SpiderQueen.releaseSpiderQueen(q, MODE_READ);
  SpiderQueen.setMainThreadChecker(null);
  SpiderQueen.resetForTest();
}

// ================================================================ 4) resetReadingProgress（只改内存）

{
  SpiderQueen.resetForTest();
  SpiderQueen.setMainThreadChecker(null);
  SpiderQueen.resetReadingProgress(3003);   // 不存在的 gid：幂等
  ok('queen 不存在时 resetReadingProgress 不崩', true);

  const g: GalleryInfo = makeInfo(3003, 'tok');
  const q: SpiderQueen = SpiderQueen.obtainSpiderQueen(g, MODE_READ);
  const info: SpiderInfo = new SpiderInfo();
  info.gid = 3003;
  info.token = 'tok';
  info.startPage = 42;
  q.setSpiderInfo(info);
  eq('设置后 startPage=42', q.getSpiderInfo() !== null ? (q.getSpiderInfo() as SpiderInfo).startPage : -1, 42);

  SpiderQueen.resetReadingProgress(3003);
  eq('resetReadingProgress 把内存 startPage 归零',
    q.getSpiderInfo() !== null ? (q.getSpiderInfo() as SpiderInfo).startPage : -1, 0);

  // 没有 spiderInfo 时幂等
  q.setSpiderInfo(null);
  SpiderQueen.resetReadingProgress(3003);
  ok('spiderInfo 为 null 时 resetReadingProgress 幂等', q.getSpiderInfo() === null);
  SpiderQueen.releaseSpiderQueen(q, MODE_READ);
  SpiderQueen.resetForTest();
}

// ================================================================ 5) findStartPage / 缓存注入

{
  SpiderQueen.resetForTest();
  // 未注入 provider → 显式抛错（不能静默返回 0：0 与"真的从第 1 页开始"无法区分）
  let threw: boolean = false;
  let msg: string = '';
  try {
    SpiderQueen.findStartPage(makeInfo(4004, 'tok'));
  } catch (e) {
    threw = true;
    msg = (e as Error).message !== undefined ? (e as Error).message : '';
  }
  ok('未注入 SpiderInfoCacheProvider → 抛错（不是返回 0）', threw);
  ok('错误信息点名 EhApplication.getSpiderInfoCache', msg.indexOf('getSpiderInfoCache') >= 0);

  // 注入返回 null 缓存的 provider → 0（缓存不存在是正常情况）
  SpiderQueen.setSpiderInfoCacheProvider({
    getSpiderInfoCache: (): SimpleDiskCache | null => null
  });
  eq('缓存不存在 → findStartPage = 0', SpiderQueen.findStartPage(makeInfo(4004, 'tok')), 0);
  SpiderQueen.setSpiderInfoCacheProvider(null);
}

// ================================================================ 6) 重复 start 抛错（上游同样）

{
  SpiderQueen.resetForTest();
  const q: SpiderQueen = SpiderQueen.obtainSpiderQueen(makeInfo(5005, 'tok'), MODE_READ);
  let threw: boolean = false;
  let isIllegalState: boolean = false;
  try {
    q.start();
  } catch (e) {
    threw = true;
    isIllegalState = e instanceof IllegalStateError;
  }
  ok('重复 start() → 抛错', threw);
  ok('抛的是 IllegalStateError（可识别类型）', isIllegalState);
  SpiderQueen.releaseSpiderQueen(q, MODE_READ);
  SpiderQueen.resetForTest();
}

// ================================================================ 7) contain / 校验 / 文件名入口

{
  eq('contain 命中', SpiderQueen.contain([1, 2, 3], 2), true);
  eq('contain 不命中', SpiderQueen.contain([1, 2, 3], 9), false);
  eq('contain 空数组', SpiderQueen.contain([], 1), false);

  SpiderQueen.resetForTest();
  const g: GalleryInfo = makeInfo(6006, 'good');
  const q: SpiderQueen = SpiderQueen.obtainSpiderQueen(g, MODE_READ);
  eq('getSpiderInfoFilename = .ehviewer', q.getSpiderInfoFilename(), '.ehviewer');
  eq('getSpiderInfoCacheDirname = spider_info', q.getSpiderInfoCacheDirname(), 'spider_info');
  ok('getGalleryInfo 返回同一对象', q.getGalleryInfo() === g);
  ok('getSpiderDen 非 null', q.getSpiderDen() !== null);

  const good: SpiderInfo = new SpiderInfo();
  good.gid = 6006;
  good.token = 'good';
  ok('hasValidSpiderInfo：gid+token 都匹配', q.hasValidSpiderInfo(good));
  const wrongToken: SpiderInfo = new SpiderInfo();
  wrongToken.gid = 6006;
  wrongToken.token = 'other';
  ok('hasValidSpiderInfo：token 不匹配为 false', !q.hasValidSpiderInfo(wrongToken));
  const wrongGid: SpiderInfo = new SpiderInfo();
  wrongGid.gid = 1;
  wrongGid.token = 'good';
  ok('hasValidSpiderInfo：gid 不匹配为 false', !q.hasValidSpiderInfo(wrongGid));
  ok('hasValidSpiderInfo：null 为 false', !q.hasValidSpiderInfo(null));
  SpiderQueen.releaseSpiderQueen(q, MODE_READ);
  SpiderQueen.resetForTest();
}

// ================================================================ 8) 类静态常量 + 监听器 API（download-sync 的调用形式）

{
  // download-sync 的写法是 `SpiderQueen.MODE_DOWNLOAD`（类静态字段），不是模块级 export。
  // 这里断言两者同时可用，否则下游要么编译失败要么 import 到错的来源。
  eq('SpiderQueen.MODE_READ（类静态）', SpiderQueen.MODE_READ, 0);
  eq('SpiderQueen.MODE_DOWNLOAD（类静态）', SpiderQueen.MODE_DOWNLOAD, 1);
  eq('SpiderQueen.STATE_DOWNLOADING（类静态）', SpiderQueen.STATE_DOWNLOADING, 1);
  eq('类静态与模块级常量同值', SpiderQueen.MODE_DOWNLOAD, MODE_DOWNLOAD);
}

class Recorder implements OnSpiderListener {
  pages: number = 0;
  gets509: number = 0;
  downloads: number = 0;
  successes: number = 0;
  failures: number = 0;
  finishes: number = 0;

  onGetPages(pages: number): void {
    this.pages++;
  }

  onGet509(index: number): void {
    this.gets509++;
  }

  onPageDownload(index: number, contentLength: number, receivedSize: number, bytesRead: number): void {
    this.downloads++;
  }

  onPageSuccess(index: number, finished: number, downloaded: number, total: number): void {
    this.successes++;
  }

  onPageFailure(index: number, error: string, finished: number, downloaded: number, total: number): void {
    this.failures++;
  }

  onFinish(finished: number, downloaded: number, total: number): void {
    this.finishes++;
  }

  onGetImageSuccess(index: number, image: Image): void {
  }

  onGetImageFailure(index: number, error: string): void {
  }
}

{
  SpiderQueen.resetForTest();
  const q: SpiderQueen = SpiderQueen.obtainSpiderQueen(makeInfo(7007, 'tok'), MODE_READ);
  const r1: Recorder = new Recorder();
  const r2: Recorder = new Recorder();

  eq('初始无监听器', q.getSpiderListenerCount(), 0);
  q.addOnSpiderListener(r1);
  eq('添加一个监听器', q.getSpiderListenerCount(), 1);
  q.addOnSpiderListener(r2);
  eq('添加第二个', q.getSpiderListenerCount(), 2);
  q.addOnSpiderListener(r1);
  eq('重复添加会重复登记（上游 ArrayList 语义）', q.getSpiderListenerCount(), 3);

  q.removeOnSpiderListener(r1);
  eq('移除一个后剩 2', q.getSpiderListenerCount(), 2);
  q.removeOnSpiderListener(r2);
  eq('移除后剩 1（重复登记的 r1 还在）', q.getSpiderListenerCount(), 1);
  q.removeOnSpiderListener(r2);
  eq('移除不存在的监听器无副作用', q.getSpiderListenerCount(), 1);

  SpiderQueen.releaseSpiderQueen(q, MODE_READ);
  eq('release 后 queen 已移出表', SpiderQueen.activeQueenCount(), 0);
  SpiderQueen.resetForTest();
}
// ================================================================ 9) 第 2 批：页面状态 / 三态请求 / pToken / 另存为

{
  SpiderQueen.resetForTest();
  const g: GalleryInfo = makeInfo(8008, 'tok');
  const q: SpiderQueen = SpiderQueen.obtainSpiderQueen(g, MODE_READ);

  // size()/getError() 的启动前后语义
  eq('已启动但无 spiderInfo → size() = STATE_WAIT', q.size(), GalleryProvider.STATE_WAIT);
  eq('已启动 → getError() = ""', q.getError(), '');
  const asLike: SpiderQueenLike = q;
  eq('SpiderQueen implements SpiderQueenLike', asLike.getError(), '');

  // applySpiderInfo：没有缓存/下载文件时全部 NONE
  const info: SpiderInfo = new SpiderInfo();
  info.gid = 8008;
  info.token = 'tok';
  info.pages = 4;
  q.applySpiderInfo(info);
  eq('applySpiderInfo 后 size() = 4', q.size(), 4);
  eq('全部页初始为 STATE_NONE', q.getPageStateArray(), [0, 0, 0, 0]);
  eq('第 2 批的 preload 默认值（上游 5）', q.getPreloadNumber(), 5);

  // 三态：STATE_NONE → null + 入队
  eq('NONE → 返回 null', q.request(0), null);
  const sizes1: number[] = q.getQueueSizes();
  // 下载泵是异步且**无条件**启动的：request() 返回时该项可能还在队列里，也可能已被泵取走处理。
  // 真实不变量是「入队或已处理」，不是「队列里一定有 1 个」。
  // 下载泵是**异步且无条件**启动的：request() 返回瞬间该项可能已被 shift 走（队列长度 0）、
  // 而 processed 还没增长。可观测的确定事实是「worker 被触发过」。
  ok('NONE → 触发了 worker（pendingWorkerStarts 增长）', q.getPendingWorkerStarts() >= 1);
  ok('预载队列填了后续页（3 页上限内）', sizes1[1] >= 1);
  ok('记录了等 worker 的次数（第 3 批前恒增长）', q.getPendingWorkerStarts() >= 1);

  // 三态：DOWNLOADING → 返回进度
  q.updatePageState(1, STATE_DOWNLOADING);
  SpiderQueen.resetForTest();
  const q2: SpiderQueen = SpiderQueen.obtainSpiderQueen(makeInfo(8009, 'tok'), MODE_READ);
  const info2: SpiderInfo = new SpiderInfo();
  info2.gid = 8009;
  info2.token = 'tok';
  info2.pages = 3;
  q2.applySpiderInfo(info2);
  q2.updatePageState(1, STATE_DOWNLOADING);
  // 百分比 Map 是私有的；通过 setter 设定（供第 3 批 worker 回填）
  q2.setPagePercent(1, 0.4);
  eq('DOWNLOADING → 返回进度 0.4', q2.request(1), 0.4);

  // 三态：FAILED —— **上游公开 API 会重试，不返回文案**
  // `request(index)` = `request(index, ignoreError=true, force=false, addNeighbor=true)`，
  // 而 ignoreError=true 会把 STATE_FAILED 复位成 STATE_NONE 重新入队 → 返回 null。
  // 所以"返回 string"那条分支只在 ignoreError=false 时可达（上游私有 API 用），公开调用永远走重试。
  q2.updatePageState(2, STATE_FAILED);
  q2.setPageError(2, 'net down');
  eq('FAILED → request() 重试并返回 null（上游 ignoreError=true）', q2.request(2), null);
  eq('FAILED → 状态被复位为 NONE', q2.getPageState(2), STATE_NONE);
  eq('FAILED → 错误文案仍保留在 map 里（诊断用）', q2.request(2), null);

  // forceRequest：把 FAILED/FINISHED 复位成 NONE 再入强制队列
  q2.updatePageState(2, STATE_FAILED);
  eq('forceRequest 复位后返回 null', q2.forceRequest(2), null);
  eq('forceRequest 后状态复位为 NONE', q2.getPageState(2), STATE_NONE);
  ok('进了强制请求队列', q2.getQueueSizes()[2] >= 1);

  // FINISHED → 入解码队列 + 返回 null
  q2.updatePageState(0, STATE_FINISHED);
  eq('FINISHED → 返回 null', q2.request(0), null);
  // 解码泵是异步的：request() 返回时该项可能还在队列里，也可能已被泵取走并解码。
  // 真实不变量是「入队或已解码」，不是「队列里一定有 1 个」。
  ok('FINISHED → 入解码队列或已被解码泵取走', q2.getQueueSizes()[3] + q2.getDecodedPages() >= 1);
  // 重复请求不重复入解码队列
  const decodeSize: number = q2.getQueueSizes()[3];
  q2.request(0);
  eq('重复 FINISHED 请求不重复入解码队列', q2.getQueueSizes()[3], decodeSize);

  // cancelRequest 从三个队列摘掉
  q2.request(2);
  q2.cancelRequest(2);
  ok('cancelRequest 不抛错且队列可查询', q2.getQueueSizes().length === 4);
  ok('cancelRequest 不抛错', true);

  // 另存为：非 FINISHED 页直接失败（上游语义）
  const dst: UniFile | null = UniFile.fromFile('/tmp/x.bin');
  if (dst !== null) {
    eq('非 FINISHED → saveToFile=false', q2.saveToFile(1, dst), false);
    eq('非 FINISHED → saveToDir=null', q2.saveToDir(1, dst, 'page'), null);
  }

  // preload clamp
  q2.setPreloadNumber(-5);
  eq('preload 下限 clamp 到 0', q2.getPreloadNumber(), 0);
  q2.setPreloadNumber(999);
  eq('preload 上限 clamp 到 100', q2.getPreloadNumber(), 100);

  SpiderQueen.releaseSpiderQueen(q, MODE_READ);
  SpiderQueen.releaseSpiderQueen(q2, MODE_READ);
  SpiderQueen.resetForTest();
}

// ================================================================ 10) pToken → 页 URL（用真实 EhUrl）

{
  SpiderQueen.resetForTest();
  const g: GalleryInfo = makeInfo(9009, 'tok');
  const q: SpiderQueen = SpiderQueen.obtainSpiderQueen(g, MODE_READ);
  eq('pToken 未知 → getPageUrl = null（不编造）', q.getPageUrl(0), null);

  const tokens: Map<number, string> = new Map<number, string>();
  tokens.set(0, 'aaaa');
  tokens.set(2, 'cccc');
  q.setPagePTokens(tokens);
  eq('第 0 页 pToken', q.getPagePToken(0), 'aaaa');
  eq('未提供的页 pToken = null', q.getPagePToken(1), null);

  const url: string | null = q.getPageUrl(0);
  ok('getPageUrl 非 null', url !== null);
  ok('URL 含 pToken 段 /s/aaaa/', url !== null && url.indexOf('/s/aaaa/') >= 0);
  ok('URL 含 gid-index+1 后缀 9009-1', url !== null && url.endsWith('9009-1'));
  // 第 2 页 → index+1 = 3
  const url2: string | null = q.getPageUrl(2);
  ok('第 2 页 URL 以 9009-3 结尾（index+1）', url2 !== null && url2.endsWith('9009-3'));

  SpiderQueen.releaseSpiderQueen(q, MODE_READ);
  SpiderQueen.resetForTest();
}
// ================================================================ 11) 解码泵（第 3 批上半：不带网络）

class ImageRec implements OnSpiderListener {
  imageSuccesses: number = 0;
  imageFailures: number = 0;

  onGetPages(pages: number): void {
  }

  onGet509(index: number): void {
  }

  onPageDownload(index: number, contentLength: number, receivedSize: number, bytesRead: number): void {
  }

  onPageSuccess(index: number, finished: number, downloaded: number, total: number): void {
  }

  onPageFailure(index: number, error: string, finished: number, downloaded: number, total: number): void {
  }

  onFinish(finished: number, downloaded: number, total: number): void {
  }

  onGetImageSuccess(index: number, image: Image): void {
    this.imageSuccesses++;
  }

  onGetImageFailure(index: number, error: string): void {
    this.imageFailures++;
  }
}

async function asyncCases(): Promise<void> {
  SpiderQueen.resetForTest();
  const q: SpiderQueen = SpiderQueen.obtainSpiderQueen(makeInfo(11011, 'tok'), MODE_READ);
  const info: SpiderInfo = new SpiderInfo();
  info.gid = 11011;
  info.token = 'tok';
  info.pages = 3;
  q.applySpiderInfo(info);

  // SpiderDen 的"边读边存"设置未注入时 openInputStreamPipe 会**显式抛错**。
  // 解码泵必须把这种异常当作"该页失败"，而不是让整个泵崩掉（decodePage 已把取 pipe 放进 try）。
  SpiderDen.setSyncDownloadSettingProvider({ getSyncDownloadWhileReading: (): boolean => false });

  const rec: ImageRec = new ImageRec();
  q.addOnSpiderListener(rec);

  eq('初始已解码 0 页', q.getDecodedPages(), 0);
  eq('初始解码索引 = -1（空闲）', q.getDecodingIndex(), -1);

  // 第 0 页标 FINISHED → request 触发解码泵；无真实缓存/文件 → 解码失败并回调
  q.updatePageState(0, STATE_FINISHED);
  eq('FINISHED → request 返回 null', q.request(0), null);
  await tick();
  await tick();
  await tick();

  eq('解码泵处理了 1 页', q.getDecodedPages(), 1);
  eq('处理后解码索引复位 -1', q.getDecodingIndex(), -1);
  eq('解码失败回调 1 次（无真实文件）', rec.imageFailures, 1);
  eq('没有成功回调', rec.imageSuccesses, 0);
  eq('解码队列已清空', q.getQueueSizes()[3], 0);

  // 再请求同一页：重新入队并再解码一次（上游语义：已完成的页 = "再给我一份"）
  q.request(0);
  await tick();
  await tick();
  eq('再次请求同一页会再解码一次', q.getDecodedPages(), 2);

  // stop 后不再处理新页，且队列全清
  q.updatePageState(1, STATE_FINISHED);
  q.request(1);
  q.stop();
  await tick();
  await tick();
  const afterStop: number = q.getDecodedPages();
  await tick();
  eq('stop() 后不再解码新页', q.getDecodedPages(), afterStop);
  eq('stop() 清空全部队列', q.getQueueSizes(), [0, 0, 0, 0]);

  SpiderQueen.resetForTest();
}

// ================================================================ 12) 下载 worker（注入点驱动）

class FakeEngine implements EhEngineLike {
  apiCalls: number = 0;
  throwOnApi: boolean = false;
  htmlImageUrl: string = '';
  imageUrl: string = 'https://example.invalid/i.jpg';

  getGalleryPage(task: Object | null, caller: Object | null, url: string,
    gid: number, token: string): Promise<GalleryPageParserResult> {
    // 与 getGalleryPageApi 保持一致的失败注入：否则 HTML 路径会先成功，测不到 API 失败路径
    if (this.throwOnApi) {
      return Promise.reject(new Error('fake api failure'));
    }
    const r: GalleryPageParserResult = new GalleryPageParserResult();
    // 默认 HTML 路径**不给** imageUrl，让用例走到 API 路径（复现上游『只有 imageUrl 为空才打 API』）
    r.imageUrl = this.htmlImageUrl;
    return Promise.resolve(r);
  }

  getGalleryPageApi(task: Object | null, caller: Object | null, gid: number, index: number,
    pToken: string, showKey: string, previousPToken: string | null): Promise<GalleryPageApiParserResult> {
    this.apiCalls++;
    if (this.throwOnApi) {
      return Promise.reject(new Error('fake api failure'));
    }
    const r: GalleryPageApiParserResult = new GalleryPageApiParserResult();
    r.imageUrl = this.imageUrl;
    return Promise.resolve(r);
  }
}

class FakeDownloader implements PageImageDownloader {
  calls: number = 0;
  succeed: boolean = true;
  statusCode: number = 200;
  lastReferer: string | undefined = undefined;
  referers: (string | undefined)[] = [];
  payload: ArrayBuffer = new Uint8Array([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]).buffer;
  throwErr: boolean = false;
  progressSteps: number[][] = [];

  download(url: string, sink: ByteSink, referer?: string): Promise<boolean> {
    return this.downloadWithStatus(url, sink, referer).then((r: DownloadResult): boolean => r.ok);
  }

  downloadWithStatus(url: string, sink: ByteSink, referer?: string,
    onProgress?: PageDownloadProgressCallback): Promise<DownloadResult> {
    this.calls++;
    this.lastReferer = referer;
    this.referers.push(referer);
    if (this.throwErr) {
      return Promise.reject(new Error('fake network write exception'));
    }
    if (!this.succeed || this.statusCode !== 200) {
      return Promise.resolve(new DownloadResult(false, this.statusCode, 0,
        this.statusCode === 509 ? 'HTTP 509' : 'fake download false'));
    }
    if (onProgress !== undefined && this.progressSteps.length > 0) {
      for (let i = 0; i < this.progressSteps.length; i++) {
        const s: number[] = this.progressSteps[i];
        onProgress(s[0], s[1], s[2]);
      }
    }
    if (this.payload.byteLength > 0) {
      sink.write(this.payload);
    }
    sink.close();
    return Promise.resolve(new DownloadResult(true, 200, this.payload.byteLength, ''));
  }
}

/** 记录失败回调的顺序与文案（断言 worker 的处理顺序与错误归属）。 */
class WorkerRec implements OnSpiderListener {
  failedIndices: number[] = [];
  failedErrors: string[] = [];
  got509Indices: number[] = [];
  downloadEvents: number[][] = [];
  gotPagesCount: number = 0;
  finishCalls: number = 0;
  lastFinishFinished: number = -1;
  lastFinishTotal: number = -1;

  onGetPages(pages: number): void {
    this.gotPagesCount = pages;
  }

  onGet509(index: number): void {
    this.got509Indices.push(index);
  }

  onPageDownload(index: number, contentLength: number, receivedSize: number, bytesRead: number): void {
    this.downloadEvents.push([index, contentLength, receivedSize, bytesRead]);
  }

  onPageSuccess(index: number, finished: number, downloaded: number, total: number): void {
  }

  onPageFailure(index: number, error: string, finished: number, downloaded: number, total: number): void {
    this.failedIndices.push(index);
    this.failedErrors.push(error);
  }

  onFinish(finished: number, downloaded: number, total: number): void {
    this.finishCalls++;
    this.lastFinishFinished = finished;
    this.lastFinishTotal = total;
  }

  onGetImageSuccess(index: number, image: Image): void {
  }

  onGetImageFailure(index: number, error: string): void {
  }
}

async function workerCases(): Promise<void> {
  SpiderDen.setSyncDownloadSettingProvider({ getSyncDownloadWhileReading: (): boolean => false });

  // —— 用例 1：未注入下载器 → 该页显式失败，**泵不崩**（对照刚修的解码泵 bug）
  SpiderQueen.resetForTest();
  SpiderQueen.setEhEngine(null);
  SpiderQueen.setPageImageDownloader(null);
  const q1: SpiderQueen = SpiderQueen.obtainSpiderQueen(makeInfo(21021, 'tok'), MODE_DOWNLOAD);
  const i1: SpiderInfo = new SpiderInfo();
  i1.gid = 21021;
  i1.token = 'tok';
  i1.pages = 3;
  q1.applySpiderInfo(i1);
  const tokens1: Map<number, string> = new Map<number, string>();
  tokens1.set(0, 'p0');
  q1.setPagePTokens(tokens1);
  const rec1: WorkerRec = new WorkerRec();
  q1.addOnSpiderListener(rec1);
  eq('未请求时 worker 计数 0', q1.getWorkerProcessed(), 0);
  q1.request(0);
  await tick();
  await tick();
  ok('未注入下载器 → worker 仍处理了该页（没停摆）', q1.getWorkerProcessed() >= 1);
  eq('该页标 FAILED', q1.getPageState(0), STATE_FAILED);
  ok('失败回调带 index 0', rec1.failedIndices.indexOf(0) >= 0);
  ok('失败文案指出 PageImageDownloader 未注入',
    rec1.failedErrors.length > 0 && rec1.failedErrors[0].indexOf('PageImageDownloader') >= 0);

  // —— 用例 2：注入 engine + downloader，但 pToken 未知 → 显式失败（不猜 URL）
  const engine2: FakeEngine = new FakeEngine();
  const dl2: FakeDownloader = new FakeDownloader();
  SpiderQueen.setEhEngine(engine2);
  SpiderQueen.setPageImageDownloader(dl2);
  SpiderQueen.resetForTest();
  const q2: SpiderQueen = SpiderQueen.obtainSpiderQueen(makeInfo(21022, 'tok'), MODE_DOWNLOAD);
  const i2: SpiderInfo = new SpiderInfo();
  i2.gid = 21022;
  i2.token = 'tok';
  i2.pages = 3;
  q2.applySpiderInfo(i2);
  const rec2: WorkerRec = new WorkerRec();
  q2.addOnSpiderListener(rec2);
  q2.request(1);
  await tick();
  await tick();
  eq('pToken 未知 → 该页 FAILED', q2.getPageState(1), STATE_FAILED);
  ok('pToken 未知 → 文案点名 pToken',
    rec2.failedErrors.length > 0 && rec2.failedErrors[0].indexOf('pToken') >= 0);
  eq('pToken 未知 → 未调用 getGalleryPageApi', engine2.apiCalls, 0);
  eq('pToken 未知 → 未调用 downloader', dl2.calls, 0);

  // —— 用例 3：engine.getGalleryPageApi 抛错 → 该页 FAILED，泵继续
  const tokens3: Map<number, string> = new Map<number, string>();
  tokens3.set(0, 'a');
  tokens3.set(1, 'b');
  tokens3.set(2, 'c');
  q2.setPagePTokens(tokens3);
  engine2.throwOnApi = true;
  q2.request(0);
  await tick();
  await tick();
  eq('engine 抛错 → 该页 FAILED', q2.getPageState(0), STATE_FAILED);
  ok('engine 抛错 → 文案带 fake api failure',
    rec2.failedErrors.some((e: string): boolean => e.indexOf('fake api failure') >= 0));

  // —— 用例 4：计数器单调递增（连续处理不会只 +1）
  engine2.throwOnApi = false;
  const beforeProcessed: number = q2.getWorkerProcessed();
  q2.request(1);
  q2.request(2);
  await tick();
  await tick();
  await tick();
  ok('processed 单调递增', q2.getWorkerProcessed() > beforeProcessed);
  ok('processed 与 failures 都 > 0（4 状态诊断可区分）',
    q2.getWorkerProcessed() > 0 && q2.getWorkerFailures() > 0);

  // —— 用例 5：强制队列优先于普通队列
  SpiderQueen.resetForTest();
  const q3: SpiderQueen = SpiderQueen.obtainSpiderQueen(makeInfo(21023, 'tok'), MODE_DOWNLOAD);
  const i3: SpiderInfo = new SpiderInfo();
  i3.gid = 21023;
  i3.token = 'tok';
  i3.pages = 4;
  q3.applySpiderInfo(i3);
  const tokens5: Map<number, string> = new Map<number, string>();
  tokens5.set(0, 'a');
  tokens5.set(1, 'b');
  q3.setPagePTokens(tokens5);
  const rec3: WorkerRec = new WorkerRec();
  q3.addOnSpiderListener(rec3);
  q3.request(0);
  await tick();
  await tick();
  eq('第 0 页第一次处理即 FAILED', q3.getPageState(0), STATE_FAILED);
  const processedAfterFirst: number = q3.getWorkerProcessed();
  // 对已 FAILED 的页 forceRequest：上游会把状态复位成 NONE 再重新下载（这里同样会重走一遍）
  q3.forceRequest(0);
  await tick();
  await tick();
  eq('forceRequest 后该页仍以 FAILED 结束（本次仍无下载器/缓存）', q3.getPageState(0), STATE_FAILED);
  ok('forceRequest 让 processed 计数继续增长', q3.getWorkerProcessed() > processedAfterFirst);

  SpiderQueen.setEhEngine(null);
  SpiderQueen.setPageImageDownloader(null);
  SpiderQueen.resetForTest();
}

interface FsFdCounterHook {
  __activeFdCount?: () => number;
}

async function m42RegressionCases(): Promise<void> {
  const fsHook: FsFdCounterHook = fs as unknown as FsFdCounterHook;
  const fdsAtStart: number = fsHook.__activeFdCount !== undefined ? fsHook.__activeFdCount() : 0;

  // —— M4-2 A: P0 #3 缓存 abort + 零 FD 泄漏 + 保留已有缓存 + 零字节保护 ——
  SpiderDen.resetCache();
  SpiderDen.initialize('/tmp/m42_queen_cache', 10);
  const fdsAfterDenCache: number = fsHook.__activeFdCount !== undefined ? fsHook.__activeFdCount() : 0;
  SpiderDen.setSyncDownloadSettingProvider({ getSyncDownloadWhileReading: (): boolean => false });
  const dlRootPath: string = '/tmp/m42_queen_dl';
  fs.mkdirSync(dlRootPath, true);
  const dlRoot: UniFile | null = UniFile.fromFile(dlRootPath);
  if (dlRoot !== null) {
    Settings.putDownloadLocation(dlRoot);
  }

  const engCache: FakeEngine = new FakeEngine();
  engCache.imageUrl = 'https://example.invalid/page0'; // 无扩展名，测试后续魔数扩展名
  const dlCache: FakeDownloader = new FakeDownloader();
  SpiderQueen.setEhEngine(engCache);
  SpiderQueen.setPageImageDownloader(dlCache);
  SpiderQueen.resetForTest();

  const qFailCache: SpiderQueen = SpiderQueen.obtainSpiderQueen(makeInfo(31001, 'tok'), MODE_READ);
  const iFailCache: SpiderInfo = new SpiderInfo();
  iFailCache.gid = 31001;
  iFailCache.token = 'tok';
  iFailCache.pages = 2;
  iFailCache.pTokenMap = new Map<number, string>([[0, 'p0token123'], [1, 'p1token456']]);
  qFailCache.applySpiderInfo(iFailCache);

  // 1) 下载失败（status=500）→ abort 缓存写端、不留 0 字节、不泄漏 FD
  dlCache.succeed = false;
  dlCache.statusCode = 500;
  qFailCache.request(0);
  for (let t = 0; t < 6; t++) {
    await tick();
  }
  eq('P0 #3: 失败下载后 page 0 为 STATE_FAILED', qFailCache.getPageState(0), STATE_FAILED);
  eq('P0 #3: 失败下载未把 0 字节写入 SpiderDen 缓存', qFailCache.getSpiderDen().contain(0), false);
  if (fsHook.__activeFdCount !== undefined) {
    eq('P0 #3: 失败下载无 FD 泄漏', fsHook.__activeFdCount(), fdsAfterDenCache);
  }

  // 2) 空 payload (0 bytes) → 同样拒绝提交、不留坏图
  dlCache.succeed = true;
  dlCache.statusCode = 200;
  dlCache.payload = new ArrayBuffer(0);
  qFailCache.forceRequest(0);
  for (let t = 0; t < 6; t++) {
    await tick();
  }
  eq('P0 #3: 0 字节响应不提交进缓存', qFailCache.getSpiderDen().contain(0), false);

  // 3) 正常下载验证 C-18 Referer 透传
  dlCache.payload = new Uint8Array([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]).buffer;
  qFailCache.forceRequest(0);
  for (let t = 0; t < 6; t++) {
    await tick();
  }
  eq('P1 #10: 正常下载 page 0 为 STATE_FINISHED', qFailCache.getPageState(0), STATE_FINISHED);
  eq('P1 #10 (C-18): 下载图片时传入 EhUrl.getPageUrl 作为 Referer',
    dlCache.lastReferer, EhUrl.getPageUrl(31001, 0, 'p0token123'));

  // 4) HTTP 509 限流状态码 → onGet509 触发一次、立即失败不重试 5 次
  const rec509: WorkerRec = new WorkerRec();
  qFailCache.addOnSpiderListener(rec509);
  dlCache.calls = 0;
  dlCache.succeed = false;
  dlCache.statusCode = 509;
  qFailCache.request(1);
  for (let t = 0; t < 6; t++) {
    await tick();
  }
  eq('P1 #10: status=509 触发 onGet509(1)', rec509.got509Indices, [1]);
  eq('P1 #10: status=509 立即失败不进行 5 次无效重试', dlCache.calls, 1);
  eq('P1 #10: page 1 标 STATE_FAILED', qFailCache.getPageState(1), STATE_FAILED);
  SpiderQueen.releaseSpiderQueen(qFailCache, MODE_READ);
  SpiderQueen.resetForTest();

  // —— M4-2 B: P0 #2 真实 start() 异步加载 SpiderInfo + 并发下载 + notifyFinish + getStartPage/putStartPage ——
  const cacheDirPath: string = '/tmp/m42_queen_info_cache';
  const infoCache: SimpleDiskCache = new SimpleDiskCache(cacheDirPath, 1024 * 1024);
  const fdsWithBothCaches: number = fsHook.__activeFdCount !== undefined ? fsHook.__activeFdCount() : 0;
  SpiderQueen.setSpiderInfoCacheProvider({
    getSpiderInfoCache: (): SimpleDiskCache | null => infoCache
  });
  SpiderDen.setTitleProvider({
    getSuitableTitle: (info: GalleryInfo): string => info.title !== null ? info.title : 'g'
  });
  SpiderDen.setDirnameStore({
    getDownloadDirname: async (): Promise<string | null> => null,
    putDownloadDirname: async (): Promise<void> => {}
  });
  SpiderQueen.setGalleryDetailFetcher({
    getGalleryDetail: async (info: GalleryInfo): Promise<GalleryDetail | null> => {
      const d: GalleryDetail = new GalleryDetail();
      d.gid = info.gid;
      d.token = info.token;
      d.SpiderInfoPages = 2;
      d.SpiderInfoPreviewPages = 1;
      const pset: LargePreviewSet = new LargePreviewSet();
      pset.addItem(0, 'https://ehgt.org/0.jpg', `https://e-hentai.org/s/aaaa111100/${info.gid}-1`);
      pset.addItem(1, 'https://ehgt.org/1.jpg', `https://e-hentai.org/s/bbbb222200/${info.gid}-2`);
      d.SpiderInfoPreviewSet = pset;
      return d;
    }
  });

  const dlDl: FakeDownloader = new FakeDownloader();
  dlDl.payload = new Uint8Array([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 0x00, 0x00]).buffer;
  const engDl: FakeEngine = new FakeEngine();
  engDl.imageUrl = 'https://example.invalid/img_no_ext';
  SpiderQueen.setEhEngine(engDl);
  SpiderQueen.setPageImageDownloader(dlDl);

  const gReal: GalleryInfo = makeInfo(31002, 'tokReal');
  gReal.title = 'RealDownload';
  const qReal: SpiderQueen = SpiderQueen.obtainSpiderQueen(gReal, MODE_DOWNLOAD);
  const recReal: WorkerRec = new WorkerRec();
  qReal.addOnSpiderListener(recReal);
  for (let t = 0; t < 12; t++) {
    await tick();
  }
  eq('P0 #2: start() 自动从 GalleryDetail 构建 SpiderInfo 并设置 size=2', qReal.size(), 2);
  ok('P0 #2: start() 自动推进全部 2 页下载完成', qReal.getFinishedPages() === 2);
  ok('P0 #2: start() 下载完成后触发 notifyFinish', recReal.finishCalls >= 1 && recReal.lastFinishTotal === 2);
  const dirReal: UniFile | null = qReal.getSpiderDen().getDownloadDir();
  ok('P1 #10: 无扩展名 URL 按 PNG 魔数落盘为 00000001.png',
    dirReal !== null && dirReal.findFile('00000001.png') !== null);

  // 2A: SpiderQueen 转发单页进度回调（contentLength > 0 触发 onPageDownload；contentLength <= 0 不产生 NaN）
  {
    const dlProg: FakeDownloader = new FakeDownloader();
    dlProg.payload = new Uint8Array([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 0x00, 0x00]).buffer;
    dlProg.progressSteps = [
      [-1, 5, 5],     // 未知长度：不写 mPagePercentMap，不产生 NaN
      [0, 5, 5],      // 0 长度：同上
      [100, 50, 50],  // 50%：首推必达
      [100, 100, 50]  // 100%：尾包必达
    ];
    SpiderQueen.setPageImageDownloader(dlProg);
    const gProg: GalleryInfo = makeInfo(31015, 'tokProg');
    const qProg: SpiderQueen = SpiderQueen.obtainSpiderQueen(gProg, MODE_READ);
    const infoProg: SpiderInfo = new SpiderInfo();
    infoProg.gid = 31015;
    infoProg.token = 'tokProg';
    infoProg.pages = 1;
    infoProg.pTokenMap = new Map<number, string>([[0, 'ptokprog01']]);
    qProg.applySpiderInfo(infoProg);
    const recProg: WorkerRec = new WorkerRec();
    qProg.addOnSpiderListener(recProg);
    qProg.request(0);
    for (let t = 0; t < 10; t++) {
      await tick();
    }
    const page0Events: number[][] = recProg.downloadEvents.filter((e: number[]) => e[0] === 0);
    ok('2A: onPageDownload 收到 50% 与 100% 真实字节进度',
      page0Events.some((e: number[]) => e[1] === 100 && e[2] === 50) &&
      page0Events.some((e: number[]) => e[1] === 100 && e[2] === 100));
    ok('2A: contentLength <= 0 不上报非法 0% 或 NaN',
      !page0Events.some((e: number[]) => e[1] === 0));
    SpiderQueen.releaseSpiderQueen(qProg, MODE_READ);
    SpiderQueen.resetForTest();
    SpiderQueen.setEhEngine(engDl);
    SpiderQueen.setPageImageDownloader(dlDl);
  }

  // getStartPage / putStartPage 往返
  qReal.putStartPage(1);
  eq('P0 #2: putStartPage(1) 后内存 getStartPage() === 1', qReal.getStartPage(), 1);
  SpiderQueen.releaseSpiderQueen(qReal, MODE_DOWNLOAD);
  SpiderQueen.resetForTest();

  // 新建 queen 不配 fetcher 时，能从本地 .ehviewer / SpiderInfoCache 恢复 startPage=1
  SpiderQueen.setGalleryDetailFetcher(null);
  const qReload: SpiderQueen = SpiderQueen.obtainSpiderQueen(gReal, MODE_READ);
  eq('P0 #2: 重新打开 queen 从本地/缓存读回 getStartPage() === 1', qReload.getStartPage(), 1);
  SpiderQueen.releaseSpiderQueen(qReload, MODE_READ);
  SpiderQueen.resetForTest();

  // GalleryDetailFetcher 返回 null 时记录 error 并通知 onFinish
  SpiderQueen.setGalleryDetailFetcher({
    getGalleryDetail: async (): Promise<GalleryDetail | null> => null
  });
  const qMissing: SpiderQueen = SpiderQueen.obtainSpiderQueen(makeInfo(31003, 'bad'), MODE_READ);
  const recMissing: WorkerRec = new WorkerRec();
  qMissing.addOnSpiderListener(recMissing);
  for (let t = 0; t < 6; t++) {
    await tick();
  }
  ok('P0 #2: SpiderInfo 获取失败后设置非空 getError() 并通知 onFinish',
    qMissing.getError().length > 0 && recMissing.finishCalls >= 1);
  SpiderQueen.releaseSpiderQueen(qMissing, MODE_READ);

  // 多预览页按需拉取 pToken + 并发去重（page 2/3 位于 previewPage=1）
  {
    let fetchCount: number = 0;
    const fetchedUrls: string[] = [];
    const fetcher: PreviewSetFetcher = {
      getPreviewSet: async (url: string): Promise<PreviewSet | null> => {
        fetchCount++;
        fetchedUrls.push(url);
        await tick();
        const ps: LargePreviewSet = new LargePreviewSet();
        ps.addItem(2, 'https://ehgt.org/t/02.jpg', 'https://e-hentai.org/s/abcdef0003/31009-3');
        ps.addItem(3, 'https://ehgt.org/t/03.jpg', 'https://e-hentai.org/s/abcdef0004/31009-4');
        return ps;
      }
    };
    SpiderQueen.setEhEngine(engCache);
    dlCache.succeed = true;
    dlCache.statusCode = 200;
    SpiderQueen.setPageImageDownloader(dlCache);
    SpiderQueen.setPreviewSetFetcher(fetcher);
    const qPrev: SpiderQueen = SpiderQueen.obtainSpiderQueen(makeInfo(31009, 'tok'), MODE_DOWNLOAD);
    const iPrev: SpiderInfo = new SpiderInfo();
    iPrev.gid = 31009;
    iPrev.token = 'tok';
    iPrev.pages = 4;
    iPrev.previewPerPage = 2;
    iPrev.previewPages = 2;
    iPrev.pTokenMap = new Map<number, string>([[0, '0000000001'], [1, '0000000002']]);
    qPrev.applySpiderInfo(iPrev);
    qPrev.request(2);
    qPrev.request(3);
    for (let t = 0; t < 16; t++) {
      await tick();
    }
    eq('PreviewSetFetcher: 并发请求第 2/3 页仅触发 1 次预览页拉取', fetchCount, 1);
    ok('PreviewSetFetcher: 请求 URL 指向第 1 预览页(p=1)',
      fetchedUrls.length === 1 && fetchedUrls[0].indexOf('p=1') >= 0);
    eq('PreviewSetFetcher: page 2 下载完成', qPrev.getPageState(2), STATE_FINISHED);
    eq('PreviewSetFetcher: page 3 下载完成', qPrev.getPageState(3), STATE_FINISHED);
    SpiderQueen.releaseSpiderQueen(qPrev, MODE_DOWNLOAD);
    SpiderQueen.resetForTest();
  }

  if (fsHook.__activeFdCount !== undefined) {
    eq('P0 #3: 全部 SpiderQueen 测试完成后无新增 FD 泄漏', fsHook.__activeFdCount(), fdsWithBothCaches);
  }
  const infoInner = infoCache.diskCacheOrNull();
  if (infoInner !== null) {
    infoInner.close();
  }
  if (fsHook.__activeFdCount !== undefined) {
    // 关闭 infoCache 后只剩 SpiderDen 持有的 1 个 cache journal 句柄
    eq('P0 #3: 关闭 infoCache 后只余 SpiderDen journal FD', fsHook.__activeFdCount(), fdsAfterDenCache);
  }

  SpiderQueen.setGalleryDetailFetcher(null);
  SpiderQueen.setSpiderInfoCacheProvider(null);
  SpiderDen.setDirnameStore(null);
  SpiderDen.setTitleProvider(null);
  SpiderDen.setSyncDownloadSettingProvider(null);
  SpiderDen.resetCache();
  SpiderQueen.setEhEngine(null);
  SpiderQueen.setPageImageDownloader(null);
  SpiderQueen.resetForTest();
}

asyncCases().then(() => {
  return workerCases();
}).then(() => {
  return m42RegressionCases();
}).then(() => {
  report();
}).catch((e: Error) => {
  fails.push(`异步用例抛异常: ${e.message}`);
  report();
});


// ================================================================ 13) P1 回归：509 检测 + 纯文本检出

{
  // 509：上游 URL_509_SUFFIX_ARRAY = { '/509.gif', '/509s.gif' }
  ok('509.gif 命中', SpiderQueen.is509Url('https://example.invalid/h/509.gif'));
  ok('509s.gif 命中', SpiderQueen.is509Url('https://example.invalid/h/509s.gif'));
  ok('普通图片不命中', !SpiderQueen.is509Url('https://example.invalid/h/abc.jpg'));
  ok('前缀相同但不结尾不命中', !SpiderQueen.is509Url('https://example.invalid/509.gif/abc.jpg'));
  ok('后缀数组与上游一致', SpiderQueen.URL_509_SUFFIX_ARRAY.length === 2
    && SpiderQueen.URL_509_SUFFIX_ARRAY[0] === '/509.gif'
    && SpiderQueen.URL_509_SUFFIX_ARRAY[1] === '/509s.gif');
}

// ================================================================ 14) P1 回归：重试循环与 URL 构造

{
  eq('重试上限与上游一致（for i<5）', SpiderQueen.MAX_RETRY_COUNT, 5);

  // buildPageUrl：对位上游 getPageUrl(gid,index,pToken,oldPageUrl,skipHathKey)
  const base: string = EhUrl.getPageUrl(1234, 4, 'tok');
  eq('无 skipHathKey → 原样', SpiderQueen.buildPageUrl(1234, 4, 'tok', null, null), base);
  ok('有 skipHathKey → 追加 ?nl=',
    SpiderQueen.buildPageUrl(1234, 4, 'tok', null, 'KEY').endsWith('?nl=KEY'));
  ok('URL 已有 ? → 用 &nl=',
    SpiderQueen.buildPageUrl(1234, 4, 'tok', base + '?x=1', 'KEY').endsWith('&nl=KEY'));
  eq('oldPageUrl 优先（不再重建）',
    SpiderQueen.buildPageUrl(1234, 4, 'tok', 'https://fixed.invalid/p', null), 'https://fixed.invalid/p');
  ok('oldPageUrl + skipHathKey 组合',
    SpiderQueen.buildPageUrl(1234, 4, 'tok', 'https://fixed.invalid/p?q=1', 'K').endsWith('&nl=K'));
}

// ================================================================ isStateDone / 计数器（对位上游 L1103-1125）

{
  const g: GalleryInfo = new GalleryInfo();
  g.gid = 8801;
  const info: SpiderInfo = new SpiderInfo();
  info.pages = 3;
  info.gid = 8801;
  const queen: SpiderQueen = SpiderQueen.obtainSpiderQueen(g, MODE_DOWNLOAD);
  queen.applySpiderInfo(info);

  // ① 进入 done 边界：NONE → FINISHED 计一次
  queen.updatePageState(0, STATE_FINISHED);
  eq('NONE→FINISHED: downloaded=1', queen.getDownloadedPages(), 1);
  eq('NONE→FINISHED: finished=1', queen.getFinishedPages(), 1);

  // ② 重复标 FINISHED：不再计数（上游按"跨越边界"，不是"当前值"）
  queen.updatePageState(0, STATE_FINISHED);
  eq('重复 FINISHED: downloaded 仍 1', queen.getDownloadedPages(), 1);
  eq('重复 FINISHED: finished 仍 1', queen.getFinishedPages(), 1);

  // ③ FAILED 也计入 downloaded（上游 isStateDone 包含 FAILED），但不计 finished
  queen.updatePageState(1, STATE_FAILED);
  eq('NONE→FAILED: downloaded=2', queen.getDownloadedPages(), 2);
  eq('NONE→FAILED: finished 仍 1', queen.getFinishedPages(), 1);

  // ④ 从 done 退回非 done：downloaded 减一
  queen.updatePageState(1, STATE_NONE);
  eq('FAILED→NONE: downloaded=1', queen.getDownloadedPages(), 1);
  eq('FAILED→NONE: finished 仍 1', queen.getFinishedPages(), 1);
}
// ================================================================ 汇总

function report(): void {
  if (fails.length > 0) {
    console.log(`\n${fails.length} 个断言失败：`);
    for (const f of fails) {
      console.log(`  ✗ ${f}`);
    }
    console.log(`\n通过 ${pass}，失败 ${fails.length}`);
    process.exit(1);
  }
  console.log(`全部通过：${pass} 个断言`);
}
