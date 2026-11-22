/*
 * 上游：.upstream-res/app/src/main/res/menu/nav_drawer_main.xml
 * 目标：harmony/entry/src/main/ets/hippo/ui/menu/nav_drawer_main.ets（inventory S0693）
 * 生成：scripts/conv/convert_menu.ps1（菜单定义 → MenuItemDef 数组）
 *
 * 这是**菜单定义**（不是布局）：字段与上游属性的对应见 hippo/ui/menu/MenuItemModel.ets。
 * icon 存的是**drawable 资源名**（对应 hippo/ui/drawable/<name>.ets 组件），不是 Resource ——
 * 本仓库的 drawable 已迁成 ArkUI 组件，`app.media.*` 多数不存在。
 *
 * 生成期发现：
 *   - 存在无 id 的 item（上游不会出现，跳过）
 */

import { MenuItemDef, ShowAsAction, CheckableBehavior } from './MenuItemModel';

/** 9 个菜单项（顺序与上游 <menu> 一致） */
export const NavDrawerMainMenu: MenuItemDef[] = [
  new MenuItemDef('nav_homepage', $r('app.string.homepage'), 'v_homepage_black_x24', ShowAsAction.NEVER, true, CheckableBehavior.SINGLE),
  new MenuItemDef('nav_subscription', $r('app.string.subscription'), 'v_eh_subscription_black_x24', ShowAsAction.NEVER, true, CheckableBehavior.SINGLE),
  new MenuItemDef('nav_whats_hot', $r('app.string.whats_hot'), 'v_fire_black_x24', ShowAsAction.NEVER, true, CheckableBehavior.SINGLE),
  new MenuItemDef('nav_top_lists', $r('app.string.top_lists'), 'v_top_lists_x24', ShowAsAction.NEVER, true, CheckableBehavior.SINGLE),
  new MenuItemDef('nav_favourite', $r('app.string.favourite'), 'v_heart_black_x24', ShowAsAction.NEVER, true, CheckableBehavior.SINGLE),
  new MenuItemDef('nav_history', $r('app.string.history'), 'v_history_black_x24', ShowAsAction.NEVER, true, CheckableBehavior.SINGLE),
  new MenuItemDef('nav_downloads', $r('app.string.downloads'), 'v_download_black_x24', ShowAsAction.NEVER, true, CheckableBehavior.SINGLE),
  new MenuItemDef('nav_settings', $r('app.string.settings'), 'v_settings_black_x24', ShowAsAction.NEVER, true, CheckableBehavior.SINGLE),
  new MenuItemDef('nav_stub', $r('app.string.stub'), null, ShowAsAction.NEVER, false, CheckableBehavior.SINGLE),
];

