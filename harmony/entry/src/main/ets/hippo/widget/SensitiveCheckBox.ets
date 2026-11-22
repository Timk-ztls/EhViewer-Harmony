/**
 * 迁移自 app/src/main/java/com/hippo/widget/SensitiveCheckBox.java（inventory S0537 之外的 S0542，上游 65 行）
 *
 * 上游核心是"区分程序化设置 vs 用户点击"：
 *   performClick()  ：mFromUser=true → super.performClick() → mFromUser=false
 *   setChecked(v)   ：super.setChecked(v) 后强制回调 onCheckedChanged(this, v, mFromUser)
 *   interface OnCheckedChangeListener { onCheckedChanged(view, isChecked, fromUser); }
 * 用途：避免"程序化回填状态"被当成用户操作（例如列表滚动复用条目时触发脏标记）。
 *
 * ArkUI 对位：
 *   Checkbox.onChange(v)  对应用户点击；`.select(v)` 对应 setChecked。
 *   ArkUI 的 onChange **在程序化改变 select 时也会触发**（与 Android setChecked 触发回调一致），
 *   故用"点击标记"复刻 fromUser：用户点击时 onClick 先于 onChange 触发 → 置位 → onChange 里读取并清位。
 *   程序化路径直接调 setCheckedProgrammatic()，不经过 onClick，因此 fromUser=false。
 *
 * 注意：@Link 用于让父组件读写选中态（对位 getChecked()/setChecked()）；父侧如直接改 @Link 变量而不调
 *      setCheckedProgrammatic()，本组件无法得知"这是程序化改动"（ArkUI 无 View 属性变更钩子），
 *      故约定：程序化改动请走 setCheckedProgrammatic()。已在 MR「平台差异」登记。
 */
export interface OnCheckedChangeListener {
  onCheckedChanged(isChecked: boolean, fromUser: boolean): void;
}

/** 具名实现类：ArkTS 禁止无类型对象字面量 */
export class CheckedChangeListenerImpl implements OnCheckedChangeListener {
  private fn: (isChecked: boolean, fromUser: boolean) => void;

  constructor(fn: (isChecked: boolean, fromUser: boolean) => void) {
    this.fn = fn;
  }

  onCheckedChanged(isChecked: boolean, fromUser: boolean): void {
    this.fn(isChecked, fromUser);
  }
}

@Component
export struct SensitiveCheckBox {
  /** 选中态；对位 isChecked()/setChecked() */
  @Link checked: boolean;
  @Prop enabledState: boolean = true;
  @Prop label: string = '';
  /** 上游 mOnCheckedChangeListener */
  listener: OnCheckedChangeListener | null = null;
  private fromUser: boolean = false;
  /**
   * 程序化改动标记（修 P2）：**不依赖 onClick 与 onChange 的先后顺序**。
   * ArkUI 若先发 onChange 再发 onClick，靠"点击标记"会得到 fromUser=false（本控件失效）；
   * 因此改为：程序化路径先置 pending，onChange 里看到 pending 就判定为非用户操作并清位。
   * 用户点击路径 pending 恒为 false ⇒ fromUser=true（不依赖顺序，两种顺序都对）。
   */
  private programmaticPending: boolean = false;

  /** 上游 setChecked(boolean)：程序化设置，fromUser 恒为 false */
  setCheckedProgrammatic(value: boolean): void {
    this.programmaticPending = true;
    this.checked = value;
    if (this.listener !== null) {
      this.listener.onCheckedChanged(value, false);
    }
  }

  build() {
    Row({ space: 4 }) {
      Checkbox()
        .select(this.checked)
        .enabled(this.enabledState)
        .onClick(() => {
          // 用户点击：Click 先于 Change，用于标记 fromUser（对位上游 performClick 里的 mFromUser）
          this.fromUser = true;
        })
        .onChange((value: boolean) => {
          // 程序化标记优先（与 onClick/onChange 的相对顺序无关）
          const user: boolean = !this.programmaticPending;
          this.programmaticPending = false;
          this.fromUser = false;
          if (this.listener !== null) {
            this.listener.onCheckedChanged(value, user);
          }
        })
      if (this.label.length > 0) {
        Text(this.label)
          .fontSize(14)
      }
    }
  }
}
