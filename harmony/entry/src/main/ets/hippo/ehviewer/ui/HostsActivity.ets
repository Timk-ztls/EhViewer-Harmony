/*
 * 上游：app/src/main/java/com/hippo/ehviewer/ui/HostsActivity.java
 *       （inventory S0209，上游实际 275 行；清单登记 225 行）
 * 目标：harmony/entry/src/main/ets/hippo/ehviewer/ui/HostsActivity.ets
 *
 * 背景：**Hosts 配置页**（自定义域名 → IP）。列表 + FAB 新增 + 点条目编辑。
 * 两个对话框（增/改）共用同一个抽象基类 `HostDialogFragment`，只有"按钮与标题"不同。
 *
 * ── 上游行为逐条对照 ────────────────────────────────────────────────────────
 * 常量：`DIALOG_TAG_ADD_HOST` / `DIALOG_TAG_EDIT_HOST`（= 类全名）、
 *      `KEY_HOST = "com.hippo.ehviewer.ui.HostsActivity.HOST"`、`KEY_IP = "...IP"`
 *      （**键名带包名前缀**，不是简短的 host/ip —— 照搬）
 * `onCreate`：
 *   · `hosts = EhApplication.getHosts(this)`；`data = hosts.getAll()`
 *   · `activity_hosts` 布局；返回图标 `v_arrow_left_dark_x24`；`recyclerView` / `tip` / `fab`
 *   · **列表与 tip 二选一**：`data.isEmpty() ? recyclerView.GONE/tip.VISIBLE : recyclerView.VISIBLE/tip.GONE`
 *   · 分隔线 `setShowLastDivider(true)`（**与 GalleryInfoScene 不同**：那个没设，默认不画末尾线）
 *   · `recyclerView.setPadding(..., bottom + @dimen/gallery_padding_bottom_fab)`（**给 FAB 留出底部空间**）
 * `onOptionsItemSelected(home)` → `finish()` + **true**
 * `onItemClick(position)`：`pair = data.get(position)` → args 带 `KEY_HOST`/`KEY_IP` → 弹 **Edit** 对话框 → true
 * `onClick(fab)` → 弹 **Add** 对话框
 * `notifyHostsChanges()`：`data = hosts.getAll()` → 重算列表/tip 可见性 → `adapter.notifyDataSetChanged()`
 *
 * `HostDialogFragment.onCreateDialog(savedInstanceState)`：
 *   · 取 `dialog_hosts` 里的 host / ip 两个输入框
 *   · **`savedInstanceState == null && arguments != null`** 才回填（编辑时才有 args；新增时 args 为 null）
 *   · `dialog.setOnShowListener` → `onCreateDialog(dialog)`（**按钮监听必须在 show 之后挂**）
 * `put(dialog)`（两个对话框共用）：
 *   ① `hostString = host.trim().toLowerCase(Locale.US)` —— **trim + 小写（US locale）**
 *   ② `ipString = ip.trim()` —— **只 trim，不改大小写**（IPv6 有大小写含义）
 *   ③ `!Hosts.isValidHost(hostString)` → host 输入框 setError `@string/invalid_host` 并 **return**
 *   ④ `!Hosts.isValidIp(ipString)` → ip 输入框 setError `@string/invalid_ip` 并 **return**
 *   ⑤ `hosts.put(hostString, ipString)` → `notifyHostsChanges()` → `dialog.dismiss()`
 * `delete(dialog)`：
 *   ① `hostString = host.trim().toLowerCase(Locale.US)`
 *   ② `hosts.delete(hostString)` → `notifyHostsChanges()` → `dismiss()`
 *   —— **注意 delete 不校验 host 合法性**（它来自已有数据）
 * `AddHostDialogFragment`：title `@string/add_host` + 正按钮 `@string/add_host_add` → 点击 `put`
 * `EditHostDialogFragment`：title `@string/edit_host` + 正按钮 `@string/edit_host_confirm` +
 *   负按钮 `@string/edit_host_delete`；**`host_input_layout.setEnabled(false)`**（host 不可改，只能改 IP）
 *   → 正按钮 `put`、负按钮 `delete`
 * `HostsAdapter.onBindViewHolder`：`holder.host.setText(pair.first)` / `holder.ip.setText(pair.second)`
 *   —— **host 与 ip 都原样显示**（`getAll()` 已经按上游规则排序/归一化）
 *
 * ── 关键行为（照搬，别"顺手修"）──────────────────────────────────────────────
 * 1. **host 归一化 = `trim().toLowerCase(Locale.US)`；ip 只 `trim()`** ——
 *    IPv6 的十六进制部分大小写敏感地表达同一地址，但**改写大小写会掩盖用户输入**；上游只 trim。
 * 2. **`toLowerCase(Locale.US)` 不是裸 `toLowerCase()`** —— 土耳其语环境下 `I` 会变成 `ı`，
 *    导致同样的 host 在不同 locale 得到不同 key。ArkTS 用 `toLowerCase()`（无 locale 参数）
 *    在 ArkTS/JS 里是 locale-independent 的，**与 `Locale.US` 行为一致**（见 DEVIATIONS）。
 * 3. **两个校验的顺序固定**：先 host 后 ip，**遇到第一个错误就 return**（不两个都标红）。
 * 4. **编辑时 host 输入框禁用** —— 只允许改 IP。删除时用的是**当前输入框里的 host**（被禁用但仍有值）。
 * 5. **`notifyHostsChanges` 里重新 `getAll()`** —— 不是本地增删，而是全量重读（Hosts 内部有排序）。
 * 6. **列表/tip 的可见性在两个地方各算一次**（onCreate 与 notifyHostsChanges）—— 上游重复，照搬。
 * 7. **`KEY_HOST`/`KEY_IP` 是带包名的长键**（防 Bundle 冲突），不是 `"host"`/`"ip"`。
 * 8. **`setShowLastDivider(true)`**（本页有，GalleryInfoScene 没有）—— 差异要有意识地保留。
 *
 * ── 平台差异 ────────────────────────────────────────────────────────────────
 * 1. `ToolbarActivity` + `DialogFragment` 在 ArkUI 无对位 → `HostsHost`（数据/对话框/提示/退出）
 *    与**纯数据对话框描述**（`HostDialogSpec`）。
 * 2. `TextInputLayout.setError` → `HostDialogSpec.hostError` / `ipError` 字段（同 `EditTextDialogSpec` 做法）。
 * 3. `UniFile`/`EasyRecyclerView` → ArkUI `List`；`FloatingActionButton` → 页面按钮。
 * 4. `Pair<String,String>` → `HostEntry`（`host` / `ip`），避免 ArkTS 无元组。
 * 5. `Hosts.isValidHost/isValidIp` **本仓库已存在**（`hippo/ehviewer/Hosts.ets`）→ **直接调用**，不重写校验。
 *
 * ── 依赖实测（本仓已存在）──────────────────────────────────────────────────
 * `Hosts`（`getAll` / `put` / `delete` / `isValidHost` / `isValidIp`）、`EhApplication.getHosts`、
 * 全部 14 个字符串键（实测 `strings.json` 里都有）。
 *
 * ── 缺口 ───────────────────────────────────────────────────────────────────
 * `@dimen/gallery_padding_bottom_fab` 本仓库没有独立 dimen 文件 → 以 `FAB_BOTTOM_PADDING_VP = 72` 常量表达
 * （上游该 dimen 的值未在清单内；按 FAB 标准高度 56 + 16 边距估算，标注为"待真机校准"）。
 */

