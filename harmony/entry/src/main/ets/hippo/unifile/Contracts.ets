/*
 * 对位上游：app/src/main/java/com/hippo/unifile/Contracts.java
 *
 * 平台对位（详见 MR「UniFile 抽象层平台对位」）：
 *   - 上游用 ContentResolver.query(uri, [column]) 取 Document 列（DISPLAY_NAME / MIME_TYPE /
 *     SIZE / LAST_MODIFIED / FLAGS）。鸿蒙没有 ContentProvider/Cursor 抽象，
 *     等价信息全部来自 `@ohos.file.fs` 的 stat（size / mtime / mode / isDirectory），
 *     故 queryForXxx 保留上游函数名与「列名 + 默认值」的调用形状，内部改为按列名分派到 stat。
 *   - 上游 openInputStream/openOutputStream 走 ContentResolver；鸿蒙走 fs.openSync + 显式
 *     fd 偏移读写。因为 ArkTS 没有 java.io 流的重载，InputStream/OutputStream 的契约在本文件定义
 *     （下游 hippo/ehviewer/{spider,gallery}、hippo/lib/image、download-sync 都从这个文件取类型）。
 *   - URI ↔ 路径转换规则（MR 必填项）：
 *       file://docs/storage/Users/<user>/...      → /storage/Users/<user>/...   （用户文档域）
 *       file://<bundleName>/data/storage/el2/...  → /data/storage/el2/...       （应用沙箱）
 *     反向统一用 @ohos.file.fileuri 的 getUriFromPath()，禁止手工拼 authority。
 *     注意：getUriFromPath 是单向 API，鸿蒙 API 20 不提供 getPathFromUri，故 toPath() 自己解析。
 */

import fs from '@ohos.file.fs';
import fileUri from '@ohos.file.fileuri';
import { Utils, Closeable } from './Utils';

const TAG: string = 'Contracts';

/*
 * 对位 java.io.Closeable（上游 InputStream/OutputStream 的基类型）。
 *
 * 注意：Closeable 的唯一声明在 Utils.ets（叶子模块），本文件只 import、不重复声明。
 * 原因：ArkTS 禁止结构化类型（arkts-no-structural-typing）。若这里再声明一个同形状的
 * `interface Closeable`，`Utils.closeQuietly(c: Utils.Closeable)` 就吃不下本文件的
 * InputStream / OutputStream —— 编译器不会因为"形状相同"放行。
 * 这正是 build_hap 编译探针在 FileInputStreamPipe.ets:66 与 FileOutputStreamPipe.ets:57
 * 抓到的真实错误（tsc --strict 放行、ArkTS 拒绝）。保留此注释防止回退。
 */

/**
 * 对位 java.io.InputStream。
 * ArkTS 无方法重载（方案 §5-⑦），上游三个 read 重载拆成 read / readBuffer / readBytes。
 */
export interface InputStream extends Closeable {
  /** 上游 read()：读一个字节，EOF 返回 -1。 */
  read(): number;

  /** 上游 read(byte[])：读满 buffer.length，EOF 返回 -1。 */
  readBuffer(buffer: ArrayBuffer): number;

  /** 上游 read(byte[], int, int)：读 len 字节到 buffer[off..]，EOF 返回 -1。 */
  readBytes(buffer: ArrayBuffer, off: number, len: number): number;

  /** 上游 skip(long)：返回实际跳过的字节数。 */
  skip(n: number): number;

  /** 上游 available()：剩余可读字节数。 */
  available(): number;
}

/**
 * 对位 java.io.OutputStream。
 * ArkTS 无方法重载，上游 write(byte[]) / write(byte[],int,int) 拆成 write / writeBytes。
 */
export interface OutputStream extends Closeable {
  /** 上游 write(byte[])。 */
  write(buffer: ArrayBuffer): void;

  /** 上游 write(byte[], int, int)。 */
  writeBytes(buffer: ArrayBuffer, off: number, len: number): void;

  /** 上游 flush()。 */
  flush(): void;
}

