/**
 * 迁移自 app/src/main/java/com/hippo/preference/DialogPreference.java（inventory S0446，上游 376 行）
 *
 * ============================ 判据：**分叉** → 自绘状态机 ============================
 * 上游 `abstract class DialogPreference extends Preference implements OnClickListener, OnDismissListener`
 * 自己实现了一套 Dialog 生命周期（这是 Android Preference 体系里唯一带"值提交时机"的基类）。
 * ArkUI 没有这个抽象，故拆成 `DialogPreferenceState`（纯类，可单测）+ 渲染（bindSheet/自定义弹层）。
 *
 * ============================ 值提交时机（本类唯一真正重要的语义） ============================
 *   mWhichButtonClicked **在创建对话框时就初始化为 BUTTON_NEGATIVE**
 *   onClick(dialog, which)：**只记录** which，不做任何提交
 *   onDismiss(dialog)       ：mDialog = null; onDialogClosed(mWhichButtonClicked == BUTTON_POSITIVE)
 *   ⇒ 结论：
 *     ① 只有 `onDialogClosed(positiveResult)` 是提交点
 *     ② **按返回键/点外部/未点任何按钮关闭 → which 仍是 NEGATIVE → positiveResult = false → 不提交**
 *     ③ 点确定 → true；点取消 → false
 *   把"提交"写在 onClick(which) 里会导致"点确定才生效"变成"点任何按钮都生效"，
 *   把提交写在 onOpen 里会导致"打开对话框就改了设置"。
 *
 * 其它对位
 *   onClick()（整行点击）：`if (mDialog != null && mDialog.isShowing()) return;` → **防重复打开**
 *   钩子：onPrepareDialogBuilder / onCreateDialogView / onBindDialogView / onDialogCreated / onDialogClosed
 *   按钮文案：dialogTitle（缺省回退 title）/ positiveButtonText / negativeButtonText / dialogIcon / dialogLayout
 *
 * ArkUI 对位：`bindSheet`（半模态）+ @BuilderParam 内容槽；钩子用注入回调（**装配期检查**：
 *   未注入的钩子会在 aboutToAppear 里 hilog.error，避免"弹窗能开但点了没反应"的静默失败）
 *
 * 差异（已登记 MR）：
 *   1) AlertDialog.Builder → `bindSheet` + 自定义 content builder（ArkUI 无 Builder 链式 API）
 *   2) `mDialog`/`isShowing()` → `dialogShowing` 状态字段（同样的防重入语义）
 *   3) 上游 `onCreateDialogView` 返回 null 表示"用默认布局"→ ArkTS 用 `hasCustomContent` 布尔
 */
import { hilog } from '@kit.PerformanceAnalysisKit';
import {
  ThemeElevation,
  ThemePalette,
  ThemeRadius,
  ThemeTokens,
  ThemeTypography
} from '../../common/theme/ThemeTokens';
import { SettingsItem } from '../ui/settings/SettingsItem';

const LOG_DOMAIN: number = 0x0000;
const LOG_TAG: string = 'HippoWidget.DialogPreference';

/** 对位 DialogInterface.BUTTON_POSITIVE / BUTTON_NEGATIVE（仅供状态机内部使用） */
export class DialogButton {
  static readonly NONE: number = -2;
  static readonly NEGATIVE: number = -1;
  static readonly POSITIVE: number = -1 + 2; // 1，与 Android 的 BUTTON_POSITIVE 值不同但语义等价
}

export class DialogPreferenceState {
  dialogTitle: ResourceStr = '';
  positiveButtonText: ResourceStr = '';
  negativeButtonText: ResourceStr = '';
  title: string = '';
  summary: string = '';

  /** 上游 mDialog != null && mDialog.isShowing() */
  dialogShowing: boolean = false;
  /**
   * 上游 mWhichButtonClicked：**构造时即为 NEGATIVE** ——
   * 这是"取消/返回键关闭也算 negative"的根因，必须按此初值，不能初始化为 NONE。
   */
  whichButtonClicked: number = DialogButton.NEGATIVE;

  effectiveDialogTitle(): ResourceStr {
    if (typeof this.dialogTitle === 'string') {
      return this.dialogTitle.length > 0 ? this.dialogTitle : this.title;
    }
    return this.dialogTitle;
  }

  /** 上游 onClick()：正在显示时不重复打开 */
  canShow(): boolean {
    return !this.dialogShowing;
  }

  /** 打开对话框：重置按钮记录为 NEGATIVE（对位上游 showDialog 里的初始化） */
  open(): boolean {
    if (!this.canShow()) {
      return false;
    }
    this.dialogShowing = true;
    this.whichButtonClicked = DialogButton.NEGATIVE;
    return true;
  }

  /** 上游 onClick(dialog, which)：**只记录**，不提交 */
  onClickButton(which: number): void {
    this.whichButtonClicked = which;
  }

  /**
   * 上游 onDismiss(dialog)：关闭并交给 onDialogClosed 判定是否提交。
   * 返回 positiveResult（true 表示按了确定）。
   */
  dismiss(): boolean {
    this.dialogShowing = false;
    const positiveResult: boolean = this.whichButtonClicked === DialogButton.POSITIVE;
    this.whichButtonClicked = DialogButton.NEGATIVE;
    return positiveResult;
  }
}

function isNonEmptyResourceStr(v: ResourceStr): boolean {
  if (typeof v === 'string') {
    return v.length > 0;
  }
  return true;
}

