/*
 * SubscriptionsSceneView: Material Design UI aligned with scene_label_list.xml,
 * item_subscription.xml, subscription_draw.xml & SubscriptionsScene.java.
 */
import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import {
  ThemeDimens,
  ThemeElevation,
  ThemePalette,
  ThemeRadius,
  ThemeTokens,
  ThemeTypography
} from '../../../common/theme/ThemeTokens';
import { PathData } from '../../drawable/PathData';
import { EhApplication } from '../../ehviewer/EhApplication';
import { GetText } from '../../ehviewer/GetText';
import { Settings } from '../../ehviewer/Settings';
import { EhEngine, HttpCaller } from '../../ehviewer/client/EhEngine';
import { EhUrl } from '../../ehviewer/client/EhUrl';
import { TagPushParam, UserTagList } from '../../ehviewer/client/data/UserTag';
import {
  ICON_VISIBILITY,
  ICON_VISIBILITY_OFF,
  SubscriptionDeleteDialogSpec,
  SubscriptionRowViewModel,
  SubscriptionsScene,
  VIEW_LIST
} from '../../ehviewer/ui/scene/gallery/list/SubscriptionsScene';
import { SubscriptionsSceneShell } from '../../ehviewer/ui/scene/gallery/list/SubscriptionsSceneShell';
import { OkHttpCallerAdapter } from '../../AppWiring';
import { BigSearch } from '../drawable/big_search';
import { IcBaselineVisibility24 } from '../drawable/ic_baseline_visibility_24';
import { IcBaselineVisibilityOff24 } from '../drawable/ic_baseline_visibility_off_24';
import { VDeleteX24 } from '../drawable/v_delete_x24';
import { VRefreshDarkX24 } from '../drawable/v_refresh_dark_x24';
import { SubscriptionItemLayout } from '../layout/item_subscription';
import { MainPageHost } from '../MainPageHost';

const DOMAIN: number = 0x0000;
const TAG: string = 'SubscriptionsSceneView';

class SubscriptionRowEntry {
  readonly index: number;
  readonly id: number;
  readonly label: string;
  readonly stateIcon: string | null;
  readonly tagName: string;

  constructor(index: number, vm: SubscriptionRowViewModel) {
    this.index = index;
    this.id = vm.id;
    this.label = vm.label;
    this.stateIcon = vm.stateIcon;
    this.tagName = vm.tagName;
  }
}

@Component
export struct SubscriptionsSceneView {
  shell: SubscriptionsSceneShell | null = null;
  host: MainPageHost | null = null;
  @Prop themeId: number = -1;

  @State rows: SubscriptionRowEntry[] = [];
  @State loading: boolean = false;
  @State loggedIn: boolean = false;
  @State errorText: string = '';
  @State addOpen: boolean = false;
  @State newTagName: string = '';
  @State tagInputFocused: boolean = false;
  @State watchSelected: boolean = true;
  @State deleteIndex: number = -1;
  @State deleteTagName: string = '';

  private hostContext: common.Context | undefined = undefined;
  private readonly subscriptionRadioGroup: string = 'subscription_mode_group';

  private palette(): ThemePalette {
    return this.themeId >= 0 ? ThemeTokens.of(this.themeId) : ThemeTokens.current();
  }

  aboutToAppear(): void {
    const ctx: common.Context | undefined = this.getUIContext().getHostContext();
    this.hostContext = ctx;
    if (ctx !== undefined && !GetText.isInitialized()) {
      GetText.initialize(ctx);
    }
    const sh: SubscriptionsSceneShell | null = this.shell;
    this.loggedIn = Settings.isLogin();
    if (sh === null) {
      return;
    }
    const logic: SubscriptionsScene = sh.getLogic();
    logic.onCreate();
    this.syncFromLogic();
    if (this.loggedIn && logic.getItemCount() === 0) {
      void this.refreshFromNetwork();
    }
  }

  aboutToDisappear(): void {
    const sh: SubscriptionsSceneShell | null = this.shell;
    if (sh !== null) {
      sh.getLogic().onDestroy();
    }
  }