/** 对位 DocumentsContract.Document 的常用列名（保持上游列名字符串，便于对照）。 */
export class DocumentColumn {
  static readonly DOCUMENT_ID: string = 'document_id';
  static readonly DISPLAY_NAME: string = 'display_name';
  static readonly MIME_TYPE: string = 'mime_type';
  static readonly SIZE: string = 'size';
  static readonly LAST_MODIFIED: string = 'last_modified';
  static readonly FLAGS: string = 'flags';
}

/** 对位 DocumentsContract.Document 的位标志。 */
export class DocumentFlag {
  static readonly SUPPORTS_WRITE: number = 1 << 1;
  static readonly SUPPORTS_DELETE: number = 1 << 2;
  static readonly DIR_SUPPORTS_CREATE: number = 1 << 3;
}

/** 对位 DocumentsContract.Document 的 MIME 常量。 */
export class MimeType {
  /** 上游 MIME_TYPE_DIR 的取值，仅作本抽象层内部哨兵，不参与网络协议。 */
  static readonly DIR: string = 'vnd.android.document/directory';
  static readonly OCTET_STREAM: string = 'application/octet-stream';
}

/*
 * 上游 MimeTypeMap.getSingleton().getMimeTypeFromExtension()：
 * 鸿蒙没有系统级 MimeTypeMap，这里按 EhViewer 实际接触的扩展名建表（图片 / 归档 / 网页 / 文本）。
 * 表外扩展名一律 application/octet-stream，与上游 RawFile.getTypeForName 的行为一致。
 */
const MIME_TABLE: Map<string, string> = new Map<string, string>([
  ['jpg', 'image/jpeg'], ['jpeg', 'image/jpeg'], ['jpe', 'image/jpeg'],
  ['png', 'image/png'], ['gif', 'image/gif'], ['webp', 'image/webp'],
  ['bmp', 'image/bmp'], ['avif', 'image/avif'], ['heic', 'image/heic'],
  ['jxl', 'image/jxl'], ['svg', 'image/svg+xml'],
  ['zip', 'application/zip'], ['cbz', 'application/vnd.comicbook+zip'],
  ['7z', 'application/x-7z-compressed'], ['rar', 'application/vnd.rar'],
  ['cbr', 'application/vnd.comicbook-rar'],
  ['txt', 'text/plain'], ['html', 'text/html'], ['htm', 'text/html'],
  ['json', 'application/json'], ['xml', 'application/xml'],
  ['pdf', 'application/pdf'], ['apk', 'application/vnd.android.package-archive'],
  ['db', 'application/x-sqlite3'], ['sqlite', 'application/x-sqlite3']
]);

/**
 * 对位 com.hippo.unifile.Contracts。
 * 保留上游静态方法名（queryForString/queryForInt/queryForLong/openInputStream/openOutputStream），
 * 参数由 (Context, Uri, ...) 收缩为 (target, ...)：鸿蒙侧没有 Context 依赖，
 * target 同时接受「沙箱/用户域绝对路径」与「file:// URI」，内部统一转路径后交给 fs。
 */
export class Contracts {
  private constructor() {
  }

  // ---------------------------------------------------------------- 路径 / URI

  /** 是否为 URI 形式（只认 file://，鸿蒙无 content://）。 */
  static isUri(target: string): boolean {
    return target.startsWith('file://');
  }

  /**
   * 提取 file:// URI 的 authority 段；非 file:// URI 返回 undefined。
   * 例：'file:///a/b' → ''；'file://docs/a' → 'docs'；'file://media/a' → 'media'。
   */
  static authorityOf(target: string): string | undefined {
    if (!Contracts.isUri(target)) {
      return undefined;
    }
    const rest: string = target.substring('file://'.length);
    const slash: number = rest.indexOf('/');
    return slash < 0 ? rest : rest.substring(0, slash);
  }

  /**
   * URI → 绝对路径。规则见文件头注释。
   * 非 URI 输入原样返回（上游 RawFile 走的就是 File.getPath()）。
   */
  static toPath(target: string): string {
    if (!Contracts.isUri(target)) {
      return target;
    }
    // file://<authority>/<abs-path>：去掉 scheme 与 authority 段
    const rest: string = target.substring('file://'.length);
    const slash: number = rest.indexOf('/');
    if (slash < 0) {
      return '/';
    }
    let path: string = rest.substring(slash);
    // 防御：URI 可能是百分号编码（含空格/中文的目录名）
    if (path.indexOf('%') >= 0) {
      try {
        path = decodeURIComponent(path);
      } catch (e) {
        Utils.throwIfFatal(e);
      }
    }
    return path;
  }

