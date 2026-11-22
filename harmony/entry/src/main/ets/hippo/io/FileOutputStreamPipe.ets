/*
 * 对位上游：app/src/main/java/com/hippo/io/FileOutputStreamPipe.java
 *
 * 平台对位（v2：与 net-parse 的 streampipe 等价层对齐）：
 *   - 实现 `hippo/streampipe/OutputStreamPipe`（net-parse 落地，inventory/net-parse.extra.txt 登记）。
 *     该接口的 open() 返回 `ByteSink`（ArkTS 无 OutputStream 基类，收敛成 write(ArrayBuffer)/close()）。
 *   - 上游 `new FileOutputStream(file)` = 覆盖写 → 这里 openSync(WRITE_ONLY | CREATE | TRUNC)。
 *   - close() 幂等且不抛（上游 IOUtils.closeQuietly）。
 */

import fs from '@ohos.file.fs';
import { Utils } from '../unifile/Utils';
import { OutputStreamPipe, ByteSink } from '../streampipe/OutputStreamPipe';

/** fs 句柄上的最小写端（对位 java.io.OutputStream 的 write/flush/close）。 */
class FsByteSink implements ByteSink {
  private readonly file: fs.File;
  private closed: boolean = false;

  constructor(file: fs.File) {
    this.file = file;
  }

  write(data: ArrayBuffer): void {
    if (this.closed) {
      throw new Error('Stream closed');
    }
    fs.writeSync(this.file.fd, data);
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

  /** 落盘（上游 FileOutputStream 无缓冲时 flush 为空操作；这里等价为 fsync，更安全）。 */
  flush(): void {
    if (this.closed) {
      return;
    }
    try {
      fs.fsyncSync(this.file.fd);
    } catch (e) {
      Utils.throwIfFatal(e);
    }
  }
}

/** 对位 com.hippo.io.FileOutputStreamPipe：按路径覆盖写。 */
export class FileOutputStreamPipe implements OutputStreamPipe {
  private readonly mPath: string;
  private mSink: FsByteSink | null = null;

  constructor(path: string) {
    this.mPath = path;
  }

  obtain(): void {
    // 上游空实现
  }

  release(): void {
    // 上游空实现
  }

  open(): ByteSink {
    if (this.mSink !== null) {
      throw new Error('Please close it first');
    }
    const mode: number = fs.OpenMode.WRITE_ONLY | fs.OpenMode.CREATE | fs.OpenMode.TRUNC;
    const sink: FsByteSink = new FsByteSink(fs.openSync(this.mPath, mode));
    this.mSink = sink;
    return sink;
  }

  close(): void {
    const sink: FsByteSink | null = this.mSink;
    this.mSink = null;
    if (sink === null) {
      return;
    }
    try {
      sink.close();
    } catch (e) {
      Utils.throwIfFatal(e);
    }
  }
}
