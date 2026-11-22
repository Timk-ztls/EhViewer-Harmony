/*
 * 上游：app/src/main/res/layout/gallery_tag_group.xml
 * 目标：harmony/entry/src/main/ets/hippo/ui/layout/gallery_tag_group.ets（inventory S0598）
 */

import { ThemeMode } from '../../../common/theme/ThemeTokens';
import { TagChip } from '../../ehviewer/ui/scene/gallery/detail/GalleryDetailBind';
import { GalleryTagItemLayout } from './item_gallery_tag';

@Component
export struct GalleryTagGroupLayout {
  @Prop groupName: string = '';
  @Prop displayGroupName: string = '';
  @Prop tags: TagChip[] = [];
  @Prop themeId: number = ThemeMode.LIGHT;
  onTagClick: (fullTag: string) => void = (_fullTag: string): void => {};
  onTagLongClick: (fullTag: string) => void = (_fullTag: string): void => {};

  build() {
    Row() {
      if (this.groupName.length > 0 || this.displayGroupName.length > 0) {
        GalleryTagItemLayout({
          text: this.displayGroupName.length > 0 ? this.displayGroupName : this.groupName,
          isNamespace: true,
          themeId: this.themeId
        })
      }

      Flex({ wrap: FlexWrap.Wrap }) {
        ForEach(this.tags, (chip: TagChip) => {
          GalleryTagItemLayout({
            text: chip.display,
            isNamespace: false,
            themeId: this.themeId,
            onTagClick: (): void => {
              this.onTagClick(chip.fullTag);
            },
            onTagLongClick: (): void => {
              this.onTagLongClick(chip.fullTag);
            }
          })
        }, (chip: TagChip) => chip.fullTag)
      }
      .layoutWeight(1)
    }
    .width('100%')
    .alignItems(VerticalAlign.Top)
    .margin({ bottom: 4 })
  }
}
