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
 * 移植自 app/src/main/java/com/hippo/ehviewer/ui/wifi/WiFiClientActivity.java（413 行）。
 *
 * ============================================================================
 * 一、上游是什么（WiFi 传书的**接收端**）
 * ============================================================================
 * 主动连对端的 `PORT=54321`（网关地址），收到帧后按 `dataType` 分派：
 *
 *   ```java
 *   DATA_TYPE_QUICK_SEARCH  → EhDB.takeOverQuickSearchList(list) + 刷新书签面板
 *   DATA_TYPE_DOWNLOAD_LABEL→ manager.addLabelInSyncThread(label) + 刷新下载面板
 *   DATA_TYPE_DOWNLOAD_INFO → manager.addDownloadInfo(info, info.label)
 *   DATA_TYPE_FAVORITE_INFO → EhDB.putLocalFavorite(galleryInfo)
 *   下载目录迁移：
 *     GET_DIR_MANIFEST → filterFilesNeeded → sendDirAck(缺哪些)
 *     GET_FILE_CHUNK   → 按 offset 写块；chunkIndex==0 先删旧文件；lastChunk 校验 MD5
 *   ```
 *
 * 逐行对照时最容易丢的**五条**（本文件逐条保留并断言）：
 *   1. `intToIp` 是**小端**：`(i & 0xFF).((i>>8)&0xFF).((i>>16)&0xFF).(i>>24)&0xFF`
 *      —— 顺序写反会得到 `1.0.168.192` 这种"看似合理"的地址；
 *   2. 没有下载根目录 / 建目录失败时：**仍要回一个空 ack**（`sendDirAck(gid, dirname, [])`），
 *      否则发送端会一直等 ack（它的 `sendNextPage` 卡在这里）；
 *   3. `manifest.pageIndex == 1` 时**重置** `dirFilesCompleted = 0`（新目录，进度计数归零）；
 *   4. `chunk.chunkIndex == 0` 时：`offset = 0` + 清写入状态 + **删掉已存在的同名文件**
 *      —— 少了删除会在旧文件后面追加，得到"半个新文件 + 半个旧文件"；
 *   5. `lastChunk` 时校验 MD5，不匹配就**删文件**并记录异常（不是保留坏文件）。
 *
 * ============================================================================
 * 二、ArkTS 侧架构
 * ============================================================================
 * - **何时做什么**（分派、ack 内容、写块偏移、MD5 判定、进度计数）→ 本文件的纯函数/状态机；
 * - **真正的读写**（建目录、写块、删文件、算 MD5）→ 注入 `MigrationWriteSink`（生产实现包
 *   storage-db 的 UniFile 或 `@ohos.file.fs`）；net-parse 的 `MigrationFileSystem` 只读，
 *   写侧在本文件补齐（跨 scope 不改别人的接口）。
 * - **落地到 DB**（EhDB / DownloadManager）→ 注入 `MigrationPersistSink`：本文件只产出
 *   "要写什么"（类型 + 载荷），由调用方落到具体 DB API。
 * - **界面** → 返回 `StateText` / `ReceiveMessage` / Toast 资源名，由 ArkUI 页面渲染。
 *
 * ============================================================================
 * 三、与发送端的关系
 * ============================================================================
 * 两端共用 `WiFiFrameCodec`（帧编解码）与 `MigrationTypes`（FileMeta/DirAck/DirManifest/FileChunk），
 * 所以**协议层不重复实现**；本文件只做"收到之后怎么办"。
 */

import { DispatchEvent } from '../../client/wifi/ConnectThread';
import { ConnectThread } from '../../client/wifi/ConnectThread';
import { WiFiDataHand } from '../../client/data/wifi/WiFiDataHand';
import { WiFiFrameCodec } from '../../client/wifi/WiFiFrameCodec';
import { WiFiDownloadMigrationHelper } from '../../client/wifi/WiFiDownloadMigrationHelper';
import { FileWriteState } from '../../client/wifi/WiFiDownloadMigrationHelper';
import { MigrationFileSystem } from '../../client/wifi/WiFiDownloadMigrationHelper';
import { DirAck } from '../../client/wifi/MigrationTypes';
import { DirManifest } from '../../client/wifi/MigrationTypes';
import { FileChunk } from '../../client/wifi/MigrationTypes';
import { FileMeta } from '../../client/wifi/MigrationTypes';
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN: number = 0x0000;
const TAG: string = 'WiFiClient';

