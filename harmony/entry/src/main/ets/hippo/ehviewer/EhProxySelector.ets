/*
 * Licensed under the Apache License, Version 2.0 (the "License");
 *
 * ── HarmonyOS 移植记录 ──────────────────────────────────────────────────────
 * 条目   : S0151   上游: com/hippo/ehviewer/EhProxySelector.java（93 行）
 * 目标   : harmony/entry/src/main/ets/hippo/ehviewer/EhProxySelector.ets
 *
 * 四种代理模式（`Settings.getProxyType()`）：
 * ```
 * TYPE_DIRECT = 0  → 不用代理（NullProxySelector）
 * TYPE_SYSTEM = 1  → 用系统代理（alternative = 原本的 ProxySelector.getDefault()）
 * TYPE_HTTP   = 2  → 用用户填的 HTTP 代理
 * TYPE_SOCKS  = 3  → 用用户填的 SOCKS 代理
 * ```
 *
 * ## `select(uri)` 的判定顺序（**这是可移植的核心**）
 * ```
 * if (type == HTTP || type == SOCKS) {
 *     ip 非空 且 port 合法(InetValidator.isValidInetPort)  → 返回该代理（单元素列表）
 *     否则/抛异常 → 往下走降级
 * }
 * if (delegation != null) return delegation.select(uri);   // DIRECT / SYSTEM 分支落在这里
 * return alternative.select(uri);                           // HTTP/SOCKS 但配置非法 → 兜底用系统
 * ```
 * **关键：HTTP/SOCKS 模式的 `delegation` 是 `null`**（`updateProxy` 里显式赋 null），
 * 所以"用户选了自定义代理但 ip/port 非法"时**不会报错，而是静默降级为系统代理** —— 照搬。
 *
 * ## 平台差异
 *  1. `ProxySelector` / `Proxy` / `InetSocketAddress` → 抽象成 `ProxyRoute` 值对象 +
 *     注入的 `selectSystem(uri)`（鸿蒙侧由 net 层的连接实现消费，不存在同名 API）。
 *  2. `InetAddress.getByName(ip)` 会做 DNS 解析（可能阻塞/抛 UnknownHostException）→
 *     本实现**只做格式校验**（`InetValidator.isValidInet4Address` 或非空字符串），
 *     DNS 交给真正的连接层。这样"填了域名当代理地址"的行为差异被限制在连接层。
 *  3. `Settings.getProxyType/getProxyIp/getProxyPort` 走已交付的 Settings；
 *     本文件只依赖注入的取值函数，便于断言（不必 attach）。
 *
 * ## 一处照搬：`updateProxy()` 的 `switch` 里 `default` 与 `TYPE_SYSTEM` **共用一个分支**
 * ```
 * case TYPE_SYSTEM:
 * default:  delegation = alternative;
 * ```
 * 后果：**未知的 proxyType 值 = 系统代理**（不是 DIRECT）。断言里钉住了这一点。
 */

import connection from '@ohos.net.connection';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { InetValidator } from '../network/InetValidator';
import { HttpUrl } from '../okhttp/HttpUrl';
import { Proxy, ProxySelector, ProxyType as OkProxyType } from '../okhttp/ProxySelector';
import { Settings } from './Settings';

/** `Settings.getProxyType()` 的四个取值（上游常量） */
export class ProxyType {
  static readonly TYPE_DIRECT: number = 0;
  static readonly TYPE_SYSTEM: number = 1;
  static readonly TYPE_HTTP: number = 2;
  static readonly TYPE_SOCKS: number = 3;
}

/** 代理路由结果（对应上游 `List<Proxy>` 里的那一个元素，或"直连"） */
export enum ProxyRouteKind {
  /** `Proxy.NO_PROXY` */
  NO_PROXY = 0,
  /** 用户配置的 HTTP 代理 */
  HTTP = 1,
  /** 用户配置的 SOCKS 代理 */
  SOCKS = 2,
  /** 系统代理（由注入的 `selectSystem` 决定具体值） */
  SYSTEM = 3
}

