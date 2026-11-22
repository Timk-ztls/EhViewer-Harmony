/**
 * 迁移自 app/src/main/java/com/hippo/text/LinkMovementMethod2.java（S0463，上游 216 行）
 *
 * 判据：**纯逻辑（键盘/方向键导航），无 UI**。
 * 上游 `extends ScrollingMovementMethod`，给 TextView 加"用方向键在链接间移动"的能力：
 *   · CLICK=1 / UP=2 / DOWN=3 三种动作
 *   · handleMovementKey：**DPAD_CENTER / ENTER** 且 `metaStateHasNoModifiers` 且
 *     `ACTION_DOWN` 且 `repeatCount == 0` → action(CLICK)；否则回落 super
 *   · up()/left() → action(UP)；down()/right() → action(DOWN)；未命中回落 super
 *   · canSelectArbitrarily() → true
 *   · initialize()：`Selection.removeSelection(text)` + 移除 FROM_BELOW 标记
 *   · onTakeFocus(dir)：清选区；`dir & FOCUS_BACKWARD` → 打 FROM_BELOW 标记，否则移除
 *   · 单例 getInstance()
 *
 * ArkUI 对位：没有 Spannable / Selection / MovementMethod 体系；链接点击由 `Span(...).onClick` 承担，
 *   键盘导航由 `onKeyEvent` 承担。因此本文件保留**可测的判定逻辑**（动作映射、按键前置条件、焦点方向标记），
 *   供调用方在 `onKeyEvent` 里复用；span 遍历与选区操作不移植（平台无对位，且 ArkUI 的焦点系统自己管）。
 *
 * 差异（已登记 MR）：
 *   1) `Selection.removeSelection` / `FROM_BELOW` span 标记 → ArkUI 无选区概念，仅保留"方向标记"的语义常量
 *   2) span 遍历（找上/下一个 ClickableSpan）→ 由调用方按业务顺序决定（ArkUI 无文字布局查询）
 */
export class MovementAction {
  static readonly CLICK: number = 1;
  static readonly UP: number = 2;
  static readonly DOWN: number = 3;
}

/** 对位 android.view.KeyEvent 中本类用到的常量 */
export class MovementKey {
  static readonly DPAD_CENTER: number = 23;
  static readonly ENTER: number = 66;
  static readonly DPAD_UP: number = 19;
  static readonly DPAD_DOWN: number = 20;
  static readonly DPAD_LEFT: number = 21;
  static readonly DPAD_RIGHT: number = 22;
  static readonly ACTION_DOWN: number = 0;
}

export class LinkMovementMethod2 {
  private static instance: LinkMovementMethod2 | null = null;
  /** 对位 FROM_BELOW 标记是否存在（上游用 span 承载，这里用布尔） */
  fromBelow: boolean = false;

  static getInstance(): LinkMovementMethod2 {
    if (LinkMovementMethod2.instance === null) {
      LinkMovementMethod2.instance = new LinkMovementMethod2();
    }
    return LinkMovementMethod2.instance;
  }

  /** 上游 canSelectArbitrarily() → true */
  canSelectArbitrarily(): boolean {
    return true;
  }

  /**
   * 上游 handleMovementKey：**只有 CLICK 有前置条件** ——
   * 无修饰键 && ACTION_DOWN && repeatCount === 0。返回动作编号，0 表示不处理（回落 super）。
   */
  static actionForKey(keyCode: number, hasModifiers: boolean, action: number, repeatCount: number): number {
    if (keyCode === MovementKey.DPAD_CENTER || keyCode === MovementKey.ENTER) {
      if (!hasModifiers && action === MovementKey.ACTION_DOWN && repeatCount === 0) {
        return MovementAction.CLICK;
      }
      return 0;
    }
    if (keyCode === MovementKey.DPAD_UP || keyCode === MovementKey.DPAD_LEFT) {
      return MovementAction.UP;
    }
    if (keyCode === MovementKey.DPAD_DOWN || keyCode === MovementKey.DPAD_RIGHT) {
      return MovementAction.DOWN;
    }
    return 0;
  }

  /** 上游 initialize()：清选区 + 移除 FROM_BELOW */
  initialize(): void {
    this.fromBelow = false;
  }

  /** 上游 onTakeFocus(dir)：FOCUS_BACKWARD(0x1) 置 FROM_BELOW，否则清除 */
  onTakeFocus(dir: number): void {
    this.fromBelow = (dir & 0x1) !== 0;
  }
}