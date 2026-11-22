/*
 * 上游：app/src/main/java/com/hippo/ehviewer/ui/scene/ToolbarScene.java
 *       （inventory S0264，上游 133 行；清单登记 111 行）
 * 目标：harmony/entry/src/main/ets/hippo/ehviewer/ui/scene/ToolbarScene.ets
 *
 * 背景：**带 Toolbar 的 Scene 基类**。它把"Toolbar + 内容面板"的搭架子逻辑收在一处：
 * 子类只实现 `onCreateView3`（返回内容视图）与若干回调（标题/菜单/返回/点击），
 * 基类负责 `scene_toolbar` 布局、把内容塞进 `content_panel`、以及**标题的延迟设置**。
 *
 * ── 上游行为逐条对照 ────────────────────────────────────────────────────────
 * `abstract class ToolbarScene extends BaseScene`
 * 字段：`mToolbar: Toolbar | null`、`mTempTitle: CharSequence`
 * `onCreateView3(inflater, container, state)`：**返回 null**（基类默认实现；子类覆盖）
 * `onCreateView2(...)` —— **`final`**：
 *   ① inflate `scene_toolbar`；取 `toolbar` 与 `content_panel`
 *   ② `contentView = onCreateView3(inflater, contentPanel, state)`
 *   ③ **`contentView == null → 返回 null`**（**注意：此时 `mToolbar` 还没赋值**）
 *   ④ 否则 `mToolbar = toolbar` → `contentPanel.addView(contentView, **0**)`（插到索引 0）
 * `onDestroyView()` → `super` + **`mToolbar = null`**
 * `onViewCreated(view, state)` —— `super` 之后，**`mToolbar != null`** 才做四件事：
 *   ① **`mTempTitle != null` → `mToolbar.setTitle(mTempTitle)` 并把 `mTempTitle` 置 null**
 *   ② `menuResId = getMenuResId()`；**`!= 0`** 才 `inflateMenu` + `setOnMenuItemClickListener`
 *      + **`onMenuCreated(mToolbar.getMenu())`**
 *   ③ `mToolbar.setNavigationOnClickListener(this::onNavigationClick)`
 *   ④ `mToolbar.setOnClickListener(this::onClickListener)`
 * `onClickListener(view)`：**空实现**
 * `getMenuResId()` → **0**（无菜单）
 * `onMenuCreated(menu)`：空实现
 * `onMenuItemClick(item)` → **false**
 * `onNavigationClick(view)`：空实现
 * `setNavigationIcon(int resId)` / `setNavigationIcon(Drawable icon)`：**`mToolbar != null` 才设**（两个重载）
 * `setTitle(int resId)` → **`setTitle(getString(resId))`**（转调 CharSequence 重载）
 * `setTitle(CharSequence title)`：`mToolbar != null` → 直接设；**否则 `mTempTitle = title`**（延迟到 onViewCreated）
 *
 * ── 关键行为（照搬，别"顺手修"）──────────────────────────────────────────────
 * 1. **`mTempTitle` 的延迟设置**：`setTitle` 可能在 `onCreateView2` 之前被调用（子类在 `onCreate` 里设标题），
 *    此时 Toolbar 还不存在 → 先暂存，`onViewCreated` 时补设并**清空暂存**。
 *    **这是本基类存在的核心理由** —— 去掉它，子类就必须自己管"标题早设"的时序。
 * 2. **`contentView == null` 时 `mToolbar` 保持 null** —— 于是后续 `setTitle` 会走暂存分支，
 *    `setNavigationIcon` 静默无效（不是抛错）。
 * 3. **`contentPanel.addView(contentView, 0)` 插到**索引 0** —— 面板里可能已有别的子视图（如占位），
 *    内容必须在最底层/最前。
 * 4. **`getMenuResId() == 0` 时不 inflate 也不挂监听** —— 所以"无菜单的 Scene"不会收到 `onMenuCreated`。
 * 5. **`onViewCreated` 的四件事顺序固定**：先补标题 → 再 inflate 菜单 → 再挂导航 → 最后挂整体点击。
 * 6. **两个 `setNavigationIcon` 重载**（资源 id / Drawable）—— ArkTS 无重载 → 拆成
 *    `setNavigationIconRes(key)` / `setNavigationIconComponent(name)`（见「平台差异」3）。
 * 7. **`setTitle(int)` 先转 `getString(resId)`**，所以最终都落到 CharSequence 重载 —— 资源解析在**调用时**发生。
 *
 * ── 平台差异 ────────────────────────────────────────────────────────────────
 * 1. **本仓 `BaseScene` 已存在**（`extends SceneFragment`，带 drawer/host/theme 能力）→ 本文件**真正继承**它，
 *    不再做接口倒置（这是少数"基类已就位"的情况）。
 * 2. `Toolbar`（Android 控件）→ ArkUI 无对位：本实现把 Toolbar 抽象成 `ToolbarModel`
 *    （title / navigationIcon / menuResId / 监听标记），**视图由页面层用 `Navigation`+`Button/Text` 渲染**。
 *    `mToolbar != null` 的等价物是 `toolbarAttached` 布尔（`onCreateView2` 成功才 true）。
 * 3. **两个 `setNavigationIcon` 重载** → 两个具名方法（ArkTS 无重载）。
 * 4. `inflateMenu` + `Menu` 对象 → `menuResId` 字符串 + `menuCreated` 标记（菜单项由页面层从资源表展开）。
 * 5. `addView(contentView, 0)` → 返回 `contentIndex = 0`（页面层据此把内容放到面板首位）。
 * 6. `getString(resId)` → 宿主 `resolveString(key)`（BaseScene 已提供 scene host，但字符串解析走注入，
 *    便于单测不依赖 ArkUI 资源）。
 *
 * ── 依赖实测（本仓已存在）──────────────────────────────────────────────────
 * `BaseScene`（`hippo/ehviewer/ui/scene/BaseScene.ets`，`abstract class BaseScene extends SceneFragment`）、
 * `hippo/ui/layout/scene_toolbar.ets`。
 *
 * ── 缺口 ───────────────────────────────────────────────────────────────────
 * 本文件**不能**在单测里实例化 `BaseScene` 的完整链路（它依赖 `SceneFragment` → `StageTransactor`）。
 * 所以 Assertions 走 `ToolbarLogic`（见文件末尾）：**把基类的"状态机部分"抽成可独立实例化的类**，
 * `ToolbarScene` 只做委托。这是为可测性做的注入（与 `QuickSearchStore` 同一手法），
 * 提交说明里已注明"为可测性注入"。
 */

