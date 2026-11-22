/*
 * Copyright 2026 ehviewer-harmony contributors
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

/**
 * 移植自 app/src/main/java/com/hippo/ehviewer/ui/wifi/WiFiServerActivity.java（535 行）。
 *
 * ============================================================================
 * 一、上游是什么（WiFi 传书的**发送端**）
 * ============================================================================
 * 起 TCP 监听（`ListenerThread(PORT=54321)`）→ 对端连上后 `ConnectThread` 收发帧；
 * 界面 = Spinner 选"发什么"（4 项）+ 一个「开始/停止」按钮 + 一段状态文本：
 *
 *   ```java
 *   selectIndex: 0=书签(QuickSearch) 1=收藏(GalleryInfo) 2=下载(标签 + DownloadInfo) 3=下载目录(迁移)
 *   onStatusChange(): sending ? stopMigration() : (队列非空 ? sendNextPage() : 按 selectIndex 造数据)
 *   sendNextPage():   队列非空且连接可用 → connectThread.sendFrame(removeFirst)
 *   onDirAck(ack):    对端要哪些文件 → 逐个 sendFileChunks（按 FILE_CHUNK_SIZE 切块）
 *   ```
 *
 * 逐行对照时最容易丢的**六条**（都在本文件里显式保留）：
 *   1. `totalPage` 是**向上取整**，且 `length=0 → 0`（零页 = 一帧都不发）；
 *   2. `pageSize` 字段里写的是 **pageCount（总页数）**、`pageIndex` 写 `i+1` ——
 *      字段名叫 pageSize 但语义是"总页数"，**不能"修正"**（对端按 totalSize 解析）；
 *   3. 造数据用 `list.remove(0)` **就地消费**（不是按下标切片）；不足一页时内层 `continue` 跳过；
 *   4. `createDownloadDirData` 每次迭代都查 `!sending`（中途停止要立刻退）；
 *   5. 空文件也要发一帧 `last=true` 的空块，否则对端建不出文件；
 *   6. `onDirAck` 在 `entry/metaMap/transport` 任一为空时**仍然**调 `sendNextPage()`（不能吞）。
 *
 * ============================================================================
 * 二、ArkTS 侧架构（对齐 net-parse 交付物）
 * ============================================================================
 * 底层已由 net-parse 做成"纯逻辑 + 注入"：`ListenerThread(port)`、`ConnectThread.sendFrame`、
 * `WiFiFrameCodec.*`、`WiFiDownloadMigrationHelper.*(fs)`。所以本文件同样是**状态机 + 编排**：
 *   - 发送 → `FrameTransport`（生产包 `@ohos.net.socket`，测试用内存实现）
 *   - 扫描 → `MigrationFileSystem`；**读块 → `FileChunkSource`（本文件定义，见下）**
 *   - 界面 → 返回值（`StateText` / `StatusButtonState` / `WiFiServerAction`），由 ArkUI 页面渲染
 *   - 数据源 → **入参**（调用方负责 `EhDB.getAllLocalFavorites()` 等查询），规则层不依赖 RDB
 *
 * ============================================================================
 * 三、三个交付侧的偏差（都已在下游消化，必须记录）
 * ============================================================================
 * ① **`WiFiDataHand.addData(key, value: string)` 会把值再 `JSON.stringify` 一次**
 *    （`WiFidDataHandData.put` 内 `JSON.stringify(value)`）。上游是 `addData(String, Object)`，
 *    传 `JSONArray` 时线上 JSON 是**真数组**；照当前的 `addData` 走会得到**双重编码的字符串**，
 *    对端（尤其 Android 端）解析不出数组。→ 本文件改用 `putArrayData()`：手工拼 `{"k":[...]}`
 *    后 `setData()`，与上游线格式一致。
 * ② **`QuickSearch` 没有 `toJson()`**（上游 `QuickSearch.java:133` 有，9 键）。
 *    → 本文件用 `quickSearchToJson()` 按上游键集与顺序补齐，待 storage-db 补上后改为调用它。
 * ③ **`DispatchEvent` 不带 MSG 文本**（上游 `msg.getData().getString("MSG")`）。
 *    → `stateTextForEvent(event, msgText)` 由调用方传入文本。
 */

