/**
 * 迁移自 app/src/main/java/com/hippo/ehviewer/preference/DefaultCategoryPreference.java（S0166，上游 63 行）
 *
 * 判据：**UI 组件行**（`extends DialogPreference`），覆写三处：
 *   onPrepareDialogBuilder：对话框内放分类单选列表
 *   onDialogCreated：绑定当前值
 *   onDialogClosed(positiveResult)：**true 时**写回所选分类（false 不写）
 * ⇒ 组合已交付的 `DialogPreference`（自带"确认才提交"的状态机）+ 分类单选内容。
 *
 * 分类位复用已交付的 `CategoryFlags.OPTIONS`（一手核对：按**名字**绑定位值，界面顺序 ≠ 位值顺序）。
 */
import { DialogPreference, DialogPreferenceState } from '../../preference/DialogPreference';
import { CategoryFlags, CategoryOption, CategoryTable, CategoryTableState } from '../widget/CategoryTable';
import { Settings } from '../Settings';

export class DefaultCategoryHelper {
  static readonly DEFAULT_CATEGORIES: number = Settings.DEFAULT_DEFAULT_CATEGORIES;

  static formatSummary(mask: number, fallbackSummary: string): string {
    if ((mask & CategoryFlags.ALL_CATEGORY) === CategoryFlags.ALL_CATEGORY) {
      return fallbackSummary.length > 0 ? fallbackSummary : 'All';
    }
    const selected: string[] = [];
    for (let i = 0; i < CategoryFlags.OPTIONS.length; i++) {
      const opt: CategoryOption = CategoryFlags.OPTIONS[i];
      if ((mask & opt.bit) !== 0) {
        selected.push(opt.label);
      }
    }
    if (selected.length === 0) {
      return 'None';
    }
    return selected.join(', ');
  }
}

@Component
export struct DefaultCategoryPreference {
  state: DialogPreferenceState = new DialogPreferenceState();
  @Prop title: string = '';
  @Prop summary: string = '';
  @Prop dialogTitle: string = '';
  @Prop current: number = -1;
  @Prop themeId: number = -1;
  @Prop showDivider: boolean = false;
  onChanged: (category: number) => void = (category: number) => {
  };
  private tableState: CategoryTableState = new CategoryTableState();
  @State selected: number = DefaultCategoryHelper.DEFAULT_CATEGORIES;
  @State rev: number = 0;

  private loadMask(): number {
    return this.current >= 0 ? this.current : Settings.getDefaultCategories();
  }

  private syncTable(): void {
    const mask: number = this.loadMask();
    this.selected = mask;
    this.tableState.setCategory(mask);
    this.state.summary = DefaultCategoryHelper.formatSummary(mask, this.summary);
  }

  aboutToAppear(): void {
    this.state.title = this.title;
    this.state.dialogTitle = this.dialogTitle;
    this.syncTable();
  }

  build() {
    DialogPreference({
      state: this.state,
      themeId: this.themeId,
      showDivider: this.showDivider,
      onPrepareDialog: () => {
        this.syncTable();
      },
      onDialogClosed: (positiveResult: boolean) => {
        // 仅确定时写回（取消不提交 —— 由 DialogPreference 的 which=NEGATIVE 初始值保证）
        if (positiveResult) {
          const nextMask: number = this.tableState.getCategory();
          this.selected = nextMask;
          Settings.putDefaultCategories(nextMask);
          this.state.summary = DefaultCategoryHelper.formatSummary(nextMask, this.summary);
          this.onChanged(nextMask);
        }
        this.rev = this.rev + 1;
      },
      content: () => {
        this.dialogContent()
      }
    })
  }

  @Builder
  dialogContent(): void {
    CategoryTable({
      state: this.tableState,
      themeId: this.themeId,
      onChange: (category: number) => {
        this.selected = category;
      }
    })
  }
}
