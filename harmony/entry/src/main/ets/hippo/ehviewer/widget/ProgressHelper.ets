/**
 * 迁移自 app/src/main/java/com/hippo/ehviewer/widget/ProgressHelper.java（inventory S0304，上游 82 行）
 *
 * 上游是**静态工具类**：全局单例 AlertDialog（不可取消），内含「indeterminate 进度圈 + 文案」，
 *   showDialog(context, message) 首次调用创建；setProgress(p) 把文案改成 `p% message`；
 *   isDialogVisible() / dismissDialog()。
 *
 * ArkUI 对位：
 *   AlertDialog → 自定义对话框内容 + `CustomDialogController`（ArkUI 只有实例，没有"静态 dialog"）
 *   静态单例 → **`ProgressHelper` 改为控制器实例**（`ProgressDialogController`），由 ui-scene 持有；
 *              目的与上游一致（全局唯一、可跨页面 setProgress），但生命周期显式化（上游靠 GC 收 dialog，这里靠 dismiss）
 *   进度圈 → `LoadingProgress`
 *   文案 `p% message` → `progressText()` 纯函数（可单测）
 *
 * 差异（已登记 MR）：
 *   1) 上游 `setCancelable(false)` → ArkUI CustomDialogController 的 `autoCancel: false` + `cancel: () => {}`
 *   2) 上游直接 `dialog.show()`；ArkUI 需在 UI 上下文里 `controller.open()`，故本类只提供状态与文案，
 *      真正的 open/close 由持有 CustomDialogController 的页面执行（见文件尾用法）。
 */
/** 修 P2：必须是 @Observed 才能让 build() 随 setProgress 重跑（普通类字段不可观察 → 百分比永不更新） */
@Observed
export class ProgressDialogState {
  message: string = '';
  progress: number = -1;
  visible: boolean = false;

  /** 上游 setProgress 改写的文案格式：`<p>% <message>` */
  progressText(): string {
    if (this.progress < 0) {
      return this.message;
    }
    return `${this.progress}% ${this.message}`;
  }
}

export class ProgressDialogController {
  state: ProgressDialogState = new ProgressDialogState();
  /** 由页面注入：打开/关闭 CustomDialogController */
  openFn: (() => void) | null = null;
  closeFn: (() => void) | null = null;

  /** 上游 showDialog(context, message)：已可见时不再重建（上游 `if (dialog == null)`） */
  showDialog(message: string): void {
    if (this.state.visible) {
      return;
    }
    this.state.message = message;
    this.state.progress = -1;
    this.state.visible = true;
    if (this.openFn !== null) {
      this.openFn();
    }
  }

  /** 上游 setProgress(progress)：无 dialog 时返回 false */
  setProgress(progress: number): boolean {
    if (!this.state.visible) {
      return false;
    }
    this.state.progress = progress;
    return true;
  }

  isDialogVisible(): boolean {
    return this.state.visible;
  }

  /** 上游 dismissDialog() */
  dismissDialog(): void {
    this.state.visible = false;
    this.state.progress = -1;
    if (this.closeFn !== null) {
      this.closeFn();
    }
  }
}

/** 对话框内容（对位上游 new LinearLayout + ProgressBar + TextView 的横向组合） */
@Component
export struct ProgressDialogView {
  @ObjectLink state: ProgressDialogState;
  @Prop textColor: ResourceColor = '#8A000000';
  @Prop textSize: number = 20;
  @Prop paddingValue: number = 30;

  build() {
    Row({ space: this.paddingValue }) {
      LoadingProgress()
        .width(32)
        .height(32)
      Text(this.state.progressText())
        .fontSize(this.textSize)
        .fontColor(this.textColor)
    }
    .padding(this.paddingValue)
    .justifyContent(FlexAlign.Center)
    .alignItems(VerticalAlign.Center)
  }
}

// 用法（ui-scene）：
//   private progressCtrl: ProgressDialogController = new ProgressDialogController();
//   private dialogCtrl: CustomDialogController = new CustomDialogController({
//     builder: ProgressDialogView({ state: this.progressCtrl.state }),
//     autoCancel: false,
//     cancel: () => {}
//   });
//   aboutToAppear() { this.progressCtrl.openFn = () => { this.dialogCtrl.open(); };
//                     this.progressCtrl.closeFn = () => { this.dialogCtrl.close(); }; }