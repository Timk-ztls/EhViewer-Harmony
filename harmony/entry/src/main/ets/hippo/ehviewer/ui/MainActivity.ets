/*
 * 上游：app/src/main/java/com/hippo/ehviewer/ui/MainActivity.java（874 行）
 * 目标：harmony/entry/src/main/ets/hippo/ehviewer/ui/MainActivity.ets（inventory S0212）
 *
 * Part 1（本批）：入口路由骨架 —— LaunchAnnouncer（启动进哪个场景）、抽屉开合、
 *                 scene 注册（launchMode）、返回键。
 * Part 2：抽屉菜单项（9 个）、快速搜索栏、主题/夜间模式切换、onDrawerOpen/Close 广播。
 *
 * Part 3（本批）：**Activity 生命周期与意图回传的判据层**（逐行对 `MainActivity.java` 980 行核过）：
 *   ① `getLaunchAnnouncer` 的**五道门链**（Security→Warning→Analytics→SignIn→SelectSite→列表）
 *   ② `processAnnouncer` 的**包装**逻辑：**只有 `sceneCount == 0` 才包装**，且门场景带上
 *      `KEY_TARGET_SCENE` / `KEY_TARGET_ARGS`（这样门放行后能回到原目标）
 *   ③ `handleIntent` 三分支：ACTION_VIEW（URL）/ ACTION_SEND text（关键词）/ ACTION_SEND image（图搜）
 *   ④ `onUnrecognizedIntent`：栈顶是 SolidScene → **直接丢弃 intent**（上游 TODO: the intent lost）
 *   ⑤ `onBackPressed`：**抽屉开着先关抽屉**，否则才交给场景栈
 *   ⑥ `onNavigationItemSelected`：`item.isChecked()` → **返回 false（拒绝重复选中）**
 *   ⑦ `setNavCheckedItem`：`resId == 0` → 用 `nav_stub` 占位（NavigationView 不支持"无选中"）
 *   ⑧ `onActivityResult`：设置页 OK → `refreshTopScene`；换头像的相机/相册 OK → `saveImageForResult`
 *   ⑨ `onSaveInstanceState` 的键集只有 `nav_checked_item` 一个
 *   ⑩ `onCreate2` 的 `KEY_RESTART`：**重启时把 savedInstanceState 置 null**（丢弃恢复状态）
 *
 * 上游实际 **980 行**（清单记 874）。
 *
 * 上游继承链：MainActivity extends EhActivity extends StageActivity
 * （EhActivity 属 core-runtime，此处用 StageActivity 直接继承并把 EhActivity 的差异记在下面：
 *  EhActivity 只是 StageActivity + 主题/语言覆盖，ArkUI 侧由 Ability 的 Configuration 承担）
 */
import { Announcer } from '../../scene/Announcer';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { StageActivity } from '../../scene/StageActivity';
import { SceneArgs } from '../../scene/SceneTypes';
import { LaunchMode } from '../../scene/SceneTypes';

export class MainActivity extends StageActivity {
  /** 上游 getContainerViewId()：ArkUI 无 view id，返回 StageLayout 容器键 */
  getContainerViewId(): string {
    return 'main_stage_container';
  }

  /** 上游 getLaunchAnnouncer()：冷启动进画廊列表（HOMEPAGE） */
  getLaunchAnnouncer(): Announcer | null {
    const args: SceneArgs = new Map<string, Object>();
    args.set('action', 'action_homepage');
    return new Announcer('GalleryListScene').setArgs(args);
  }

  /** 上游 onCreate2：注册场景 launchMode（ArkTS 无反射，注册靠显式调用） */
  protected onCreateStage(savedInstanceState: SceneArgs | null): void {
    StageActivity.registerLaunchMode('GalleryListScene', LaunchMode.SINGLE_TOP);
    StageActivity.registerLaunchMode('GalleryDetailScene', LaunchMode.STANDARD);
    StageActivity.registerLaunchMode('GalleryCommentsScene', LaunchMode.STANDARD);
    StageActivity.registerLaunchMode('FavoritesScene', LaunchMode.SINGLE_TOP);
  }

