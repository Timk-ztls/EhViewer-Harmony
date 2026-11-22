/*
 * W-08 修复：显式场景工厂注册表 + 装配可达性报告。
 *
 * 问题：SceneApplication.createScene(name) 查表失败会 **throw**
 *   （'The scene is not registered: ' + sceneName），而全仓 registerScene 真实调用 = 0
 *   → 抽屉任意一项都会崩，不是显示空。
 *
 * 上游用 Announcer 带 Class<?> + 反射实例化；ArkTS 无反射 → 显式 registerScene(name, factory)。
 *
 * 装配现状（用编译器当判据，不是 grep extends —— grep 会漏"声明了 extends 但没实现抽象成员"）：
 *   ✅ 直接可构造（extends SolidScene → SceneFragment，无参）：
 *        AnalyticsScene / WarningScene / SelectSiteScene
 *   ✅ U-02b 薄子类（父类 abstract → 子类只注入默认实现 + getSceneName）：
 *        GalleryListScene / GalleryDetailScene / GalleryCommentsScene / FavoritesScene /
 *        SignInScene / CookieSignInScene / WebViewSignInScene
 *   ⛔ 不是 SceneFragment 子类（当前是逻辑类形态）：
 *        HistoryScene / QuickSearchScene / DownloadsScene / DownloadLabelsScene /
 *        EhTopListScene / SubscriptionsScene / GalleryInfoScene / GalleryPreviewsScene
 *   ⛔ 全仓不存在：SettingsScene / AboutScene
 */
import { SceneApplication } from './SceneApplication';
import { SceneFragment } from './SceneFragment';
import { AnalyticsScene } from '../ehviewer/ui/scene/AnalyticsScene';
import { SelectSiteScene } from '../ehviewer/ui/scene/SelectSiteScene';
import { WarningScene } from '../ehviewer/ui/scene/WarningScene';
import { GalleryListSceneConcrete } from '../ehviewer/ui/scene/gallery/list/GalleryListSceneConcrete';
import { FavoritesSceneConcrete } from '../ehviewer/ui/scene/gallery/list/FavoritesSceneConcrete';
import { GalleryDetailSceneConcrete } from '../ehviewer/ui/scene/gallery/detail/GalleryDetailSceneConcrete';
import { GalleryCommentsSceneConcrete } from '../ehviewer/ui/scene/GalleryCommentsSceneConcrete';
import { SignInSceneConcrete } from '../ehviewer/ui/scene/sign/SignInSceneConcrete';
import { CookieSignInSceneConcrete } from '../ehviewer/ui/scene/sign/CookieSignInSceneConcrete';
import { WebViewSignInSceneConcrete } from '../ehviewer/ui/scene/sign/WebViewSignInSceneConcrete';
import { GetProfileSceneShell } from '../ehviewer/ui/scene/sign/GetProfileSceneShell';
import { ProgressSceneShell } from '../ehviewer/ui/scene/ProgressSceneShell';
import { SecuritySceneShell } from '../ehviewer/ui/scene/SecuritySceneShell';
import { DownloadsSceneShell } from '../ehviewer/ui/scene/download/DownloadsSceneShell';

/** 本仓库存在但不是 `SceneFragment` 子类 → 不能进工厂表（U-02c 待定型） */
export const NON_SCENE_FRAGMENT_CLASSES: string[] = [
  'HistoryScene', 'QuickSearchScene', 'DownloadLabelsScene',
  'EhTopListScene', 'SubscriptionsScene', 'GalleryInfoScene', 'GalleryPreviewsScene'
];

/**
 * 曾经以为"缺失"的两个名字，U-02d 查证后**都不是 Scene**：
 *   Settings → 上游是 `startActivity(SettingsActivity)`，Activity 形态差异
 *              （走 `MainActivity.setAbilityStarter` 注入的能力，不进本注册表）
 *   About    → 上游抽屉里根本没有这一项；它是 `about_settings.xml` + `AboutFragment`，
 *              挂在设置页内部
 * 所以本列表为空：不是"漏登记"，是"形态不同"。
 */
export const MISSING_SCENES: string[] = [];

/** 一条登记结果（让"不可装配"成为可观测数据，而不是静默失败） */
export class SceneRegResult {
  readonly name: string;
  readonly registered: boolean;
  readonly reason: string;
  constructor(name: string, registered: boolean, reason: string) {
    this.name = name;
    this.registered = registered;
    this.reason = reason;
  }
}

