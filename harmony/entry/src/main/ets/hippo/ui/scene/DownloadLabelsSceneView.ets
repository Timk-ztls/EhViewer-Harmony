/*
 * DownloadLabelsSceneView: Material Design UI aligned with scene_label_list.xml,
 * item_download_label.xml, menu/scene_download_label.xml & DownloadLabelsScene.java.
 */
import { hilog } from '@kit.PerformanceAnalysisKit';
import {
  ThemeDimens,
  ThemeElevation,
  ThemePalette,
  ThemeRadius,
  ThemeTokens,
  ThemeTypography
} from '../../../common/theme/ThemeTokens';
import { EditTextDialogSpec } from '../../app/DialogSpecs';
import { PathData } from '../../drawable/PathData';
import {
  DeleteLabelDialogSpec,
  DownloadLabelsScene,
  ERROR_LABEL_EMPTY,
  ERROR_LABEL_EXIST,
  ERROR_LABEL_INVALID,
  LabelItemViewModel,
  VIEW_TIP
} from '../../ehviewer/ui/scene/download/DownloadLabelsScene';
import { DownloadLabelsSceneShell } from '../../ehviewer/ui/scene/download/DownloadLabelsSceneShell';
import { DownloadsSceneAction } from '../../ehviewer/ui/scene/download/DownloadsScene';
import { Announcer } from '../../scene/Announcer';
import { SceneArgs } from '../../scene/SceneTypes';
import { BigLabel } from '../drawable/big_label';
import { VDeleteX24 } from '../drawable/v_delete_x24';
import { DownloadLabelItemLayout } from '../layout/item_download_label';
import { SceneLabelListLayout } from '../layout/scene_label_list';
import { MainPageHost } from '../MainPageHost';

const DOMAIN: number = 0x0000;
const TAG: string = 'DownloadLabelsSceneView';
const PD_CHEVRON_UP: string = 'M7.41,15.41L12,10.83L16.59,15.41L18,14L12,8L6,14Z';
const PD_CHEVRON_DOWN: string = 'M7.41,8.59L12,13.17L16.59,8.59L18,10L12,16L6,10Z';

class LabelRowEntry {
  readonly index: number;
  readonly id: number;
  readonly label: string;

  constructor(index: number, id: number, label: string) {
    this.index = index;
    this.id = id;
    this.label = label;
  }
}

@Component
export struct DownloadLabelsSceneView {
  shell: DownloadLabelsSceneShell | null = null;
  host: MainPageHost | null = null;
  @Prop themeId: number = -1;

  @State rows: LabelRowEntry[] = [];
  @State showTip: boolean = true;
  @State addOpen: boolean = false;
  @State newLabelText: string = '';
  @State newLabelFocused: boolean = false;
  @State renameIndex: number = -1;
  @State renameText: string = '';
  @State renameFocused: boolean = false;
  @State deleteIndex: number = -1;
  @State deleteMessage: string = '';
  @State errorRes: Resource | null = null;
  @State errorText: string = '';

  private newDialogSpec: EditTextDialogSpec | null = null;
  private renameDialogSpec: EditTextDialogSpec | null = null;

  private palette(): ThemePalette {
    return this.themeId >= 0 ? ThemeTokens.of(this.themeId) : ThemeTokens.current();
  }

  aboutToAppear(): void {
    const sh: DownloadLabelsSceneShell | null = this.shell;
    if (sh === null) {
      return;
    }
    const logic: DownloadLabelsScene = sh.getLogic();
    logic.onCreate();
    logic.onViewCreated();
    this.syncFromLogic();
  }

  aboutToDisappear(): void {
    const sh: DownloadLabelsSceneShell | null = this.shell;
    if (sh !== null) {
      sh.getLogic().onDestroy();
    }
  }