/** 收到的帧该交给谁处理（`onReceiveMsg` 的 switch）。 */
export enum ReceiveKind {
  QUICK_SEARCH = 0,
  DOWNLOAD_LABEL = 1,
  DOWNLOAD_INFO = 2,
  FAVORITE_INFO = 3,
  /** 未知 dataType：显示"未知消息"并**仍然** dataProcessed（不阻塞对端） */
  UNKNOWN = 4,
  /** 迁移 manifest */
  DIR_MANIFEST = 5,
  /** 迁移文件块 */
  DIR_FILE_CHUNK = 6
}

/** 状态文本 / 接收消息（上游 `textState.setText` / `receiveMessage.setText`）。 */
export class ClientText {
  resKey: string;
  args: (string | number)[];

  constructor(resKey: string, args: (string | number)[]) {
    this.resKey = resKey;
    this.args = args;
  }

  static of(resKey: string, ...args: (string | number)[]): ClientText {
    return new ClientText(resKey, args);
  }
}

/**
 * 写侧能力（上游直接操作 `UniFile`）。
 * 生产实现包 storage-db 的 UniFile 或 `@ohos.file.fs`；测试用内存实现。
 */
export interface MigrationWriteSink {
  /** 下载根目录是否可用（上游 `WiFiDownloadMigrationHelper.getDownloadRoot() != null`）。 */
  hasDownloadRoot(): boolean;

  /** 建/取画廊目录；失败返回 null（上游 `ensureGalleryDir`）。 */
  ensureGalleryDir(gid: number, dirname: string): string | null;

  /** 删除文件（上游 `existing.delete()`）；不存在视为成功。 */
  deleteFile(path: string): boolean;

  /** 在 offset 处写一块（上游 `writeChunk(galleryDir, name, data, offset)`）。 */
  writeChunk(galleryDir: string, name: string, data: Uint8Array, offset: number): boolean;

  /** 在画廊目录里解析相对路径（上游 `resolveFileInGallery` 的写侧对应）。 */
  resolveFile(galleryDir: string, relPath: string): string | null;
}

/** 落地能力（上游 EhDB / DownloadManager 调用）。 */
export interface MigrationPersistSink {
  /** 书签：整表接管（上游 `EhDB.takeOverQuickSearchList`）。 */
  takeOverQuickSearchList(jsonTexts: string[]): void;

  /** 下载标签（上游 `manager.addLabelInSyncThread`）。 */
  addDownloadLabel(label: string): void;

  /** 下载信息（上游 `manager.addDownloadInfo(info, info.label)`）。 */
  addDownloadInfo(jsonText: string): void;

  /** 本地收藏（上游 `EhDB.putLocalFavorite`）。 */
  putLocalFavorite(jsonText: string): void;
}

/** 一条待落地的记录（`onReceiveMsg` 解析出的载荷）。 */
export class PersistBatch {
  kind: ReceiveKind;
  /** 数组元素的 JSON 文本（`DOWNLOAD_LABEL` 时是纯字符串）。 */
  items: string[];

  constructor(kind: ReceiveKind, items: string[]) {
    this.kind = kind;
    this.items = items;
  }
}

/** manifest 处理计划（`processDownloadDirManifest` 的结果）。 */
export class ManifestPlan {
  /** 是否要回空 ack（没有下载根 / 建目录失败）。 */
  sendEmptyAck: boolean;
  /** 要回的 ack（`sendEmptyAck` 时为空数组）。 */
  needed: string[];
  /** 进度文案（`wifi_download_dir_manifest_received` 的 5 个参数）；`sendEmptyAck` 时为 null。 */
  progress: ClientText | null;
  /** 新建目录时重置完成计数（上游 `pageIndex == 1`）。 */
  resetCompleted: boolean;

