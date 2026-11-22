/*
 * 对位上游：app/src/main/java/com/hippo/ehviewer/gallery/Pipe.kt
 *
 * 用途：容量受限的环形缓冲管道，供「native/解码线程写 → 阅读器线程读」使用
 * （上游 A7ZipArchive 解压流、GalleryProvider2 的图片流都走它）。
 *
 * 平台对位（关键：ArkTS 没有 synchronized/wait/notify）：
 *   - 上游 `synchronized(this) { ... wait() ... notifyAll() }` 是「监视器 + 条件变量」。
 *     ArkTS 无监视器，唯一的跨线程阻塞原语是 `Atomics.wait/notify`（作用于 SharedArrayBuffer）。
 *     因此本 port 把环形缓冲区和状态字都放进 **SharedArrayBuffer**：
 *       data  : capacity 字节的数据环
 *       state : Int32Array(6) = [head, tail, full, inClosed, outClosed, seq]
 *     `seq` 是条件序号：读者/写者各自 `Atomics.load(seq)` 后 `Atomics.wait(state, 5, seq)`
 *     进入睡眠，另一方 `Atomics.notify(state, 5, 1)` 唤醒；唤醒后重查条件（标准条件变量模式）。
 *   - 一致性：上游用「单锁保护全部状态」；这里把 head/tail/full/closed 全部放进 state 数组，
 *     用 Atomics.load/store 保证可见性，逻辑与上游逐行对应（含 min() 的两次语义）。
 *   - 使用约束：`Atomics.wait` 不能跑在 UI 主线程（会抛）。这与上游的隐含约束一致
 *     （上游在 glgallery 的渲染线程 + 解码线程之间用 Pipe，主线程阻塞本来就是 bug）。
 *
 * 与上游的签名差异（ArkTS 无 java.io / 无方法重载）：
 *   inputStream  → getInputStream(): PipeInputStream { read(): number; readBytes(b, off, len): number; close(); }
 *   outputStream → getOutputStream(): PipeOutputStream { writeByte(b): void; writeBytes(b, off, len): void; close(); }
 */

const IDX_HEAD: number = 0;
const IDX_TAIL: number = 1;
const IDX_FULL: number = 2;
const IDX_IN_CLOSED: number = 3;
const IDX_OUT_CLOSED: number = 4;
const IDX_SEQ: number = 5;

/** 管道读端（对位上游 `Pipe.inputStream`）。 */
export interface PipeInputStream {
  /** 读一个字节，EOF 返回 -1。 */
  read(): number;

  /** 读 len 字节到 b[off..]，返回实际字节数，EOF 返回 -1。 */
  readBytes(b: ArrayBuffer, off: number, len: number): number;

  close(): void;
}

/** 管道写端（对位上游 `Pipe.outputStream`）。 */
export interface PipeOutputStream {
  writeByte(b: number): void;

  writeBytes(b: ArrayBuffer, off: number, len: number): void;

  close(): void;
}

/**
 * 对位上游 `internal class Pipe(capacity: Int)`。
 * 注意：跨线程使用；同一 Pipe 只允许一个读者 + 一个写者（与上游一致）。
 */
export class Pipe {
  private readonly capacity: number;
  private readonly data: Uint8Array;
  private readonly state: Int32Array;
  private readonly input: PipeInputStreamImpl;
  private readonly output: PipeOutputStreamImpl;

  constructor(capacity: number) {
    if (capacity <= 0) {
      throw new Error(`capacity must be > 0, but ${capacity}`);
    }
    this.capacity = capacity;
    this.data = new Uint8Array(new SharedArrayBuffer(capacity));
    this.state = new Int32Array(new SharedArrayBuffer(6 * 4));
    this.input = new PipeInputStreamImpl(this);
    this.output = new PipeOutputStreamImpl(this);
  }

  getCapacity(): number {
    return this.capacity;
  }

  getInputStream(): PipeInputStream {
    return this.input;
  }

  getOutputStream(): PipeOutputStream {
    return this.output;
  }

  // ---------------------------------------------------------------- 供内层类访问

  /** 数据环（SharedArrayBuffer 视图）。 */
  getData(): Uint8Array {
    return this.data;
  }

  getState(): Int32Array {
    return this.state;
  }

  /** 唤醒所有等待者（对位上游 notifyAll()）。 */
  notifyAll(): void {
    Atomics.notify(this.state, IDX_SEQ);
  }

  /**
   * 在条件序号上睡眠（对位上游 wait()）。
   * @param expected 进入等待前观察到的 seq，避免丢唤醒
   */
  awaitChange(expected: number): void {
    Atomics.wait(this.state, IDX_SEQ, expected);
  }

  /** 读 seq（进入等待前的快照）。 */
  loadSeq(): number {
    return Atomics.load(this.state, IDX_SEQ);
  }

  /** seq 自增（每次状态变化都递增，让等待者一定被唤醒）。 */
  bumpSeq(): void {
    Atomics.add(this.state, IDX_SEQ, 1);
  }
}

