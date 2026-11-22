/**
 * 迁移自 app/src/main/java/com/hippo/ehviewer/ui/ExcludedLanguagesActivity.java（S0197，上游 355 行）
 *
 * 判据：**页面内容**（`ToolbarActivity` 壳属 ui-scene 基类）
 *
 * 一手语义（逐条来自源码）
 *   · 布局：`ROW_COUNT = 17` 行 × **3 列**（原始 / 翻译 / 重写）⇒ `mSelections[17][3]`
 *   · `isDecimal(str)`：**非空且全为 '0'..'9'**（空串不算数字）
 *   · onInit：`Settings.getExcludedLanguages()` → `split("x")` → 每个 token 若是十进制，
 *     则在 `LANGUAGES[]` 里**继续向后扫描**（`for (; j < jLength; j++)`，**j 不重置**）找第一个相等项 →
 *     `mSelections[j / 3][j % 3] = true`，找到即 break
 *     ⇒ **隐含要求：存进去的 token 顺序必须与 LANGUAGES 顺序一致**，乱序会漏匹配（上游行为，照搬）
 *   · onSaveInstanceState：`saveSelectionsToLong()` → **位打包** `value |= 1 << (i*3 + j)`
 *   · onRestore：`restoreSelectionsFromLong()` → `(value >>> (i*3+j)) & 1`
 *   · onClick：cancel → finish；**ok → 遍历 17×3，按 `i*3+j` 升序把选中的 pattern 用 `"x"` 连接**，
 *     然后写回 Settings 并 finish
 *   · 三个批量按钮：select_all / deselect_all / invert_selection
 *   · 单元格变更只处理 **fromUser**（程序化回填不写回）—— 依赖 `SensitiveCheckBox` 的 fromUser 语义
 *
 * 依赖缺口（规则 ③）：`Settings.getExcludedLanguages/setExcludedLanguages` 属 core-runtime；
 *   `LANGUAGES[]` 的 pattern 字符串属资源；`SensitiveCheckBox` **已交付**（含 programmaticPending 顺序无关修复）。
 *
 * 差异（已登记 MR）：`EasyRecyclerView` → `List`（D-022）；`AlertDialog`/Ripple 不涉及。
 */
import { hilog } from '@kit.PerformanceAnalysisKit';
import {
  ThemeDimens,
  ThemePalette,
  ThemeRadius,
  ThemeTokens,
  ThemeTypography
} from '../../../common/theme/ThemeTokens';

const LOG_DOMAIN: number = 0x0000;
const LOG_TAG: string = 'HippoWidget.ExcludedLanguagesActivity';

export class ExcludedLanguagesConst {
  static readonly ROW_COUNT: number = 17;
  static readonly COLUMN_COUNT: number = 3;
  /** 上游 KEY_SELECTIONS（Bundle 键） */
  static readonly KEY_SELECTIONS: string = 'selections';
  /** 上游用 "x" 作为 pattern 分隔符 */
  static readonly SEPARATOR: string = 'x';
}

export class ExcludedLanguagesState {
  /** 对位 mSelections[17][3] */
  selections: boolean[][] = [];

  constructor() {
    this.reset();
  }

  reset(): void {
    this.selections = [];
    for (let i = 0; i < ExcludedLanguagesConst.ROW_COUNT; i++) {
      const row: boolean[] = [];
      for (let j = 0; j < ExcludedLanguagesConst.COLUMN_COUNT; j++) {
        row.push(false);
      }
      this.selections.push(row);
    }
  }

  /** 上游 isDecimal：非空且全为数字 */
  static isDecimal(str: string): boolean {
    if (str.length <= 0) {
      return false;
    }
    for (let i = 0; i < str.length; i++) {
      const ch: string = str.charAt(i);
      if (ch < '0' || ch > '9') {
        return false;
      }
    }
    return true;
  }

