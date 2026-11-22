/**
 * 迁移自 app/src/main/java/com/hippo/ehviewer/preference/ProxyPreference.java（S0170，上游 162 行）
 *
 * 判据：**UI 组件行**（`extends DialogPreference implements View.OnClickListener`），自有逻辑：
 *   onPrepareDialogBuilder / onDialogCreated：对话框内"代理类型 + 主机 + 端口"表单，类型切换时启用/禁用主机与端口
 *   onClick：代理类型单选 → 联动启用状态
 *   onDialogClosed(positiveResult)：**true 时**写回 (type, host, port)
 * ⇒ 组合 `DialogPreference` + 表单状态；写回只在确认时发生。
 *
 * 断言重点：**取消不写回**、类型切换时的启用联动、端口空串不当作 0。
 */
import { DialogPreference, DialogPreferenceState } from '../../preference/DialogPreference';
import { ProxyType as EhProxyType } from '../EhProxySelector';
import { InetValidator } from '../../network/InetValidator';
import { Settings } from '../Settings';
import { GetText } from '../GetText';
import { ProxyDialogLayout } from '../../ui/layout/preference_dialog_proxy';

/** 与 EhProxySelector.ProxyType 1:1 对齐的四态代理常量（0=Direct, 1=System, 2=HTTP, 3=SOCKS） */
export class ProxyType {
  static readonly TYPE_DIRECT: number = EhProxyType.TYPE_DIRECT;
  static readonly TYPE_SYSTEM: number = EhProxyType.TYPE_SYSTEM;
  static readonly TYPE_HTTP: number = EhProxyType.TYPE_HTTP;
  static readonly TYPE_SOCKS: number = EhProxyType.TYPE_SOCKS;
  static readonly LABELS: string[] = ['Direct', 'System Proxy', 'HTTP', 'SOCKS'];

  /** 仅 HTTP/SOCKS 允许编辑主机与端口 */
  static hostEnabled(type: number): boolean {
    return type === ProxyType.TYPE_HTTP || type === ProxyType.TYPE_SOCKS;
  }

  static clampType(type: number): number {
    if (type >= ProxyType.TYPE_DIRECT && type <= ProxyType.TYPE_SOCKS) {
      return type;
    }
    return ProxyType.TYPE_SYSTEM;
  }
}

export class ProxyValue {
  type: number = ProxyType.TYPE_SYSTEM;
  host: string = '';
  port: string = '';
  portNumber: number = -1;
}

export class ProxyValidationResult {
  ok: boolean = false;
  type: number = ProxyType.TYPE_SYSTEM;
  host: string = '';
  port: number = -1;
  hostErrorKey: string = '';
  portErrorKey: string = '';
}

export class ProxyPreferenceHelper {
  /** 上游 ProxyPreference.onClick 校验逻辑：trim host/port，HTTP/SOCKS 要求 host 非空且 port 在 0..65535 */
  static validate(type: number, rawHost: string, rawPort: string): ProxyValidationResult {
    const res: ProxyValidationResult = new ProxyValidationResult();
    const t: number = ProxyType.clampType(type);
    const host: string = rawHost.trim();
    const portStr: string = rawPort.trim();
    const needEndpoint: boolean = ProxyType.hostEnabled(t);

    if (needEndpoint && host.length === 0) {
      res.hostErrorKey = 'text_is_empty';
      return res;
    }

    let portNum: number = -1;
    if (!needEndpoint) {
      if (portStr.length > 0 && /^\d+$/.test(portStr)) {
        const parsed: number = Number.parseInt(portStr, 10);
        if (InetValidator.isValidInetPort(parsed)) {
          portNum = parsed;
        }
      }
    } else if (portStr.length === 0) {
      res.portErrorKey = 'text_is_empty';
      return res;
    } else {
      if (!/^\d+$/.test(portStr)) {
        res.portErrorKey = 'proxy_invalid_port';
        return res;
      }
      const parsed: number = Number.parseInt(portStr, 10);
      if (!InetValidator.isValidInetPort(parsed)) {
        res.portErrorKey = 'proxy_invalid_port';
        return res;
      }
      portNum = parsed;
    }

    res.ok = true;
    res.type = t;
    res.host = host;
    res.port = portNum;
    return res;
  }

  /** 上游 updateSummary(type, ip, port) */
  static formatSummary(type: number, ip: string | null, port: number, labels?: string[]): string {
    let t: number = ProxyType.clampType(type);
    const hostStr: string = ip === null ? '' : ip;
    if (ProxyType.hostEnabled(t) && (hostStr.length === 0 || !InetValidator.isValidInetPort(port))) {
      t = ProxyType.TYPE_SYSTEM;
    }
    const label: string = (labels !== undefined && labels.length > t) ? labels[t] : ProxyType.LABELS[t];
    if (ProxyType.hostEnabled(t)) {
      return `${label} ${hostStr}:${port}`;
    }
    return label;
  }
}

