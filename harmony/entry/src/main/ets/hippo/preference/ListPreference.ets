/**
 * 迁移自 app/src/main/java/com/hippo/preference/ListPreference.java（inventory S0447，上游 302 行）
 *
 * ============================ 三个"错一位不报错"的风险点，全部按上游实现 ============================
 * ① **findIndexOfValue 从尾部往前扫**（`for (int i = length-1; i >= 0; i--)`）
 *    → entryValues 有重复值时返回**最后一个**下标，不是第一个。写成正序扫描会在重复值上取错项。
 * ② 找不到时返回 **-1**（不是 0）；value 为 null 或 entryValues 为 null 也返回 -1
 * ③ `setValueIndex(index)` **无边界检查**（上游直接 `mEntryValues[index].toString()`，越界即崩）；
 *    本移植加守卫并返回 false（**已登记差异**：宁可拒绝也不崩，语义等价于"无效下标无操作"）
 *
 * 其它要点
 * - onPrepareDialogBuilder：entries 或 entryValues 为 null 时**抛 IllegalStateException**（对话框不弹）
 *   → ArkTS 无异常路径，改为 `canShowDialog()` 返回 false，由调用方决定不弹（差异已登记）
 * - mClickedDialogEntryIndex = getValueIndex() → 可能为 -1（无预选）
 * - 点击某一项**等价于按确定**：立即 onDialogClosed(true) 并关闭对话框
 * - getEntry()：`index >= 0 && mEntries != null ? mEntries[index] : null`
 *   → 若 entryValues 比 entries 长，index 可能越界（上游不校验长度，会崩）；本移植返回 null 并给出警告
 * - setValue：`changed = !equals(mValue, value)`，`if (changed || !mValueSet)` → **首次必持久化**
 * - getSummary：`String.format(mSummary, entry)` —— **mSummary 是带 %s 的格式串**，不是普通文本
 *
 * ArkUI 对位：SettingsItem 行（summary 显示当前 entry）+ 自定义单选弹层（List + Radio）。
 *   行右侧显示 getEntry()（对位上游 summary 的 %s 填充）。
 */
import {
  ThemeDimens,
  ThemeElevation,
  ThemePalette,
  ThemeRadius,
  ThemeTokens,
  ThemeTypography
} from '../../common/theme/ThemeTokens';
import { SettingsItem } from '../ui/settings/SettingsItem';

export class ListPreferenceState {
  entries: string[] = [];
  entryValues: string[] = [];
  value: string = '';
  /** 上游 mValueSet：首次 setValue 必须持久化（即使值与默认相同） */
  valueSet: boolean = false;
  /** 上游 mClickedDialogEntryIndex */
  clickedDialogEntryIndex: number = -1;
  /** 上游 mSummary（含 %s 的格式串） */
  summaryFormat: string = '';

  /** 上游 findIndexOfValue：**从尾部往前扫**，返回最后出现的下标；支持 ""，仅 null/空表返回 -1 */
  findIndexOfValue(value: string | null): number {
    if (value === null || value === undefined || this.entryValues.length === 0) {
      return -1;
    }
    for (let i = this.entryValues.length - 1; i >= 0; i--) {
      if (this.entryValues[i] === value) {
        return i;
      }
    }
    return -1;
  }

  getValueIndex(): number {
    return this.findIndexOfValue(this.value);
  }

  /** 上游 getEntry()：无对应项返回空串（上游返回 null） */
  getEntry(): string {
    const index: number = this.getValueIndex();
    if (index < 0 || this.entries.length === 0) {
      return '';
    }
    if (index >= this.entries.length) {
      // 上游此处会 ArrayIndexOutOfBounds（不校验两数组长度）；本实现降级为空串（差异已登记）
      return '';
    }
    return this.entries[index];
  }

  /** 上游 getSummary()：mSummary 是格式串，用 entry 填充 %s */
  getSummary(): string {
    const entry: string = this.getEntry();
    if (this.summaryFormat.length === 0) {
      return entry;
    }
    return this.summaryFormat.replace('%s', entry);
  }

  /**
   * 上游 setValueIndex(index)：无边界检查。
   * 本实现加守卫（越界返回 false，不修改），差异已登记。
   */
  setValueIndex(index: number): boolean {
    if (index < 0 || index >= this.entryValues.length) {
      return false;
    }
    return this.setValue(this.entryValues[index]);
  }

  /** 上游 setValue(value)：首次必持久化（mValueSet 语义） */
  setValue(value: string): boolean {
    const changed: boolean = this.value !== value;
    if (changed || !this.valueSet) {
      this.value = value;
      this.valueSet = true;
      return true;
    }
    return false;
  }

  /** 上游 onPrepareDialogBuilder：两数组缺一不可（上游抛 IllegalStateException） */
  canShowDialog(): boolean {
    return this.entries.length > 0 && this.entryValues.length > 0;
  }

  /** 打开对话框时确定预选下标（上游 mClickedDialogEntryIndex = getValueIndex()） */
  prepareDialog(): number {
    this.clickedDialogEntryIndex = this.getValueIndex();
    return this.clickedDialogEntryIndex;
  }

  /** 点击某一项 = 按确定（上游 onClick 里等价 BUTTON_POSITIVE 并关闭） */
  onItemClicked(index: number): boolean {
    this.clickedDialogEntryIndex = index;
    return this.setValueIndex(index);
  }
}

