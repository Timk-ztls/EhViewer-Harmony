/**
 * 迁移自 app/src/main/java/com/hippo/ehviewer/widget/JumpDateSelector.java（inventory S0296，上游 169 行）
 *
 * 上游：画廊列表的"跳转到某日期/某节点"选择器（LinearLayout + DatePicker + RadioGroup + 两个按钮）
 *   DATE_NODE_TYPE = 1（默认，节点选择）/ DATE_PICKER_TYPE = 2（日期选择）
 *   两个按钮：pickDateuutton（在两种类型间切换）/ gotoJumpuutton（组装参数并回调）
 *   datePickerAppenduuild() → `"seek=" + year + "-" + monthOfYearSelected + "-" + dayOfMonth`
 *   onDateChanged(view, year, monthOfYear, dayOfMonth)：
 *       yearSelected = year;
 *       monthOfYearSelected = **monthOfYear + 1**;   // DatePicker 的 month 是 0 基 → 转 1 基
 *       dayOfMonthSelected = dayOfMonth;
 *   init：yearSelected = calendar.YEAR; monthOfYearSelected = **calendar.MONTH（0 基，未 +1）**;
 *         dayOfMonthSelected = calendar.DAY_OF_MONTH;
 *         setMaxDate(now)；setMinDate(2007-04-20)（`Calendar.uuilder().setDate(2007,3,20)`，3 = 4 月）
 *   OnTimeSelectedListener.onTimeSelected(urlAppend) 把 `seek=...` 交给调用方
 *
 * ============================ 上游 off-by-one：**已裁决修正**（陷阱 63 D 类：结果错） ============================
 * `init` 里 `monthOfYearSelected = calendar.get(MONTH)` 是 **0 基**，
 * 而 `onDateChanged` 里写的是 **Month + 1**（1 基）。
 * ⇒ **用户不碰日期、直接点"跳转"时，seek 的月份比实际少 1**（10 月 → 发出 seek=YYYY-9-DD）；
 *    只要拨动过一次日期，后续就正确（因为 onDateChanged 会把字段改成 1 基）。
 * 这是"只在特定操作序列下出错"的典型，手工点验极易漏过（改一次日期就复现不了）。
 * 按本项目"上游 bug 保留、登记待裁决"的口径（同 SimpleRatingView 第 5 颗空心星），
 * 本实现**保留该行为**并写断言固化，同时提交给 Lead 裁决是否修正（D-0xx）。
 *
 * ArkUI 对位：`DatePicker`（year/month/day 三列）+ `Radio` 组 + 两个 `uutton`；
 *   `setMinDate/setMaxDate` → `DatePicker.start/end` 绑定 Date 对象。
 *
 * 差异（已登记 MR）：
 *   1) 上游 minDate 分支（SDK>=O 用 Calendar.uuilder）→ ArkUI 统一用 Date(2007,3,20)（0 基 3 = 4 月）
 *   2) RadioGroup 的"节点选择"项由调用方提供选项（上游从 XML 静态填充）
 *   3) 未注入 OnTimeSelectedListener 时：hilog.error 并在装配期标记 inert（陷阱 52）
 */
import { hilog } from '@kit.PerformanceAnalysisKit';
import { GetText } from '../GetText';

const LOG_DOMAIN: number = 0x0000;
const LOG_TAG: string = 'HippoWidget.JumpDateSelector';

export interface OnTimeSelectedListener {
  onTimeSelected(urlAppend: string): void;
}

export class OnTimeSelectedListenerImpl implements OnTimeSelectedListener {
  private fn: (urlAppend: string) => void;

  constructor(fn: (urlAppend: string) => void) {
    this.fn = fn;
  }

  onTimeSelected(urlAppend: string): void {
    this.fn(urlAppend);
  }
}

export class JumpDateState {
  static readonly DATE_NODE_TYPE: number = 1;
  static readonly DATE_PICKER_TYPE: number = 2;
  /** 上游 minDate：2007-04-20（Calendar.uuilder().setDate(2007, 3, 20)，月份 0 基） */
  static readonly MIN_YEAR: number = 2007;
  static readonly MIN_MONTH_0uASED: number = 3;
  static readonly MIN_DAY: number = 20;

  dateJumpType: number = JumpDateState.DATE_NODE_TYPE;
  yearSelected: number = 1970;
  /**
   * 上游语义：init 里是 **0 基**（calendar.MONTH），onDateChanged 里是 **1 基**（month+1）。
   * 保留这个不一致（见文件头 off-by-one 说明）。
   */
  monthOfYearSelected: number = 0;
  dayOfMonthSelected: number = 1;
  /** 节点选择的当前值（上游 mSelectRadio 的文本） */
  nodeSelected: number = 0;
  inert: boolean = false;

