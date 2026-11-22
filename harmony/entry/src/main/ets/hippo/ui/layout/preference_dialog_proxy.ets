/*
 * 上游：app/src/main/res/layout/preference_dialog_proxy.xml（inventory S0641，上游 54 行）
 * 目标：harmony/entry/src/main/ets/hippo/ui/layout/preference_dialog_proxy.ets
 *
 * 背景：代理设置对话框：类型下拉 + 主机/IP + 端口。
 *
 * ── 结构对照 ────────────────────────────────────────────────────────────────
 * Android                                ArkUI
 * LinearLayout(vertical, match × match)   Column().width('100%').height('100%')
 *   paddingLeft/Right=?attr/dialogPreferredPadding(24dp)  .padding({left:24,right:24})
 *   paddingTop=**18dp**（硬编码，不是 24）                .padding({top:18})（见 1）
 * com.hippo.widget.CuteSpinner#type      CuteSpinner（ui-widget 已交付）
 *   entries=@array/proxy_types             $r('app.array.proxy_types')
 *   paddingTop/Bottom=8dp                  .padding({top:8,bottom:8})
 * TextInputLayout#ip_input_layout        Column
 *   hint=@string/proxy_host_or_ip           → TextInput placeholder
 *   HackyTextInputEditText#ip               TextInput（TODO(ui-widget)）+ inputType=text
 * TextInputLayout#port_input_layout      Column
 *   hint=@string/proxy_port                 → placeholder
 *   HackyTextInputEditText#port             TextInput + inputType=**numberDecimal**（见 2）
 *
 * ── 无法等价 / 需注意 ───────────────────────────────────────────────────────
 * 1. 本布局的 paddingTop 是**硬编码 18dp**（不是 dialog 的 24dp 惯例）—— 照原值，
 *    不要"统一成 24dp"（这是本文件与 dialog_hosts/add_filter 的差异点）。
 * 2. 端口输入是 `inputType="numberDecimal"`（允许小数点，不是纯 Number）→
 *    ArkUI 没有 NumberDecimal，取 `InputType.Number` 并**在注释里登记**：输入校验由业务层做
 *    （端口理论上是整数，上游允许小数点属宽松输入，不在布局层收紧）。
 * 3. 三个子项之间**没有** margin（只有 Spinner 自己的 8dp 上下 padding）→ 照原样不加间距。
 * 4. `TextInputLayout` 无 ArkUI 对位 → 只取 hint 作 placeholder，不伪造浮动标签。
 * 5. `HackyTextInputEditText` 未交付 → TODO(ui-widget)，外观/输入属性用系统 TextInput 对位。
 */

import { ThemePalette, ThemeTokens } from '../../../common/theme/ThemeTokens';
import { CuteSpinner } from '../../widget/CuteSpinner';

function isNonEmptyResStr(v: ResourceStr): boolean {
  if (typeof v === 'string') {
    return v.length > 0;
  }
  return true;
}

@Component
export struct ProxyDialogLayout {
  @Prop options: SelectOption[] = [];
  @Prop @Watch('onTypePropChanged') proxyTypeIndex: number = 1;
  @Prop @Watch('onHostPropChanged') host: string = '';
  @Prop @Watch('onPortPropChanged') port: string = '';
  @Prop hostError: ResourceStr = '';
  @Prop portError: ResourceStr = '';
  @Prop textColor: ResourceColor = ThemeTokens.LIGHT.textPrimary;
  @Prop errorColor: ResourceColor = ThemeTokens.LIGHT.errorColor;
  @Prop dialogPreferredPadding: number = 24;
  /** 上游硬编码 paddingTop=18dp（**不是** 24dp） */
  @Prop paddingTop: number = 18;
  @Prop themeId: number = -1;

  @State draftTypeIndex: number = 1;
  @State draftHost: string = '';
  @State draftPort: string = '';

