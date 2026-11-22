/*
 * 上游：app/src/main/java/com/hippo/ehviewer/ui/splash/SplashActivity.kt（inventory S0271，76 行）
 * 目标：harmony/entry/src/main/ets/hippo/ehviewer/ui/splash/SplashActivity.ets
 *
 * 背景：**启动页**。它做三件事：
 *   ① 用 `SplashTheme` 显示 `splash_layout`
 *   ② 起一个后台线程做"耗时任务"，完成后**回主线程**跳到 `MainActivity` 并 `finish()` 自己
 *   ③ 若 `!openNews && Settings.getShowEhEvents()` → 拉 EH 新闻（`METHOD_GET_NEWS`），成功则 `showEventPane`
 *
 * ── 上游行为逐条对照 ────────────────────────────────────────────────────────
 * `class SplashActivity : EhActivity()`
 *   字段：`signNewsListener = SignNewsListener()` / `checkUpdate = false` / `openNews = false`
 *   `getThemeResId(theme)` → **`R.style.SplashTheme`**（注意：**不看 theme 参数**，恒定返回启动主题）
 *   `onCreate(savedInstanceState)`:
 *     ① 前 8 行全被注释（AppCenter/Distribute 自更新，见 D-006）→ **不搬**
 *     ② `super.onCreate(savedInstanceState)` → `setContentView(R.layout.splash_layout)`
 *     ③ `Thread(Runnable { ... runOnUiThread(Runnable { ... }) }).start()`
 *        —— 后台线程做耗时任务，**回主线程**再跳转（跳转必须在主线程）
 *     ④ 跳转逻辑：`restart = intent.getBooleanExtra(KEY_RESTART, false)`
 *        → `Intent(MainActivity)`；`restart` 为真时加 `FLAG_ACTIVITY_NEW_TASK | FLAG_ACTIVITY_CLEAR_TASK`
 *          并把 `KEY_RESTART=true` 透传下去
 *        → `startActivity(intent)` → **`finish()` 自己**
 *     ⑤ `if (!openNews && Settings.getShowEhEvents()) signInNews()`
 *   `signInNews()`：`EhRequest().setMethod(METHOD_GET_NEWS).setArgs(EhUrl.getEhNewsUrl()).setCallback(signNewsListener)`
 *                   → `EhApplication.getEhClient(context).execute(request)`
 *   内部类 `SignNewsListener : EhClient.Callback<EhNewsDetail?>`：
 *     `onSuccess(result)` → `openNews = true`；`result == null` **return**；否则 `showEventPane(result)`
 *     `onFailure(e)`      → `openNews = true`
 *     `onCancel()`        → `openNews = true`
 *   `companion object { const val KEY_RESTART = "restart" }`
 *
 * ── 关键行为（照搬，别"顺手修"）──────────────────────────────────────────────
 * 1. **`getThemeResId(theme)` 忽略参数**，恒返回 `SplashTheme` —— 启动页永远是启动主题，
 *    不跟随用户深浅色。改成"跟随主题"会改变首屏观感。
 * 2. **三条回调都把 `openNews = true`**（成功/失败/取消）—— 它是"已尝试过"标记，
 *    不是"成功"标记。所以失败后**不会重试**（上游如此）。
 * 3. `onSuccess` 里 `if (result == null) return` **在 `openNews = true` 之后** → 即使 null 也算"已尝试"。
 * 4. **`finish()` 在 Fi 跳转之后立刻调用** —— 启动页不进返回栈（鸿蒙侧等价 `router.replaceUrl`，
 *    而不是 `pushUrl`；用 push 会导致返回键回到启动页）。
 * 5. `openNews` 与 `checkUpdate` 都是**实例字段**（每次新建 SplashActivity 都重置）。
 *
 * ── 平台差异 ────────────────────────────────────────────────────────────────
 * 1. **`Thread(...).start()` + `runOnUiThread(...)`**：鸿蒙用 `taskpool`/`setTimeout` + UI 线程回调。
 *    本实现**不自己起线程**，而是把"耗时任务完成后调用哪个回调"暴露成 `scheduleNavigate(done)`：
 *    调用方传一个"执行耗时任务并在主线程回调"的调度器（`PageScheduler` 接口），
 *    ArkUI 侧用 `setTimeout`/`taskpool` 实现。**这样跳转顺序（后台→主线程→跳转→finish）被保留且可测**。
 * 2. **`Intent` + `FLAG_ACTIVITY_NEW_TASK | CLEAR_TASK`**：鸿蒙用 `router.replaceUrl`（等价"清栈跳转"）。
 *    本实现产出 `SplashNavigation`（目标页 + 是否清栈 + 是否透传 restart），由页面层执行路由。
 * 3. **`EhActivity` 已交付**（gl-render S0196），但它是 `class` 且方法为 `static`（D-051：页面注册表 +
 *    纯函数），**没有可继承的实例生命周期**。故本实现是"组合 + 注册"：`onCreate` 时
 *    `EhActivity.registerPage('splash')`、`onDestroy` 时 `unregisterPage('splash')`，
 *    与 D-051 的页面注册表契约一致（清零时不影响其它页面）。
 * 4. `EhRequest` / `EhClient.execute` 的完整链路未落地到可直调形态 → 新闻拉取走**依赖注入**：
 *    `NewsFetcher` 接口（`fetch(callback)`），由调用方接 `EhRequestBuilder`。**不 import 未接通链路。**
 * 5. `EhApplication.getShowEhEvents()` / `showEventPane()`：前者已有（`EhApplication.shouldShowEventPane`），
 *    后者在 ArkUI 是 AlertDialog（ui-widget）→ 同样走注入（`showEventPane` 回调）。
 *
 * ── 关联 ────────────────────────────────────────────────────────────────────
 * - 宿主基类：`hippo/ehviewer/ui/EhActivity.ets`（D-051：`registerPage` / `unregisterPage` / 纯函数主题）
 * - 布局：`hippo/ui/layout/splash_layout.ets`（已存在）
 * - 数据：`hippo/ehviewer/client/data/EhNewsDetail.ets`；`EhClient.METHOD_GET_NEWS`；`EhEngine.getEhNewsUrl()`
 * - 上游被注释的自更新（AppCenter/Distribute）→ **D-006 删除**，不搬
 */

