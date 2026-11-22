/**
 * 迁移自 app/src/main/java/com/hippo/widget/HackyTextInputEditText.java（inventory S0523，上游 74 行）
 *
 * ============================ 判据：**平台缺陷路径不存在 → 死代码（陷阱 100 的 ②）** ============================
 * 上游源码自己的注释就是判据：
 *   `// Avoid crash on some Meizu devices`
 *   `// https://github.com/android-in-china/Compatibility/issues/11`
 *   `// https://stackoverflow.com/questions/51891415/nullpointerexception-on-meizu-devices-in-editor-updatecursorpositionmz`
 *
 * 它做的事：
 *   1) 反射 `android.widget.Editor` 的方法表，检测是否存在 **魅族私有方法 `updateCursorPositionMz`**
 *   2) 若存在 → 反射取 `TextView.mHint` 字段并 `setAccessible(true)`，`getHint()` 时**直接读字段**，
 *      绕过 `TextInputEditText.getHint()` —— 因为后者在魅族 ROM 上会调到 `updateCursorPositionMz` 而 NPE
 *   3) 若不存在 → `super.getHint()`（正常路径）
 *
 * ⇒ **这是纯粹的魅族 ROM 输入法崩溃规避**：
 *   · 判据对象是**厂商私有方法**（`updateCursorPositionMz` 只在魅族 ROM 的 Editor 里存在）
 *   · 鸿蒙既没有 `android.widget.Editor`，也没有该私有方法，更没有该 NPE 路径
 *   · ⇒ `HAS_METHOD_UPDATE_CURSOR_POSITION_MZ` 恒为 false ⇒ `getHint()` 恒等于 `super.getHint()`
 *   **整个类在鸿蒙上退化为"一个带 hint 的输入框"，没有任何需要移植的行为。**
 *
 * 本文件保留：
 *   · 同名组件（调用点 1:1，避免 ui-scene 侧还要改名）
 *   · `VENDOR_WORKAROUND_NEEDED = false` 常量 + 上游两个 issue 链接（**判定记录**，供后续审计对照）
 *   · 组件只做 `TextInput` + hint 透传
 *
 * 差异（已登记 MR）：反射检测 / 字段直读 / `setAccessible` 全部不移植（无对位对象）。
 * **不删掉这个类名**：它在 inventory 里有一条，删了会让"1:1 覆盖"出现空洞；正确做法是"存在但明确是 no-op"。
 */
import { hilog } from '@kit.PerformanceAnalysisKit';

const LOG_DOMAIN: number = 0x0000;
const LOG_TAG: string = 'HippoWidget.HackyTextInputEditText';

export class HackyTextInputConst {
  /**
   * 上游 `HAS_METHOD_UPDATE_CURSOR_POSITION_MZ` 在鸿蒙上的取值：**恒为 false**
   * （`android.widget.Editor.updateCursorPositionMz` 是魅族 ROM 私有方法，鸿蒙不存在）
   */
  static readonly VENDOR_WORKAROUND_NEEDED: boolean = false;
  /** 上游注释里记录的两个 bug 链接（判定记录，勿删） */
  static readonly UPSTREAM_ISSUE_1: string =
    'https://github.com/android-in-china/Compatibility/issues/11';
  static readonly UPSTREAM_ISSUE_2: string =
    'https://stackoverflow.com/questions/51891415/nullpointerexception-on-meizu-devices-in-editor-updatecursorpositionmz';
}

/** 上游 `getHint()` 的净语义：有规避需求时读字段，否则读 super；鸿蒙上恒为后者 */
export class HackyHintResolver {
  static resolveHint(_superHint: string, needsWorkaround: boolean = HackyTextInputConst.VENDOR_WORKAROUND_NEEDED): string {
    // 上游：needsWorkaround && 字段可读 → 读字段（值等于 mHint）；否则 super.getHint()
    // 两条路径的**返回值相同**（都是 mHint）—— 差别只在"是否绕过会 NPE 的实现"
    return _superHint;
  }
}

@Component
export struct HackyTextInputEditText {
  @Prop placeholder: string = '';
  @Prop text: string = '';
  @State privateValue: string = '';
  onTextChange: (value: string) => void = (value: string) => {
  };

  aboutToAppear(): void {
    // 装配期提示：本组件是 no-op 包装，若调用方以为它有特殊行为，会误判问题原因
    hilog.info(LOG_DOMAIN, LOG_TAG,
      '%{public}s', 'HackyTextInputEditText is a no-op on HarmonyOS (Meizu-only IME crash workaround)');
    this.privateValue = this.text;
  }

  build() {
    TextInput({ placeholder: this.placeholder, text: this.privateValue })
      .onChange((value: string) => {
        this.privateValue = value;
        this.onTextChange(value);
      })
  }
}
