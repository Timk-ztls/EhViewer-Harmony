/**
 * 迁移自 app/src/main/java/com/hippo/widget/RadioGridGroup.java（inventory S0536，上游 231 行）
 *
 * 上游：`extends SimpleGridLayout`，在网格布局里做**单选组**语义（AOSP RadioGroup 的网格版）：
 *   mCheckedId            当前选中项 id（默认 -1 = 未选）
 *   mProtectFromCheckedChange  为 true 时丢弃 nCheckedChange 回调（内部变更保护，避免递归）
 *   CheckedStateTracker   子按钮被勾选 → 若 id 变了：先取消旧的 → setCheckedId(新)
 *   setCheckedId(id)      → 若 !protected 且 listener 存在：onCheckedChanged(this, id)
 *   addView 时若子 RadioButton 已勾选 → 直接接管为当前选中（并取消旧的）
 *   onFinishInflate 读 android:checkedButton → 勾上并在保护态下 setCheckedId
 *   clearCheck() → 取消当前选中并把 mCheckedId 置 -1（**不触发回调**）
 *
 * ArkUI 对位：
 *   SimpleGridLayout → `Flex({ wrap: FlexWrap.Wrap })`（对位上游的网格换行；SimpleGridLayout 的列数由子项宽度决定）
 *   子 RadioButton    → 调用方在 slot 里渲染，点击时调 `state.onChildChecked(id)`
 *   mProtectFromCheckedChange → 同名保护位（**这是单选组正确性的核心**：不加会让"取消旧项"触发一次回调，
 *                            调用方收到两次 onCheckedChanged）
 *   setCheckedStateForView(id, checked) → 由 slot 通过 `state.isChecked(id)` 读，组件不持有子控件
 *
 * 差异（已登记 MR）：
 *   1) 上游用 View id（R.id.xxx）标识子项；ArkTS 无 View id，改用调用方给的**数字 id**（与上游 id 等价使用）。
 *   2) 上游 addView 时"接管已勾选子项"的行为在 ArkUI 没有对等时机（无 onFinishInflate）；
 *      改为在 `state.initChecked(id)` 显式调用（ui-scene 在构造后调一次即可，语义相同）。
 */
export interface OnCheckedChangeListener {
  onCheckedChanged(group: RadioGridGroupState, checkedId: number): void;
}

/** 具名实现类（ArkTS 禁止无类型对象字面量） */
export class OnCheckedChangeListenerImpl implements OnCheckedChangeListener {
  private fn: (group: RadioGridGroupState, checkedId: number) => void;

  constructor(fn: (group: RadioGridGroupState, checkedId: number) => void) {
    this.fn = fn;
  }

  onCheckedChanged(group: RadioGridGroupState, checkedId: number): void {
    this.fn(group, checkedId);
  }
}

export class RadioGridGroupState {
  /** 上游 mCheckedId，-1 = 未选 */
  checkedId: number = -1;
  /** 上游 mProtectFromCheckedChange */
  protectFromCheckedChange: boolean = false;
  listener: OnCheckedChangeListener | null = null;

  getCheckedRadioButtonId(): number {
    return this.checkedId;
  }

  isChecked(id: number): boolean {
    return this.checkedId === id;
  }

  /** 上游 setCheckedId(id)：保护态下只改状态、不回调 */
  setCheckedId(id: number): void {
    this.checkedId = id;
    if (this.protectFromCheckedChange) {
      return;
    }
    if (this.listener !== null) {
      this.listener.onCheckedChanged(this, id);
    }
  }

  /** 上游 CheckedStateTracker.onCheckedChanged：子项被勾选时接管为唯一选中 */
  onChildChecked(id: number, checked: boolean): void {
    if (!checked || this.checkedId === id) {
      return;
    }
    this.protectFromCheckedChange = true;
    // 旧项由 UI 依 isChecked() 自动取消（组件无子控件引用）
    this.protectFromCheckedChange = false;
    this.setCheckedId(id);
  }

  /** 上游 onFinishInflate 的 android:checkedButton 等价入口 */
  initChecked(id: number): void {
    if (id === -1) {
      return;
    }
    this.protectFromCheckedChange = true;
    this.checkedId = id;
    this.protectFromCheckedChange = false;
    this.setCheckedId(id);
  }

  /** 上游 clearCheck()：把 mCheckedId 置 -1（**不触发回调**） */
  clearCheck(): void {
    this.checkedId = -1;
  }

  setOnCheckedChangeListener(listener: OnCheckedChangeListener | null): void {
    this.listener = listener;
  }
}

@Component
export struct RadioGridGroup {
  state: RadioGridGroupState = new RadioGridGroupState();
  /** 子项数量（对位上游 addView 的子 View 集合） */
  @Prop itemCount: number = 0;
  /** 子项渲染：调用方按 index 画 RadioButton，并在点击时调 state.onChildChecked(id) */
  @BuilderParam item: (index: number) => void = this.emptyItem;

  @Builder
  emptyItem(index: number): void {
  }

  build() {
    Flex({ wrap: FlexWrap.Wrap }) {
      ForEach(this.indices(), (index: number) => {
        Column() {
          this.item(index)
        }
        .onClick(() => {
          this.state.onChildChecked(index, true);
        })
      }, (index: number) => `${index}`)
    }
    .width('100%')
  }

  private indices(): number[] {
    const arr: number[] = [];
    for (let i = 0; i < this.itemCount; i++) {
      arr.push(i);
    }
    return arr;
  }
}
