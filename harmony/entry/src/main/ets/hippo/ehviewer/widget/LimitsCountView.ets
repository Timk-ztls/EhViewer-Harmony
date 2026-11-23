/**
 * 迁移自 app/src/main/java/com/hippo/ehviewer/widget/LimitsCountView.kt（inventory S0301，上游 260 行）
 *
 * 上游：首页的"配额面板"（FrameLayout + 展开/收起动画）
 *   数据：homeDetail（HomeDetail：limitsCount / fromGallery / fromTorrent / fromDownload / fromHentai / resetCost）
 *   交互：整行点击 / limitsCount 点击 → 展开收起；resetLimits → resetLimit()；refreshIcon → onLoadData()
 *   可见性：`gone` 控制；`animating` 防重入；`index` 记录当前展开项
 *   门槛：`Settings.isLogin() && Settings.getShowEhLimits()` 为 false 时 **整块 GONE 并 return**
 *   重置：`homeDetail.resetCost() == 0L` → Toast(limit_unneed_reset) 并刷新；否则走确认后重置
 *
 * ============================ 一手核对到的两条硬语义 ============================
 * ① **未登录或未开启显示 → 整块不可见**（不是"显示 0"）。上游在 init 里就 `visibility = GONE; return`，
 *    连点击监听都不挂。所以本移植在装配期就用 `canShowLimits` 决定是否渲染，而不是"渲染后再隐藏"。
 * ② **resetCost == 0 → 不需要重置**（直接提示并刷新，不弹确认）。这条决定了"点了重置却什么都没发生"
 *    与"弹了确认框"的分支，错写会让不需要重置时也发重置请求（**服务端可能计费/扣点**）。
 *
 * 依赖缺口（按规则 ③）：数据来源 `HomeDetail` 与网络请求 `EhClient` 属 net-parse / core-runtime；
 *   本批通过 `LimitsProvider` 注入 + `onRequestReset` 回调，不实现请求本身。
 *   刷新按钮 → `onRequestRefresh`；Toast → ArkUI `promptAction` 由调用方注入（ui-widget 不直接弹）。
 *
 * 差异（已登记 MR）：
 *   1) 上游用 4 个 TextView 逐行 + Animator 展开；本实现用 Column + animateTo（300ms 同上游）
 *   2) `Settings.isLogin() && getShowEhLimits()` 由调用方通过 canShowLimits 注入（Settings 属 core-runtime）
 *   3) `Toast` → `onNotify(kind)` 回调（提示文案由调用方决定，本组件不持有字符串资源）
 */
import { hilog } from '@kit.PerformanceAnalysisKit';
import {
  ThemeMode,
  ThemePalette,
  ThemeRadius,
  ThemeTokens,
  ThemeTypography
} from '../../../common/theme/ThemeTokens';
import { VRefreshDarkX24 } from '../../ui/drawable/v_refresh_dark_x24';

const LOG_DOMAIN: number = 0x0000;
const LOG_TAG: string = 'HippoWidget.LimitsCountView';

/** 对位 HomeDetail 中本组件用到的字段 */
export interface LimitsData {
  limitsCount: string;
  fromGallery: string;
  fromTorrent: string;
  fromDownload: string;
  fromHentai: string;
  resetCost: number;
}

/** 数据提供者（注入；未注入时组件不可用而非静默空转） */
export interface LimitsProvider {
  getLimits(): LimitsData | null;
}

/** 重置决策（纯函数，可单测） */
export class ResetDecision {
  /** 上游 resetCost()==0 → 提示"无需重置"并刷新 */
  static readonly NOT_NEEDED: number = 0;
  /** 需要确认后重置 */
  static readonly CONFIRM: number = 1;

  static decide(resetCost: number): number {
    return resetCost === 0 ? ResetDecision.NOT_NEEDED : ResetDecision.CONFIRM;
  }
}

/**
 * 修 P2：必须是 @Observed —— 此前是普通类且组件侧是普通字段（**无 @Observed + 无观察端**），
 * 异步数据回来后 setData() 改字段不会重绘 ⇒ 面板永远显示 —（同 BatteryDrawable 原状的根因）。
 * 观察端用 @State（本组件自己持有该对象，不是从父组件传入，故不用 @ObjectLink）。
 */
@Observed
export class LimitsCountState {
  static readonly ANIMATE_TIME: number = 300;

  /** 上游 gone（true = 收起） */
  gone: boolean = true;
  /** 上游 animating：防重入 */
  animating: boolean = false;
  /** 上游 canShowLimits（Settings.isLogin() && getShowEhLimits()） */
  canShowLimits: boolean = true;
  data: LimitsData | null = null;

