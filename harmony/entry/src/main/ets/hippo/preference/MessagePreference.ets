/**
 * 迁移自 app/src/main/java/com/hippo/preference/MessagePreference.java（inventory S0448，上游 72 行）
 *
 * 判据：**完全重复** —— 上游只是"点一行 → 弹一个只有标题/正文/确定按钮的对话框"，无自有逻辑。
 * 上游 extends DialogPreference 但只覆写 onPrepareDialogBuilder 设置 message，不收集任何输入。
 *
 * ArkUI 对位：SettingsItem 行 + Material `@CustomDialog`（`customStyle: true`、`ThemeTokens` 动态主题）。
 * 差异（已登记 MR）：上游用 AlertDialog.Builder 且可配 cancelable/按钮文案；
 *   ArkUI 改用 `CustomDialogController` 驱动 `MessagePreferenceMaterialDialog`（打开时按当前主题重建）。
 */
import {
  ThemeDimens,
  ThemeElevation,
  ThemePalette,
  ThemeRadius,
  ThemeTokens,
  ThemeTypography
} from '../../common/theme/ThemeTokens';
import { SettingsItem } from '../ui/settings/SettingsItem';

function isNonEmptyResourceStr(v: ResourceStr): boolean {
  if (typeof v === 'string') {
    return v.length > 0;
  }
  return true;
}

@CustomDialog
struct MessagePreferenceMaterialDialog {
  controller?: CustomDialogController;
  titleText: ResourceStr = '';
  messageText: ResourceStr = '';
  positiveText: ResourceStr = '';
  negativeText: ResourceStr = '';
  showNegativeButton: boolean = true;
  themeId: number = -1;
  onPositive: () => void = (): void => {
  };
  onNegative: () => void = (): void => {
  };

  private palette(): ThemePalette {
    return this.themeId >= 0 ? ThemeTokens.of(this.themeId) : ThemeTokens.current();
  }

  build() {
    Column() {
      if (isNonEmptyResourceStr(this.titleText)) {
        Text(this.titleText)
          .fontSize(ThemeTypography.DIALOG_TITLE)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.palette().textPrimary)
          .width('100%')
          .padding({ left: 24, right: 24, top: 20, bottom: 12 })
      }

      Scroll() {
        Column() {
          Text(this.messageText)
            .fontSize(ThemeTypography.CARD_MESSAGE)
            .fontColor(this.palette().textSecondary)
            .width('100%')
        }
        .width('100%')
        .padding({ left: 24, right: 24, top: 4, bottom: 16 })
      }
      .align(Alignment.TopStart)
      .width('100%')
      .constraintSize({ maxHeight: 400 })

      Row({ space: 8 }) {
        if (this.showNegativeButton) {
          Button({ type: ButtonType.Normal }) {
            Text(this.negativeText)
              .fontSize(ThemeTypography.BUTTON)
              .fontWeight(FontWeight.Medium)
              .fontColor(this.palette().textSecondary)
              .textCase(TextCase.UpperCase)
          }
          .backgroundColor(Color.Transparent)
          .borderRadius(ThemeRadius.BUTTON)
          .constraintSize({ minHeight: 36, minWidth: 64 })
          .padding({ left: 12, right: 12 })
          .onClick(() => {
            if (this.controller !== undefined) {
              this.controller.close();
            }
            this.onNegative();
          })
        }

        Button({ type: ButtonType.Normal }) {
          Text(this.positiveText)
            .fontSize(ThemeTypography.BUTTON)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.palette().colorPrimary)
            .textCase(TextCase.UpperCase)
        }
        .backgroundColor(Color.Transparent)
        .borderRadius(ThemeRadius.BUTTON)
        .constraintSize({ minHeight: 36, minWidth: 64 })
        .padding({ left: 12, right: 12 })
        .onClick(() => {
          if (this.controller !== undefined) {
            this.controller.close();
          }
          this.onPositive();
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

@Component
export struct MessagePreference {
  @Prop title: string = '';
  @Prop summary: string = '';
  @Prop message: ResourceStr = '';
  @Prop dialogTitle: ResourceStr = '';
  @Prop positiveText: ResourceStr = '';
  @Prop negativeText: ResourceStr = '';
  @Prop showNegativeButton: boolean = true;
  @Prop autoCancel: boolean = true;
  @Prop itemEnabled: boolean = true;
  @Prop themeId: number = -1;
  @Prop showDivider: boolean = false;
  onConfirm: () => void = () => {
  };
  onShown: () => void = () => {
  };
  onCancel: () => void = () => {
  };
  private dialogController: CustomDialogController | null = null;

  aboutToDisappear(): void {
    this.dialogController = null;
  }

  private effectiveTitle(): ResourceStr {
    return isNonEmptyResourceStr(this.dialogTitle) ? this.dialogTitle : this.title;
  }

  private effectivePositiveText(): ResourceStr {
    return isNonEmptyResourceStr(this.positiveText) ? this.positiveText : $r('app.string.ok');
  }

  private effectiveNegativeText(): ResourceStr {
    return isNonEmptyResourceStr(this.negativeText) ? this.negativeText : $r('app.string.cancel');
  }

  private handlePositiveClick(): void {
    this.onConfirm();
    this.onShown();
  }

  private openDialog(): void {
    this.dialogController = new CustomDialogController({
      builder: MessagePreferenceMaterialDialog({
        titleText: this.effectiveTitle(),
        messageText: this.message,
        positiveText: this.effectivePositiveText(),
        negativeText: this.effectiveNegativeText(),
        showNegativeButton: this.showNegativeButton,
        themeId: this.themeId,
        onPositive: (): void => {
          this.handlePositiveClick();
        },
        onNegative: (): void => {
          this.onCancel();
        }
      }),
      customStyle: true,
      autoCancel: this.autoCancel,
      alignment: DialogAlignment.Center,
      cancel: (): void => {
        this.onCancel();
      }
    });
    this.dialogController.open();
  }

  build() {
    SettingsItem({
      title: this.title,
      summary: this.summary,
      itemEnabled: this.itemEnabled,
      themeId: this.themeId,
      showDivider: this.showDivider,
      onItemClick: () => {
        this.openDialog();
      }
    })
  }
}
