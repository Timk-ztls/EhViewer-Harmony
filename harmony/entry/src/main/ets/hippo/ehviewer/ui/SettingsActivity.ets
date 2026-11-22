/*
 * 上游：app/src/main/java/com/hippo/ehviewer/ui/SettingsActivity.java（inventory S0270，105 行）
 * 目标：harmony/entry/src/main/ets/hippo/ehviewer/ui/SettingsActivity.ets
 *
 * 背景：设置页的**宿主**（Activity）。它自己几乎没有业务逻辑，做四件事：
 *   ① 按主题选样式  ② 设置返回箭头 + 标题"设置"  ③ 首屏挂 `SettingsHeaders`  ④ 处理子页回传的 result
 *
 * ── 上游行为逐条对照 ────────────────────────────────────────────────────────
 * `public final class SettingsActivity extends EhActivity`
 *   `static final int REQUEST_CODE_FRAGMENT = 0`
 *   `getThemeResId(theme)`:
 *       `Settings.THEME_LIGHT`(default) → `R.style.AppTheme_Settings`
 *       `Settings.THEME_DARK`           → `R.style.AppTheme_Settings_Dark`
 *       `Settings.THEME_BLACK`          → `R.style.AppTheme_Settings_Black`
 *   `setActionBarUpIndicator(drawable)`:
 *       ① `delegate = getDrawerToggleDelegate()`；非空 → `delegate.setActionBarUpIndicator(drawable, 0)`
 *       ② `actionBar = getSupportActionBar()`；非空 → `setDisplayHomeAsUpEnabled(true)` +
 *          `setHomeButtonEnabled(true)` + `setTitle(@string/settings)`
 *   `onCreate(savedInstanceState)`:
 *       `super.onCreate()` → `setContentView(R.layout.activity_settings)`
 *       → `setActionBarUpIndicator(DrawableManager.getVectorDrawable(this, @drawable/v_arrow_left_dark_x24))`
 *       → `if (savedInstanceState == null)` 用 FragmentManager `replace(R.id.settings, new SettingsHeaders())`
 *   `onOptionsItemSelected(item)`:
 *       `android.R.id.home` → `getOnBackPressedDispatcher().onBackPressed(); return true`
 *       其它 → `return super.onOptionsItemSelected(item)`
 *   `onActivityResult(requestCode, resultCode, data)`:
 *       `requestCode == REQUEST_CODE_FRAGMENT(0)`：
 *           `resultCode == RESULT_OK` → `setResult(RESULT_OK)`（**把结果原样上抛给调用方**）
 *           否则**什么都不做**（注意：也不调 super，见「关键行为」2）
 *       其它 `requestCode` → `super.onActivityResult(...)`
 *   `setSettingsTitle(int res)` / `setSettingsTitle(CharSequence res)`:
 *       `getSupportActionBar() != null` → `actionBar.setTitle(x); return;`
 *       否则 → `setTitle(x)`
 *
 * ── 关键行为（照搬，别"顺手修"）──────────────────────────────────────────────
 * 1. **`setSettingsTitle` 有两个重载**（`int` 资源 id / `CharSequence` 文本），
 *    且都是"先试 ActionBar、没有再退到 Activity 标题" —— 两条路径**结果一样**，
 *    只是作用对象不同。本实现用 `titleIsResource: boolean` 区分（见「平台差异」3）。
 * 2. `onActivityResult` 里 `requestCode == 0` 且 `resultCode != RESULT_OK` 时**既不做任何事、也不调 super**
 *    —— 与 `else` 分支（调 super）不对称。这是上游原样，照搬。
 * 3. `onCreate` 里 `savedInstanceState == null` 才挂 `SettingsHeaders`：**重建（如旋转）时不重挂**，
 *    避免与已恢复的 Fragment 状态冲突。本实现用 `firstCreate` 参数保留。
 * 4. `onOptionsItemSelected` 对 `home` 返回 **true**（已消费）；其它走 super。
 *
 * ── 平台差异 ────────────────────────────────────────────────────────────────
 * 1. **`extends EhActivity`**：`EhActivity` 在本仓库**尚未落地**（gl-render S0196 在做）。
 *    硬等会一直阻塞。因此按**依赖倒置**：本文件声明它实际用到的四个能力为接口 `EhActivityHost`
 *    （`getDrawerToggleDelegate` 的等价 `setActionBarUpIndicator`、`setTitle`、`onBackPressed`、
 *    `setResult`），`EhActivity` 落地后 `implements` 即可接入。
 *    —— 与 `GalleryUpdateDialog` 的 `GalleryDetailSceneHost`、Lead 的 `PageImageDownloader` 同一做法。
 * 2. **`R.style.AppTheme_Settings*` 在 ArkUI 不存在**：主题是 `AbilityStage`/窗口级配置。
 *    `getThemeResId` 的语义保留为**纯函数**：theme 常量 → 主题名字符串（`'AppTheme_Settings'` 等），
 *    由宿主在启动时消费。这样它是**可断言的纯逻辑**（见测试）。
 * 3. `setTitle(int res)` 与 `setTitle(CharSequence)` 在 ArkTS 里都是 `string`（`$r(...)` 返回 Resource），
 *    所以统一成 `setSettingsTitle(title: string, isResource: boolean)`。
 * 4. `setContentView(R.layout.activity_settings)` + `replace(R.id.settings, new SettingsHeaders())`
 *    → 产出**首屏构建描述** `SettingsScreenSpec`（布局名 + 首屏 header 表），由页面组件渲染。
 * 5. `DrawableManager.getVectorDrawable(this, @drawable/v_arrow_left_dark_x24)`
 *    → 存**组件名** `'v_arrow_left_dark_x24'`（本仓库 drawable 已迁成组件，实测存在）。
 *
 * ── 关联 ────────────────────────────────────────────────────────────────────
 * - 首屏：`SettingsHeaders`（S0207，同批移植；6 个分组入口 + 资源键已补齐）
 * - 主题常量：`Settings.THEME_LIGHT/DARK/BLACK`（core-runtime 的 Settings.ets）
 * - 资源：`@string/settings`（已补进 string.json）、图标组件 `v_arrow_left_dark_x24`（已存在）
 */

