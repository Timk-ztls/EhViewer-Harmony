/*
 * GalleryCommentsSceneView: Material UI for GalleryCommentsScene
 * (Toolbar, flat comment list w/ 1dp dividers, comment actions dialog, vote details, FAB + bottom edit panel).
 */
import { pasteboard } from '@kit.BasicServicesKit';
import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import {
  ThemeDimens,
  ThemeElevation,
  ThemeMode,
  ThemePalette,
  ThemeRadius,
  ThemeTokens,
  ThemeTypography
} from '../../../common/theme/ThemeTokens';
import { EhApplication } from '../../ehviewer/EhApplication';
import { EhDB } from '../../ehviewer/EhDB';
import { GetText } from '../../ehviewer/GetText';
import { EhEngine, HttpCaller } from '../../ehviewer/client/EhEngine';
import { GalleryComment } from '../../ehviewer/client/data/GalleryComment';
import { GalleryCommentsSceneConcrete } from '../../ehviewer/ui/scene/GalleryCommentsSceneConcrete';
import { OkHttpCallerAdapter } from '../../AppWiring';
import { BlackListUtils, GalleryCommentLike } from '../../util/BlackListUtils';
import { ReadableTime } from '../../util/ReadableTime';
import { SceneDataSourceListener, DataOperation } from '../SceneDataSource';
import { MainPageHost } from '../MainPageHost';
import { GalleryCommentItemLayout } from '../layout/item_gallery_comment';
import { VArrowLeftDarkX24 } from '../drawable/v_arrow_left_dark_x24';
import { VRefreshDarkX24 } from '../drawable/v_refresh_dark_x24';
import { VReplyDarkX24 } from '../drawable/v_reply_dark_x24';
import { VSendDarkX24 } from '../drawable/v_send_dark_x24';
import { VPencilDarkX24 } from '../drawable/v_pencil_dark_x24';
import { BigSadPandroid } from '../drawable/big_sad_pandroid';

const DOMAIN: number = 0x0000;
const TAG: string = 'GalleryCommentsSceneView';

class VoteStatusRow {
  readonly user: string;
  readonly vote: string;

  constructor(user: string, vote: string) {
    this.user = user;
    this.vote = vote;
  }
}

class CommentBlacklistInput implements GalleryCommentLike {
  user: string;
  comment: string;

  constructor(user: string, comment: string) {
    this.user = user;
    this.comment = comment;
  }
}

class CommentsDataListener implements SceneDataSourceListener {
  private readonly onChange: () => void;

  constructor(onChange: () => void) {
    this.onChange = onChange;
  }

  onDataReloaded(): void {
    this.onChange();
  }

  onDataAdd(_index: number): void {
    this.onChange();
  }

  onDataMove(_from: number, _to: number): void {
    this.onChange();
  }

  onDataDelete(_index: number): void {
    this.onChange();
  }

  onDataChange(_index: number): void {
    this.onChange();
  }

  onDatasetChange(_operations: DataOperation[]): void {
    this.onChange();
  }
}

@Component
export struct GalleryCommentsSceneView {
  scene: GalleryCommentsSceneConcrete | null = null;
  host: MainPageHost | null = null;

  @State comments: GalleryComment[] = [];
  @State loading: boolean = false;
  @State hasMore: boolean = false;
  @State replyTargetId: number = -1;
  @State draftComment: string = '';
  @State editPanelOpen: boolean = false;
  @State selectedCommentIdx: number = -1;
  @State showVoteStatusDialog: boolean = false;
  @State voteStatusRows: VoteStatusRow[] = [];
  @Prop themeId: number = -1;

  private dataListener: CommentsDataListener | null = null;
  private pollTimerId: number = -1;

  private palette(): ThemePalette {
    return this.themeId >= 0 ? ThemeTokens.of(this.themeId) : ThemeTokens.current();
  }

  aboutToAppear(): void {
    if (!ReadableTime.isInitialized()) {
      const ctx: common.Context | undefined = this.getUIContext().getHostContext();
      if (ctx !== undefined) {
        ReadableTime.initialize(ctx);
      }
    }
    const s: GalleryCommentsSceneConcrete | null = this.scene;
    if (s === null) {
      return;
    }
    s.setOnStateChangedListener((): void => {
      this.syncFromScene();
    });
    const listener: CommentsDataListener = new CommentsDataListener((): void => {
      this.syncFromScene();
    });
    this.dataListener = listener;
    s.getDataSource().registerDataChangeListener(listener);
    if (s.getDataSource().totalCount() === 0 && s.getApiUrl().length > 0 && !s.isLoading()) {
      s.refreshComments();
    }
    this.syncFromScene();
  }