  /** 绝对路径 → URI（反向统一走系统 API，禁止手拼 authority）。 */
  static toUri(path: string): string {
    if (Contracts.isUri(path)) {
      return path;
    }
    try {
      return fileUri.getUriFromPath(path);
    } catch (e) {
      Utils.throwIfFatal(e);
      Utils.logE(TAG, `getUriFromPath failed: ${path}`);
      return path;
    }
  }

  /** 把 target（路径或 URI）规范化成绝对路径，并去掉结尾多余的 '/'（根目录除外）。 */
  static normalize(target: string): string {
    let p: string = Contracts.toPath(target);
    while (p.length > 1 && p.endsWith('/')) {
      p = p.substring(0, p.length - 1);
    }
    return p;
  }

  /** 对位 Uri.getPathSegments() 的最后一段 / File.getName()。根目录返回空串。 */
  static nameOf(target: string): string {
    const p: string = Contracts.normalize(target);
    if (p === '/' || p.length === 0) {
      return '';
    }
    const idx: number = p.lastIndexOf('/');
    return idx < 0 ? p : p.substring(idx + 1);
  }

  /** 取父目录路径；已到根返回 undefined（对位 File.getParent / UniFile.getParentFile 的边界）。 */
  static parentOf(target: string): string | undefined {
    const p: string = Contracts.normalize(target);
    if (p === '/' || p.length === 0) {
      return undefined;
    }
    const idx: number = p.lastIndexOf('/');
    if (idx < 0) {
      return undefined;
    }
    return idx === 0 ? '/' : p.substring(0, idx);
  }

  /** 子路径拼接（不做存在性检查，对位 new File(parent, name)）。 */
  static childOf(parent: string, displayName: string): string {
    const p: string = Contracts.normalize(parent);
    return p === '/' ? `/${displayName}` : `${p}/${displayName}`;
  }

  // ---------------------------------------------------------------- stat 分派

  /** stat；失败返回 undefined（上游 query 失败返回 defaultValue 的等价路径）。 */
  static statOf(target: string): fs.Stat | undefined {
    try {
      return fs.statSync(Contracts.toPath(target));
    } catch (e) {
      Utils.throwIfFatal(e);
      if (Contracts.isUri(target)) {
        let opened: fs.File | null = null;
        try {
          opened = fs.openSync(target, fs.OpenMode.READ_ONLY);
          return fs.statSync(opened.fd);
        } catch (uriErr) {
          Utils.throwIfFatal(uriErr);
          return undefined;
        } finally {
          if (opened !== null) {
            try {
              fs.closeSync(opened);
            } catch (closeErr) {
              Utils.throwIfFatal(closeErr);
              Utils.logW(TAG, `statOf closeSync failed for ${target}`);
            }
          }
        }
      }
      return undefined;
    }
  }

  static exists(target: string): boolean {
    try {
      if (fs.accessSync(Contracts.toPath(target))) {
        return true;
      }
    } catch (e) {
      Utils.throwIfFatal(e);
    }
    if (Contracts.isUri(target)) {
      return Contracts.statOf(target) !== undefined;
    }
    return false;
  }

  /** 以只读方式打开路径或外部 URI：file:// URI 先直开再退化到剥离路径。 */
  static openReadFile(target: string): fs.File {
    if (Contracts.isUri(target)) {
      try {
        return fs.openSync(target, fs.OpenMode.READ_ONLY);
      } catch (e) {
        Utils.throwIfFatal(e);
        Utils.logW(TAG, `openReadFile direct URI fallback to path: ${target}`);
      }
    }
    return fs.openSync(Contracts.toPath(target), fs.OpenMode.READ_ONLY);
  }

  // ---------------------------------------------------------------- queryForXxx

