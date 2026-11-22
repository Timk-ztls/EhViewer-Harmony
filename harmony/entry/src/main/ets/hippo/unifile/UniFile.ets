/*
 * 对位上游：app/src/main/java/com/hippo/unifile/UniFile.java
 *                     + RawFile.java / SingleDocumentFile.java / TreeDocumentFile.java / MediaFile.java
 *
 * ── 为什么五个类都在这个文件里（重要，MR 有同文说明）─────────────────────────────
 * 上游 Java 里 UniFile 是抽象基类，RawFile/TreeDocumentFile/... 在各自文件里 extends UniFile，
 * 而 UniFile 的静态工厂（fromFile/fromTreeUri/...）又反过来 new 这些子类 —— 形成
 * 「基类模块 ←→ 子类模块」的双向 import。JVM 用惰性链接可以容忍这种环；ArkTS（ESM 语义）不行：
 * 谁先被 import，谁在求值时就会读到对方尚未初始化的类绑定（TDZ：Cannot access 'UniFile'
 * before initialization），class extends 直接崩。
 *
 * 三选一后取「实现体集中在本文件」：
 *   A) 基类放 Contracts 之类的下层文件、本文件只做转出口 → 类名对位失效，TypeScript 类型面错位；
 *   B) 用 ArkTS 的 `import lazy`（API 12+）打断环 → 依赖新语法，且本机整包构建不可用，无法验证；
 *   C) 实现体集中在本文件（当前方案）→ 100% 消除环、不引入未验证语法；
 *      四个子类文件保留为「结构对位转出口」，import { RawFile } from '.../unifile/RawFile' 的
 *      调用点形状与上游完全一致。
 * 选 C 的代价：本文件约 900 行（上游五个文件合计 ~1200 行）。行为零差异，见下列逐方法注释。
 *
 * ── 方法名映射（ArkTS 不支持方法重载，方案 §5-⑦ 明确要求重命名）───────────────
 *   openOutputStream()            → openOutputStream()
 *   openOutputStream(boolean)     → openOutputStreamAppend(append)
 *   listFiles()                   → listFiles()
 *   listFiles(FilenameFilter)     → listFilesFiltered(filter)
 *   fromFile(File)                → fromFile(path: string)
 *   fromSingleUri(Context, Uri)   → fromSingleUri(uri: string)
 *   fromTreeUri(Context, Uri)     → fromTreeUri(uri: string)
 *   fromMediaUri(Context, Uri)    → fromMediaUri(uri: string)
 *   fromUri(Context, Uri)         → fromUri(uri: string)
 *   isDocumentUri(Context, Uri)   → isDocumentUri(uri: string)
 */

import fs from '@ohos.file.fs';
import { Contracts, InputStream, OutputStream, MimeType } from './Contracts';
import { Utils } from './Utils';
import { FilenameFilter } from './FilenameFilter';
import { UriHandler } from './UriHandler';
import { UniRandomAccessFile } from './UniRandomAccessFile';
import { RawRandomAccessFile } from './RawRandomAccessFile';
import { FileDescriptorRandomAccessFile } from './FileDescriptorRandomAccessFile';
import { DocumentsContractApi19 } from './DocumentsContractApi19';
import { DocumentsContractApi21 } from './DocumentsContractApi21';
import { UriOutputStream } from './UriOutputStream';
import { MediaContract } from './MediaContract';

const TAG: string = 'UniFile';

/**
 * 对位 com.hippo.unifile.UniFile：文件（File）与文档（Document/URI）的统一抽象。
 * 保留上游全部公开 API 的形状（方法名/语义/返回值约定），仅重载按上文映射重命名。
 */
export abstract class UniFile {
  private static sUriHandlerArray: UriHandler[] | null = null;

  private readonly mParent: UniFile | null;

  constructor(parent: UniFile | null) {
    this.mParent = parent;
  }

  // ------------------------------------------------------------------ 静态工厂

  /** 对位 UniFile.addUriHandler。 */
  static addUriHandler(handler: UriHandler): void {
    if (UniFile.sUriHandlerArray === null) {
      UniFile.sUriHandlerArray = [];
    }
    UniFile.sUriHandlerArray.push(handler);
  }

