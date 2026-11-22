/*
 * 对位上游：app/src/main/java/com/hippo/ehviewer/dao/DownloadInfo.java（GreenDAO 生成实体）
 *
 * 表：DOWNLOADS —— 列映射逐字保留（列名/类型/约束见 DownloadsDao.ets 的 CREATE_TABLE_SQL）。
 *
 * 平台对位：
 *   - 上游 `extends com.hippo.ehviewer.client.data.GalleryInfo`（net-parse，C-7 契约）；
 *     ArkTS 侧 GalleryInfo 是 `@Observed class`，子类**必须同样 @Observed**，
 *     否则编译能过但 ArkUI 观察链断裂（列表项数据变了 UI 不刷新，P5 才暴露）。
 *   - GreenDAO 生成的 getter/setter 与继承来的 public 字段并存：字段供直接读写（上游到处这么用），
 *     getter/setter 供 DAO 的 toBucket/fromResultSet 与下游调用点（getGid() 等 19 处上游调用）。
 *   - Parcelable 去除（D-013）；JSON 保留（toJson/fromJson 见文件尾部）。
 */

import { GalleryInfo, JsonMap } from '../client/data/GalleryInfo';

@Observed
export class DownloadInfo extends GalleryInfo {
  state: number = 0;
  legacy: number = 0;
  time: number = 0;
  label: string | null = null;
  archiveUri: string | null = null;

  constructor(gid?: number) {
    super();
    if (gid !== undefined) {
      this.gid = gid;
    }
  }

  getGid(): number {
    return this.gid;
  }

  setGid(value: number): void {
    this.gid = value;
  }

  getToken(): string {
    return this.token;
  }

  setToken(value: string): void {
    this.token = value;
  }

  getTitle(): string {
    return this.title;
  }

  setTitle(value: string): void {
    this.title = value;
  }

  getTitleJpn(): string {
    return this.titleJpn;
  }

  setTitleJpn(value: string): void {
    this.titleJpn = value;
  }

  getThumb(): string {
    return this.thumb;
  }

  setThumb(value: string): void {
    this.thumb = value;
  }

  getCategory(): number {
    return this.category;
  }

  setCategory(value: number): void {
    this.category = value;
  }

  getPosted(): string {
    return this.posted;
  }

  setPosted(value: string): void {
    this.posted = value;
  }

  getUploader(): string {
    return this.uploader;
  }

  setUploader(value: string): void {
    this.uploader = value;
  }

  getRating(): number {
    return this.rating;
  }

  setRating(value: number): void {
    this.rating = value;
  }

  getSimpleLanguage(): string | null {
    return this.simpleLanguage;
  }

  setSimpleLanguage(value: string | null): void {
    this.simpleLanguage = value;
  }

  getState(): number {
    return this.state;
  }

  setState(value: number): void {
    this.state = value;
  }

  getLegacy(): number {
    return this.legacy;
  }

  setLegacy(value: number): void {
    this.legacy = value;
  }

  getTime(): number {
    return this.time;
  }

  setTime(value: number): void {
    this.time = value;
  }

  getLabel(): string | null {
    return this.label;
  }

  setLabel(value: string | null): void {
    this.label = value;
  }

  getArchiveUri(): string | null {
    return this.archiveUri;
  }

  setArchiveUri(value: string | null): void {
    this.archiveUri = value;
  }
  // ================= 对位上游 DownloadInfo 的非常量/非列成员 =================

  /** 下载状态常量（值与上游逐字一致）。 */
  static readonly STATE_INVALID: number = -1;
  static readonly STATE_NONE: number = 0;
  static readonly STATE_WAIT: number = 1;
  static readonly STATE_DOWNLOAD: number = 2;
  static readonly STATE_FINISH: number = 3;
  static readonly STATE_FAILED: number = 4;
  static readonly STATE_UPDATE: number = 5;
  static readonly GOTO_NEW: number = 6;