import { Hosts, HostIpPair } from '../Hosts';

/** 上游两个对话框 tag（= 类全名） */
export const DIALOG_TAG_ADD_HOST: string = 'com.hippo.ehviewer.ui.HostsActivity$AddHostDialogFragment';
export const DIALOG_TAG_EDIT_HOST: string = 'com.hippo.ehviewer.ui.HostsActivity$EditHostDialogFragment';
/** 上游两个 args 键（**带包名前缀**，见「关键行为」7） */
export const KEY_HOST: string = 'com.hippo.ehviewer.ui.HostsActivity.HOST';
export const KEY_IP: string = 'com.hippo.ehviewer.ui.HostsActivity.IP';

/** 上游字符串键 */
export const STR_INVALID_HOST: string = 'app.string.invalid_host';
export const STR_INVALID_IP: string = 'app.string.invalid_ip';
export const STR_ADD_HOST: string = 'app.string.add_host';
export const STR_ADD_HOST_ADD: string = 'app.string.add_host_add';
export const STR_EDIT_HOST: string = 'app.string.edit_host';
export const STR_EDIT_HOST_CONFIRM: string = 'app.string.edit_host_confirm';
export const STR_EDIT_HOST_DELETE: string = 'app.string.edit_host_delete';

/** 上游 `R.layout.activity_hosts` / `R.drawable.v_arrow_left_dark_x24` */
export const LAYOUT_ACTIVITY_HOSTS: string = 'activity_hosts';
export const DRAWABLE_BACK: string = 'v_arrow_left_dark_x24';
/** 上游 `@dimen/gallery_padding_bottom_fab`（见「缺口」） */
export const FAB_BOTTOM_PADDING_VP: number = 72;
/** 上游 `setShowLastDivider(true)`（本页有，GalleryInfoScene 无 —— 见「关键行为」8） */
export const SHOW_LAST_DIVIDER: boolean = true;

