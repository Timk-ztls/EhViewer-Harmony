/*
 * 上游：app/src/main/res/layout/item_gallery_tag.xml（inventory S0624）
 * 目标：harmony/entry/src/main/ets/hippo/ui/layout/item_gallery_tag.ets
 */

import {
  ThemeMode,
  ThemePalette,
  ThemeRadius,
  ThemeTokens,
  ThemeTypography
} from '../../../common/theme/ThemeTokens';

@Component
export struct GalleryTagItemLayout {
  @Prop text: string = '';
  @Prop isNamespace: boolean = false;
  @Prop themeId: number = ThemeMode.LIGHT;
  onTagClick: () => void = (): void => {};
  onTagLongClick: () => void = (): void => {};

  private palette(): ThemePalette {
    return ThemeTokens.of(this.themeId);
  }

  build() {
    Text(this.text)
      .fontSize(ThemeTypography.TEXT_SUPER_SMALL)
      .fontColor(this.palette().white)
      .backgroundColor(this.isNamespace ? this.palette().tagGroupBackground : this.palette().tagBackground)
      .padding({ left: 6, right: 6, top: 3, bottom: 3 })
      .borderRadius(ThemeRadius.TAG)
      .margin(this.isNamespace ? { right: 6, bottom: 4 } : { right: 4, bottom: 4 })
      .maxLines(1)
      .textOverflow({ overflow: TextOverflow.Ellipsis })
      .onClick((): void => {
        this.onTagClick();
      })
      .gesture(
        LongPressGesture()
          .onAction((): void => {
            this.onTagLongClick();
          })
      )
  }
}