  /** 对位 UniFile.removeUriHandler。 */
  static removeUriHandler(handler: UriHandler): void {
    const arr: UriHandler[] | null = UniFile.sUriHandlerArray;
    if (arr === null) {
      return;
    }
    const idx: number = arr.indexOf(handler);
    if (idx >= 0) {
      arr.splice(idx, 1);
    }
  }

  /**
   * 对位 UniFile.fromFile(File)：包装普通文件。
   * 鸿蒙侧没有 java.io.File，入参改为绝对路径（沙箱路径或用户域路径）。
   */
  static fromFile(path: string | null | undefined): UniFile | null {
    if (path === null || path === undefined || path.length === 0) {
      return null;
    }
    return new RawFile(null, path);
  }

  /** 对位 UniFile.fromSingleUri(context, singleUri)：包装单个文档（picker 选中的单个文件）。 */
  static fromSingleUri(uri: string | null | undefined): UniFile | null {
    if (uri === null || uri === undefined || uri.length === 0) {
      return null;
    }
    return new SingleDocumentFile(null, uri);
  }

  /** 对位 UniFile.fromTreeUri(context, treeUri)：包装用户授权的目录树。 */
  static fromTreeUri(uri: string | null | undefined): UniFile | null {
    if (uri === null || uri === undefined || uri.length === 0) {
      return null;
    }
    return new TreeDocumentFile(null, DocumentsContractApi21.prepareTreeUri(uri), '');
  }

  /** 对位 UniFile.fromMediaUri(context, mediaUri)：包装媒体库 URI。 */
  static fromMediaUri(uri: string | null | undefined): UniFile | null {
    if (uri === null || uri === undefined || uri.length === 0) {
      return null;
    }
    return new MediaFile(uri);
  }

  /**
   * 对位 UniFile.fromUri(context, uri)：先问自定义 handler，再按 scheme 分派。
   * 鸿蒙只有 file:// 一种 scheme，分派规则简化为「目录 → Tree，文件 → Single，媒体 → Media」。
   */
  static fromUri(uri: string | null | undefined): UniFile | null {
    if (uri === null || uri === undefined || uri.length === 0) {
      return null;
    }

    // 1) 自定义 handler（扩展点，与上游顺序一致）
    const handlers: UriHandler[] | null = UniFile.sUriHandlerArray;
    if (handlers !== null) {
      for (const handler of handlers) {
        const file: UniFile | null = handler.fromUri(uri);
        if (file !== null) {
          return file;
        }
      }
    }

    // 2) 内建分派：与上游 UniFile.fromUri 一致，file:// 本地沙箱/路径走 RawFile，
    //    docs 走 TreeDocumentFile / SingleDocumentFile，media 走 MediaFile。
    if (UniFile.isFileUri(uri)) {
      return UniFile.fromFile(Contracts.toPath(uri));
    }
    if (UniFile.isDocumentUri(uri)) {
      if (UniFile.isTreeUri(uri)) {
        return UniFile.fromTreeUri(uri);
      }
      return UniFile.fromSingleUri(uri);
    }
    if (MediaContract.isMediaTarget(uri)) {
      return UniFile.fromMediaUri(uri);
    }
    return null;
  }

  /** 对位 UniFile.isFileUri：file:// 本地沙箱/路径 URI（排除 docs / media authority）。 */
  static isFileUri(uri: string | null | undefined): boolean {
    if (uri === null || uri === undefined || !Contracts.isUri(uri)) {
      return false;
    }
    const auth: string | undefined = Contracts.authorityOf(uri);
    return auth !== 'docs' && auth !== 'media';
  }

  /** 对位 UniFile.isDocumentUri：DocumentViewPicker 用户文档域（file://docs/...）。 */
  static isDocumentUri(uri: string | null | undefined): boolean {
    if (uri === null || uri === undefined) {
      return false;
    }
    return DocumentsContractApi19.isDocumentUri(uri);
  }