export class ProxyRoute {
  kind: ProxyRouteKind;
  /** HTTP/SOCKS 时的代理地址；系统/直连时为 null */
  host: string | null;
  port: number;

  constructor(kind: ProxyRouteKind, host: string | null, port: number) {
    this.kind = kind;
    this.host = host;
    this.port = port;
  }

  static noProxy(): ProxyRoute {
    return new ProxyRoute(ProxyRouteKind.NO_PROXY, null, -1);
  }

  static system(): ProxyRoute {
    return new ProxyRoute(ProxyRouteKind.SYSTEM, null, -1);
  }
}

/** 代理配置的取值来源（`Settings.getProxyType/getProxyIp/getProxyPort`） */
export interface ProxySettings {
  getProxyType(): number;

  /** 可能为 null（上游 `DEFAULT_PROXY_IP = null`） */
  getProxyIp(): string | null;

  /** 上游 `DEFAULT_PROXY_PORT = -1` */
  getProxyPort(): number;
}

export class EhProxySelector {

  static readonly TYPE_DIRECT: number = ProxyType.TYPE_DIRECT;
  static readonly TYPE_SYSTEM: number = ProxyType.TYPE_SYSTEM;
  static readonly TYPE_HTTP: number = ProxyType.TYPE_HTTP;
  static readonly TYPE_SOCKS: number = ProxyType.TYPE_SOCKS;

  /**
   * **生产用的默认配置来源**（对应上游 `Settings.getProxyType/getProxyIp/getProxyPort`）。
   *
   * 之前本类只有注入接口 `ProxySettings`，**全仓没有任何实现** → 生产路径上代理永远是空配置
   * （`check_settings_consumers.ps1` 的 B 类"上游调了、我们没调"抓到的正是这条）。
   * 现在把 Settings 的三个访问器接上：调用方 `EhProxySelector.select(EhProxySelector.defaultProxySettings(), …)` 即可。
   */
  static defaultProxySettings(): ProxySettings {
    return new SettingsProxySettings();
  }

  /**
   * 对应上游 `updateProxy()` 的结果：`delegation` 的**去向**。
   * @returns `'ALTERNATIVE'`（类型为 DIRECT 时其实是 Null）—— 见下：
   *   · DIRECT  → `'NULL'`（新建 NullProxySelector，不走 alternative）
   *   · SYSTEM / 未知 → `'ALTERNATIVE'`
   *   · HTTP / SOCKS → `'NONE'`（delegation = null）
   */
  static delegationOf(proxyType: number): string {
    if (proxyType === ProxyType.TYPE_DIRECT) {
      return 'NULL';
    }
    if (proxyType === ProxyType.TYPE_HTTP || proxyType === ProxyType.TYPE_SOCKS) {
      return 'NONE';
    }
    // TYPE_SYSTEM 与**任何未知值**都落这里（上游 switch 的 default 与 TYPE_SYSTEM 共用分支）
    return 'ALTERNATIVE';
  }

  /**
   * 对应上游 `select(uri)`：返回本次请求该用哪条代理路线。
   * @param selectSystem 系统代理（`alternative.select(uri)`；鸿蒙侧由 net 层提供）
   */
  static select(settings: ProxySettings, selectSystem: () => ProxyRoute): ProxyRoute {
    const type: number = settings.getProxyType();

    // 1. HTTP / SOCKS：先试用户配置
    if (type === ProxyType.TYPE_HTTP || type === ProxyType.TYPE_SOCKS) {
      const ip: string | null = settings.getProxyIp();
      const port: number = settings.getProxyPort();
      if (!EhProxySelector.isEmpty(ip) && InetValidator.isValidInetPort(port)) {
        return new ProxyRoute(
          (type === ProxyType.TYPE_HTTP) ? ProxyRouteKind.HTTP : ProxyRouteKind.SOCKS,
          ip as string, port);
      }
      // 配置非法 → **不报错**，继续往下（delegation 为 null → 落到 alternative）
    }

    // 2. delegation
    const delegation: string = EhProxySelector.delegationOf(type);
    if (delegation === 'NULL') {
      return ProxyRoute.noProxy();
    }
    if (delegation === 'ALTERNATIVE') {
      return selectSystem();
    }

    // 3. HTTP/SOCKS 但配置非法 → 兜底系统代理（上游 `alternative.select(uri)`）
    return selectSystem();
  }

