/*
 * 对位上游：app/src/main/java/com/hippo/ehviewer/gallery/A7ZipArchive.java
 *
 * 上游状态：`@Deprecated`（上游注释原文自己写了"此类在64位应用中会抛出异常，正在寻求替代方案"），
 *          依赖 Maven 依赖 `com.github.xiaojieonly.a7zip_XJ:extract-lite:1.0.3` 的
 *          InArchive / PropID / PropType / SeekableInputStream / ArchiveException。
 *
 * 本 port 的裁决（DEVIATIONS **D-004**：7z 走 NDK）：
 *   鸿蒙没有 7z 库，方案 §4 定的是「NDK 编译 LZMA SDK / 7-Zip C 源 + NAPI 封装，与 cpp/ 同构建体系」。
 *   因此本文件**只定义接口契约**（Lead 指定的形状：open / entryCount / entryName / openEntry / close），
 *   实现体等 native-image 的 `cpp/7z` 落地后由 NAPI 填入。**不做假实现**：
 *   - `A7ZipArchive.create()` 在 bridge 未注入时抛 `TODO(D-004)` 错误；
 *   - 解压条目同样抛错，不会"静默返回空列表"导致阅读器显示 0 页、让人误以为是空包。
 *
 * 为什么 PropId 用字符串而不是数字（重要，给 native-image 的交接）：
 *   上游用的 PropID 常量来自外部 Java 包装库（不在仓库里），其数值映射无法从本仓库验证。
 *   编造数值会让 NAPI 侧对错 7-Zip 的 kpid* 枚举，后果是「条目被误判为加密/目录」这类难查的
 *   静默错误。所以这里用语义键（'ENCRYPTED' / 'IS_DIR' / 'IS_VOLUME' / 'SOLID'），
 *   由 NAPI 侧映射到 7-Zip C++ 的枚举。已知正确值写在各常量注释里（7zTypes.h），
 *   `IS_VOLUME` 的具体枚举待 native-image 按所用 7-Zip 版本核对 —— 见 TODO(D-004)。
 */

import { UniRandomAccessFile } from '../../unifile/UniRandomAccessFile';
import { OutputStream } from '../../unifile/Contracts';
import { GalleryProvider2 } from './GalleryProvider2';

const TAG: string = 'A7ZipArchive';

/**
 * 对位上游 a7zip 库的 PropID（用语义键，见文件头说明）。
 * 参考 7-Zip `CPP/7zip/IDecl.h` / `7zTypes.h` 的 kpid* 枚举：
 *   kpidIsDir = 6、kpidSolid = 13、kpidEncrypted = 15。
 *   kpidIsVolume 在部分版本不存在（有 kpidVolumeIndex），必须按实际链接的 7-Zip 版本核对 → TODO(D-004)。
 */
export class PropId {
  static readonly ENCRYPTED: string = 'ENCRYPTED';
  static readonly IS_DIR: string = 'IS_DIR';
  static readonly IS_VOLUME: string = 'IS_VOLUME';
  static readonly SOLID: string = 'SOLID';
}

/** 对位上游 a7zip 库的 PropType（这里只需要「是不是布尔属性」）。 */
export class PropType {
  static readonly NONE: string = 'NONE';
  static readonly BOOL: string = 'BOOL';
  static readonly STRING: string = 'STRING';
  static readonly OTHER: string = 'OTHER';
}

/**
 * 7z 解压后端契约（由 native-image 模块的 `cpp/7z` + NAPI 实现）。
 * 这是 D-004 的正式交接面：16 个上游 JNI 语义收敛成下面 8 个方法。
 */
export interface A7ZipBridge {
  /** 打开归档，返回 native 句柄（0 表示失败）。 */
  open(file: UniRandomAccessFile): number;

  /** 关闭归档并释放句柄。 */
  close(handle: number): void;

  /** 条目数量。 */
  entryCount(handle: number): number;

  /** 第 index 个条目的路径（上游 getEntryPath）。 */
  entryPath(handle: number, index: number): string;

  /** 条目布尔属性（上游 getEntryBooleanProperty）。 */
  entryBoolean(handle: number, index: number, prop: string): boolean;

