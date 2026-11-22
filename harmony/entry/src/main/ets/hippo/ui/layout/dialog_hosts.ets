/*
 * 上游：app/src/main/res/layout/dialog_hosts.xml（inventory S0577，上游 47 行）
 * 目标：harmony/entry/src/main/ets/hippo/ui/layout/dialog_hosts.ets
 *
 * 背景：自定义 hosts 对话框：域名 + IP 两个输入框。
 *
 * ── 结构对照 ────────────────────────────────────────────────────────────────
 * Android                                ArkUI
 * LinearLayout(vertical, match × match)   Column().width('100%').height('100%')
 *   paddingLeft/Right=?attr/dialogPreferredPadding(24dp)  .padding({left:24,right:24})
 *   paddingTop=@dimen/abc_dialog_padding_top_material(24dp) .padding({top:24})
 * TextInputLayout#host_input_layout       Column（见 1）
 *   hint=@string/hosts_host                 → TextInput 的 placeholder
 *   HackyTextInputEditText#host             TextInput（TODO(ui-widget)）
 *     inputType=text                          InputType.Normal
 * TextInputLayout#ip_input_layout         Column
 *   hint=@string/hosts_ip                   → placeholder
 *   HackyTextInputEditText#ip               TextInput
 *
 * ── 无法等价 / 需注意 ───────────────────────────────────────────────────────
 * 1. `TextInputLayout` 无 ArkUI 对位（浮动标签 + 错误提示位）→ 只取 hint 作为 placeholder，
 *    不伪造浮动动画（与 dialog_add_blacklist / dialog_edittext_builder 同一处理）。
 * 2. **两个输入框之间没有 marginTop**（上游这里没写，与 dialog_add_blacklist 的 16dp 不同）→
 *    照原样不加间距。这类"看起来该有间距但上游没有"的地方必须按上游，否则视觉漂移。
 * 3. 高度 `match_parent`：对话框内容撑满，由外部 AlertDialog 决定实际高度。
 * 4. `HackyTextInputEditText` 未交付 → TODO(ui-widget)，外观与输入属性用系统 TextInput 对位。
 */

function isNonEmptyHostRes(v: ResourceStr): boolean {
  if (typeof v === 'string') {
    return v.length > 0;
  }
  return true;
}

@Component
export struct HostsDialogLayout {
  @Prop @Watch('onHostPropChanged') host: string = '';
  @Prop @Watch('onIpPropChanged') ip: string = '';
  @Prop hostInputEnabled: boolean = true;
  @Prop hostError: ResourceStr = '';
  @Prop ipError: ResourceStr = '';
  @Prop textColor: ResourceColor = '#DE000000';
  @Prop errorColor: ResourceColor = '#FFD32F2F';
  @Prop dialogPreferredPadding: number = 24;
  @Prop dialogPaddingTop: number = 24;

  @State draftHost: string = '';
  @State draftIp: string = '';

  onHostChange: (value: string) => void = (value: string) => {
    // 默认空实现：使用方注入
  };
  onIpChange: (value: string) => void = (value: string) => {
    // 默认空实现：使用方注入
  };

  aboutToAppear(): void {
    this.draftHost = this.host;
    this.draftIp = this.ip;
  }

  private onHostPropChanged(): void {
    if (this.host !== this.draftHost) {
      this.draftHost = this.host;
    }
  }

  private onIpPropChanged(): void {
    if (this.ip !== this.draftIp) {
      this.draftIp = this.ip;
    }
  }

  build() {
    Column() {
      // 域名输入（上游 TextInputLayout hint=@string/hosts_host）
      Column() {
        // TODO(ui-widget): com.hippo.widget.HackyTextInputEditText
        TextInput({ text: this.draftHost, placeholder: $r('app.string.hosts_host') })
          .type(InputType.Normal)
          .fontColor(this.textColor)
          .enabled(this.hostInputEnabled)
          .width('100%')
          .onChange((value: string) => {
            this.draftHost = value;
            this.onHostChange(value);
          })
        if (isNonEmptyHostRes(this.hostError)) {
          Text(this.hostError)
            .fontSize(12)
            .fontColor(this.errorColor)
            .margin({ top: 4 })
        }
      }
      .width('100%')

      // IP 输入（上游 TextInputLayout hint=@string/hosts_ip；两框之间**无** margin）
      Column() {
        // TODO(ui-widget): com.hippo.widget.HackyTextInputEditText
        TextInput({ text: this.draftIp, placeholder: $r('app.string.hosts_ip') })
          .type(InputType.Normal)
          .fontColor(this.textColor)
          .width('100%')
          .onChange((value: string) => {
            this.draftIp = value;
            this.onIpChange(value);
          })
        if (isNonEmptyHostRes(this.ipError)) {
          Text(this.ipError)
            .fontSize(12)
            .fontColor(this.errorColor)
            .margin({ top: 4 })
        }
      }
      .width('100%')
    }
    .width('100%')
    .padding({
      left: this.dialogPreferredPadding,
      right: this.dialogPreferredPadding,
      top: this.dialogPaddingTop
    })
    .alignItems(HorizontalAlign.Start)
  }
}