import { DispatchEvent } from '../../client/wifi/ConnectThread';
import { ConnectThread } from '../../client/wifi/ConnectThread';
import { FrameTransport } from '../../client/wifi/ConnectThread';
import { WiFiDataHand } from '../../client/data/wifi/WiFiDataHand';
import { WiFiFrame } from '../../client/wifi/WiFiFrame';
import { WiFiFrameCodec } from '../../client/wifi/WiFiFrameCodec';
import { WiFiDownloadMigrationHelper } from '../../client/wifi/WiFiDownloadMigrationHelper';
import { MigrationFileSystem } from '../../client/wifi/WiFiDownloadMigrationHelper';
import { DirAck } from '../../client/wifi/MigrationTypes';
import { FileMeta } from '../../client/wifi/MigrationTypes';
import { GalleryDirEntry } from '../../client/wifi/MigrationTypes';
import { GalleryInfo } from '../../client/data/GalleryInfo';
import { DownloadInfo } from '../../dao/DownloadInfo';
import { DownloadLabel } from '../../dao/DownloadLabel';
import { QuickSearch } from '../../dao/QuickSearch';
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN: number = 0x0000;
const TAG: string = 'WiFiServer';

/** Spinner 的 4 个选项（顺序即 `selectIndex`，不要重排）。 */
export enum WiFiServerMenu {
  BOOKMARK = 0,
  FAVORITE = 1,
  DOWNLOAD = 2,
  DOWNLOAD_DIR = 3
}

/** 「开始/停止」按下后的意图（`onStatusChange` 的分支结果）。 */
export enum WiFiServerAction {
  NONE = 0,
  STOP = 1,
  SEND_NEXT = 2,
  BUILD_BOOKMARK = 3,
  BUILD_FAVORITE = 4,
  BUILD_DOWNLOAD = 5,
  BUILD_DOWNLOAD_DIR = 6
}

/** 状态文本（上游 `textState.setText(...)`）；`resKey` + 参数交页面渲染。 */
export class StateText {
  resKey: string;
  args: (string | number)[];

  constructor(resKey: string, args: (string | number)[]) {
    this.resKey = resKey;
    this.args = args;
  }

  static of(resKey: string, ...args: (string | number)[]): StateText {
    return new StateText(resKey, args);
  }
}

/** 「开始/停止」按钮文本（上游 `updateStatusButton`）。 */
export class StatusButtonState {
  resKey: string;
  suffix: string;

  constructor(resKey: string, suffix: string) {
    this.resKey = resKey;
    this.suffix = suffix;
  }
}

/** 网卡枚举投影（上游 `NetworkInterface` + `InetAddress`）。 */
export class NetworkInterfaceLike {
  name: string;
  addresses: string[];
  /** 与 `addresses` 同序：是否 IPv4（上游 `getAddress().length == 4`）。 */
  ipv4Flags: boolean[];

  constructor(name: string, addresses: string[], ipv4Flags: boolean[]) {
    this.name = name;
    this.addresses = addresses;
    this.ipv4Flags = ipv4Flags;
  }
}

/**
 * 分块读文件的抽象（对应上游 `UniFile.openInputStream()` + 循环 `read(buffer)`）。
 *
 * 为什么单独定义、不加进 `MigrationFileSystem`：那个接口是 net-parse 的交付物（跨 scope），
 * 而本文件只需要"按块读"，用一个更小的接口即可；生产实现包 `@ohos.file.fs` 的 `read()`，
 * 测试用内存实现。`readChunk` 返回 `null` 表示 EOF。
 */
export interface FileChunkSource {
  /** 从 offset 读最多 length 字节；EOF 返回 null。 */
  readChunk(path: string, offset: number, length: number): Uint8Array | null;
}

/**
 * WiFi 传书**发送端**（对位上游 `WiFiServerActivity`）。
 */
