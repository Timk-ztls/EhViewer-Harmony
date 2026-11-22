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

import { GalleryInfo } from './GalleryInfo';
import { GalleryTagGroup } from './GalleryTagGroup';
import { GalleryCommentList } from './GalleryCommentList';
import { PreviewSet } from './PreviewSet';
import { NewVersion } from './NewVersion';

/**
 * 1:1 对位 upstream: app/src/main/java/com/hippo/ehviewer/client/data/GalleryDetail.java
 * （inventory S0049，149 行 / 实测 166 行含注释）
 *
 * 详情页最大模型：在 GalleryInfo 之上加种子/归档/父画廊/评分/标签组/评论/预览集。
 * 上游继承 GalleryInfo（Parcelable），写 Parcel 时先 super.writeToParcel 再写自己的字段；
 * ArkTS 无 Parcel，序列化出口是 JSON（`toJson` 覆写父类）。
 *
 * 字段为 public 且全部可空（除 apiUid 默认 -1），NULL 可能来自解析失败，
 * 读方一律按 null 检查（与上游一致，不做默认值兜底）。
 *
 * @Observed：详情页直接绑定本对象；父类 GalleryInfo 已是 @Observed，子类沿用同一观察链。
 */
@Observed
export class GalleryDetail extends GalleryInfo {
  /** 上游 `public long apiUid = -1L`：未登录/未解析时为 -1。 */
  apiUid: number = -1;
  apiKey: string | null = null;
  torrentCount: number = 0;
  torrentUrl: string | null = null;
  archiveUrl: string | null = null;
  parent: string | null = null;
  visible: string | null = null;
  language: string | null = null;
  size: string | null = null;
  /** SpiderQueen 记录的页数（与父类 pages 区分：那是详情页显示的页数）。 */
  SpiderInfoPages: number = 0;

  favoriteCount: number = 0;
  isFavorited: boolean = false;
  ratingCount: number = 0;
  tags: GalleryTagGroup[] | null = null;
  comments: GalleryCommentList | null = null;
  previewPages: number = 0;
  SpiderInfoPreviewPages: number = 0;
  previewSet: PreviewSet | null = null;
  SpiderInfoPreviewSet: PreviewSet | null = null;

  newVersions: NewVersion[] | null = null;

  constructor() {
    super();
  }

  /**
   * 覆写 GalleryInfo.toJson()：保留父类全部键，再追加详情字段。
   * 上游 GalleryDetail **没有**覆写 toJson（只有 GalleryInfo 有），这里覆写是为了
   * 让详情缓存（SimpleDiskCache 存 JSON）能带全字段；差异已在 MR 登记。
   * 若要求逐字对齐「只有父类 toJson」，把本方法删掉即可，父类签名不变。
   */
  toJson(): string {
    const base: string = super.toJson();
    const extra: DetailJson = new DetailJson();
    extra.putNum('apiUid', this.apiUid);
    extra.putStrOrNull('apiKey', this.apiKey);
    extra.putNum('torrentCount', this.torrentCount);
    extra.putStrOrNull('torrentUrl', this.torrentUrl);
    extra.putStrOrNull('archiveUrl', this.archiveUrl);
    extra.putStrOrNull('parent', this.parent);
    extra.putStrOrNull('visible', this.visible);
    extra.putStrOrNull('language', this.language);
    extra.putStrOrNull('size', this.size);
    extra.putNum('SpiderInfoPages', this.SpiderInfoPages);
    extra.putNum('favoriteCount', this.favoriteCount);
    extra.putBool('isFavorited', this.isFavorited);
    extra.putNum('ratingCount', this.ratingCount);
    extra.putNum('previewPages', this.previewPages);
    extra.putNum('SpiderInfoPreviewPages', this.SpiderInfoPreviewPages);
    // 嵌套结构（tags/comments/previewSet/newVersions）由调用方按需序列化：
    // 上游 toJson 也不含这些（它们走 Parcel 而非 JSON），保持同一取舍。
    return extra.mergeInto(base);
  }