/** 上游 `Pair<String, String>`（host, ip）→ 具名类型 */
export class HostEntry {
  host: string = '';
  ip: string = '';

  constructor(host: string = '', ip: string = '') {
    this.host = host;
    this.ip = ip;
  }
}

/** 对话框类型 */
export const HOST_DIALOG_ADD: number = 0;
export const HOST_DIALOG_EDIT: number = 1;

/** 对话框描述（上游 `AlertDialog` + `TextInputLayout` 的纯数据对位） */
export class HostDialogSpec {
  kind: number = HOST_DIALOG_ADD;
  title: string = STR_ADD_HOST;
  /** 两个输入框的当前文本（edit 时由 args 回填） */
  hostText: string = '';
  ipText: string = '';
  /** `TextInputLayout.setError` 的对位（null = 无错误） */
  hostError: string | null = null;
  ipError: string | null = null;
  positiveText: string = STR_ADD_HOST_ADD;
  /** 仅 edit 有负按钮（删除） */
  negativeText: string | null = null;
  /** 上游 `host_input_layout.setEnabled(false)`（仅 edit） */
  hostInputEnabled: boolean = true;
  /** 页面层据此知道该弹哪个 */
  dialogTag: string = DIALOG_TAG_ADD_HOST;
}

/** 一次提交的结果 */
export class HostCommitResult {
  /** 是否已写入（false = 校验失败，对话框保持打开） */
  ok: boolean = false;
  /** 写入的 key（ok 时有值） */
  host: string = '';
  ip: string = '';
  /** 校验失败时置位（`@string/invalid_host` / `@string/invalid_ip`） */
  error: string | null = null;
}

/** 本页宿主能力（D-012：Hosts 读写均为 RDB async） */
export interface HostsHost {
  /** 上游 `hosts.getAll()` */
  getAll(): Promise<HostIpPair[]>;
  /** 上游 `hosts.put(host, ip)` */
  put(host: string, ip: string): Promise<boolean>;
  /** 上游 `hosts.delete(host)` */
  delete(host: string): Promise<void>;
  /** 上游 `Hosts.isValidHost(host)` / `isValidIp(ip)`（本仓已实现，直接转发） */
  isValidHost(host: string): boolean;
  isValidIp(ip: string): boolean;
  /** 上游 `finish()` */
  finish(): void;
  /** 页面层"弹对话框"（本文件只产出描述） */
  showDialog(spec: HostDialogSpec): void;
}

export class HostsActivity {
  private host: HostsHost;
  private data: HostEntry[] = [];
  private lastDialog: HostDialogSpec | null = null;

  constructor(host: HostsHost) {
    this.host = host;
  }

  private async reloadEntries(): Promise<HostListState> {
    const pairs: HostIpPair[] = await this.host.getAll();
    const next: HostEntry[] = [];
    for (let i = 0; i < pairs.length; i++) {
      next.push(new HostEntry(pairs[i].host, pairs[i].ip));
    }
    this.data = next;
    return this.computeVisibility();
  }

  /** 上游 `onCreate()` 的前半：取数据 + 算一次可见性 */
  async onCreate(): Promise<HostListState> {
    return this.reloadEntries();
  }

  /** 上游 `notifyHostsChanges()`：**重读 getAll** 后重算可见性（见「关键行为」5） */
  async notifyHostsChanges(): Promise<HostListState> {
    return this.reloadEntries();
  }

  /** 当前列表快照（供 UI ForEach 渲染） */
  getEntries(): HostEntry[] {
    return this.data.slice();
  }

  /** 上游两处重复的可见性计算（见「关键行为」6） */
  private computeVisibility(): HostListState {
    const s: HostListState = new HostListState();
    s.listVisible = this.data.length > 0;
    s.tipVisible = this.data.length === 0;
    return s;
  }

  /** 上游 `getItemCount()` */
  getItemCount(): number {
    return this.data.length;
  }

  /** 上游 `onBindViewHolder`：host / ip 原样显示 */
  bindItem(position: number): HostEntry | null {
    if (position < 0 || position >= this.data.length) {
      return null;
    }
    return new HostEntry(this.data[position].host, this.data[position].ip);
  }

