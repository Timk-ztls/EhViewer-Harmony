/*
 * Licensed under the Apache License, Version 2.0 (the "License");
 *
 * ── HarmonyOS 移植记录 ──────────────────────────────────────────────────────
 * 条目   : S0020   上游: com/hippo/content/FileProvider.java（757 行，AOSP 派生）
 * 目标   : harmony/entry/src/main/ets/hippo/content/FileProvider.ets
 *
 * 【**部分移植**：文件 URI ↔ 路径映射 + 越界检查，其余是 Android IPC 机制】
 *
 * 移植的（可移植、且有安全语义）：
 *   · `SimplePathStrategy.addRoot` —— 注册"名字 → 根目录"，要求**名字非空**、根路径**规范化**
 *   · `getUriForFile` —— **找最长匹配的根**（most-specific root），再算相对路径
 *   · `getFileForUri` —— 解析回路径，规范化后**必须仍在根下**，否则抛 `SecurityException`
 *     （`Resolved path jumped beyond configured root`）—— **这是路径穿越防护，必须保留**
 *   · `modeToMode` —— "r/w/wt/wa/rw/rwt" → 位标志（`ParcelFileDescriptor.MODE_*` 的值镜像）
 *   · `buildPath` / `copyOf` —— 路径拼接与数组扩容（纯工具）
 *   · 六种 XML 标签名常量（`root-path`/`files-path`/`cache-path`/`external-path`/
 *     `external-files-path`/`external-cache-path`）
 *
 * 不移植的（Android 专有）：
 *   · `ContentProvider` 生命周期（`onCreate`/`attachInfo`）→ 鸿蒙用 `@ohos.app.ability.*`
 *   · `query/insert/update/delete/getType` → 鸿蒙无 ContentProvider 契约
 *   · `openFile` → `ParcelFileDescriptor` 是 Binder 传递的 fd 封装；鸿蒙用
 *     `@ohos.file.fs` 直接给路径/fd
 *   · `Uri` 类型 → 本文件用 `string` 表示（`content://authority/tag/encodedPath`）
 *   · `getPathStrategy` 的 `sCache` 静态缓存 → 保留（进程内缓存语义相同）
 *
 * 平台差异：
 *  1. `File.getCanonicalPath()` → 注入 `canonicalize(path)`（鸿蒙用 `fileIo` 的 realpath 语义；
 *     **必须真实解析 `..` 与符号链接**，否则路径穿越检查形同虚设）。
 *  2. `Uri.encode/decode` → `encodeURIComponent` / `decodeURIComponent`
 *     （差异：Java 的 `Uri.encode(s, "/")` 保留 `/`，等价于 encodeURIComponent 后再把 `%2F` 还原）。
 *  3. `TextUtils.isEmpty(name)` → `name === ''`（**非空校验照搬**：空名字会让 URI 变成 `content://a//path`）
 */

/** 上游 `ParcelFileDescriptor.MODE_*` 的值（Android 常量镜像） */
export class FileMode {
  static readonly MODE_READ_ONLY: number = 0x10000000;
  static readonly MODE_WRITE_ONLY: number = 0x20000000;
  static readonly MODE_READ_WRITE: number = 0x30000000;
  static readonly MODE_CREATE: number = 0x08000000;
  static readonly MODE_TRUNCATE: number = 0x04000000;
  static readonly MODE_APPEND: number = 0x80000000 | 0; // Java int 里是负数，这里用无符号值
}

/** 一条 `<tag> → 根目录` 映射 */
export class RootEntry {
  name: string;
  root: string;

  constructor(name: string, root: string) {
    this.name = name;
    this.root = root;
  }
}

export class FileProvider {

  // 上游六个 XML 标签名（映射文件里的元素名）
  static readonly TAG_ROOT_PATH: string = 'root-path';
  static readonly TAG_FILES_PATH: string = 'files-path';
  static readonly TAG_CACHE_PATH: string = 'cache-path';
  static readonly TAG_EXTERNAL: string = 'external-path';
  static readonly TAG_EXTERNAL_FILES: string = 'external-files-path';
  static readonly TAG_EXTERNAL_CACHE: string = 'external-cache-path';
  static readonly ATTR_NAME: string = 'name';
  static readonly ATTR_PATH: string = 'path';
  /** 上游 `DEVICE_ROOT = new File("/")` */
  static readonly DEVICE_ROOT: string = '/';

  private authority: string;
  private roots: Map<string, string> = new Map<string, string>();
  private canonicalize: (path: string) => string;

  /**
   * @param canonicalize 注入"规范化绝对路径"（对应 `File.getCanonicalPath()`）。
   *                     必须真实解析 `..` 与符号链接，否则 `getFileForUri` 的越界检查无效。
   */
  constructor(authority: string, canonicalize: (path: string) => string) {
    this.authority = authority;
    this.canonicalize = canonicalize;
  }