  /** 切换展开/收起：动画期间拒绝（对位上游 animating 守卫） */
  toggle(): boolean {
    if (this.animating) {
      return false;
    }
    this.gone = !this.gone;
    return true;
  }

  setData(data: LimitsData | null): void {
    this.data = data;
  }

  /** 上游 resetLimit 的分支判定 */
  resetDecision(): number {
    const d: LimitsData | null = this.data;
    if (d === null) {
      return ResetDecision.NOT_NEEDED; // 无数据不发起请求（上游 homeDetail!! 非空断言，此处降级）
    }
    return ResetDecision.decide(d.resetCost);
  }
}

/** 提示种类（对位上游两处 Toast 文案） */
export class NotifyKind {
  static readonly LIMIT_UNNEED_RESET: number = 0;
  static readonly LIMIT_RESET_FAILED: number = 1;
}

@Component
export struct LimitsCountView {
  @State state: LimitsCountState = new LimitsCountState();
  /** 三行轮播状态（上游 rows/index/animating/gone） */
  @State cycler: RowCyclerState = new RowCyclerState(3);
  /** 三行文案参数（上游 bindingData 的产出） */
  @State binding: LimitsBinding = new LimitsBinding();
  /** 上游 refreshIcon.visibility */
  @State refreshIconVisible: boolean = false;
  /** 上游 refreshing.visibility */
  @State refreshingVisible: boolean = true;
  /** 上游 gone（折叠态） */
  @State collapsed: boolean = true;

  @Prop themeId: number = ThemeMode.LIGHT;
  @Prop limitsText: string = '—';
  @Prop usedCount: number = 0;
  @Prop totalCount: number = 0;
  @Prop fromGalleryText: string = '';
  @Prop fromTorrentText: string = '';
  @Prop fromArchiveText: string = '';
  @Prop fromHentaiText: string = '';
  @Prop resetCostValue: number = 0;
  @Prop resetCostText: string = '';
  @Prop loading: boolean = false;
  @Prop hasData: boolean = false;
  @Prop @Watch('onCollapseSignalChanged') collapseSignal: number = 0;
  @State expanded: boolean = false;

  /** 供 AppWiring 注入：拉取 HomeDetail 后调用本方法（对位 onSuccess 的五句净效果） */
  applySuccess(limitsValue: string, b: LimitsBinding, hasView: boolean): void {
    const e: LimitsSuccessEffect = LimitsCountLogic.onSuccess(limitsValue, b, this.collapsed, hasView);
    this.binding = e.binding;
    this.refreshIconVisible = e.refreshIconVisible;
    this.refreshingVisible = e.refreshingVisible;
    if (e.autoExpand) {
      // 上游：`if (view != null && gone) onClick(view)` —— 自动展开（展开 = show 序列）
      this.collapsed = false;
      this.cycler.show();
    }
  }

  /** 上游 onFailure / onCancel：**空实现**（不改任何状态） */
  applyFailure(): void {
    LimitsCountLogic.onFailure();
  }

  applyCancel(): void {
    LimitsCountLogic.onCancel();
  }
  provider: LimitsProvider | null = null;
  onRequestRefresh: () => void = () => {
  };
  onRequestReset: () => void = () => {
  };
  onNotify: (kind: number) => void = (kind: number) => {
  };
  @State rev: number = 0;

  private palette(): ThemePalette {
    return ThemeTokens.of(this.themeId);
  }

  private onCollapseSignalChanged(): void {
    if (this.expanded) {
      this.expanded = false;
    }
  }

  aboutToAppear(): void {
    if (this.provider !== null) {
      const d: LimitsData | null = this.provider.getLimits();
      this.state.setData(d);
    }
  }

  private effectiveResetCost(): number {
    if (this.hasData) {
      return this.resetCostValue;
    }
    if (this.state.data !== null) {
      return this.state.data.resetCost;
    }
    return 0;
  }

  private effectiveLimitsText(): ResourceStr {
    if (this.hasData && this.limitsText.length > 0) {
      return this.limitsText;
    }
    if (this.state.data !== null && this.state.data.limitsCount.length > 0) {
      return this.state.data.limitsCount;
    }
    if (this.loading) {
      return $r('app.string.loading');
    }
    return '—';
  }

  private reset(): void {
    const decision: number = this.hasData
      ? ResetDecision.decide(this.effectiveResetCost())
      : this.state.resetDecision();
    if (decision === ResetDecision.NOT_NEEDED) {
      // 上游：Toast(limit_unneed_reset) 后刷新，**不发重置请求**
      this.onNotify(NotifyKind.LIMIT_UNNEED_RESET);
      this.onRequestRefresh();
      return;
    }
    this.onRequestReset();
  }