  private syncFromLogic(): void {
    const sh: DownloadLabelsSceneShell | null = this.shell;
    if (sh === null) {
      this.rows = [];
      this.showTip = true;
      return;
    }
    const logic: DownloadLabelsScene = sh.getLogic();
    const viewIndex: number = logic.updateView();
    this.showTip = viewIndex === VIEW_TIP;
    const count: number = logic.getItemCount();
    const next: LabelRowEntry[] = [];
    for (let i = 0; i < count; i++) {
      const vm: LabelItemViewModel | null = logic.bindItem(i);
      if (vm !== null) {
        next.push(new LabelRowEntry(i, vm.id, vm.label));
      }
    }
    this.rows = next;
  }

  private mapErrorKey(key: string | null): Resource | null {
    if (key === null) {
      return null;
    }
    if (key === ERROR_LABEL_EMPTY) {
      return $r('app.string.label_text_is_empty');
    }
    if (key === ERROR_LABEL_EXIST) {
      return $r('app.string.label_text_exist');
    }
    if (key === ERROR_LABEL_INVALID) {
      return $r('app.string.label_text_is_invalid');
    }
    return $r('app.string.label_text_is_invalid');
  }

  private openAddPanel(): void {
    const sh: DownloadLabelsSceneShell | null = this.shell;
    if (sh === null) {
      return;
    }
    this.renameIndex = -1;
    this.deleteIndex = -1;
    this.errorRes = null;
    this.newDialogSpec = sh.getLogic().buildNewLabelDialog();
    this.newLabelText = '';
    this.addOpen = true;
  }

  private async submitAdd(): Promise<void> {
    const sh: DownloadLabelsSceneShell | null = this.shell;
    if (sh === null) {
      return;
    }
    const logic: DownloadLabelsScene = sh.getLogic();
    const spec: EditTextDialogSpec = this.newDialogSpec !== null
      ? this.newDialogSpec : logic.buildNewLabelDialog();
    spec.text = this.newLabelText.trim();
    try {
      const ok: boolean = await logic.confirmNewLabel(spec);
      if (!ok) {
        this.errorRes = this.mapErrorKey(spec.error);
        return;
      }
      this.errorRes = null;
      this.newLabelText = '';
      this.newDialogSpec = null;
      this.addOpen = false;
      this.syncFromLogic();
    } catch (e) {
      const msg: string = (e as Error).message !== undefined ? (e as Error).message : String(e);
      this.errorText = msg;
      hilog.error(DOMAIN, TAG, 'confirmNewLabel failed: %{public}s', msg);
    }
  }

  private openRenamePanel(index: number): void {
    const sh: DownloadLabelsSceneShell | null = this.shell;
    if (sh === null) {
      return;
    }
    const spec: EditTextDialogSpec | null = sh.getLogic().buildRenameDialog(index);
    if (spec === null) {
      return;
    }
    this.addOpen = false;
    this.deleteIndex = -1;
    this.errorRes = null;
    this.renameDialogSpec = spec;
    this.renameIndex = index;
    this.renameText = spec.getText();
  }

  private async submitRename(): Promise<void> {
    const sh: DownloadLabelsSceneShell | null = this.shell;
    const spec: EditTextDialogSpec | null = this.renameDialogSpec;
    if (sh === null || spec === null) {
      return;
    }
    const logic: DownloadLabelsScene = sh.getLogic();
    spec.text = this.renameText.trim();
    try {
      const ok: boolean = await logic.confirmRename(spec);
      if (!ok) {
        this.errorRes = this.mapErrorKey(spec.error);
        return;
      }
      this.errorRes = null;
      this.renameIndex = -1;
      this.renameText = '';
      this.renameDialogSpec = null;
      this.syncFromLogic();
    } catch (e) {
      const msg: string = (e as Error).message !== undefined ? (e as Error).message : String(e);
      this.errorText = msg;
      hilog.error(DOMAIN, TAG, 'confirmRename failed: %{public}s', msg);
    }
  }