  /** 上游 `onOptionsItemSelected(home)` → `finish()` + true */
  onOptionsItemSelected(itemId: string): boolean {
    if (itemId === 'android.R.id.home') {
      this.host.finish();
      return true;
    }
    return false;
  }

  /** 上游 FAB `onClick` → Add 对话框（**无 args**） */
  onClickFab(): HostDialogSpec {
    const spec: HostDialogSpec = new HostDialogSpec();
    spec.kind = HOST_DIALOG_ADD;
    spec.title = STR_ADD_HOST;
    spec.positiveText = STR_ADD_HOST_ADD;
    spec.negativeText = null;
    spec.hostInputEnabled = true;
    spec.dialogTag = DIALOG_TAG_ADD_HOST;
    this.lastDialog = spec;
    this.host.showDialog(spec);
    return spec;
  }

  /** 上游 `onItemClick(position)` → Edit 对话框（**args 回填 host/ip**） */
  onItemClick(position: number): HostDialogSpec | null {
    if (position < 0 || position >= this.data.length) {
      return null;
    }
    const entry: HostEntry = this.data[position];
    const spec: HostDialogSpec = new HostDialogSpec();
    spec.kind = HOST_DIALOG_EDIT;
    spec.title = STR_EDIT_HOST;
    spec.positiveText = STR_EDIT_HOST_CONFIRM;
    spec.negativeText = STR_EDIT_HOST_DELETE;
    // 上游：savedInstanceState == null && arguments != null 才回填 → 这里恒回填
    spec.hostText = entry.host;
    spec.ipText = entry.ip;
    // 上游：dialog.findViewById(R.id.host_input_layout).setEnabled(false)
    spec.hostInputEnabled = false;
    spec.dialogTag = DIALOG_TAG_EDIT_HOST;
    this.lastDialog = spec;
    this.host.showDialog(spec);
    return spec;
  }

  /** 最近一次产出的对话框（测试观测） */
  getLastDialog(): HostDialogSpec | null {
    return this.lastDialog;
  }

  /**
   * 上游 `put(dialog)`（两个对话框共用）：
   * host = `trim + toLowerCase`；ip = `trim`；**先校验 host 再校验 ip，首个错误即 return**。
   */
  async put(spec: HostDialogSpec): Promise<HostCommitResult> {
    const result: HostCommitResult = new HostCommitResult();
    const hostString: string = normalizeHost(spec.hostText);
    const ipString: string = spec.ipText.trim();

    if (!this.host.isValidHost(hostString)) {
      // 上游：host 输入框 setError + return（**不再校验 ip**）
      spec.hostError = STR_INVALID_HOST;
      result.error = STR_INVALID_HOST;
      return result;
    }
    spec.hostError = null;

    if (!this.host.isValidIp(ipString)) {
      spec.ipError = STR_INVALID_IP;
      result.error = STR_INVALID_IP;
      return result;
    }
    spec.ipError = null;

    const saved: boolean = await this.host.put(hostString, ipString);
    if (!saved) {
      result.error = STR_INVALID_IP;
      return result;
    }
    // 上游：notifyHostsChanges()
    await this.notifyHostsChanges();
    result.ok = true;
    result.host = hostString;
    result.ip = ipString;
    // 上游：dialog.dismiss()（由页面层根据 ok 关闭）
    return result;
  }

  /**
   * 上游 `delete(dialog)`：只归一化 host，**不校验**（它来自已有数据），
   * 用**当前输入框里的 host**（编辑态下输入框被禁用但仍有值）。
   */
  async delete(spec: HostDialogSpec): Promise<boolean> {
    const hostString: string = normalizeHost(spec.hostText);
    await this.host.delete(hostString);
    await this.notifyHostsChanges();
    return true;
  }
}

/** 列表/tip 的可见性（上游两处重复计算的产物） */
export class HostListState {
  listVisible: boolean = false;
  tipVisible: boolean = true;
}

/**
 * 上游 `host.getText().toString().trim().toLowerCase(Locale.US)`。
 * ArkTS 的 `String.prototype.toLowerCase()` 是 **locale-independent**（不走土耳其语等特例），
 * 与 Java 的 `toLowerCase(Locale.US)` 行为一致；**不能用 `toLocaleLowerCase()`**（那个随 locale 变）。
 */
export function normalizeHost(s: string): string {
  return s.trim().toLowerCase();
}
