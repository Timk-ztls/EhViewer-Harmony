/*
 * 上游：app/src/main/java/com/hippo/ehviewer/ui/GalleryActivity.java（**实际 1449 行**，清单记 1283）
 * 目标：harmony/entry/src/main/ets/hippo/ehviewer/ui/GalleryActivity.ets（inventory S0208）
 *
 * Part 1：深链路由 —— 解析 gid/page/search 参数决定进详情还是列表；启动检查链
 *         （WarningScene → SelectSiteScene → AnalyticsScene）；返回栈。
 *
 * Part 2（本批）：**阅读器本体的判据层** ——
 *   ① 意图解析与三个 provider 的分派（ACTION_DIR / ACTION_EH / ACTION_VIEW，后者只支持 zip）
 *   ② 按键 → 翻页/菜单 的映射（**音量键的两个不对称分支**逐条照搬）
 *   ③ 底部滑块状态（起始/末尾文本、max、progress、reverse）与拖动/松手语义
 *   ④ 自动翻页开关、EventBus 投递的"已建就不重建"、状态序列化键集
 *
 * 为什么 Part 2 只做判据层：上游 1449 行里约 **900 行是 GL/视图脚手架**
 * （GLRootView / GalleryView / ColorView / ObjectAnimator / SeekBar 控件本身），
 * 属 gl-render + ui-widget 的领域（`GalleryView`、`GLRootView` 已由 gl-render 交付）。
 * 本文件交付它们之间的**决策**：按哪个键翻哪一页、滑块显示什么、什么时候切 provider。
 *
 * ⚠️ 与 Part 1 头注的差异（必须记录）：Part 1 头注写的
 * "Part 2 待补：EHTasker / EhDeepLink / 分享意图" —— 经核**上游本文件里没有这些**
 * （全仓 grep `EHTasker`/`EhDeepLink` 均 0 命中）。本文件的"外部入口"只有
 * `Intent.ACTION_VIEW` + `buildProvider()` 三分派 + EventBus 的 `onGalleryActivityEvent`。
 */
import { Announcer } from '../../scene/Announcer';
import { StageActivity } from '../../scene/StageActivity';
import { LaunchMode, SceneArgs } from '../../scene/SceneTypes';
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN: number = 0x0000;
const TAG: string = 'GalleryActivity';

/** 深链参数（上游 Intent extra 的键，同名） */
export class GalleryActivityKeys {
  static readonly KEY_GID: string = 'gid';
  static readonly KEY_PAGE: string = 'page';
  static readonly KEY_SEARCH: string = 'search';
  static readonly KEY_API_URL: string = 'api_url';
}

export class GalleryActivity extends StageActivity {
  private gid: number = -1;
  private page: number = -1;
  private search: string = '';
  /** Part 2：provider 分派用（上游 mFilename / mUri / mGalleryInfo） */
  private fileName: string | null = null;
  private uri: string | null = null;
  private galleryInfo: boolean = false;

  /** 滑块动画时长（上游 `SLIDER_ANIMATION_DURING = 150`）。 */
  static readonly SLIDER_ANIMATION_DURATION: number = 150;
  /** 滑块自动隐藏延迟（上游 `HIDE_SLIDER_DELAY = 3000`）。 */
  static readonly HIDE_SLIDER_DELAY: number = 3000;

  getContainerViewId(): string {
    return 'gallery_stage_container';
  }

  /** 冷启动：无深链参数时进列表；有 gid 时 Part 2 改为直达详情 */
  getLaunchAnnouncer(): Announcer | null {
    if (this.gid > 0) {
      const args: SceneArgs = new Map<string, Object>();
      args.set(GalleryActivityKeys.KEY_GID, this.gid);
      if (this.page > 0) {
        args.set(GalleryActivityKeys.KEY_PAGE, this.page);
      }
      return new Announcer('GalleryDetailScene').setArgs(args);
    }
    const listArgs: SceneArgs = new Map<string, Object>();
    if (this.search.length > 0) {
      listArgs.set(GalleryActivityKeys.KEY_SEARCH, this.search);
    }
    return new Announcer('GalleryListScene').setArgs(listArgs);
  }

  /** 解析深链参数（上游 handleArguments 的等价；由 Ability 层在 createStage 前注入） */
  setDeepLink(gid: number, page: number, search: string): void {
    this.gid = gid;
    this.page = page;
    this.search = search;
  }

  /** 上游 onCreate2：注册 launchMode + 启动检查链 */
  protected onCreateStage(savedInstanceState: SceneArgs | null): void {
    StageActivity.registerLaunchMode('GalleryDetailScene', LaunchMode.STANDARD);
    StageActivity.registerLaunchMode('GalleryListScene', LaunchMode.SINGLE_TOP);
    if (savedInstanceState === null) {
      this.runStartupChecks();
    }
  }

