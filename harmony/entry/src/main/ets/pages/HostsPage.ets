import { relationalStore } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { ThemePalette, ThemeTokens } from '../common/theme/ThemeTokens';
import { AppWiring } from '../hippo/AppWiring';
import { EhApplication } from '../hippo/ehviewer/EhApplication';
import { Hosts, HostIpPair, HostsDbLike, HostsResultSetLike, RdbHostsStore } from '../hippo/ehviewer/Hosts';
import {
  HostsActivity, HostsHost, HostEntry, HostDialogSpec, HostCommitResult, HostListState,
  HOST_DIALOG_ADD, HOST_DIALOG_EDIT, FAB_BOTTOM_PADDING_VP, STR_INVALID_HOST, STR_INVALID_IP
} from '../hippo/ehviewer/ui/HostsActivity';
import { ActivityHostsLayout } from '../hippo/ui/layout/activity_hosts';
import { HostsDialogLayout } from '../hippo/ui/layout/dialog_hosts';
import { HostsItemLayout } from '../hippo/ui/layout/item_hosts';
import { VArrowLeftDarkX24 } from '../hippo/ui/drawable/v_arrow_left_dark_x24';
import { VPlusDarkX24 } from '../hippo/ui/drawable/v_plus_dark_x24';

const LOG_DOMAIN: number = 0x0000;
const LOG_TAG: string = 'HostsPage';

class RdbHostsResultSetAdapter implements HostsResultSetLike {
  private readonly rs: relationalStore.ResultSet;

  constructor(rs: relationalStore.ResultSet) {
    this.rs = rs;
  }

  goToNextRow(): boolean {
    return this.rs.goToNextRow();
  }

  getColumnIndex(name: string): number {
    return this.rs.getColumnIndex(name);
  }

  isColumnNull(index: number): boolean {
    return this.rs.isColumnNull(index);
  }

  getString(index: number): string {
    return this.rs.getString(index);
  }

  close(): void {
    this.rs.close();
  }
}

class RdbHostsDbAdapter implements HostsDbLike {
  private readonly store: relationalStore.RdbStore;

  constructor(store: relationalStore.RdbStore) {
    this.store = store;
  }

  private toBindArgs(args?: Array<string | number>): Array<relationalStore.ValueType> {
    const out: Array<relationalStore.ValueType> = [];
    if (args !== undefined) {
      for (let i = 0; i < args.length; i++) {
        out.push(args[i]);
      }
    }
    return out;
  }

  async querySql(sql: string, bindArgs?: Array<string | number>): Promise<HostsResultSetLike> {
    const rs: relationalStore.ResultSet = await this.store.querySql(sql, this.toBindArgs(bindArgs));
    return new RdbHostsResultSetAdapter(rs);
  }

  async executeSql(sql: string, args?: Array<string | number>): Promise<void> {
    await this.store.executeSql(sql, this.toBindArgs(args));
  }
}

class HostsPageHostImpl implements HostsHost {
  private readonly getContextFn: () => common.Context | undefined;
  private readonly finishFn: () => void;
  private readonly showDialogFn: (spec: HostDialogSpec) => void;
  private hostsPromise: Promise<Hosts> | null = null;

  constructor(
    getContextFn: () => common.Context | undefined,
    finishFn: () => void,
    showDialogFn: (spec: HostDialogSpec) => void
  ) {
    this.getContextFn = getContextFn;
    this.finishFn = finishFn;
    this.showDialogFn = showDialogFn;
  }

  private async getHosts(): Promise<Hosts> {
    if (this.hostsPromise !== null) {
      return await this.hostsPromise;
    }
    const ctx: common.Context | undefined = this.getContextFn();
    if (ctx === undefined) {
      throw new Error('HostsPage context is unavailable');
    }
    const pending: Promise<Hosts> = (async (): Promise<Hosts> => {
      await AppWiring.whenReady();
      const shared: Hosts | null = EhApplication.getHosts(ctx);
      if (shared !== null) {
        return shared;
      }
      const rdbStore: relationalStore.RdbStore = await relationalStore.getRdbStore(ctx, {
        name: AppWiring.DB_NAME,
        securityLevel: relationalStore.SecurityLevel.S1
      });
      const store: RdbHostsStore = new RdbHostsStore(new RdbHostsDbAdapter(rdbStore));
      return new Hosts(store);
    })().catch((err: Error): Hosts => {
      this.hostsPromise = null;
      throw err;
    });
    this.hostsPromise = pending;
    return await pending;
  }

  async getAll(): Promise<HostIpPair[]> {
    const hosts: Hosts = await this.getHosts();
    return await hosts.getAll();
  }

  async put(host: string, ip: string): Promise<boolean> {
    const hosts: Hosts = await this.getHosts();
    return await hosts.put(host, ip);
  }

  async delete(host: string): Promise<void> {
    const hosts: Hosts = await this.getHosts();
    await hosts.delete(host);
  }