  /** 归档属性类型（上游 getArchivePropertyType），返回 PropType 的字符串键。 */
  archivePropertyType(handle: number, prop: string): string;

  /** 归档布尔属性（上游 getArchiveBooleanProperty）。 */
  archiveBoolean(handle: number, prop: string): boolean;

  /** 解压第 index 个条目到 sink（上游 extractEntry + OutputStreamSequentialOutStream）。 */
  extractEntry(handle: number, index: number, sink: OutputStream): void;
}

/**
 * 对位 `com.hippo.ehviewer.gallery.A7ZipArchive`。
 * 上游方法名：create / close / getArchiveEntries；本 port 按 Lead 指定补齐
 * entryCount / entryName / openEntry 三个便捷入口（与 getArchiveEntries 等价，便于阅读器逐页拉流）。
 */
export class A7ZipArchive {
  /**
   * 支持的图片扩展名 —— 直接引用 `GalleryProvider2.SUPPORT_IMAGE_EXTENSIONS`
   * （上游同样从这里取；此前本地留过一份副本，GalleryProvider2 落地后已收回，避免两处漂移）。
   */
  static readonly SUPPORT_IMAGE_EXTENSIONS: string[] = GalleryProvider2.SUPPORT_IMAGE_EXTENSIONS;

  private static bridge: A7ZipBridge | null = null;

  private readonly handle: number;
  private readonly file: UniRandomAccessFile;
  private readonly paths: string[];
  private readonly rawIndices: number[];

  private constructor(handle: number, file: UniRandomAccessFile, paths: string[], rawIndices: number[]) {
    this.handle = handle;
    this.file = file;
    this.paths = paths;
    this.rawIndices = rawIndices;
  }

  /** 由 native-image 在启动时注入（`cpp/7z` 的 NAPI 实现）。 */
  static setBridge(bridge: A7ZipBridge | null): void {
    A7ZipArchive.bridge = bridge;
  }

  private static requireBridge(): A7ZipBridge {
    const b: A7ZipBridge | null = A7ZipArchive.bridge;
    if (b === null) {
      throw new Error(
        `[${TAG}] TODO(D-004): 7z 解压后端未接入（A7ZipArchive.setBridge 未调用）。` +
        '方案 §4 定的是 NDK 编译 LZMA/7-Zip C 源 + NAPI（cpp/7z），由 native-image 模块提供。');
    }
    return b;
  }

  /** 对位上游 `isSupportedFilename(name)`：按小写后缀匹配图片扩展名。 */
  private static isSupportedFilename(name: string): boolean {
    const lower: string = name.toLowerCase();
    for (const ext of A7ZipArchive.SUPPORT_IMAGE_EXTENSIONS) {
      if (lower.endsWith(ext)) {
        return true;
      }
    }
    return false;
  }

  /**
   * 对位上游 `create(UniRandomAccessFile)`。
   * 拒绝加密 / 固实(solid) / 分卷归档（上游同样的三条判断 + ArchiveException("Unsupported archive")）。
   */
  static create(file: UniRandomAccessFile): A7ZipArchive {
    const bridge: A7ZipBridge = A7ZipArchive.requireBridge();
    const handle: number = bridge.open(file);
    if (handle === 0) {
      throw new Error('ArchiveException: failed to open archive');
    }
    // 归档级拒绝条件（逐条对位上游）
    const encType: string = bridge.archivePropertyType(handle, PropId.ENCRYPTED);
    const solidType: string = bridge.archivePropertyType(handle, PropId.SOLID);
    const volumeType: string = bridge.archivePropertyType(handle, PropId.IS_VOLUME);
    const unsupported: boolean =
      (encType === PropType.BOOL && bridge.archiveBoolean(handle, PropId.ENCRYPTED)) ||
        (solidType === PropType.BOOL && bridge.archiveBoolean(handle, PropId.SOLID)) ||
        (volumeType === PropType.BOOL && bridge.archiveBoolean(handle, PropId.IS_VOLUME));
    if (unsupported) {
      bridge.close(handle);
      throw new Error('ArchiveException: Unsupported archive');
    }
    // 收集可读条目路径（跳过加密/目录/分卷/固实 + 非图片后缀）
    const paths: string[] = [];
    const rawIndices: number[] = [];
    const n: number = bridge.entryCount(handle);
    for (let i = 0; i < n; i++) {
      if (!bridge.entryBoolean(handle, i, PropId.ENCRYPTED) &&
        !bridge.entryBoolean(handle, i, PropId.IS_DIR) &&
        !bridge.entryBoolean(handle, i, PropId.IS_VOLUME) &&
        !bridge.entryBoolean(handle, i, PropId.SOLID)) {
        const path: string = bridge.entryPath(handle, i);
        if (A7ZipArchive.isSupportedFilename(path)) {
          paths.push(path);
          rawIndices.push(i);
        }
      }
    }
    return new A7ZipArchive(handle, file, paths, rawIndices);
  }