  aboutToDisappear(): void {
    this.stopLoadingPoll();
    const s: GalleryCommentsSceneConcrete | null = this.scene;
    if (s !== null) {
      s.setOnStateChangedListener(null);
      if (this.dataListener !== null) {
        s.getDataSource().unregisterDataChangeListener(this.dataListener);
      }
    }
    this.dataListener = null;
  }

  private stopLoadingPoll(): void {
    if (this.pollTimerId >= 0) {
      clearInterval(this.pollTimerId);
      this.pollTimerId = -1;
    }
  }

  private ensureLoadingPoll(): void {
    if (!this.loading) {
      this.stopLoadingPoll();
      return;
    }
    if (this.pollTimerId >= 0) {
      return;
    }
    this.pollTimerId = setInterval((): void => {
      const s: GalleryCommentsSceneConcrete | null = this.scene;
      if (s === null || !s.isLoading()) {
        this.syncFromScene();
        this.stopLoadingPoll();
      }
    }, 150) as number;
  }

  private syncFromScene(): void {
    const s: GalleryCommentsSceneConcrete | null = this.scene;
    if (s === null) {
      return;
    }
    this.loading = s.isLoading();
    this.hasMore = s.isHasMore();
    this.replyTargetId = s.getReplyTargetId();
    const ds = s.getDataSource();
    const total: number = ds.totalCount();
    const list: GalleryComment[] = [];
    for (let i = 0; i < total; i++) {
      const c: GalleryComment | null = ds.getData(i);
      if (c !== null) {
        list.push(c);
      }
    }
    this.comments = list;
    this.ensureLoadingPoll();
  }

  private stripHtml(html: string): string {
    return html
      .replace(/<br\s*\/?>/gi, '\n')
      .replace(/<\/p>/gi, '\n')
      .replace(/<[^>]+>/g, '')
      .replace(/&nbsp;/g, ' ')
      .replace(/&lt;/g, '<')
      .replace(/&gt;/g, '>')
      .replace(/&amp;/g, '&')
      .replace(/&quot;/g, '"')
      .replace(/&#039;/g, "'")
      .trim();
  }

  private formatCommentTime(ms: number): string {
    if (ms <= 0) {
      return '';
    }
    return ReadableTime.getTimeAgo(ms);
  }

  private scoreBadge(c: GalleryComment): string {
    if (c.id === 0 || c.score === 0) {
      return '';
    }
    return c.score > 0 ? `+${c.score}` : String(c.score);
  }

  private formatLastEdited(ms: number): string {
    if (ms <= 0) {
      return '';
    }
    const ago: string = ReadableTime.getTimeAgo(ms);
    const tmpl: string = GetText.getString('last_edited');
    if (tmpl.length > 0 && tmpl.indexOf('%s') >= 0) {
      return tmpl.replace('%s', ago);
    }
    return ago;
  }

  private showToast(message: Resource): void {
    try {
      this.getUIContext().getPromptAction().showToast({ message: message, duration: 1500 });
    } catch (err) {
      const e: Error = err as Error;
      hilog.warn(DOMAIN, TAG, 'showToast skipped: %{public}s', e.message);
    }
  }

  private copyTextToClipboard(text: string): void {
    try {
      const board: pasteboard.SystemPasteboard = pasteboard.getSystemPasteboard();
      const data: pasteboard.PasteData = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, text);
      board.setDataSync(data);
      this.showToast($r('app.string.copied_to_clipboard'));
    } catch (err) {
      const e: Error = err as Error;
      hilog.warn(DOMAIN, TAG, 'copyTextToClipboard failed: %{public}s', e.message);
    }
  }

