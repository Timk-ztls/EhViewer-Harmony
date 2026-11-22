/*
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 *
 * ── HarmonyOS 移植记录 ──────────────────────────────────────────────────────
 * 条目   : S0035   上游: com/hippo/ehviewer/AppConfig.java（220 行）
 * 目标   : harmony/entry/src/main/ets/hippo/ehviewer/AppConfig.ets
 *
 * 【为什么这个文件是 storage-db 的硬依赖】上游 `getDefaultDownloadDir()` 在**本类**，
 * 不在 Settings（Lead 最初误记为 Settings，已纠正）。storage-db 的 DownloadDirProvider
 * 注入点应按本类的 `getDefaultDownloadDir()` 对接。
 *
 * 平台差异：
 *  1. **`java.io.File` → `string` 路径**（与 FileUtils 全批一致）；返回值 `File | null` →
 *     `string | null`（C-13：可空一律 `T | null`，不用 undefined）。
 *  2. **`Environment.getExternalStorageDirectory()`（/sdcard）在鸿蒙三方应用不可用**：
 *     改用应用沙箱 `context.filesDir` 作为 app root，子结构保持上游同名
 *     （`<filesDir>/EhViewer/...` 的 `EhViewer` 层保留，便于与上游目录树对照）。
 *     外部共享目录若将来需要，应走 SAF（`@ohos.file.picker`），属另一条决策。
 *  3. `Context` → `common.Context`；必须启动时 `AppConfig.initialize(context)` 注入一次
 *     （非上游 API：ArkTS 拿不到全局 Context）。未 initialize 时所有目录 getter 返回 null，
 *     **不抛异常**（避免启动竞态崩），可用 `isInitialized()` 判定。
 *  4. `File.lastModified()` → `fs.statSync(path).mtime`（秒级，需 ×1000 转毫秒）。
 *  5. `IoThreadPoolExecutor.getInstance().execute(...)`（删除过期 parse error 文件）→
 *     改为 fire-and-forget 的 `Promise.resolve().then(...)`（不阻塞调用方），
 *     并发保护用 `sDeletingOldParseErrorFiles` 布尔（ArkTS 单 VM，无需锁对象）。
 *  6. `saveParseErrorBody(ParseException e)` **未移植**：`ParseException` 是 net-parse 的
 *     `ehviewer/client/exception/ParseException`（需 `getMessage()/getBody()`），该类未落地前
 *     写它会留下编译不过的 import。等 net-parse 落地后补（已在 MR 标注）。
 *  7. `synchronized` 块 → 无锁（方案 §5-4：单 VM 内无共享内存线程）。
 */

import fs from '@ohos.file.fs';
import common from '@ohos.app.ability.common';
import { FileUtils } from '../lib/yorozuya/FileUtils';

export class AppConfig {

  private static readonly APP_DIRNAME: string = 'EhViewer';
  private static readonly DOWNLOAD: string = 'download';
  private static readonly TEMP: string = 'temp';
  private static readonly ARCHIVER: string = 'archiver';
  private static readonly IMAGE: string = 'image';
  private static readonly PARSE_ERROR: string = 'parse_error';
  private static readonly LOGCAT: string = 'logcat';
  private static readonly DATA: string = 'data';
  private static readonly CRASH: string = 'crash';

  private static sFilesDir: string | null = null;
  private static sCacheDir: string | null = null;
  private static sDeletingOldParseErrorFiles: boolean = false;

  /** 注入 Context（非上游 API，见文件头差异 3） */
  static initialize(context: common.Context): void {
    AppConfig.sFilesDir = context.filesDir;
    AppConfig.sCacheDir = context.cacheDir;
  }

  static isInitialized(): boolean {
    return AppConfig.sFilesDir !== null;
  }

  /**
   * 对应上游 getExternalAppDir()：<外部存储>/EhViewer（见差异 2，实为沙箱 filesDir 下）
   */
  static getExternalAppDir(): string | null {
    if (AppConfig.sFilesDir === null) {
      return null;
    }
    const dir: string = `${AppConfig.sFilesDir}/${AppConfig.APP_DIRNAME}`;
    return FileUtils.ensureDirectory(dir) ? dir : null;
  }

  /**
   * mkdirs and get
   */
  static getDirInExternalAppDir(filename: string): string | null {
    const appFolder: string | null = AppConfig.getExternalAppDir();
    if (appFolder === null) {
      return null;
    }
    const dir: string = `${appFolder}/${filename}`;
    return FileUtils.ensureDirectory(dir) ? dir : null;
  }

