/**
 * 迁移自 app/src/main/java/com/hippo/ehviewer/ui/BlackListActivity.java（S0188，上游 315 行）
 *
 * 判据：**页面内容**（`ToolbarActivity` 壳属 ui-scene 基类）
 *
 * 一手语义（逐条来自源码）
 *   · updateView：`mblackListList` 为空 → `showView(1)`；否则 `showView(0)`
 *   · 菜单：home → finish；action_add → showAddBlackListDialog；action_tip → showTipDialog
 *   · showAddBlackListDialog：Spinner + TextInputLayout + "add"（**同样覆盖按钮 listener**：校验失败不关闭）
 *   · AddBlackListDialogHelper.onClick：
 *       `text = editText.trim()`；**空 → setError(text_is_empty) 且不关闭**；否则清 error
 *       **新建的 BlackList 字段是硬编码的**：
 *         `badgayname = text`
 *         `add_time = TimeUtils.getTimeNow()`
 *         `angrywith = "/手动添加/"`
 *         `mode = 1`
 *       add → notify → updateView(true) → dismiss
 *       （`mode = 1` 与 `angrywith` 的固定文案是上游写死的，**照搬**；`mode` 的语义属 storage-db）
 *   · showDeleteBlackListDialog(blackList)：message = `delete_blacklist % blackList.badgayname`；
 *       **`which != BUTTON_POSITIVE` 直接 return**；否则 delete + notify + updateView(true)
 *   · BlackListHolder：icon → 删除对话框；text → （与 FilterActivity 不同，这里**没有 trigger**）
 *
 * 依赖缺口（规则 ③）：`BlackListList` / `BlackList` 属 storage-db；`TimeUtils.getTimeNow()` 属 yorozuya（已交付 DateUtils）。
 *
 * 差异（已登记 MR）：
 *   1) `EasyRecyclerView` → `List`（D-022）；`ViewTransition` 复用已交付实现
 *   2) Spinner → `Select`；`setError` → `TextInput` 的 `showError`
 *   3) 上游"覆盖 positive 按钮 listener"技巧 → 显式返回值（可测）
 */
import { hilog } from '@kit.PerformanceAnalysisKit';

const LOG_DOMAIN: number = 0x0000;
const LOG_TAG: string = 'HippoWidget.BlackListActivity';

/** 对位 storage-db 的 BlackList */
export class BlackListItem {
  /** 上游字段名照搬（badgayname） */
  badgayname: string = '';
  addTime: number = 0;
  /** 上游硬编码 `"/手动添加/"` */
  angrywith: string = '/手动添加/';
  /** 上游硬编码 `mode = 1` */
  mode: number = 1;
}

export class AddBlackListResult {
  ok: boolean = false;
  error: string = '';
}

export class BlackListActivityState {
  /** 上游硬编码的两个常量（照搬，勿"优化"） */
  static readonly MANUAL_ANGRYWITH: string = '/手动添加/';
  static readonly MANUAL_MODE: number = 1;

  items: BlackListItem[] = [];

  isEmpty(): boolean {
    return this.items.length === 0;
  }

  /** 对位 updateView 的 showView 下标 */
  visibleView(): number {
    return this.isEmpty() ? 1 : 0;
  }

  /**
   * 上游 AddBlackListDialogHelper.onClick 的净效果：
   * trim → 空则报错且**不加入**；否则按上游四个字段加入。
   */
  addItem(rawText: string, now: number): AddBlackListResult {
    const r: AddBlackListResult = new AddBlackListResult();
    const text: string = rawText.trim();
    if (text.length === 0) {
      r.ok = false;
      r.error = 'text_is_empty';
      return r;
    }
    const item: BlackListItem = new BlackListItem();
    item.badgayname = text;
    item.addTime = now;
    item.angrywith = BlackListActivityState.MANUAL_ANGRYWITH;
    item.mode = BlackListActivityState.MANUAL_MODE;
    this.items.push(item);
    r.ok = true;
    return r;
  }

  /** 上游 showDeleteBlackListDialog 的 positive 分支：**只有确认才删** */
  deleteItem(item: BlackListItem): boolean {
    const i: number = this.items.indexOf(item);
    if (i < 0) {
      return false;
    }
    this.items.splice(i, 1);
    return true;
  }
}

@Component
export struct BlackListActivity {
  state: BlackListActivityState = new BlackListActivityState();
  @Prop title: string = '';
  @Prop tipTitle: string = '';
  @Prop tipMessage: string = '';
  @Prop addTitle: string = '';
  @Prop deleteMessageFormat: string = '';
  onPersist: (items: BlackListItem[]) => void = (items: BlackListItem[]) => {
  };
  @State rev: number = 0;
  @State inputText: string = '';
  @State inputError: string = '';
  @State pendingDelete: BlackListItem | null = null;

  aboutToAppear(): void {
    if (this.onPersist === null) {
      hilog.error(LOG_DOMAIN, LOG_TAG, '%{public}s', 'onPersist not injected — edits will be lost');
    }
  }

  private confirmAdd(): void {
    const r: AddBlackListResult = this.state.addItem(this.inputText, Date.now());
    if (!r.ok) {
      this.inputError = r.error; // 上游：setError 且不关闭
      this.rev = this.rev + 1;
      return;
    }
    this.inputError = '';
    this.inputText = '';
    this.onPersist(this.state.items);
    this.rev = this.rev + 1;
  }

  private confirmDelete(): void {
    const item: BlackListItem | null = this.pendingDelete;
    if (item !== null && this.state.deleteItem(item)) {
      this.onPersist(this.state.items);
    }
    this.pendingDelete = null;
    this.rev = this.rev + 1;
  }

  build() {
    Column() {
      Row({ space: 12 }) {
        Text(this.title).fontSize(18).layoutWeight(1)
        Text('?').fontSize(16).onClick(() => { /* tip dialog */ })
        Text('+').fontSize(20).onClick(() => {
          this.inputText = '';
          this.inputError = '';
        })
      }
      .width('100%')
      .padding(12)

      if (this.state.visibleView() === 1) {
        // 上游 activity_blacklist.xml：android:text=@string/no_blicklist（上游键名本身拼错，照搬）
        Text($r('app.string.no_blicklist')).fontSize(14).width('100%').padding(24)
      } else {
        List() {
          ForEach(this.state.items, (item: BlackListItem, index: number) => {
            ListItem() {
              Row({ space: 8 }) {
                Text(item.badgayname).fontSize(14).layoutWeight(1)
                Text('🗑').fontSize(14).onClick(() => {
                  this.pendingDelete = item;
                })
              }
              .width('100%')
              .padding(12)
            }
          }, (item: BlackListItem, index: number) => `${index}:${item.badgayname}`)
        }
        .width('100%')
        .layoutWeight(1)
      }
    }
    .width('100%')
    .height('100%')
  }
}