  private openDeletePanel(index: number): void {
    const sh: DownloadLabelsSceneShell | null = this.shell;
    if (sh === null) {
      return;
    }
    const spec: DeleteLabelDialogSpec | null = sh.getLogic().buildDeleteDialog(index);
    if (spec === null) {
      return;
    }
    this.addOpen = false;
    this.renameIndex = -1;
    this.errorRes = null;
    this.deleteIndex = index;
    this.deleteMessage = spec.message;
  }

  private async confirmDeleteLabel(): Promise<void> {
    const sh: DownloadLabelsSceneShell | null = this.shell;
    if (sh === null) {
      this.deleteIndex = -1;
      return;
    }
    const logic: DownloadLabelsScene = sh.getLogic();
    try {
      await logic.confirmDelete();
      logic.onDeleteDialogDismiss();
      this.deleteIndex = -1;
      this.deleteMessage = '';
      this.syncFromLogic();
    } catch (e) {
      const msg: string = (e as Error).message !== undefined ? (e as Error).message : String(e);
      this.errorText = msg;
      hilog.error(DOMAIN, TAG, 'confirmDelete failed: %{public}s', msg);
    }
  }

  private cancelDeleteLabel(): void {
    const sh: DownloadLabelsSceneShell | null = this.shell;
    if (sh !== null) {
      sh.getLogic().onDeleteDialogDismiss();
    }
    this.deleteIndex = -1;
    this.deleteMessage = '';
    this.syncFromLogic();
  }

  private async moveRow(from: number, to: number): Promise<void> {
    const sh: DownloadLabelsSceneShell | null = this.shell;
    if (sh === null || to < 0 || to >= this.rows.length) {
      return;
    }
    try {
      await sh.getLogic().onMoveItem(from, to);
      this.syncFromLogic();
    } catch (e) {
      const msg: string = (e as Error).message !== undefined ? (e as Error).message : String(e);
      this.errorText = msg;
      hilog.error(DOMAIN, TAG, 'onMoveItem failed: %{public}s', msg);
    }
  }

  private openDownloadsForLabel(label: string | null): void {
    const args: SceneArgs = new Map<string, Object>();
    if (label !== null) {
      args.set(DownloadsSceneAction.KEY_LABEL, label);
    }
    const sh: DownloadLabelsSceneShell | null = this.shell;
    if (sh !== null && sh.hasStageHost()) {
      sh.startScene(new Announcer('DownloadsScene').setArgs(args));
      return;
    }
    if (this.host !== null) {
      this.host.startSceneByName('DownloadsScene', args, null, 0);
    }
  }

  private navigateBack(): void {
    const sh: DownloadLabelsSceneShell | null = this.shell;
    if (sh !== null) {
      sh.getLogic().onNavigationClick();
    } else if (this.host !== null) {
      this.host.goBack();
    }
  }

  @Builder
  private deleteIconFor(index: number): void {
    Column() {
      VDeleteX24({
        iconSize: ThemeDimens.ICON_SIZE_STANDARD,
        fillColor: this.palette().drawablePrimary
      })
    }
    .width(ThemeDimens.ICON_SIZE_STANDARD)
    .height(ThemeDimens.ICON_SIZE_STANDARD)
    .onClick((): void => {
      this.openDeletePanel(index);
    })
  }

