/*
 * 上游：.upstream-res/app/src/main/res/menu/drawer_gallery_list.xml
 * 目标：harmony/entry/src/main/ets/hippo/ui/menu/drawer_gallery_list.ets（inventory S0692）
 * 生成：scripts/conv/convert_menu.ps1（菜单定义 → MenuItemDef 数组）
 *
 * 这是**菜单定义**（不是布局）：字段与上游属性的对应见 hippo/ui/menu/MenuItemModel.ets。
 * icon 存的是**drawable 资源名**（对应 hippo/ui/drawable/<name>.ets 组件），不是 Resource ——
 * 本仓库的 drawable 已迁成 ArkUI 组件，`app.media.*` 多数不存在。
 *
 * 生成期发现：
 *   （无）
 */

import { MenuItemDef, ShowAsAction, CheckableBehavior } from './MenuItemModel';

/** 2 个菜单项（顺序与上游 <menu> 一致） */
export const DrawerGalleryListMenu: MenuItemDef[] = [
  new MenuItemDef('action_add', $r('app.string.add'), 'v_plus_dark_x24', ShowAsAction.ALWAYS, true, CheckableBehavior.NONE),
  new MenuItemDef('action_settings', $r('app.string.settings'), 'v_settings_dark_x24', ShowAsAction.IF_ROOM, true, CheckableBehavior.NONE),
];

