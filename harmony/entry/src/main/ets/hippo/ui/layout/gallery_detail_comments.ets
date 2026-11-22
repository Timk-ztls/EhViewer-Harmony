/*
 * 上游：app/src/main/res/layout/gallery_detail_comments.xml
 * 目标：harmony/entry/src/main/ets/hippo/ui/layout/gallery_detail_comments.ets（inventory S0588）
 */

import {
  ThemeDimens,
  ThemeMode,
  ThemePalette,
  ThemeRadius,
  ThemeTokens,
  ThemeTypography
} from '../../../common/theme/ThemeTokens';
import { GalleryComment } from '../../ehviewer/client/data/GalleryComment';
import { GalleryCommentItemLayout } from './item_gallery_comment';

@Component
export struct GalleryDetailCommentsLayout {
  @Prop comments: GalleryComment[] = [];
  @Prop commentsText: ResourceStr = $r('app.string.no_comments');
  @Prop themeId: number = ThemeMode.LIGHT;
  formatTime: (ms: number) => string = (_ms: number): string => '';
  formatBody: (html: string) => string = (html: string): string => html;
  formatScore: (c: GalleryComment) => string = (_c: GalleryComment): string => '';
  onCommentsClick: () => void = (): void => {};

  private palette(): ThemePalette {
    return ThemeTokens.of(this.themeId);
  }

  build() {
    Column({ space: ThemeDimens.KEYLINE_MARGIN }) {
      if (this.comments.length > 0) {
        Column() {
          ForEach(this.comments, (c: GalleryComment, idx: number) => {
            GalleryCommentItemLayout({
              user: c.user,
              time: this.formatTime(c.time),
              comment: this.formatBody(c.comment),
              scoreText: this.formatScore(c),
              maxLinesLimit: 5,
              themeId: this.themeId
            })
          }, (c: GalleryComment, idx: number) => String(c.id) + '_' + String(idx))
        }
        .width('100%')
      }

      Button(this.commentsText, { type: ButtonType.Normal })
        .id('commentsText')
        .borderRadius(ThemeRadius.BUTTON)
        .backgroundColor(this.palette().transparent)
        .fontColor(this.palette().textThemeAccent)
        .fontSize(ThemeTypography.BUTTON)
        .fontWeight(FontWeight.Medium)
        .width('100%')
        .constraintSize({ minHeight: ThemeDimens.TOUCH_TARGET_MIN })
        .padding({ left: 16, right: 16 })
        .onClick((): void => {
          this.onCommentsClick();
        })
    }
    .id('comments')
    .width('100%')
    .alignItems(HorizontalAlign.Center)
    .padding(ThemeDimens.KEYLINE_MARGIN)
  }
}