/**
 * 注册所有**当前就能装配**的场景；不抛异常、不静默跳过。
 *
 * @param overrides **整个工厂的替换**（不是"构造后注入"）。为什么必须是替换：
 *   `DownloadManager.getInstance()` 是 **async**，而工厂签名 `() => SceneFragment` 是**同步**的 ——
 *   调用方只能在 `await` 之后**闭合一个已就绪的实例**进工厂，无法在同步的构造后补注入。
 *   所以 overrides 的值类型是 `() => SceneFragment`（可闭包捕获 await 到的真实依赖）。
 *
 *   同时它也让"薄子类只注入 `Unavailable*` 默认值"这条约束成立 ——
 *   真实现由 `AppWiring` 覆写（只有它知道"谁实现谁"；`ui-scene` 不该 import `storage-db`/`net-parse`）。
 *
 *   **为什么在工厂里应用、而不是注册后拿实例改**：`SceneApplication.createScene` 每次调工厂都
 *   `factory()` new 一个新实例 → 改"注册时那一个"无效，第二次进页面又是 `Unavailable`。
 */
export function registerAllScenes(app: SceneApplication,
  overrides?: Map<string, () => SceneFragment>): SceneRegResult[] {
  const out: SceneRegResult[] = [];
  const handled: Set<string> = new Set<string>();
  const reg = (name: string, defaultFactory: () => SceneFragment): void => {
    handled.add(name);
    try {
      const ov: (() => SceneFragment) | undefined =
        overrides === undefined ? undefined : overrides.get(name);
      const wrapped: () => SceneFragment = ov === undefined ? defaultFactory : ov;
      app.registerScene(name, wrapped);
      out.push(new SceneRegResult(name, true, ov === undefined ? 'ok' : 'ok +override-factory'));
    } catch (e) {
      out.push(new SceneRegResult(name, false, 'registerScene 抛出: ' + (e as Error).message));
    }
  };

  // 1) 直接可构造
  reg('AnalyticsScene', (): SceneFragment => new AnalyticsScene());
  reg('WarningScene', (): SceneFragment => new WarningScene());
  reg('SelectSiteScene', (): SceneFragment => new SelectSiteScene());

  // 2) U-02b 薄子类（只注入默认实现 + getSceneName）
  reg('GalleryListScene', (): SceneFragment => new GalleryListSceneConcrete());
  reg('GalleryDetailScene', (): SceneFragment => new GalleryDetailSceneConcrete());
  reg('GalleryCommentsScene', (): SceneFragment => new GalleryCommentsSceneConcrete());
  reg('FavoritesScene', (): SceneFragment => new FavoritesSceneConcrete());
  reg('SignInScene', (): SceneFragment => new SignInSceneConcrete());
  reg('CookieSignInScene', (): SceneFragment => new CookieSignInSceneConcrete());
  reg('WebViewSignInScene', (): SceneFragment => new WebViewSignInSceneConcrete());
  // U-02c 样板：逻辑类 + extends SceneFragment 外壳
  reg('SecurityScene', (): SceneFragment => new SecuritySceneShell(null));
  reg('GetProfileScene', (): SceneFragment => new GetProfileSceneShell(null, null));
  reg('ProgressScene', (): SceneFragment => new ProgressSceneShell(null));
  reg('DownloadsScene', (): SceneFragment => new DownloadsSceneShell(null));

  // 3) 逻辑类/外壳类场景：若 overrides 提供了 *Shell 工厂则正式注册，否则逐条记录原因
  for (let i = 0; i < NON_SCENE_FRAGMENT_CLASSES.length; i++) {
    const clsName: string = NON_SCENE_FRAGMENT_CLASSES[i];
    const ov: (() => SceneFragment) | undefined =
      overrides === undefined ? undefined : overrides.get(clsName);
    if (ov !== undefined) {
      reg(clsName, ov);
    } else {
      handled.add(clsName);
      out.push(new SceneRegResult(clsName, false,
        '不是 SceneFragment 子类（逻辑类形态），U-02c 待定型'));
    }
  }
  if (overrides !== undefined) {
    overrides.forEach((factory: () => SceneFragment, name: string): void => {
      if (!handled.has(name)) {
        reg(name, factory);
      }
    });
  }
  for (let i = 0; i < MISSING_SCENES.length; i++) {
    out.push(new SceneRegResult(MISSING_SCENES[i], false, '本仓库不存在该场景文件，U-02d 待查'));
  }
  return out;
}

/** MainActivity 抽屉项 → 场景名 → 装配状态（"点哪一项会崩"的唯一可观测面） */
export function getDrawerRoutingReport(results: SceneRegResult[]): string[] {
  // 与上游 onNavigationItemSelected 的 8 项同序：
  // homepage / subscription / whats_hot / top_lists （都进 GalleryListScene，靠 action 区分）
  // favourite / history / downloads / settings（settings 是 Activity，不在此表）
  const order: string[] = [
    'GalleryListScene', 'GalleryListScene', 'GalleryListScene', 'GalleryListScene',
    'FavoritesScene', 'HistoryScene', 'DownloadsScene'
  ];
  const lines: string[] = [];
  for (let i = 0; i < order.length; i++) {
    let state: string = '未在结果表里';
    for (let j = 0; j < results.length; j++) {
      if (results[j].name === order[i]) {
        state = results[j].registered ? '可装配' : results[j].reason;
        break;
      }
    }
    lines.push(order[i] + ' -> ' + state);
  }
  return lines;
}
