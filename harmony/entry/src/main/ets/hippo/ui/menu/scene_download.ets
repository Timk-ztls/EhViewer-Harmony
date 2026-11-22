/*
 * 上游：.upstream-res/app/src/main/res/menu/scene_download.xml
 * 目标：harmony/entry/src/main/ets/hippo/ui/menu/scene_download.ets（inventory S0695）
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

/** 40 个菜单项（顺序与上游 <menu> 一致） */
export const SceneDownloadMenu: MenuItemDef[] = [
  new MenuItemDef('sort_download_list', $r('app.string.download_sort_list'), 'ic_sort_filter', ShowAsAction.IF_ROOM, true, CheckableBehavior.NONE),
  new MenuItemDef('filter_by_status', $r('app.string.download_filter_by_status'), null, ShowAsAction.IF_ROOM, true, CheckableBehavior.NONE),
  new MenuItemDef('all', $r('app.string.download_status_all'), null, ShowAsAction.IF_ROOM, true, CheckableBehavior.NONE),
  new MenuItemDef('download_done', $r('app.string.download_state_downloaded'), null, ShowAsAction.IF_ROOM, true, CheckableBehavior.NONE),
  new MenuItemDef('not_started', $r('app.string.download_state_none'), null, ShowAsAction.IF_ROOM, true, CheckableBehavior.NONE),
  new MenuItemDef('waiting', $r('app.string.download_state_wait'), null, ShowAsAction.IF_ROOM, true, CheckableBehavior.NONE),
  new MenuItemDef('downloading', $r('app.string.download_state_downloading'), null, ShowAsAction.IF_ROOM, true, CheckableBehavior.NONE),
  new MenuItemDef('failed', $r('app.string.download_state_failed'), null, ShowAsAction.IF_ROOM, true, CheckableBehavior.NONE),
  new MenuItemDef('filter_by_kind', $r('app.string.download_filter_by_kind'), null, ShowAsAction.IF_ROOM, true, CheckableBehavior.NONE),
  new MenuItemDef('all_kind', $r('app.string.download_status_all'), null, ShowAsAction.IF_ROOM, true, CheckableBehavior.NONE),
  new MenuItemDef('misc', $r('app.string.misc'), null, ShowAsAction.IF_ROOM, true, CheckableBehavior.NONE),
  new MenuItemDef('doujinshi', $r('app.string.doujinshi'), null, ShowAsAction.IF_ROOM, true, CheckableBehavior.NONE),
  new MenuItemDef('manga', $r('app.string.manga'), null, ShowAsAction.IF_ROOM, true, CheckableBehavior.NONE),
  new MenuItemDef('artist_cg', $r('app.string.artist_cg'), null, ShowAsAction.IF_ROOM, true, CheckableBehavior.NONE),
  new MenuItemDef('game_cg', $r('app.string.game_cg'), null, ShowAsAction.IF_ROOM, true, CheckableBehavior.NONE),
  new MenuItemDef('image_set', $r('app.string.image_set'), null, ShowAsAction.IF_ROOM, true, CheckableBehavior.NONE),
  new MenuItemDef('cosplay', $r('app.string.cosplay'), null, ShowAsAction.IF_ROOM, true, CheckableBehavior.NONE),
  new MenuItemDef('asian_porn', $r('app.string.asian_porn'), null, ShowAsAction.IF_ROOM, true, CheckableBehavior.NONE),
  new MenuItemDef('non_h', $r('app.string.non_h'), null, ShowAsAction.IF_ROOM, true, CheckableBehavior.NONE),
  new MenuItemDef('western', $r('app.string.western'), null, ShowAsAction.IF_ROOM, true, CheckableBehavior.NONE),
  new MenuItemDef('unknown', $r('app.string.unknown'), null, ShowAsAction.IF_ROOM, true, CheckableBehavior.NONE),
  new MenuItemDef('local_import', $r('app.string.imported_archive_category'), null, ShowAsAction.IF_ROOM, true, CheckableBehavior.NONE),
  new MenuItemDef('sort', $r('app.string.sort_download_list'), null, ShowAsAction.ALWAYS, true, CheckableBehavior.NONE),
  new MenuItemDef('sort_by_default', $r('app.string.default_sort'), null, ShowAsAction.IF_ROOM, true, CheckableBehavior.NONE),
  new MenuItemDef('sort_by_gallery_id_asc', $r('app.string.sort_by_gallery_id_asc'), null, ShowAsAction.IF_ROOM, true, CheckableBehavior.NONE),
  new MenuItemDef('sort_by_gallery_id_desc', $r('app.string.sort_by_gallery_id_desc'), null, ShowAsAction.IF_ROOM, true, CheckableBehavior.NONE),
  new MenuItemDef('sort_by_create_time_asc', $r('app.string.sort_by_create_time_asc'), null, ShowAsAction.IF_ROOM, true, CheckableBehavior.NONE),
  new MenuItemDef('sort_by_create_time_desc', $r('app.string.sort_by_create_time_desc'), null, ShowAsAction.IF_ROOM, true, CheckableBehavior.NONE),
  new MenuItemDef('sort_by_rating_asc', $r('app.string.sort_by_rating_asc'), null, ShowAsAction.IF_ROOM, true, CheckableBehavior.NONE),
  new MenuItemDef('sort_by_rating_desc', $r('app.string.sort_by_rating_desc'), null, ShowAsAction.IF_ROOM, true, CheckableBehavior.NONE),
  new MenuItemDef('sort_by_name_asc', $r('app.string.sort_by_name_asc'), null, ShowAsAction.IF_ROOM, true, CheckableBehavior.NONE),
  new MenuItemDef('sort_by_name_desc', $r('app.string.sort_by_name_desc'), null, ShowAsAction.IF_ROOM, true, CheckableBehavior.NONE),
  new MenuItemDef('sort_by_file_size_asc', $r('app.string.sort_by_file_size_asc'), null, ShowAsAction.IF_ROOM, true, CheckableBehavior.NONE),
  new MenuItemDef('sort_by_file_size_desc', $r('app.string.sort_by_file_size_desc'), null, ShowAsAction.IF_ROOM, true, CheckableBehavior.NONE),
  new MenuItemDef('action_start_all', $r('app.string.download_start_all'), 'v_play_dark_x24', ShowAsAction.ALWAYS, true, CheckableBehavior.NONE),
  new MenuItemDef('action_stop_all', $r('app.string.download_stop_all'), 'v_pause_dark_x24', ShowAsAction.IF_ROOM, true, CheckableBehavior.NONE),
  new MenuItemDef('action_reset_reading_progress', $r('app.string.download_reset_reading_progress'), null, ShowAsAction.NEVER, true, CheckableBehavior.NONE),
  new MenuItemDef('search_download_gallery', $r('app.string.download_search_gallery'), null, ShowAsAction.NEVER, true, CheckableBehavior.NONE),
  new MenuItemDef('import_local_archive', $r('app.string.import_local_archive'), null, ShowAsAction.NEVER, true, CheckableBehavior.NONE),
  new MenuItemDef('import_local_album', $r('app.string.import_local_album'), null, ShowAsAction.NEVER, true, CheckableBehavior.NONE),
];

