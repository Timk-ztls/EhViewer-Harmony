/*
 * 上游：app/src/main/res/layout/item_gallery_comment.xml（inventory S0615）
 * 目标：harmony/entry/src/main/ets/hippo/ui/layout/item_gallery_comment.ets
 */

import {
  ThemeDimens,
  ThemeMode,
  ThemePalette,
  ThemeTokens,
  ThemeTypography
} from '../../../common/theme/ThemeTokens';

@Component
export struct GalleryCommentItemLayout {
  @Prop user: string = '';
  @Prop time: string = '';
  @Prop comment: string = '';
  @Prop scoreText: string = '';
  @Prop lastEditedText: string = '';
  @Prop maxLinesLimit: number = 0;
  @Prop themeId: number = ThemeMode.LIGHT;

  @BuilderParam commentBuilder: () => void = this.defaultComment;

  private palette(): ThemePalette {
    return ThemeTokens.of(this.themeId);
  }

  @Builder
  defaultComment() {
    Column({ space: 6 }) {
      Text(this.comment)
        .fontSize(ThemeTypography.TEXT_SMALL)
        .fontColor(this.palette().textPrimary)
        .maxLines(this.maxLinesLimit > 0 ? this.maxLinesLimit : 999)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')

      if (this.lastEditedText.length > 0) {
        Text(this.lastEditedText)
          .fontSize(ThemeTypography.TEXT_SUPER_SMALL)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.palette().textSecondary)
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  build() {
    Column() {
      Row() {
        Text(this.user)
          .id('user')
          .fontSize(ThemeTypography.TEXT_SUPER_SMALL)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.palette().textPrimary)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)

        if (this.scoreText.length > 0) {
          Text(this.scoreText)
            .fontSize(ThemeTypography.TEXT_SUPER_SMALL)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.palette().textSecondary)
            .margin({ left: 8 })
        }

        Text(this.time)
          .id('time')
          .fontSize(ThemeTypography.TEXT_SUPER_SMALL)
          .fontColor(this.palette().textSecondary)
          .margin({ left: 8 })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

      Column() {
        this.commentBuilder()
      }
      .id('comment')
      .width('100%')
      .alignItems(HorizontalAlign.Start)
      .margin({ top: 8 })
    }
    .width('100%')
    .padding({
      left: ThemeDimens.KEYLINE_MARGIN,
      right: ThemeDimens.KEYLINE_MARGIN,
      top: 8,
      bottom: 8
    })
  }
}