  /**
   * 对位 Contracts.queryForString(context, uri, column, defaultValue)。
   * 支持列：DOCUMENT_ID / DISPLAY_NAME / MIME_TYPE；其余列走 queryForLong 再转字符串。
   */
  static queryForString(target: string, column: string, defaultValue: string | undefined): string | undefined {
    if (column === DocumentColumn.DOCUMENT_ID) {
      return Contracts.toUri(target);
    }
    if (column === DocumentColumn.DISPLAY_NAME) {
      const name: string = Contracts.nameOf(target);
      return name.length > 0 ? name : defaultValue;
    }
    if (column === DocumentColumn.MIME_TYPE) {
      const st: fs.Stat | undefined = Contracts.statOf(target);
      if (st === undefined) {
        return defaultValue;
      }
      return st.isDirectory() ? MimeType.DIR : Contracts.mimeFromName(Contracts.nameOf(target));
    }
    const n: number = Contracts.queryForLong(target, column, -1);
    return n < 0 ? defaultValue : `${n}`;
  }

  /** 对位 Contracts.queryForInt。 */
  static queryForInt(target: string, column: string, defaultValue: number): number {
    return Math.trunc(Contracts.queryForLong(target, column, defaultValue));
  }

  /**
   * 对位 Contracts.queryForLong。
   * SIZE / LAST_MODIFIED 取 stat；FLAGS 由 mode 推导（可写位 → SUPPORTS_WRITE|SUPPORTS_DELETE，
   * 目录 → DIR_SUPPORTS_CREATE）。上游 FLAGS 来自 provider 上报，鸿蒙只能按本机可写性推导，
   * 语义等价于「本进程能否写/删」。
   */
  static queryForLong(target: string, column: string, defaultValue: number): number {
    const st: fs.Stat | undefined = Contracts.statOf(target);
    if (column === DocumentColumn.FLAGS) {
      if (st === undefined) {
        return defaultValue;
      }
      let flags: number = 0;
      if (Contracts.canWrite(target)) {
        flags |= DocumentFlag.SUPPORTS_WRITE | DocumentFlag.SUPPORTS_DELETE;
      }
      if (st.isDirectory() && Contracts.canWrite(target)) {
        flags |= DocumentFlag.DIR_SUPPORTS_CREATE;
      }
      return flags;
    }
    if (st === undefined) {
      return defaultValue;
    }
    if (column === DocumentColumn.SIZE) {
      return st.size;
    }
    if (column === DocumentColumn.LAST_MODIFIED) {
      // fs.Stat.mtime 单位是秒，上游 COLUMN_LAST_MODIFIED 单位是毫秒
      return st.mtime * 1000;
    }
    return defaultValue;
  }

  /** 读权限判定（对位 DocumentsContractApi19.canRead，去掉 URI grant 检查改探针式 access）。 */
  static canRead(target: string): boolean {
    try {
      return fs.accessSync(Contracts.toPath(target), fs.AccessModeType.READ);
    } catch (e) {
      Utils.throwIfFatal(e);
      return false;
    }
  }

  /** 写权限判定（对位 canWrite）。 */
  static canWrite(target: string): boolean {
    try {
      return fs.accessSync(Contracts.toPath(target), fs.AccessModeType.WRITE);
    } catch (e) {
      Utils.throwIfFatal(e);
      return false;
    }
  }

  // ---------------------------------------------------------------- MIME

  /** 对位 MimeTypeMap.getMimeTypeFromExtension；表外返回 octet-stream。 */
  static mimeFromName(name: string): string {
    const lastDot: number = name.lastIndexOf('.');
    if (lastDot >= 0 && lastDot < name.length - 1) {
      const ext: string = name.substring(lastDot + 1).toLowerCase();
      const mime: string | undefined = MIME_TABLE.get(ext);
      if (mime !== undefined) {
        return mime;
      }
    }
    return MimeType.OCTET_STREAM;
  }

  // ---------------------------------------------------------------- 流

  /** 对位 Contracts.openInputStream()：打开失败一律抛 Error（上游抛 IOException）。 */
  static openInputStream(target: string): InputStream {
    try {
      return new FsInputStream(target);
    } catch (e) {
      Utils.throwIfFatal(e);
      throw new Error(`Can't open InputStream: ${target}`);
    }
  }

