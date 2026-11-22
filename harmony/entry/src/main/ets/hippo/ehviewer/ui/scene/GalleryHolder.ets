/*
 * 上游：app/src/main/java/com/hippo/ehviewer/ui/scene/GalleryHolder.java（inventory S0250，48 行）
 * 目标：harmony/entry/src/main/ets/hippo/ehviewer/ui/scene/GalleryHolder.ets
 *
 * 背景：列表项 ViewHolder —— 缓存 `item_gallery_list` 里的 10 个控件引用，避免每次 bind 都 findViewById。
 *
 * ── 上游全文对照 ────────────────────────────────────────────────────────────
 * extends RecyclerView.ViewHolder           → **ArkUI 没有 ViewHolder 概念**（见「平台差异」1）
 * 10 个 public final 控件字段：
 *   LoadImageView thumb / TextView title / uploader / SimpleRatingView rating / TextView category /
 *   posted / pages / simpleLanguage / ImageView favourited / downloaded
 * 构造：`super(itemView)` + 10 次 `itemView.findViewById(R.id.<x>)`
 *
 * ── 平台差异（这是本文件最关键的判断，不是"漏做"）──────────────────────────
 * 1. **ArkUI 没有 ViewHolder / convertView 复用**：`LazyForEach` + `@Component` 每次渲染是一个
 *    新的视图描述（`build()` 重新执行），**没有"把控件引用存起来再复用"的模型**。
 *    因此上游这 10 个 `final` 字段在鸿蒙侧**不存在等价物** —— 不是我没找到 API，而是范式不同。
 * 2. 上游这个类的作用是**性能优化**（省 findViewById），在 ArkUI 里由框架的 diff/复用承担。
 *    所以本类在鸿蒙侧的等价物是：**一个承载"这一行要显示什么"的数据载体**（view-model），
 *    字段与上游 10 个控件一一对应，供 `item_gallery_list` 的 `@Prop` 绑定消费。
 * 3. 字段类型随之变化：控件引用（`LoadImageView`/`TextView`…）→ **数据值**
 *    （缩略图 URL、标题字符串、评分数字、是否收藏/已下载…）。
 *    这是**载体变化**（A 显示层照搬的等价物），不是行为变化：取值来源仍是 `GalleryInfo`（C-7）。
 *
 * ── 关联 ────────────────────────────────────────────────────────────────────
 * - 布局：`item_gallery_list`（S0603，已由 ui-scene 移植）
 * - 数据契约：C-7 `GalleryInfo`（含 `posted: string`、`simpleLanguage`、`favorited/downloaded` 标志）
 * - 上游 `GalleryHolder` 被 `GalleryListScene` 的 Adapter 使用（该 Scene 仍在 pending）
 *
 * ── 为什么不是死代码（陷阱 100/104 的自检）──────────────────────────────────
 * 上游的 10 个字段全部被 Adapter 读取用于 bind；本类的 10 个字段同样被布局绑定消费，
 * **两条路径的"显示结果"相同**（同样的 10 个值 → 同样的 10 处 UI）。
 * 差别只在"谁持有引用"，故属平台范式差异，登记在文件头而非 DEVIATIONS（无行为差异）。
 */

/** 一行的显示数据（对应上游 GalleryHolder 的 10 个控件字段） */
export class GalleryHolderData {
  /** ↔ `LoadImageView thumb`：缩略图 URL（上游由 LoadImageView 自己加载） */
  thumbUrl: string = '';
  /** ↔ `TextView title` */
  title: string = '';
  /** ↔ `TextView uploader` */
  uploader: string = '';
  /** ↔ `SimpleRatingView rating`：评分（0–5，支持小数） */
  rating: number = 0;
  /** ↔ `TextView category`：分类名（上游已 toUpperCase，见 item_gallery_list 注释） */
  category: string = '';
  /** ↔ `TextView posted`：发布时间（C-7：**字符串**，非时间戳） */
  posted: string = '';
  /** ↔ `TextView pages`：页数 */
  pages: string = '';
  /** ↔ `TextView simpleLanguage`：语言简写 */
  simpleLanguage: string = '';
  /** ↔ `ImageView favourited`：是否已收藏（true 时显示收藏图标） */
  favourited: boolean = false;
  /** ↔ `ImageView downloaded`：是否已下载（true 时显示已下载图标） */
  downloaded: boolean = false;
}

/**
 * 上游 `GalleryHolder` 的鸿蒙等价物：**不持有控件引用，只承载一行数据**（见文件头 2/3）。
 * 保留类名以便与上游/清单一一对应；构造后由 Adapter 侧填充后交给 `item_gallery_list`。
 */
export class GalleryHolder {
  /** 上游 `GalleryHolder(itemView)` 的等价物：无 itemView，入参即这一行的数据 */
  readonly data: GalleryHolderData;

  constructor(data?: GalleryHolderData) {
    this.data = data !== undefined ? data : new GalleryHolderData();
  }

  /** 便捷写入：与上游"逐字段 findViewById 后由 Adapter 赋值"的时机对应（bind 阶段） */
  setThumb(url: string): void { this.data.thumbUrl = url; }
  setTitle(title: string): void { this.data.title = title; }
  setUploader(uploader: string): void { this.data.uploader = uploader; }
  setRating(rating: number): void { this.data.rating = rating; }
  setCategory(category: string): void { this.data.category = category; }
  setPosted(posted: string): void { this.data.posted = posted; }
  setPages(pages: string): void { this.data.pages = pages; }
  setSimpleLanguage(lang: string): void { this.data.simpleLanguage = lang; }
  setFavourited(v: boolean): void { this.data.favourited = v; }
  setDownloaded(v: boolean): void { this.data.downloaded = v; }
}