  constructor(sendEmptyAck: boolean, needed: string[], progress: ClientText | null,
    resetCompleted: boolean) {
    this.sendEmptyAck = sendEmptyAck;
    this.needed = needed;
    this.progress = progress;
    this.resetCompleted = resetCompleted;
  }
}

/** 收到一个文件块后该做什么（`applyFileChunk` 的决策部分）。 */
export class ChunkPlan {
  /** 是否忽略该块（`dirnameByGid` 查不到 → 上游直接 return）。 */
  ignore: boolean;
  /** 写入偏移（`chunkIndex == 0` 时为 0）。 */
  offset: number;
  /** 是否要在写之前删掉已存在的同名文件（`chunkIndex == 0`）。 */
  deleteExisting: boolean;
  /** 是否要在写之前清空写入状态（`chunkIndex == 0`）。 */
  clearState: boolean;
  /** 本块写完后累计应加多少（`data.length`）。 */
  writtenBytes: number;
  /** 是否要校验 MD5（`lastChunk`）。 */
  verifyMd5: boolean;
  /** 是否要在完成后清状态 + 计数 +1（`lastChunk`）。 */
  finishFile: boolean;

  constructor(ignore: boolean, offset: number, deleteExisting: boolean, clearState: boolean,
    writtenBytes: number, verifyMd5: boolean, finishFile: boolean) {
    this.ignore = ignore;
    this.offset = offset;
    this.deleteExisting = deleteExisting;
    this.clearState = clearState;
    this.writtenBytes = writtenBytes;
    this.verifyMd5 = verifyMd5;
    this.finishFile = finishFile;
  }
}

/**
 * WiFi 传书**接收端**（对位上游 `WiFiClientActivity`）。
 */
export class WiFiClientActivity {
  /** 目标端口（上游 `PORT = 54321`，与发送端一致）。 */
  public static readonly PORT: number = 54321;
  /** 权限请求码（上游 `pCode = 88888`）。 */
  public static readonly PCODE: number = 88888;
  /** 每完成多少个文件刷新一次进度（上游 `dirFilesCompleted % 10 == 0`）。 */
  public static readonly PROGRESS_STEP: number = 10;

  /** 每个文件的已写字节（上游 `FileWriteState`）。 */
  private readonly fileWriteState: FileWriteState = new FileWriteState();
  /** `gid → dirname`（上游 `dirnameByGid`）。 */
  private readonly dirnameByGid: Map<number, string> = new Map<number, string>();
  /** `gid:dirname → 目录路径`（上游 `galleryDirCache`）。 */
  private readonly galleryDirCache: Map<string, string> = new Map<string, string>();
  /** 已完成的文件数（上游 `dirFilesCompleted`）。 */
  private dirFilesCompleted: number = 0;

  // ------------------------------------------------------------------ 纯函数

  /**
   * 小端 IPv4 int → 点分十进制（上游 `intToIp`）。
   *
   * 上游：`(i & 0xFF) + "." + ((i >> 8) & 0xFF) + "." + ((i >> 16) & 0xFF) + "." + (i >> 24 & 0xFF)`
   * —— **低位在前**。`WifiInfo.getIpAddress()` 返回的就是这个小端 int。
   */
  static intToIp(i: number): string {
    const b0: number = i & 0xFF;
    const b1: number = (i >> 8) & 0xFF;
    const b2: number = (i >> 16) & 0xFF;
    const b3: number = (i >> 24) & 0xFF;
    return `${b0}.${b1}.${b2}.${b3}`;
  }

  /** 目录键（上游 `dirKey`）。 */
  static dirKey(gid: number, dirname: string): string {
    return `${gid}:${dirname}`;
  }

  /** 文件写入状态键（上游 `key + "/" + chunk.name`）。 */
  static fileKey(key: string, name: string): string {
    return `${key}/${name}`;
  }