  isValidHost(host: string): boolean {
    return Hosts.isValidHost(host);
  }

  isValidIp(ip: string): boolean {
    return Hosts.isValidIp(ip);
  }

  finish(): void {
    this.finishFn();
  }

  showDialog(spec: HostDialogSpec): void {
    this.showDialogFn(spec);
  }
}

@Entry
@Component
struct HostsPage {
  @State entries: HostEntry[] = [];
  @State listVisible: boolean = false;
  @State tipVisible: boolean = true;
  @State dialogOpen: boolean = false;
  @State dialogKind: number = HOST_DIALOG_ADD;
  @State dialogHost: string = '';
  @State dialogIp: string = '';
  @State dialogHostEnabled: boolean = true;
  @State dialogHostError: ResourceStr = '';
  @State dialogIpError: ResourceStr = '';
  @State saving: boolean = false;

  private activeSpec: HostDialogSpec | null = null;
  private controller: HostsActivity | null = null;

  private palette(): ThemePalette {
    return ThemeTokens.current();
  }

  aboutToAppear(): void {
    const backend: HostsPageHostImpl = new HostsPageHostImpl(
      (): common.Context | undefined => this.getUIContext().getHostContext(),
      (): void => {
        this.navigateBack();
      },
      (spec: HostDialogSpec): void => {
        this.openSpecDialog(spec);
      }
    );
    const ctrl: HostsActivity = new HostsActivity(backend);
    this.controller = ctrl;
    this.loadHosts(ctrl);
  }

  private loadHosts(ctrl: HostsActivity): void {
    ctrl.onCreate().then((state: HostListState): void => {
      this.applyListState(ctrl, state);
    }).catch((err: Error): void => {
      hilog.error(LOG_DOMAIN, LOG_TAG, '%{public}s', `Failed to load hosts: ${err.message}`);
      this.showToast($r('app.string.hosts_load_failed'));
    });
  }

  private applyListState(ctrl: HostsActivity, state: HostListState): void {
    this.entries = ctrl.getEntries();
    this.listVisible = state.listVisible;
    this.tipVisible = state.tipVisible;
  }

  private syncEntriesFromController(): void {
    if (this.controller === null) {
      return;
    }
    const next: HostEntry[] = this.controller.getEntries();
    this.entries = next;
    this.listVisible = next.length > 0;
    this.tipVisible = next.length === 0;
  }

  private navigateBack(): void {
    try {
      this.getUIContext().getRouter().back();
    } catch (err) {
      hilog.warn(LOG_DOMAIN, LOG_TAG, '%{public}s', `Router back failed: ${JSON.stringify(err)}`);
    }
  }

  private showToast(message: ResourceStr): void {
    try {
      this.getUIContext().getPromptAction().showToast({ message: message, duration: 2000 });
    } catch (err) {
      hilog.warn(LOG_DOMAIN, LOG_TAG, '%{public}s', `Toast failed: ${JSON.stringify(err)}`);
    }
  }

  private mapErrorResource(key: string | null): ResourceStr {
    if (key === STR_INVALID_HOST) {
      return $r('app.string.invalid_host');
    }
    if (key === STR_INVALID_IP) {
      return $r('app.string.invalid_ip');
    }
    return '';
  }

  private openSpecDialog(spec: HostDialogSpec): void {
    this.activeSpec = spec;
    this.dialogKind = spec.kind;
    this.dialogHost = spec.hostText;
    this.dialogIp = spec.ipText;
    this.dialogHostEnabled = spec.hostInputEnabled;
    this.dialogHostError = this.mapErrorResource(spec.hostError);
    this.dialogIpError = this.mapErrorResource(spec.ipError);
    this.dialogOpen = true;
  }

  private onSaveClicked(): void {
    if (this.saving || this.controller === null || this.activeSpec === null) {
      return;
    }
    const ctrl: HostsActivity = this.controller;
    const spec: HostDialogSpec = this.activeSpec;
    spec.hostText = this.dialogHost;
    spec.ipText = this.dialogIp;
    this.saving = true;
    ctrl.put(spec).then((result: HostCommitResult): void => {
      this.dialogHostError = this.mapErrorResource(spec.hostError);
      this.dialogIpError = this.mapErrorResource(spec.ipError);
      if (result.ok) {
        this.syncEntriesFromController();
        this.dialogOpen = false;
      }
      this.saving = false;
    }).catch((err: Error): void => {
      this.saving = false;
      hilog.error(LOG_DOMAIN, LOG_TAG, '%{public}s', `Failed to save host: ${err.message}`);
      this.showToast($r('app.string.hosts_save_failed'));
    });
  }

  private onDeleteClicked(): void {
    if (this.saving || this.controller === null || this.activeSpec === null) {
      return;
    }
    const ctrl: HostsActivity = this.controller;
    const spec: HostDialogSpec = this.activeSpec;
    spec.hostText = this.dialogHost;
    this.saving = true;
    ctrl.delete(spec).then((ok: boolean): void => {
      if (ok) {
        this.syncEntriesFromController();
        this.dialogOpen = false;
      }
      this.saving = false;
    }).catch((err: Error): void => {
      this.saving = false;
      hilog.error(LOG_DOMAIN, LOG_TAG, '%{public}s', `Failed to delete host: ${err.message}`);
      this.showToast($r('app.string.hosts_save_failed'));
    });
  }

