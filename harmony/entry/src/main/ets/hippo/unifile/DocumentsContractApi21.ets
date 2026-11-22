/*
 * 对位上游：app/src/main/java/com/hippo/unifile/DocumentsContractApi21.java
 *
 * 平台对位：
 *   上游 SA F（Storage Access Framework）的 documentId/treeUri 概念在鸿蒙不存在。
 *   鸿蒙的用户授权目录来自 @ohos.file.picker 的 DocumentViewPicker（返回 file://docs/... URI），
 *   其子项没有独立 documentId，子项 URI 就是「父 URI + '/' + 名字」。因此：
 *     createDocument(parent, mime, name) → 在父目录下建空文件/建目录（fs.openSync CREATE / fs.mkdirSync）
 *     buildDocumentUriUsingTree(uri, id)  → buildChildUri：字符串拼接 + toUri 规整
 *     getTreeDocumentId(uri)             → getTreeDocumentPath：URI 对应的绝对路径
 *     listFiles(uri)                     → fs.listFileSync 后逐个转 URI
 *     renameDocument(uri, name)          → fs.renameSync，返回新 URI
 *   权限：picker 授权目录在「持久化授权」(persistPermission) 之后可直接按路径读写，
 *   这一点是 URI→路径转换能成立的前提，MR 里给了验证步骤。
 */

import fs from '@ohos.file.fs';
import { Contracts, MimeType } from './Contracts';
import { DocumentsContractApi19 } from './DocumentsContractApi19';
import { Utils } from './Utils';

const TAG: string = 'DocumentsContractApi21';

export class DocumentsContractApi21 {
  private constructor() {
  }

  /**
   * 对位 DocumentsContractApi21.createFile(context, self, mimeType, displayName)。
   * 返回子项 URI；失败返回 undefined（上游返回 null）。
   */
  static createFile(parent: string, mimeType: string, displayName: string): string | undefined {
    if (mimeType === MimeType.DIR) {
      return DocumentsContractApi21.createDirectory(parent, displayName);
    }
    const childPath: string = Contracts.childOf(parent, displayName);
    try {
      // 上游 createDocument 对已存在同名文件会抛 FileAlreadyExistsException；
      // 这里保持「已存在即失败」语义，避免覆盖用户数据。
      if (Contracts.exists(childPath)) {
        Utils.logW(TAG, `createFile failed, already exists: ${childPath}`);
        return undefined;
      }
      const file: fs.File = fs.openSync(childPath, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE);
      fs.closeSync(file);
      return Contracts.toUri(childPath);
    } catch (e) {
      Utils.throwIfFatal(e);
      // 上游注释：Maybe user ejects tf card
      Utils.logE(TAG, `Failed to createFile: ${parent}/${displayName}`);
      return undefined;
    }
  }

  /** 对位 DocumentsContractApi21.createDirectory。 */
  static createDirectory(parent: string, displayName: string): string | undefined {
    const childPath: string = Contracts.childOf(parent, displayName);
    try {
      if (Contracts.exists(childPath)) {
        return undefined;
      }
      fs.mkdirSync(childPath);
      return Contracts.toUri(childPath);
    } catch (e) {
      Utils.throwIfFatal(e);
      Utils.logE(TAG, `Failed to createDirectory: ${parent}/${displayName}`);
      return undefined;
    }
  }

  /**
   * 对位 DocumentsContractApi21.prepareTreeUri：
   * 上游把 tree URI 规整成 document URI（去掉 '/tree/' 段）。鸿蒙没有 tree/document 双形态，
   * 规整只剩「去掉结尾多余斜杠」这一件事，保持单一路径形态。
   */
  static prepareTreeUri(treeUri: string): string {
    return Contracts.toUri(Contracts.normalize(treeUri));
  }

  /** 对位 DocumentsContractApi21.getTreeDocumentPath：取 URI 对应的绝对路径。 */
  static getTreeDocumentPath(documentUri: string): string {
    const path: string = Contracts.normalize(documentUri);
    if (path.length === 0) {
      throw new Error(`Invalid URI: ${documentUri}`);
    }
    return path;
  }

  /** 对位 DocumentsContractApi21.buildChildUri：父 URI + 子名 → 子 URI。 */
  static buildChildUri(uri: string, displayName: string): string {
    return Contracts.toUri(Contracts.childOf(uri, displayName));
  }

  /**
   * 对位 DocumentsContractApi21.listFiles(context, self)：
   * 返回子项 URI 列表；失败返回空数组（上游 catch 后返回空数组，非 null）。
   */
  static listFiles(self: string): string[] {
    const result: string[] = [];
    const path: string = Contracts.normalize(self);
    let names: string[] | undefined;
    try {
      names = fs.listFileSync(path, { recursion: false });
    } catch (e) {
      Utils.throwIfFatal(e);
      Utils.logE(TAG, `Failed listFiles: ${path}`);
      return result;
    }
    if (names === undefined) {
      return result;
    }
    for (const name of names) {
      result.push(Contracts.toUri(Contracts.childOf(path, name)));
    }
    return result;
  }

  /**
   * 对位 DocumentsContractApi21.renameTo(context, self, displayName)。
   * 返回新 URI；失败返回 undefined（上游返回 null）。
   */
  static renameTo(self: string, displayName: string): string | undefined {
    const oldPath: string = Contracts.normalize(self);
    const parent: string | undefined = Contracts.parentOf(oldPath);
    if (parent === undefined) {
      Utils.logE(TAG, `Failed renameTo, no parent: ${oldPath}`);
      return undefined;
    }
    const newPath: string = Contracts.childOf(parent, displayName);
    try {
      fs.renameSync(oldPath, newPath);
      return Contracts.toUri(newPath);
    } catch (e) {
      Utils.throwIfFatal(e);
      Utils.logE(TAG, `Failed renameTo: ${oldPath} -> ${displayName}`);
      return undefined;
    }
  }

  /** 便利：判定 target 是否为目录（TreeDocumentFile.isTreeUri 的底座）。 */
  static isDirectoryTarget(target: string): boolean {
    return DocumentsContractApi19.isDirectory(target);
  }
}