  /**
   * 上游 onInit：把 `getExcludedLanguages()` 的字符串解析进 selections。
   * **j 指针跨 token 单调前进**（上游 `for (; j < jLength; j++)`）—— 照搬，并断言乱序会漏匹配。
   */
  initFromSettings(excluded: string, patterns: string[]): void {
    this.reset();
    if (excluded.length === 0) {
      return;
    }
    const tokens: string[] = excluded.split(ExcludedLanguagesConst.SEPARATOR);
    let j: number = 0;
    for (let i = 0; i < tokens.length; i++) {
      const token: string = tokens[i];
      if (!ExcludedLanguagesState.isDecimal(token)) {
        continue;
      }
      for (; j < patterns.length; j++) {
        if (patterns[j] === token) {
          this.selections[Math.trunc(j / 3)][j % 3] = true;
          break;
        }
      }
    }
  }

  /**
   * 上游 saveSelectionsToLong：`value |= 1 << (i*3 + j)`（Java **long 64 位**）。
   * ⚠ ArkTS/JS 的 `<<` 是 **32 位**整数操作：51 位打包时 `1 << 50` 会静默回绕成 `1 << 18`。
   * 故改用 `2 ** bit` 的**数值加法**（每个 bit 只会置一次，加法与按位或等价）。
   * 这条是断言抓出来的真 bug（`PASS` 前是 `FAIL ... actual=262144 expected=1125899906842624`）。
   */
  saveSelectionsToLong(): number {
    let value: number = 0;
    for (let i = 0; i < ExcludedLanguagesConst.ROW_COUNT; i++) {
      for (let j = 0; j < ExcludedLanguagesConst.COLUMN_COUNT; j++) {
        if (this.selections[i][j]) {
          value += Math.pow(2, i * 3 + j);
        }
      }
    }
    return value;
  }

  /** 上游 restoreSelectionsFromLong：`(value >>> (i*3+j)) & 1`；同上，**不能用 32 位移位** */
  restoreSelectionsFromLong(value: number): void {
    this.reset();
    for (let i = 0; i < ExcludedLanguagesConst.ROW_COUNT; i++) {
      for (let j = 0; j < ExcludedLanguagesConst.COLUMN_COUNT; j++) {
        const bit: number = i * 3 + j;
        this.selections[i][j] = Math.floor(value / Math.pow(2, bit)) % 2 === 1;
      }
    }
  }

  /** 上游 select_all / deselect_all / invert_selection */
  selectAll(): void {
    this.fillAll(true);
  }

  deselectAll(): void {
    this.fillAll(false);
  }

  invertSelection(): void {
    for (let i = 0; i < ExcludedLanguagesConst.ROW_COUNT; i++) {
      for (let j = 0; j < ExcludedLanguagesConst.COLUMN_COUNT; j++) {
        this.selections[i][j] = !this.selections[i][j];
      }
    }
  }

  private fillAll(v: boolean): void {
    for (let i = 0; i < ExcludedLanguagesConst.ROW_COUNT; i++) {
      for (let j = 0; j < ExcludedLanguagesConst.COLUMN_COUNT; j++) {
        this.selections[i][j] = v;
      }
    }
  }

  /** 上游单元格变更（仅 fromUser 时写回） */
  setCell(row: number, column: number, checked: boolean, fromUser: boolean): boolean {
    if (!fromUser) {
      return false;
    }
    if (row < 0 || row >= ExcludedLanguagesConst.ROW_COUNT) {
      return false;
    }
    if (column < 0 || column >= ExcludedLanguagesConst.COLUMN_COUNT) {
      return false;
    }
    this.selections[row][column] = checked;
    return true;
  }

  /** 上游 onOk 分支：按 `i*3+j` 升序把选中 pattern 用 "x" 连接 */
  buildExcludedString(patterns: string[]): string {
    let out: string = '';
    let first: boolean = true;
    for (let i = 0; i < ExcludedLanguagesConst.ROW_COUNT; i++) {
      for (let j = 0; j < ExcludedLanguagesConst.COLUMN_COUNT; j++) {
        if (!this.selections[i][j]) {
          continue;
        }
        const idx: number = i * 3 + j;
        if (idx >= patterns.length) {
          continue;
        }
        if (!first) {
          out += ExcludedLanguagesConst.SEPARATOR;
        } else {
          first = false;
        }
        out += patterns[idx];
      }
    }
    return out;
  }
}