export class WiFiServerActivity {
  /** 监听端口（上游 `PORT = 54321`）。 */
  public static readonly PORT: number = 54321;
  /** 权限请求码（上游 `REQUEST_CODE = 996`）。 */
  public static readonly REQUEST_CODE: number = 996;
  /** 每页条数（上游 `int pageSize = 10`）。 */
  public static readonly PAGE_SIZE: number = 10;
  /** `onNothingSelected` 的哨兵下标（上游 `selectIndex = 999`）。 */
  public static readonly SELECT_INDEX_NONE: number = 999;

  private sending: boolean = false;
  private readonly sendQueue: WiFiFrame[] = [];
  private readonly dirEntryMap: Map<string, GalleryDirEntry> = new Map<string, GalleryDirEntry>();
  private readonly dirFileMetaMap: Map<string, Map<string, FileMeta>> =
    new Map<string, Map<string, FileMeta>>();
  /** 迁移扫描的根目录（`GalleryDirEntry` 只有 gid/dirname，目录路径靠 root 拼）。 */
  private dirRoot: string = '';
  private selectIndex: number = 0;
  private transport: FrameTransport | null = null;

  // ------------------------------------------------------------------ 纯函数

  /** 总页数（上游 `totalPage`）：向上取整；`length=0 → 0`。 */
  static totalPage(length: number, pageSize: number): number {
    if (pageSize <= 0) {
      return 0;
    }
    const a: number = Math.floor(length / pageSize);
    const b: number = length % pageSize;
    return b > 0 ? a + 1 : a;
  }

  /** 迁移目录键（上游 `dirKey` = `gid + ":" + dirname`）。 */
  static dirKey(gid: number, dirname: string): string {
    return `${gid}:${dirname}`;
  }

  /**
   * 「开始/停止」语义（上游 `onStatusChange` 分支树）。
   * 顺序关键：先 `sending`，再队列非空，最后才按 selectIndex 造数据。
   */
  static planStatusChange(sending: boolean, queueEmpty: boolean, selectIndex: number): WiFiServerAction {
    if (sending) {
      return WiFiServerAction.STOP;
    }
    if (!queueEmpty) {
      return WiFiServerAction.SEND_NEXT;
    }
    switch (selectIndex) {
      case WiFiServerMenu.BOOKMARK:
        return WiFiServerAction.BUILD_BOOKMARK;
      case WiFiServerMenu.FAVORITE:
        return WiFiServerAction.BUILD_FAVORITE;
      case WiFiServerMenu.DOWNLOAD:
        return WiFiServerAction.BUILD_DOWNLOAD;
      case WiFiServerMenu.DOWNLOAD_DIR:
        return WiFiServerAction.BUILD_DOWNLOAD_DIR;
      default:
        return WiFiServerAction.NONE;
    }
  }

  /** 按钮文本（上游 `updateStatusButton` 的四条分支）。 */
  static statusButtonState(sending: boolean, queueSize: number): StatusButtonState {
    const resKey: string = sending ? 'wifi_send_stop' : 'wifi_send_start';
    const suffix: string = queueSize > 0 ? `(${queueSize})` : '';
    return new StatusButtonState(resKey, suffix);
  }

  /** 取 `wlan*` 网卡上第一个非回环 IPv4（上游 `getWifiApIpAddress`）；找不到 → null。 */
  static pickWlanIpv4(interfaces: NetworkInterfaceLike[]): string | null {
    for (let i = 0; i < interfaces.length; i++) {
      const intf: NetworkInterfaceLike = interfaces[i];
      if (!intf.name.includes('wlan')) {
        continue;
      }
      for (let j = 0; j < intf.addresses.length; j++) {
        const addr: string = intf.addresses[j];
        const isIpv4: boolean = j < intf.ipv4Flags.length ? intf.ipv4Flags[j] : addr.includes('.');
        if (!addr.startsWith('127.') && isIpv4) {
          return addr;
        }
      }
    }
    return null;
  }

  /** 权限是否仍需申请（上游 `requestMyPermission()` 未授权 → true）。 */
  static isPermissionRequired(accessWifiStateGranted: boolean): boolean {
    return !accessWifiStateGranted;
  }