  /** 上游 onDrawerOpened/onDrawerClosed：向所有 Scene 广播（D-023 的作用域 reset 依赖它） */
  onDrawerOpened(): void {
    this.broadcastDrawer(true);
  }

  onDrawerClosedBroadcast(): void {
    this.broadcastDrawer(false);
  }

  private broadcastDrawer(opened: boolean): void {
    const tags: string[] = this.getSceneTagList();
    for (let i = 0; i < tags.length; i++) {
      const scene = this.findSceneByTag(tags[i]);
      if (scene !== null && !opened) {
        scene.onDrawerClosed();
      }
    }
  }

  /** 上游 onBackPressed：交给栈顶场景；栈空则退出（由 EntryAbility 处理） */
  handleBackPressed(): boolean {
    if (this.getSceneCount() === 0) {
      return false;
    }
    this.onBackPressed();
    return true;
  }

  // ---------------- Part 2：抽屉 9 项 / 快速搜索 / 主题切换 ----------------

  /** 上游抽屉菜单 id（顺序与 strings 一致，索引即上游 menu 顺序） */
  /**
   * 抽屉项（**与上游 `MainActivity.onNavigationItemSelected` 的 8 个 `case R.id.nav_*` 一一对应**）。
   * 上游没有 About 抽屉项（About 是 `about_settings.xml` + `AboutFragment`，挂在设置页内部），
   * 因此这里曾有的 `DRAWER_ABOUT` / `'AboutScene'` 是臆造的，已删除。
   * `nav_settings` 在上游是 `startActivity(SettingsActivity)` —— **Activity 不是 Scene**，
   * 所以它不进 SceneRegistry，而是走 `abilityStarter`（能力由 EntryAbility 注入）。
   */
  static readonly DRAWER_HOMEPAGE: number = 0;
  static readonly DRAWER_SUBSCRIPTION: number = 1;
  static readonly DRAWER_WHATS_HOT: number = 2;
  static readonly DRAWER_TOP_LIST: number = 3;
  static readonly DRAWER_FAVORITES: number = 4;
  static readonly DRAWER_HISTORY: number = 5;
  static readonly DRAWER_DOWNLOADS: number = 6;
  static readonly DRAWER_SETTINGS: number = 7;

  /**
   * 「启动 Ability」的能力注入点（A 方案）。
   * 本类是纯逻辑类、没有 UI 上下文；`startAbility` 需要 `AbilityContext`，
   * 所以由**唯一持有 context 的 EntryAbility** 注入实现，AppWiring 不介入。
   */
  private abilityStarter: (abilityName: string) => void = (abilityName: string): void => {
    hilog.warn(0x0000, 'MainActivity',
      'abilityStarter 未注入: %{public}s；后果：设置页打不开（点抽屉设置项无反应）', abilityName);
  };

  setAbilityStarter(starter: (abilityName: string) => void): void {
    this.abilityStarter = starter;
  }

  /** 抽屉选中：按 id 路由到对应场景（上游 onNavigationItemSelected） */
  onDrawerItemSelected(id: number): void {
    let sceneName: string = '';
    let action: string = '';
    switch (id) {
      case MainActivity.DRAWER_HOMEPAGE: sceneName = 'GalleryListScene'; action = 'action_homepage'; break;
      case MainActivity.DRAWER_SUBSCRIPTION: sceneName = 'GalleryListScene'; action = 'action_subscription'; break;
      case MainActivity.DRAWER_WHATS_HOT: sceneName = 'GalleryListScene'; action = 'action_whats_hot'; break;
      case MainActivity.DRAWER_TOP_LIST: sceneName = 'GalleryListScene'; action = 'action_top_list'; break;
      case MainActivity.DRAWER_FAVORITES: sceneName = 'FavoritesScene'; break;
      case MainActivity.DRAWER_HISTORY: sceneName = 'HistoryScene'; break;
      case MainActivity.DRAWER_DOWNLOADS: sceneName = 'DownloadsScene'; break;
      case MainActivity.DRAWER_SETTINGS:
        // 上游是 startActivity(SettingsActivity)：Activity 不进 Scene 注册表，走注入的能力
        this.abilityStarter('SettingsAbility');
        return;
      default: return;
    }
    const args: SceneArgs = new Map<string, Object>();
    if (action.length > 0) {
      args.set('action', action);
    }
    this.startScene(new Announcer(sceneName).setArgs(args));
  }