  private async openEditForComment(idx: number, comment: GalleryComment): Promise<void> {
    const s: GalleryCommentsSceneConcrete | null = this.scene;
    if (s === null) {
      return;
    }
    s.openReplyPanel(idx);
    this.replyTargetId = s.getReplyTargetId();
    this.draftComment = this.stripHtml(comment.comment);
    this.editPanelOpen = true;
    try {
      const ctx: common.Context | undefined = this.getUIContext().getHostContext();
      const okClient = EhApplication.getOkHttpClient(ctx === undefined ? null : ctx);
      const caller: HttpCaller = new OkHttpCallerAdapter(okClient);
      const apiUid: number = s.getApiUid();
      const apiKey: string | null = s.getApiKey();
      const gid: number = s.getGid();
      const token: string = s.getToken();
      if (apiUid > 0 && apiKey !== null && gid > 0 && token.length > 0) {
        const res = await EhEngine.getEditComment(null, caller, apiUid, apiKey, gid, token, comment.id);
        if (res.comment.length > 0) {
          this.draftComment = res.comment;
        }
      }
    } catch (err) {
      const e: Error = err as Error;
      hilog.warn(DOMAIN, TAG, 'getEditComment fallback to stripped body: %{public}s', e.message);
    }
  }

  private joinCommentBlacklist(idx: number, comment: GalleryComment): void {
    const input: CommentBlacklistInput = new CommentBlacklistInput(comment.user, comment.comment);
    const entry = BlackListUtils.parseBlacklist(input);
    EhDB.insertBlackList(entry).then((): void => {
      const s: GalleryCommentsSceneConcrete | null = this.scene;
      if (s !== null) {
        s.getDataSource().removeAt(idx);
        this.syncFromScene();
      }
    }).catch((err: Error): void => {
      hilog.warn(DOMAIN, TAG, 'insertBlackList failed: %{public}s', err.message);
    });
  }

  private openVoteStatus(voteState: string): void {
    const parts: string[] = voteState.split(',');
    const rows: VoteStatusRow[] = [];
    for (let i = 0; i < parts.length; i++) {
      const str: string = parts[i].trim();
      if (str.length === 0) {
        continue;
      }
      const spaceIdx: number = str.lastIndexOf(' ');
      if (spaceIdx < 0) {
        rows.push(new VoteStatusRow(str, ''));
      } else {
        rows.push(new VoteStatusRow(str.substring(0, spaceIdx).trim(), str.substring(spaceIdx + 1).trim()));
      }
    }
    this.voteStatusRows = rows;
    this.showVoteStatusDialog = true;
  }

  private submitComment(): void {
    const s: GalleryCommentsSceneConcrete | null = this.scene;
    if (s === null) {
      return;
    }
    const text: string = this.draftComment.trim();
    if (text.length === 0) {
      return;
    }
    const isEdit: boolean = this.replyTargetId > 0;
    s.sendComment(text);
    this.draftComment = '';
    this.editPanelOpen = false;
    this.showToast(isEdit ? $r('app.string.edit_comment_successfully') : $r('app.string.comment_successfully'));
    this.syncFromScene();
  }

