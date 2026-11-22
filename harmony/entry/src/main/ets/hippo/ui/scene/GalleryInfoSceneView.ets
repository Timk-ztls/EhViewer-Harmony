/*
 * GalleryInfoSceneView: UI for GalleryInfoScene (detailed gallery metadata key/value rows, copy & open parent link).
 */
import {
  ThemeDimens,
  ThemeElevation,
  ThemeMode,
  ThemePalette,
  ThemeTokens,
  ThemeTypography
} from '../../../common/theme/ThemeTokens';
import { GalleryInfoRowSpec, GalleryInfoScene } from '../../ehviewer/ui/scene/GalleryInfoScene';
import { GalleryInfoSceneShell } from '../../ehviewer/ui/scene/GalleryInfoSceneShell';
import { MainPageHost } from '../MainPageHost';
import { VArrowLeftDarkX24 } from '../drawable/v_arrow_left_dark_x24';
import { BigSadPandroid } from '../drawable/big_sad_pandroid';

@Component
export struct GalleryInfoSceneView {
  shell: GalleryInfoSceneShell | null = null;
  host: MainPageHost | null = null;

  @State rows: GalleryInfoRowSpec[] = [];
  @Prop themeId: number = -1;

  private palette(): ThemePalette {
    return this.themeId >= 0 ? ThemeTokens.of(this.themeId) : ThemeTokens.current();
  }

  aboutToAppear(): void {
    this.syncRows();
  }

  private syncRows(): void {
    const sh: GalleryInfoSceneShell | null = this.shell;
    if (sh === null) {
      this.rows = [];
      return;
    }
    const logic: GalleryInfoScene = sh.getLogic();
    const count: number = logic.getItemCount();
    const list: GalleryInfoRowSpec[] = [];
    for (let i = 0; i < count; i++) {
      const row: GalleryInfoRowSpec | null = logic.bindItem(i);
      if (row !== null) {
        list.push(row);
      }
    }
    this.rows = list;
  }

  private handleBack(): void {
    if (this.shell !== null) {
      this.shell.getLogic().onNavigationClick();
    } else if (this.host !== null) {
      this.host.goBack();
    }
  }

  @Builder
  materialToolbar() {
    Row() {
      Row() {
        VArrowLeftDarkX24({
          iconSize: ThemeDimens.ICON_SIZE_STANDARD,
          fillColor: this.palette().toolbarIconColor
        })
      }
      .width(ThemeDimens.TOUCH_TARGET_MIN)
      .height(ThemeDimens.TOUCH_TARGET_MIN)
      .justifyContent(FlexAlign.Center)
      .alignItems(VerticalAlign.Center)
      .onClick((): void => {
        this.handleBack();
      })

      Text($r('app.string.gallery_info'))
        .fontSize(ThemeTypography.TOOLBAR_TITLE)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.palette().toolbarTitleColor)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .margin({ left: ThemeDimens.SPACING })
        .layoutWeight(1)
    }
    .width('100%')
    .height(ThemeDimens.TOOLBAR_HEIGHT)
    .padding({ left: ThemeDimens.SPACING_XS, right: ThemeDimens.SPACING_XS })
    .backgroundColor(this.palette().toolbarColor)
    .shadow(ThemeElevation.toolbar())
    .alignItems(VerticalAlign.Center)
    .zIndex(2)
  }

  build() {
    Column() {
      this.materialToolbar()

      if (this.rows.length === 0) {
        Column({ space: 12 }) {
          BigSadPandroid({
            iconSize: 120,
            fillColor: this.palette().drawableSecondary
          })
          Text($r('app.string.empty_result'))
            .fontSize(ThemeTypography.TEXT_MEDIUM)
            .fontColor(this.palette().textSecondary)
            .textAlign(TextAlign.Center)
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
      } else {
        List() {
          ForEach(this.rows, (row: GalleryInfoRowSpec, idx: number) => {
            ListItem() {
              Row() {
                Text(row.key)
                  .width(90)
                  .padding(ThemeDimens.SPACING)
                  .fontSize(ThemeTypography.TEXT_SMALL)
                  .fontColor(row.enabled ? this.palette().textPrimary : this.palette().textSecondary)

                Text(row.value)
                  .layoutWeight(1)
                  .padding(ThemeDimens.SPACING)
                  .fontSize(ThemeTypography.TEXT_SMALL)
                  .fontColor(row.enabled ? this.palette().textPrimary : this.palette().textSecondary)
              }
              .width('100%')
              .padding({
                left: ThemeDimens.KEYLINE_MARGIN,
                right: ThemeDimens.KEYLINE_MARGIN
              })
              .alignItems(VerticalAlign.Top)
              .onClick((): void => {
                if (this.shell !== null && row.enabled) {
                  this.shell.getLogic().onItemClick(idx);
                }
              })
            }
          }, (row: GalleryInfoRowSpec, idx: number) => `${idx}_${row.key}`)
        }
        .width('100%')
        .layoutWeight(1)
        .contentStartOffset(ThemeDimens.KEYLINE_MARGIN)
        .contentEndOffset(ThemeDimens.KEYLINE_MARGIN)
        .divider({
          strokeWidth: ThemeDimens.DIVIDER_HEIGHT,
          color: this.palette().divider,
          startMargin: ThemeDimens.KEYLINE_MARGIN,
          endMargin: ThemeDimens.KEYLINE_MARGIN
        })
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.palette().windowBackground)
  }
}
