/**
 * 迁移自 app/src/main/java/com/hippo/widget/CuteSpinner.java（inventory S0516，上游 61 行）
 *
 * 上游行为：AppCompatSpinner 的薄包装，唯一逻辑是 init() 里读 `android:entries` 属性，
 *          有 entries 就用 item_cute_spinner_item 布局造 ArrayAdapter 并 setAdapter。
 *          （下拉项布局用 support_simple_spinner_dropdown_item）
 *
 * ArkUI 对位：`Select` 组件本身就是"选项集合 + 下拉"，没有 attribute 注入通道，
 *          因此把 entries 提升为组件入参 `options: SelectOption[]`；
 *          上游 XML 里的 `android:entries` 由调用方在构造时转成 options（等价于 init 里那段）。
 *          `@Prop selected` 对位 setSelection()（受控），`onSelected` 对位 OnItemSelectedListener。
 *
 * 差异：
 *   1) 上游可用 custom layout(item_cute_spinner_item)，ArkUI Select 的菜单项样式只能通过 theme/样式统一，
 *      无法逐项自定义布局 —— 已在 MR「平台差异」登记（视觉项，不影响行为）。
 *   2) 上游 mode(DIALOG/DROPDOWN) 两种弹层形态，ArkUI Select 默认下拉菜单；DIALOG 形态需调用方改用
 *      bindMenu/CustomDialog，组件暴露 `useDialog: boolean` 仅作语义提示（不改变渲染路径）。
 */
import { ThemePalette, ThemeTokens } from '../../common/theme/ThemeTokens';

@Component
export struct CuteSpinner {
  /** 对位上游 android:entries */
  @Prop options: SelectOption[] = [];
  /** 当前选中下标，对位 getSelectedItemPosition()/setSelection() */
  @Prop selected: number = 0;
  /** 占位文案，对位 spinner 无选中时的提示 */
  @Prop placeholder: string = '';
  /** 上游 mode=DIALOG 的语义提示（见文件头差异 2） */
  @Prop useDialog: boolean = false;
  @Prop themeId: number = -1;
  /** 对位 OnItemSelectedListener.onItemSelected */
  onSelected: (index: number, value: string) => void = () => {
  };

  private palette(): ThemePalette {
    return this.themeId >= 0 ? ThemeTokens.of(this.themeId) : ThemeTokens.current();
  }

  build() {
    Select(this.options)
      .selected(this.selected)
      .value(this.selected >= 0 && this.selected < this.options.length ? this.options[this.selected].value : this.placeholder)
      .fontColor(this.palette().textPrimary)
      .selectedOptionFontColor(this.palette().colorPrimary)
      .optionFontColor(this.palette().textPrimary)
      .menuBackgroundColor(this.palette().popupBackground)
      .backgroundColor(Color.Transparent)
      .width('100%')
      .onSelect((index: number, value?: string) => {
        this.selected = index;
        this.onSelected(index, value === undefined ? '' : value);
      })
  }
}
