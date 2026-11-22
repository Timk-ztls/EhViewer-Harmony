/*
 * 对位上游：app/src/main/java/com/hippo/unifile/UniRandomAccessFile.java
 *
 * 平台差异：
 *   - 上游是 interface + java.io.RandomAccessFile 语义（read(byte[]) / read(byte[],int,int) 重载）。
 *     ArkTS 不支持方法重载（方案 §5 第 7 条），故重载对拆成独立方法名，
 *     对应关系：read(byte[]) → read / read(byte[],int,int) → readBytes，
 *               write(byte[]) → write / write(byte[],int,int) → writeBytes。
 *   - 字节容器 ArkTS 统一用 ArrayBuffer（对位 byte[]）。
 *   - 异常模型只有 Error，签名不再声明 throws IOException，语义由实现抛 Error 承担。
 */

/**
 * 对位上游 UniRandomAccessFile：UniFile 的随机读写句柄。
 * 用法与上游一致：先 seek 再 read/write，读越界返回 -1。
 */
export interface UniRandomAccessFile {
  /** 关闭句柄；重复关闭必须幂等（上游 close 后再 close 不抛）。 */
  close(): void;

  /** 当前文件指针（字节偏移）。 */
  getFilePointer(): number;

  /** 把指针移到 pos（>=0，否则抛 Error）。 */
  seek(pos: number): void;

  /** 跳过 n 字节（n<=0 返回 0；越过 EOF 时停在 EOF），返回实际跳过字节数。 */
  skipBytes(n: number): number;

  /** 文件长度。 */
  length(): number;

  /** 截断/扩展到 newLength 字节，指针随之后撤（上游行为）。 */
  setLength(newLength: number): void;

  /** 读满 buffer.length 字节，返回读到的字节数，EOF 返回 -1。 */
  read(buffer: ArrayBuffer): number;

  /** 从 off 开始读 len 字节（off/len 描述目标 buffer 的切片），返回读到的字节数，EOF 返回 -1。 */
  readBytes(buffer: ArrayBuffer, off: number, len: number): number;

  /** 写入整个 buffer。 */
  write(buffer: ArrayBuffer): void;

  /** 从 off 开始写 len 字节。 */
  writeBytes(buffer: ArrayBuffer, off: number, len: number): void;
}

/** 上游 RandomAccessFile 支持的模式串（"r" / "rw" / "rws" / "rwd"），保留以便调用点零改动。 */
export class RandomAccessMode {
  static readonly R: string = 'r';
  static readonly RW: string = 'rw';
  static readonly RWS: string = 'rws';
  static readonly RWD: string = 'rwd';
}