  /** 上游快速搜索栏：打开 SearchBar 浮层，由 ui-widget 的 SearchBar 承接 IME 提交 */
  protected quickSearchOpen: boolean = false;

  openQuickSearch(): void {
    this.quickSearchOpen = true;
  }

  closeQuickSearch(): void {
    this.quickSearchOpen = false;
  }

  isQuickSearchOpen(): boolean {
    return this.quickSearchOpen;
  }

  /**
   * 主题/夜间模式切换（上游 EhActivity.shouldSwitchTheme + getThemeResId）。
   * ArkUI 侧由 ApplicationContext.setColorMode 承担；本方法只做状态与回调，不直接改系统设置。
   */
  protected darkMode: boolean = false;

  toggleDarkMode(): void {
    this.darkMode = !this.darkMode;
    this.onColorModeChanged(this.darkMode);
  }

  isDarkMode(): boolean {
    return this.darkMode;
  }

  /** 子类/Ability 层覆盖：接 ApplicationContext.setColorMode(ColorMode.DARK/LIGHT) */
  protected onColorModeChanged(dark: boolean): void {
  }

  // ================================================================ Part 3

  /** 门场景的键（上游各 Scene 各有一份同名字符串，这里统一） */
  static readonly KEY_TARGET_SCENE: string = 'target_scene';
  static readonly KEY_TARGET_ARGS: string = 'target_args';
  /** 实例状态键（上游 `KEY_NAV_CHECKED_ITEM`） */
  static readonly KEY_NAV_CHECKED_ITEM: string = 'nav_checked_item';
  /** 设置页的 requestCode（上游 `REQUEST_CODE_SETTINGS = 0`） */
  static readonly REQUEST_CODE_SETTINGS: number = 0;
  /** 换头像的 requestCode（上游 `UserImageChange.TAKE_CAMERA` / `PICK_PHOTO`） */
  static readonly REQUEST_CODE_TAKE_CAMERA: number = 1;
  static readonly REQUEST_CODE_PICK_PHOTO: number = 2;
  /** `Activity.RESULT_OK` */
  static readonly RESULT_OK: number = -1;

  /**
   * 启动门链（上游 `getLaunchAnnouncer`）。
   *
   * **五道门按顺序 first-match，且返回的门场景不带 target**（因为还没有"原目标"）：
   *   Security（有安全码）→ Warning（未同意警告）→ Analytics（未答统计）→
   *   SignIn（需要登录）→ SelectSite（需要选站点）→ 列表（带 launchPage action）。
   *
   * ⚠️ Part 1 里这里写死 `action_homepage` 是简化版；上游取
   * `Settings.getLaunchPageGalleryListSceneAction()`（用户可设默认页）。
   */
  static launchAnnouncerFor(gates: StartupGates): Announcer {
    if (gates.hasSecurity) {
      return new Announcer('SecurityScene');
    }
    if (gates.showWarning) {
      return new Announcer('WarningScene');
    }
    // D-006: 鸿蒙版已永久跳过 AnalyticsScene
    if (gates.needSignedIn) {
      return new Announcer('SignInScene');
    }
    if (gates.selectSite) {
      return new Announcer('SelectSiteScene');
    }
    const args: SceneArgs = new Map<string, Object>();
    args.set('action', gates.launchPageAction);
    return new Announcer('GalleryListScene').setArgs(args);
  }

  static buildStartupGates(
    securityCode: string | null,
    securityUnlocked: boolean,
    showWarning: boolean,
    _askAnalytics: boolean,
    needSignedIn: boolean,
    selectSite: boolean,
    launchPageAction: string
  ): StartupGates {
    const hasSecurity: boolean = securityCode !== null && securityCode.length > 0 && !securityUnlocked;
    return new StartupGates(
      hasSecurity,
      showWarning,
      false,
      needSignedIn,
      selectSite,
      launchPageAction
    );
  }