  /** 对位 Contracts.openOutputStream(context, uri)：覆盖写。 */
  static openOutputStream(target: string): OutputStream {
    return Contracts.openOutputStreamAppend(target, false);
  }

  /** 对位 Contracts.openOutputStream(context, uri, append)。 */
  static openOutputStreamAppend(target: string, append: boolean): OutputStream {
    try {
      return new FsOutputStream(Contracts.toPath(target), append);
    } catch (e) {
      Utils.throwIfFatal(e);
      throw new Error(`Can't open OutputStream: ${target}`);
    }
  }

  // ---------------------------------------------------------------- 目录操作

  /** 目录项名字列表；失败或非目录返回 undefined（对位 File.listFiles() 返回 null）。 */
  static listNames(target: string): string[] | undefined {
    try {
      return fs.listFileSync(Contracts.toPath(target), { recursion: false });
    } catch (e) {
      Utils.throwIfFatal(e);
      return undefined;
    }
  }

  /**
   * 递归删除（对位 RawFile.deleteContents + File.delete）。
   * 注意：上游是「先递归清空内容再删自身」，这里保持同样顺序，失败不抛、返回 false。
   */
  static deleteRecursively(target: string): boolean {
    const path: string = Contracts.normalize(target);
    const st: fs.Stat | undefined = Contracts.statOf(path);
    if (st === undefined) {
      return false;
    }
    let ok: boolean = true;
    if (st.isDirectory()) {
      const names: string[] | undefined = Contracts.listNames(path);
      if (names !== undefined) {
        for (const name of names) {
          ok = Contracts.deleteRecursively(Contracts.childOf(path, name)) && ok;
        }
      }
      try {
        fs.rmdirSync(path);
      } catch (e) {
        Utils.throwIfFatal(e);
        Utils.logW(TAG, `Failed to rmdir ${path}`);
        ok = false;
      }
      return ok;
    }
    try {
      fs.unlinkSync(path);
      return true;
    } catch (e) {
      Utils.throwIfFatal(e);
      Utils.logW(TAG, `Failed to delete ${path}`);
      return false;
    }
  }
}

/** ArrayBuffer 区间拷贝（ArkTS 无 System.arraycopy）。 */
function copyRange(src: ArrayBuffer, srcOff: number, dst: ArrayBuffer, dstOff: number, len: number): void {
  const s: Uint8Array = new Uint8Array(src, srcOff, len);
  const d: Uint8Array = new Uint8Array(dst, dstOff, len);
  d.set(s);
}

/**
 * 对位 java.io.FileInputStream，底层换成 fs.openSync(READ_ONLY) + fs.lseek / 顺序读。
 * 通过 fs.lseek 推进内核偏移，同时维护逻辑指针 pos（用于 available()）。
 */
export class FsInputStream implements InputStream {
  private readonly fd: number;
  private readonly file: fs.File;
  private readonly size: number;
  private pos: number = 0;
  private closed: boolean = false;
  private readonly one: ArrayBuffer = new ArrayBuffer(1);

  constructor(path: string) {
    this.file = Contracts.openReadFile(path);
    this.fd = this.file.fd;
    try {
      const st: fs.Stat = fs.statSync(this.fd);
      this.size = st.size;
    } catch (e) {
      try {
        fs.closeSync(this.file);
      } catch (e2) {
        Utils.throwIfFatal(e2);
      }
      Utils.throwIfFatal(e);
      throw (e instanceof Error) ? e : new Error(String(e));
    }
  }

  read(): number {
    const b: ArrayBuffer = this.one;
    const n: number = this.fill(b, 0, 1);
    if (n <= 0) {
      return -1;
    }
    return new Uint8Array(b)[0];
  }

  readBuffer(buffer: ArrayBuffer): number {
    return this.fill(buffer, 0, buffer.byteLength);
  }

  readBytes(buffer: ArrayBuffer, off: number, len: number): number {
    const avail: number = buffer.byteLength - off;
    const realLen: number = len < avail ? len : avail;
    if (realLen <= 0) {
      return 0;
    }
    return this.fill(buffer, off, realLen);
  }