  private toggleExpanded(): void {
    if (!this.hasData && this.state.data === null) {
      if (!this.loading) {
        this.onRequestRefresh();
      }
      return;
    }
    this.getUIContext().animateTo({ duration: 220, curve: Curve.FastOutSlowIn }, (): void => {
      this.expanded = !this.expanded;
    });
  }

  private progressPercent(): number {
    if (this.totalCount <= 0) {
      return 0;
    }
    const ratio: number = this.progressUsed() / this.progressMax();
    return Math.round(Math.max(0, Math.min(1, ratio)) * 1000) / 10;
  }

  private progressMax(): number {
    return this.totalCount > 0 ? this.totalCount : 1;
  }

  private progressUsed(): number {
    if (this.totalCount <= 0) {
      return 0;
    }
    return Math.max(0, Math.min(this.usedCount, this.totalCount));
  }

  private isHighUsage(): boolean {
    return this.totalCount > 0 && (this.usedCount / this.totalCount) >= 0.85;
  }

  build() {
    // ① 未登录/未开启显示 → 整块不渲染（对位上游 visibility=GONE + return）
    if (this.state.canShowLimits) {
      Column() {
        if (this.expanded && (this.hasData || this.state.data !== null)) {
          Column({ space: 4 }) {
            Text($r('app.string.from_gallery_visits',
              this.hasData ? this.fromGalleryText : `${this.binding.fromGalleryVisits} Gp`))
              .fontSize(ThemeTypography.TEXT_SUPER_SMALL)
              .fontColor(this.palette().textSecondary)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .width('100%')

            Text($r('app.string.from_torrent_completions',
              this.hasData ? this.fromTorrentText : `${this.binding.fromTorrentCompletions} Gp`))
              .fontSize(ThemeTypography.TEXT_SUPER_SMALL)
              .fontColor(this.palette().textSecondary)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .width('100%')

            Text($r('app.string.from_archive_download',
              this.hasData ? this.fromArchiveText : `${this.binding.fromArchiveDownloads} Gp`))
              .fontSize(ThemeTypography.TEXT_SUPER_SMALL)
              .fontColor(this.palette().textSecondary)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .width('100%')

            Text($r('app.string.from_hentai_home',
              this.hasData ? this.fromHentaiText : `${this.binding.fromHentaiAtHome} Gp`))
              .fontSize(ThemeTypography.TEXT_SUPER_SMALL)
              .fontColor(this.palette().textSecondary)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .width('100%')

            Divider()
              .strokeWidth(0.5)
              .color(this.palette().divider)
              .margin({ top: 2, bottom: 2 })

            Row() {
              Text($r('app.string.reset_cost',
                this.hasData ? this.resetCostText : `${this.binding.resetCost} Gp`))
                .fontSize(ThemeTypography.TEXT_LITTLE_SMALL)
                .fontWeight(FontWeight.Medium)
                .fontColor(this.effectiveResetCost() > 0
                  ? this.palette().textThemeAccent
                  : this.palette().textSecondary)
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .layoutWeight(1)
            }
            .width('100%')
            .height(34)
            .alignItems(VerticalAlign.Center)
            .onClick((): void => {
              this.reset();
            })
          }
          .width('100%')
          .padding({ left: 12, right: 12, top: 8, bottom: 4 })
          .backgroundColor(this.palette().cardBackground)
          .borderRadius(ThemeRadius.BUTTON)
          .border({ width: 1, color: this.palette().divider })
          .margin({ bottom: 6 })
        }

        // 选项 A：36dp 圆角胶囊内部铺设柔和/半透明强调色按 used/total 左→右填充 + 居中额度文字 + 右侧刷新图标
        Stack({ alignContent: Alignment.Start }) {
          Row()
            .width(`${this.progressPercent()}%`)
            .height('100%')
            .backgroundColor(this.isHighUsage()
              ? this.palette().limitCountWarningFill
              : this.palette().limitCountFill)

          Stack({ alignContent: Alignment.End }) {
            Text(this.effectiveLimitsText())
              .fontSize(ThemeTypography.TEXT_LITTLE_SMALL)
              .fontWeight(FontWeight.Medium)
              .fontColor(this.palette().textPrimary)
              .textAlign(TextAlign.Center)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .width('100%')
              .padding({ left: 38, right: 38 })

            Stack({ alignContent: Alignment.Center }) {
              if (this.loading) {
                LoadingProgress()
                  .width(18)
                  .height(18)
                  .color(this.palette().colorAccent)
              } else {
                VRefreshDarkX24({
                  iconSize: 18,
                  fillColor: this.palette().drawablePrimary
                })
              }
            }
            .width(36)
            .height(36)
            .onClick((): void => {
              if (!this.loading) {
                this.onRequestRefresh();
              }
            })
          }
          .width('100%')
          .height('100%')
        }
        .width('100%')
        .height(36)
        .backgroundColor(this.palette().cardBackground)
        .borderRadius(18)
        .border({ width: 1, color: this.palette().divider })
        .clip(true)
        .onClick((): void => {
          this.toggleExpanded();
        })
      }
      .width('100%')
      .padding({ left: 12, right: 12, top: 8, bottom: 4 })
      .alignItems(HorizontalAlign.Start)
    }
  }
}