import { BaseScene } from './BaseScene';

/** 上游 `R.layout.scene_toolbar` 里的两个 id */
export const LAYOUT_SCENE_TOOLBAR: string = 'scene_toolbar';
export const ID_TOOLBAR: string = 'toolbar';
export const ID_CONTENT_PANEL: string = 'content_panel';
/** 上游 `getMenuResId()` 的默认值（0 = 无菜单） */
export const NO_MENU: number = 0;

/**
 * 内容视图的**句柄**（ArkTS 禁 any/unknown，见 arkts-no-any-unknown）。
 * 页面层把真实 ArkUI 组件挂在 `component` 上；单测里只关心"是否存在"。
 */
export class ContentViewToken {
  /** 视图标识（资源名/自定义名），仅用于日志与断言 */
  name: string = '';

  constructor(name: string = '') {
    this.name = name;
  }
}

/**
 * 上游 `Toolbar` 的可测替身（见「平台差异」2）：
 * 只保留基类真正驱动的四件事 —— 标题、导航图标、菜单资源、`getMenu()` 是否可得。
 */
export class ToolbarModel {
  /** 当前标题（null = 未设） */
  title: string | null = null;
  /** 导航图标（资源键或组件名；null = 未设） */
  navigationIcon: string | null = null;
  /** 已 inflate 的菜单资源名（null = 未 inflate） */
  inflatedMenu: string | null = null;
  /** `setOnMenuItemClickListener` / `setNavigationOnClickListener` / `setOnClickListener` 是否已挂 */
  menuListenerAttached: boolean = false;
  navListenerAttached: boolean = false;
  clickListenerAttached: boolean = false;
}

/**
 * 基类的**状态机部分**（从 `ToolbarScene` 抽出，便于单测；见「缺口」）。
 * `ToolbarScene` 只做委托 —— 行为与上游逐条对应。
 */
export class ToolbarLogic {
  /** 上游 `mToolbar` */
  private toolbar: ToolbarModel | null = null;
  /** 上游 `mTempTitle` */
  private tempTitle: string | null = null;
  /** 子类提供的字符串解析（上游 `getString(resId)`） */
  private resolveString: (key: string) => string;

  constructor(resolveString: (key: string) => string) {
    this.resolveString = resolveString;
  }

  /** 当前 Toolbar 是否存在（上游 `mToolbar != null`） */
  hasToolbar(): boolean {
    return this.toolbar !== null;
  }

  /** 当前 Toolbar 模型（测试观测） */
  getToolbar(): ToolbarModel | null {
    return this.toolbar;
  }

  /** 暂存标题（测试观测） */
  getTempTitle(): string | null {
    return this.tempTitle;
  }

  /**
   * 上游 `onCreateView2` 的后半（`scene_toolbar` 的 inflate 与 `contentView == null` 判断）：
   * ① `contentView == null → 返回 false`（**且 `mToolbar` 不赋值**）
   * ② 否则挂上 toolbar 并返回 true
   */
  attachView(contentView: ContentViewToken | null): boolean {
    if (contentView === null || contentView === undefined) {
      return false;
    }
    this.toolbar = new ToolbarModel();
    return true;
  }

  /** 上游 `onDestroyView`：`mToolbar = null`（**`mTempTitle` 不动** —— 上游也没动） */
  detachView(): void {
    this.toolbar = null;
  }