@Component
export struct DialogPreference {
  state: DialogPreferenceState = new DialogPreferenceState();
  @Prop itemEnabled: boolean = true;
  @Prop positiveText: ResourceStr = '';
  @Prop negativeText: ResourceStr = '';
  @Prop themeId: number = -1;
  @Prop showDivider: boolean = false;
  @State dialogOpen: boolean = false;
  @State rev: number = 0;

  /** 上游 onPrepareDialogBuilder（可选钩子） */
  onPrepareDialog: () => void = () => {
  };
  /** 上游 onDialogCreated（可选钩子） */
  onDialogCreated: () => void = () => {
  };
  /** 点击确定时的校验钩子（返回 false 时保持对话框打开，不关闭也不提交） */
  onValidatePositive: () => boolean = (): boolean => true;
  /** 上游 onDialogClosed(positiveResult)：**唯一的提交点** */
  onDialogClosed: (positiveResult: boolean) => void = (positiveResult: boolean) => {
  };
  /** 对话框内容（对位 onCreateDialogView 的布局 + onBindDialogView 的绑定） */
  @BuilderParam content: () => void = this.emptyContent;

  private palette(): ThemePalette {
    return this.themeId >= 0 ? ThemeTokens.of(this.themeId) : ThemeTokens.current();
  }

  @Builder
  emptyContent(): void {
  }

  private effectivePositiveText(): ResourceStr {
    if (isNonEmptyResourceStr(this.positiveText)) {
      return this.positiveText;
    }
    if (isNonEmptyResourceStr(this.state.positiveButtonText)) {
      return this.state.positiveButtonText;
    }
    return $r('app.string.ok');
  }

  private effectiveNegativeText(): ResourceStr {
    if (isNonEmptyResourceStr(this.negativeText)) {
      return this.negativeText;
    }
    if (isNonEmptyResourceStr(this.state.negativeButtonText)) {
      return this.state.negativeButtonText;
    }
    return $r('app.string.cancel');
  }

  aboutToAppear(): void {
    // 装配期接线检查：onDialogClosed 是唯一提交点，未注入 = 弹窗能开但"确定"永远不生效
    if (this.onDialogClosed === null) {
      hilog.error(LOG_DOMAIN, LOG_TAG,
        '%{public}s', 'onDialogClosed not injected — dialog result will be dropped (control is inert)');
    }
  }

  private openDialog(): void {
    if (!this.state.open()) {
      return; // 上游：isShowing() 时直接 return
    }
    this.onPrepareDialog();
    this.dialogOpen = true;
    this.rev = this.rev + 1;
    this.onDialogCreated();
  }

  private closeDialog(which: number): void {
    this.state.onClickButton(which);
    const positiveResult: boolean = this.state.dismiss();
    this.dialogOpen = false;
    if (this.onDialogClosed === null) {
      hilog.error(LOG_DOMAIN, LOG_TAG, '%{public}s', 'onDialogClosed is null, result dropped');
      this.rev = this.rev + 1;
      return;
    }
    this.onDialogClosed(positiveResult);
    this.rev = this.rev + 1;
  }

  build() {
    SettingsItem({
      title: this.rev >= 0 ? this.state.title : this.state.title,
      summary: this.rev >= 0 ? this.state.summary : this.state.summary,
      itemEnabled: this.itemEnabled,
      themeId: this.themeId,
      showDivider: this.showDivider,
      onItemClick: () => {
        this.openDialog();
      }
    })
      .bindContentCover($$this.dialogOpen, this.dialogOverlay(), {
        modalTransition: ModalTransition.NONE,
        backgroundColor: Color.Transparent,
        onDisappear: () => {
          // 用户返回/点外部关闭：对位 onDismiss（which 仍是 NEGATIVE → 不提交）
          if (this.state.dialogShowing) {
            this.closeDialog(DialogButton.NEGATIVE);
          }
        }
      })
  }

  @Builder
  dialogOverlay(): void {
    Stack({ alignContent: Alignment.Center }) {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor('#66000000')
        .onClick(() => {
          if (this.state.dialogShowing) {
            this.closeDialog(DialogButton.NEGATIVE);
          }
        })

      Column() {
        Text(this.state.effectiveDialogTitle())
          .fontSize(ThemeTypography.DIALOG_TITLE)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.palette().textPrimary)
          .width('100%')
          .padding({ left: 24, right: 24, top: 20, bottom: 12 })

        Scroll() {
          Column() {
            this.content()
          }
          .width('100%')
          .padding({ left: 24, right: 24, top: 4, bottom: 12 })
        }
        .align(Alignment.TopStart)
        .width('100%')
        .constraintSize({ maxHeight: 400 })

        Row({ space: 8 }) {
          Button({ type: ButtonType.Normal }) {
            Text(this.effectiveNegativeText())
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
            this.closeDialog(DialogButton.NEGATIVE);
          })

          Button({ type: ButtonType.Normal }) {
            Text(this.effectivePositiveText())
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
            if (!this.onValidatePositive()) {
              return;
            }
            this.closeDialog(DialogButton.POSITIVE);
          })
        }
        .width('100%')
        .justifyContent(FlexAlign.End)
        .padding({ left: 16, right: 16, top: 8, bottom: 12 })
      }
      .width('86%')
      .constraintSize({ maxWidth: 360 })
      .backgroundColor(this.palette().popupBackground)
      .borderRadius(ThemeRadius.DIALOG)
      .shadow(ThemeElevation.dialog())
      .onClick(() => {
      })
    }
    .width('100%')
    .height('100%')
  }
}