  /** 可直接阅读的条目数（= 上游 getArchiveEntries().size()）。 */
  entryCount(): number {
    return this.paths.length;
  }

  /** 第 index 个可读条目的路径（= 上游 getArchiveEntries().get(index).getPath()）。 */
  entryName(index: number): string {
    if (index < 0 || index >= this.paths.length) {
      throw new Error(`entry index out of range: ${index}/${this.paths.length}`);
    }
    return this.paths[index];
  }

  /** 解压第 index 个可读条目到 sink（= 上游 getArchiveEntries().get(index).extract(os)）。 */
  openEntry(index: number, sink: OutputStream): void {
    if (index < 0 || index >= this.paths.length) {
      throw new Error(`entry index out of range: ${index}/${this.paths.length}`);
    }
    A7ZipArchive.requireBridge().extractEntry(this.handle, this.rawIndices[index], sink);
  }

  /**
   * 对位上游 `getArchiveEntries()`（A7ZipArchive.java:67）—— **列出全部可读条目**。
   *
   * 上游返回 `List<A7ZipArchiveEntry>`；本 port 用 `entryCount()` + `entryName(i)` 逐个包成
   * `A7ZipArchiveEntry`（该类持有 archive + index + path，`extract(sink)` 走 `openEntry`）。
   *
   * 为什么要它：上游有调用点按「**条目列表**」遍历（例如归档导入的顺序规划
   * `planImportOrder(entries, true)`）。只有 `entryCount`/`entryName` 时调用方得自己拼循环，
   * 而拼出来的列表语义容易与上游不一致 —— 上游返回的是**已经过滤掉**加密/目录/分卷/固实
   * 以及非图片后缀**之后**的可读条目。
   *
   * 顺序 = `create()` 收集 `paths` 的顺序（归档内顺序），与上游一致。
   */
  getArchiveEntries(): A7ZipArchiveEntry[] {
    const entries: A7ZipArchiveEntry[] = [];
    const n: number = this.entryCount();
    for (let i = 0; i < n; i++) {
      entries.push(new A7ZipArchiveEntry(this, i, this.entryName(i)));
    }
    return entries;
  }

  /** 对位上游 `close()`：关闭归档（幂等由 bridge 保证）。 */
  close(): void {
    try {
      A7ZipArchive.requireBridge().close(this.handle);
    } catch (e) {
      // bridge 未注入时 close 不该再抛，交给上层
    }
  }

  /** 底层随机访问句柄（上游把 UniRandomAccessFile 藏在 InArchive 里，这里显式持有便于排查）。 */
  getRandomAccessFile(): UniRandomAccessFile {
    return this.file;
  }
}

/**
 * 对位上游 `A7ZipArchive.A7ZipArchiveEntry`（内部类）。
 * 本 port 把「entry」收敛成 archive + index 两个字段，避免 native 句柄在多对象间重复持有。
 */
export class A7ZipArchiveEntry {
  private readonly archive: A7ZipArchive;
  private readonly index: number;
  private readonly path: string;

  constructor(archive: A7ZipArchive, index: number, path: string) {
    this.archive = archive;
    this.index = index;
    this.path = path;
  }

  getPath(): string {
    return this.path;
  }

  /** 对位上游 `extract(OutputStream)`。 */
  extract(sink: OutputStream): void {
    this.archive.openEntry(this.index, sink);
  }
}