  private formatDeleteMessage(tagName: string): string {
    const formatted: string = GetText.getStringFormat('delete_quick_search_message', [tagName]);
    if (formatted.length > 0) {
      return formatted;
    }
    const ctx: common.Context | undefined = this.hostContext;
    if (ctx !== undefined) {
      try {
        const tmpl: string = ctx.resourceManager.getStringByNameSync('delete_quick_search_message');
        if (tmpl.length > 0) {
          return tmpl.replace('%s', tagName);
        }
      } catch (e) {
        hilog.warn(DOMAIN, TAG, 'formatDeleteMessage failed: %{public}s', (e as Error).message);
      }
    }
    return tagName;
  }

  private resolveCaller(): HttpCaller | null {
    try {
      const ctx: common.Context = this.getUIContext().getHostContext() as common.Context;
      return new OkHttpCallerAdapter(EhApplication.getOkHttpClient(ctx));
    } catch (e) {
      const msg: string = (e as Error).message !== undefined ? (e as Error).message : String(e);
      hilog.warn(DOMAIN, TAG, 'resolveCaller failed: %{public}s', msg);
      return null;
    }
  }

  private syncFromLogic(): void {
    const sh: SubscriptionsSceneShell | null = this.shell;
    if (sh === null) {
      this.rows = [];
      return;
    }
    const logic: SubscriptionsScene = sh.getLogic();
    logic.updateView();
    const count: number = logic.getItemCount();
    const next: SubscriptionRowEntry[] = [];
    for (let i = 0; i < count; i++) {
      const vm: SubscriptionRowViewModel | null = logic.bindItem(i);
      if (vm !== null) {
        next.push(new SubscriptionRowEntry(i, vm));
      }
    }
    this.rows = next;
    const err: Error | null = logic.getLastError();
    if (err !== null && err.message !== undefined && err.message.length > 0) {
      this.errorText = err.message;
    }
  }

  private async refreshFromNetwork(): Promise<void> {
    const sh: SubscriptionsSceneShell | null = this.shell;
    this.loggedIn = Settings.isLogin();
    if (sh === null || !this.loggedIn) {
      return;
    }
    const caller: HttpCaller | null = this.resolveCaller();
    if (caller === null) {
      return;
    }
    this.loading = true;
    this.errorText = '';
    try {
      const list: UserTagList | null = await EhEngine.getWatchedList(null, caller, EhUrl.getMyTag());
      sh.getLogic().applyResult(list);
      this.syncFromLogic();
    } catch (e) {
      const msg: string = (e as Error).message !== undefined ? (e as Error).message : String(e);
      this.errorText = msg;
      hilog.error(DOMAIN, TAG, 'getWatchedList failed: %{public}s', msg);
    } finally {
      this.loading = false;
    }
  }

  private async submitAddTag(): Promise<void> {
    const sh: SubscriptionsSceneShell | null = this.shell;
    const tag: string = this.newTagName.trim();
    if (sh === null || tag.length === 0) {
      return;
    }
    const caller: HttpCaller | null = this.resolveCaller();
    if (caller === null) {
      return;
    }
    const param: TagPushParam = new TagPushParam();
    param.userTagAction = 'add';
    param.tagNameNew = tag;
    param.tagWatchNew = this.watchSelected ? 'on' : null;
    param.tagHiddenNew = this.watchSelected ? null : 'on';
    param.tagColorNew = '';
    this.loading = true;
    this.errorText = '';
    try {
      const res: UserTagList | null = await EhEngine.addTag(null, caller, EhUrl.getMyTag(), param);
      if (res !== null) {
        sh.getLogic().applyResult(res);
        this.newTagName = '';
        this.addOpen = false;
        this.syncFromLogic();
      } else {
        this.errorText = tag;
      }
    } catch (e) {
      const msg: string = (e as Error).message !== undefined ? (e as Error).message : String(e);
      this.errorText = msg;
      hilog.error(DOMAIN, TAG, 'addTag failed: %{public}s', msg);
    } finally {
      this.loading = false;
    }
  }

  private requestDeleteRow(index: number): void {
    const sh: SubscriptionsSceneShell | null = this.shell;
    if (sh === null) {
      return;
    }
    const spec: SubscriptionDeleteDialogSpec | null = sh.getLogic().buildDeleteDialog(index);
    if (spec === null) {
      return;
    }
    this.deleteIndex = index;
    this.deleteTagName = spec.tagName;
  }

