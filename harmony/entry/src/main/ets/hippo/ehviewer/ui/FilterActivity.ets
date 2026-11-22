/**
 * 迁移自 app/src/main/java/com/hippo/ehviewer/ui/FilterActivity.java（S0198，上游 393 行）
 *
 * 判据：**页面内容**（页面壳 `ToolbarActivity` 属 ui-scene 基类体系，不在此文件）
 *
 * 一手语义（逐条来自源码，非推断）
 *   · updateView(animation)：`mFilterList` 为空 → `showView(1)`（空态）；否则 `showView(0)`（列表）
 *   · 菜单：home → finish；action_add → showAddFilterDialog；action_tip → showTipDialog
 *   · showTipDialog：title=filter、message=filter_tip（纯提示）
 *   · showAddFilterDialog：Spinner(模式) + TextInputLayout(文本) + "add" 按钮
 *     **注意**：上游先 `setPositiveButton(add, null)` 再把该按钮的 listener 覆盖成自己的 →
 *     即"校验失败时不关闭对话框"。本实现用 `addResult` 返回值表达同一语义。
 *   · AddFilterDialogHelper.onClick：
 *       任一依赖为 null → return（不崩）
 *       `text = editText.trim()`；**空 → setError(text_is_empty) 且不关闭**；否则清 error
 *       `mode = spinner.getSelectedItemPosition()`；add({mode,text})；notify；updateView(true)；dismiss
 *   · showDeleteFilterDialog(filter)：message = `delete_filter % filter.text`；
 *     **`which != BUTTON_POSITIVE` 直接 return**（取消不删）；否则 delete + notify + updateView(true)
 *   · FilterHolder：icon 点击 → 删除对话框；**text 点击 → trigger(filter)（启用/禁用）+ notifyItemChanged**
 *     （后者是为了更新文字上的删除线）
 *   · `FilterList.MODE_HEADER` 的项**不可删、不可 trigger**
 *
 * 依赖缺口（规则 ③）：`FilterList` / `Filter` 属 storage-db，`AlertDialog` → ArkUI `AlertDialog`；
 *   本文件只保留**状态机 + 校验语义**，持久化与列表数据由调用方注入。
 *
 * 差异（已登记 MR）：
 *   1) `EasyRecyclerView` → `List`（D-022）；`ViewTransition.showView(0/1)` → 已交付的 `ViewTransition`
 *   2) `Spinner` → `Select`；`TextInputLayout.setError` → `TextInput` 的 `showError`
 *   3) 上游对话框按钮 listener 覆盖技巧 → 显式返回值（可测，不依赖框架顺序）
 */
import { hilog } from '@kit.PerformanceAnalysisKit';

const LOG_DOMAIN: number = 0x0000;
const LOG_TAG: string = 'HippoWidget.FilterActivity';

/** 对位 storage-db 的 Filter */
export class FilterItem {
  mode: number = 0;
  text: string = '';
  /** 启用态（上游 `FilterList.trigger()` 翻转；禁用时文字加删除线） */
  enabled: boolean = true;
}

/** 对位 FilterList 的常量 */
export class FilterListConst {
  /** 上游 `FilterList.MODE_HEADER`：表头项不可删、不可 trigger */
  static readonly MODE_HEADER: number = -1;
}

/** add 对话框的提交结果（对位上游"校验失败不关闭"） */
export class AddFilterResult {
  /** 是否成功加入（false 时**对话框保持打开**） */
  ok: boolean = false;
  /** 失败原因（空文本） */
  error: string = '';
}

export class FilterActivityState {
  filters: FilterItem[] = [];

  /** 上游 updateView 的判定：空 → 空态(1)，非空 → 列表(0) */
  isEmpty(): boolean {
    return this.filters.length === 0;
  }

  /** 对位 updateView 的 showView 下标 */
  visibleView(): number {
    return this.isEmpty() ? 1 : 0;
  }

  /**
   * 上游 AddFilterDialogHelper.onClick 的净效果：
   * trim → 空则报错且**不加入**（对话框不关闭）；否则加入并返回 ok。
   */
  addFilter(mode: number, rawText: string): AddFilterResult {
    const r: AddFilterResult = new AddFilterResult();
    const text: string = rawText.trim();
    if (text.length === 0) {
      r.ok = false;
      r.error = 'text_is_empty';
      return r;
    }
    const f: FilterItem = new FilterItem();
    f.mode = mode;
    f.text = text;
    f.enabled = true;
    this.filters.push(f);
    r.ok = true;
    return r;
  }

