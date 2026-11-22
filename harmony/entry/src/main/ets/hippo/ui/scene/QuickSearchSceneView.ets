/*
 * QuickSearchSceneView: Material Design UI aligned with scene_label_list.xml,
 * item_quick_search.xml & QuickSearchScene.java.
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
import { EhDB } from '../../ehviewer/EhDB';
import { GetText } from '../../ehviewer/GetText';
import { QuickSearch } from '../../ehviewer/dao/QuickSearch';
import { ListUrlBuilder } from '../../ehviewer/client/data/ListUrlBuilder';
import {
  QuickSearchItem,
  QuickSearchScene,
  QuickSearchStore,
  QuickSearchView
} from '../../ehviewer/ui/scene/gallery/list/QuickSearchScene';
import { QuickSearchSceneShell } from '../../ehviewer/ui/scene/gallery/list/QuickSearchSceneShell';
import { GalleryListAction } from '../../ehviewer/ui/scene/gallery/list/GalleryListScene';
import { Announcer } from '../../scene/Announcer';
import { SceneArgs } from '../../scene/SceneTypes';
import { BigSearch } from '../drawable/big_search';
import { VDeleteX24 } from '../drawable/v_delete_x24';
import { VRefreshDarkX24 } from '../drawable/v_refresh_dark_x24';
import { ItemQuickSearchLayout } from '../layout/item_quick_search';
import { SwipeHandlerShadow } from '../layout/support/SwipeHandlerShadow';
import { MainPageHost } from '../MainPageHost';

const DOMAIN: number = 0x0000;
const TAG: string = 'QuickSearchSceneView';
const PD_CHEVRON_UP: string = 'M7.41,15.41L12,10.83L16.59,15.41L18,14L12,8L6,14Z';
const PD_CHEVRON_DOWN: string = 'M7.41,8.59L12,13.17L16.59,8.59L18,10L12,16L6,10Z';

class QuickSearchEntry implements QuickSearchItem {
  readonly name: string;
  readonly summary: string;
  readonly entity: QuickSearch;
  readonly key: string;

  constructor(entity: QuickSearch, index: number) {
    this.entity = entity;
    const rawName: string | null = entity.getName();
    const rawKeyword: string | null = entity.getKeyword();
    this.name = rawName !== null && rawName.length > 0
      ? rawName
      : (rawKeyword !== null && rawKeyword.length > 0 ? rawKeyword : `#${index + 1}`);
    this.summary = rawKeyword !== null ? rawKeyword : '';
    const idVal: number | null = entity.getId();
    this.key = idVal !== null ? `${idVal}_${entity.getTime()}` : `idx_${index}_${this.name}`;
  }
}

class DbQuickSearchStore implements QuickSearchStore {
  private readonly entries: QuickSearchEntry[];
  private readonly onError: (msg: string) => void;

  constructor(entries: QuickSearchEntry[], onError: (msg: string) => void) {
    this.entries = entries;
    this.onError = onError;
  }

  deleteQuickSearch(item: QuickSearchItem): void {
    const entry: QuickSearchEntry = item as QuickSearchEntry;
    EhDB.deleteQuickSearch(entry.entity).catch((e: Error): void => {
      const msg: string = e.message !== undefined ? e.message : String(e);
      hilog.error(DOMAIN, TAG, 'deleteQuickSearch failed: %{public}s', msg);
      this.onError(msg);
    });
  }

  moveQuickSearch(from: number, to: number): void {
    EhDB.moveQuickSearch(from, to).catch((e: Error): void => {
      const msg: string = e.message !== undefined ? e.message : String(e);
      hilog.error(DOMAIN, TAG, 'moveQuickSearch failed: %{public}s', msg);
      this.onError(msg);
    });
  }

  listQuickSearch(): QuickSearchItem[] {
    return this.entries;
  }
}

@Component
export struct QuickSearchSceneView {
  shell: QuickSearchSceneShell | null = null;
  host: MainPageHost | null = null;
  @Prop themeId: number = -1;

  @State entries: QuickSearchEntry[] = [];
  @State loading: boolean = false;
  @State errorText: string = '';
  @State addOpen: boolean = false;
  @State newName: string = '';
  @State newKeyword: string = '';
  @State nameFocused: boolean = false;
  @State keywordFocused: boolean = false;
  @State deleteIndex: number = -1;
  @State validationErrorRes: Resource | null = null;

  private hostContext: common.Context | undefined = undefined;

  private palette(): ThemePalette {
    return this.themeId >= 0 ? ThemeTokens.of(this.themeId) : ThemeTokens.current();
  }

  aboutToAppear(): void {
    const ctx: common.Context | undefined = this.getUIContext().getHostContext();
    this.hostContext = ctx;
    if (ctx !== undefined && !GetText.isInitialized()) {
      GetText.initialize(ctx);
    }
    void this.loadQuickSearches();
  }

  private formatDeleteMessage(name: string): string {
    const formatted: string = GetText.getStringFormat('delete_quick_search_message', [name]);
    if (formatted.length > 0) {
      return formatted;
    }
    const ctx: common.Context | undefined = this.hostContext;
    if (ctx !== undefined) {
      try {
        const tmpl: string = ctx.resourceManager.getStringByNameSync('delete_quick_search_message');
        if (tmpl.length > 0) {
          return tmpl.replace('%s', name);
        }
      } catch (e) {
        hilog.warn(DOMAIN, TAG, 'formatDeleteMessage failed: %{public}s', (e as Error).message);
      }
    }
    return name;
  }

  private async loadQuickSearches(): Promise<void> {
    this.loading = true;
    this.errorText = '';
    try {
      const list: QuickSearch[] = await EhDB.getAllQuickSearch();
      const mapped: QuickSearchEntry[] = [];
      for (let i = 0; i < list.length; i++) {
        mapped.push(new QuickSearchEntry(list[i], i));
      }
      this.entries = mapped;
    } catch (e) {
      const msg: string = (e as Error).message !== undefined ? (e as Error).message : String(e);
      this.errorText = msg;
      hilog.error(DOMAIN, TAG, 'loadQuickSearches failed: %{public}s', msg);
    } finally {
      this.loading = false;
    }
  }

  private makeStore(): DbQuickSearchStore {
    return new DbQuickSearchStore(this.entries, (msg: string): void => {
      this.errorText = msg;
    });
  }

  private async submitAdd(): Promise<void> {
    const trimmedName: string = this.newName.trim();
    if (trimmedName.length === 0) {
      this.validationErrorRes = $r('app.string.name_is_empty');
      return;
    }
    for (let i = 0; i < this.entries.length; i++) {
      if (this.entries[i].name === trimmedName) {
        this.validationErrorRes = $r('app.string.duplicate_name');
        return;
      }
    }
    const trimmedKeyword: string = this.newKeyword.trim();
    const qs: QuickSearch = new QuickSearch();
    qs.setName(trimmedName);
    qs.setMode(ListUrlBuilder.MODE_NORMAL);
    qs.setCategory(-1);
    qs.setKeyword(trimmedKeyword.length > 0 ? trimmedKeyword : trimmedName);
    qs.setAdvanceSearch(-1);
    qs.setMinRating(-1);
    qs.setPageFrom(-1);
    qs.setPageTo(-1);
    qs.setTime(Date.now());
    try {
      await EhDB.insertQuickSearch(qs);
      this.newName = '';
      this.newKeyword = '';
      this.validationErrorRes = null;
      this.addOpen = false;
      await this.loadQuickSearches();
    } catch (e) {
      const msg: string = (e as Error).message !== undefined ? (e as Error).message : String(e);
      this.errorText = msg;
      hilog.error(DOMAIN, TAG, 'insertQuickSearch failed: %{public}s', msg);
    }
  }

  private launchQuickSearch(entry: QuickSearchEntry): void {
    const builder: ListUrlBuilder = new ListUrlBuilder();
    builder.copyFromQuickSearch(entry.entity);
    const url: string = builder.build();
    const args: SceneArgs = new Map<string, Object>();
    args.set(GalleryListAction.KEY_ACTION, GalleryListAction.LIST_URL_BUILDER);
    args.set(GalleryListAction.KEY_LIST_URL_BUILDER, url);
    const sh: QuickSearchSceneShell | null = this.shell;
    if (sh !== null && sh.hasStageHost()) {
      sh.startScene(new Announcer('GalleryListScene').setArgs(args));
      return;
    }
    if (this.host !== null) {
      this.host.startSceneByName('GalleryListScene', args, null, 0);
    }
  }

  private moveEntry(from: number, to: number): void {
    if (to < 0 || to >= this.entries.length) {
      return;
    }
    const store: DbQuickSearchStore = this.makeStore();
    const next: QuickSearchItem[] = QuickSearchScene.applyMove(this.entries, from, to, store);
    const updated: QuickSearchEntry[] = [];
    for (let i = 0; i < next.length; i++) {
      updated.push(next[i] as QuickSearchEntry);
    }
    this.entries = updated;
  }

  private confirmDeleteEntry(): void {
    if (this.deleteIndex < 0 || this.deleteIndex >= this.entries.length) {
      this.deleteIndex = -1;
      return;
    }
    const store: DbQuickSearchStore = this.makeStore();
    const next: QuickSearchItem[] = QuickSearchScene.applyDelete(this.entries, this.deleteIndex, store);
    const updated: QuickSearchEntry[] = [];
    for (let i = 0; i < next.length; i++) {
      updated.push(next[i] as QuickSearchEntry);
    }
    this.entries = updated;
    this.deleteIndex = -1;
  }

  private navigateBack(): void {
    const sh: QuickSearchSceneShell | null = this.shell;
    if (sh !== null && sh.hasStageHost()) {
      sh.finish();
    } else if (this.host !== null) {
      this.host.goBack();
    }
  }

  @Builder
  private quickSearchRow(entry: QuickSearchEntry, index: number): void {
    SwipeHandlerShadow({ containerColor: this.palette().cardWhiteSurface }) {
      Column() {
        Row() {
          Stack({ alignContent: Alignment.Center }) {
            VDeleteX24({
              iconSize: ThemeDimens.ICON_SIZE_STANDARD,
              fillColor: this.palette().drawablePrimary
            })
          }
          .width(ThemeDimens.TOUCH_TARGET_MIN)
          .height(ThemeDimens.TOUCH_TARGET_MIN)
          .padding(12)
          .onClick((): void => {
            this.deleteIndex = index;
          })

          Column({ space: 2 }) {
            Text(entry.name)
              .fontSize($r('app.float.text_little_small'))
              .fontColor(this.palette().textPrimary)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
            if (entry.summary.length > 0 && entry.summary !== entry.name) {
              Text(entry.summary)
                .fontSize(ThemeTypography.TEXT_SUPER_SMALL)
                .fontColor(this.palette().textSecondary)
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
            }
          }
          .layoutWeight(1)
          .constraintSize({ minHeight: ThemeDimens.PREF_ROW_MIN_HEIGHT })
          .padding({ left: 16, right: 8, top: 8, bottom: 8 })
          .justifyContent(FlexAlign.Center)
          .alignItems(HorizontalAlign.Start)
          .onClick((): void => {
            this.launchQuickSearch(entry);
          })

          Stack({ alignContent: Alignment.Center }) {
            Shape() {
              Path()
                .commands(PD_CHEVRON_UP)
                .fill(index > 0 ? this.palette().drawablePrimary : this.palette().textDisabled)
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
          .enabled(index > 0)
          .onClick((): void => {
            this.moveEntry(index, index - 1);
          })

          Stack({ alignContent: Alignment.Center }) {
            Shape() {
              Path()
                .commands(PD_CHEVRON_DOWN)
                .fill(index < this.entries.length - 1 ? this.palette().drawablePrimary : this.palette().textDisabled)
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
          .enabled(index < this.entries.length - 1)
          .onClick((): void => {
            this.moveEntry(index, index + 1);
          })
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)

        Divider()
          .strokeWidth(ThemeDimens.DIVIDER_HEIGHT)
          .color(this.palette().divider)
          .width('100%')
      }
      .width('100%')
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
          this.validationErrorRes = null;
        })

      Column() {
        Text($r('app.string.add_quick_search_dialog_title'))
          .fontSize(ThemeTypography.DIALOG_TITLE)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.palette().textPrimary)
          .width('100%')
          .padding({ left: ThemeDimens.DIALOG_PADDING_H, right: ThemeDimens.DIALOG_PADDING_H, top: 20, bottom: 12 })

        Column({ space: 12 }) {
          Column() {
            TextInput({ placeholder: $r('app.string.quick_search'), text: this.newName })
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
                this.nameFocused = true;
              })
              .onBlur((): void => {
                this.nameFocused = false;
              })
              .onChange((val: string): void => {
                this.newName = val;
                this.validationErrorRes = null;
              })

            Row()
              .width('100%')
              .height(this.nameFocused ? 2 : ThemeDimens.DIVIDER_HEIGHT)
              .backgroundColor(this.validationErrorRes !== null
                ? this.palette().errorColor
                : (this.nameFocused ? this.palette().colorAccent : this.palette().divider))
          }
          .width('100%')

          Column() {
            TextInput({ placeholder: $r('app.string.keyword_search'), text: this.newKeyword })
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
                this.keywordFocused = true;
              })
              .onBlur((): void => {
                this.keywordFocused = false;
              })
              .onChange((val: string): void => {
                this.newKeyword = val;
              })
              .onSubmit((): void => {
                void this.submitAdd();
              })

            Row()
              .width('100%')
              .height(this.keywordFocused ? 2 : ThemeDimens.DIVIDER_HEIGHT)
              .backgroundColor(this.keywordFocused ? this.palette().colorAccent : this.palette().divider)
          }
          .width('100%')

          if (this.validationErrorRes !== null) {
            Text(this.validationErrorRes)
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
            this.validationErrorRes = null;
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
  private deleteDialogOverlay(): void {
    Stack({ alignContent: Alignment.Center }) {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor(this.palette().dialogScrim)
        .onClick((): void => {
          this.deleteIndex = -1;
        })

      Column() {
        Text($r('app.string.delete_quick_search_title'))
          .fontSize(ThemeTypography.DIALOG_TITLE)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.palette().textPrimary)
          .width('100%')
          .padding({ left: ThemeDimens.DIALOG_PADDING_H, right: ThemeDimens.DIALOG_PADDING_H, top: 20, bottom: 12 })

        Text(this.formatDeleteMessage(this.entries[this.deleteIndex].name))
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
            this.confirmDeleteEntry();
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

          Text($r('app.string.quick_search'))
            .fontSize(ThemeTypography.TOOLBAR_TITLE)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.palette().toolbarTitleColor)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)
            .margin({ left: ThemeDimens.SPACING })

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
            this.validationErrorRes = null;
            this.addOpen = true;
          })

          Stack({ alignContent: Alignment.Center }) {
            VRefreshDarkX24({
              iconSize: ThemeDimens.ICON_SIZE_STANDARD,
              fillColor: this.palette().toolbarIconColor
            })
          }
          .width(ThemeDimens.TOUCH_TARGET_MIN)
          .height(ThemeDimens.TOUCH_TARGET_MIN)
          .onClick((): void => {
            void this.loadQuickSearches();
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

        if (this.loading && this.entries.length === 0) {
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
        } else if (QuickSearchScene.viewFor(this.entries) === QuickSearchView.EMPTY) {
          Column({ space: 12 }) {
            BigSearch({
              iconSize: 120,
              fillColor: this.palette().drawableSecondary
            })
            Text($r('app.string.no_quick_search'))
              .fontSize(ThemeTypography.TEXT_LITTLE_SMALL)
              .fontColor(this.palette().textSecondary)
              .textAlign(TextAlign.Center)
            Text($r('app.string.quick_search_tip'))
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
            ForEach(this.entries, (entry: QuickSearchEntry, index: number) => {
              ListItem() {
                ItemQuickSearchLayout({
                  swipeHandlerBuilder: (): void => {
                    this.quickSearchRow(entry, index);
                  }
                })
              }
            }, (entry: QuickSearchEntry) => entry.key)
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

      if (this.deleteIndex >= 0 && this.deleteIndex < this.entries.length) {
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