  /** 对应上游 `connectFailed(uri, sa, ioe)`：只打日志，不改变代理设置 */
  static describeConnectFailed(uri: string | null, host: string, port: number): string {
    return `${uri} ${host}:${port} connect failed`;
  }

  /** 对应 `TextUtils.isEmpty(ip)` */
  private static isEmpty(s: string | null): boolean {
    return s === null || s.length === 0;
  }
}
/**
 * 把 `Settings` 的三个代理访问器适配成 `ProxySettings`（生产默认实现）。
 * 单列一个类而不是内联对象字面量：ArkTS **禁止对象字面量作类型**（`arkts-no-obj-literals-as-types`）。
 */
class SettingsProxySettings implements ProxySettings {
  getProxyType(): number {
    return Settings.getProxyType();
  }

  getProxyIp(): string | null {
    return Settings.getProxyIp();
  }

  getProxyPort(): number {
    return Settings.getProxyPort();
  }
}

/** 系统 HTTP 代理快照（对应 `@ohos.net.connection.HttpProxy`） */
export class SystemProxyConfig {
  host: string;
  port: number;
  exclusionList: string[];

  constructor(host: string, port: number, exclusionList: string[] = []) {
    this.host = host;
    this.port = port;
    this.exclusionList = exclusionList;
  }
}

/**
 * 适配 OkHttp `ProxySelector` 抽象基类的生产代理选择器（对应上游 `EhProxySelector extends ProxySelector`）。
 *
 * - `select(url)` 保持同步不阻塞，SYSTEM 回落读取缓存的系统代理（缺省/被 exclusionList 排除则返回 `[Proxy.direct()]`）。
 * - 首次按需或调用 `updateProxy()` / `refreshSystemProxy()` 时通过 `@ohos.net.connection.getDefaultHttpProxy()`
 *   安全异步刷新系统代理缓存（异常与平台不支持均安全捕获，不抛未捕获 rejection）。
 */
export class OkHttpEhProxySelector extends ProxySelector {
  private readonly settings: ProxySettings;
  private readonly systemProxyFetcher: (() => Promise<SystemProxyConfig | null>) | null;
  private cachedSystemProxy: SystemProxyConfig | null = null;
  private refreshInFlight: Promise<SystemProxyConfig | null> | null = null;
  private hasAttemptedSystemRefresh: boolean = false;

  constructor(settings?: ProxySettings,
    systemProxyFetcher?: () => Promise<SystemProxyConfig | null>) {
    super();
    this.settings = (settings !== undefined) ? settings : EhProxySelector.defaultProxySettings();
    this.systemProxyFetcher = (systemProxyFetcher !== undefined) ? systemProxyFetcher : null;
  }

  /** 手动设置/清除缓存的系统代理（供宿主监听器或单测同步更新） */
  setCachedSystemProxy(host: string | null, port: number, exclusionList: string[] = []): void {
    if (host === null || host.length === 0 || !InetValidator.isValidInetPort(port)) {
      this.cachedSystemProxy = null;
    } else {
      this.cachedSystemProxy = new SystemProxyConfig(host, port, exclusionList.slice());
    }
    this.hasAttemptedSystemRefresh = true;
  }

  getCachedSystemProxy(): SystemProxyConfig | null {
    return this.cachedSystemProxy;
  }

  /** 对应上游 `updateProxy()`：在需要系统代理时非阻塞刷新缓存 */
  updateProxy(): void {
    const delegation: string = EhProxySelector.delegationOf(this.settings.getProxyType());
    if (delegation !== 'NULL') {
      this.triggerSystemRefresh();
    }
  }