  /*
   * 运行期字段（不入库，上游同样没有对应列）：下载进度/速度/剩余。
   * 上游靠 GreenDAO 只映射列字段、其余字段自然不参与 SQL —— ArkTS 侧同理：
   * 下面 6 个字段不出现在 DownloadsDao.toBucket/fromResultSet 里，check-columns 断言会验证这一点。
   */
  speed: number = 0;
  remaining: number = 0;
  finished: number = 0;
  downloaded: number = 0;
  total: number = 0;
  /** 文件夹总大小（字节），-1 表示未计算（上游注释）。 */
  fileSize: number = -1;

  /** 对位上游 `updateInfo(GalleryInfo)`：把图库元信息刷进下载条目。 */
  updateInfo(galleryInfo: GalleryInfo): void {
    this.token = galleryInfo.token;
    this.title = galleryInfo.title;
    this.titleJpn = galleryInfo.titleJpn;
    this.thumb = galleryInfo.thumb;
    this.category = galleryInfo.category;
    this.posted = galleryInfo.posted;
    this.uploader = galleryInfo.uploader;
    this.rating = galleryInfo.rating;
    this.simpleTags = galleryInfo.simpleTags;
    this.simpleLanguage = galleryInfo.simpleLanguage;
  }

  /**
   * 对位上游 `toJson()`（fastjson：super.toJson() 再 put 10 个额外键）。
   * 合并基类 GalleryInfo.toJson() 与 DownloadInfo 自有 10 个字段（避免经 JsonMap 二次往返破坏 tgList 等嵌套结构）。
   */
  toJson(): string {
    const baseJson: string = super.toJson().trim();
    const extraParts: string[] = [
      `"finished":${this.finished}`,
      `"legacy":${this.legacy}`,
      `"label":${this.label !== null ? JSON.stringify(this.label) : 'null'}`,
      `"downloaded":${this.downloaded}`,
      `"remaining":${this.remaining}`,
      `"speed":${this.speed}`,
      `"state":${this.state}`,
      `"time":${this.time}`,
      `"total":${this.total}`,
      `"archiveUri":${this.archiveUri !== null ? JSON.stringify(this.archiveUri) : 'null'}`
    ];
    if (baseJson === '{}' || baseJson.length === 0) {
      return `{${extraParts.join(',')}}`;
    }
    if (!baseJson.endsWith('}')) {
      return baseJson;
    }
    return `${baseJson.substring(0, baseJson.length - 1)},${extraParts.join(',')}}`;
  }

  /** 对位上游静态 `downloadInfoFromJson(JSONObject)`：先用 GalleryInfo.fromJson 填基类，再补下载字段。 */
  static downloadInfoFromJson(s: string): DownloadInfo {
    const base: GalleryInfo = GalleryInfo.fromJson(s);
    const info: DownloadInfo = new DownloadInfo(base.gid);
    info.token = base.token;
    info.title = base.title;
    info.titleJpn = base.titleJpn;
    info.thumb = base.thumb;
    info.category = base.category;
    info.posted = base.posted;
    info.uploader = base.uploader;
    info.rating = base.rating;
    info.rated = base.rated;
    info.simpleLanguage = base.simpleLanguage;
    info.simpleTags = base.simpleTags;
    info.pages = base.pages;
    info.thumbWidth = base.thumbWidth;
    info.thumbHeight = base.thumbHeight;
    info.spanSize = base.spanSize;
    info.spanIndex = base.spanIndex;
    info.spanGroupIndex = base.spanGroupIndex;
    info.favoriteSlot = base.favoriteSlot;
    info.favoriteName = base.favoriteName;
    info.tgList = base.tgList;
    info.postedAt = base.postedAt;
    const map: JsonMap = JsonMap.parse(s);
    info.finished = map.getNum('finished', 0);
    info.legacy = map.getNum('legacy', 0);
    info.label = map.getStrOrNull('label');
    info.downloaded = map.getNum('downloaded', 0);
    info.remaining = map.getNum('remaining', 0);
    info.speed = map.getNum('speed', 0);
    info.state = map.getNum('state', 0);
    info.time = map.getNum('time', 0);
    info.total = map.getNum('total', 0);
    info.archiveUri = map.getStrOrNull('archiveUri');
    return info;
  }
}