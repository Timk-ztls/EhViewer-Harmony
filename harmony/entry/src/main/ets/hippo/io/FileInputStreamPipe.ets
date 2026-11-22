/*
 * 对位上游：app/src/main/java/com/hippo/io/FileInputStreamPipe.java
 *
 * 平台对位（v2：与 net-parse 已落地的等价层对齐）：
 *   - 上游接口 com.hippo.streampipe.InputStreamPipe 来自 Maven 依赖
 *     `com.github.seven332:streampipe:0.1.0`（无源码、无 inventory 编号）。
 *     net-parse 已在 `hippo/streampipe/InputStreamPipe.ets` 落了等价层（登记在
 *     inventory/net-parse.extra.txt），**本文件改为实现那个接口**，不再自带一份定义
 *     ——否则同一个上游契约在仓库里有两份互不接受的定义，beerbelly / SimpleDiskCache
 *     传 pipe 时会类型不兼容（ArkTS 无结构化类型，D-012 那轮已经吃过这个亏）。
 *   - 该接口的 open() 返回 `fileIo.File`（ArkTS 侧把 java.io.InputStream 收敛成 fs 句柄），
 *     故本类直接 fs.openSync 并交出句柄；调用方用自己的 readSync 读。
 *   - obtain/release 在上游 0.1.0 里就是空实现（引用计数在更高层 StreamPipe），保持空实现。
 *   - 上游构造参数 java.io.File → 鸿蒙绝对路径 string。
 */

import fs from '@ohos.file.fs';
import { Utils } from '../unifile/Utils';
import { InputStreamPipe } from '../streampipe/InputStreamPipe';

/** 对位 com.hippo.io.FileInputStreamPipe：按路径读。 */
export class FileInputStreamPipe implements InputStreamPipe {
  private readonly mPath: string;
  private mFile: fs.File | null = null;

  constructor(path: string) {
    this.mPath = path;
  }

  obtain(): void {
    // 上游空实现
  }

  release(): void {
    // 上游空实现
  }

  open(): fs.File {
    if (this.mFile !== null) {
      throw new Error('Please close it first');
    }
    const file: fs.File = fs.openSync(this.mPath, fs.OpenMode.READ_ONLY);
    this.mFile = file;
    return file;
  }

  close(): void {
    const file: fs.File | null = this.mFile;
    this.mFile = null;
    if (file === null) {
      return;
    }
    try {
      fs.closeSync(file);
    } catch (e) {
      Utils.throwIfFatal(e);
    }
  }
}
