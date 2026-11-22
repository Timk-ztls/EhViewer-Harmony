/*
 * ①② 装配层需要的 8 个 Null*Host / Null*Api —— 让 8 个逻辑场景能在 `AppWiring` 的
 * `registerAllScenes(app, overrides)` 里被构造出来（否则只能传 null → 第一次调用就崩）。
 *
 * 三条统一约定（同 NullDownloadManager / MainPageHost）：
 *   · warn-once：每个方法一条，避免列表滚动/分页时刷屏（UnavailableLocalFavorites 的教训）
 *   · 返回值语义正确：列表 → []；bool → false；Promise → resolve 而非 reject
 *     （reject 会让页面走错误态，而真实状态是"未接线"）
 *   · 调用计数：每个 host 一个 callCount（继承自基类），让测试断言"真的调到了"（T-01 同族）
 *
 * 方法签名逐条来自各场景文件的 `export interface ...Host/Api/Port`（grep 接口体，不抄注释概述）。
 * 这些是**临时实现**：真实宿主就绪后由 AppWiring 的 overrides 替换。
 */
import { hilog } from '@kit.PerformanceAnalysisKit';
import { Announcer } from '../../../scene/Announcer';
import { GalleryInfo } from '../../client/data/GalleryInfo';
import { HistoryInfo } from '../../dao/HistoryInfo';
import { DownloadLabel } from '../../dao/DownloadLabel';
import { EhTopListDetail } from '../../client/data/TopList';
import { UserTag, UserTagList } from '../../client/data/UserTag';
import { GalleryPreview } from '../../client/data/GalleryPreview';
import { ListUrlBuilderSpec } from './topList/EhTopListScene';
import { HistorySceneHost } from './history/HistoryScene';
import { LabelsSceneHost } from './download/DownloadLabelsScene';
import { TopListSceneHost, TopListApi } from './topList/EhTopListScene';
import { SubscriptionsSceneHost, SubscriptionsApi } from './gallery/list/SubscriptionsScene';
import { GalleryInfoSceneHost } from './GalleryInfoScene';
import { PreviewHelperPort, PreviewsSceneHost } from './GalleryPreviewsScene';

const DOMAIN: number = 0x0000;

/** 统一 warn-once + 调用计数基类 */
abstract class NullHostBase {
  readonly callCount: Map<string, number> = new Map<string, number>();
  private static warned: Map<string, boolean> = new Map<string, boolean>();

  protected bump(name: string): void {
    const n: number | undefined = this.callCount.get(name);
    this.callCount.set(name, n === undefined ? 1 : n + 1);
  }

  protected warnOnce(tag: string, method: string, consequence: string): void {
    const key: string = tag + '#' + method;
    if (NullHostBase.warned.get(key) === true) {
      return;
    }
    NullHostBase.warned.set(key, true);
    hilog.warn(DOMAIN, tag, '%{public}s 未接线；后果：%{public}s。此告警只打印一次', method, consequence);
  }

  getCallCount(name: string): number {
    const n: number | undefined = this.callCount.get(name);
    return n === undefined ? 0 : n;
  }
}

export class NullHistorySceneHost extends NullHostBase implements HistorySceneHost {
  async loadHistory(): Promise<HistoryInfo[]> {
    this.bump('loadHistory');
    this.warnOnce('NullHistorySceneHost', 'loadHistory', '历史页显示空列表');
    return [];
  }
  async clearHistory(): Promise<void> { this.bump('clearHistory'); this.warnOnce('NullHistorySceneHost', 'clearHistory', '清空历史无效'); }
  async deleteHistory(info: HistoryInfo): Promise<void> { this.bump('deleteHistory'); this.warnOnce('NullHistorySceneHost', 'deleteHistory', '删除单条历史无效'); }
  startScene(announcer: Announcer): void { this.bump('startScene'); this.warnOnce('NullHistorySceneHost', 'startScene', '点击历史项不跳转'); }
  showTip(messageKey: string, isLong: boolean): void { this.bump('showTip'); this.warnOnce('NullHistorySceneHost', 'showTip', '用户看不到提示'); }
  onBackPressed(): void { this.bump('onBackPressed'); }
  startDownload(info: GalleryInfo): void { this.bump('startDownload'); this.warnOnce('NullHistorySceneHost', 'startDownload', '从历史页下载无效'); }
  addToFavorites(info: GalleryInfo, onSuccess: () => void, onFailure: (e: Error) => void): void {
    this.bump('addToFavorites');
    this.warnOnce('NullHistorySceneHost', 'addToFavorites', '从历史页收藏无效');
  }
  thumbCacheKey(gid: number): string { this.bump('thumbCacheKey'); return 'g' + gid.toString(); }
}

export class NullLabelsSceneHost extends NullHostBase implements LabelsSceneHost {
  getLabelList(): DownloadLabel[] {
    this.bump('getLabelList');
    this.warnOnce('NullLabelsSceneHost', 'getLabelList', '标签列表为空');
    return [];
  }
  containLabel(text: string): boolean { this.bump('containLabel'); return false; }
  async addLabel(text: string): Promise<void> { this.bump('addLabel'); this.warnOnce('NullLabelsSceneHost', 'addLabel', '新增标签不生效'); }
  async renameLabel(from: string, to: string): Promise<void> { this.bump('renameLabel'); this.warnOnce('NullLabelsSceneHost', 'renameLabel', '改名不生效'); }
  async deleteLabel(label: string): Promise<void> { this.bump('deleteLabel'); this.warnOnce('NullLabelsSceneHost', 'deleteLabel', '删除标签不生效'); }
  async moveLabel(from: number, to: number): Promise<void> { this.bump('moveLabel'); this.warnOnce('NullLabelsSceneHost', 'moveLabel', '拖动排序不生效'); }
  getDefaultLabelName(): string { this.bump('getDefaultLabelName'); return ''; }
  formatDeleteLabelMessage(label: string): string { this.bump('formatDeleteLabelMessage'); return label; }
  onBackPressed(): void { this.bump('onBackPressed'); }
}

