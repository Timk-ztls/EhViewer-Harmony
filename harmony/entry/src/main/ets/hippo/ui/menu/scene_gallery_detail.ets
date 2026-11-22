/*
 * 上游：.upstream-res/app/src/main/res/menu/scene_gallery_detail.xml
 * 目标：harmony/entry/src/main/ets/hippo/ui/menu/scene_gallery_detail.ets（inventory S0696）
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
export const SceneGalleryDetailMenu: MenuItemDef[] = [
  new MenuItemDef('action_refresh', $r('app.string.refresh'), null, ShowAsAction.NEVER, true, CheckableBehavior.NONE),
  new MenuItemDef('action_open_in_other_app', $r('app.string.open_in_other_app'), null, ShowAsAction.NEVER, true, CheckableBehavior.NONE),
];

