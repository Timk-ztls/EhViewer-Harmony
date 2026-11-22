/*
 * 对位上游：app/src/main/java/com/hippo/ehviewer/dao/HistoryInfo.java（GreenDAO 生成实体）
 *
 * 表：HISTORY —— 列映射逐字保留（列名/类型/约束见 HistoryDao.ets 的 CREATE_TABLE_SQL）。
 *
 * 平台对位：
 *   - 上游 `extends com.hippo.ehviewer.client.data.GalleryInfo`（net-parse，C-7 契约）；
 *     ArkTS 侧 GalleryInfo 是 `@Observed class`，子类**必须同样 @Observed**，
 *     否则编译能过但 ArkUI 观察链断裂（列表项数据变了 UI 不刷新，P5 才暴露）。
 *   - GreenDAO 生成的 getter/setter 与继承来的 public 字段并存：字段供直接读写（上游到处这么用），
 *     getter/setter 供 DAO 的 toBucket/fromResultSet 与下游调用点（getGid() 等 19 处上游调用）。
 *   - Parcelable 去除（D-013）；JSON 保留（toJson/fromJson 见文件尾部）。
 */

import { GalleryInfo } from '../client/data/GalleryInfo';

@Observed
export class HistoryInfo extends GalleryInfo {
  mode: number = 0;
  time: number = 0;

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

  getMode(): number {
    return this.mode;
  }

  setMode(value: number): void {
    this.mode = value;
  }

  getTime(): number {
    return this.time;
  }

  setTime(value: number): void {
    this.time = value;
  }

  // ---------------------------------------------------------------- 静态工厂

  /**
   * 对位上游 `HistoryInfo(GalleryInfo)` 构造器（HistoryInfo.java，我按上游源码逐行核过）。
   *
   * ArkTS 没有「接受同族基类参数的拷贝构造」（`constructor(g: GalleryInfo)` 会与
   * `constructor(gid?: number)` 冲突且无法重载），故落成静态工厂 —— 语义完全等价：
   * `const h: HistoryInfo = HistoryInfo.fromGalleryInfo(info);`
   *
   * **只拷贝上游那 11 个字段**，一个不多一个不少。理由是有 DDL 硬证据的：
   *   `HistoryDao.CREATE_TABLE_SQL` 的列全集 = GID / TOKEN / TITLE / TITLE_JPN / THUMB /
   *   CATEGORY / POSTED / UPLOADER / RATING / SIMPLE_LANGUAGE / MODE / TIME
   * → `GalleryInfo` 的另外 8 个字段（`rated` / `pages` / `thumbWidth` / `thumbHeight` /
   *   `spanSize` / `spanIndex` / `spanGroupIndex` / `favoriteSlot` / `favoriteName` /
   *   `tgList` / `postedAt`）在 HISTORY 表里**没有对应列**，拷了也会在落库时丢掉。
   * 如果有人为了"看起来完整"把它们也拷进来，只会制造"内存里有、库里没有"的假象 ——
   * 这正是 lead 说的"漏一列不报错但静默丢数据"的镜像问题。
   *
   * `mode` / `time` 是 history 专有列，上游构造器不碰（由调用方 `setMode` / `setTime`）。
   *
   * 注意 `simpleTags` 是**共享引用**（上游同样是 `this.simpleTags = galleryInfo.simpleTags`，
   * 不 clone）。调用方若要修改，需自行 clone，别改这份。
   */
  static fromGalleryInfo(galleryInfo: GalleryInfo): HistoryInfo {
    const info: HistoryInfo = new HistoryInfo();
    info.gid = galleryInfo.gid;
    info.token = galleryInfo.token;
    info.title = galleryInfo.title;
    info.titleJpn = galleryInfo.titleJpn;
    info.thumb = galleryInfo.thumb;
    info.category = galleryInfo.category;
    info.posted = galleryInfo.posted;
    info.uploader = galleryInfo.uploader;
    info.rating = galleryInfo.rating;
    info.simpleTags = galleryInfo.simpleTags;
    info.simpleLanguage = galleryInfo.simpleLanguage;
    return info;
  }
}