  /** 对应上游 `SimplePathStrategy.addRoot(name, root)` */
  addRoot(name: string, root: string): void {
    if (name === null || name === '') {
      throw new Error('Name must not be empty');
    }
    // Resolve to canonical path to keep path checking fast
    const canonical: string = this.canonicalize(root);
    this.roots.set(name, canonical);
  }

  /** 当前已注册的根（测试与诊断用；上游是 private 字段） */
  getRoots(): RootEntry[] {
    const list: RootEntry[] = [];
    this.roots.forEach((v: string, k: string) => {
      list.push(new RootEntry(k, v));
    });
    return list;
  }

  /**
   * 对应上游 `getUriForFile(file)`：**找最长匹配根**，再算相对路径并拼成
   * `content://<authority>/<encodedName>/<encodedPath>`。
   */
  getUriForFile(file: string): string {
    const path: string = this.canonicalize(file);

    // Find the most-specific root path
    let bestName: string | null = null;
    let bestRoot: string | null = null;
    this.roots.forEach((root: string, name: string) => {
      if (path.startsWith(root) && (bestRoot === null || root.length > bestRoot.length)) {
        bestName = name;
        bestRoot = root;
      }
    });

    if (bestRoot === null || bestName === null) {
      throw new Error('Failed to find configured root that contains ' + path);
    }

    // Start at first char of path under root
    const rootPath: string = bestRoot;
    let rel: string;
    if (rootPath.endsWith('/')) {
      rel = path.substring(rootPath.length);
    } else {
      rel = path.substring(rootPath.length + 1);
    }

    // Encode the tag and path separately（上游 Uri.encode(path, "/") 保留 '/'）
    const encoded: string = encodeURIComponent(bestName) + '/'
      + FileProvider.encodeKeepSlash(rel);
    return 'content://' + this.authority + '/' + encoded;
  }

  /**
   * 对应上游 `getFileForUri(uri)`：解析回路径，规范化后**必须仍在根下**。
   * 越界 → 抛 `SecurityException` 同义错误（**路径穿越防护**）。
   */
  getFileForUri(uri: string): string {
    const prefix: string = 'content://' + this.authority + '/';
    if (!uri.startsWith(prefix)) {
      throw new Error('Unable to find configured root for ' + uri);
    }
    const path: string = uri.substring(prefix.length);

    const splitIndex: number = path.indexOf('/', 1);
    if (splitIndex < 0) {
      throw new Error('Unable to find configured root for ' + uri);
    }
    const tag: string = decodeURIComponent(path.substring(0, splitIndex));
    const relPath: string = decodeURIComponent(path.substring(splitIndex + 1));

    const root: string | undefined = this.roots.get(tag);
    if (root === undefined) {
      throw new Error('Unable to find configured root for ' + uri);
    }

    const file: string = this.canonicalize(FileProvider.buildPath(root, relPath));
    if (!file.startsWith(root)) {
      throw new Error('Resolved path jumped beyond configured root');
    }
    return file;
  }

  /** 对应上游 `modeToMode(mode)`（取自 ContentResolver） */
  static modeToMode(mode: string): number {
    if (mode === 'r') {
      return FileMode.MODE_READ_ONLY;
    } else if (mode === 'w' || mode === 'wt') {
      return FileMode.MODE_WRITE_ONLY | FileMode.MODE_CREATE | FileMode.MODE_TRUNCATE;
    } else if (mode === 'wa') {
      return FileMode.MODE_WRITE_ONLY | FileMode.MODE_CREATE | FileMode.MODE_APPEND;
    } else if (mode === 'rw') {
      return FileMode.MODE_READ_WRITE | FileMode.MODE_CREATE;
    } else if (mode === 'rwt') {
      return FileMode.MODE_READ_WRITE | FileMode.MODE_CREATE | FileMode.MODE_TRUNCATE;
    }
    throw new Error('Invalid mode: ' + mode);
  }

  /** 对应上游 `buildPath(base, segments...)`：base + 各段（末尾带 '/' 时不再补） */
  static buildPath(base: string, ...segments: string[]): string {
    let path: string = base;
    for (let i = 0; i < segments.length; i++) {
      const seg: string = segments[i];
      if (path.endsWith('/')) {
        path += seg;
      } else {
        path += '/' + seg;
      }
    }
    return path;
  }

  /** `encodeURIComponent` 后把 `%2F` 还原成 `/`（等价 Java `Uri.encode(s, "/")`） */
  private static encodeKeepSlash(s: string): string {
    return encodeURIComponent(s).replace(/%2F/g, '/');
  }
}