  /**
   * 收到的普通消息该交给谁（`onReceiveMsg` 的 switch）。
   *
   * 未知类型也返回 `UNKNOWN`（上游先显示"未知消息"再 `dataProcessed`）——
   * 不能"直接丢弃"，否则发送端等不到 `dataProcessed` 会卡住。
   */
  static receiveKindOf(dataType: number): ReceiveKind {
    switch (dataType) {
      case ConnectThread.DATA_TYPE_QUICK_SEARCH:
        return ReceiveKind.QUICK_SEARCH;
      case ConnectThread.DATA_TYPE_DOWNLOAD_LABEL:
        return ReceiveKind.DOWNLOAD_LABEL;
      case ConnectThread.DATA_TYPE_DOWNLOAD_INFO:
        return ReceiveKind.DOWNLOAD_INFO;
      case ConnectThread.DATA_TYPE_FAVORITE_INFO:
        return ReceiveKind.FAVORITE_INFO;
      case ConnectThread.DATA_TYPE_DOWNLOAD_DIR_MANIFEST:
        return ReceiveKind.DIR_MANIFEST;
      case ConnectThread.DATA_TYPE_DOWNLOAD_DIR_FILE:
        return ReceiveKind.DIR_FILE_CHUNK;
      default:
        return ReceiveKind.UNKNOWN;
    }
  }

  /** 数据键名（按 kind 取上游常量；`UNKNOWN` 返回空串）。 */
  static dataKeyOf(kind: ReceiveKind): string {
    switch (kind) {
      case ReceiveKind.QUICK_SEARCH:
        return ConnectThread.QUICK_SEARCH_DATA_KEY;
      case ReceiveKind.DOWNLOAD_LABEL:
        return ConnectThread.DOWNLOAD_LABEL_KEY;
      case ReceiveKind.DOWNLOAD_INFO:
        return ConnectThread.DOWNLOAD_INFO_DATA_KEY;
      case ReceiveKind.FAVORITE_INFO:
        return ConnectThread.FAVORITE_INFO_DATA_KEY;
      default:
        return '';
    }
  }

  /**
   * 文件块写入决策（`applyFileChunk` 的前半段，纯逻辑）。
   *
   * @param hasDirname `dirnameByGid` 里是否有该 gid
   * @param writtenSoFar 该文件已写字节（`fileWriteState`）
   * @param chunk 收到的块
   */
  static planChunk(hasDirname: boolean, writtenSoFar: number, chunk: FileChunk): ChunkPlan {
    if (!hasDirname) {
      return new ChunkPlan(true, 0, false, false, 0, false, false);
    }
    const isFirst: boolean = chunk.chunkIndex === 0;
    const offset: number = isFirst ? 0 : writtenSoFar;
    const dataLen: number = chunk.data === null ? 0 : chunk.data.byteLength;
    return new ChunkPlan(
      false,
      offset,
      isFirst,        // chunkIndex==0 → 删旧文件（避免追加到旧内容后面）
      isFirst,        // chunkIndex==0 → 清写入状态
      dataLen,
      chunk.lastChunk,
      chunk.lastChunk
    );
  }

  /** 进度文案（上游 `dirFilesCompleted % 10 == 0` 时刷一次）。 */
  static progressTextIfDue(completed: number): ClientText | null {
    if (completed <= 0 || completed % WiFiClientActivity.PROGRESS_STEP !== 0) {
      return null;
    }
    return ClientText.of('wifi_download_dir_files_progress', completed);
  }

  // ------------------------------------------------------------------ 迁移：manifest

  /**
   * 收到目录 manifest（上游 `processDownloadDirManifest`）。
   *
   * 两种"回空 ack"的情形必须回 ack —— 否则发送端 `onDirAck` 永远等不到，整个迁移卡死：
   *   ① 没有下载根目录（上游先 Toast `wifi_download_dir_no_location`）；
   *   ② `ensureGalleryDir` 失败。
   */
  public onDirManifest(manifest: DirManifest, sink: MigrationWriteSink,
    fs: MigrationFileSystem): ManifestPlan {
    if (!sink.hasDownloadRoot()) {
      hilog.error(DOMAIN, TAG, 'no download root for manifest gid=%{public}d', manifest.gid);
      return new ManifestPlan(true, [], null, false);
    }
    const galleryDir: string | null = sink.ensureGalleryDir(manifest.gid, manifest.dirname);
    if (galleryDir === null) {
      hilog.error(DOMAIN, TAG, 'ensureGalleryDir failed: gid=%{public}d, dir=%{public}s',
        manifest.gid, manifest.dirname);
      return new ManifestPlan(true, [], null, false);
    }
    this.dirnameByGid.set(manifest.gid, manifest.dirname);
    const key: string = WiFiClientActivity.dirKey(manifest.gid, manifest.dirname);
    this.galleryDirCache.set(key, galleryDir);
    const resetCompleted: boolean = manifest.pageIndex === 1;
    if (resetCompleted) {
      this.dirFilesCompleted = 0;
    }
    const needed: string[] = WiFiDownloadMigrationHelper.filterFilesNeeded(fs, galleryDir, manifest.files);
    const skipped: number = manifest.files.length - needed.length;
    const progress: ClientText = ClientText.of('wifi_download_dir_manifest_received',
      manifest.dirname, manifest.pageIndex, manifest.pageSize, skipped, needed.length);
    return new ManifestPlan(false, needed, progress, resetCompleted);
  }