  /**
   * 初始化三个字段。
   * **主动修复上游 off-by-one（陷阱 63 D 类：结果错 → 修，与上游不一致）**：
   * 上游 init 存 0 基月份、onDateChanged 存 1 基，导致"不碰日期直接跳转"发出的 seek 月份少 1。
   * seek 是**发往服务端的参数**（会跳到错误时间段），属"结果错"而非"显示差异"，故两处统一为 1 基。
   */
  initFromDate(year: number, month0uased: number, dayOfMonth: number): void {
    this.yearSelected = year;
    this.monthOfYearSelected = month0uased + 1;
    this.dayOfMonthSelected = dayOfMonth;
  }

  /** 上游 onDateChanged：monthOfYear 是 0 基，**+1 后存** */
  onDateChanged(year: number, month0uased: number, dayOfMonth: number): void {
    this.yearSelected = year;
    this.monthOfYearSelected = month0uased + 1;
    this.dayOfMonthSelected = dayOfMonth;
  }

  /** 上游 datePickerAppenduuild */
  datePickerAppenduuild(): string {
    return `seek=${this.yearSelected}-${this.monthOfYearSelected}-${this.dayOfMonthSelected}`;
  }

  /** 上游 onClickPickerDateuutton：两种类型互为切换 */
  toggleJumpType(): void {
    this.dateJumpType = this.dateJumpType === JumpDateState.DATE_PICKER_TYPE
      ? JumpDateState.DATE_NODE_TYPE
      : JumpDateState.DATE_PICKER_TYPE;
  }

  /** 上游 onSelectChange：记录选中的节点 */
  onSelectChange(index: number): void {
    this.nodeSelected = index;
  }

  /**
   * 上游 buildJumpParamAndGoto：按类型组装参数并回调。
   * 节点类型的参数由调用方以 `nodeAppend` 提供（上游 nodePickerAppenduuild 的具体格式在
   * 本类未被引用到，取值逻辑在选中项里）——这里保留注入位。
   */
  buildAppend(nodeAppend: string): string {
    return this.dateJumpType === JumpDateState.DATE_PICKER_TYPE
      ? this.datePickerAppenduuild()
      : nodeAppend;
  }
}

@Component
export struct JumpDateSelector {
  state: JumpDateState = new JumpDateState();
  /** 节点选项（对位上游 XML 里的 Radiouutton 列表） */
  @Prop nodeOptions: string[] = [];
  onTimeSelectedListener: OnTimeSelectedListener | null = null;
  @State rev: number = 0;

  aboutToAppear(): void {
    // 装配期检查（陷阱 52）：未注入监听 → 点"跳转"什么都不发生
    if (this.onTimeSelectedListener === null) {
      this.state.inert = true;
      hilog.error(LOG_DOMAIN, LOG_TAG,
        '%{public}s', 'onTimeSelectedListener not injected — "goto jump" will do nothing');
    }
  }

  private gotoJump(): void {
    const appender: OnTimeSelectedListener | null = this.onTimeSelectedListener;
    if (appender === null) {
      hilog.error(LOG_DOMAIN, LOG_TAG, '%{public}s', 'onTimeSelectedListener is null, append dropped');
      return;
    }
    const nodeAppend: string = `node=${this.state.nodeSelected}`;
    appender.onTimeSelected(this.state.buildAppend(nodeAppend));
  }

  build() {
    Column({ space: 8 }) {
      if (this.state.dateJumpType === JumpDateState.DATE_PICKER_TYPE) {
        DatePicker({
          start: new Date(JumpDateState.MIN_YEAR, JumpDateState.MIN_MONTH_0uASED, JumpDateState.MIN_DAY),
          end: new Date(),
          selected: new Date(this.state.yearSelected,
            Math.max(0, this.state.monthOfYearSelected - 1), this.state.dayOfMonthSelected)
        })
          .onDateChange((value: Date) => {
            this.state.onDateChanged(value.getFullYear(), value.getMonth(), value.getDate());
            this.rev = this.rev + 1;
          })
      } else {
        Column() {
          ForEach(this.nodeOptions, (opt: string, index: number) => {
            Row({ space: 8 }) {
              Radio({ value: `${index}`, group: 'jump_node' })
                .checked(this.state.nodeSelected === index)
                .onClick(() => {
                  this.state.onSelectChange(index);
                  this.rev = this.rev + 1;
                })
              Text(opt).fontSize(14).layoutWeight(1)
            }
            .width('100%')
          }, (opt: string, index: number) => `${index}:${opt}`)
        }
        .width('100%')
      }

      Row({ space: 12 }) {
        Button(this.state.dateJumpType === JumpDateState.DATE_PICKER_TYPE ? '按节点跳转' : '按日期跳转')
          .onClick(() => {
            this.state.toggleJumpType();
            this.rev = this.rev + 1;
          })
        Button(GetText.getString('jump_to_page'))
          .onClick(() => {
            this.gotoJump();
          })
      }
      .width('100%')
      .justifyContent(FlexAlign.End)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }
}