  private handleBack(): void {
    if (this.editPanelOpen) {
      this.editPanelOpen = false;
      if (this.scene !== null) {
        this.scene.closeReplyPanel();
        this.syncFromScene();
      }
      return;
    }
    if (this.host !== null) {
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

      Text($r('app.string.gallery_comments'))
        .fontSize(ThemeTypography.TOOLBAR_TITLE)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.palette().toolbarTitleColor)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .margin({ left: ThemeDimens.SPACING })
        .layoutWeight(1)

      Row() {
        VRefreshDarkX24({
          iconSize: ThemeDimens.ICON_SIZE_STANDARD,
          fillColor: this.palette().toolbarIconColor
        })
      }
      .width(ThemeDimens.TOUCH_TARGET_MIN)
      .height(ThemeDimens.TOUCH_TARGET_MIN)
      .justifyContent(FlexAlign.Center)
      .alignItems(VerticalAlign.Center)
      .onClick((): void => {
        const s: GalleryCommentsSceneConcrete | null = this.scene;
        if (s !== null) {
          s.refreshComments();
          this.syncFromScene();
        }
      })
    }
    .width('100%')
    .height(ThemeDimens.TOOLBAR_HEIGHT)
    .padding({ left: ThemeDimens.SPACING_XS, right: ThemeDimens.SPACING_XS })
    .backgroundColor(this.palette().toolbarColor)
    .shadow(ThemeElevation.toolbar())
    .alignItems(VerticalAlign.Center)
    .zIndex(2)
  }

  @Builder
  commentActionMenuRow(label: Resource, action: () => void) {
    Button(label, { type: ButtonType.Normal })
      .width('100%')
      .height(48)
      .padding({ left: 24, right: 24 })
      .borderRadius(ThemeRadius.NONE)
      .backgroundColor(this.palette().transparent)
      .fontColor(this.palette().textPrimary)
      .fontSize(ThemeTypography.TEXT_LITTLE_SMALL)
      .align(Alignment.Start)
      .onClick(action)
  }

  @Builder
  commentActionDialogOverlay() {
    if (this.selectedCommentIdx >= 0 && this.selectedCommentIdx < this.comments.length) {
      Stack({ alignContent: Alignment.Center }) {
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor('#73000000')
          .onClick((): void => {
            this.selectedCommentIdx = -1;
          })

        Column() {
          this.commentActionMenuRow($r('app.string.copy_comment_text'), (): void => {
            const c: GalleryComment = this.comments[this.selectedCommentIdx];
            this.selectedCommentIdx = -1;
            this.copyTextToClipboard(this.stripHtml(c.comment));
          })

          this.commentActionMenuRow($r('app.string.join_in_blacklist'), (): void => {
            const idx: number = this.selectedCommentIdx;
            const c: GalleryComment = this.comments[idx];
            this.selectedCommentIdx = -1;
            this.joinCommentBlacklist(idx, c);
          })

          if (this.comments[this.selectedCommentIdx].editable) {
            this.commentActionMenuRow($r('app.string.edit_comment'), (): void => {
              const idx: number = this.selectedCommentIdx;
              const c: GalleryComment = this.comments[idx];
              this.selectedCommentIdx = -1;
              void this.openEditForComment(idx, c);
            })
          }

          if (this.comments[this.selectedCommentIdx].voteUpAble) {
            this.commentActionMenuRow(
              this.comments[this.selectedCommentIdx].voteUpEd
                ? $r('app.string.cancel_vote_up')
                : $r('app.string.vote_up'),
              (): void => {
                const idx: number = this.selectedCommentIdx;
                this.selectedCommentIdx = -1;
                if (this.scene !== null) {
                  this.scene.voteComment(idx, true);
                }
              }
            )
          }

          if (this.comments[this.selectedCommentIdx].voteDownAble) {
            this.commentActionMenuRow(
              this.comments[this.selectedCommentIdx].voteDownEd
                ? $r('app.string.cancel_vote_down')
                : $r('app.string.vote_down'),
              (): void => {
                const idx: number = this.selectedCommentIdx;
                this.selectedCommentIdx = -1;
                if (this.scene !== null) {
                  this.scene.voteComment(idx, false);
                }
              }
            )
          }

          if (this.comments[this.selectedCommentIdx].voteState.length > 0) {
            this.commentActionMenuRow($r('app.string.check_vote_status'), (): void => {
              const vs: string = this.comments[this.selectedCommentIdx].voteState;
              this.selectedCommentIdx = -1;
              this.openVoteStatus(vs);
            })
          }
        }
        .width('84%')
        .constraintSize({ maxWidth: 360 })
        .padding({ top: 8, bottom: 8 })
        .backgroundColor(this.palette().popupBackground)
        .borderRadius(ThemeRadius.DIALOG)
        .shadow(ThemeElevation.dialog())
      }
      .width('100%')
      .height('100%')
      .zIndex(10)
    }
  }

  @Builder
  voteStatusDialogOverlay() {
    Stack({ alignContent: Alignment.Center }) {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor('#73000000')
        .onClick((): void => {
          this.showVoteStatusDialog = false;
        })

      Column() {
        Text($r('app.string.check_vote_status'))
          .fontSize(ThemeTypography.DIALOG_TITLE)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.palette().textPrimary)
          .width('100%')
          .padding({ left: 24, right: 24, top: 20, bottom: 12 })

        List() {
          ForEach(this.voteStatusRows, (row: VoteStatusRow, idx: number) => {
            ListItem() {
              Row() {
                Text(row.user)
                  .fontSize(ThemeTypography.TEXT_SMALL)
                  .fontColor(this.palette().textPrimary)
                  .layoutWeight(1)
                Text(row.vote)
                  .fontSize(ThemeTypography.TEXT_SMALL)
                  .fontColor(this.palette().textSecondary)
              }
              .width('100%')
              .padding({ left: 24, right: 24, top: 10, bottom: 10 })
            }
          }, (row: VoteStatusRow, idx: number) => `${idx}_${row.user}`)
        }
        .width('100%')
        .constraintSize({ maxHeight: 320 })
        .divider({
          strokeWidth: ThemeDimens.DIVIDER_HEIGHT,
          color: this.palette().divider,
          startMargin: 24,
          endMargin: 24
        })

        Row() {
          Button($r('app.string.ok'), { type: ButtonType.Normal })
            .borderRadius(ThemeRadius.BUTTON)
            .constraintSize({ minWidth: 64, minHeight: 36 })
            .backgroundColor(this.palette().transparent)
            .fontColor(this.palette().colorPrimary)
            .fontSize(ThemeTypography.BUTTON)
            .fontWeight(FontWeight.Medium)
            .onClick((): void => {
              this.showVoteStatusDialog = false;
            })
        }
        .width('100%')
        .justifyContent(FlexAlign.End)
        .padding({ left: 16, right: 16, top: 8, bottom: 12 })
      }
      .width('86%')
      .constraintSize({ maxWidth: 380 })
      .backgroundColor(this.palette().popupBackground)
      .borderRadius(ThemeRadius.DIALOG)
      .shadow(ThemeElevation.dialog())
    }
    .width('100%')
    .height('100%')
    .zIndex(11)
  }

  build() {
    Stack() {
      Column() {
        this.materialToolbar()

        Stack({ alignContent: Alignment.BottomEnd }) {
          if (this.loading && this.comments.length === 0) {
            Column({ space: 12 }) {
              LoadingProgress()
                .width(48)
                .height(48)
                .color(this.palette().progressColor)
              Text($r('app.string.loading'))
                .fontSize(ThemeTypography.TEXT_SMALL)
                .fontColor(this.palette().textSecondary)
            }
            .width('100%')
            .height('100%')
            .justifyContent(FlexAlign.Center)
            .alignItems(HorizontalAlign.Center)
          } else if (this.comments.length === 0) {
            Column({ space: 8 }) {
              BigSadPandroid({
                iconSize: 120,
                fillColor: this.palette().drawableSecondary
              })
              Text($r('app.string.no_one_comments_gallery'))
                .width(228)
                .fontSize(ThemeTypography.TEXT_MEDIUM)
                .fontColor(this.palette().textSecondary)
                .textAlign(TextAlign.Center)
            }
            .width('100%')
            .height('100%')
            .justifyContent(FlexAlign.Center)
            .alignItems(HorizontalAlign.Center)
          } else {
            List() {
              ForEach(this.comments, (c: GalleryComment, idx: number) => {
                ListItem() {
                  GalleryCommentItemLayout({
                    user: c.user,
                    time: this.formatCommentTime(c.time),
                    comment: this.stripHtml(c.comment),
                    scoreText: this.scoreBadge(c),
                    lastEditedText: this.formatLastEdited(c.lastEdited),
                    maxLinesLimit: 0,
                    themeId: this.themeId
                  })
                }
                .onClick((): void => {
                  this.selectedCommentIdx = idx;
                })
              }, (c: GalleryComment, idx: number) => `${c.id}_${idx}_${c.score}_${c.voteUpEd}_${c.voteDownEd}`)

              ListItem() {
                Row() {
                  if (this.hasMore) {
                    if (this.loading) {
                      LoadingProgress()
                        .width(36)
                        .height(36)
                        .color(this.palette().progressColor)
                    } else {
                      Button($r('app.string.click_more_comments'), { type: ButtonType.Normal })
                        .borderRadius(ThemeRadius.BUTTON)
                        .backgroundColor(this.palette().transparent)
                        .fontColor(this.palette().colorPrimary)
                        .fontSize(ThemeTypography.BUTTON)
                        .fontWeight(FontWeight.Medium)
                        .constraintSize({ minHeight: 36 })
                        .padding({ left: 16, right: 16 })
                        .onClick((): void => {
                          if (this.scene !== null) {
                            this.scene.showMoreComments();
                            this.syncFromScene();
                          }
                        })
                    }
                  } else {
                    Text($r('app.string.no_more_comments'))
                      .fontSize(ThemeTypography.TEXT_SUPER_SMALL)
                      .fontColor(this.palette().textSecondary)
                  }
                }
                .width('100%')
                .padding(ThemeDimens.KEYLINE_MARGIN)
                .justifyContent(FlexAlign.Center)
              }
            }
            .width('100%')
            .height('100%')
            .contentEndOffset(ThemeDimens.GALLERY_PADDING_BOTTOM_FAB)
            .divider({
              strokeWidth: ThemeDimens.DIVIDER_HEIGHT,
              color: this.palette().divider
            })
          }

          if (!this.editPanelOpen) {
            Row() {
              VReplyDarkX24({
                iconSize: ThemeDimens.ICON_SIZE_STANDARD,
                fillColor: this.palette().fabIconColor
              })
            }
            .width(ThemeDimens.FAB_SIZE)
            .height(ThemeDimens.FAB_SIZE)
            .borderRadius(ThemeRadius.FAB_PRIMARY)
            .backgroundColor(this.palette().widgetThemePrimary)
            .shadow(ThemeElevation.fab())
            .justifyContent(FlexAlign.Center)
            .alignItems(VerticalAlign.Center)
            .margin({
              right: ThemeDimens.CORNER_FAB_MARGIN,
              bottom: ThemeDimens.CORNER_FAB_MARGIN
            })
            .onClick((): void => {
              if (this.scene !== null) {
                this.scene.closeReplyPanel();
                this.syncFromScene();
              }
              this.draftComment = '';
              this.editPanelOpen = true;
            })
          }

          if (this.editPanelOpen) {
            Column() {
              if (this.replyTargetId > 0) {
                Row({ space: 8 }) {
                  Text(`#${this.replyTargetId}`)
                    .fontSize(ThemeTypography.TEXT_SUPER_SMALL)
                    .fontColor(this.palette().textThemePrimary)
                    .layoutWeight(1)
                  Button($r('app.string.cancel'), { type: ButtonType.Normal })
                    .borderRadius(ThemeRadius.BUTTON)
                    .height(28)
                    .fontSize(ThemeTypography.TEXT_SUPER_SMALL)
                    .fontColor(this.palette().textSecondary)
                    .backgroundColor(this.palette().transparent)
                    .onClick((): void => {
                      this.editPanelOpen = false;
                      if (this.scene !== null) {
                        this.scene.closeReplyPanel();
                        this.syncFromScene();
                      }
                    })
                }
                .width('100%')
                .padding({ left: 16, right: 8, top: 6, bottom: 4 })
                .backgroundColor(this.palette().surfaceBackground)
              }

              Row() {
                TextArea({ placeholder: $r('app.string.gallery_comments'), text: this.draftComment })
                  .layoutWeight(1)
                  .constraintSize({ minHeight: 56, maxHeight: 112 })
                  .fontSize(ThemeTypography.TEXT_LITTLE_SMALL)
                  .fontColor(this.palette().galleryDetailHeaderTitle)
                  .placeholderColor(this.palette().textSecondaryInverse)
                  .backgroundColor(this.palette().transparent)
                  .padding({ left: 16, right: 8, top: 14, bottom: 14 })
                  .onChange((v: string): void => {
                    this.draftComment = v;
                  })

                Row() {
                  if (this.replyTargetId > 0) {
                    VPencilDarkX24({
                      iconSize: ThemeDimens.ICON_SIZE_STANDARD,
                      fillColor: this.palette().toolbarIconColor
                    })
                  } else {
                    VSendDarkX24({
                      iconSize: ThemeDimens.ICON_SIZE_STANDARD,
                      fillColor: this.palette().toolbarIconColor
                    })
                  }
                }
                .width(56)
                .height(56)
                .justifyContent(FlexAlign.Center)
                .alignItems(VerticalAlign.Center)
                .onClick((): void => {
                  this.submitComment();
                })
              }
              .width('100%')
              .backgroundColor(this.palette().galleryDetailHeaderBackground)
              .shadow(ThemeElevation.toolbar())
              .alignItems(VerticalAlign.Bottom)
            }
            .width('100%')
          }
        }
        .width('100%')
        .layoutWeight(1)
      }
      .width('100%')
      .height('100%')

      if (this.selectedCommentIdx >= 0) {
        this.commentActionDialogOverlay()
      }

      if (this.showVoteStatusDialog) {
        this.voteStatusDialogOverlay()
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.palette().windowBackground)
  }
}
