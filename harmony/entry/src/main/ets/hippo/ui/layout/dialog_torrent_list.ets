/*
 * 上游：app/src/main/res/layout/dialog_torrent_list.xml（inventory S0583，上游 39 行）
 * 目标：harmony/entry/src/main/ets/hippo/ui/layout/dialog_torrent_list.ets
 *
 * 与 dialog_archive_list.xml **逐属性相同**（FrameLayout + padding 24/24 +
 * ProgressView 居中 + TextView(AppCompat.Medium) 居中 + ListView match），
 * 唯一差别是控件 id 与业务含义（种子列表 vs 归档列表）。
 *
 * 因此复用 `ArchiveListDialogLayout`（S0569），本文件只做语义命名别名 ——
 * 与 item_filter/item_blacklist、item_quick_search/item_download_label 同一处理方式。
 *
 * 差异登记：无（结构/尺寸/字体全部一致；叠放与未交付控件的处理见 dialog_archive_list）。
 */

export { ArchiveListDialogLayout as TorrentListDialogLayout } from './dialog_archive_list';