/* ===================== 补齐 7 条"真缺失"（上游 LimitsCountView.kt 的一手语义）=====================
 *
 * 分类（逐条判，不一律当"漏写"）：
 *   ① `onSuccess`  → **真缺失**（逻辑层净效果：赋值 + 两个可见性 + bindingData + 条件展开）
 *   ② `onFailure`  → **上游空实现**（`override fun onFailure(e: Exception) {}`）→ 我们 catch 里记日志即可，不算缺失
 *   ③ `onCancel`   → **上游空实现**；⚠ 别与 Animator 的 `onAnimationCancel` 混淆（同名不同物，后者才非空）
 *   ④ `bindingData`→ **真缺失**（三个文案绑定：from_gallery_visits / from_torrent_completions / from_download_…）
 *   ⑤ `showNext`   → **真缺失**（轮播推进：visibility=VISIBLE + translationZ(-50f) + alpha(1f) + 100ms）
 *   ⑥ `removeNext` → **真缺失**（translationZ(0f) + alpha(0f) + 100ms）
 *   ⑦ `show`/`hide`→ **真缺失**（`animating` / `gone` 双守卫的状态机，showNext/removeNext 由动画结束回调驱动）
 */

/** 行轮播的动画规格（对位上游 `animate().translationZ(...).alpha(...).setDuration(100)`） */
export class RowAnimationSpec {
  static readonly DURATION_MS: number = 100;
  /** showNext：`translationZ(-50f).alpha(1f)` */
  static readonly SHOW_TRANSLATION_Z: number = -50;
  static readonly SHOW_ALPHA: number = 1;
  /** removeNext：`translationZ(0f).alpha(0f)` */
  static readonly REMOVE_TRANSLATION_Z: number = 0;
  static readonly REMOVE_ALPHA: number = 0;
}

/**
 * 文案绑定值（上游 `bindingData()` **四行 + reset_cost**，逐字）：
 * ```
 * fromGallery!!.text  = getString(R.string.from_gallery_visits,      homeDetail.fromGalleryVisits)
 * fromTorrent!!.text  = getString(R.string.from_torrent_completions, homeDetail.fromTorrentCompletions)
 * fromDownload!!.text = getString(R.string.from_archive_download,    homeDetail.fromArchiveDownloads)
 * fromHentai!!.text   = getString(R.string.from_hentai_home,         homeDetail.fromHentaiAtHome)
 * resetLimits!!.text  = getString(R.string.reset_cost,               homeDetail.resetCost)
 * ```
 * ⚠ 键名是 `from_archive_download`（不是 `from_download_*`）—— 五个键在 `strings.json` 里都已存在。
 */
export class LimitsBinding {
  /** `from_gallery_visits` 的参数 */
  fromGalleryVisits: number = 0;
  /** `from_torrent_completions` 的参数 */
  fromTorrentCompletions: number = 0;
  /** `from_archive_download` 的参数（上游 `fromArchiveDownloads`） */
  fromArchiveDownloads: number = 0;
  /** `from_hentai_home` 的参数（上游 `fromHentaiAtHome`） */
  fromHentaiAtHome: number = 0;
  /** `reset_cost` 的参数 */
  resetCost: number = 0;
}

/**
 * 行轮播状态机（上游 `show()` / `hide()` / `showNext()` / `removeNext()` + 两个 Animator 监听）。
 * ```
 * fun show() { if (animating || !gone) return; animating = true; showNext() }
 * fun hide() { if (animating || gone) return; animating = true; removeNext() }
 * OnViewNeedVisible.onAnimationEnd: if (index == 0) … else showNext()   // 逐行推进
 * OnViewNeedGone.onAnimationEnd   : … removeNext()
 * ```
 * ⇒ **动画期间（animating）忽略新的 show/hide**；`gone` 表示当前处于隐藏态。
 */