  /**
   * 上游首次启动检查链：警告页 → 站点选择 → 统计同意。
   * 三者都由 registerScene 注册，这里只按顺序判断"是否需要展示"。
   */
  private runStartupChecks(): void {
    if (this.needWarning()) {
      this.startScene(new Announcer('WarningScene'));
      return;
    }
    if (this.needSelectSite()) {
      this.startScene(new Announcer('SelectSiteScene'));
    }
  }

  /** 子类/设置层覆盖：是否需要展示警告页（上游读取 Settings 的同意状态） */
  protected needWarning(): boolean { return false; }
  protected needSelectSite(): boolean { return false; }
  protected needAnalyticsDialog(): boolean { return false; }

  /** 返回：栈空则由 EntryAbility 退出 */
  handleBackPressed(): boolean {
    if (this.getSceneCount() === 0) {
      return false;
    }
    this.onBackPressed();
    return true;
  }

  // ================================================================== Part 2

  /** 供 Ability 层注入 provider 相关字段（Part 1 的 setDeepLink 之外）。 */
  setIntentFields(fileName: string | null, uri: string | null, hasGalleryInfo: boolean): void {
    this.fileName = fileName;
    this.uri = uri;
    this.galleryInfo = hasGalleryInfo;
  }

  /** 当前要建的 provider（未注入任何参数 → NONE）。 */
  providerPlanFor(action: string | null): ProviderPlan {
    return GalleryActivity.buildProviderPlan(action, this.fileName, this.uri, this.galleryInfo);
  }

  // ------------------------------------------------------------------ 意图与 provider

  /**
   * 意图解析（上游 `onInit`）。
   *
   * **`canFinish` 是"跳转崩溃"修复的核心**：只有 `DATA_IN_EVENT=true`（EventBus 投递、
   * provider 已经建好）时才**不**设置 canFinish；其余（无 intent / 普通启动）都允许结束。
   */
  static parseIntent(intent: IntentLike | null): IntentParseResult {
    if (intent === null) {
      return new IntentParseResult(true, new IntentLike(null, null, null, false, -1, false),
        new ProviderPlan(ProviderKind.NONE, null, null, false));
    }
    const canFinish: boolean = !intent.dataInEvent;
    const plan: ProviderPlan = GalleryActivity.buildProviderPlan(intent.action, intent.filename,
      intent.uri, intent.galleryInfoPresent);
    return new IntentParseResult(canFinish, intent, plan);
  }

  /**
   * provider 分派（上游 `buildProvider`）。
   *
   * 三分支互斥且各有前置条件：DIR 要 filename、EH 要 galleryInfo、VIEW 要 uri
   * （上游注释写明 **只支持 zip**）。
   */
  static buildProviderPlan(action: string | null, filename: string | null, uri: string | null,
    hasGalleryInfo: boolean): ProviderPlan {
    if (action === ACTION_DIR) {
      return filename === null
        ? new ProviderPlan(ProviderKind.NONE, null, null, false)
        : new ProviderPlan(ProviderKind.DIR, filename, null, false);
    }
    if (action === ACTION_EH) {
      return hasGalleryInfo
        ? new ProviderPlan(ProviderKind.EH, null, null, true)
        : new ProviderPlan(ProviderKind.NONE, null, null, false);
    }
    if (action === ACTION_VIEW) {
      return uri === null
        ? new ProviderPlan(ProviderKind.NONE, null, null, false)
        : new ProviderPlan(ProviderKind.ARCHIVE, null, uri, false);
    }
    return new ProviderPlan(ProviderKind.NONE, null, null, false);
  }

  /**
   * EventBus 投递（上游 `onGalleryActivityEvent`）：**provider 已存在就直接返回**。
   *
   * @returns true = 需要继续（buildProvider + onCreateView）
   */
  static shouldHandleEvent(providerExists: boolean): boolean {
    return !providerExists;
  }

  /** 状态保存的键集（上游 `onSaveInstanceState` 的 6 个键，顺序照搬）。 */
  static savedKeys(): string[] {
    return [KEY_ACTION, KEY_FILENAME, KEY_URI, KEY_GALLERY_INFO, KEY_PAGE, KEY_CURRENT_INDEX];
  }

  // ------------------------------------------------------------------ 按键映射

