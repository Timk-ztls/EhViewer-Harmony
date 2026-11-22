/**
 * 上游 `EhDrawerLayout` 的内部接口 `DrawerLayoutChild`（inventory 新增层，登记于
 * inventory/ui-widget.extra.txt）。为什么单独成文件：`EhNavigationView` / `EhStageLayout` /
 * `EhDrawerView` 三个实现者都要用它，而上游它定义在 `EhDrawerLayout.java` 内部；
 * 若放进 EhDrawerLayout.ets，三个小控件会被迫 import 那个 144 行的大文件（且 EhDrawerLayout 尚未移植）。
 * 待 EhDrawerLayout 移植时本接口原样保留，语义不变。
 *
 * 上游（app/src/main/java/com/hippo/ehviewer/widget/EhDrawerLayout.java 内部接口）：
 *   void onGetWindowPadding(int top, int bottom);
 *   int getAdditionalTopMargin();
 *   int getAdditionalBottomMargin();
 * 用途：抽屉内的子视图向抽屉报告"我需要多少窗口内边距"（状态栏/导航栏），
 *      抽屉据此给内容加额外外边距，避免被系统栏遮挡。
 */
export interface DrawerLayoutChild {
  /** 抽屉把窗口内边距下发给子视图 */
  onGetWindowPadding(top: number, bottom: number): void;

  /** 子视图要求抽屉额外加在顶部的外边距 */
  getAdditionalTopMargin(): number;

  /** 子视图要求抽屉额外加在底部的外边距 */
  getAdditionalBottomMargin(): number;
}
