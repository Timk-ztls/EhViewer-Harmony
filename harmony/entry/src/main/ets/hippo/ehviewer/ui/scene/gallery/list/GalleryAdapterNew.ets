/*
 * 上游：app/src/main/java/com/hippo/ehviewer/ui/scene/gallery/list/GalleryAdapterNew.java（449 行）
 * 目标：harmony/entry/src/main/ets/hippo/ehviewer/ui/scene/gallery/list/GalleryAdapterNew.ets（inventory S0241）
 *
 * 抽基类后本文件只保留 FixedThumbNew 变体的差异（Lead 批准，去重约 60%）。
 * 差异点（相对 GalleryAdapter）：
 *   1. 缩略图控件 FixedThumbNew（item_gallery_list_new.ets 的 thumb_new 槽位）
 *   2. 新增构造参数 showReadProgress：Grid 模式显示阅读进度（"12/34"）
 *   3. 新增 OnThumbItemClickListener（缩略图长按/点击回调）
 * 基类不出现上述任何字段名（抽象泄漏判据）。
 */
import { GalleryInfo } from '../../../../client/data/GalleryInfo';
import { GalleryAdapterBase, GalleryBindData } from '../../../../../ui/GalleryAdapterBase';

export interface OnThumbItemClickListener {
  onThumbItemClick(info: GalleryInfo): void;
  onThumbItemLongClick(info: GalleryInfo): boolean;
}

export abstract class GalleryAdapterNew extends GalleryAdapterBase {
  private showReadProgress: boolean = false;
  /** 阅读进度来源：SpiderInfo 的 startPage（GalleryInfo 上没有该字段，故用注入而非硬读） */
  private readProgressProvider: (gid: number) => number = (gid: number): number => 0;

  setReadProgressProvider(provider: (gid: number) => number): void {
    this.readProgressProvider = provider;
  }
  private thumbClickListener: OnThumbItemClickListener | null = null;

  setShowReadProgress(show: boolean): void {
    this.showReadProgress = show;
  }

  setOnThumbItemClickListener(listener: OnThumbItemClickListener | null): void {
    this.thumbClickListener = listener;
  }

  getThumbItemClickListener(): OnThumbItemClickListener | null {
    return this.thumbClickListener;
  }

  /** FixedThumbNew：加载中占位 + 阅读进度文本 */
  bindThumb(d: GalleryBindData, info: GalleryInfo): void {
    d.thumbKey = this.getThumbKey(info.gid);
    d.thumbUrl = info.thumb;
  }

  /**
   * 上游 New 变体在 Grid 模式显示阅读进度，写进 d.pages（上游就是复用 pages 那个 TextView），
   * 不另开 extraText（那个字段全仓 0 消费者，且值恒为 '1/20' 是错的）。
   * 格式：startPage+1 + "/" + pages + "P"；未读过显示 0/…P；受 showReadProgress 门控。
   */
  bindExtra(d: GalleryBindData, info: GalleryInfo): void {
    if (!this.showReadProgress || info.pages <= 0) {
      return;
    }
    const startPage: number = this.readProgressProvider(info.gid);
    d.pages = startPage.toString() + '/' + info.pages.toString() + 'P';
    d.pagesVisible = true;
  }
}