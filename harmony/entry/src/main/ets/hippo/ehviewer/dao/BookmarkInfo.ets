/*
 * 对位上游：app/src/main/java/com/hippo/ehviewer/dao/BookmarkInfo.java（GreenDAO 生成实体）
 *
 * 表：BOOKMARKS —— 列映射逐字保留（列名/类型/约束见 BookmarksBao.ets 的 CREATE_TABLE_SQL）。
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
export class BookmarkInfo extends GalleryInfo {
  page: number = 0;
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

  getPage(): number {
    return this.page;
  }

  setPage(value: number): void {
    this.page = value;
  }

  getTime(): number {
    return this.time;
  }

  setTime(value: number): void {
    this.time = value;
  }
}
