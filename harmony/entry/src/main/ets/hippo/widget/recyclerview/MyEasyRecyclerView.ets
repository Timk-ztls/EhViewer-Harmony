/**
 * 迁移自 app/src/main/java/com/hippo/widget/recyclerview/MyEasyRecyclerView.java（inventory S0539，上游 3 行）
 *
 * 上游本体是空类：`public class MyEasyRecyclerView { }`（在 Android 侧只是占位/预留，
 * 真正的列表行为来自 androidx 的 EasyRecyclerView，属于 ui-scene 的列表装配）。
 * 为保持"上游有文件、鸿蒙有对应文件"的一对一，这里保留同名组件作为**纯容器**：
 * 只透传子内容，不引入任何测量/滚动策略（与上游零逻辑一致）。
 */
@Component
export struct MyEasyRecyclerView {
  @BuilderParam content: () => void = this.empty;

  @Builder
  empty(): void {
  }

  build() {
    Column() {
      this.content()
    }
    .width('100%')
  }
}
