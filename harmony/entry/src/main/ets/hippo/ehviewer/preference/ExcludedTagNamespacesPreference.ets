/**
 * 迁移自 app/src/main/java/com/hippo/ehviewer/preference/ExcludedTagNamespacesPreference.java（S0167，上游 99 行）
 *
 * 判据：**UI 组件行**（`extends DialogPreference`），自有逻辑：
 *   onPrepareDialogBuilder / onDialogCreated：对话框内 8 个 namespace 复选框
 *   onDialogClosed(positiveResult)：**true 时**写回整型位掩码
 *   setExcludedTagNamespaces(view, value)：按位回填勾选
 * ⇒ 组合 `DialogPreference` + 位掩码状态（复用 `NamespaceFlags`，一手核对 0x1..0x80）。
 *
 * ⚠ 与 `CategoryTable` 的关键差别：这里的勾选语义是**"排除"**（用户勾上的 namespace 被排除），
 *   所以写回的掩码就是勾选位的 OR（**不取反**）；取反若发生，也在消费端（`ListUrlBuilder` 风格）。
 */
import { ThemePalette, ThemeTokens } from '../../../common/theme/ThemeTokens';
import { DialogPreference, DialogPreferenceState } from '../../preference/DialogPreference';
import { Settings } from '../Settings';

/** 上游 EhConfig 的 namespace 位（一手核对：升级版 EhConfig.ets 逐项一致 0x1..0x80） */
export class NamespaceFlags {
  static readonly RECLASS: number = 0x1;
  static readonly LANGUAGE: number = 0x2;
  static readonly PARODY: number = 0x4;
  static readonly CHARACTER: number = 0x8;
  static readonly GROUP: number = 0x10;
  static readonly ARTIST: number = 0x20;
  static readonly MALE: number = 0x40;
  static readonly FEMALE: number = 0x80;

  /** 界面顺序（与位值顺序一致，便于对照；断言会锁这一点） */
  static readonly ORDER: number[] = [0x1, 0x2, 0x4, 0x8, 0x10, 0x20, 0x40, 0x80];
  static readonly LABELS: string[] = ['Reclass', 'Language', 'Parody', 'Character', 'Group', 'Artist', 'Male', 'Female'];

  static toMask(values: boolean[]): number {
    let v: number = 0;
    for (let i = 0; i < NamespaceFlags.ORDER.length; i++) {
      if (values[i]) {
        v |= NamespaceFlags.ORDER[i];
      }
    }
    return v;
  }

  static fromMask(mask: number): boolean[] {
    const out: boolean[] = [];
    for (let i = 0; i < NamespaceFlags.ORDER.length; i++) {
      out.push((mask & NamespaceFlags.ORDER[i]) !== 0);
    }
    return out;
  }

  static formatSummary(mask: number, fallbackSummary: string): string {
    const excluded: string[] = [];
    for (let i = 0; i < NamespaceFlags.ORDER.length; i++) {
      if ((mask & NamespaceFlags.ORDER[i]) !== 0) {
        excluded.push(NamespaceFlags.LABELS[i]);
      }
    }
    if (excluded.length === 0) {
      return fallbackSummary;
    }
    return excluded.join(', ');
  }
}

@Component
export struct ExcludedTagNamespacesPreference {
  state: DialogPreferenceState = new DialogPreferenceState();
  @Prop title: string = '';
  @Prop summary: string = '';
  @Prop dialogTitle: string = '';
  /** 当前排除掩码（-1 表示直接读取 Settings.getExcludedTagNamespaces()） */
  @Prop current: number = -1;
  @Prop themeId: number = -1;
  @Prop showDivider: boolean = false;
  onChanged: (mask: number) => void = (mask: number) => {
  };
  @State values: boolean[] = [false, false, false, false, false, false, false, false];
  @State rev: number = 0;

  private palette(): ThemePalette {
    return this.themeId >= 0 ? ThemeTokens.of(this.themeId) : ThemeTokens.current();
  }

  private loadMask(): number {
    return this.current >= 0 ? this.current : Settings.getExcludedTagNamespaces();
  }

  private syncValues(): void {
    const mask: number = this.loadMask();
    // 上游 setExcludedTagNamespaces(view, value)：按位回填
    this.values = NamespaceFlags.fromMask(mask);
    this.state.summary = NamespaceFlags.formatSummary(mask, this.summary);
  }

  aboutToAppear(): void {
    this.state.title = this.title;
    this.state.dialogTitle = this.dialogTitle;
    this.syncValues();
  }

  private toggleIndex(index: number, checked: boolean): void {
    if (index < 0 || index >= this.values.length || this.values[index] === checked) {
      return;
    }
    const next: boolean[] = this.values.slice();
    next[index] = checked;
    this.values = next;
    this.rev = this.rev + 1;
  }

  build() {
    DialogPreference({
      state: this.state,
      themeId: this.themeId,
      showDivider: this.showDivider,
      onPrepareDialog: () => {
        this.syncValues();
      },
      onDialogClosed: (positiveResult: boolean) => {
        if (positiveResult) {
          const mask: number = NamespaceFlags.toMask(this.values);
          Settings.putExcludedTagNamespaces(mask);
          this.state.summary = NamespaceFlags.formatSummary(mask, this.summary);
          this.onChanged(mask);
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
    Column() {
      ForEach(NamespaceFlags.LABELS, (label: string, index: number) => {
        Row({ space: 8 }) {
          Checkbox()
            .select(this.values[index])
            .selectedColor(this.palette().controlActivated)
            .unselectedColor(this.palette().drawablePrimary)
            .shape(CheckBoxShape.ROUNDED_SQUARE)
            .onChange((isChecked: boolean) => {
              this.toggleIndex(index, isChecked);
            })
          Text(label)
            .fontSize(14)
            .fontColor(this.palette().textPrimary)
            .layoutWeight(1)
        }
        .width('100%')
        .constraintSize({ minHeight: 44 })
        .onClick(() => {
          this.toggleIndex(index, !this.values[index]);
        })
      }, (label: string, index: number) => `${index}:${label}`)
    }
    .width('100%')
  }
}