  static getFileInExternalAppDir(filename: string): string | null {
    const appFolder: string | null = AppConfig.getExternalAppDir();
    if (appFolder === null) {
      return null;
    }
    const file: string = `${appFolder}/${filename}`;
    return FileUtils.ensureFile(file) ? file : null;
  }

  /** storage-db 的 DownloadDirProvider 注入点要对接的就是这个方法 */
  static getDefaultDownloadDir(): string | null {
    return AppConfig.getDirInExternalAppDir(AppConfig.DOWNLOAD);
  }

  static getExternalTempDir(): string | null {
    return AppConfig.getDirInExternalAppDir(AppConfig.TEMP);
  }

  static getExternalArchiverDir(): string | null {
    return AppConfig.getDirInExternalAppDir(AppConfig.ARCHIVER);
  }

  static getExternalImageDir(): string | null {
    return AppConfig.getDirInExternalAppDir(AppConfig.IMAGE);
  }

  static getExternalParseErrorDir(): string | null {
    return AppConfig.getDirInExternalAppDir(AppConfig.PARSE_ERROR);
  }

  static getExternalLogcatDir(): string | null {
    return AppConfig.getDirInExternalAppDir(AppConfig.LOGCAT);
  }

  static getExternalDataDir(): string | null {
    return AppConfig.getDirInExternalAppDir(AppConfig.DATA);
  }

  static getExternalCrashDir(): string | null {
    return AppConfig.getDirInExternalAppDir(AppConfig.CRASH);
  }

  /** 对应上游 getTempDir()：<cacheDir>/temp */
  static getTempDir(): string | null {
    const cacheDir: string | null = AppConfig.sCacheDir;
    if (cacheDir === null) {
      return null;
    }
    const dir: string = `${cacheDir}/${AppConfig.TEMP}`;
    return FileUtils.ensureDirectory(dir) ? dir : null;
  }

  /** 对应上游 getArchiverDir()：<cacheDir>/archiver */
  static getArchiverDir(): string | null {
    const cacheDir: string | null = AppConfig.sCacheDir;
    if (cacheDir === null) {
      return null;
    }
    const dir: string = `${cacheDir}/${AppConfig.ARCHIVER}`;
    return FileUtils.ensureDirectory(dir) ? dir : null;
  }

  static createTempFile(): string | null {
    const parent: string | null = AppConfig.getTempDir();
    if (parent === null) {
      return null;
    }
    return FileUtils.createTempFile(parent);
  }

  /** 对应上游 getFilesDir(String name)：<filesDir>/<name> */
  static getFilesDir(name: string): string | null {
    const filesDir: string | null = AppConfig.sFilesDir;
    if (filesDir === null) {
      return null;
    }
    const dir: string = `${filesDir}/${name}`;
    return FileUtils.ensureDirectory(dir) ? dir : null;
  }

  /**
   * 对应上游 deleteOldParseErrorFiles()：删掉 3 天前的 parse_error 文件。
   * 上游丢给 IoThreadPoolExecutor（后台线程）；ArkTS 侧改为不阻塞调用方的异步执行
   * （文件头差异 5：并发保护用布尔，无锁）。
   */
  static deleteOldParseErrorFiles(): void {
    const dir: string | null = AppConfig.getExternalParseErrorDir();
    if (dir === null) {
      return;
    }
    if (!FileUtils.ensureDirectory(dir)) {
      return;
    }
    if (AppConfig.sDeletingOldParseErrorFiles) {
      return;
    }
    AppConfig.sDeletingOldParseErrorFiles = true;

    const dirPath: string = dir;
    Promise.resolve().then(() => {
      try {
        const names: string[] = fs.listFileSync(dirPath);
        const threeDaysAgo: number = Date.now() - 3 * 24 * 60 * 60 * 1000;
        for (let i = 0; i < names.length; i++) {
          const path: string = `${dirPath}/${names[i]}`;
          try {
            const st: fs.Stat = fs.statSync(path);
            // mtime 单位是秒（见差异 4）
            if (st.isFile() && st.mtime * 1000 < threeDaysAgo) {
              fs.unlinkSync(path);
            }
          } catch (e) {
            // 单个文件失败不影响其余
          }
        }
      } catch (e) {
        // 目录读取失败：上游此处 catch OutOfMemoryError 后 dir.delete()，ArkTS 侧保持不崩
      } finally {
        AppConfig.sDeletingOldParseErrorFiles = false;
      }
    });
  }
}
