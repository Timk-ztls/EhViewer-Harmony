/*
 * 上游：app/src/main/java/com/hippo/ehviewer/ui/scene/gallery/list/GalleryAdapter.java（245 行）
 *       app/src/main/java/com/hippo/ehviewer/ui/scene/gallery/list/GalleryAdapterNew.java（449 行）
 * 目标：harmony/entry/src/main/ets/hippo/ui/GalleryAdapterBase.ets（扩展文件，登记 inventory/ui-scene.extra.txt）
 *
 * 为什么抽基类（Lead 2026-10-24 批准）：两个上游 Adapter 同构度约 60%
 * （type/decoration/padding/getItemViewType/EhUtils 六件套完全一致），
 * 差异只在「缩略图控件」与「阅读进度文本」。复制 449 行必然漂移，故逻辑去重、文件结构保留：
 *   GalleryAdapter.ets    extends GalleryAdapterBase（FixedThumb）
 *   GalleryAdapterNew.ets extends GalleryAdapterBase（FixedThumbNew + 阅读进度）
 *
 * 抽象泄漏约束（Lead 判据）：基类**不出现** FixedThumb/FixedThumbNew/showReadProgress 字样。
 * 子类差异只能通过下列抽象方法表达：
 *   bindThumb(d, gi)   缩略图相关字段（New 变体在此处理阅读进度/占位）
 *   bindExtra(d, gi)   其它模式特有字段（基类默认空实现）
 */
import { GalleryInfo } from '../ehviewer/client/data/GalleryInfo';

export class GalleryAdapterType {
  static readonly INVALID: number = -1;
  static readonly LIST: number = 0;
  static readonly GRID: number = 1;
}

/** 一次绑定的结果（对位上游 onBindViewHolder 的逐字段赋值 + setVisibility） */
export class GalleryBindData {
  thumbKey: string = '';
  thumbUrl: string = '';
  title: string = '';
  uploader: string = '';
  rating: number = 0;
  category: string = '';
  categoryColor: string = '#FF000000';
  posted: string = '';
  pages: string = '';
  pagesVisible: boolean = false;
  simpleLanguage: string = '';
  languageVisible: boolean = false;
  favouritedVisible: boolean = false;
  downloadedVisible: boolean = false;
  thumbWidth: number = 0;
  thumbHeight: number = 0;
  transitionName: string = '';
  /** 子类扩展位（如 New 变体的阅读进度文本） */
  extraText: string = '';
  extraVisible: boolean = false;
}

export abstract class GalleryAdapterBase {
  protected type: number = GalleryAdapterType.INVALID;
  private showFavourited: boolean = false;

  setShowFavourited(show: boolean): void {
    this.showFavourited = show;
  }

  getType(): number {
    return this.type;
  }

  /** 上游 setType(type)：只切形态；列宽/间距交给 ArkUI Grid 参数 */
  setType(type: number): void {
    this.type = type;
  }

  getItemViewType(position: number): number {
    return this.type;
  }

  // ---------------- 子类必须提供的数据/工具 ----------------
  abstract getDataAt(position: number): GalleryInfo | null;
  abstract getThumbKey(gid: number): string;
  abstract getSuitableTitle(info: GalleryInfo): string;
  abstract getCategoryText(category: number): string;
  abstract getCategoryColor(category: number): string;
  abstract isDownloaded(gid: number): boolean;
  abstract isFavourited(info: GalleryInfo): boolean;

  // ---------------- 子类差异点（基类不感知具体控件） ----------------
  /** 缩略图相关字段：New 变体在此处理"加载中占位/重试类型/阅读进度" */
  bindThumb(d: GalleryBindData, info: GalleryInfo): void {
    d.thumbKey = this.getThumbKey(info.gid);
    d.thumbUrl = info.thumb;
  }

  /** 其它模式特有字段（默认无） */
  bindExtra(d: GalleryBindData, info: GalleryInfo): void {
  }

  /** 上游 onBindViewHolder：公共字段 + 两处差异点 */
  bind(position: number): GalleryBindData | null {
    const gi: GalleryInfo | null = this.getDataAt(position);
    if (gi === null) {
      return null;
    }
    const d: GalleryBindData = new GalleryBindData();
    // C-13：simpleLanguage 是 string | null（上游 @Nullable String），判空后再用，禁用非空断言
    const sLang: string = gi.simpleLanguage ?? '';
    d.uploader = gi.uploader;
    d.rating = gi.rating;
    d.posted = gi.posted;
    d.transitionName = 'thumb_' + gi.gid;
    d.simpleLanguage = sLang;
    d.languageVisible = sLang.length > 0;

    this.bindThumb(d, gi);

    if (this.type === GalleryAdapterType.GRID) {
      // 上游 TYPE_GRID：TileThumb 尺寸 + 三角色块
      d.thumbWidth = gi.thumbWidth;
      d.thumbHeight = gi.thumbHeight;
      d.categoryColor = this.getCategoryColor(gi.category);
      this.bindExtra(d, gi);
      return d;
    }

    // 上游 TYPE_LIST
    d.title = this.getSuitableTitle(gi);
    d.category = this.getCategoryText(gi.category);
    d.categoryColor = this.getCategoryColor(gi.category);
    d.pagesVisible = gi.pages !== 0;
    d.pages = gi.pages > 0 ? (gi.pages.toString() + 'P') : '';
    d.favouritedVisible = this.showFavourited && gi.favoriteSlot >= -1 && gi.favoriteSlot <= 10;
    d.downloadedVisible = this.isDownloaded(gi.gid);
    this.bindExtra(d, gi);
    return d;
  }
}