  /**
   * 深拷贝（替代上游 `DataUtils.copy(this)`，D-043：DataUtils 判 na）。
   *
   * 上游 `DataUtils.copy` 走 `Parcel.writeParcelable` —— 会**递归序列化所有 Parcelable
   * 子对象**，所以是深拷不是浅拷。这里逐字段照做：
   *   - 基本类型/字符串：直接赋值（字符串不可变，共享无副作用）
   *   - 数组：`slice()` 复制（`simpleTags` / `tgList` / `newVersions`）
   *   - Parcelable 子对象：调各自的 `copy()`
   *
   * 派生字段 `postedAt` 一并复制（它是 `posted` 的缓存，原值有效就不必重算）。
   */
  copy(): GalleryDetail {
    const n: GalleryDetail = new GalleryDetail();

    // ---- 父类 GalleryInfo 的字段 ----
    n.gid = this.gid;
    n.token = this.token;
    n.title = this.title;
    n.titleJpn = this.titleJpn;
    n.thumb = this.thumb;
    n.category = this.category;
    n.posted = this.posted;
    n.uploader = this.uploader;
    n.rating = this.rating;
    n.simpleLanguage = this.simpleLanguage;
    n.rated = this.rated;
    n.simpleTags = this.simpleTags === null ? null : this.simpleTags.slice();
    n.pages = this.pages;
    n.thumbWidth = this.thumbWidth;
    n.thumbHeight = this.thumbHeight;
    n.spanSize = this.spanSize;
    n.spanIndex = this.spanIndex;
    n.spanGroupIndex = this.spanGroupIndex;
    n.favoriteSlot = this.favoriteSlot;
    n.favoriteName = this.favoriteName;
    n.tgList = this.tgList === null ? null : this.tgList.slice();
    n.postedAt = this.postedAt;

    // ---- 详情特有字段 ----
    n.apiUid = this.apiUid;
    n.apiKey = this.apiKey;
    n.torrentCount = this.torrentCount;
    n.torrentUrl = this.torrentUrl;
    n.archiveUrl = this.archiveUrl;
    n.parent = this.parent;
    n.visible = this.visible;
    n.language = this.language;
    n.size = this.size;
    n.SpiderInfoPages = this.SpiderInfoPages;
    n.favoriteCount = this.favoriteCount;
    n.isFavorited = this.isFavorited;
    n.ratingCount = this.ratingCount;
    n.previewPages = this.previewPages;
    n.SpiderInfoPreviewPages = this.SpiderInfoPreviewPages;

    // ---- 引用类型：深拷 ----
    if (this.tags !== null) {
      const tags: GalleryTagGroup[] = [];
      for (let i = 0; i < this.tags.length; i++) {
        tags.push(this.tags[i].copy());
      }
      n.tags = tags;
    }
    n.comments = this.comments === null ? null : this.comments.copy();
    n.previewSet = this.previewSet === null ? null : this.previewSet.copy();
    n.SpiderInfoPreviewSet = this.SpiderInfoPreviewSet === null
      ? null : this.SpiderInfoPreviewSet.copy();
    if (this.newVersions !== null) {
      const versions: NewVersion[] = [];
      for (let i = 0; i < this.newVersions.length; i++) {
        versions.push(this.newVersions[i].copy());
      }
      n.newVersions = versions;
    }
    return n;
  }

  /**
   * 对齐上游 `getNewGalleryDetail(int index)`：返回「切换到第 index 个版本后」的详情对象。
   *
   * **`try/catch` 整段照搬**：上游任何异常（index 越界、`versionUrl` 分段不足、
   * gid 解析失败）都 `catch (Throwable) { return this; }` ——
   * **返回原对象而不是抛错**。调用方据此判断"切换失败就沿用旧对象"。
   *
   * 两个细节：
   *   - `newVersions == null` 时**返回拷贝**（不是 this）：调用方可以安全改它
   *   - `gid` 用 `Number()` 而不是 `parseInt()`：`"123abc"` 会得到 NaN（更严格），
   *     与 `Long.parseLong` 行为一致（parseInt 会宽容地返回 123）
   */
  getNewGalleryDetail(index: number): GalleryDetail {
    try {
      const n: GalleryDetail = this.copy();
      const versions = this.newVersions;
      if (versions === null) {
        return n;
      }
      const updateUrl: string = versions[index].versionUrl;
      const params: string[] = updateUrl.split('/');
      const length: number = params.length;
      n.token = params[length - 1];
      n.gid = Number(params[length - 2]);
      if (Number.isNaN(n.gid)) {
        // Long.parseLong 对非数字会抛 NumberFormatException → 上游落到 catch 返回 this
        throw new Error('NumberFormatException: For input string: "' + params[length - 2] + '"');
      }
      n.newVersions = null;
      return n;
    } catch (e) {
      return this;
    }
  }
}

/**
 * 详情字段的 JSON 附加器：把新键合并进父类已生成的 JSON 文本。
 * 为什么不复用 GalleryInfo 里的 JsonMap：那个是「键→值」构建器，父类 toJson 已输出成字符串；
 * 这里只需把字符串尾部 `}` 前插入新键值对，避免二次解析（大对象少一次全量 parse）。
 */
class DetailJson {
  private readonly _map: Map<string, string> = new Map<string, string>();

  putNum(key: string, value: number): void {
    this._map.set(key, `${value}`);
  }

  putBool(key: string, value: boolean): void {
    this._map.set(key, value ? 'true' : 'false');
  }

  putStrOrNull(key: string, value: string | null): void {
    this._map.set(key, value === null ? 'null' : JSON.stringify(value));
  }

  mergeInto(baseJson: string): string {
    if (this._map.size === 0) {
      return baseJson;
    }
    const parts: string[] = [];
    this._map.forEach((v: string, k: string) => {
      parts.push(`${JSON.stringify(k)}:${v}`);
    });
    const trimmed: string = baseJson.trim();
    if (trimmed === '{}' || trimmed.length === 0) {
      return `{${parts.join(',')}}`;
    }
    if (!trimmed.endsWith('}')) {
      return baseJson;
    }
    return trimmed.substring(0, trimmed.length - 1) + ',' + parts.join(',') + '}';
  }

}