  /**
   * `QuickSearch` 的 JSON（上游 `QuickSearch.java:133` 的 9 个键，顺序一致）。
   *
   * 临时补位：我们的 `QuickSearch` 没有 `toJson()`。待 storage-db 补上后删掉本方法改为调用。
   */
  static quickSearchToJson(search: QuickSearch): string {
    const name: string = search.name === null ? '' : search.name;
    const keyword: string = search.keyword === null ? '' : search.keyword;
    return `{"name":${JSON.stringify(name)},"mode":${search.mode},"category":${search.category},` +
      `"keyword":${JSON.stringify(keyword)},"advanceSearch":${search.advanceSearch},` +
      `"minRating":${search.minRating},"pageFrom":${search.pageFrom},` +
      `"pageTo":${search.pageTo},"time":${search.time}}`;
  }

  /** 路径拼接（与 `WiFiDownloadMigrationHelper.join` 同语义）。 */
  private static joinPath(dir: string, name: string): string {
    return dir.length > 0 && dir.charAt(dir.length - 1) === '/' ? dir + name : dir + '/' + name;
  }

  // ------------------------------------------------------------------ 状态

  public isSending(): boolean {
    return this.sending;
  }

  public queueSize(): number {
    return this.sendQueue.length;
  }

  public statusButton(): StatusButtonState {
    return WiFiServerActivity.statusButtonState(this.sending, this.sendQueue.length);
  }

  /** Spinner 选中（上游 `onItemSelected`）。 */
  public onItemSelected(position: number): void {
    this.selectIndex = position;
  }

  /** Spinner 未选中（上游 `onNothingSelected` → 999）。 */
  public onNothingSelected(): void {
    this.selectIndex = WiFiServerActivity.SELECT_INDEX_NONE;
  }

  public currentSelectIndex(): number {
    return this.selectIndex;
  }

  /** 绑定连接（上游 `new ConnectThread(...)` 后持有）。 */
  public attachTransport(transport: FrameTransport | null): void {
    this.transport = transport;
  }

  /** 停止发送并清队列（上游 `stopMigration`）。 */
  public stopMigration(): void {
    this.sending = false;
    this.sendQueue.length = 0;
  }

  /** 按钮按下（上游 `onStatusChange`）：更新 `sending` 并回报意图。 */
  public onStatusChange(): WiFiServerAction {
    const action: WiFiServerAction =
      WiFiServerActivity.planStatusChange(this.sending, this.sendQueue.length === 0, this.selectIndex);
    if (action === WiFiServerAction.STOP) {
      this.stopMigration();
      return action;
    }
    if (action !== WiFiServerAction.NONE) {
      this.sending = true;
    }
    return action;
  }

  // ------------------------------------------------------------------ 造数据

  /**
   * 把数组值放进 `WiFiDataHand` 的 data（**绕过 `addData` 的双重编码**，见文件头偏差 ①）。
   *
   * @param jsonTexts 每个元素的**JSON 文本**（不含外层方括号）
   */
  private putArrayData(hand: WiFiDataHand, key: string, jsonTexts: string[]): void {
    hand.setData(`{${JSON.stringify(key)}:[${jsonTexts.join(',')}]}`);
  }

  /** 把字符串数组放进 data（标签列表用；等价上游 `JSONArray.add(String)`）。 */
  private putStringArrayData(hand: WiFiDataHand, key: string, values: string[]): void {
    hand.setData(`{${JSON.stringify(key)}:${JSON.stringify(values)}}`);
  }

  /** 入队一帧（上游 `enqueueHand`）。 */
  public enqueueHand(hand: WiFiDataHand): void {
    this.sendQueue.push(WiFiFrameCodec.encode(hand));
  }