  /** 构造要回给发送端的 ack（上游 `connectThread.sendDirAck(gid, dirname, needed)`）。 */
  static buildAck(manifest: DirManifest, needed: string[]): DirAck {
    const ack: DirAck = new DirAck();
    ack.gid = manifest.gid;
    ack.dirname = manifest.dirname;
    ack.filesNeeded = needed;
    return ack;
  }

  // ------------------------------------------------------------------ 迁移：文件块

  /**
   * 应用一个文件块（上游 `applyFileChunk`）。
   *
   * 顺序严格照上游：删旧文件 → 写块 → （lastChunk）校验 MD5 → 不匹配则删文件 → 清状态 → 计数。
   *
   * @returns 需要提示 `wifi_download_dir_file_failed` 时为 true（MD5 不匹配）
   */
  public applyFileChunk(chunk: FileChunk, sink: MigrationWriteSink, fs: MigrationFileSystem): boolean {
    const dirname: string | undefined = this.dirnameByGid.get(chunk.gid);
    const hasDirname: boolean = dirname !== undefined;
    const key: string = hasDirname
      ? WiFiClientActivity.dirKey(chunk.gid, dirname as string)
      : '';
    const fileKey: string = WiFiClientActivity.fileKey(key, chunk.name);
    const plan: ChunkPlan = WiFiClientActivity.planChunk(
      hasDirname, this.fileWriteState.getWritten(fileKey), chunk);
    if (plan.ignore) {
      return false;
    }
    let galleryDir: string | undefined = this.galleryDirCache.get(key);
    if (galleryDir === undefined) {
      const ensured: string | null = sink.ensureGalleryDir(chunk.gid, dirname as string);
      if (ensured === null) {
        return false;
      }
      galleryDir = ensured;
      this.galleryDirCache.set(key, ensured);
    }
    const dir: string = galleryDir as string;

    if (plan.clearState) {
      this.fileWriteState.clear(fileKey);
    }
    if (plan.deleteExisting) {
      const existing: string | null = sink.resolveFile(dir, chunk.name);
      if (existing !== null) {
        sink.deleteFile(existing);
      }
    }
    if (plan.writtenBytes > 0 && chunk.data !== null) {
      sink.writeChunk(dir, chunk.name, new Uint8Array(chunk.data), plan.offset);
      this.fileWriteState.addWritten(fileKey, plan.writtenBytes);
    }
    if (plan.verifyMd5) {
      let md5Mismatch: boolean = false;
      const written: string | null = sink.resolveFile(dir, chunk.name);
      if (written !== null) {
        if (!WiFiDownloadMigrationHelper.verifyFileMd5(fs, written, chunk.fileMd5)) {
          sink.deleteFile(written);
          hilog.error(DOMAIN, TAG, 'MD5 mismatch, deleted: %{public}s', chunk.name);
          md5Mismatch = true;
        }
      }
      this.fileWriteState.clear(fileKey);
      this.dirFilesCompleted++;
      return md5Mismatch;
    }
    return false;
  }

  /** 已完成文件数（上游 `dirFilesCompleted`）。 */
  public completedFiles(): number {
    return this.dirFilesCompleted;
  }

  // ------------------------------------------------------------------ 落地

