/*
 * 上游：app/src/main/res/layout/dialog_archiver.xml（inventory S0570，上游 89 行）
 * 目标：harmony/entry/src/main/ets/hippo/ui/layout/dialog_archiver.ets
 *
 * 背景：归档（离线包）选择对话框：左"原图"列 + 右"重采样"列（各 费用/按钮/体积），
 * 未就绪时叠一个进度条。
 *
 * ── 结构对照 ────────────────────────────────────────────────────────────────
 * Android                                   ArkUI
 * FrameLayout(match × wrap)                  Stack
 *   LinearLayout#dialog_archiver_body       Row（@Prop bodyVisible，见 1）
 *     visibility=invisible                    → Visibility.Hidden（**占位**，与 gone 不同）
 *     LinearLayout(0dp, weight=1, vertical)    Column().layoutWeight(1)
 *       TextView#..._original_cost            Text：AppCompat.Caption(12fp)
 *         layout_gravity=center                 .alignSelf(ItemAlign.Center)
 *         text=@string/archiver_dialog_cost       $r('app.string.archiver_dialog_cost')
 *       Button#..._original_download          Button($r('app.string.archiver_dialog_download_original'))
 *         layout_gravity=center                 .alignSelf(ItemAlign.Center)
 *       TextView#..._original_size            Text：Caption(12fp) + archiver_dialog_size
 *     LinearLayout(0dp, weight=1, vertical)    Column().layoutWeight(1)（右列同构）
 *       ..._resample_cost / _resample_download（archiver_dialog_download_resample）/ _resample_size
 *   ProgressBar#dialog_archiver_progress     Progress({type: Linear})（见 2）
 *     marginTop=@dimen/dad_bar_size           .margin({top: dad_bar_size})
 *     match × wrap                             .width('100%')
 *
 * ── 无法等价 / 需注意 ───────────────────────────────────────────────────────
 * 1. `visibility="invisible"` → ArkUI `Visibility.Hidden`（**保留占位**）。
 *    这与本模块其它布局里的 `gone`→`Visibility.None`（不占位）**不同**，不能混用：
 *    上游这里要的是"加载期间两列仍占位，避免进度条出现/消失时高度跳动"。
 * 2. `ProgressBar`（无 style=Horizontal）是**无限旋转**的圆形进度条 → ArkUI 用
 *    `LoadingProgress`（不是 Linear Progress，那是有确定进度的横条）。
 *    上游 `layout_marginTop=@dimen/dad_bar_size` 把进度条压在内容下方。
 * 3. 两列结构完全同构（费用文本 + 按钮 + 体积文本），但**文案不同**（original / resample），
 *    故用 @Prop 参数化后由同一 @Builder 渲染两列（数据参数化，不传 builder —— 见
 *    widget_advance_search_table 那条 @Builder 不能传函数的规则）。
 * 4. `AppCompat.Caption` = 12sp → 已迁资源 `app.float.text_super_small`。
 * 5. 按钮点击（选择原图/重采样）与费用/体积文案内容属业务层：本组件只暴露两个回调
 *    与六个文本 @Prop。
 */

@Component
export struct ArchiverDialogLayout {
  // ---- 左列（原图） ----
  @Prop originalCost: string = '';
  @Prop originalSize: string = '';
  // ---- 右列（重采样） ----
  @Prop resampleCost: string = '';
  @Prop resampleSize: string = '';
  // ---- 状态 ----
  /** 上游 body 初始 invisible（加载完成后才显示两列） */
  @Prop bodyVisible: boolean = false;
  @Prop textColor: ResourceColor = '#DE000000';
  /** 上游 @dimen/dad_bar_size（进度条与内容的垂直间距） */
  @Prop barMarginTop: number = 24;

  onDownloadOriginal: () => void = () => {
    // 默认空实现：使用方注入
  };
  onDownloadResample: () => void = () => {
    // 默认空实现：使用方注入
  };

  /** 一列（费用 + 按钮 + 体积），数据参数化 */
  @Builder
  archiverColumn(cost: string, size: string, buttonText: Resource, onDownload: () => void) {
    Column() {
      Text(cost.length > 0 ? cost : $r('app.string.archiver_dialog_cost'))
        .fontSize($r('app.float.text_super_small'))
        .fontColor(this.textColor)
        .alignSelf(ItemAlign.Center)

      Button(buttonText)
        .alignSelf(ItemAlign.Center)
        .onClick(() => {
          onDownload();
        })

      Text(size.length > 0 ? size : $r('app.string.archiver_dialog_size'))
        .fontSize($r('app.float.text_super_small'))
        .fontColor(this.textColor)
        .alignSelf(ItemAlign.Center)
    }
    .layoutWeight(1)
    .alignItems(HorizontalAlign.Center)
  }

  build() {
    Stack() {
      // 两列主体（上游初始 invisible：**保留占位**，避免加载完成后高度跳动）
      Row() {
        this.archiverColumn(this.originalCost, this.originalSize,
          $r('app.string.archiver_dialog_download_original'), this.onDownloadOriginal);

        this.archiverColumn(this.resampleCost, this.resampleSize,
          $r('app.string.archiver_dialog_download_resample'), this.onDownloadResample);
      }
      .width('100%')
      .visibility(this.bodyVisible ? Visibility.Visible : Visibility.Hidden)

      // 无限旋转进度条（上游 ProgressBar 无 style=Horizontal → 圆形不确定进度）
      LoadingProgress()
        .width('100%')
        .margin({ top: this.barMarginTop })
        .visibility(this.bodyVisible ? Visibility.None : Visibility.Visible)
    }
    .width('100%')
  }
}
