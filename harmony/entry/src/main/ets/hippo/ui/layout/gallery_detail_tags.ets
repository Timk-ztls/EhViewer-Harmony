/*
 * 上游：app/src/main/res/layout/gallery_detail_tags.xml
 * 目标：harmony/entry/src/main/ets/hippo/ui/layout/gallery_detail_tags.ets（inventory S0594）
 */

import {
  ThemeDimens,
  ThemeMode,
  ThemePalette,
  ThemeTokens,
  ThemeTypography
} from '../../../common/theme/ThemeTokens';
import { TagGroupView } from '../../ehviewer/ui/scene/gallery/detail/GalleryDetailBind';
import { GalleryTagGroupLayout } from './gallery_tag_group';

@Component
export struct GalleryDetailTagsLayout {
  @Prop tagGroups: TagGroupView[] = [];
  @Prop noTags: ResourceStr = $r('app.string.no_tags');
  @Prop themeId: number = ThemeMode.LIGHT;
  onTagClick: (fullTag: string) => void = (_fullTag: string): void => {};
  onTagLongClick: (fullTag: string) => void = (_fullTag: string): void => {};

  private palette(): ThemePalette {
    return ThemeTokens.of(this.themeId);
  }

  build() {
    Column() {
      if (this.tagGroups.length === 0) {
        Text(this.noTags)
          .id('noTags')
          .fontSize(ThemeTypography.TEXT_SMALL)
          .fontColor(this.palette().textThemeAccent)
      } else {
        ForEach(this.tagGroups, (tg: TagGroupView) => {
          GalleryTagGroupLayout({
            groupName: tg.groupName,
            displayGroupName: tg.displayName,
            tags: tg.tags,
            themeId: this.themeId,
            onTagClick: (fullTag: string): void => {
              this.onTagClick(fullTag);
            },
            onTagLongClick: (fullTag: string): void => {
              this.onTagLongClick(fullTag);
            }
          })
        }, (tg: TagGroupView) => tg.groupName)
      }
    }
    .id('tags')
    .width('100%')
    .alignItems(this.tagGroups.length === 0 ? HorizontalAlign.Center : HorizontalAlign.Start)
    .padding(ThemeDimens.KEYLINE_MARGIN)
  }
}
