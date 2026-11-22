/*
 * Copyright 2016 Hippo Seven
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

import { DirAck, DirManifest, FileChunk, FileMeta, GalleryDirEntry } from './MigrationTypes';

/**
 * 1:1 对位 upstream: app/src/main/java/com/hippo/ehviewer/client/wifi/WiFiDownloadMigrationHelper.java
 * （inventory S0116，326 行）
 *
 * 干「把下载目录从旧设备搬到新设备」的活：扫描 → 生成清单 → 对端回 ACK 要哪些文件 → 分块传输 → 校验 MD5。
 *
 * 本层把**纯逻辑**与**文件系统/摘要**分离：
 *   - 纯逻辑（可测、已在下面实现）：`parseGidFromDirname`、`filterFilesNeeded`、`bytesToHex`、
 *     `verifyFileMd5`、`FileWriteState`、`FILE_CHUNK_SIZE`
 *   - 文件系统与摘要是平台能力（上游 `UniFile` + `MessageDigest`）→ 抽成
 *     `MigrationFileSystem` / `Md5Provider` 注入（storage-db 的 unifile 与 @ohos.security.cryptoFramework 接线）
 *
 * 照搬的关键行为：
 *   - `parseGidFromDirname`：目录名形如 `1234567-title`，**取第一个 '-' 之前**；`-` 在首位或无 `-` → -1
 *   - `filterFilesNeeded`：本地缺失/不是文件 → 需要；MD5 算不出或与远端不一致（**忽略大小写**）→ 需要
 *   - `verifyFileMd5`：同样忽略大小写比较
 *   - 分块大小 256 KiB
 */
export class WiFiDownloadMigrationHelper {
  static readonly FILE_CHUNK_SIZE: number = 256 * 1024;

  /** 对齐 `parseGidFromDirname(String)`。 */
  static parseGidFromDirname(dirname: string): number {
    const dash: number = dirname.indexOf('-');
    if (dash <= 0) {
      return -1;
    }
    const v: number = Number.parseInt(dirname.substring(0, dash), 10);
    return Number.isNaN(v) ? -1 : v;
  }

  /**
   * 对齐 `filterFilesNeeded(UniFile galleryDir, List<FileMeta> remoteFiles)`：
   * 返回「本地需要（重新）下载」的文件名列表。
   */
  static filterFilesNeeded(fs: MigrationFileSystem, galleryDir: string,
    remoteFiles: FileMeta[]): string[] {
    const needed: string[] = [];
    for (let i = 0; i < remoteFiles.length; i++) {
      const meta: FileMeta = remoteFiles[i];
      const local: string | null = fs.resolveFileInGallery(galleryDir, meta.name);
      if (local === null || !fs.isFile(local)) {
        needed.push(meta.name);
        continue;
      }
      const localMd5: string | null = fs.computeMd5Hex(local);
      if (localMd5 === null || localMd5.toLowerCase() !== meta.md5.toLowerCase()) {
        needed.push(meta.name);
      }
    }
    return needed;
  }

  /** 对齐 `verifyFileMd5(UniFile, String)`：忽略大小写比较。 */
  static verifyFileMd5(fs: MigrationFileSystem, file: string, expectedMd5: string): boolean {
    const actual: string | null = fs.computeMd5Hex(file);
    if (actual === null) {
      return false;
    }
    return actual.toLowerCase() === expectedMd5.toLowerCase();
  }

  /** 对齐 `bytesToHex(byte[])`：小写、两位、无分隔。 */
  static bytesToHex(bytes: Uint8Array): string {
    let out: string = '';
    for (let i = 0; i < bytes.length; i++) {
      out += bytes[i].toString(16).padStart(2, '0');
    }
    return out;
  }

  /** 对齐 `scanGalleryDir`：递归收集，`prefix` 是相对路径前缀（子目录带 '/'）。 */
  static scanGalleryDir(fs: MigrationFileSystem, dir: string): FileMeta[] {
    const list: FileMeta[] = [];
    WiFiDownloadMigrationHelper.collectFiles(fs, dir, '', list);
    return list;
  }

  private static collectFiles(fs: MigrationFileSystem, dir: string, prefix: string,
    out: FileMeta[]): void {
    // 约定：fs.list(dir) 返回**条目名**（与 UniFile.listFiles + getName 一致），不是完整路径
    const names: string[] = fs.list(dir);
    for (let i = 0; i < names.length; i++) {
      const name: string = names[i];
      const full: string = WiFiDownloadMigrationHelper.join(dir, name);
      if (fs.isDirectory(full)) {
        WiFiDownloadMigrationHelper.collectFiles(fs, full, prefix + name + '/', out);
      } else if (fs.isFile(full)) {
        const meta: FileMeta = new FileMeta();
        meta.name = prefix + name;
        const md5: string | null = fs.computeMd5Hex(full);
        meta.md5 = md5 === null ? '' : md5;
        meta.size = fs.size(full);
        out.push(meta);
      }
    }
  }

  /** 路径拼接（对应 UniFile.subFile 的单级语义）。 */
  private static join(dir: string, name: string): string {
    return dir.length > 0 && dir.charAt(dir.length - 1) === '/' ? dir + name : dir + '/' + name;
  }

  /** 对齐 `scanGalleryDirs()`：只保留 gid 可解析的目录。 */
  static scanGalleryDirs(fs: MigrationFileSystem, root: string): GalleryDirEntry[] {
    const out: GalleryDirEntry[] = [];
    const names: string[] = fs.list(root);
    for (let i = 0; i < names.length; i++) {
      const name: string = names[i];
      if (!fs.isDirectory(WiFiDownloadMigrationHelper.join(root, name))) {
        continue;
      }
      // 上游传的是**目录名**（UniFile.getName()），不是完整路径
      const gid: number = WiFiDownloadMigrationHelper.parseGidFromDirname(name);
      if (gid < 0) {
        continue;
      }
      const entry: GalleryDirEntry = new GalleryDirEntry();
      entry.gid = gid;
      entry.dirname = name;
      out.push(entry);
    }
    return out;
  }
}

/**
 * 文件系统抽象（对应上游的 `UniFile`）。
 * 生产实现由 storage-db 的 unifile 提供；测试用内存实现。
 */
export interface MigrationFileSystem {
  /** 返回**条目名**列表（不是完整路径），对应 UniFile.listFiles() + getName()。 */
  list(dir: string): string[];

  isDirectory(path: string): boolean;

  isFile(path: string): boolean;

  size(path: string): number;

  computeMd5Hex(path: string): string | null;

  /** 相对路径解析（含子目录时逐级下钻）；不存在返回 null。 */
  resolveFileInGallery(galleryDir: string, relPath: string): string | null;
}

/** 对齐 `FileWriteState`：按文件名累计已写字节。 */
export class FileWriteState {
  private _map: Map<string, number> = new Map<string, number>();

  addWritten(name: string, bytes: number): void {
    const old: number | undefined = this._map.get(name);
    this._map.set(name, (old === undefined ? 0 : old) + bytes);
  }

  clear(name: string): void {
    this._map.delete(name);
  }

  getWritten(name: string): number {
    const v: number | undefined = this._map.get(name);
    return v === undefined ? 0 : v;
  }
}

/** 传输载荷类型别名（与 codec 的返回类型一致，便于调用方阅读）。 */
export type MigrationPayload = DirManifest | DirAck | FileChunk;