/** 对位上游 `object : InputStream()`（匿名子类）。 */
class PipeInputStreamImpl implements PipeInputStream {
  private readonly pipe: Pipe;

  constructor(pipe: Pipe) {
    this.pipe = pipe;
  }

  read(): number {
    const one: ArrayBuffer = new ArrayBuffer(1);
    const n: number = this.readBytes(one, 0, 1);
    if (n === -1) {
      return -1;
    }
    return new Uint8Array(one)[0];
  }

  readBytes(b: ArrayBuffer, off: number, len: number): number {
    const st: Int32Array = this.pipe.getState();
    const data: Uint8Array = this.pipe.getData();
    const capacity: number = this.pipe.getCapacity();
    while (true) {
      if (Atomics.load(st, IDX_IN_CLOSED) !== 0) {
        throw new Error('The InputStream is closed');
      }
      if (len === 0) {
        return 0;
      }
      const head: number = Atomics.load(st, IDX_HEAD);
      const tail: number = Atomics.load(st, IDX_TAIL);
      const full: number = Atomics.load(st, IDX_FULL);
      if (head === tail && full === 0) {
        if (Atomics.load(st, IDX_OUT_CLOSED) !== 0) {
          // 没有数据且写端已关闭 → EOF
          return -1;
        }
        // 等写端写入（条件变量模式：先取 seq 快照再重查条件，最后才睡）
        const seq: number = this.pipe.loadSeq();
        if (Atomics.load(st, IDX_HEAD) === head && Atomics.load(st, IDX_TAIL) === tail &&
          Atomics.load(st, IDX_FULL) === 0 && Atomics.load(st, IDX_IN_CLOSED) === 0) {
          this.pipe.awaitChange(seq);
        }
      } else {
        const available: number = (head < tail ? tail : capacity) - head;
        const readLen: number = Math.min(len, available);
        const dst: Uint8Array = new Uint8Array(b, off, readLen);
        dst.set(data.subarray(head, head + readLen));
        let newHead: number = head + readLen;
        if (newHead === capacity) {
          newHead = 0;
        }
        Atomics.store(st, IDX_HEAD, newHead);
        Atomics.store(st, IDX_FULL, 0);
        this.pipe.bumpSeq();
        this.pipe.notifyAll();
        return readLen;
      }
    }
  }

  close(): void {
    const st: Int32Array = this.pipe.getState();
    Atomics.store(st, IDX_IN_CLOSED, 1);
    this.pipe.bumpSeq();
    this.pipe.notifyAll();
  }
}

/** 对位上游 `object : OutputStream()`（匿名子类）。 */
class PipeOutputStreamImpl implements PipeOutputStream {
  private readonly pipe: Pipe;

  constructor(pipe: Pipe) {
    this.pipe = pipe;
  }

  writeByte(b: number): void {
    const one: ArrayBuffer = new ArrayBuffer(1);
    new Uint8Array(one)[0] = b & 0xff;
    this.writeBytes(one, 0, 1);
  }

  writeBytes(b: ArrayBuffer, off: number, len: number): void {
    const st: Int32Array = this.pipe.getState();
    const data: Uint8Array = this.pipe.getData();
    const capacity: number = this.pipe.getCapacity();
    const src: Uint8Array = new Uint8Array(b, off, len);
    let written: number = 0;
    while (written < len) {
      if (Atomics.load(st, IDX_OUT_CLOSED) !== 0) {
        throw new Error('The OutputStream is closed');
      }
      if (Atomics.load(st, IDX_IN_CLOSED) !== 0) {
        throw new Error('The InputStream is closed');
      }
      const head: number = Atomics.load(st, IDX_HEAD);
      const tail: number = Atomics.load(st, IDX_TAIL);
      const full: number = Atomics.load(st, IDX_FULL);
      if (head === tail && full !== 0) {
        // 缓冲区满，等读端取走
        const seq: number = this.pipe.loadSeq();
        if (Atomics.load(st, IDX_HEAD) === head && Atomics.load(st, IDX_TAIL) === tail &&
          Atomics.load(st, IDX_FULL) !== 0 && Atomics.load(st, IDX_OUT_CLOSED) === 0) {
          this.pipe.awaitChange(seq);
        }
      } else {
        const space: number = (head <= tail ? capacity : head) - tail;
        const writeLen: number = Math.min(len - written, space);
        data.set(src.subarray(written, written + writeLen), tail);
        written += writeLen;
        let newTail: number = tail + writeLen;
        if (newTail === capacity) {
          newTail = 0;
        }
        Atomics.store(st, IDX_TAIL, newTail);
        if (Atomics.load(st, IDX_HEAD) === newTail) {
          Atomics.store(st, IDX_FULL, 1);
        }
        this.pipe.bumpSeq();
        this.pipe.notifyAll();
      }
    }
  }

  close(): void {
    const st: Int32Array = this.pipe.getState();
    Atomics.store(st, IDX_OUT_CLOSED, 1);
    this.pipe.bumpSeq();
    this.pipe.notifyAll();
  }
}