  /**
   * 对位 UniFile.isTreeUri：上游判定 scheme=content 且首段是 'tree'。
   * 鸿蒙等价判定：file://docs/... 且指向目录（picker 的目录授权就是这个形态）。
   */
  static isTreeUri(uri: string | null | undefined): boolean {
    if (uri === null || uri === undefined || !UniFile.isDocumentUri(uri)) {
      return false;
    }
    return DocumentsContractApi19.isDirectory(uri);
  }

  // ------------------------------------------------------------------ 通用

  /** 对位 UniFile.getParentFile：只在用户选定树内有效，越界不可得（上游注释保留）。 */
  getParentFile(): UniFile | null {
    return this.mParent;
  }

  // ------------------------------------------------------------------ 抽象 API

  /** 在自身目录下创建文件；失败返回 null。 */
  abstract createFile(displayName: string): UniFile | null;

  /** 在自身目录下创建目录；失败返回 null。 */
  abstract createDirectory(displayName: string): UniFile | null;

  /** 底层 URI（上游 @NonNull Uri）。 */
  abstract getUri(): string;

  /** 显示名；取不到返回 undefined（上游 @Nullable String）。 */
  abstract getName(): string | undefined;

  /** MIME；目录返回 undefined（上游 @Nullable String）。 */
  abstract getType(): string | undefined;

  abstract isDirectory(): boolean;

  abstract isFile(): boolean;

  /** 毫秒；取不到 -1。 */
  abstract lastModified(): number;

  /** 字节；取不到 -1。目录长度上游未定义。 */
  abstract length(): number;

  abstract canRead(): boolean;

  abstract canWrite(): boolean;

  /** mkdirs 语义：已是目录返回 true。 */
  abstract ensureDir(): boolean;

  /** 确保是文件（不存在则创建空文件）。 */
  abstract ensureFile(): boolean;

  /** 取子文件（不要求存在；不支持的实现返回 null）。 */
  abstract subFile(displayName: string): UniFile | null;

  /** 删除（不抛异常，调用方看返回值）。 */
  abstract delete(): boolean;

  abstract exists(): boolean;

  /** 列目录；不是目录/失败返回 null。 */
  abstract listFiles(): UniFile[] | null;

  /** 带过滤的列目录（上游 listFiles(FilenameFilter)）。 */
  abstract listFilesFiltered(filter: FilenameFilter | null): UniFile[] | null;

  /** 按显示名找子项；找不到返回 null。 */
  abstract findFile(displayName: string): UniFile | null;

  /** 重命名；成功 true，且后续 getUri()/getName() 反映新名。 */
  abstract renameTo(displayName: string): boolean;

  /** 覆盖写输出流（上游 openOutputStream()）。 */
  abstract openOutputStream(): OutputStream;

  /** 追加/覆盖写输出流（上游 openOutputStream(boolean append)）。 */
  abstract openOutputStreamAppend(append: boolean): OutputStream;

  /** 读输入流。 */
  abstract openInputStream(): InputStream;

  /** 随机访问句柄，mode ∈ "r"/"rw"/"rws"/"rwd"。 */
  abstract createRandomAccessFile(mode: string): UniRandomAccessFile;
}

// ══════════════════════════════════════════════════════════════════════════
// 对位 RawFile.java：普通文件（沙箱路径 / 用户域绝对路径）
// ══════════════════════════════════════════════════════════════════════════

/** 对位 com.hippo.unifile.RawFile。 */
export class RawFile extends UniFile {
  private mPath: string;

  constructor(parent: UniFile | null, path: string) {
    super(parent);
    this.mPath = Contracts.normalize(path);
  }

  /** 当前绝对路径（等价上游 mFile.getPath()，子类外的调用点用于日志/调试）。 */
  getPath(): string {
    return this.mPath;
  }

  createFile(displayName: string): UniFile | null {
    const target: string = Contracts.childOf(this.mPath, displayName);
    if (Contracts.exists(target)) {
      if (DocumentsContractApi19.isFile(target)) {
        return new RawFile(this, target);
      }
      return null;
    }
    try {
      const file: fs.File = fs.openSync(target, fs.OpenMode.WRITE_ONLY | fs.OpenMode.CREATE);
      fs.closeSync(file);
      return new RawFile(this, target);
    } catch (e) {
      Utils.throwIfFatal(e);
      Utils.logW(TAG, `Failed to createFile ${displayName}: ${e}`);
      return null;
    }
  }