  /**
   * 包装（上游 `processAnnouncer`）：**只有栈里一个场景都没有时才包装**。
   *
   * 与 `launchAnnouncerFor` 的差别（这是最容易写错的地方）：
   *   - 门**相同**、顺序**相同**；
   *   - 但每道门都把 `target_scene` / `target_args` 塞进**门场景的参数**里，
   *     这样门放行后能回到调用方本来想去的场景；
   *   - `launchAnnouncerFor` 的门**不带** target（没有原目标）。
   *
   * 为什么必须判 `sceneCount == 0`：上游注释 "Sometimes scene can't show directly" ——
   * 栈里已有场景时不包装，否则用户会看到"从列表点详情却先弹出锁屏"。
   */
  static processAnnouncer(announcer: Announcer, sceneCount: number,
    gates: StartupGates): Announcer {
    if (sceneCount !== 0) {
      return announcer;
    }
    const target: string = announcer.sceneName;
    if (gates.hasSecurity) {
      return MainActivity.wrapWithTarget('SecurityScene', target, announcer);
    }
    if (gates.showWarning) {
      return MainActivity.wrapWithTarget('WarningScene', target, announcer);
    }
    if (gates.needSignedIn) {
      return MainActivity.wrapWithTarget('SignInScene', target, announcer);
    }
    if (gates.selectSite) {
      return MainActivity.wrapWithTarget('SelectSiteScene', target, announcer);
    }
    return announcer;
  }

  /** 把目标场景塞进门场景的参数（上游那 5 段重复的 `newArgs.putString/putBundle`）。 */
  private static wrapWithTarget(gateScene: string, target: string, original: Announcer): Announcer {
    const args: SceneArgs = new Map<string, Object>();
    args.set(MainActivity.KEY_TARGET_SCENE, target);
    const originalArgs: SceneArgs | null = original.args;
    if (originalArgs !== null) {
      args.set(MainActivity.KEY_TARGET_ARGS, originalArgs);
    }
    return new Announcer(gateScene).setArgs(args);
  }

  /**
   * 意图分发（上游 `handleIntent`）。
   *
   * 三条都返回"要进哪个场景"，调用方再套 `processAnnouncer`：
   *   - `ACTION_VIEW` + url → `EhUrlOpener.parseUrl` 的结果（null = 解析失败，交给调用方处理）
   *   - `ACTION_SEND` + `text/plain` → 用 EXTRA_TEXT 当关键词进列表
   *   - `ACTION_SEND` + `image/*` → 存临时文件后进**图搜**（`MODE_IMAGE_SEARCH` + 相似搜索 + 含已删除）
   */
  static intentTargetFor(intent: IntentSummaryLike | null): IntentTarget {
    if (intent === null) {
      return new IntentTarget(IntentTargetKind.NONE, null, '', false);
    }
    if (intent.action === 'android.intent.action.VIEW') {
      if (intent.uri === null) {
        return new IntentTarget(IntentTargetKind.NONE, null, '', false);
      }
      return new IntentTarget(IntentTargetKind.URL, intent.uri, '', false);
    }
    if (intent.action === 'android.intent.action.SEND') {
      if (intent.type === 'text/plain') {
        const text: string = intent.extraText === null ? '' : intent.extraText;
        return new IntentTarget(IntentTargetKind.KEYWORD, null, text, false);
      }
      if (intent.type !== null && intent.type.startsWith('image/')) {
        const hasStream: boolean = intent.extraStream !== null;
        return new IntentTarget(IntentTargetKind.IMAGE_SEARCH, intent.extraStream, '', hasStream);
      }
    }
    return new IntentTarget(IntentTargetKind.NONE, null, '', false);
  }

  /** 图搜的列表参数（上游 `ListUrlBuilder` 的三个 setter，逐项断言）。 */
  static imageSearchArgsOf(imagePath: string): SceneArgs {
    const args: SceneArgs = new Map<string, Object>();
    args.set('mode', 1);              // ListUrlBuilder.MODE_IMAGE_SEARCH
    args.set('image_path', imagePath);
    args.set('use_similarity_scan', true);
    args.set('show_expunged', true);
    return args;
  }

