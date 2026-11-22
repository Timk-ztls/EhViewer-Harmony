/*
 * 上游：app/src/main/java/com/hippo/ehviewer/ui/scene/gallery/list/EnterGalleryDetailTransaction.java
 *       （inventory S0238，51 行）
 * 目标：harmony/entry/src/main/ets/hippo/ehviewer/ui/scene/gallery/list/EnterGalleryDetailTransaction.ets
 *
 * 背景：从列表进入**画廊详情页**时的共享元素转场（缩略图从列表位置飞到大图位置）。
 *
 * ── 上游行为逐条对照 ────────────────────────────────────────────────────────
 * `class EnterGalleryDetailTransaction implements TransitionHelper`
 *   字段 `mThumb: View`（列表项的缩略图 View；它的 transitionName 由 TransitionNameFactory 生成）
 *   `onTransition(context, transaction, exit, enter)`:
 *     ① `if (mThumb == null || !(enter instanceof GalleryDetailScene)) return false;`
 *        → 缩略图缺失、或目标不是详情页 → **不接管**转场（返回 false 让默认动画跑）
 *     ② `String transitionName = ViewCompat.getTransitionName(mThumb);`
 *     ③ `if (transitionName != null)`：
 *          exit.setSharedElementReturnTransition(trans_move)
 *          exit.setExitTransition(trans_fade)
 *          enter.setSharedElementEnterTransition(trans_move)
 *          enter.setEnterTransition(trans_fade)
 *          transaction.addSharedElement(mThumb, transitionName)
 *     ④ `return true`（**即使 transitionName 为 null 也返回 true** —— 见「关键行为」1）
 *
 * ── 关键行为（容易写错的三个点）────────────────────────────────────────────
 * 1. **`return true` 在 if 外面**：只要 ① 过了，无论有没有 transitionName 都返回 true。
 *    即"我接管了转场"，只是没有共享元素 —— 默认转场动画**不会**跑。
 * 2. 四个 transition 是**两两成对**：exit/enter 各有 sharedElement 与普通两套；
 *    上游写了 4 次 `inflateTransition`（每次都新建），本实现按语义聚成两个名字常量
 *    （`trans_move` / `trans_fade`），避免读起来像四个不同资源。
 * 3. `instanceof GalleryDetailScene` 在 ArkTS 里用**场景 tag/类型串**判断
 *    （`StageTransactor` 只给 tag，不给 Fragment 实例）→ 见「平台差异」2。
 *
 * ── 平台差异 ────────────────────────────────────────────────────────────────
 * 1. **Android 的 FragmentTransaction / TransitionInflater 在鸿蒙不存在**：
 *    ArkUI 的共享元素转场是 `geometryTransition(id)` + `TransitionEffect`，声明在组件上，
 *    不是"运行时往 transaction 里 addSharedElement"。因此本类不"执行"转场，
 *    而是**产出一个转场描述**（是否接管 / 共享元素名 / 两套动画名），由 Scene 层消费。
 * 2. **`instanceof GalleryDetailScene`**：本仓库 `SceneTransitionHelper.onTransition(transactor, exitTag, enterTag)`
 *    只传 **tag 字符串**（`SceneTypes.ets`）。所以判断改为"enter 的 tag 是否等于详情页 tag"，
 *    并把期望的 tag 作为构造参数（默认 `'GalleryDetailScene'`，与 Scene 注册名一致）。
 *    这是**载体变化**，不是行为变化：上游也是按"是不是那个类"决定，这里按"是不是那个 tag"。
 * 3. `mThumb == null` → 本实现用 `thumbTransitionName === ''`（空串）表达"没有缩略图"，
 *    与上游 null 判断等价（上游 null 的唯一作用就是走 ① 的 false 分支）。
 *
 * ── 关联 ────────────────────────────────────────────────────────────────────
 * - 转场名来源：`TransitionNameFactory.getThumbTransitionName(gid)`（S0267，已移植）
 * - 接口：`hippo/scene/SceneTypes.ets` 的 `SceneTransitionHelper`（onTransition(transactor, exitTag, enterTag)）
 * - 转场资源：上游 `@transition/trans_move`、`@transition/trans_fade`（ArkUI 侧用等价参数表达，见 1）
 */