  createDirectory(displayName: string): UniFile | null {
    const target: string = Contracts.childOf(this.mPath, displayName);
    if (DocumentsContractApi19.isDirectory(target)) {
      return new RawFile(this, target);
    }
    try {
      fs.mkdirSync(target, true);
      return new RawFile(this, target);
    } catch (e) {
      Utils.throwIfFatal(e);
      Utils.logW(TAG, `Failed to createDirectory ${displayName}: ${e}`);
      return null;
    }
  }

  getUri(): string {
    return Contracts.toUri(this.mPath);
  }

  getName(): string | undefined {
    const name: string = Contracts.nameOf(this.mPath);
    return name.length > 0 ? name : undefined;
  }

  getType(): string | undefined {
    if (this.isDirectory()) {
      return undefined;
    }
    return Contracts.mimeFromName(Contracts.nameOf(this.mPath));
  }

  isDirectory(): boolean {
    return DocumentsContractApi19.isDirectory(this.mPath);
  }

  isFile(): boolean {
    return DocumentsContractApi19.isFile(this.mPath);
  }

  lastModified(): number {
    return DocumentsContractApi19.lastModified(this.mPath);
  }

  length(): number {
    return DocumentsContractApi19.lengthOf(this.mPath);
  }

  canRead(): boolean {
    return Contracts.canRead(this.mPath);
  }

  canWrite(): boolean {
    return Contracts.canWrite(this.mPath);
  }

  ensureDir(): boolean {
    if (this.isDirectory()) {
      return true;
    }
    try {
      fs.mkdirSync(this.mPath, true);
      return true;
    } catch (e) {
      Utils.throwIfFatal(e);
      return false;
    }
  }

  ensureFile(): boolean {
    if (Contracts.exists(this.mPath)) {
      return this.isFile();
    }
    try {
      const file: fs.File = fs.openSync(this.mPath, fs.OpenMode.WRITE_ONLY | fs.OpenMode.CREATE);
      fs.closeSync(file);
      return true;
    } catch (e) {
      Utils.throwIfFatal(e);
      return false;
    }
  }

  subFile(displayName: string): UniFile | null {
    return new RawFile(this, Contracts.childOf(this.mPath, displayName));
  }

  delete(): boolean {
    // 上游：先递归清空内容，再删自身
    return Contracts.deleteRecursively(this.mPath);
  }

  exists(): boolean {
    return Contracts.exists(this.mPath);
  }

  listFiles(): UniFile[] | null {
    const names: string[] | undefined = Contracts.listNames(this.mPath);
    if (names === undefined) {
      return null;
    }
    const results: UniFile[] = [];
    for (const name of names) {
      results.push(new RawFile(this, Contracts.childOf(this.mPath, name)));
    }
    return results;
  }

  listFilesFiltered(filter: FilenameFilter | null): UniFile[] | null {
    if (filter === null) {
      return this.listFiles();
    }
    const names: string[] | undefined = Contracts.listNames(this.mPath);
    if (names === undefined) {
      return null;
    }
    const results: UniFile[] = [];
    for (const name of names) {
      if (filter.accept(this, name)) {
        results.push(new RawFile(this, Contracts.childOf(this.mPath, name)));
      }
    }
    return results;
  }

  findFile(displayName: string): UniFile | null {
    const child: string = Contracts.childOf(this.mPath, displayName);
    return Contracts.exists(child) ? new RawFile(this, child) : null;
  }

  renameTo(displayName: string): boolean {
    const parent: string | undefined = Contracts.parentOf(this.mPath);
    if (parent === undefined) {
      return false;
    }
    const target: string = Contracts.childOf(parent, displayName);
    try {
      fs.renameSync(this.mPath, target);
      this.mPath = target;
      return true;
    } catch (e) {
      Utils.throwIfFatal(e);
      return false;
    }
  }

  openOutputStream(): OutputStream {
    return Contracts.openOutputStream(this.mPath);
  }