  /**
   * 无法识别的意图（上游 `onUnrecognizedIntent`）。
   *
   * 两处**反直觉**的行为：
   *   ① 栈顶是 **SolidScene** → **直接丢弃 intent**（上游注释 "TODO the intent lost"）——
   *      SolidScene 是"必须处理完才能走"的场景（锁屏/警告/登录），此时切场景会破坏它；
   *   ② `handleIntent` 失败且栈空：**是 ACTION_VIEW 就 finish**（URL 解析失败 → 关掉整个 Activity），
   *      否则进列表。注意 finish 的条件是"栈空**且**是 URL"，缺一不可。
   */
  static unrecognizedIntentPlan(topIsSolidScene: boolean, handled: boolean,
    isUrlIntent: boolean, sceneCount: number): UnrecognizedPlan {
    if (topIsSolidScene) {
      return new UnrecognizedPlan(UnrecognizedAction.DROP, false);
    }
    if (handled) {
      return new UnrecognizedPlan(UnrecognizedAction.NONE, false);
    }
    const shouldToast: boolean = isUrlIntent;
    if (sceneCount === 0) {
      if (isUrlIntent) {
        return new UnrecognizedPlan(UnrecognizedAction.FINISH, shouldToast);
      }
      return new UnrecognizedPlan(UnrecognizedAction.START_LIST, shouldToast);
    }
    return new UnrecognizedPlan(UnrecognizedAction.NONE, shouldToast);
  }

  /**
   * 返回键（上游 `onBackPressed`）：**抽屉开着先关抽屉**（左或右都算），否则交给场景栈。
   *
   * 这条容易漏：不判抽屉的话，用户开着抽屉按返回会直接退出场景（抽屉还悬在那里）。
   */
  static backActionFor(drawerOpen: boolean): BackAction {
    return drawerOpen ? BackAction.CLOSE_DRAWERS : BackAction.TO_SCENE_STACK;
  }

  /**
   * 抽屉选中（上游 `onNavigationItemSelected` 开头）：**已选中的项返回 false**。
   *
   * 上游注释 "Don't select twice" —— 返回 false 时 NavigationView **不关闭抽屉**，
   * 与"点了另一项"（返回 true 且关抽屉）是两种不同结果。
   */
  static shouldSelectNavItem(alreadyChecked: boolean): boolean {
    return !alreadyChecked;
  }

  /**
   * 设置导航选中项（上游 `setNavCheckedItem`）：`resId == 0` 时用 `nav_stub` 占位。
   *
   * 为什么要占位：`NavigationView` 没有"取消全部选中"的 API，传 0 会抛异常，
   * 上游用隐藏的 `nav_stub` 项当空选中。
   */
  static navStubFor(resId: number): string {
    return resId === 0 ? 'nav_stub' : `${resId}`;
  }

  /** 实例状态：只有这一个键（上游 `onSaveInstanceState` 用 PersistableBundle 版本）。 */
  static savedKeys(): string[] {
    return [MainActivity.KEY_NAV_CHECKED_ITEM];
  }

  /** 恢复（上游 `onRestore`）：只是一次 `getInt`，缺省 0。 */
  static navCheckedFromSaved(saved: number | null): number {
    return saved === null ? 0 : saved;
  }

  /**
   * `onCreate2` 的 `KEY_RESTART`（上游 `SplashActivity.KEY_RESTART`）：
   * **为 true 时把 savedInstanceState 置 null** ——
   * 重启（换主题/换语言）后绝不能恢复旧状态，否则界面还在旧语言/旧主题下。
   */
  static shouldDropSavedState(restart: boolean): boolean {
    return restart;
  }

