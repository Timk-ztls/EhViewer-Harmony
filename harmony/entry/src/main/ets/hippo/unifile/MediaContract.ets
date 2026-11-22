/*
 * 对位上游：app/src/main/java/com/hippo/unifile/MediaContract.java
 *
 * 上游用 MediaStore.MediaColumns 的 DISPLAY_NAME / MIME_TYPE / DATE_MODIFIED / SIZE 查媒体库。
 * 鸿蒙对位：
 *   - 媒体库在鸿蒙是 `@ohos.file.photoAccessHelper`，其属性名是 photoAccessHelper.PhotoKeys
 *     （DISPLAY_NAME / DATE_MODIFIED / SIZE / MIME_TYPE），且只能操作「图片/视频资产」，
 *     没有 Android MediaStore 那种「任意 content:// 都能查」的能力。
 *   - 本抽象层只做只读属性查询，统一由 Contracts 的 stat 分派实现（语义等价：名字/大小/时间/类型），
 *     不去调 photoAccessHelper —— 因为 MediaFile 拿到的 target 既可能是媒体资产 URI，
 *     也可能是普通文件 URI，stat 对两者都成立。
 *   - TODO(平台)：若后续要做「写回媒体库」（保存图片到相册），必须换成
 *     photoAccessHelper.getAssets + PhotoAsset.set 系列，届时在此文件加专用方法，不要在 stat 上硬凑。
 *
 * 列名常量保持上游 MediaColumns 的字面值，便于与上游调用点对照。
 */

import fs from '@ohos.file.fs';
import fileUri from '@ohos.file.fileuri';
import { Contracts, DocumentColumn } from './Contracts';
import { Utils } from './Utils';

export class MediaColumn {
  static readonly DISPLAY_NAME: string = '_display_name';
  static readonly MIME_TYPE: string = 'mime_type';
  static readonly DATE_MODIFIED: string = 'date_modified';
  static readonly SIZE: string = '_size';
}

export class MediaContract {
  private constructor() {
  }

  /** 对位 MediaContract.getName。 */
  static getName(target: string): string | undefined {
    return Contracts.queryForString(target, DocumentColumn.DISPLAY_NAME, undefined);
  }

  /** 对位 MediaContract.getType。 */
  static getType(target: string): string | undefined {
    return Contracts.queryForString(target, DocumentColumn.MIME_TYPE, undefined);
  }

  /** 对位 MediaContract.lastModified（毫秒；取不到返回 0，与上游默认值一致）。 */
  static lastModified(target: string): number {
    return Contracts.queryForLong(target, DocumentColumn.LAST_MODIFIED, 0);
  }

  /**
   * 对位 MediaContract.length（字节；取不到返回 0，与上游默认值一致）。
   * 方法名映射：`length` → `lengthOf`，因静态成员 `length` 与内建 Function.length 冲突（TS2699）。
   */
  static lengthOf(target: string): number {
    return Contracts.queryForLong(target, DocumentColumn.SIZE, 0);
  }

  /**
   * 对位 MediaFile.isMediaUri(context, uri)：上游判断标准是「媒体库能查到 DISPLAY_NAME」。
   * 鸿蒙侧通过 FileUri.path 或 openSync + statSync(fd) 探测可读非目录目标，
   * 避免直接把 'file://media/...' 错剥为不存在的 '/...' 路径。
   */
  static isMediaTarget(target: string): boolean {
    if (target === undefined || target === null || target.length === 0) {
      return false;
    }
    if (!target.startsWith('file://media/')) {
      let resolved: string = target;
      if (Contracts.isUri(target)) {
        try {
          const parsedPath: string = new fileUri.FileUri(target).path;
          resolved = parsedPath.length > 0 ? parsedPath : Contracts.toPath(target);
        } catch (e) {
          Utils.throwIfFatal(e);
          resolved = Contracts.toPath(target);
        }
      }
      try {
        const st: fs.Stat = fs.statSync(resolved);
        return !st.isDirectory();
      } catch (e) {
        Utils.throwIfFatal(e);
      }
    }
    let file: fs.File | undefined = undefined;
    try {
      file = fs.openSync(target, fs.OpenMode.READ_ONLY);
      const st: fs.Stat = fs.statSync(file.fd);
      return !st.isDirectory();
    } catch (e) {
      Utils.throwIfFatal(e);
      return false;
    } finally {
      if (file !== undefined) {
        try {
          fs.closeSync(file);
        } catch (e2) {
          Utils.throwIfFatal(e2);
        }
      }
    }
  }
}
