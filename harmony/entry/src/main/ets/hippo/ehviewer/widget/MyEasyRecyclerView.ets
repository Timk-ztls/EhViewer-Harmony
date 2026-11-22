/**
 * 迁移自 app/src/main/java/com/hippo/ehviewer/widget/MyEasyRecyclerView.kt（inventory S0302，上游 25 行）
 *
 * ============================ 一手语义：本类**只有一处自有行为** ============================
 * `class MyEasyRecyclerView : EasyRecyclerView { override fun onTouchEvent(ev): Boolean }`
 *   `try { return super.onTouchEvent(ev) } catch (e: IllegalArgumentException) { Log.e(...) } return true`
 * ⇒ 自有行为只有一条：**吞掉 RecyclerView 触摸路径抛出的 IllegalArgumentException**（框架已知缺陷，
 *   典型触发是滚动/回收与触摸动画竞争时的 "Scrapped or attached views may not be recycled"）。
 *   其余全部能力来自 `EasyRecyclerView`（下拉刷新 / FastScroller / 多选 CustomChoiceListener / 状态管理）。
 *
 * ============================ 判据 ============================
 * ① **try/catch 部分 → 平台缺陷路径不存在**：ArkUI 的 `List` 触摸派发不经 RecyclerView 的回收逻辑，
 *    没有可抛该异常的路径（同 `SafeCoordinatorLayout` 的空 try/catch、`ShadowLinearLayout` 的 nine-patch 分支）。
 * ② **父类能力 → 受 D-022 约束**：`EasyRecyclerView` 已裁决不移植，其四项能力分别对位为
 *    下拉刷新 `Refresh` / 到底加载 `List.onReachEnd` / 空错态 `ContentLayout` 三态 / FastScroller 不移植。
 *    ⇒ 本组件只提供**调用点需要的列表表面**（itemCount + item 渲染 + onReachEnd），
 *      不自造一套 RecyclerView。
 *
 * 结论：本类是"**别名 + 空实现**"型（与 `HackyTextInputEditText` 同源判断），
 *   **无自有逻辑可断言** —— 因此本文件不写断言（没有逻辑就没有可断言的东西，
 *   硬写"存在性断言"是浪费；同 Message/Activity/Url 三个纯外观类的处理）。
 *
 * 差异（已登记 MR）：
 *   1) `onTouchEvent` 的 try/catch 不移植（无该异常路径）
 *   2) 继承 `EasyRecyclerView` → 组合 `List`（D-022）
 *   3) 多选（CustomChoiceListener）不在本类：本类上游也没实现它（那是父类能力），
 *      需要多选的调用点应直接用 `ContentLayout` 的列表 + 自己的选择状态机
 */
import { hilog } from '@kit.PerformanceAnalysisKit';

const LOG_DOMAIN: number = 0x0000;
const LOG_TAG: string = 'HippoWidget.MyEasyRecyclerView';

@Component
export struct MyEasyRecyclerView {
  @Prop itemCount: number = 0;
  /** 对位 RecyclerView.Adapter 的 item 渲染 */
  @BuilderParam item: (index: number) => void = this.emptyItem;
  /** 对位 `List.onReachEnd`（EasyRecyclerView 的到底加载） */
  onReachEnd: () => void = () => {
  };

  @Builder
  emptyItem(index: number): void {
  }

  aboutToAppear(): void {
    // 装配期提示：上游本类的自有行为（try/catch）在鸿蒙不存在，
    // 若调用方以为它能兜 RecyclerView 异常，会误判问题原因
    hilog.info(LOG_DOMAIN, LOG_TAG,
      '%{public}s', 'MyEasyRecyclerView: touch-exception workaround is a no-op on HarmonyOS (D-022)');
  }

  private indices(): number[] {
    const arr: number[] = [];
    for (let i = 0; i < this.itemCount; i++) {
      arr.push(i);
    }
    return arr;
  }

  build() {
    List() {
      ForEach(this.indices(), (index: number) => {
        ListItem() {
          this.item(index)
        }
      }, (index: number) => `${index}`)
    }
    .width('100%')
    .height('100%')
    .onReachEnd(() => {
      this.onReachEnd();
    })
  }
}