  private async confirmDelete(): Promise<void> {
    const sh: SubscriptionsSceneShell | null = this.shell;
    if (sh === null) {
      this.deleteIndex = -1;
      return;
    }
    this.loading = true;
    this.errorText = '';
    try {
      await sh.getLogic().deleteTag();
      this.deleteIndex = -1;
      this.deleteTagName = '';
      this.syncFromLogic();
    } catch (e) {
      const msg: string = (e as Error).message !== undefined ? (e as Error).message : String(e);
      this.errorText = msg;
      hilog.error(DOMAIN, TAG, 'deleteTag failed: %{public}s', msg);
    } finally {
      this.loading = false;
    }
  }

  private navigateBack(): void {
    const sh: SubscriptionsSceneShell | null = this.shell;
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
      this.requestDeleteRow(index);
    })
  }

  @Builder
  private stateIconFor(iconName: string | null): void {
    if (iconName === ICON_VISIBILITY) {
      IcBaselineVisibility24({
        iconSize: ThemeDimens.ICON_SIZE_STANDARD,
        fillColor: this.palette().drawablePrimary
      })
    } else if (iconName === ICON_VISIBILITY_OFF) {
      IcBaselineVisibilityOff24({
        iconSize: ThemeDimens.ICON_SIZE_STANDARD,
        fillColor: this.palette().drawablePrimary
      })
    } else {
      Row().width(0).height(0)
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
        })

      Column() {
        Text($r('app.string.add_tag_dialog_title'))
          .fontSize(ThemeTypography.DIALOG_TITLE)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.palette().textPrimary)
          .width('100%')
          .padding({ left: ThemeDimens.DIALOG_PADDING_H, right: ThemeDimens.DIALOG_PADDING_H, top: 20, bottom: 12 })

        Column() {
          TextInput({ placeholder: $r('app.string.tag_title'), text: this.newTagName })
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
              this.tagInputFocused = true;
            })
            .onBlur((): void => {
              this.tagInputFocused = false;
            })
            .onChange((val: string): void => {
              this.newTagName = val;
            })
            .onSubmit((): void => {
              void this.submitAddTag();
            })

          Row()
            .width('100%')
            .height(this.tagInputFocused ? 2 : ThemeDimens.DIVIDER_HEIGHT)
            .backgroundColor(this.tagInputFocused ? this.palette().colorAccent : this.palette().divider)
        }
        .width('100%')
        .padding({ left: ThemeDimens.DIALOG_PADDING_H, right: ThemeDimens.DIALOG_PADDING_H, bottom: 8 })

        Row({ space: ThemeDimens.SPACING_MD }) {
          Radio({ value: 'watched', group: this.subscriptionRadioGroup })
            .checked(this.watchSelected)
            .radioStyle({ checkedBackgroundColor: this.palette().controlActivated })
            .hitTestBehavior(HitTestMode.None)

          Text($r('app.string.subscription_watched'))
            .fontSize(ThemeTypography.PREF_TITLE)
            .fontColor(this.palette().textPrimary)
            .layoutWeight(1)
        }
        .width('100%')
        .constraintSize({ minHeight: 44 })
        .padding({ left: 20, right: ThemeDimens.DIALOG_PADDING_H, top: 6, bottom: 6 })
        .onClick((): void => {
          this.watchSelected = true;
        })

        Row({ space: ThemeDimens.SPACING_MD }) {
          Radio({ value: 'hidden', group: this.subscriptionRadioGroup })
            .checked(!this.watchSelected)
            .radioStyle({ checkedBackgroundColor: this.palette().controlActivated })
            .hitTestBehavior(HitTestMode.None)

          Text($r('app.string.subscription_hidden'))
            .fontSize(ThemeTypography.PREF_TITLE)
            .fontColor(this.palette().textPrimary)
            .layoutWeight(1)
        }
        .width('100%')
        .constraintSize({ minHeight: 44 })
        .padding({ left: 20, right: ThemeDimens.DIALOG_PADDING_H, top: 6, bottom: 6 })
        .onClick((): void => {
          this.watchSelected = false;
        })

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
            void this.submitAddTag();
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
          this.deleteIndex = -1;
          this.deleteTagName = '';
        })

      Column() {
        Text($r('app.string.delete_subscription_title'))
          .fontSize(ThemeTypography.DIALOG_TITLE)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.palette().textPrimary)
          .width('100%')
          .padding({ left: ThemeDimens.DIALOG_PADDING_H, right: ThemeDimens.DIALOG_PADDING_H, top: 20, bottom: 12 })

        Text(this.formatDeleteMessage(this.deleteTagName))
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
            this.deleteIndex = -1;
            this.deleteTagName = '';
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
            void this.confirmDelete();
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

          Text($r('app.string.tag_title'))
            .fontSize(ThemeTypography.TOOLBAR_TITLE)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.palette().toolbarTitleColor)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)
            .margin({ left: ThemeDimens.SPACING })

          if (this.loggedIn) {
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
              this.addOpen = true;
            })
          }

          Stack({ alignContent: Alignment.Center }) {
            VRefreshDarkX24({
              iconSize: ThemeDimens.ICON_SIZE_STANDARD,
              fillColor: this.palette().toolbarIconColor
            })
          }
          .width(ThemeDimens.TOUCH_TARGET_MIN)
          .height(ThemeDimens.TOUCH_TARGET_MIN)
          .onClick((): void => {
            void this.refreshFromNetwork();
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

        if (!this.loggedIn) {
          Column({ space: 8 }) {
            Text($r('app.string.settings_eh_identity_cookies_tourist'))
              .fontSize(ThemeTypography.TEXT_SUPER_LARGE)
              .fontColor(this.palette().textSecondary)
              .textAlign(TextAlign.Center)
          }
          .width('100%')
          .layoutWeight(1)
          .padding(24)
          .justifyContent(FlexAlign.Center)
        } else if (this.loading && this.rows.length === 0) {
          Column({ space: 12 }) {
            LoadingProgress()
              .width(ThemeDimens.ICON_SIZE_LARGE)
              .height(ThemeDimens.ICON_SIZE_LARGE)
              .color(this.palette().progressColor)
            Text($r('app.string.loading'))
              .fontSize(ThemeTypography.TEXT_SMALL)
              .fontColor(this.palette().textSecondary)
          }
          .width('100%')
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
        } else if (this.shell !== null && this.shell.getLogic().updateView() !== VIEW_LIST) {
          Column({ space: 12 }) {
            BigSearch({
              iconSize: 120,
              fillColor: this.palette().drawableSecondary
            })
            Text($r('app.string.empty_subscription'))
              .fontSize(ThemeTypography.TEXT_LITTLE_SMALL)
              .fontColor(this.palette().textSecondary)
              .textAlign(TextAlign.Center)
            Text($r('app.string.subscription_tip'))
              .fontSize(ThemeTypography.TEXT_SMALL)
              .fontColor(this.palette().textSecondary)
              .textAlign(TextAlign.Center)
          }
          .width('100%')
          .layoutWeight(1)
          .padding(24)
          .justifyContent(FlexAlign.Center)
        } else {
          List({ space: 0 }) {
            ForEach(this.rows, (row: SubscriptionRowEntry) => {
              ListItem() {
                SubscriptionItemLayout({
                  label: row.label,
                  textColor: this.palette().textPrimary,
                  containerColor: this.palette().cardWhiteSurface,
                  dividerColor: this.palette().divider,
                  deleteIconBuilder: (): void => {
                    this.deleteIconFor(row.index);
                  },
                  dragIconBuilder: (): void => {
                    this.stateIconFor(row.stateIcon);
                  }
                })
              }
            }, (row: SubscriptionRowEntry) => `${row.id}_${row.tagName}_${row.index}`)
          }
          .width('100%')
          .layoutWeight(1)
          .padding({ left: ThemeDimens.KEYLINE_MARGIN, right: ThemeDimens.KEYLINE_MARGIN, top: ThemeDimens.KEYLINE_MARGIN, bottom: ThemeDimens.KEYLINE_MARGIN })
        }
      }
      .width('100%')
      .height('100%')

      if (this.addOpen) {
        this.addDialogOverlay()
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