  /** 异步刷新系统代理缓存（并发去重） */
  async refreshSystemProxy(): Promise<SystemProxyConfig | null> {
    if (this.refreshInFlight !== null) {
      return this.refreshInFlight;
    }
    const task: Promise<SystemProxyConfig | null> = this.fetchSystemProxySafe();
    this.refreshInFlight = task;
    try {
      const proxy: SystemProxyConfig | null = await task;
      this.cachedSystemProxy = proxy;
      this.hasAttemptedSystemRefresh = true;
      return proxy;
    } finally {
      if (this.refreshInFlight === task) {
        this.refreshInFlight = null;
      }
    }
  }

  private triggerSystemRefresh(): void {
    this.refreshSystemProxy().catch((e: Error): void => {
      // fetchSystemProxySafe already handles errors; log unexpected rejections so refresh failures leave a trace.
      const msg: string = e instanceof Error ? e.message : String(e);
      hilog.warn(0x0000, 'EhProxySelector', 'triggerSystemRefresh failed: %{public}s', msg);
    });
  }

  private async fetchSystemProxySafe(): Promise<SystemProxyConfig | null> {
    try {
      if (this.systemProxyFetcher !== null) {
        const fetched: SystemProxyConfig | null = await this.systemProxyFetcher();
        if (fetched === null || fetched.host.length === 0 || !InetValidator.isValidInetPort(fetched.port)) {
          return null;
        }
        return fetched;
      }
      const hp: connection.HttpProxy = await connection.getDefaultHttpProxy();
      if (hp === null || hp === undefined || typeof hp.host !== 'string'
        || hp.host.length === 0 || !InetValidator.isValidInetPort(hp.port)) {
        return null;
      }
      const exclusions: string[] = Array.isArray(hp.exclusionList) ? hp.exclusionList.slice() : [];
      return new SystemProxyConfig(hp.host, hp.port, exclusions);
    } catch (_e) {
      return null;
    }
  }

  select(url: HttpUrl): Proxy[] {
    const route: ProxyRoute = EhProxySelector.select(this.settings, (): ProxyRoute => ProxyRoute.system());
    if (route.kind === ProxyRouteKind.NO_PROXY) {
      return [Proxy.direct()];
    }
    if (route.kind === ProxyRouteKind.HTTP && route.host !== null) {
      return [new Proxy(OkProxyType.HTTP, route.host, route.port)];
    }
    if (route.kind === ProxyRouteKind.SOCKS && route.host !== null) {
      return [new Proxy(OkProxyType.SOCKS, route.host, route.port)];
    }

    // SYSTEM 或非法自定义代理降级：使用非阻塞缓存的系统代理
    if (!this.hasAttemptedSystemRefresh && this.refreshInFlight === null) {
      this.triggerSystemRefresh();
    }
    const sys: SystemProxyConfig | null = this.cachedSystemProxy;
    if (sys !== null && sys.host.length > 0 && InetValidator.isValidInetPort(sys.port)) {
      if (OkHttpEhProxySelector.isExcluded(url.host(), sys.exclusionList)) {
        return [Proxy.direct()];
      }
      return [new Proxy(OkProxyType.HTTP, sys.host, sys.port)];
    }
    return [Proxy.system()];
  }

  private static isExcluded(host: string, exclusionList: string[]): boolean {
    const target: string = host.toLowerCase();
    for (let i = 0; i < exclusionList.length; i++) {
      const raw: string = exclusionList[i].trim().toLowerCase();
      if (raw.length === 0) {
        continue;
      }
      if (raw === '*' || raw === target) {
        return true;
      }
      const suffix: string = raw.startsWith('*.') ? raw.substring(1) : raw;
      if (suffix.startsWith('.')) {
        if (target === suffix.substring(1) || target.endsWith(suffix)) {
          return true;
        }
      } else if (target.endsWith('.' + suffix)) {
        return true;
      }
    }
    return false;
  }
}