  /** 上游 showDeleteFilterDialog 的 positive 分支：**只有确认才删** */
  deleteFilter(filter: FilterItem): boolean {
    const i: number = this.filters.indexOf(filter);
    if (i < 0) {
      return false;
    }
    this.filters.splice(i, 1);
    return true;
  }

  /**
   * 上游 FilterHolder.onClick 的 text 分支：`trigger(filter)` 翻转启用态。
   * **MODE_HEADER 不可 trigger**（上游 `if (FilterList.MODE_HEADER != filter.mode)`）。
   */
  trigger(filter: FilterItem): boolean {
    if (filter.mode === FilterListConst.MODE_HEADER) {
      return false;
    }
    filter.enabled = !filter.enabled;
    return true;
  }

  /** 上游 icon 分支：表头项不可删（同一守卫） */
  canDelete(filter: FilterItem): boolean {
    return filter.mode !== FilterListConst.MODE_HEADER;
  }
}

@Component
export struct FilterActivity {
  state: FilterActivityState = new FilterActivityState();
  @Prop title: string = '';
  @Prop tipTitle: string = '';
  @Prop tipMessage: string = '';
  @Prop addTitle: string = '';
  @Prop deleteMessageFormat: string = '';
  /** 模式名（对位 Spinner 的 entries） */
  @Prop modeLabels: string[] = [];
  /** 持久化（storage-db）：由调用方注入 */
  onPersist: (filters: FilterItem[]) => void = (filters: FilterItem[]) => {
  };
  @State rev: number = 0;
  @State addDialogOpen: boolean = false;
  @State tipDialogOpen: boolean = false;
  @State pendingDelete: FilterItem | null = null;
  @State inputText: string = '';
  @State inputError: string = '';
  @State modeIndex: number = 0;

  aboutToAppear(): void {
    if (this.onPersist === null) {
      hilog.error(LOG_DOMAIN, LOG_TAG, '%{public}s', 'onPersist not injected — filter edits will be lost');
    }
  }

  private confirmAdd(): void {
    const r: AddFilterResult = this.state.addFilter(this.modeIndex, this.inputText);
    if (!r.ok) {
      // 上游：setError 且**不关闭对话框**
      this.inputError = r.error;
      this.rev = this.rev + 1;
      return;
    }
    this.inputError = '';
    this.inputText = '';
    this.addDialogOpen = false;
    this.onPersist(this.state.filters);
    this.rev = this.rev + 1;
  }

  private confirmDelete(): void {
    const f: FilterItem | null = this.pendingDelete;
    if (f !== null && this.state.deleteFilter(f)) {
      this.onPersist(this.state.filters);
    }
    this.pendingDelete = null;
    this.rev = this.rev + 1;
  }

  build() {
    Column() {
      Row({ space: 12 }) {
        Text(this.title).fontSize(18).layoutWeight(1)
        Text('?').fontSize(16)
          .onClick(() => {
            this.tipDialogOpen = true;
          })
        Text('+').fontSize(20)
          .onClick(() => {
            this.inputText = '';
            this.inputError = '';
            this.addDialogOpen = true;
          })
      }
      .width('100%')
      .padding(12)

      // 上游 ViewTransition：空态(1) / 列表(0)
      if (this.state.visibleView() === 1) {
        // 上游 activity_filter.xml：android:text=@string/no_filter
        Text($r('app.string.no_filter'))
          .fontSize(14)
          .width('100%')
          .padding(24)
      } else {
        List() {
          ForEach(this.state.filters, (f: FilterItem, index: number) => {
            ListItem() {
              Row({ space: 8 }) {
                Text(f.text)
                  .fontSize(14)
                  .layoutWeight(1)
                  .decoration({
                    type: f.enabled ? TextDecorationType.None : TextDecorationType.LineThrough
                  })
                  .onClick(() => {
                    // 上游 text 点击 → trigger（启用/禁用）
                    if (this.state.trigger(f)) {
                      this.onPersist(this.state.filters);
                      this.rev = this.rev + 1;
                    }
                  })
                if (this.state.canDelete(f)) {
                  Text('🗑').fontSize(14)
                    .onClick(() => {
                      this.pendingDelete = f;
                    })
                }
              }
              .width('100%')
              .padding(12)
            }
          }, (f: FilterItem, index: number) => `${index}:${f.text}`)
        }
        .width('100%')
        .layoutWeight(1)
      }
    }
    .width('100%')
    .height('100%')
  }
}