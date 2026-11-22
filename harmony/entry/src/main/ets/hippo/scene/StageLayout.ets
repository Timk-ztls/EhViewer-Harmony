/*
 * 上游：app/src/main/java/com/hippo/scene/StageLayout.java（132 行）
 * 结构：场景容器 —— 反射拿 ViewGroup#mDisappearingChildren，把"正在消失的 Fragment View"重排 z 序，
 *       配合 dispatchDraw/drawChild 的 trick 完成转场叠加绘制
 * 平台差异（等价重写，不是逐行对照）：
 *  1. 上游全部实现依赖 FragmentManager 的 disappearing children 与自定义绘制顺序；
 *     ArkUI 声明式渲染下不存在"已移除但仍在绘制"的 View：
 *     → 容器改为 Stack + ForEach，渲染顺序由 renderOrder（上游 mDelaySceneTagList）决定；
 *     → 转场不再是绘制 trick，而是每个场景容器上的 .transition(...)。
 *  2. mDumpView / 反射 / dispatchDraw / drawChild 全部删除（无对应物且无必要）。
 *  3. 动画参数不硬编码：取自 hippo/ui/anim 下按上游 XML 1:1 搬来的场景动画参数。
 *     ArkTS 限制（本文件实测）：TransitionEffect.translate({...}) / .animation({duration, curve})
 *     这类含 union 成员的对象字面量，写在"显式类型变量 = 字面量"位置会被判
 *     arkts-no-structural-typing，只能直接写在 @Component 的 build() 调用位。
 *     因此本文件只导出"该用哪套参数"的数据，实际 .transition(...) 由场景页在 build() 里套用：
 *
 *       Stack() { this.sceneContent(tag) }
 *         .transition(tag === spec.enterTag
 *           ? TransitionEffect.OPACITY
 *               .combine(TransitionEffect.translate({ y: spec.enterTranslateY }))
 *               .animation({ duration: spec.enterDuration, curve: spec.enterCurve })
 *           : TransitionEffect.OPACITY
 *               .animation({ duration: spec.exitDuration, curve: spec.exitCurve }))
 */
import { PendingAnimation } from './StageActivity';

// 动画整段时长（ms）：数值直接来自上游场景动画 XML（同源实现见 ui/anim/scene_*.ets）
//   scene_open_enter  : alpha 200ms + translateY 350ms           → 整段 350
//   scene_open_exit   : alpha 200ms                               → 整段 200
//   scene_close_enter : alpha 250ms                               → 整段 250
//   scene_close_exit  : alpha 150ms(startOffset 100) + translateY 250ms → 整段 250
// 注：不在模块间传递 AnimSet —— 每个 anim 文件各自声明 AnimSet/AnimItem，
//     跨文件传值属于结构类型匹配，ArkTS 会报 arkts-no-structural-typing（本文件实测）。
const OPEN_ENTER_DURATION: number = 350;
const OPEN_EXIT_DURATION: number = 200;
const CLOSE_ENTER_DURATION: number = 250;
const CLOSE_EXIT_DURATION: number = 250;

/** 一次场景切换的转场参数（纯数据：规避 ArkTS 对含 union 成员字面量的结构化类型限制） */
export class StageTransitionSpec {
  readonly enterTag: string;
  readonly exitTag: string;
  /** true = 场景打开（scene_open_enter/exit）；false = 场景关闭（scene_close_enter/exit） */
  readonly opening: boolean;
  readonly enterDuration: number;
  readonly exitDuration: number;
  readonly enterCurve: Curve;
  readonly exitCurve: Curve;
  /** 进入场景纵向位移（上游 translate fromYDelta 百分比；空串表示无位移） */
  readonly enterTranslateY: string;
  /** 退出场景纵向位移（上游 translate toYDelta 百分比；空串表示无位移） */
  readonly exitTranslateY: string;

  constructor(enterTag: string, exitTag: string, opening: boolean,
              enterDuration: number, exitDuration: number,
              enterCurve: Curve, exitCurve: Curve,
              enterTranslateY: string, exitTranslateY: string) {
    this.enterTag = enterTag;
    this.exitTag = exitTag;
    this.opening = opening;
    this.enterDuration = enterDuration;
    this.exitDuration = exitDuration;
    this.enterCurve = enterCurve;
    this.exitCurve = exitCurve;
    this.enterTranslateY = enterTranslateY;
    this.exitTranslateY = exitTranslateY;
  }
}

/**
 * 把 PendingAnimation 映射成转场参数：
 *   opening=true  → 上游 R.anim.scene_open_enter / scene_open_exit
 *                   （enter: alpha 0→1 @200ms + translateY 8%→0 @350ms；exit: alpha 1→0）
 *   opening=false → 上游 R.anim.scene_close_enter / scene_close_exit
 *                   （enter: alpha 0.7→1 @250ms；exit: alpha 1→0 @150ms + translateY 0→8% @250ms）
 */
export function buildTransition(pending: PendingAnimation): StageTransitionSpec {
  if (pending.opening) {
    return new StageTransitionSpec(pending.enterTag, pending.exitTag, true,
      OPEN_ENTER_DURATION, OPEN_EXIT_DURATION,
      Curve.Friction, Curve.Sharp, '8%', '');
  }
  return new StageTransitionSpec(pending.enterTag, pending.exitTag, false,
    CLOSE_ENTER_DURATION, CLOSE_EXIT_DURATION,
    Curve.Friction, Curve.Sharp, '', '8%');
}

@Component
export struct StageLayout {
  /** 栈内场景 tag（插入序，栈底 → 栈顶），由 StageActivity#getSceneTagList 同步 */
  @Prop sceneTags: string[] = [];
  /** 渲染顺序（上游 mDelaySceneTagList），决定 z 序 */
  @Prop renderOrder: string[] = [];
  /** 场景内容由使用方提供：tag → 该场景的 UI */
  @BuilderParam sceneContent: (tag: string) => void;

  /** 上游 SceneViewComparator：按 renderOrder 索引升序（越靠后越上层） */
  private sortedTags(): string[] {
    const order: string[] = this.renderOrder.slice();
    const tags: string[] = this.sceneTags.slice();
    tags.sort((lhs: string, rhs: string): number => {
      return order.indexOf(lhs) - order.indexOf(rhs);
    });
    return tags;
  }

  build() {
    Stack() {
      ForEach(this.sortedTags(), (tag: string) => {
        Stack() {
          this.sceneContent(tag);
        }
        .width('100%')
        .height('100%')
      }, (tag: string) => tag)
    }
    .width('100%')
    .height('100%')
    .alignContent(Alignment.TopStart)
  }
}