  openOutputStreamAppend(append: boolean): OutputStream {
    return Contracts.openOutputStreamAppend(this.mPath, append);
  }

  openInputStream(): InputStream {
    return Contracts.openInputStream(this.mPath);
  }

  createRandomAccessFile(mode: string): UniRandomAccessFile {
    return RawRandomAccessFile.open(this.mPath, mode);
  }
}

// ══════════════════════════════════════════════════════════════════════════
// 对位 SingleDocumentFile.java：单个文档（不可建子项）
// ══════════════════════════════════════════════════════════════════════════

/** 对位 com.hippo.unifile.SingleDocumentFile。 */
export class SingleDocumentFile extends UniFile {
  private readonly mUri: string;

  constructor(parent: UniFile | null, uri: string) {
    super(parent);
    this.mUri = uri;
  }

  createFile(displayName: string): UniFile | null {
    return null;
  }

  createDirectory(displayName: string): UniFile | null {
    return null;
  }

  getUri(): string {
    return this.mUri;
  }

  getName(): string | undefined {
    return DocumentsContractApi19.getName(this.mUri);
  }

  getType(): string | undefined {
    return DocumentsContractApi19.getType(this.mUri);
  }

  isDirectory(): boolean {
    return DocumentsContractApi19.isDirectory(this.mUri);
  }

  isFile(): boolean {
    return DocumentsContractApi19.isFile(this.mUri);
  }

  lastModified(): number {
    return DocumentsContractApi19.lastModified(this.mUri);
  }

  length(): number {
    return DocumentsContractApi19.lengthOf(this.mUri);
  }

  canRead(): boolean {
    return DocumentsContractApi19.canRead(this.mUri);
  }

  canWrite(): boolean {
    return DocumentsContractApi19.canWrite(this.mUri);
  }

  ensureDir(): boolean {
    return this.isDirectory();
  }

  ensureFile(): boolean {
    if (this.isFile()) {
      return true;
    }
    try {
      Utils.closeQuietly(this.openOutputStream());
      return true;
    } catch (e) {
      Utils.throwIfFatal(e);
      return false;
    }
  }

  subFile(displayName: string): UniFile | null {
    return null;
  }

  delete(): boolean {
    return DocumentsContractApi19.delete(this.mUri);
  }

  exists(): boolean {
    return DocumentsContractApi19.exists(this.mUri);
  }

  listFiles(): UniFile[] | null {
    return null;
  }

  listFilesFiltered(filter: FilenameFilter | null): UniFile[] | null {
    return null;
  }

  findFile(displayName: string): UniFile | null {
    return null;
  }

  renameTo(displayName: string): boolean {
    // 上游 SingleDocumentFile.renameTo 恒 false（单文档没有可命名的父树）
    return false;
  }

  openOutputStream(): OutputStream {
    return Contracts.openOutputStream(this.mUri);
  }

  openOutputStreamAppend(append: boolean): OutputStream {
    return Contracts.openOutputStreamAppend(this.mUri, append);
  }

  openInputStream(): InputStream {
    return Contracts.openInputStream(this.mUri);
  }

  createRandomAccessFile(mode: string): UniRandomAccessFile {
    if (mode === 'r') {
      return FileDescriptorRandomAccessFile.create(this.mUri, mode);
    }
    if (!this.ensureFile()) {
      throw new Error("Can't make sure it is file");
    }
    return FileDescriptorRandomAccessFile.create(this.mUri, mode);
  }
}

// ══════════════════════════════════════════════════════════════════════════
// 对位 TreeDocumentFile.java：用户授权目录（可建子项、可列目录）
// ══════════════════════════════════════════════════════════════════════════

/** 对位 com.hippo.unifile.TreeDocumentFile。 */
export class TreeDocumentFile extends UniFile {
  private mUri: string;
  private mFilename: string;

  /**
   * @param uri 目录/子项 URI
   * @param filename 子项名（上游第二个构造器才有；空串表示「当前 URI 就是命名锚点本身」）
   */
  constructor(parent: UniFile | null, uri: string, filename: string) {
    super(parent);
    this.mUri = uri;
    this.mFilename = filename;
  }