  /**
   * Activity 结果回传（上游 `onActivityResult`）。
   *
   * 三条分支 + 一个"否则交给父类"：
   *   ① `REQUEST_CODE_SETTINGS`：**不论 resultCode** 都 return（OK 才 refreshTopScene）；
   *   ② 相机/相册 + `RESULT_OK` → `saveImageForResult`；
   *   ③ 其余 → `super.onActivityResult`（交给 StageActivity 分发场景结果）。
   */
  static activityResultPlan(requestCode: number, resultCode: number,
    hasUserImageChange: boolean): ActivityResultPlan {
    if (requestCode === MainActivity.REQUEST_CODE_SETTINGS) {
      return new ActivityResultPlan(ActivityResultAction.REFRESH_TOP_SCENE,
        resultCode === MainActivity.RESULT_OK);
    }
    if (resultCode === MainActivity.RESULT_OK
      && (requestCode === MainActivity.REQUEST_CODE_TAKE_CAMERA
        || requestCode === MainActivity.REQUEST_CODE_PICK_PHOTO) && hasUserImageChange) {
      return new ActivityResultPlan(ActivityResultAction.SAVE_USER_IMAGE, true);
    }
    return new ActivityResultPlan(ActivityResultAction.TO_SUPER, false);
  }
}

/** 启动门链的输入（全部来自 Settings / EhUtils，由调用方注入）。 */
export class StartupGates {
  hasSecurity: boolean = false;
  showWarning: boolean = false;
  askAnalytics: boolean = false;
  needSignedIn: boolean = false;
  selectSite: boolean = false;
  /** 上游 `Settings.getLaunchPageGalleryListSceneAction()` */
  launchPageAction: string = 'action_homepage';

  constructor(hasSecurity: boolean, showWarning: boolean, askAnalytics: boolean,
    needSignedIn: boolean, selectSite: boolean, launchPageAction: string) {
    this.hasSecurity = hasSecurity;
    this.showWarning = showWarning;
    this.askAnalytics = askAnalytics;
    this.needSignedIn = needSignedIn;
    this.selectSite = selectSite;
    this.launchPageAction = launchPageAction;
  }
}

/** 意图投影（只取 `handleIntent` 用到的字段）。 */
export class IntentSummaryLike {
  action: string | null = null;
  uri: string | null = null;
  type: string | null = null;
  extraText: string | null = null;
  extraStream: string | null = null;

  constructor(action: string | null, uri: string | null, type: string | null,
    extraText: string | null, extraStream: string | null) {
    this.action = action;
    this.uri = uri;
    this.type = type;
    this.extraText = extraText;
    this.extraStream = extraStream;
  }
}

/** 意图要进哪类目标。 */
export enum IntentTargetKind {
  NONE = 0,
  URL = 1,
  KEYWORD = 2,
  IMAGE_SEARCH = 3
}

export class IntentTarget {
  kind: IntentTargetKind = IntentTargetKind.NONE;
  /** URL 的原始 url / 图搜的 uri */
  uri: string | null = null;
  /** 关键词 */
  keyword: string = '';
  /** 图搜是否带 stream（决定能否继续） */
  hasStream: boolean = false;

  constructor(kind: IntentTargetKind, uri: string | null, keyword: string, hasStream: boolean) {
    this.kind = kind;
    this.uri = uri;
    this.keyword = keyword;
    this.hasStream = hasStream;
  }
}

/** 无法识别意图后的动作。 */
export enum UnrecognizedAction {
  NONE = 0,
  /** 丢弃（栈顶是 SolidScene） */
  DROP = 1,
  /** 结束整个 Activity */
  FINISH = 2,
  /** 进列表 */
  START_LIST = 3
}

export class UnrecognizedPlan {
  action: UnrecognizedAction = UnrecognizedAction.NONE;
  toastParseError: boolean = false;

  constructor(action: UnrecognizedAction, toastParseError: boolean) {
    this.action = action;
    this.toastParseError = toastParseError;
  }
}

/** 返回键动作。 */
export enum BackAction {
  CLOSE_DRAWERS = 0,
  TO_SCENE_STACK = 1
}

/** Activity 结果动作。 */
export enum ActivityResultAction {
  REFRESH_TOP_SCENE = 0,
  SAVE_USER_IMAGE = 1,
  TO_SUPER = 2
}

export class ActivityResultPlan {
  action: ActivityResultAction = ActivityResultAction.TO_SUPER;
  /** 设置页：是否真的刷新（resultCode == RESULT_OK） */
  shouldRefresh: boolean = false;

  constructor(action: ActivityResultAction, shouldRefresh: boolean) {
    this.action = action;
    this.shouldRefresh = shouldRefresh;
  }
}