  /**
   * 按键 → 动作（上游 `onKeyDown`）。
   *
   * **两个刻意的不对称，必须照搬**：
   *   ① 音量键判 `layoutRTL && unReverse`（`unReverse = !reverseVolumePage`）——**两条件合取**；
   *      而方向键只判 `layoutRTL`，**不看 unReverse**；
   *   ② `DPAD_LEFT` / `DPAD_RIGHT` 是**绝对方向**（永远 pageLeft / pageRight），不随 RTL 取反；
   *      只有 `PAGE_UP/DOWN`、`DPAD_UP/DOWN` 随 RTL 取反。
   */
  static keyActionFor(keyCode: number, volumePage: boolean, reverseVolumePage: boolean,
    layout: LayoutMode): KeyAction {
    const unReverse: boolean = !reverseVolumePage;
    const rtl: boolean = layout === LayoutMode.RIGHT_TO_LEFT;

    if (volumePage) {
      if (keyCode === KeyCode.VOLUME_UP) {
        return (rtl && unReverse) ? KeyAction.PAGE_RIGHT : KeyAction.PAGE_LEFT;
      }
      if (keyCode === KeyCode.VOLUME_DOWN) {
        return (rtl && unReverse) ? KeyAction.PAGE_LEFT : KeyAction.PAGE_RIGHT;
      }
    }

    switch (keyCode) {
      case KeyCode.PAGE_UP:
      case KeyCode.DPAD_UP:
        return rtl ? KeyAction.PAGE_RIGHT : KeyAction.PAGE_LEFT;
      case KeyCode.DPAD_LEFT:
        return KeyAction.PAGE_LEFT;
      case KeyCode.PAGE_DOWN:
      case KeyCode.DPAD_DOWN:
        return rtl ? KeyAction.PAGE_LEFT : KeyAction.PAGE_RIGHT;
      case KeyCode.DPAD_RIGHT:
        return KeyAction.PAGE_RIGHT;
      case KeyCode.DPAD_CENTER:
      case KeyCode.SPACE:
      case KeyCode.MENU:
        return KeyAction.TAP_MENU;
      default:
        return KeyAction.PASS_THROUGH;
    }
  }

  /**
   * 抬手（上游 `onKeyUp`）：把刚处理过的键**吃掉**，不让系统再处理一次。
   *
   * 判据与 `onKeyDown` **不同**：音量键只在 `volumePage=true` 时吃掉
   * （开关关掉要让系统调音量）；方向/翻页/菜单键**无条件吃掉**。
   */
  static keyUpActionFor(keyCode: number, volumePage: boolean): KeyAction {
    if (volumePage && (keyCode === KeyCode.VOLUME_UP || keyCode === KeyCode.VOLUME_DOWN)) {
      return KeyAction.SWALLOW;
    }
    switch (keyCode) {
      case KeyCode.PAGE_UP:
      case KeyCode.PAGE_DOWN:
      case KeyCode.DPAD_LEFT:
      case KeyCode.DPAD_UP:
      case KeyCode.DPAD_RIGHT:
      case KeyCode.DPAD_DOWN:
      case KeyCode.DPAD_CENTER:
      case KeyCode.SPACE:
      case KeyCode.MENU:
        return KeyAction.SWALLOW;
      default:
        return KeyAction.PASS_THROUGH;
    }
  }

  // ------------------------------------------------------------------ 滑块

  /**
   * 底部滑块状态（上游 `updateSlider`）。
   *
   * 前置：`size > 0` 且 `currentIndex >= 0`，否则**不更新**（返回 null）。
   * 起始文本永远是"当前页 + 1"（1 基展示）；RTL 时 `reverse = true`（文本位置由调用方按 reverse 摆）。
   */
  static sliderState(size: number, currentIndex: number, layout: LayoutMode): SliderState | null {
    if (size <= 0 || currentIndex < 0) {
      return null;
    }
    const rtl: boolean = layout === LayoutMode.RIGHT_TO_LEFT;
    return new SliderState(`${currentIndex + 1}`, `${size}`, size - 1, currentIndex, rtl);
  }

  /** 拖动中（上游 `onProgressChanged`）：**只有 fromUser** 才刷起始文本。 */
  static sliderTextWhileDragging(progress: number, fromUser: boolean): string | null {
    return fromUser ? `${progress + 1}` : null;
  }

  /** 松手（上游 `onStopTrackingTouch`）：只有 progress 与当前页不同才跳页。 */
  static shouldJumpOnRelease(progress: number, currentIndex: number): boolean {
    return progress !== currentIndex;
  }

  /** 松手后重排自动隐藏的延迟（毫秒）。 */
  static hideDelayAfterRelease(): number {
    return GalleryActivity.HIDE_SLIDER_DELAY;
  }

  /** 自动翻页开关的图标（上游两张图）。 */
  static autoTransferIcon(autoTransferring: boolean): string {
    return autoTransferring ? 'ic_pause_circle' : 'ic_start_play_24';
  }

  /** 切换自动翻页（上游 `autoTransferring = !autoTransferring` + 换图标）。 */
  static toggleAutoTransfer(autoTransferring: boolean): boolean {
    const next: boolean = !autoTransferring;
    hilog.info(DOMAIN, TAG, 'auto transfer → %{public}s', `${next}`);
    return next;
  }
}