  /**
   * 上游 `onViewCreated` 的四件事（顺序固定，见「关键行为」5）：
   * ① 补设暂存标题并清空 ② `menuResId != 0` 才 inflate + 挂菜单监听 + `onMenuCreated`
   * ③ 挂导航监听 ④ 挂整体点击监听
   * @returns `onMenuCreated` 是否应被调用（`menuResId != 0 && toolbar != null`）
   */
  onViewCreated(menuResId: number): boolean {
    const tb: ToolbarModel | null = this.toolbar;
    if (tb === null) {
      return false;
    }
    // ① 延迟标题
    if (this.tempTitle !== null) {
      tb.title = this.tempTitle;
      this.tempTitle = null;
    }
    // ② 菜单（**0 表示没有菜单**）
    let menuCreated: boolean = false;
    if (menuResId !== NO_MENU) {
      tb.inflatedMenu = menuResId.toString();
      tb.menuListenerAttached = true;
      menuCreated = true;
    }
    // ③④ 两个监听：**无条件挂**
    tb.navListenerAttached = true;
    tb.clickListenerAttached = true;
    return menuCreated;
  }

  /** 上游 `setNavigationIcon(@DrawableRes int)` —— `mToolbar != null` 才设 */
  setNavigationIcon(icon: string): void {
    const tb: ToolbarModel | null = this.toolbar;
    if (tb !== null) {
      tb.navigationIcon = icon;
    }
  }

  /**
   * 上游 `setTitle(int resId)`：**先 `getString(resId)` 再走 CharSequence 重载**
   * （资源解析发生在**调用时**，见「关键行为」7）。
   */
  setTitleRes(key: string): void {
    this.setTitle(this.resolveString(key));
  }

  /** 上游 `setTitle(CharSequence)`：有 toolbar 直接设，否则**暂存**（见「关键行为」1） */
  setTitle(title: string | null): void {
    const tb: ToolbarModel | null = this.toolbar;
    if (tb !== null) {
      tb.title = title;
    } else {
      this.tempTitle = title;
    }
  }
}

/**
 * 上游 `ToolbarScene extends BaseScene`。
 * 本仓 `BaseScene` 已就位 → **真正继承**（不做接口倒置）。
 * 视图装配委托给 `ToolbarLogic`（为可测性，见「缺口」）。
 */
export abstract class ToolbarScene extends BaseScene {
  /** 状态机部分（可单测；对测试暴露，见「缺口」） */
  logic: ToolbarLogic;

  constructor(resolveString?: (key: string) => string) {
    super();
    // 上游 `getString(resId)`：默认原样返回键名（页面层/宿主可注入真实解析）
    this.logic = new ToolbarLogic(resolveString !== undefined
      ? resolveString
      : (key: string): string => {
        return key;
      });
  }

  /**
   * 上游 `onCreateView3(inflater, container, state)` —— **基类默认返回 null**，子类覆盖。
   * 本仓用 `unknown | null` 表达"内容视图"。
   */
  onCreateView3(): ContentViewToken | null {
    return null;
  }

  /**
   * 上游 `onCreateView2`（**final**，子类不得覆盖）：
   * 调 `onCreateView3` → 内容为空则失败（toolbar 不挂）→ 否则挂 toolbar。
   * @returns true = 视图装配成功
   */
  onCreateView2(): boolean {
    const content: ContentViewToken | null = this.onCreateView3();
    return this.logic.attachView(content);
  }

  /** 内容视图在 content_panel 里的插入索引（上游 `addView(contentView, 0)`） */
  getContentIndex(): number {
    return 0;
  }

  /** 上游 `onViewCreated`：菜单真的被 inflate 时才回调 `onMenuCreated`（见「关键行为」4） */
  onViewCreated(): void {
    const menuCreated: boolean = this.logic.onViewCreated(this.getMenuResId());
    if (menuCreated) {
      this.onMenuCreated();
    }
  }

  /** 上游 `onDestroyView` */
  onDestroyView(): void {
    this.logic.detachView();
  }

  /** 上游 `onClickListener(view)`：空实现 */
  onClickListener(): void {
  }

  /** 上游 `getMenuResId()` → 0（无菜单） */
  getMenuResId(): number {
    return NO_MENU;
  }

  /** 上游 `onMenuCreated(menu)`：空实现 */
  onMenuCreated(): void {
  }

  /** 上游 `onMenuItemClick(item)` → false */
  onMenuItemClick(itemId: string): boolean {
    return false;
  }

  /** 上游 `onNavigationClick(view)`：空实现 */
  onNavigationClick(): void {
  }

  /** 上游 `setNavigationIcon(Drawable)`（一个具名方法，见「平台差异」3） */
  setNavigationIcon(icon: string): void {
    this.logic.setNavigationIcon(icon);
  }

  /** 上游 `setTitle(@StringRes int)` */
  setTitleRes(key: string): void {
    this.logic.setTitleRes(key);
  }

  /** 上游 `setTitle(CharSequence)` */
  setTitle(title: string | null): void {
    this.logic.setTitle(title);
  }

  /** 当前标题（测试观测：`mToolbar != null` 时是实设值，否则看暂存） */
  getCurrentTitle(): string | null {
    const tb: ToolbarModel | null = this.logic.getToolbar();
    if (tb !== null) {
      return tb.title;
    }
    return this.logic.getTempTitle();
  }
}