  /**
   * 把收到的 JSON 数组分派给落地能力（上游 `dealWithXxx` 的公共骨架）。
   *
   * @returns 解析出的批次；`UNKNOWN` 返回 null（调用方只显示"未知消息"）
   */
  static planPersist(kind: ReceiveKind, jsonArray: string[]): PersistBatch | null {
    switch (kind) {
      case ReceiveKind.QUICK_SEARCH:
      case ReceiveKind.DOWNLOAD_INFO:
      case ReceiveKind.FAVORITE_INFO:
        return new PersistBatch(kind, jsonArray);
      case ReceiveKind.DOWNLOAD_LABEL:
        return new PersistBatch(kind, jsonArray);
      default:
        return null;
    }
  }

  /** 执行落地（顺序照上游：逐条写 → dataProcessed → 刷消息 → 通知刷新）。 */
  static persist(batch: PersistBatch, sink: MigrationPersistSink): void {
    switch (batch.kind) {
      case ReceiveKind.QUICK_SEARCH:
        sink.takeOverQuickSearchList(batch.items);
        break;
      case ReceiveKind.DOWNLOAD_LABEL:
        for (let i = 0; i < batch.items.length; i++) {
          sink.addDownloadLabel(batch.items[i]);
        }
        break;
      case ReceiveKind.DOWNLOAD_INFO:
        for (let i = 0; i < batch.items.length; i++) {
          sink.addDownloadInfo(batch.items[i]);
        }
        break;
      case ReceiveKind.FAVORITE_INFO:
        for (let i = 0; i < batch.items.length; i++) {
          sink.putLocalFavorite(batch.items[i]);
        }
        break;
      default:
        break;
    }
  }

  // ------------------------------------------------------------------ 事件分派

  /**
   * 事件 → 状态文本（上游 `WiFiClientHandler.handleMessage`）。
   *
   * 与发送端同样的三条文本分支；`GET_MSG` / `GET_DIR_*` 不改 `textState`。
   *
   * @param msgText 上游 `msg.getData().getString("MSG")`（`DispatchEvent` 不携带，调用方传入）
   */
  public stateTextForEvent(event: DispatchEvent, msgText: string): ClientText | null {
    switch (event.what) {
      case ConnectThread.DEVICE_CONNECTED:
        return ClientText.of('wifi_server_connection_succeeded');
      case ConnectThread.DEVICE_DISCONNECTED:
        return ClientText.of('wifi_server_disconnect');
      case ConnectThread.SEND_MSG_SUCCESS:
        return ClientText.of('wifi_server_send_success', msgText);
      case ConnectThread.SEND_MSG_ERROR:
        return ClientText.of('wifi_server_send_fail', msgText);
      default:
        return null;
    }
  }

  /** 收到未知 `dataType` 时的提示（上游 `wifi_server_receive_message_unknown`）。 */
  static unknownMessageText(): ClientText {
    return ClientText.of('wifi_server_receive_message_unknown');
  }

  /** 收到可识别消息后的提示（上游 `getString(R.string.wifi_server_receive_message, response.toString())`）。 */
  static receivedMessageText(response: WiFiDataHand): ClientText {
    return ClientText.of('wifi_server_receive_message', response.toJsonObject());
  }

  /** 连接信息三行（上游 `onCreate` 里的 `statusInit` 文本）。 */
  static statusInitText(ssid: string, ip: string, route: string): ClientText {
    return ClientText.of('wifi_client_status_init', ssid, ip, route);
  }

  /** 连接失败 → 2 秒后重试（上游 `connectSocket` 的 catch 分支）。 */
  public static readonly CONNECT_FAILED_RES: string = 'wifi_client_connect_failed';
  public static readonly CONNECT_RETRY_RES: string = 'wifi_client_connect_retry';
  /** 重试间隔（上游 `Thread.sleep(2000)`）。 */
  public static readonly RETRY_DELAY_MS: number = 2000;

  /** 清状态（上游 `onDestroy`：注销 chunk 接收器、关连接、关 executor）。 */
  public destroy(): void {
    this.dirnameByGid.clear();
    this.galleryDirCache.clear();
    this.dirFilesCompleted = 0;
  }
}