import { SettingsHeaders, SettingsHeader, SETTINGS_HEADERS } from './fragment/SettingsHeaders';

/** 上游 `Settings.THEME_*` 常量（core-runtime 的 Settings.ets 同值；此处直接引用其数值语义） */
export const THEME_LIGHT: number = 0;
export const THEME_DARK: number = 1;
export const THEME_BLACK: number = 2;

/** 上游 `R.style.AppTheme_Settings*` 的主题名（ArkUI 侧作为窗口/页面主题键，见「平台差异」2） */
export const STYLE_SETTINGS: string = 'AppTheme_Settings';
export const STYLE_SETTINGS_DARK: string = 'AppTheme_Settings_Dark';
export const STYLE_SETTINGS_BLACK: string = 'AppTheme_Settings_Black';

/** 上游 `REQUEST_CODE_FRAGMENT = 0` */
export const REQUEST_CODE_FRAGMENT: number = 0;
/** 上游 `RESULT_OK`（Android `Activity.RESULT_OK = -1`） */
export const RESULT_OK: number = -1;

/**
 * 本 Activity 对 `EhActivity` 的最小依赖（依赖倒置，见文件头「平台差异」1）。
 * `EhActivity` 落地后 `implements EhActivityHost` 即可接入。
 */
export interface EhActivityHost {
  /** 上游 `getDrawerToggleDelegate().setActionBarUpIndicator(drawable, 0)` */
  setActionBarUpIndicator(drawableComponent: string, descriptionRes: number): void;
  /** 上游 `getSupportActionBar().setTitle(x)` / `setTitle(x)` */
  setTitle(title: string, isResource: boolean): void;
  /** 上游 `getOnBackPressedDispatcher().onBackPressed()` */
  onBackPressed(): void;
  /** 上游 `setResult(RESULT_OK)` */
  setResult(resultCode: number): void;
}

/** 首屏构建描述（上游 `setContentView` + `replace(R.id.settings, new SettingsHeaders())`） */
export class SettingsScreenSpec {
  /** 上游 `R.layout.activity_settings` */
  layoutName: string = 'activity_settings';
  /** 首屏挂的 header 表（上游 `new SettingsHeaders()` 展开的 6 项） */
  headers: SettingsHeader[] = SETTINGS_HEADERS;
  /** 上游 `setActionBarUpIndicator(... @drawable/v_arrow_left_dark_x24)` */
  upIndicatorComponent: string = 'v_arrow_left_dark_x24';
  /** 上游 `setTitle(@string/settings)` */
  titleKey: string = 'app.string.settings';
}

export class SettingsActivity {
  private host: EhActivityHost;
  /** 上游 `savedInstanceState == null` 的等价物：只有首次创建才挂首屏 */
  private headersAttached: boolean = false;

  constructor(host: EhActivityHost) {
    this.host = host;
  }