  @Builder
  private actionIconsFor(row: LabelRowEntry): void {
    Row({ space: 0 }) {
      Stack({ alignContent: Alignment.Center }) {
        Shape() {
          Path()
            .commands(PathData.pd_pencil)
            .fill(this.palette().drawablePrimary)
            .stroke(Color.Transparent)
            .strokeWidth(0)
        }
        .viewPort({ x: 0, y: 0, width: '24px', height: '24px' })
        .width(20)
        .height(20)
        .antiAlias(true)
      }
      .width(36)
      .height(ThemeDimens.TOUCH_TARGET_MIN)
      .onClick((): void => {
        this.openRenamePanel(row.index);
      })

      Stack({ alignContent: Alignment.Center }) {
        Shape() {
          Path()
            .commands(PD_CHEVRON_UP)
            .fill(row.index > 0 ? this.palette().drawablePrimary : this.palette().textDisabled)
            .stroke(Color.Transparent)
            .strokeWidth(0)
        }
        .viewPort({ x: 0, y: 0, width: '24px', height: '24px' })
        .width(20)
        .height(20)
        .antiAlias(true)
      }
      .width(32)
      .height(ThemeDimens.TOUCH_TARGET_MIN)
      .enabled(row.index > 0)
      .onClick((): void => {
        void this.moveRow(row.index, row.index - 1);
      })

      Stack({ alignContent: Alignment.Center }) {
        Shape() {
          Path()
            .commands(PD_CHEVRON_DOWN)
            .fill(row.index < this.rows.length - 1 ? this.palette().drawablePrimary : this.palette().textDisabled)
            .stroke(Color.Transparent)
            .strokeWidth(0)
        }
        .viewPort({ x: 0, y: 0, width: '24px', height: '24px' })
        .width(20)
        .height(20)
        .antiAlias(true)
      }
      .width(32)
      .height(ThemeDimens.TOUCH_TARGET_MIN)
      .enabled(row.index < this.rows.length - 1)
      .onClick((): void => {
        void this.moveRow(row.index, row.index + 1);
      })
    }
    .padding({ right: ThemeDimens.SPACING_XS })
    .alignItems(VerticalAlign.Center)
  }

  @Builder
  private listSlot(): void {
    if (this.showTip) {
      Column({ space: 12 }) {
        BigLabel({
          iconSize: 120,
          fillColor: this.palette().drawableSecondary
        })
        Text($r('app.string.no_download_label'))
          .fontSize(ThemeTypography.TEXT_LITTLE_SMALL)
          .fontColor(this.palette().textSecondary)
          .textAlign(TextAlign.Center)
      }
      .width('100%')
      .height('100%')
      .padding(24)
      .justifyContent(FlexAlign.Center)
    } else {
      List({ space: 0 }) {
        ForEach(this.rows, (row: LabelRowEntry) => {
          ListItem() {
            DownloadLabelItemLayout({
              label: row.label,
              textColor: this.palette().textPrimary,
              containerColor: this.palette().cardWhiteSurface,
              dividerColor: this.palette().divider,
              showDefaultDragIcon: false,
              onLabelClick: (): void => {
                this.openDownloadsForLabel(row.label);
              },
              deleteIconBuilder: (): void => {
                this.deleteIconFor(row.index);
              },
              trailingActionsBuilder: (): void => {
                this.actionIconsFor(row);
              }
            })
          }
        }, (row: LabelRowEntry) => `${row.id}_${row.index}_${row.label}`)
      }
      .width('100%')
      .height('100%')
    }
  }