  @Builder
  hostsListBuilder(): void {
    List() {
      ForEach(this.entries, (entry: HostEntry, index: number) => {
        ListItem() {
          HostsItemLayout({
            host: entry.host,
            ip: entry.ip,
            textColor: '#DE000000'
          })
        }
        .onClick(() => {
          if (this.controller !== null) {
            this.controller.onItemClick(index);
          }
        })
      }, (entry: HostEntry, index: number) => `${index}:${entry.host}:${entry.ip}`)
    }
    .width('100%')
    .height('100%')
    .divider({ strokeWidth: 1, color: '#1F000000' })
    .padding({ bottom: FAB_BOTTOM_PADDING_VP })
  }

  @Builder
  hostsFabBuilder(): void {
    Stack({ alignContent: Alignment.BottomEnd }) {
      Button({ type: ButtonType.Circle }) {
        VPlusDarkX24({ iconSize: 24, fillColor: this.palette().fabIconColor })
      }
      .width(56)
      .height(56)
      .backgroundColor($r('app.color.teal_500'))
      .shadow({ radius: 8, color: '#33000000', offsetY: 3 })
      .margin({ right: 16, bottom: 16 })
      .onClick(() => {
        if (this.controller !== null) {
          this.controller.onClickFab();
        }
      })
    }
    .width('100%')
    .height('100%')
    .hitTestBehavior(HitTestMode.Transparent)
  }

  @Builder
  hostDialogSheet(): void {
    Column({ space: 16 }) {
      HostsDialogLayout({
        host: this.dialogHost,
        ip: this.dialogIp,
        hostInputEnabled: this.dialogHostEnabled,
        hostError: this.dialogHostError,
        ipError: this.dialogIpError,
        onHostChange: (value: string) => {
          this.dialogHost = value;
          this.dialogHostError = '';
        },
        onIpChange: (value: string) => {
          this.dialogIp = value;
          this.dialogIpError = '';
        }
      })

      Row({ space: 8 }) {
        if (this.dialogKind === HOST_DIALOG_EDIT) {
          Button($r('app.string.edit_host_delete'))
            .type(ButtonType.Normal)
            .fontColor('#FFD32F2F')
            .backgroundColor(Color.Transparent)
            .enabled(!this.saving)
            .onClick(() => {
              this.onDeleteClicked();
            })
        }

        Blank()

        Button($r('app.string.cancel'))
          .type(ButtonType.Normal)
          .fontColor('#666666')
          .backgroundColor(Color.Transparent)
          .onClick(() => {
            this.dialogOpen = false;
          })

        Button(this.dialogKind === HOST_DIALOG_EDIT
          ? $r('app.string.edit_host_confirm')
          : $r('app.string.add_host_add'))
          .type(ButtonType.Normal)
          .fontColor($r('app.color.teal_500'))
          .backgroundColor(Color.Transparent)
          .enabled(!this.saving)
          .onClick(() => {
            this.onSaveClicked();
          })
      }
      .width('100%')
      .padding({ left: 16, right: 16, bottom: 16 })
    }
    .width('100%')
  }

  build() {
    Column() {
      Row({ space: 8 }) {
        Button({ type: ButtonType.Normal }) {
          VArrowLeftDarkX24({ iconSize: 24, fillColor: this.palette().toolbarIconColor })
        }
        .width(44)
        .height(44)
        .backgroundColor(Color.Transparent)
        .onClick(() => {
          if (this.controller !== null) {
            this.controller.onOptionsItemSelected('android.R.id.home');
          } else {
            this.navigateBack();
          }
        })

        Text($r('app.string.hosts'))
          .fontSize(20)
          .fontWeight(FontWeight.Medium)
          .fontColor('#FFFFFFFF')
          .layoutWeight(1)
      }
      .width('100%')
      .height(56)
      .padding({ left: 8, right: 16 })
      .backgroundColor($r('app.color.teal_500'))

      Column() {
        ActivityHostsLayout({
          listVisible: this.listVisible,
          tipVisible: this.tipVisible,
          recyclerViewBuilder: () => {
            this.hostsListBuilder();
          },
          fabLayoutBuilder: () => {
            this.hostsFabBuilder();
          }
        })
      }
      .layoutWeight(1)
      .width('100%')
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.start_window_background'))
    .bindSheet($$this.dialogOpen, this.hostDialogSheet(), {
      height: SheetSize.FIT_CONTENT,
      dragBar: true,
      title: {
        title: this.dialogKind === HOST_DIALOG_EDIT ? $r('app.string.edit_host') : $r('app.string.add_host')
      }
    })
  }
}