  /** 收藏（上游 `createFavoriteData`）：10 条/页，消费传入列表。返回页数。 */
  public buildFavoriteFrames(list: GalleryInfo[]): number {
    const pageCount: number = WiFiServerActivity.totalPage(list.length, WiFiServerActivity.PAGE_SIZE);
    for (let i = 0; i < pageCount; i++) {
      const hand: WiFiDataHand = new WiFiDataHand(WiFiDataHand.SEND);
      hand.dataType = ConnectThread.DATA_TYPE_FAVORITE_INFO;
      hand.pageSize = pageCount;
      hand.pageIndex = i + 1;
      const objects: string[] = [];
      for (let j = 0; j < WiFiServerActivity.PAGE_SIZE; j++) {
        if (list.length === 0) {
          continue;
        }
        const galleryInfo: GalleryInfo = list.shift() as GalleryInfo;
        objects.push(galleryInfo.toJson());
      }
      this.putArrayData(hand, ConnectThread.FAVORITE_INFO_DATA_KEY, objects);
      this.enqueueHand(hand);
    }
    return pageCount;
  }

  /** 书签/快速搜索（上游 `createBookmarkData`）：10 条/页。返回页数。 */
  public buildBookmarkFrames(list: QuickSearch[]): number {
    const pageCount: number = WiFiServerActivity.totalPage(list.length, WiFiServerActivity.PAGE_SIZE);
    for (let i = 0; i < pageCount; i++) {
      const hand: WiFiDataHand = new WiFiDataHand(WiFiDataHand.SEND);
      hand.dataType = ConnectThread.DATA_TYPE_QUICK_SEARCH;
      hand.pageSize = pageCount;
      hand.pageIndex = i + 1;
      const objects: string[] = [];
      for (let j = 0; j < WiFiServerActivity.PAGE_SIZE; j++) {
        if (list.length === 0) {
          continue;
        }
        const quickSearch: QuickSearch = list.shift() as QuickSearch;
        objects.push(WiFiServerActivity.quickSearchToJson(quickSearch));
      }
      this.putArrayData(hand, ConnectThread.QUICK_SEARCH_DATA_KEY, objects);
      this.enqueueHand(hand);
    }
    return pageCount;
  }

  /**
   * 下载（上游 `createDownloadData`）：先一帧**标签列表**（不分页），再 10 条/页发 `DownloadInfo`。
   * 返回信息页数（标签帧不计）。
   */
  public buildDownloadFrames(labels: DownloadLabel[], allInfo: DownloadInfo[]): number {
    const labelHand: WiFiDataHand = new WiFiDataHand(WiFiDataHand.SEND);
    labelHand.dataType = ConnectThread.DATA_TYPE_DOWNLOAD_LABEL;
    const labelArray: string[] = [];
    for (let i = 0; i < labels.length; i++) {
      const label: string | null = labels[i].getLabel();
      labelArray.push(label === null ? '' : label);
    }
    this.putStringArrayData(labelHand, ConnectThread.DOWNLOAD_LABEL_KEY, labelArray);
    this.enqueueHand(labelHand);

    const pageCount: number = WiFiServerActivity.totalPage(allInfo.length, WiFiServerActivity.PAGE_SIZE);
    for (let i = 0; i < pageCount; i++) {
      const infoHand: WiFiDataHand = new WiFiDataHand(WiFiDataHand.SEND);
      infoHand.dataType = ConnectThread.DATA_TYPE_DOWNLOAD_INFO;
      infoHand.pageSize = pageCount;
      infoHand.pageIndex = i + 1;
      const infoArray: string[] = [];
      for (let j = 0; j < WiFiServerActivity.PAGE_SIZE; j++) {
        if (allInfo.length === 0) {
          continue;
        }
        const downloadInfo: DownloadInfo = allInfo.shift() as DownloadInfo;
        infoArray.push(downloadInfo.toJson());
      }
      this.putArrayData(infoHand, ConnectThread.DOWNLOAD_INFO_DATA_KEY, infoArray);
      this.enqueueHand(infoHand);
    }
    return pageCount;
  }