@Component
export struct ProxyPreference {
  state: DialogPreferenceState = new DialogPreferenceState();
  @Prop title: string = '';
  @Prop summary: string = '';
  @Prop dialogTitle: string = '';
  @Prop currentType: number = -1;
  @Prop currentHost: string | null = null;
  @Prop currentPort: number = -2;
  @Prop themeId: number = -1;
  @Prop showDivider: boolean = false;
  onChanged: (value: ProxyValue) => void = (value: ProxyValue) => {
  };
  @State type: number = ProxyType.TYPE_SYSTEM;
  @State host: string = '';
  @State port: string = '';
  @State hostError: ResourceStr = '';
  @State portError: ResourceStr = '';
  @State rev: number = 0;

  private loadFromSettingsOrProps(): void {
    const t: number = this.currentType >= 0 ? ProxyType.clampType(this.currentType) : ProxyType.clampType(Settings.getProxyType());
    const ipVal: string | null = this.currentHost !== null ? this.currentHost : Settings.getProxyIp();
    const portVal: number = this.currentPort >= -1 ? this.currentPort : Settings.getProxyPort();
    this.type = t;
    this.host = ipVal === null ? '' : ipVal;
    this.port = InetValidator.isValidInetPort(portVal) ? `${portVal}` : '';
    this.hostError = '';
    this.portError = '';
    this.state.summary = this.computeSummary(t, ipVal, portVal);
  }

  private localizedLabels(): string[] {
    const direct: string = GetText.getString('proxy_direct');
    const system: string = GetText.getString('proxy_system');
    const http: string = GetText.getString('proxy_http');
    const socks: string = GetText.getString('proxy_socks');
    return [
      direct.length > 0 ? direct : ProxyType.LABELS[0],
      system.length > 0 ? system : ProxyType.LABELS[1],
      http.length > 0 ? http : ProxyType.LABELS[2],
      socks.length > 0 ? socks : ProxyType.LABELS[3]
    ];
  }

  private computeSummary(type: number, ip: string | null, port: number): string {
    return ProxyPreferenceHelper.formatSummary(type, ip, port, this.localizedLabels());
  }

  aboutToAppear(): void {
    const ctx: Context | undefined = this.getUIContext().getHostContext();
    if (ctx !== undefined && !GetText.isInitialized()) {
      GetText.initialize(ctx);
    }
    this.state.title = this.title;
    this.state.dialogTitle = this.dialogTitle;
    this.loadFromSettingsOrProps();
  }

  private validateDraft(): boolean {
    const check: ProxyValidationResult = ProxyPreferenceHelper.validate(this.type, this.host, this.port);
    this.hostError = check.hostErrorKey.length > 0 ? $r('app.string.text_is_empty') : '';
    if (check.portErrorKey === 'text_is_empty') {
      this.portError = $r('app.string.text_is_empty');
    } else if (check.portErrorKey === 'proxy_invalid_port') {
      this.portError = $r('app.string.proxy_invalid_port');
    } else {
      this.portError = '';
    }
    this.rev = this.rev + 1;
    return check.ok;
  }

  build() {
    DialogPreference({
      state: this.state,
      themeId: this.themeId,
      showDivider: this.showDivider,
      onPrepareDialog: () => {
        this.loadFromSettingsOrProps();
      },
      onValidatePositive: (): boolean => {
        return this.validateDraft();
      },
      onDialogClosed: (positiveResult: boolean) => {
        if (positiveResult) {
          const check: ProxyValidationResult = ProxyPreferenceHelper.validate(this.type, this.host, this.port);
          if (check.ok) {
            Settings.putProxyType(check.type);
            Settings.putProxyIp(check.host);
            Settings.putProxyPort(check.port);
            this.type = check.type;
            this.host = check.host;
            this.port = InetValidator.isValidInetPort(check.port) ? `${check.port}` : '';
            this.state.summary = this.computeSummary(check.type, check.host, check.port);
            const v: ProxyValue = new ProxyValue();
            v.type = check.type;
            v.host = check.host;
            v.port = this.port;
            v.portNumber = check.port;
            this.onChanged(v);
          }
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
    ProxyDialogLayout({
      proxyTypeIndex: this.type,
      host: this.host,
      port: this.port,
      hostError: this.hostError,
      portError: this.portError,
      themeId: this.themeId,
      onTypeChange: (index: number) => {
        this.type = ProxyType.clampType(index);
        this.hostError = '';
        this.portError = '';
      },
      onHostChange: (value: string) => {
        this.host = value;
        if (this.hostError !== '') {
          this.hostError = '';
        }
      },
      onPortChange: (value: string) => {
        this.port = value;
        if (this.portError !== '') {
          this.portError = '';
        }
      }
    })
  }
}
