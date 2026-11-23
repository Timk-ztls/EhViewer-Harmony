/*
 * Copyright 2026 ehviewer-harmony contributors
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

import {
  ThemeDimens,
  ThemeElevation,
  ThemePalette,
  ThemeRadius,
  ThemeTokens,
  ThemeTypography
} from '../../common/theme/ThemeTokens';

/**
 * Standard Material Design `customStyle: true` dialog presenting E-Hentai daily/event pane content.
 * Styled uniformly with three-state `ThemeTokens` (light/dark/black).
 */
@CustomDialog
export struct EhEventPaneMaterialDialog {
  controller?: CustomDialogController;
  bodyText: string = '';
  themeId: number = -1;
  onDismiss: () => void = (): void => {};

  private palette(): ThemePalette {
    return this.themeId >= 0 ? ThemeTokens.of(this.themeId) : ThemeTokens.current();
  }

  build() {
    Column() {
      Text($r('app.string.settings_eh_show_eh_event'))
        .fontSize(ThemeTypography.DIALOG_TITLE)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.palette().textPrimary)
        .width('100%')
        .padding({ left: 24, right: 24, top: 20, bottom: 12 })

      Scroll() {
        Column() {
          Text(this.bodyText)
            .fontSize(ThemeTypography.CARD_MESSAGE)
            .fontColor(this.palette().textSecondary)
            .lineHeight(22)
            .copyOption(CopyOptions.LocalDevice)
            .width('100%')
        }
        .width('100%')
        .padding({ left: 24, right: 24, top: 4, bottom: 16 })
      }
      .align(Alignment.TopStart)
      .width('100%')
      .constraintSize({ maxHeight: 380 })

      Row({ space: 8 }) {
        Button({ type: ButtonType.Normal }) {
          Text($r('app.string.ok'))
            .fontSize(ThemeTypography.BUTTON)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.palette().colorPrimary)
            .textCase(TextCase.UpperCase)
        }
        .backgroundColor(Color.Transparent)
        .borderRadius(ThemeRadius.BUTTON)
        .constraintSize({ minHeight: 36, minWidth: 64 })
        .padding({ left: 12, right: 12 })
        .onClick((): void => {
          if (this.controller !== undefined) {
            this.controller.close();
          }
          this.onDismiss();
        })
      }
      .width('100%')
      .justifyContent(FlexAlign.End)
      .padding({ left: 16, right: 16, top: 8, bottom: 12 })
    }
    .width('86%')
    .constraintSize({ maxWidth: ThemeDimens.DIALOG_MAX_WIDTH })
    .backgroundColor(this.palette().popupBackground)
    .borderRadius(ThemeRadius.DIALOG)
    .shadow(ThemeElevation.dialog())
  }
}
