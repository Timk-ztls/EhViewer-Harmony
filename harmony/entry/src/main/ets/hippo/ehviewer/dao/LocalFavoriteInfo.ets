/*
 * 对位上游：app/src/main/java/com/hippo/ehviewer/dao/LocalFavoriteInfo.java（GreenDAO 生成实体）
 *
 * 表：LOCAL_FAVORITES —— 列映射逐字保留（列名/类型/约束见 LocalFavoritesDao.ets 的 CREATE_TABLE_SQL）。
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
export class LocalFavoriteInfo extends GalleryInfo {
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

  getTime(): number {
    return this.time;
  }

  setTime(value: number): void {
    this.time = value;
  }

  // ---------------------------------------------------------------- 静态工厂

  /**
   * 对位上游 `LocalFavoriteInfo(GalleryInfo)` 构造器（LocalFavoriteInfo.java，逐行核过）。
   *
   * ArkTS 无重载：`constructor(gid?: number)` 已存在，故落成静态工厂，语义等价。
   *
   * **只拷贝上游那 11 个字段**，有 DDL 硬证据：
   *   `LocalFavoritesDao.CREATE_TABLE_SQL` 列全集 =
   *   GID / TOKEN / TITLE / TITLE_JPN / THUMB / CATEGORY / POSTED / UPLOADER / RATING /
   *   SIMPLE_LANGUAGE / TIME
   * 与 HISTORY 相比**少了 `MODE`**（`DownloadInfo` 才有 state/mode 那类列）：
   *   → 所以这里**不能**照 `HistoryInfo.fromGalleryInfo` 抄 mode（那边有列，这边没列）。
   *   → `GalleryInfo` 的 `pages` / `thumbWidth` / `spanSize` / `favoriteSlot` / `tgList` /
   *     `postedAt` 等同样没有对应列，拷了会在落库时静默丢弃，故不拷（见 HistoryInfo 同名说明）。
   *   → `time` 是 LOCAL_FAVORITES 专有列，上游构造器不碰（由调用方 `setTime`）。
   *
   * `simpleTags` 与上游一样是**共享引用**（不 clone）；调用方要改请自行 clone。
   */
  static fromGalleryInfo(galleryInfo: GalleryInfo): LocalFavoriteInfo {
    const info: LocalFavoriteInfo = new LocalFavoriteInfo();
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