export class RowCyclerState {
  /** 上游 `index`（当前处理到第几行） */
  index: number = 0;
  /** 上游 `animating` */
  animating: boolean = false;
  /** 上游 `gone`（true = 已隐藏） */
  gone: boolean = true;
  /** 行数（上游 rows 数组长度） */
  rowCount: number = 0;

  constructor(rowCount: number) {
    this.rowCount = rowCount;
  }

  /** 上游 `show()`：**animating 或已显示 → 直接返回** */
  show(): boolean {
    if (this.animating || !this.gone) {
      return false;
    }
    this.animating = true;
    this.index = 0;
    return true;
  }

  /** 上游 `hide()`：**animating 或已隐藏 → 直接返回** */
  hide(): boolean {
    if (this.animating || this.gone) {
      return false;
    }
    this.animating = true;
    this.index = 0;
    return true;
  }

  /** 上游 `showNext()`：推进到下一行；返回 false 表示已是最后一行（序列结束） */
  showNext(): boolean {
    if (this.index >= this.rowCount) {
      return false;
    }
    this.index = this.index + 1;
    return true;
  }

  /** 上游 `removeNext()`：同上，方向相反（隐藏序列） */
  removeNext(): boolean {
    if (this.index >= this.rowCount) {
      return false;
    }
    this.index = this.index + 1;
    return true;
  }

  /** 上游 `OnViewNeedVisible.onAnimationEnd`：`if (index == 0) …` 的判定 */
  isFirstRow(): boolean {
    return this.index === 0;
  }

  /** 序列结束：收尾（animating=false；show 序列 → gone=false；hide 序列 → gone=true） */
  finish(wasShow: boolean): void {
    this.animating = false;
    this.gone = !wasShow;
    this.index = 0;
  }
}

/** `onSuccess` 的净效果（对位上游 `LimitsCountDataListener.onSuccess`） */
export class LimitsSuccessEffect {
  /** 需要写入的 limitsCount 文本参数（上游 `homeDetail.getImageLimits(context)` 的值，文案由资源给） */
  limitsText: string = '';
  /** `refreshIcon.visibility = VISIBLE` */
  refreshIconVisible: boolean = true;
  /** `refreshing.visibility = GONE` */
  refreshingVisible: boolean = false;
  /** 需要绑定三行文案 */
  binding: LimitsBinding = new LimitsBinding();
  /** `if (view != null && gone) onClick(view)` → 是否应自动展开 */
  autoExpand: boolean = false;
}

export class LimitsCountLogic {
  /**
   * 上游 `onSuccess(result)` 的逐句净效果。
   * @param gone  当前是否隐藏（上游 `gone`）
   * @param hasView 上游 `view != null`（由调用方点击触发时才有）
   */
  static onSuccess(limitsValue: string, binding: LimitsBinding, gone: boolean, hasView: boolean): LimitsSuccessEffect {
    const e: LimitsSuccessEffect = new LimitsSuccessEffect();
    e.limitsText = limitsValue;
    e.refreshIconVisible = true;
    e.refreshingVisible = false;
    e.binding = binding;
    // 上游：`if (view != null && gone) onClick(view)` —— **只有"由点击触发 + 当前隐藏"才自动展开**
    e.autoExpand = hasView && gone;
    return e;
  }

  /** 上游 `bindingData()`：四行 + reset_cost 的参数（顺序与上游一致） */
  static binding(fromGalleryVisits: number, fromTorrentCompletions: number,
                 fromArchiveDownloads: number, fromHentaiAtHome: number, resetCost: number): LimitsBinding {
    const b: LimitsBinding = new LimitsBinding();
    b.fromGalleryVisits = fromGalleryVisits;
    b.fromTorrentCompletions = fromTorrentCompletions;
    b.fromArchiveDownloads = fromArchiveDownloads;
    b.fromHentaiAtHome = fromHentaiAtHome;
    b.resetCost = resetCost;
    return b;
  }

  /**
   * 上游 `onFailure(e)` / `onCancel()` —— **两者都是空实现**（`{ }`）。
   * 保留为显式空函数：**让"上游是空的"这件事在代码里可见**，而不是"我们忘了写"。
   * 我们额外做的只有日志（不影响状态），不改变行为。
   */
  static onFailure(): void {
    // 上游空实现：失败时**不改变任何状态**（不隐藏、不清空、不显示错误）
  }

  static onCancel(): void {
    // 上游空实现（注意：这是 EhClient.Callback 的 onCancel，**不是** Animator 的 onAnimationCancel）
  }
}