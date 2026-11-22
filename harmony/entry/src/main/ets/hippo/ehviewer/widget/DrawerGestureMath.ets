/**
 * 抽屉手势的**纯数学层**（S0289 EhDrawerLayout 的配套，第 8 轮新增）。
 *
 * 为什么要单独成文件：`EhDrawerLayout.ets` 里是 `@Component` struct，而本仓库的 TS 单测
 * 是把 .ets 机械改名成 .ts 后用 tsc 编译（不做装饰器擦除）→ **测试无法 import 带 @Component 的文件**
 * （实测：`error TS1146: Declaration expected` 全在装饰器行）。
 * 所以凡是"要断言的逻辑"都必须落在**不含装饰器**的文件里，这是本仓库既有的分层习惯
 * （同 `ArchiverNotificationPlanner` 在服务文件里但没有装饰器、`DownloadGuideHelper` 独立成文件）。
 *
 * 常量全部照 AOSP（`androidx.drawerlayout.widget.DrawerLayout` / `ViewDragHelper`），不自己发明：
 *   · `ViewDragHelper.EDGE_SIZE = 20dp` —— 关闭态下只有这条窄带能起手拖出抽屉
 *   · `DrawerLayout.MIN_DRAWER_MARGIN = 64dp` —— 抽屉宽度上限 = 父宽 − 64dp
 *   · 松手吸附：越过一半 → 打开，否则回弹（`settleCapturedViewAt` 前的判定）
 *   · scrim：`COLOR_SCRIM = 0x99000000`，绘制不透明度 = `progress × 0xFF`
 *
 * 上游为什么"文件里看不到这些"：`EhDrawerLayout.java`（144 行）只写 Snackbar Behavior，
 * 抽屉行为**全在它 extends 的 `DrawerLayout` 父类里**。判据：看 `extends` 后面的类，
 * 逐个问"它提供了哪些用户可观测行为"，再到我们的实现里核对 —— 不能只 `grep` 上游自己的文件。
 */
export class DrawerGestureMath {
  /** AOSP ViewDragHelper.EDGE_SIZE（dp） */
  static readonly EDGE_SIZE: number = 20;
  /** AOSP DrawerLayout.MIN_DRAWER_MARGIN（dp） */
  static readonly MIN_DRAWER_MARGIN: number = 64;
  /** 松手吸附阈值（半数） */
  static readonly SNAP_THRESHOLD: number = 0.5;
  /** AOSP DrawerLayout.COLOR_SCRIM = 0x99000000 → 最大不透明度 0x99/0xFF */
  static readonly SCRIM_MAX_ALPHA: number = 0x99 / 0xFF;

  /** offset 夹到 [0, width]（width = 抽屉宽）；拖过头不外溢 */
  static clampOffset(offset: number, width: number): number {
    if (width <= 0) {
      return 0;
    }
    if (offset < 0) {
      return 0;
    }
    if (offset > width) {
      return width;
    }
    return offset;
  }

  /** 打开进度 0..1（位移与 scrim 都用它） */
  static progress(offset: number, width: number): number {
    if (width <= 0) {
      return 0;
    }
    return DrawerGestureMath.clampOffset(offset, width) / width;
  }

  /** 松手后落到哪：越过半数 → width（打开），否则 0（关闭） */
  static snapTarget(offset: number, width: number): number {
    if (width <= 0) {
      return 0;
    }
    return DrawerGestureMath.progress(offset, width) >= DrawerGestureMath.SNAP_THRESHOLD ? width : 0;
  }

  /**
   * 是否允许开始拖动：
   *   · 已打开 → 任意位置可起手（拖动即关闭，与 AOSP 一致）
   *   · 已关闭 → **只有左边缘 EDGE_SIZE 内**能起手（防止和列表横滑/翻页手势打架）
   */
  static shouldStartDrag(startX: number, isOpen: boolean, width: number): boolean {
    if (isOpen) {
      return true;
    }
    if (startX < 0) {
      return false;
    }
    return startX <= DrawerGestureMath.EDGE_SIZE;
  }

  /** 抽屉宽度上限：`min(期望值, 父宽 − 64dp)`；父宽未知/过窄时回退期望值（不产生负宽） */
  static clampDrawerWidth(desired: number, viewWidth: number): number {
    if (viewWidth <= 0) {
      return desired;
    }
    const limit: number = viewWidth - DrawerGestureMath.MIN_DRAWER_MARGIN;
    if (limit <= 0) {
      return desired;
    }
    return desired > limit ? limit : desired;
  }

  /** scrim 不透明度 0..0.6（= 0x99/0xFF × 进度） */
  static scrimAlpha(offset: number, width: number): number {
    return DrawerGestureMath.SCRIM_MAX_ALPHA * DrawerGestureMath.progress(offset, width);
  }
}