import { EhActivity } from '../EhActivity';
import { EhNewsDetail } from '../../client/data/EhNewsDetail';

/** 上游 `companion object { const val KEY_RESTART = "restart" }` */
export const KEY_RESTART: string = 'restart';
/** 本页在 D-051 页面注册表里的 id */
export const SPLASH_PAGE_ID: string = 'splash';
/** 上游 `R.style.SplashTheme`（启动页恒定主题，见「关键行为」1） */
export const STYLE_SPLASH: string = 'SplashTheme';

/**
 * 调度器：等价上游 `Thread(Runnable { ... runOnUiThread { ... } }).start()`。
 * 实现方负责"在后台做耗时任务、然后回 UI 线程调用 done"。
 */
export interface PageScheduler {
  runThenOnUiThread(work: () => void, done: () => void): void;
}

/** 新闻拉取（等价上游 `EhRequest().setMethod(METHOD_GET_NEWS)...execute(request)`） */
export interface NewsFetcher {
  fetch(callback: NewsCallback): void;
}

/** 上游 `EhClient.Callback<EhNewsDetail?>` 的三个回调 */
export interface NewsCallback {
  onSuccess(result: EhNewsDetail | null): void;
  onFailure(error: Error): void;
  onCancel(): void;
}

/** 上游 `showEventPane(result)`（ArkUI 侧是 AlertDialog，由 ui-widget 提供） */
export interface EventPaneShower {
  showEventPane(detail: EhNewsDetail): void;
}

/** 路由跳转描述（等价上游 `Intent(MainActivity)` + flags） */
export class SplashNavigation {
  /** 目标页（上游 `MainActivity`） */
  targetPage: string = 'MainActivity';
  /** 是否"清栈跳转"（上游 `FLAG_ACTIVITY_NEW_TASK | FLAG_ACTIVITY_CLEAR_TASK`） */
  clearTask: boolean = false;
  /** 是否把 `KEY_RESTART=true` 透传下去（上游 `putExtra(KEY_RESTART, true)`） */
  passRestart: boolean = false;
  /** 上游跳转后立刻 `finish()` —— 鸿蒙等价 `router.replaceUrl`（见「关键行为」4） */
  finishSelf: boolean = true;
}

/** 上游 `intent.getBooleanExtra(KEY_RESTART, false)` 的等价入参 */
export class SplashParams {
  restart: boolean = false;

  constructor(restart: boolean = false) {
    this.restart = restart;
  }
}

export class SplashActivity {
  /** 上游 `private var checkUpdate = false`（AppCenter 已删，保留字段语义但不再使用） */
  private checkUpdate: boolean = false;
  /** 上游 `private var openNews = false` —— "已尝试过"标记，不是"成功"标记（见「关键行为」2） */
  private openNews: boolean = false;
  private newsFetcher: NewsFetcher;
  private eventPane: EventPaneShower;

  constructor(newsFetcher: NewsFetcher, eventPane: EventPaneShower) {
    this.newsFetcher = newsFetcher;
    this.eventPane = eventPane;
  }