  @Builder
  private addDialogOverlay(): void {
    Stack({ alignContent: Alignment.Center }) {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor(this.palette().dialogScrim)
        .onClick((): void => {
          this.addOpen = false;
          this.errorRes = null;
        })

      Column() {
        Text($r('app.string.new_label_title'))
          .fontSize(ThemeTypography.DIALOG_TITLE)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.palette().textPrimary)
          .width('100%')
          .padding({ left: ThemeDimens.DIALOG_PADDING_H, right: ThemeDimens.DIALOG_PADDING_H, top: 20, bottom: 12 })

        Column({ space: 8 }) {
          Column() {
            TextInput({ placeholder: $r('app.string.download_labels'), text: this.newLabelText })
              .width('100%')
              .height(44)
              .fontSize(ThemeTypography.PREF_TITLE)
              .fontColor(this.palette().textPrimary)
              .placeholderColor(this.palette().textHint)
              .caretColor(this.palette().controlActivated)
              .backgroundColor(Color.Transparent)
              .borderRadius(0)
              .padding({ left: 0, right: 0 })
              .onFocus((): void => {
                this.newLabelFocused = true;
              })
              .onBlur((): void => {
                this.newLabelFocused = false;
              })
              .onChange((val: string): void => {
                this.newLabelText = val;
                this.errorRes = null;
              })
              .onSubmit((): void => {
                void this.submitAdd();
              })

            Row()
              .width('100%')
              .height(this.newLabelFocused ? 2 : ThemeDimens.DIVIDER_HEIGHT)
              .backgroundColor(this.errorRes !== null
                ? this.palette().errorColor
                : (this.newLabelFocused ? this.palette().colorAccent : this.palette().divider))
          }
          .width('100%')

          if (this.errorRes !== null) {
            Text(this.errorRes)
              .fontSize(ThemeTypography.TEXT_SUPER_SMALL)
              .fontColor(this.palette().errorColor)
              .width('100%')
          }
        }
        .width('100%')
        .padding({ left: ThemeDimens.DIALOG_PADDING_H, right: ThemeDimens.DIALOG_PADDING_H, bottom: 8 })

        Row({ space: 8 }) {
          Button({ type: ButtonType.Normal }) {
            Text($r('app.string.cancel'))
              .fontSize(ThemeTypography.BUTTON)
              .fontWeight(FontWeight.Medium)
              .fontColor(this.palette().textSecondary)
              .textCase(TextCase.UpperCase)
          }
          .backgroundColor(Color.Transparent)
          .borderRadius(ThemeRadius.BUTTON)
          .constraintSize({ minHeight: ThemeDimens.DIALOG_ACTION_MIN_HEIGHT, minWidth: 64 })
          .padding({ left: 12, right: 12 })
          .onClick((): void => {
            this.addOpen = false;
            this.errorRes = null;
          })

          Button({ type: ButtonType.Normal }) {
            Text($r('app.string.yes'))
              .fontSize(ThemeTypography.BUTTON)
              .fontWeight(FontWeight.Medium)
              .fontColor(this.palette().colorPrimary)
              .textCase(TextCase.UpperCase)
          }
          .backgroundColor(Color.Transparent)
          .borderRadius(ThemeRadius.BUTTON)
          .constraintSize({ minHeight: ThemeDimens.DIALOG_ACTION_MIN_HEIGHT, minWidth: 64 })
          .padding({ left: 12, right: 12 })
          .onClick((): void => {
            void this.submitAdd();
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
      .onClick((): void => {
      })
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  private renameDialogOverlay(): void {
    Stack({ alignContent: Alignment.Center }) {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor(this.palette().dialogScrim)
        .onClick((): void => {
          this.renameIndex = -1;
          this.renameDialogSpec = null;
          this.errorRes = null;
        })

      Column() {
        Text($r('app.string.rename_label_title'))
          .fontSize(ThemeTypography.DIALOG_TITLE)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.palette().textPrimary)
          .width('100%')
          .padding({ left: ThemeDimens.DIALOG_PADDING_H, right: ThemeDimens.DIALOG_PADDING_H, top: 20, bottom: 12 })

        Column({ space: 8 }) {
          Column() {
            TextInput({ placeholder: $r('app.string.download_labels'), text: this.renameText })
              .width('100%')
              .height(44)
              .fontSize(ThemeTypography.PREF_TITLE)
              .fontColor(this.palette().textPrimary)
              .placeholderColor(this.palette().textHint)
              .caretColor(this.palette().controlActivated)
              .backgroundColor(Color.Transparent)
              .borderRadius(0)
              .padding({ left: 0, right: 0 })
              .onFocus((): void => {
                this.renameFocused = true;
              })
              .onBlur((): void => {
                this.renameFocused = false;
              })
              .onChange((val: string): void => {
                this.renameText = val;
                this.errorRes = null;
              })
              .onSubmit((): void => {
                void this.submitRename();
              })

            Row()
              .width('100%')
              .height(this.renameFocused ? 2 : ThemeDimens.DIVIDER_HEIGHT)
              .backgroundColor(this.errorRes !== null
                ? this.palette().errorColor
                : (this.renameFocused ? this.palette().colorAccent : this.palette().divider))
          }
          .width('100%')

          if (this.errorRes !== null) {
            Text(this.errorRes)
              .fontSize(ThemeTypography.TEXT_SUPER_SMALL)
              .fontColor(this.palette().errorColor)
              .width('100%')
          }
        }
        .width('100%')
        .padding({ left: ThemeDimens.DIALOG_PADDING_H, right: ThemeDimens.DIALOG_PADDING_H, bottom: 8 })

        Row({ space: 8 }) {
          Button({ type: ButtonType.Normal }) {
            Text($r('app.string.cancel'))
              .fontSize(ThemeTypography.BUTTON)
              .fontWeight(FontWeight.Medium)
              .fontColor(this.palette().textSecondary)
              .textCase(TextCase.UpperCase)
          }
          .backgroundColor(Color.Transparent)
          .borderRadius(ThemeRadius.BUTTON)
          .constraintSize({ minHeight: ThemeDimens.DIALOG_ACTION_MIN_HEIGHT, minWidth: 64 })
          .padding({ left: 12, right: 12 })
          .onClick((): void => {
            this.renameIndex = -1;
            this.renameDialogSpec = null;
            this.errorRes = null;
          })

          Button({ type: ButtonType.Normal }) {
            Text($r('app.string.ok'))
              .fontSize(ThemeTypography.BUTTON)
              .fontWeight(FontWeight.Medium)
              .fontColor(this.palette().colorPrimary)
              .textCase(TextCase.UpperCase)
          }
          .backgroundColor(Color.Transparent)
          .borderRadius(ThemeRadius.BUTTON)
          .constraintSize({ minHeight: ThemeDimens.DIALOG_ACTION_MIN_HEIGHT, minWidth: 64 })
          .padding({ left: 12, right: 12 })
          .onClick((): void => {
            void this.submitRename();
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
      .onClick((): void => {
      })
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  private deleteDialogOverlay(): void {
    Stack({ alignContent: Alignment.Center }) {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor(this.palette().dialogScrim)
        .onClick((): void => {
          this.cancelDeleteLabel();
        })

      Column() {
        Text($r('app.string.delete_label_title'))
          .fontSize(ThemeTypography.DIALOG_TITLE)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.palette().textPrimary)
          .width('100%')
          .padding({ left: ThemeDimens.DIALOG_PADDING_H, right: ThemeDimens.DIALOG_PADDING_H, top: 20, bottom: 12 })

        Text(this.deleteMessage)
          .fontSize(ThemeTypography.PREF_TITLE)
          .fontColor(this.palette().textSecondary)
          .width('100%')
          .padding({ left: ThemeDimens.DIALOG_PADDING_H, right: ThemeDimens.DIALOG_PADDING_H, top: 4, bottom: 16 })

        Row({ space: 8 }) {
          Button({ type: ButtonType.Normal }) {
            Text($r('app.string.cancel'))
              .fontSize(ThemeTypography.BUTTON)
              .fontWeight(FontWeight.Medium)
              .fontColor(this.palette().textSecondary)
              .textCase(TextCase.UpperCase)
          }
          .backgroundColor(Color.Transparent)
          .borderRadius(ThemeRadius.BUTTON)
          .constraintSize({ minHeight: ThemeDimens.DIALOG_ACTION_MIN_HEIGHT, minWidth: 64 })
          .padding({ left: 12, right: 12 })
          .onClick((): void => {
            this.cancelDeleteLabel();
          })

          Button({ type: ButtonType.Normal }) {
            Text($r('app.string.delete'))
              .fontSize(ThemeTypography.BUTTON)
              .fontWeight(FontWeight.Medium)
              .fontColor(this.palette().colorPrimary)
              .textCase(TextCase.UpperCase)
          }
          .backgroundColor(Color.Transparent)
          .borderRadius(ThemeRadius.BUTTON)
          .constraintSize({ minHeight: ThemeDimens.DIALOG_ACTION_MIN_HEIGHT, minWidth: 64 })
          .padding({ left: 12, right: 12 })
          .onClick((): void => {
            void this.confirmDeleteLabel();
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
      .onClick((): void => {
      })
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  private buildContent(): void {
    Stack({ alignContent: Alignment.TopStart }) {
      Column() {
        // 56vp Material Toolbar
        Row() {
          Stack({ alignContent: Alignment.Center }) {
            Shape() {
              Path()
                .commands(PathData.pd_arrow_left)
                .fill(this.palette().toolbarIconColor)
                .stroke(Color.Transparent)
                .strokeWidth(0)
            }
            .viewPort({ x: 0, y: 0, width: '24px', height: '24px' })
            .width(ThemeDimens.ICON_SIZE_STANDARD)
            .height(ThemeDimens.ICON_SIZE_STANDARD)
            .antiAlias(true)
          }
          .width(ThemeDimens.TOUCH_TARGET_MIN)
          .height(ThemeDimens.TOUCH_TARGET_MIN)
          .onClick((): void => {
            this.navigateBack();
          })

          Text($r('app.string.download_labels'))
            .fontSize(ThemeTypography.TOOLBAR_TITLE)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.palette().toolbarTitleColor)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)
            .margin({ left: ThemeDimens.SPACING })

          Button({ type: ButtonType.Normal }) {
            Text($r('app.string.default_download_label_name'))
              .fontSize(ThemeTypography.BUTTON)
              .fontWeight(FontWeight.Medium)
              .fontColor(this.palette().toolbarTitleColor)
              .textCase(TextCase.UpperCase)
          }
          .height(ThemeDimens.DIALOG_ACTION_MIN_HEIGHT)
          .padding({ left: 10, right: 10 })
          .borderRadius(ThemeRadius.BUTTON)
          .backgroundColor(Color.Transparent)
          .onClick((): void => {
            this.openDownloadsForLabel(null);
          })

          Stack({ alignContent: Alignment.Center }) {
            Shape() {
              Path()
                .commands(PathData.pd_plus)
                .fill(this.palette().toolbarIconColor)
                .stroke(Color.Transparent)
                .strokeWidth(0)
            }
            .viewPort({ x: 0, y: 0, width: '24px', height: '24px' })
            .width(ThemeDimens.ICON_SIZE_STANDARD)
            .height(ThemeDimens.ICON_SIZE_STANDARD)
            .antiAlias(true)
          }
          .width(ThemeDimens.TOUCH_TARGET_MIN)
          .height(ThemeDimens.TOUCH_TARGET_MIN)
          .onClick((): void => {
            if (this.addOpen) {
              this.addOpen = false;
            } else {
              this.openAddPanel();
            }
          })
        }
        .width('100%')
        .height(ThemeDimens.TOOLBAR_HEIGHT)
        .padding({ left: ThemeDimens.SPACING_XS, right: ThemeDimens.SPACING_XS })
        .backgroundColor(this.palette().toolbarColor)
        .shadow(ThemeElevation.toolbar())

        if (this.errorText.length > 0) {
          Text(this.errorText)
            .fontSize(ThemeTypography.TEXT_SUPER_SMALL)
            .fontColor(this.palette().errorColor)
            .width('100%')
            .padding({ left: ThemeDimens.KEYLINE_MARGIN, right: ThemeDimens.KEYLINE_MARGIN, top: 8, bottom: 8 })
            .backgroundColor(this.palette().errorBannerBg)
        }

        Column() {
          SceneLabelListLayout({
            tip: '',
            progressVisibility: Visibility.None,
            recyclerViewBuilder: (): void => {
              this.listSlot();
            }
          })
        }
        .width('100%')
        .layoutWeight(1)
      }
      .width('100%')
      .height('100%')

      if (this.addOpen) {
        this.addDialogOverlay()
      }

      if (this.renameIndex >= 0 && this.renameIndex < this.rows.length) {
        this.renameDialogOverlay()
      }

      if (this.deleteIndex >= 0 && this.deleteIndex < this.rows.length) {
        this.deleteDialogOverlay()
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.palette().windowBackground)
  }

  build() {
    this.buildContent();
  }
}