import { SceneTransitionHelper } from '../../../../../scene/SceneTypes';
import { StageTransactor } from '../../../../../scene/SceneTypes';

/** 上游 @transition/trans_move（共享元素位移动画） */
export const TRANSITION_MOVE: string = 'trans_move';
/** 上游 @transition/trans_fade（普通淡入淡出） */
export const TRANSITION_FADE: string = 'trans_fade';

/** 本类产出的转场描述（供 Scene/Stage 层用 ArkUI 的 geometryTransition/TransitionEffect 消费） */
export class GalleryDetailTransitionSpec {
  /** 是否接管转场（上游 onTransition 的返回值） */
  takeOver: boolean = false;
  /** 共享元素名（上游 `ViewCompat.getTransitionName(mThumb)`）；空串 = 无共享元素 */
  sharedElementName: string = '';
  /** exit 场景的共享元素返回动画（上游 sharedElementReturnTransition） */
  exitSharedElementTransition: string = TRANSITION_MOVE;
  /** exit 场景的退出动画（上游 setExitTransition） */
  exitTransition: string = TRANSITION_FADE;
  /** enter 场景的共享元素进入动画（上游 sharedElementEnterTransition） */
  enterSharedElementTransition: string = TRANSITION_MOVE;
  /** enter 场景的进入动画（上游 setEnterTransition） */
  enterTransition: string = TRANSITION_FADE;
}

export class EnterGalleryDetailTransaction implements SceneTransitionHelper {
  /** 缩略图的共享元素名（`TransitionNameFactory.getThumbTransitionName(gid)`）；空串 = 没有缩略图 */
  private thumbTransitionName: string;
  /** 详情页的场景 tag（`instanceof GalleryDetailScene` 的等价判据，见文件头 2） */
  private detailSceneTag: string;

  /**
   * @param thumbTransitionName 缩略图共享元素名；传 `''` 等价于上游 `mThumb == null`
   * @param detailSceneTag 详情页 tag（默认与 Scene 注册名一致）
   */
  constructor(thumbTransitionName: string, detailSceneTag: string = 'GalleryDetailScene') {
    this.thumbTransitionName = thumbTransitionName;
    this.detailSceneTag = detailSceneTag;
  }

  /**
   * 上游 `onTransition(...)` 的等价实现（接口签名见 SceneTypes）：
   * 返回 true = 接管转场（默认动画不跑）。详细描述用 `buildSpec()` 取。
   */
  onTransition(transactor: StageTransactor, exitTag: string, enterTag: string): boolean {
    return this.buildSpec(enterTag).takeOver;
  }

  /**
   * 产出转场描述（本类的实际内容）。
   * 上游顺序逐字保留：
   *   ① 无缩略图 或 目标不是详情页 → takeOver=false（**什么都不设**）
   *   ② transitionName 为空      → takeOver=**true**（接管但没有共享元素，见文件头 1）
   *   ③ 否则                     → takeOver=true + 四套动画 + 共享元素名
   */
  buildSpec(enterTag: string): GalleryDetailTransitionSpec {
    const spec = new GalleryDetailTransitionSpec();
    // ① 上游：if (mThumb == null || !(enter instanceof GalleryDetailScene)) return false;
    if (this.thumbTransitionName === '' || enterTag !== this.detailSceneTag) {
      spec.takeOver = false;
      return spec;
    }
    // ②③ 上游：transitionName 非空才设置四套动画；但 return true 在 if 外面
    spec.takeOver = true;
    if (this.thumbTransitionName !== '') {
      spec.sharedElementName = this.thumbTransitionName;
      spec.exitSharedElementTransition = TRANSITION_MOVE;
      spec.exitTransition = TRANSITION_FADE;
      spec.enterSharedElementTransition = TRANSITION_MOVE;
      spec.enterTransition = TRANSITION_FADE;
    }
    return spec;
  }
}