  /** 上游 `getThemeResId(theme)` → **恒返回 `SplashTheme`，忽略参数**（见「关键行为」1） */
  getThemeResId(theme: number): string {
    return STYLE_SPLASH;
  }

  /**
   * 上游 `onCreate(savedInstanceState)` 的等价：
   * ① 注册页面（D-051）② 挂布局名 ③ 调度"耗时任务 → 主线程 → 跳转 + finish"
   * ④ 若未尝试过且允许显示事件 → 拉新闻
   */
  onCreate(params: SplashParams, scheduler: PageScheduler): SplashNavigation {
    // 上游：super.onCreate(...) —— 本实现用 D-051 的页面注册代替
    EhActivity.registerPage(SPLASH_PAGE_ID);

    // 上游：setContentView(R.layout.splash_layout) —— 由页面层渲染 layoutName
    const nav: SplashNavigation = new SplashNavigation();

    // 上游：Thread{ ... runOnUiThread { 跳转 + finish } }.start()
    // 后台做耗时任务的**内容**上游没写（空 Runnable），这里同样不做业务，只保留调度顺序
    scheduler.runThenOnUiThread(() => {
      // 等价"耗时任务"阶段：上游此处为空（真正的加载在 MainActivity 里）
    }, () => {
      // 上游：val restart = intent.getBooleanExtra(KEY_RESTART, false)
      const restart: boolean = params.restart;
      nav.targetPage = 'MainActivity';
      if (restart) {
        // 上游：FLAG_ACTIVITY_NEW_TASK or FLAG_ACTIVITY_CLEAR_TASK + putExtra(KEY_RESTART, true)
        nav.clearTask = true;
        nav.passRestart = true;
      }
      // 上游：startActivity(intent); finish()
      nav.finishSelf = true;
      this.navigated = true;
    });

    // 上游：if (!openNews && Settings.getShowEhEvents()) signInNews()
    if (!this.openNews && isShowEhEventsEnabled()) {
      this.signInNews();
    }
    return nav;
  }

  /** 上游 `signInNews()` */
  private signInNews(): void {
    // 注意：ArkTS 禁止"对象字面量当接口实现"（arkts-no-untyped-obj-literals），
    // 即使写了类型注解也会被拒 —— 必须用**显式声明类**实现接口。这是 ArkTS 与 TypeScript 的硬差异。
    this.newsFetcher.fetch(new SplashNewsCallback(this, this.eventPane));
  }

  /** 供 `SplashNewsCallback` 置位（上游是内部类直接改外部字段） */
  markNewsAttempted(): void {
    this.openNews = true;
  }

  /** 上游 Activity 销毁 → D-051 注销页面 */
  onDestroy(): void {
    EhActivity.unregisterPage(SPLASH_PAGE_ID);
  }

  /** 是否"已尝试过拉新闻"（上游 `openNews`，便于测试观测） */
  isNewsAttempted(): boolean {
    return this.openNews;
  }

  /** 是否已完成跳转（上游 `startActivity` 之后的时点，便于测试观测） */
  isNavigated(): boolean {
    return this.navigated;
  }

  private navigated: boolean = false;
}

/**
 * 上游 `Settings.getShowEhEvents()` 的等价读取。
 * 单独提出来是为了**可替换**：测试里置 false 就能跳过新闻拉取，不必构造整个 Settings。
 */
let showEhEventsProvider: () => boolean = (): boolean => true;
/** 供宿主/测试注入（默认 true，与上游 Settings 默认一致） */
export function setShowEhEventsProvider(provider: () => boolean): void {
  showEhEventsProvider = provider;
}
function isShowEhEventsEnabled(): boolean {
  return showEhEventsProvider();
}


/**
 * 上游内部类 `SignNewsListener : EhClient.Callback<EhNewsDetail?>`。
 * **必须用显式类实现**（ArkTS 禁止"对象字面量当接口实现"，即使有类型注解 → `arkts-no-untyped-obj-literals`）。
 */
export class SplashNewsCallback implements NewsCallback {
  private owner: SplashActivity;
  private eventPane: EventPaneShower;

  constructor(owner: SplashActivity, eventPane: EventPaneShower) {
    this.owner = owner;
    this.eventPane = eventPane;
  }

  onSuccess(result: EhNewsDetail | null): void {
    // 上游：openNews = true；**再**判 null（顺序不能反，见「关键行为」3）
    this.owner.markNewsAttempted();
    if (result === null) {
      return;
    }
    this.eventPane.showEventPane(result);
  }

  onFailure(error: Error): void {
    this.owner.markNewsAttempted();   // 失败也算"已尝试"
  }

  onCancel(): void {
    this.owner.markNewsAttempted();   // 取消也算"已尝试"
  }
}
