/*
 * 对位上游：app/src/main/java/com/hippo/io/UniFileInputStreamPipe.java
 *
 * 平台对位（v2：与 net-parse 的 streampipe 等价层对齐）：
 *   - 实现 `hippo/streampipe/InputStreamPipe`（inventory/net-parse.extra.txt 登记的等价层）。
 *     该接口 open() 返回 `fileIo.File`，所以这里把 UniFile 定位到路径后直接开 fs 句柄，
 *     而不是返回 unifile/Contracts.ets 的 InputStream —— 保证 ImageBitmapHelper /
 *     SimpleDiskCache 这类下游拿得到同一个 pipe 类型。
 *   - 上游行为不变：obtain/release 空实现、open 前必须 close、close 幂等。
 */

import fs from '@ohos.file.fs';
import { Utils } from '../unifile/Utils';
import { Contracts } from '../unifile/Contracts';
import { UniFile } from '../unifile/UniFile';
import { InputStreamPipe } from '../streampipe/InputStreamPipe';

/** 对位 com.hippo.io.UniFileInputStreamPipe。 */
export class UniFileInputStreamPipe implements InputStreamPipe {
  private readonly mFile: UniFile;
  private mHandle: fs.File | null = null;

  constructor(file: UniFile) {
    this.mFile = file;
  }

  obtain(): void {
    // 上游空实现
  }

  release(): void {
    // 上游空实现
  }

  open(): fs.File {
    if (this.mHandle !== null) {
      throw new Error('Please close it first');
    }
    const path: string = Contracts.toPath(this.mFile.getUri());
    const handle: fs.File = fs.openSync(path, fs.OpenMode.READ_ONLY);
    this.mHandle = handle;
    return handle;
  }

  close(): void {
    const handle: fs.File | null = this.mHandle;
    this.mHandle = null;
    if (handle === null) {
      return;
    }
    try {
      fs.closeSync(handle);
    } catch (e) {
      Utils.throwIfFatal(e);
    }
  }
}
