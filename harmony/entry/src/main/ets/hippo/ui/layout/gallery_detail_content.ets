/*
 * 上游：app/src/main/res/layout/gallery_detail_content.xml
 * 目标：harmony/entry/src/main/ets/hippo/ui/layout/gallery_detail_content.ets（inventory S0589）
 *
 * 结构（按上游 XML 父子关系，不能搞错）：
 *   LinearLayout
 *    └ FrameLayout
 *       ├ include gallery_detail_header            ← below_header **之外**（不随内容滚动）
 *       └ LinearLayout#below_header
 *          └ include info / actions / tags / comments / previews / progress   （6 个，在滚动区内）
 *
 * ArkUI 的 include = 组件组合：@Builder 内直接实例化已移植的 7 个布局组件。
 * 5 个（info/actions/tags/comments/previews）在上游是"可选显示"，这里用 if 条件渲染
 * （ArkUI 的 if 不占位，比 Visibility.None 更干净 —— 陷阱：None 仍参与 weight 分配）。
 */
import { GalleryDetailHeaderLayout } from './gallery_detail_header';
import { GalleryDetailInfoLayout } from './gallery_detail_info';
import { GalleryDetailActionsLayout } from './gallery_detail_actions';
import { GalleryDetailTagsLayout } from './gallery_detail_tags';
import { GalleryDetailCommentsLayout } from './gallery_detail_comments';
import { GalleryDetailPreviewsLayout } from './gallery_detail_previews';
import { GalleryDetailProgressLayout } from './gallery_detail_progress';

@Component
export struct GalleryDetailContentLayout {
  // 五个可选区块的可见性（上游由 GalleryDetailScene 的 setVisibility 控制）
  @Prop showInfo: boolean = true;
  @Prop showActions: boolean = true;
  @Prop showTags: boolean = true;
  @Prop showComments: boolean = true;
  @Prop showPreviews: boolean = true;
  @Prop showProgress: boolean = false;

  build() {
    Column() {
      Stack() {
        // ① header：below_header 之外
        GalleryDetailHeaderLayout()

        Column() {
          // ② below_header 内的 6 个 include
          if (this.showInfo) {
            GalleryDetailInfoLayout()
          }
          if (this.showActions) {
            GalleryDetailActionsLayout()
          }
          if (this.showTags) {
            GalleryDetailTagsLayout()
          }
          if (this.showPreviews) {
            GalleryDetailPreviewsLayout()
          }
          if (this.showComments) {
            GalleryDetailCommentsLayout()
          }
          if (this.showProgress) {
            GalleryDetailProgressLayout()
          }
        }
        .id('belowHeader')
        .width('100%')
      }
      .width('100%')
      .height('100%')
    }
    .width('100%')
    .height('100%')
  }
}
