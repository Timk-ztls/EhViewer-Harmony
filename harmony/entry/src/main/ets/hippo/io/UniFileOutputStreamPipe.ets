/*
 * 对位上游：app/src/main/java/com/hippo/io/UniFileOutputStreamPipe.java
 *
 * 平台对位（v2：与 net-parse 的 streampipe 等价层对齐）：
 *   - 实现 `hippo/streampipe/OutputStreamPipe`（inventory/net-parse.extra.txt 登记的等价层），
 *     open() 返回 ByteSink。
 *   - 上游行为不变：`UniFile.openOutputStream()`（覆盖写）、open 前必须 close、close 幂等。
 */

import fs from '@ohos.file.fs';
import { Utils } from '../unifile/Utils';
import { Contracts } from '../unifile/Contracts';
import { UniFile } from '../unifile/UniFile';
import { OutputStreamPipe, ByteSink } from '../streampipe/OutputStreamPipe';

/** fs 句柄上的最小写端（与 FileOutputStreamPipe 内的实现同构，各自文件内私有）。 */
class UniFileByteSink implements ByteSink {
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
}

/** 对位 com.hippo.io.UniFileOutputStreamPipe。 */
export class UniFileOutputStreamPipe implements OutputStreamPipe {
  private readonly mUniFile: UniFile;
  private mSink: UniFileByteSink | null = null;

  constructor(uniFile: UniFile) {
    this.mUniFile = uniFile;
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
    this.mUniFile.ensureFile();
    const path: string = Contracts.toPath(this.mUniFile.getUri());
    const mode: number = fs.OpenMode.WRITE_ONLY | fs.OpenMode.CREATE | fs.OpenMode.TRUNC;
    const sink: UniFileByteSink = new UniFileByteSink(fs.openSync(path, mode));
    this.mSink = sink;
    return sink;
  }

  close(): void {
    const sink: UniFileByteSink | null = this.mSink;
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