/** 阅读器要建哪种 provider（上游 `buildProvider` 三分支 + 空）。 */
export enum ProviderKind {
  NONE = 0,
  /** `ACTION_DIR` + filename → `DirGalleryProvider` */
  DIR = 1,
  /** `ACTION_EH` + galleryInfo → `EhGalleryProvider` */
  EH = 2,
  /** `ACTION_VIEW` + uri → `ArchiveGalleryProvider`（**只支持 zip**） */
  ARCHIVE = 3
}

/** provider 分派计划（纯数据）。 */
export class ProviderPlan {
  kind: ProviderKind = ProviderKind.NONE;
  filename: string | null = null;
  uri: string | null = null;
  hasGalleryInfo: boolean = false;

  constructor(kind: ProviderKind, filename: string | null, uri: string | null,
    hasGalleryInfo: boolean) {
    this.kind = kind;
    this.filename = filename;
    this.uri = uri;
    this.hasGalleryInfo = hasGalleryInfo;
  }
}

/** 意图投影（上游 `getIntent()` 的四个 extra + action）。 */
export class IntentLike {
  action: string | null = null;
  filename: string | null = null;
  uri: string | null = null;
  galleryInfoPresent: boolean = false;
  page: number = -1;
  dataInEvent: boolean = false;

  constructor(action: string | null, filename: string | null, uri: string | null,
    galleryInfoPresent: boolean, page: number, dataInEvent: boolean) {
    this.action = action;
    this.filename = filename;
    this.uri = uri;
    this.galleryInfoPresent = galleryInfoPresent;
    this.page = page;
    this.dataInEvent = dataInEvent;
  }
}

/** 意图解析结果（`onInit` 的字段赋值 + `canFinish`）。 */
export class IntentParseResult {
  canFinish: boolean = false;
  intent: IntentLike = new IntentLike(null, null, null, false, -1, false);
  plan: ProviderPlan = new ProviderPlan(ProviderKind.NONE, null, null, false);

  constructor(canFinish: boolean, intent: IntentLike, plan: ProviderPlan) {
    this.canFinish = canFinish;
    this.intent = intent;
    this.plan = plan;
  }
}

/** 按键应做什么。 */
export enum KeyAction {
  PASS_THROUGH = 0,
  /** 上一页（视觉左） */
  PAGE_LEFT = 1,
  /** 下一页（视觉右） */
  PAGE_RIGHT = 2,
  /** 呼出菜单区 */
  TAP_MENU = 3,
  /** 吃掉但不动作（上游 `onKeyUp` 对音量/方向键 return true） */
  SWALLOW = 4
}

/** 上游用到的键码（数值与 Android 一致）。 */
export class KeyCode {
  static readonly VOLUME_UP: number = 24;
  static readonly VOLUME_DOWN: number = 25;
  static readonly DPAD_UP: number = 19;
  static readonly DPAD_DOWN: number = 20;
  static readonly DPAD_LEFT: number = 21;
  static readonly DPAD_RIGHT: number = 22;
  static readonly DPAD_CENTER: number = 23;
  static readonly PAGE_UP: number = 92;
  static readonly PAGE_DOWN: number = 93;
  static readonly SPACE: number = 62;
  static readonly MENU: number = 82;
}

/** 布局方向（上游 `GalleryView.LAYOUT_LEFT_TO_RIGHT` / `LAYOUT_RIGHT_TO_LEFT`）。 */
export enum LayoutMode {
  LEFT_TO_RIGHT = 0,
  /** 日漫方向 */
  RIGHT_TO_LEFT = 1
}

/** 底部滑块状态（上游 `updateSlider`）。 */
export class SliderState {
  /** 起始文本（`currentIndex + 1`） */
  startText: string = '';
  /** 末尾文本（`size`） */
  endText: string = '';
  max: number = 0;
  progress: number = 0;
  reverse: boolean = false;

  constructor(startText: string, endText: string, max: number, progress: number,
    reverse: boolean) {
    this.startText = startText;
    this.endText = endText;
    this.max = max;
    this.progress = progress;
    this.reverse = reverse;
  }
}

/** 上游两个自定义 action + 系统 VIEW。 */
export const ACTION_DIR: string = 'dir';
export const ACTION_EH: string = 'eh';
export const ACTION_VIEW: string = 'android.intent.action.VIEW';

/** 上游 Intent 键（逐字对齐）。 */
export const KEY_ACTION: string = 'action';
export const KEY_FILENAME: string = 'filename';
export const KEY_URI: string = 'uri';
export const KEY_GALLERY_INFO: string = 'gallery_info';
export const DATA_IN_EVENT: string = 'data_in_event';
export const KEY_PAGE: string = 'page';
export const KEY_CURRENT_INDEX: string = 'current_index';