@Component
export struct ExcludedLanguagesActivity {
  state: ExcludedLanguagesState = new ExcludedLanguagesState();
  @Prop title: string = '';
  /** 17 行的语言名（对位 language_* 资源） */
  @Prop languageLabels: string[] = [];
  /** 51 个 pattern（17×3，顺序即 LANGUAGES 顺序） */
  @Prop patterns: string[] = [];
  /** 初始值（对位 Settings.getExcludedLanguages()） */
  @Prop excludedFromSettings: string = '';
  @Prop themeId: number = -1;
  onSave: (excluded: string) => void = (excluded: string) => {
  };
  onCancel: () => void = () => {
  };
  @State rev: number = 0;

  private palette(): ThemePalette {
    return this.themeId >= 0 ? ThemeTokens.of(this.themeId) : ThemeTokens.current();
  }

  aboutToAppear(): void {
    this.state.initFromSettings(this.excludedFromSettings, this.patterns);
    if (this.onSave === null) {
      hilog.error(LOG_DOMAIN, LOG_TAG, '%{public}s', 'onSave not injected — edits will be discarded');
    }
  }

  build() {
    Column() {
      Row({ space: 8 }) {
        // 上游 scene_excluded_languages.xml：android:text=@android:string/cancel → 本仓库对应 cancel 键
        Button({ type: ButtonType.Normal }) {
          Text($r('app.string.cancel'))
            .fontSize(ThemeTypography.BUTTON)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.palette().textSecondary)
            .textCase(TextCase.UpperCase)
        }
        .backgroundColor(Color.Transparent)
        .borderRadius(ThemeRadius.BUTTON)
        .constraintSize({ minHeight: ThemeDimens.DIALOG_ACTION_MIN_HEIGHT })
        .padding({ left: 8, right: 8 })
        .onClick(() => {
          this.onCancel();
        })

        Text(this.title)
          .fontSize(18)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.palette().textPrimary)
          .layoutWeight(1)
          .textAlign(TextAlign.Center)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })

        // 上游 @android:string/ok（框架串）→ 本仓库无 ok 键；值为 OK 的键是 sure（strings.json 实测）
        Button({ type: ButtonType.Normal }) {
          Text($r('app.string.sure'))
            .fontSize(ThemeTypography.BUTTON)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.palette().colorPrimary)
            .textCase(TextCase.UpperCase)
        }
        .backgroundColor(Color.Transparent)
        .borderRadius(ThemeRadius.BUTTON)
        .constraintSize({ minHeight: ThemeDimens.DIALOG_ACTION_MIN_HEIGHT })
        .padding({ left: 8, right: 8 })
        .onClick(() => {
          this.onSave(this.state.buildExcludedString(this.patterns));
        })
      }
      .width('100%')
      .constraintSize({ minHeight: ThemeDimens.TOOLBAR_HEIGHT })
      .padding({ left: 16, right: 16 })
      .border({ width: { bottom: 1 }, color: this.palette().divider })

      Row({ space: 8 }) {
        Button({ type: ButtonType.Normal }) {
          Text($r('app.string.select_all'))
            .fontSize(12)
            .fontColor(this.palette().textPrimary)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .borderRadius(ThemeRadius.BUTTON)
        .backgroundColor(this.palette().widgetBackground)
        .height(36)
        .layoutWeight(1)
        .onClick(() => {
          this.state.selectAll();
          this.rev = this.rev + 1;
        })

        Button({ type: ButtonType.Normal }) {
          Text($r('app.string.deselect_all'))
            .fontSize(12)
            .fontColor(this.palette().textPrimary)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .borderRadius(ThemeRadius.BUTTON)
        .backgroundColor(this.palette().widgetBackground)
        .height(36)
        .layoutWeight(1)
        .onClick(() => {
          this.state.deselectAll();
          this.rev = this.rev + 1;
        })

        Button({ type: ButtonType.Normal }) {
          Text($r('app.string.invert_selection'))
            .fontSize(12)
            .fontColor(this.palette().textPrimary)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .borderRadius(ThemeRadius.BUTTON)
        .backgroundColor(this.palette().widgetBackground)
        .height(36)
        .layoutWeight(1)
        .onClick(() => {
          this.state.invertSelection();
          this.rev = this.rev + 1;
        })
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 8, bottom: 8 })

      Row({ space: 8 }) {
        Text($r('app.string.language'))
          .fontSize(12)
          .fontColor(this.palette().textSecondary)
          .layoutWeight(1)
        Text($r('app.string.original'))
          .fontSize(12)
          .fontColor(this.palette().textSecondary)
          .width(48)
          .textAlign(TextAlign.Center)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text($r('app.string.translated'))
          .fontSize(12)
          .fontColor(this.palette().textSecondary)
          .width(56)
          .textAlign(TextAlign.Center)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text($r('app.string.rewrite'))
          .fontSize(12)
          .fontColor(this.palette().textSecondary)
          .width(48)
          .textAlign(TextAlign.Center)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 4, bottom: 8 })

      Divider()
        .strokeWidth(1)
        .color(this.palette().divider)
        .width('100%')

      List() {
        ForEach(this.languageLabels, (label: string, row: number) => {
          ListItem() {
            Row({ space: 8 }) {
              Text(label)
                .fontSize(14)
                .fontColor(this.palette().textPrimary)
                .layoutWeight(1)
              Column() {
                Checkbox()
                  .select(this.rev >= 0 ? this.state.selections[row][0] : false)
                  .selectedColor(this.palette().controlActivated)
                  .unselectedColor(this.palette().drawablePrimary)
                  .shape(CheckBoxShape.ROUNDED_SQUARE)
                  .onChange((isChecked: boolean) => {
                    if (this.state.selections[row][0] !== isChecked) {
                      this.state.setCell(row, 0, isChecked, true);
                      this.rev = this.rev + 1;
                    }
                  })
              }
              .width(48)
              .alignItems(HorizontalAlign.Center)

              Column() {
                Checkbox()
                  .select(this.rev >= 0 ? this.state.selections[row][1] : false)
                  .selectedColor(this.palette().controlActivated)
                  .unselectedColor(this.palette().drawablePrimary)
                  .shape(CheckBoxShape.ROUNDED_SQUARE)
                  .onChange((isChecked: boolean) => {
                    if (this.state.selections[row][1] !== isChecked) {
                      this.state.setCell(row, 1, isChecked, true);
                      this.rev = this.rev + 1;
                    }
                  })
              }
              .width(56)
              .alignItems(HorizontalAlign.Center)

              Column() {
                Checkbox()
                  .select(this.rev >= 0 ? this.state.selections[row][2] : false)
                  .selectedColor(this.palette().controlActivated)
                  .unselectedColor(this.palette().drawablePrimary)
                  .shape(CheckBoxShape.ROUNDED_SQUARE)
                  .onChange((isChecked: boolean) => {
                    if (this.state.selections[row][2] !== isChecked) {
                      this.state.setCell(row, 2, isChecked, true);
                      this.rev = this.rev + 1;
                    }
                  })
              }
              .width(48)
              .alignItems(HorizontalAlign.Center)
            }
            .width('100%')
            .padding({ left: 16, right: 16, top: 8, bottom: 8 })
          }
        }, (label: string, row: number) => `${row}:${label}`)
      }
      .width('100%')
      .layoutWeight(1)
      .divider({ strokeWidth: 1, color: this.palette().divider })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.palette().popupBackground)
  }
}