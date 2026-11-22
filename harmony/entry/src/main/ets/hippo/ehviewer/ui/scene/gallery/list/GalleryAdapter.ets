/*
 * 上游：app/src/main/java/com/hippo/ehviewer/ui/scene/gallery/list/GalleryAdapter.java（245 行）
 * 目标：harmony/entry/src/main/ets/hippo/ehviewer/ui/scene/gallery/list/GalleryAdapter.ets（inventory S0240）
 *
 * 抽基类后本文件只保留 FixedThumb 变体的差异（Lead 2026-10-24 批准去重，见 GalleryAdapterBase.ets 头注释）。
 * 差异点：缩略图控件为 FixedThumb（item_gallery_list.ets 的 thumb 槽位）。
 */
import { GalleryInfo } from '../../../../client/data/GalleryInfo';
import { GalleryAdapterBase } from '../../../../../ui/GalleryAdapterBase';

export abstract class GalleryAdapter extends GalleryAdapterBase {
  /** FixedThumb：不做加载中占位（上游 GalleryHolder.thumb 为 FixedThumb，retryType=click） */
  bindThumb(d: import('../../../../../ui/GalleryAdapterBase').GalleryBindData, info: GalleryInfo): void {
    d.thumbKey = this.getThumbKey(info.gid);
    d.thumbUrl = info.thumb;
  }
}