export class NullTopListSceneHost extends NullHostBase implements TopListSceneHost {
  getStackIndex(): number { this.bump('getStackIndex'); return 0; }
  now(): number { this.bump('now'); return Date.now(); }
  showTip(key: string): void { this.bump('showTip'); this.warnOnce('NullTopListSceneHost', 'showTip', '用户看不到提示'); }
  finish(): void { this.bump('finish'); }
  isThisScene(sceneTag: string): boolean { this.bump('isThisScene'); return false; }
  startDetail(gid: number, pToken: string): void { this.bump('startDetail'); this.warnOnce('NullTopListSceneHost', 'startDetail', '点榜单项不跳详情'); }
  startList(builder: ListUrlBuilderSpec): void { this.bump('startList'); this.warnOnce('NullTopListSceneHost', 'startList', '榜单内跳转无效'); }
  resolveAnnouncerFromUrl(href: string): boolean { this.bump('resolveAnnouncerFromUrl'); return false; }
}

export class NullTopListApi extends NullHostBase implements TopListApi {
  async fetchDetail(url: string): Promise<EhTopListDetail | null> {
    this.bump('fetchDetail');
    this.warnOnce('NullTopListApi', 'fetchDetail', '榜单详情为空');
    return null;
  }
  cancel(): void { this.bump('cancel'); }
}

export class NullSubscriptionsSceneHost extends NullHostBase implements SubscriptionsSceneHost {
  getUserTagList(): UserTagList | null {
    this.bump('getUserTagList');
    this.warnOnce('NullSubscriptionsSceneHost', 'getUserTagList', '订阅列表为空');
    return null;
  }
  saveUserTagList(result: UserTagList | null): void { this.bump('saveUserTagList'); this.warnOnce('NullSubscriptionsSceneHost', 'saveUserTagList', '订阅修改不保存'); }
  setProgressVisible(visible: boolean): void { this.bump('setProgressVisible'); }
  setRecyclerViewVisible(visible: boolean): void { this.bump('setRecyclerViewVisible'); }
  showTipRaw(text: string): void { this.bump('showTipRaw'); this.warnOnce('NullSubscriptionsSceneHost', 'showTipRaw', '用户看不到提示'); }
  getShowTagTranslations(): boolean { this.bump('getShowTagTranslations'); return false; }
  getEhTagDatabase(): Object | null { this.bump('getEhTagDatabase'); return null; }
  onBackPressed(): void { this.bump('onBackPressed'); }
}

export class NullSubscriptionsApi extends NullHostBase implements SubscriptionsApi {
  async deleteWatched(url: string, tag: UserTag): Promise<UserTagList | null> {
    this.bump('deleteWatched');
    this.warnOnce('NullSubscriptionsApi', 'deleteWatched', '取消关注无效');
    return null;
  }
}

export class NullGalleryInfoSceneHost extends NullHostBase implements GalleryInfoSceneHost {
  copyToClipboard(text: string): void { this.bump('copyToClipboard'); this.warnOnce('NullGalleryInfoSceneHost', 'copyToClipboard', '复制无效'); }
  rememberClipboardHash(hash: number): void { this.bump('rememberClipboardHash'); }
  openUrlExternally(url: string): void { this.bump('openUrlExternally'); this.warnOnce('NullGalleryInfoSceneHost', 'openUrlExternally', '外部链接打不开'); }
  showTip(key: string): void { this.bump('showTip'); this.warnOnce('NullGalleryInfoSceneHost', 'showTip', '用户看不到提示'); }
  onBackPressed(): void { this.bump('onBackPressed'); }
  resolveString(key: string): string { this.bump('resolveString'); return key; }
}

export class NullPreviewHelperPort extends NullHostBase implements PreviewHelperPort {
  firstRefresh(): void { this.bump('firstRefresh'); this.warnOnce('NullPreviewHelperPort', 'firstRefresh', '预览页不加载'); }
  size(): number { this.bump('size'); return 0; }
  getDataAtEx(location: number): GalleryPreview | undefined { this.bump('getDataAtEx'); return undefined; }
  getPages(): number { this.bump('getPages'); return 0; }
  canGoTo(): boolean { this.bump('canGoTo'); return false; }
  getPageForTop(): number { this.bump('getPageForTop'); return 0; }
  goTo(page: number): void { this.bump('goTo'); }
  isCurrentTask(taskId: number): boolean { this.bump('isCurrentTask'); return false; }
  onGetPageData(taskId: number, pages: number, nextPage: number, newData: GalleryPreview[]): void { this.bump('onGetPageData'); }
  onGetException(taskId: number, e: Error): void { this.bump('onGetException'); this.warnOnce('NullPreviewHelperPort', 'onGetException', '预览加载错误被吞'); }
}

export class NullPreviewsSceneHost extends NullHostBase implements PreviewsSceneHost {
  openReader(galleryInfo: GalleryInfo, page: number): void {
    this.bump('openReader');
    this.warnOnce('NullPreviewsSceneHost', 'openReader', '点预览不进入阅读');
  }
  showTip(messageKey: string, isLong: boolean): void { this.bump('showTip'); this.warnOnce('NullPreviewsSceneHost', 'showTip', '用户看不到提示'); }
  onBackPressed(): void { this.bump('onBackPressed'); }
  recordException(e: Error): void { this.bump('recordException'); this.warnOnce('NullPreviewsSceneHost', 'recordException', '异常只被记录不展示'); }
}