  createFile(displayName: string): UniFile | null {
    const child: UniFile | null = this.findFile(displayName);
    if (child !== null) {
      if (child.isFile()) {
        return child;
      }
      Utils.logW(TAG, `Try to create file ${displayName}, but it is not file`);
      return null;
    }
    // 上游会按扩展名推断 MIME 再交给 createDocument；鸿蒙建空文件不需要 MIME，
    // 保留推断只是为了日志与后续 provider 适配（行为等价：都创建一个空文件）。
    const mimeType: string = Contracts.mimeFromName(displayName);
    const result: string | undefined = DocumentsContractApi21.createFile(this.mUri, mimeType, displayName);
    if (result === undefined) {
      return null;
    }
    return new TreeDocumentFile(this, result, displayName);
  }

  createDirectory(displayName: string): UniFile | null {
    const child: UniFile | null = this.findFile(displayName);
    if (child !== null) {
      return child.isDirectory() ? child : null;
    }
    const result: string | undefined = DocumentsContractApi21.createDirectory(this.mUri, displayName);
    if (result === undefined) {
      return null;
    }
    return new TreeDocumentFile(this, result, displayName);
  }

  getUri(): string {
    return this.mUri;
  }

  getName(): string | undefined {
    return DocumentsContractApi19.getName(this.mUri);
  }

  getType(): string | undefined {
    return DocumentsContractApi19.getType(this.mUri);
  }

  isDirectory(): boolean {
    return DocumentsContractApi19.isDirectory(this.mUri);
  }

  isFile(): boolean {
    return DocumentsContractApi19.isFile(this.mUri);
  }

  lastModified(): number {
    return DocumentsContractApi19.lastModified(this.mUri);
  }

  length(): number {
    return DocumentsContractApi19.lengthOf(this.mUri);
  }

  canRead(): boolean {
    return DocumentsContractApi19.canRead(this.mUri);
  }

  canWrite(): boolean {
    return DocumentsContractApi19.canWrite(this.mUri);
  }

  ensureDir(): boolean {
    if (this.isDirectory()) {
      return true;
    }
    if (this.isFile()) {
      return false;
    }
    const parent: UniFile | null = this.getParentFile();
    if (parent !== null && parent.ensureDir() && this.mFilename.length > 0) {
      return parent.createDirectory(this.mFilename) !== null;
    }
    return false;
  }

  ensureFile(): boolean {
    if (this.isFile()) {
      return true;
    }
    if (this.isDirectory()) {
      return false;
    }
    const parent: UniFile | null = this.getParentFile();
    if (parent !== null && parent.ensureDir() && this.mFilename.length > 0) {
      return parent.createFile(this.mFilename) !== null;
    }
    return false;
  }

  subFile(displayName: string): UniFile | null {
    const childUri: string = DocumentsContractApi21.buildChildUri(this.mUri, displayName);
    return new TreeDocumentFile(this, childUri, displayName);
  }

  delete(): boolean {
    return DocumentsContractApi19.delete(this.mUri);
  }

  exists(): boolean {
    return DocumentsContractApi19.exists(this.mUri);
  }

  listFiles(): UniFile[] | null {
    const uris: string[] = DocumentsContractApi21.listFiles(this.mUri);
    const results: UniFile[] = [];
    for (const uri of uris) {
      results.push(new TreeDocumentFile(this, uri, Contracts.nameOf(uri)));
    }
    return results;
  }

  listFilesFiltered(filter: FilenameFilter | null): UniFile[] | null {
    if (filter === null) {
      return this.listFiles();
    }
    const uris: string[] = DocumentsContractApi21.listFiles(this.mUri);
    const results: UniFile[] = [];
    for (const uri of uris) {
      const name: string = Contracts.nameOf(uri);
      if (filter.accept(this, name)) {
        results.push(new TreeDocumentFile(this, uri, name));
      }
    }
    return results;
  }

  findFile(displayName: string): UniFile | null {
    const childUri: string = DocumentsContractApi21.buildChildUri(this.mUri, displayName);
    return DocumentsContractApi19.exists(childUri)
      ? new TreeDocumentFile(this, childUri, displayName)
      : null;
  }