  /**
   * 下载目录迁移（上游 `createDownloadDirData`）：逐目录发 manifest。
   *
   * @returns `false` = 没有可迁移目录（上游在此 `sending=false` + Toast `wifi_download_dir_empty`）
   */
  public buildDownloadDirFrames(fs: MigrationFileSystem, root: string): boolean {
    this.dirEntryMap.clear();
    this.dirFileMetaMap.clear();
    this.dirRoot = root;
    const entries: GalleryDirEntry[] = WiFiDownloadMigrationHelper.scanGalleryDirs(fs, root);
    if (entries.length === 0) {
      this.sending = false;
      return false;
    }
    const total: number = entries.length;
    for (let i = 0; i < total; i++) {
      if (!this.sending) {
        return true;
      }
      const entry: GalleryDirEntry = entries[i];
      const dirPath: string = WiFiServerActivity.joinPath(root, entry.dirname);
      const files: FileMeta[] = WiFiDownloadMigrationHelper.scanGalleryDir(fs, dirPath);
      const key: string = WiFiServerActivity.dirKey(entry.gid, entry.dirname);
      this.dirEntryMap.set(key, entry);
      const metaMap: Map<string, FileMeta> = new Map<string, FileMeta>();
      for (let k = 0; k < files.length; k++) {
        metaMap.set(files[k].name, files[k]);
      }
      this.dirFileMetaMap.set(key, metaMap);
      this.sendQueue.push(WiFiFrameCodec.encodeManifest(entry.gid, entry.dirname, files, i + 1, total,
        ConnectThread.DATA_TYPE_DOWNLOAD_DIR_MANIFEST));
    }
    return true;
  }

  // ------------------------------------------------------------------ 发送

  /**
   * 发下一帧（上游 `sendNextPage`）。
   *
   * 三条出口：队列空 → `sending=false`（页面提示 `wifi_send_done`）；
   * 连接可用 → 写一帧（返回 `SEND_NEXT`）；连接不可用 → `sending=false`（提示 `wifi_server_connect_unable`）。
   */
  public sendNextPage(): WiFiServerAction {
    if (!this.sending) {
      return WiFiServerAction.NONE;
    }
    if (this.sendQueue.length === 0) {
      this.sending = false;
      return WiFiServerAction.NONE;
    }
    if (this.transport !== null) {
      const frame: WiFiFrame = this.sendQueue.shift() as WiFiFrame;
      this.transport.writeFrame(frame);
      return WiFiServerAction.SEND_NEXT;
    }
    this.sending = false;
    hilog.warn(DOMAIN, TAG, 'connect transport unavailable');
    return WiFiServerAction.STOP;
  }

  /**
   * 对端的目录 ack（上游 `onDirAck`）：按 `filesNeeded` 逐个发文件块。
   *
   * @returns 发送失败的文件名列表（上游只 `Analytics.recordException`，这里交调用方决定）
   */
  public onDirAck(ack: DirAck, fs: MigrationFileSystem, reader: FileChunkSource): string[] {
    if (!this.sending) {
      return [];
    }
    const key: string = WiFiServerActivity.dirKey(ack.gid, ack.dirname);
    const entry: GalleryDirEntry | undefined = this.dirEntryMap.get(key);
    const metaMap: Map<string, FileMeta> | undefined = this.dirFileMetaMap.get(key);
    if (entry === undefined || metaMap === undefined || this.transport === null) {
      // 上游：条件不满足**仍然**推进队列，否则发送会卡死在这里
      this.sendNextPage();
      return [];
    }
    const failed: string[] = [];
    for (let i = 0; i < ack.filesNeeded.length; i++) {
      if (!this.sending) {
        return failed;
      }
      const name: string = ack.filesNeeded[i];
      const meta: FileMeta | undefined = metaMap.get(name);
      if (meta === undefined) {
        continue;
      }
      if (!this.sendFileChunks(entry, meta, fs, reader)) {
        failed.push(name);
      }
    }
    if (this.sending) {
      this.sendNextPage();
    }
    return failed;
  }