  onTypeChange: (index: number) => void = (index: number) => {
    // 默认空实现：使用方注入
  };
  onHostChange: (value: string) => void = (value: string) => {
    // 默认空实现：使用方注入
  };
  onPortChange: (value: string) => void = (value: string) => {
    // 默认空实现：使用方注入
  };

  private palette(): ThemePalette {
    return this.themeId >= 0 ? ThemeTokens.of(this.themeId) : ThemeTokens.current();
  }

  aboutToAppear(): void {
    this.draftTypeIndex = this.proxyTypeIndex;
    this.draftHost = this.host;
    this.draftPort = this.port;
  }

  private onTypePropChanged(): void {
    if (this.proxyTypeIndex !== this.draftTypeIndex) {
      this.draftTypeIndex = this.proxyTypeIndex;
    }
  }

  private onHostPropChanged(): void {
    if (this.host !== this.draftHost) {
      this.draftHost = this.host;
    }
  }

  private onPortPropChanged(): void {
    if (this.port !== this.draftPort) {
      this.draftPort = this.port;
    }
  }

  private effectiveOptions(): SelectOption[] {
    if (this.options.length > 0) {
      return this.options;
    }
    return [
      { value: $r('app.string.proxy_direct') },
      { value: $r('app.string.proxy_system') },
      { value: $r('app.string.proxy_http') },
      { value: $r('app.string.proxy_socks') }
    ];
  }

  private isHostEditable(): boolean {
    return this.draftTypeIndex === 2 || this.draftTypeIndex === 3;
  }

  build() {
    Column() {
      // 类型下拉（Spinner 自带 8dp 上下 padding）
      CuteSpinner({
        options: this.effectiveOptions(),
        selected: this.draftTypeIndex,
        themeId: this.themeId,
        onSelected: (index: number, _value: string) => {
          this.draftTypeIndex = index;
          this.onTypeChange(index);
        }
      })
        .width('100%')
        .padding({ top: 8, bottom: 8 })

      // 主机/IP
      Column() {
        // TODO(ui-widget): com.hippo.widget.HackyTextInputEditText
        TextInput({ text: this.draftHost, placeholder: $r('app.string.proxy_host_or_ip') })
          .type(InputType.Normal)
          .fontColor(this.palette().textPrimary)
          .placeholderColor(this.palette().textHint)
          .backgroundColor(Color.Transparent)
          .borderRadius(0)
          .border({ width: { bottom: 1 }, color: this.palette().divider })
          .enabled(this.isHostEditable())
          .width('100%')
          .onChange((value: string) => {
            this.draftHost = value;
            this.onHostChange(value);
          })
        if (isNonEmptyResStr(this.hostError)) {
          Text(this.hostError)
            .fontSize(12)
            .fontColor(this.palette().errorColor)
            .margin({ top: 4 })
        }
      }
      .width('100%')

      // 端口（上游 inputType=numberDecimal；ArkUI 无该类型 → Number，校验交业务层）
      Column() {
        // TODO(ui-widget): com.hippo.widget.HackyTextInputEditText
        TextInput({ text: this.draftPort, placeholder: $r('app.string.proxy_port') })
          .type(InputType.Number)
          .fontColor(this.palette().textPrimary)
          .placeholderColor(this.palette().textHint)
          .backgroundColor(Color.Transparent)
          .borderRadius(0)
          .border({ width: { bottom: 1 }, color: this.palette().divider })
          .enabled(this.isHostEditable())
          .width('100%')
          .onChange((value: string) => {
            this.draftPort = value;
            this.onPortChange(value);
          })
        if (isNonEmptyResStr(this.portError)) {
          Text(this.portError)
            .fontSize(12)
            .fontColor(this.palette().errorColor)
            .margin({ top: 4 })
        }
      }
      .width('100%')
    }
    .width('100%')
    .padding({
      left: this.dialogPreferredPadding,
      right: this.dialogPreferredPadding,
      top: this.paddingTop
    })
    .alignItems(HorizontalAlign.Start)
  }
}
