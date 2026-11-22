/*
 * 上游：app/src/main/res/layout/item_filter_header.xml（inventory S0611，上游 25 行）
 * 目标：harmony/entry/src/main/ets/hippo/ui/layout/item_filter_header.ets
 *
 * 上游这两个文件（item_blacklist_header / item_filter_header）**逐属性相同**，
 * 实现只有一份：复用 `BlacklistHeaderItemLayout`，本文件只做语义命名别名，
 * 保证清单里每个上游文件都有独立落点（inventory 1 行 = 1 个上游文件），
 * 又不产生两份会漂移的布局代码。
 *
 * 差异登记：无（结构/尺寸/颜色全部与上游一致；attr 解析差异见
 * item_blacklist_header.ets 的「无法等价」1/3）。
 */

export { BlacklistHeaderItemLayout as FilterHeaderItemLayout } from './item_blacklist_header';
