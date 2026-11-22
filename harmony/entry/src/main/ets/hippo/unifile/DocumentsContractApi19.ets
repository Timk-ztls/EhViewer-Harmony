/*
 * 对位上游：app/src/main/java/com/hippo/unifile/DocumentsContractApi19.java
 *
 * 平台对位（表：Android DocumentsContract → 鸿蒙 fs）：
 *   isDocumentUri   → target 是 file:// URI（鸿蒙只有 file 一种 scheme，见 Contracts.isUri）
 *   COLUMN_DISPLAY_NAME → 路径最后一段
 *   COLUMN_MIME_TYPE    → 目录 ? MIME_TYPE_DIR : 扩展名查表
 *   COLUMN_SIZE         → fs.stat.size
 *   COLUMN_LAST_MODIFIED→ fs.stat.mtime * 1000（秒 → 毫秒）
 *   canRead/canWrite    → fs.accessSync(READ/WRITE)（上游查 URI grant + FLAGS，鸿蒙查实际权限位）
 *   deleteDocument      → fs.unlinkSync / fs.rmdirSync（上游 ContentResolver.delete）
 *   exists              → fs.accessSync
 *
 * 与上游的两处语义差异（已在 MR 记录）：
 *   1) 上游 canWrite 依赖 provider 上报的 FLAGS（可能是「provider 支持写」而非「当前进程可写」）；
 *      鸿蒙没有 provider 层，只能判定实际权限位，对 EhViewer 的用法（自己写自己的下载目录）等价。
 *   2) 上游 deleteDocument 对不存在的 uri 返回 false；鸿蒙捕获异常后同样返回 false。
 */

import fs from '@ohos.file.fs';
import { Contracts, DocumentColumn, MimeType } from './Contracts';
import { Utils } from './Utils';

const TAG: string = 'DocumentsContractApi19';

export class DocumentsContractApi19 {
  private constructor() {
  }

  /** 对位 DocumentsContract.isDocumentUri(context, self)：用户文档域 URI（file://docs/...）。 */
  static isDocumentUri(target: string): boolean {
    if (target === undefined || target === null || target.length === 0) {
      return false;
    }
    return Contracts.isUri(target) && Contracts.authorityOf(target) === 'docs';
  }

  /** 对位 DocumentsContractApi19.getName。 */
  static getName(target: string): string | undefined {
    return Contracts.queryForString(target, DocumentColumn.DISPLAY_NAME, undefined);
  }

  /** 原始 MIME（含目录哨兵），对位上游私有 getRawType。 */
  static getRawType(target: string): string | undefined {
    return Contracts.queryForString(target, DocumentColumn.MIME_TYPE, undefined);
  }

  /** 对位 DocumentsContractApi19.getType：目录返回 null（上游语义）。 */
  static getType(target: string): string | undefined {
    const rawType: string | undefined = DocumentsContractApi19.getRawType(target);
    return rawType === MimeType.DIR ? undefined : rawType;
  }

  static isDirectory(target: string): boolean {
    const st: fs.Stat | undefined = Contracts.statOf(target);
    return st !== undefined && st.isDirectory();
  }

  static isFile(target: string): boolean {
    const st: fs.Stat | undefined = Contracts.statOf(target);
    return st !== undefined && st.isFile();
  }

  /** 毫秒；取不到返回 -1（与上游 COLUMN_LAST_MODIFIED 缺省 -1L 一致）。 */
  static lastModified(target: string): number {
    return Contracts.queryForLong(target, DocumentColumn.LAST_MODIFIED, -1);
  }

  /**
   * 字节；取不到返回 -1（与上游 COLUMN_SIZE 缺省 -1L 一致）。
   * 方法名映射：上游 `length(Context, Uri)` → `lengthOf(target)`。
   * 原因：ArkTS/TS 里静态成员 `length` 与内建 Function.length 冲突（TS2699），不是风格选择。
   */
  static lengthOf(target: string): number {
    return Contracts.queryForLong(target, DocumentColumn.SIZE, -1);
  }

  static canRead(target: string): boolean {
    return Contracts.canRead(target);
  }

  static canWrite(target: string): boolean {
    return Contracts.canWrite(target);
  }

  /** 对位 DocumentsContractApi19.delete(context, self)：目录先递归清空再删除。 */
  static delete(target: string): boolean {
    const path: string = Contracts.normalize(target);
    const st: fs.Stat | undefined = Contracts.statOf(path);
    if (st === undefined) {
      return false;
    }
    try {
      if (st.isDirectory()) {
        return Contracts.deleteRecursively(path);
      }
      fs.unlinkSync(path);
      return true;
    } catch (e) {
      Utils.throwIfFatal(e);
      // 上游注释：Maybe user ejects tf card
      Utils.logE(TAG, `Failed to delete: ${path}`);
      return false;
    }
  }

  /** 对位 DocumentsContractApi19.exists。 */
  static exists(target: string): boolean {
    return Contracts.exists(target);
  }
}