  skip(n: number): number {
    if (this.closed) {
      throw new Error('Stream closed');
    }
    if (n <= 0) {
      return 0;
    }
    const remain: number = this.size - this.pos;
    const step: number = n < remain ? n : (remain > 0 ? remain : 0);
    if (step > 0) {
      fs.lseek(this.fd, step, fs.WhenceType.SEEK_CUR);
      this.pos += step;
    }
    return step;
  }

  available(): number {
    const remain: number = this.size - this.pos;
    return remain > 0 ? remain : 0;
  }

  close(): void {
    if (this.closed) {
      return;
    }
    this.closed = true;
    try {
      fs.closeSync(this.file);
    } catch (e) {
      Utils.throwIfFatal(e);
    }
  }

  private fill(buffer: ArrayBuffer, off: number, len: number): number {
    if (this.closed) {
      throw new Error('Stream closed');
    }
    if (len <= 0) {
      return 0;
    }
    // ⚠ F-3 裁决（docs/f3-readsync-ruling.md）：`ReadOptions.offset` 的语义是
    // **filePointer + offset**（SDK d.ts L5370/5493/5578），而 readSync 本身已经推进内核 filePointer。
    // 所以**绝不能把 this.pos 传给 offset** —— 那会变成 2×已读字节数，每隔一块跳一块（静默损坏）。
    // 这里只传 length，让内核指针自然推进；this.pos 仍维护（available() 用它）。
    let n: number = 0;
    if (off === 0) {
      n = fs.readSync(this.fd, buffer, { length: len });
    } else {
      const tmp: ArrayBuffer = new ArrayBuffer(len);
      n = fs.readSync(this.fd, tmp, { length: len });
      if (n > 0) {
        copyRange(tmp, 0, buffer, off, n);
      }
    }
    if (n > 0) {
      this.pos += n;
      return n;
    }
    return -1;
  }
}

/**
 * 对位 java.io.FileOutputStream，底层 fs.openSync(WRITE_ONLY | CREATE | [TRUNC | APPEND])。
 * append=false → TRUNC（上游 new FileOutputStream(file)）；append=true → APPEND（new FileOutputStream(file, true)）。
 */
export class FsOutputStream implements OutputStream {
  private readonly fd: number;
  private readonly file: fs.File;
  private closed: boolean = false;
  private written: number = 0;

  constructor(path: string, append: boolean) {
    let mode: number = fs.OpenMode.WRITE_ONLY | fs.OpenMode.CREATE;
    mode = mode | (append ? fs.OpenMode.APPEND : fs.OpenMode.TRUNC);
    this.file = fs.openSync(path, mode);
    this.fd = this.file.fd;
  }

  write(buffer: ArrayBuffer): void {
    this.ensureOpen();
    const n: number = fs.writeSync(this.fd, buffer);
    this.written += n;
  }

  writeBytes(buffer: ArrayBuffer, off: number, len: number): void {
    this.ensureOpen();
    const avail: number = buffer.byteLength - off;
    const realLen: number = len < avail ? len : avail;
    if (realLen <= 0) {
      return;
    }
    if (off === 0 && realLen === buffer.byteLength) {
      this.written += fs.writeSync(this.fd, buffer);
      return;
    }
    const slice: ArrayBuffer = buffer.slice(off, off + realLen);
    this.written += fs.writeSync(this.fd, slice);
  }

  flush(): void {
    this.ensureOpen();
    try {
      fs.fsyncSync(this.fd);
    } catch (e) {
      Utils.throwIfFatal(e);
    }
  }

  close(): void {
    if (this.closed) {
      return;
    }
    this.closed = true;
    try {
      fs.closeSync(this.file);
    } catch (e) {
      Utils.throwIfFatal(e);
    }
  }

  /** 已写入字节数（供下载器核对进度，上游无此方法，仅本 port 内部使用）。 */
  getWritten(): number {
    return this.written;
  }

  private ensureOpen(): void {
    if (this.closed) {
      throw new Error('Stream closed');
    }
  }
}