  /**
   * 分块发送一个文件（上游 `sendFileChunks`）。
   *
   * - `chunkTotal = ceil(fileLen / FILE_CHUNK_SIZE)`，`<= 0` 按 1；
   * - `last = (chunkIndex + 1 >= chunkTotal)`；
   * - **读到 0 块（空文件）时补一帧空块 `last=true`**，否则对端不会建文件；
   * - 中途 `sending` 变 false → 返回 false（不是异常）。
   */
  public sendFileChunks(entry: GalleryDirEntry, meta: FileMeta, fs: MigrationFileSystem,
    reader: FileChunkSource): boolean {
    const dirPath: string = WiFiServerActivity.joinPath(this.dirRoot, entry.dirname);
    const filePath: string | null = fs.resolveFileInGallery(dirPath, meta.name);
    if (filePath === null || !fs.isFile(filePath)) {
      return false;
    }
    const chunkSize: number = WiFiDownloadMigrationHelper.FILE_CHUNK_SIZE;
    const fileLen: number = meta.size > 0 ? meta.size : fs.size(filePath);
    let chunkTotal: number = Math.floor((fileLen + chunkSize - 1) / chunkSize);
    if (chunkTotal <= 0) {
      chunkTotal = 1;
    }
    let chunkIndex: number = 0;
    let offset: number = 0;
    while (true) {
      if (!this.sending) {
        return false;
      }
      const data: Uint8Array | null = reader.readChunk(filePath, offset, chunkSize);
      if (data === null || data.byteLength === 0) {
        break;
      }
      const last: boolean = chunkIndex + 1 >= chunkTotal;
      const frame: WiFiFrame = WiFiFrameCodec.encodeFileChunk(
        entry.gid, meta.name, meta.md5, chunkIndex, chunkTotal,
        data.buffer as ArrayBuffer, last, ConnectThread.DATA_TYPE_DOWNLOAD_DIR_FILE);
      if (this.transport !== null) {
        this.transport.writeFrame(frame);
      }
      chunkIndex++;
      offset += data.byteLength;
    }
    if (chunkIndex === 0) {
      const frame: WiFiFrame = WiFiFrameCodec.encodeFileChunk(
        entry.gid, meta.name, meta.md5, 0, 1, new ArrayBuffer(0), true,
        ConnectThread.DATA_TYPE_DOWNLOAD_DIR_FILE);
      if (this.transport !== null) {
        this.transport.writeFrame(frame);
      }
    }
    return true;
  }

  // ------------------------------------------------------------------ 事件分派

  /**
   * 事件 → 状态文本（上游 `WiFiServerHandler.handleMessage` 的文本分支）。
   *
   * @param msgText 上游 `msg.getData().getString("MSG")`（我们的 `DispatchEvent` 不携带，由调用方传入）
   * @returns `null` = 该事件不改状态文本（上游 `DEVICE_CONNECTING`/`GET_*` 分支不动 textState）
   */
  public stateTextForEvent(event: DispatchEvent, msgText: string): StateText | null {
    switch (event.what) {
      case ConnectThread.DEVICE_CONNECTED:
        return StateText.of('wifi_server_connection_succeeded');
      case ConnectThread.DEVICE_DISCONNECTED:
        return StateText.of('wifi_server_disconnect');
      case ConnectThread.SEND_MSG_SUCCESS:
        return StateText.of('wifi_server_send_success', msgText);
      case ConnectThread.SEND_MSG_ERROR:
        return StateText.of('wifi_server_send_fail', msgText);
      default:
        return null;
    }
  }

  /**
   * `SEND_MSG_SUCCESS` 之后的队列推进（上游 handler 里那段）：
   * 未在发送 → 只刷按钮；队列空 → 提示完成；否则继续发。
   *
   * @returns 需要提示 `wifi_send_done` 时为 true
   */
  public onSendSuccess(): boolean {
    if (!this.sending) {
      return false;
    }
    if (this.sendQueue.length === 0) {
      this.sending = false;
      return true;
    }
    this.sendNextPage();
    return false;
  }

  /** `SEND_MSG_ERROR`：停止发送（上游 `sending = false; updateStatusButton()`）。 */
  public onSendError(): void {
    this.sending = false;
  }

  /** 销毁（上游 `onDestroy`：关连接、清状态）。 */
  public destroy(): void {
    if (this.transport !== null) {
      this.transport.close();
      this.transport = null;
    }
    this.sending = false;
    this.sendQueue.length = 0;
    this.dirEntryMap.clear();
    this.dirFileMetaMap.clear();
    this.dirRoot = '';
  }
}
