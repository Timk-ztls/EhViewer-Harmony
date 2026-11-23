/*
 * 阶段 A 任务 B3：统一二级页面路由表与启动门槽位规范（P0~P4 接口隔离）。
 *
 * 约定：
 * 1. `REGISTERED_PAGES` 严格对应 `resources/base/profile/main_pages.json` 中已落盘的 `@Entry` 页面；
 *    `verify.ps1` / `hvigor` 构建要求 `main_pages.json` 不得登记磁盘上尚不存在的页面。
 * 2. `RESERVED_PHASE_B_PAGES` 为阶段 B 并行 Track P1~P4 预留统一 URL 与 `SettingsPage` /
 *    `MainPageHostView` 路由映射；未注册槽位在运行期由 `resolveNavigation()` 明确返回
 *    `RouteActionKind.UNREGISTERED` 并给出提示，不静默崩溃或盲目 `pushUrl`。
 */

/** 二级页面跳转决策动作 */
export enum RouteActionKind {
  PUSH = 'PUSH',
  REQUIRE_SIGN_IN = 'REQUIRE_SIGN_IN',
  UNREGISTERED = 'UNREGISTERED',
  UNKNOWN = 'UNKNOWN',
}

/** 单个页面路由槽位描述 */
export class PageRouteEntry {
  readonly url: string;
  readonly activityName: string;
  readonly track: string;
  readonly registered: boolean;
  readonly requiresSignIn: boolean;

  constructor(
    url: string,
    activityName: string,
    track: string,
    registered: boolean,
    requiresSignIn: boolean
  ) {
    this.url = url;
    this.activityName = activityName;
    this.track = track;
    this.registered = registered;
    this.requiresSignIn = requiresSignIn;
  }
}

/** 统一路由解析结果 */
export class RouteNavigationPlan {
  readonly kind: RouteActionKind;
  readonly entry: PageRouteEntry | null;
  readonly tipResKey: string;

  constructor(kind: RouteActionKind, entry: PageRouteEntry | null, tipResKey: string) {
    this.kind = kind;
    this.entry = entry;
    this.tipResKey = tipResKey;
  }
}

/**
 * 二级页面路由表：已激活 15 页（P0 5 页 + Phase B P1~P4 10 页）。
 */
export class PageRoutes {
  // P0 已激活（同步 main_pages.json）
  static readonly INDEX: string = 'pages/Index';
  static readonly SETTINGS: string = 'pages/SettingsPage';
  static readonly HOSTS: string = 'pages/HostsPage';
  static readonly GALLERY_READER: string = 'pages/GalleryReaderPage';
  static readonly IN_APP_BROWSER: string = 'pages/InAppBrowserPage';

  // Phase B Track P1 已激活（同步 main_pages.json）
  static readonly SET_SECURITY: string = 'pages/SetSecurityPage';

  // Phase B Track P2 已激活（同步 main_pages.json）
  static readonly DIR_PICKER: string = 'pages/DirPickerPage';
  static readonly LICENSE: string = 'pages/LicensePage';

  // Phase B Track P3 已激活（同步 main_pages.json）
  static readonly FILTER: string = 'pages/FilterPage';
  static readonly BLACK_LIST: string = 'pages/BlackListPage';
  static readonly MY_TAGS: string = 'pages/MyTagsPage';
  static readonly U_CONFIG: string = 'pages/UConfigPage';
  static readonly TAG_SELECTOR: string = 'pages/TagSelectorPage';

  // Phase B Track P4 已激活（同步 main_pages.json）
  static readonly WIFI_SERVER: string = 'pages/WiFiServerPage';
  static readonly WIFI_CLIENT: string = 'pages/WiFiClientPage';

  static readonly REGISTERED_PAGES: PageRouteEntry[] = [
    new PageRouteEntry(PageRoutes.INDEX, 'MainActivity', 'P0', true, false),
    new PageRouteEntry(PageRoutes.SETTINGS, 'SettingsActivity', 'P0', true, false),
    new PageRouteEntry(PageRoutes.HOSTS, 'HostsActivity', 'P0', true, false),
    new PageRouteEntry(PageRoutes.GALLERY_READER, 'GalleryActivity', 'P0', true, false),
    new PageRouteEntry(PageRoutes.IN_APP_BROWSER, 'InAppBrowserActivity', 'P0', true, false),
    new PageRouteEntry(PageRoutes.SET_SECURITY, 'SetSecurityActivity', 'P1', true, false),
    new PageRouteEntry(PageRoutes.DIR_PICKER, 'DirPickerActivity', 'P2', true, false),
    new PageRouteEntry(PageRoutes.LICENSE, 'LicenseActivity', 'P2', true, false),
    new PageRouteEntry(PageRoutes.FILTER, 'FilterActivity', 'P3', true, false),
    new PageRouteEntry(PageRoutes.BLACK_LIST, 'BlackListActivity', 'P3', true, false),
    new PageRouteEntry(PageRoutes.MY_TAGS, 'MyTagsActivity', 'P3', true, true),
    new PageRouteEntry(PageRoutes.U_CONFIG, 'UConfigActivity', 'P3', true, true),
    new PageRouteEntry(PageRoutes.TAG_SELECTOR, 'TagSelectorActivity', 'P3', true, false),
    new PageRouteEntry(PageRoutes.WIFI_SERVER, 'WiFiServerActivity', 'P4', true, false),
    new PageRouteEntry(PageRoutes.WIFI_CLIENT, 'WiFiClientActivity', 'P4', true, false),
  ];