let listPreferenceGroupSeq: number = 0;

@Component
export struct ListPreference {
  state: ListPreferenceState = new ListPreferenceState();
  @Prop title: string = '';
  @Prop itemEnabled: boolean = true;
  @Prop dialogTitle: string = '';
  @Prop entries: string[] = [];
  @Prop entryValues: string[] = [];
  @Prop @Watch('onValuePropChanged') value: string | null = null;
  @Prop summaryFormat: string = '';
  @Prop themeId: number = -1;
  @Prop showDivider: boolean = false;
  onChanged: (value: string) => void = (value: string) => {
  };
  @State rev: number = 0;
  @State dialogOpen: boolean = false;
  @State selectedIndex: number = -1;
  private radioGroup: string = 'list_preference';

  private palette(): ThemePalette {
    return this.themeId >= 0 ? ThemeTokens.of(this.themeId) : ThemeTokens.current();
  }

  aboutToAppear(): void {
    listPreferenceGroupSeq += 1;
    this.radioGroup = `list_preference_${listPreferenceGroupSeq}`;
    if (this.entries.length > 0) {
      this.state.entries = this.entries;
    }
    if (this.entryValues.length > 0) {
      this.state.entryValues = this.entryValues;
    }
    if (this.summaryFormat.length > 0) {
      this.state.summaryFormat = this.summaryFormat;
    }
    if (this.value !== null) {
      this.state.setValue(this.value);
    }
  }

  private onValuePropChanged(): void {
    if (this.value !== null && this.state.value !== this.value) {
      this.state.setValue(this.value);
      this.rev = this.rev + 1;
    }
  }

  private open(): void {
    if (!this.state.canShowDialog()) {
      return; // 对位上游抛 IllegalStateException 的"不弹"效果（差异已登记）
    }
    this.selectedIndex = this.state.prepareDialog();
    this.dialogOpen = true;
  }

  private selectIndex(index: number): void {
    if (this.state.onItemClicked(index)) {
      this.onChanged(this.state.value);
    }
    this.rev = this.rev + 1;
    this.dialogOpen = false;
  }

  build() {
    SettingsItem({
      title: this.title,
      summary: this.rev >= 0 ? this.state.getSummary() : this.state.getSummary(),
      itemEnabled: this.itemEnabled,
      themeId: this.themeId,
      showDivider: this.showDivider,
      onItemClick: () => {
        this.open();
      }
    })
      .bindContentCover($$this.dialogOpen, this.dialogOverlay(), {
        modalTransition: ModalTransition.NONE,
        backgroundColor: Color.Transparent,
        onDisappear: () => {
          this.dialogOpen = false;
        }
      })
  }

  @Builder
  dialogOverlay(): void {
    Stack({ alignContent: Alignment.Center }) {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor('#66000000')
        .onClick(() => {
          this.dialogOpen = false;
        })

      Column() {
        Text(this.dialogTitle.length > 0 ? this.dialogTitle : this.title)
          .fontSize(ThemeTypography.DIALOG_TITLE)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.palette().textPrimary)
          .width('100%')
          .padding({ left: 24, right: 24, top: 20, bottom: 12 })

        List() {
          ForEach(this.state.entries, (entry: string, index: number) => {
            ListItem() {
              Row({ space: ThemeDimens.SPACING_MD }) {
                Radio({ value: `${index}`, group: this.radioGroup })
                  .checked(this.state.getValueIndex() === index)
                  .radioStyle({ checkedBackgroundColor: this.palette().controlActivated })
                  .hitTestBehavior(HitTestMode.None)
                Text(entry)
                  .fontSize(ThemeTypography.PREF_TITLE)
                  .fontColor(this.palette().textPrimary)
                  .layoutWeight(1)
              }
              .width('100%')
              .constraintSize({ minHeight: ThemeDimens.PREF_ROW_MIN_HEIGHT })
              .padding({ left: 20, right: 24, top: 10, bottom: 10 })
              .onClick(() => {
                this.selectIndex(index);
              })
            }
          }, (entry: string, index: number) => `${index}:${entry}`)
        }
        .width('100%')
        .constraintSize({ maxHeight: 360 })

        Row() {
          Button({ type: ButtonType.Normal }) {
            Text($r('app.string.cancel'))
              .fontSize(ThemeTypography.BUTTON)
              .fontWeight(FontWeight.Medium)
              .fontColor(this.palette().colorPrimary)
              .textCase(TextCase.UpperCase)
          }
          .backgroundColor(Color.Transparent)
          .borderRadius(ThemeRadius.BUTTON)
          .constraintSize({ minHeight: 36, minWidth: 64 })
          .padding({ left: 12, right: 12 })
          .onClick(() => {
            this.dialogOpen = false;
          })
        }
        .width('100%')
        .justifyContent(FlexAlign.End)
        .padding({ left: 16, right: 16, top: 8, bottom: 12 })
      }
      .width('86%')
      .constraintSize({ maxWidth: 340 })
      .backgroundColor(this.palette().popupBackground)
      .borderRadius(ThemeRadius.DIALOG)
      .shadow(ThemeElevation.dialog())
      .onClick(() => {
      })
    }
    .width('100%')
    .height('100%')
  }
}