  /**
   * 上游 `getThemeResId(int theme)` —— **纯函数**（见「平台差异」2）。
   * `default:` 分支与 `THEME_LIGHT` 同值，所以未知主题也返回 `AppTheme_Settings`（上游如此）。
   */
  getThemeResId(theme: number): string {
    switch (theme) {
      case THEME_DARK:
        return STYLE_SETTINGS_DARK;
      case THEME_BLACK:
        return STYLE_SETTINGS_BLACK;
      case THEME_LIGHT:
      default:
        return STYLE_SETTINGS;
    }
  }

  /**
   * 上游 `setActionBarUpIndicator(drawable)`：
   * ① delegate 非空才设置 up indicator ② actionBar 非空才设 homeAsUp/home 按钮/标题。
   * ArkUI 侧 ① 是 host 的 `setActionBarUpIndicator`，② 的标题走 `setSettingsTitle`。
   */
  setActionBarUpIndicator(drawableComponent: string): void {
    // 上游 ①：delegate != null → setActionBarUpIndicator(drawable, 0)（0 = 无描述资源的等价）
    this.host.setActionBarUpIndicator(drawableComponent, 0);
    // 上游 ②：actionBar != null → setDisplayHomeAsUpEnabled(true) + setHomeButtonEnabled(true) + setTitle(settings)
    // ArkUI 没有 ActionBar 对象；title 通过 setSettingsTitle 设置（资源键形式）
    this.setSettingsTitle('app.string.settings', true);
  }

  /**
   * 上游 `onCreate(savedInstanceState)`。
   * @param firstCreate 等价 `savedInstanceState == null`（true = 首次创建，才挂首屏）
   */
  onCreate(firstCreate: boolean): SettingsScreenSpec {
    const spec = new SettingsScreenSpec();
    // 上游：setContentView(R.layout.activity_settings)
    spec.layoutName = 'activity_settings';
    // 上游：setActionBarUpIndicator(DrawableManager.getVectorDrawable(this, @drawable/v_arrow_left_dark_x24))
    spec.upIndicatorComponent = 'v_arrow_left_dark_x24';
    this.setActionBarUpIndicator(spec.upIndicatorComponent);
    // 上游：if (savedInstanceState == null) → replace(R.id.settings, new SettingsHeaders())
    if (firstCreate) {
      const headers: SettingsHeaders = new SettingsHeaders(this);
      spec.headers = headers.onCreatePreferences();
      this.headersAttached = true;
    } else {
      spec.headers = SETTINGS_HEADERS;   // 重建时不重挂（见「关键行为」3），但仍渲染表
    }
    return spec;
  }

  /** 上游 `onOptionsItemSelected(item)`：`home` → onBackPressed + true；其它 → super（这里返回 false） */
  onOptionsItemSelected(itemId: string): boolean {
    if (itemId === 'android.R.id.home') {
      this.host.onBackPressed();
      return true;
    }
    return false;
  }

  /**
   * 上游 `onActivityResult(requestCode, resultCode, data)`：
   * `requestCode == 0` 时：`RESULT_OK` → 上抛 `setResult(RESULT_OK)`；
   * **否则什么都不做、也不调 super**（见「关键行为」2）。
   * 其它 requestCode → super（这里返回 false 表示"已交给父类"）。
   *
   * @returns true = 本类已处理（requestCode == 0）；false = 交给父类
   */
  onActivityResult(requestCode: number, resultCode: number): boolean {
    if (requestCode === REQUEST_CODE_FRAGMENT) {
      if (resultCode === RESULT_OK) {
        this.host.setResult(RESULT_OK);
      }
      return true;   // 上游 requestCode==0 分支**不调 super**
    }
    return false;    // 上游 else 分支调 super
  }

  /**
   * 上游两个 `setSettingsTitle` 重载（`int res` / `CharSequence`）：
   * 共同语义 —— **先试 ActionBar，没有再退到 Activity 标题**。
   * @param title 资源键（`app.string.x`）或纯文本
   * @param isResource true = 上游的 `int res` 重载；false = `CharSequence` 重载
   */
  setSettingsTitle(title: string, isResource: boolean): void {
    // 上游：if (getSupportActionBar() != null) { actionBar.setTitle(x); return; }
    // ArkUI 无 ActionBar 对象 → host 内部决定作用对象；两条路径结果相同（见「关键行为」1）
    this.host.setTitle(title, isResource);
  }

  /** 首屏是否已挂（上游 Fragment 是否已 replace） —— 便于测试观测 */
  isHeadersAttached(): boolean {
    return this.headersAttached;
  }
}