  static readonly RESERVED_PHASE_B_PAGES: PageRouteEntry[] = [];

  /** 返回当前 `main_pages.json` 已注册的页面 URL 列表 */
  static getRegisteredUrls(): string[] {
    const urls: string[] = [];
    for (let i = 0; i < PageRoutes.REGISTERED_PAGES.length; i++) {
      urls.push(PageRoutes.REGISTERED_PAGES[i].url);
    }
    return urls;
  }

  /** 返回全量（已注册 + Phase B 预留）路由条目 */
  static getAllRoutes(): PageRouteEntry[] {
    const all: PageRouteEntry[] = [];
    for (let i = 0; i < PageRoutes.REGISTERED_PAGES.length; i++) {
      all.push(PageRoutes.REGISTERED_PAGES[i]);
    }
    for (let i = 0; i < PageRoutes.RESERVED_PHASE_B_PAGES.length; i++) {
      all.push(PageRoutes.RESERVED_PHASE_B_PAGES[i]);
    }
    return all;
  }

  static findByUrl(url: string): PageRouteEntry | null {
    for (let i = 0; i < PageRoutes.REGISTERED_PAGES.length; i++) {
      if (PageRoutes.REGISTERED_PAGES[i].url === url) {
        return PageRoutes.REGISTERED_PAGES[i];
      }
    }
    for (let i = 0; i < PageRoutes.RESERVED_PHASE_B_PAGES.length; i++) {
      if (PageRoutes.RESERVED_PHASE_B_PAGES[i].url === url) {
        return PageRoutes.RESERVED_PHASE_B_PAGES[i];
      }
    }
    return null;
  }

  static findByActivity(activityName: string): PageRouteEntry | null {
    for (let i = 0; i < PageRoutes.REGISTERED_PAGES.length; i++) {
      if (PageRoutes.REGISTERED_PAGES[i].activityName === activityName) {
        return PageRoutes.REGISTERED_PAGES[i];
      }
    }
    for (let i = 0; i < PageRoutes.RESERVED_PHASE_B_PAGES.length; i++) {
      if (PageRoutes.RESERVED_PHASE_B_PAGES[i].activityName === activityName) {
        return PageRoutes.RESERVED_PHASE_B_PAGES[i];
      }
    }
    return null;
  }

  static isRegistered(url: string): boolean {
    const entry: PageRouteEntry | null = PageRoutes.findByUrl(url);
    return entry !== null && entry.registered;
  }

  /** 解析导航计划：拦截未登记槽位与未登录态受限入口 */
  static resolveNavigation(url: string, signedIn: boolean): RouteNavigationPlan {
    const entry: PageRouteEntry | null = PageRoutes.findByUrl(url);
    if (entry === null) {
      return new RouteNavigationPlan(RouteActionKind.UNKNOWN, null, 'scene_not_supported');
    }
    if (!entry.registered) {
      return new RouteNavigationPlan(RouteActionKind.UNREGISTERED, entry, 'scene_not_supported');
    }
    if (entry.requiresSignIn && !signedIn) {
      return new RouteNavigationPlan(RouteActionKind.REQUIRE_SIGN_IN, entry, 'need_sign_in');
    }
    return new RouteNavigationPlan(RouteActionKind.PUSH, entry, '');
  }
}

/** Scene 门控与槽位辅助定义 */
export class SceneSlots {
  static readonly GATE_SECURITY: string = 'SecurityScene';
  static readonly GATE_WARNING: string = 'WarningScene';
  static readonly GATE_ANALYTICS: string = 'AnalyticsScene';
  static readonly GATE_SIGN_IN: string = 'SignInScene';
  static readonly GATE_SELECT_SITE: string = 'SelectSiteScene';

  static readonly GATE_SCENES: string[] = [
    SceneSlots.GATE_SECURITY,
    SceneSlots.GATE_WARNING,
    SceneSlots.GATE_ANALYTICS,
    SceneSlots.GATE_SIGN_IN,
    SceneSlots.GATE_SELECT_SITE,
  ];

  static isGateScene(sceneName: string): boolean {
    for (let i = 0; i < SceneSlots.GATE_SCENES.length; i++) {
      if (SceneSlots.GATE_SCENES[i] === sceneName) {
        return true;
      }
    }
    return false;
  }
}