  renameTo(displayName: string): boolean {
    const result: string | undefined = DocumentsContractApi21.renameTo(this.mUri, displayName);
    if (result === undefined) {
      return false;
    }
    this.mUri = result;
    this.mFilename = displayName;
    return true;
  }

  openOutputStream(): OutputStream {
    return Contracts.openOutputStream(this.mUri);
  }

  openOutputStreamAppend(append: boolean): OutputStream {
    return Contracts.openOutputStreamAppend(this.mUri, append);
  }

  openInputStream(): InputStream {
    return Contracts.openInputStream(this.mUri);
  }

  createRandomAccessFile(mode: string): UniRandomAccessFile {
    if (mode === 'r') {
      return FileDescriptorRandomAccessFile.create(this.mUri, mode);
    }
    if (!this.ensureFile()) {
      throw new Error("Can't make sure it is file");
    }
    return FileDescriptorRandomAccessFile.create(this.mUri, mode);
  }
}

// ══════════════════════════════════════════════════════════════════════════
// 对位 MediaFile.java：媒体库 URI（只读为主，写走 UriOutputStream）
// ══════════════════════════════════════════════════════════════════════════

/** 对位 com.hippo.unifile.MediaFile。 */
export class MediaFile extends UniFile {
  private readonly mUri: string;

  constructor(uri: string) {
    super(null);
    this.mUri = uri;
  }

  createFile(displayName: string): UniFile | null {
    return null;
  }

  createDirectory(displayName: string): UniFile | null {
    return null;
  }

  getUri(): string {
    return this.mUri;
  }

  getName(): string | undefined {
    return MediaContract.getName(this.mUri);
  }

  getType(): string | undefined {
    return MediaContract.getType(this.mUri);
  }

  isDirectory(): boolean {
    return false;
  }

  isFile(): boolean {
    try {
      Utils.closeQuietly(this.openInputStream());
      return true;
    } catch (e) {
      Utils.throwIfFatal(e);
      return false;
    }
  }

  lastModified(): number {
    return MediaContract.lastModified(this.mUri);
  }

  length(): number {
    return MediaContract.lengthOf(this.mUri);
  }

  canRead(): boolean {
    return this.isFile();
  }

  canWrite(): boolean {
    try {
      Utils.closeQuietly(this.openOutputStreamAppend(true));
      return true;
    } catch (e) {
      Utils.throwIfFatal(e);
      return false;
    }
  }

  ensureDir(): boolean {
    return false;
  }

  ensureFile(): boolean {
    if (this.isFile()) {
      return true;
    }
    try {
      Utils.closeQuietly(this.openOutputStream());
      return true;
    } catch (e) {
      Utils.throwIfFatal(e);
      return false;
    }
  }

  subFile(displayName: string): UniFile | null {
    return null;
  }

  delete(): boolean {
    // 上游 MediaFile.delete() 恒 false（媒体条目要经 MediaStore 删除）
    return false;
  }

  exists(): boolean {
    return this.isFile();
  }

  listFiles(): UniFile[] | null {
    return null;
  }

  listFilesFiltered(filter: FilenameFilter | null): UniFile[] | null {
    return null;
  }

  findFile(displayName: string): UniFile | null {
    return null;
  }

  renameTo(displayName: string): boolean {
    return false;
  }

  openOutputStream(): OutputStream {
    return UriOutputStream.create(this.mUri, 'w');
  }

  openOutputStreamAppend(append: boolean): OutputStream {
    return UriOutputStream.create(this.mUri, append ? 'wa' : 'w');
  }

  openInputStream(): InputStream {
    return Contracts.openInputStream(this.mUri);
  }

  createRandomAccessFile(mode: string): UniRandomAccessFile {
    return FileDescriptorRandomAccessFile.create(this.mUri, mode);
  }
}

/** MIME 目录哨兵在本文件被间接使用（getType 语义），保留导出以便调用点判定。 */
export const UNIFILE_MIME_TYPE_DIR: string = MimeType.DIR;
