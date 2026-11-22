/**
 * 迁移自 app/src/main/java/com/hippo/widget/DirExplorer.java（S0518，上游 158 行）
 *
 * 判据：**分叉（目录浏览器）→ 自写状态机 + ArkUI 列表**
 * 上游 `extends EasyRecyclerView`（受 D-022 约束不移植），核心逻辑：
 *   · `DIR_FILTER`：只接受 `isDirectory()` 的项
 *   · `PARENT_DIR` 是 **null 哨兵**，显示名 `".."`
 *   · `updateFileList()`：`listFiles(DIR_FILTER)` → 清空 → **若 `getParent() != null` 先插入父目录哨兵** →
 *     再 `Collections.addAll(files)`（顺序由 FileSort 决定，见差异）→ notifyDataSetChanged
 *   · `setCurrentFile(file)`：更新当前目录 → updateFileList → 通知 `OnChangeDirListener.onChangeDir(current)`
 *   · `onItemClick(position)`：取第 position 项；**若为父哨兵则换成 `getParentFile()`** → setCurrentFile
 *   · 初始目录：外部存储根；**未挂载或为 null 时退化为 `/`**
 *
 * ArkUI 对位：`List` + `ForEach`；文件枚举由调用方注入（`listDirs(path)`，鸿蒙侧用 fileIo/FilePicker 权限模型）。
 *
 * 差异（已登记 MR）：
 *   1) `EasyRecyclerView` → `List`（D-022）；分隔线/Ripple 选择态用 `Divider` + 默认点击态
 *   2) `FileSort` 属 storage-db（`hippo/lib/yorozuya`），本文件只接收**已排序**的列表（保持"排序一处实现"）
 *   3) `File` → 路径字符串（`string`），父目录用 `parentPath` 显式表达，不再用 null 哨兵
 */
export class DirEntry {
  name: string = '';
  path: string = '';
  /** 是否为父目录哨兵（对位 PARENT_DIR） */
  isParent: boolean = false;

  constructor(name: string, path: string, isParent: boolean) {
    this.name = name;
    this.path = path;
    this.isParent = isParent;
  }
}

export class DirExplorerState {
  /** 上游 PARENT_DIR_NAME */
  static readonly PARENT_DIR_NAME: string = '..';

  currentPath: string = '/';
  entries: DirEntry[] = [];

  /**
   * 上游 updateFileList：**父目录哨兵只在有父目录时插入**（根目录 `/` 不插入）。
   * @param dirs 已排序的子目录（调用方给；排序属 storage-db 的 FileSort）
   * @param parentPath 父目录路径；空串表示无父目录
   */
  buildEntries(dirs: string[], parentPath: string): DirEntry[] {
    const out: DirEntry[] = [];
    if (parentPath.length > 0) {
      out.push(new DirEntry(DirExplorerState.PARENT_DIR_NAME, parentPath, true));
    }
    for (let i = 0; i < dirs.length; i++) {
      const p: string = dirs[i];
      const name: string = DirExplorerState.baseName(p);
      out.push(new DirEntry(name, p, false));
    }
    this.entries = out;
    return out;
  }

  /** 上游 setCurrentFile + updateFileList 的净效果（返回是否变化） */
  setCurrentFile(path: string, dirs: string[], parentPath: string): boolean {
    this.currentPath = path;
    this.buildEntries(dirs, parentPath);
    return true;
  }

  /**
   * 上游 onItemClick(position)：取第 position 项，父哨兵已被 buildEntries 换成真实父路径，
   * 因此这里只需取出 path。越界返回 null（上游会 IndexOutOfBounds，此处降级）。
   */
  entryAt(position: number): DirEntry | null {
    if (position < 0 || position >= this.entries.length) {
      return null;
    }
    return this.entries[position];
  }

  /** 取路径最后一段作为显示名（对位 File.getName()） */
  static baseName(path: string): string {
    if (path.length === 0) {
      return '';
    }
    let end: number = path.length;
    while (end > 1 && path.charAt(end - 1) === '/') {
      end = end - 1;
    }
    const trimmed: string = path.substring(0, end);
    const idx: number = trimmed.lastIndexOf('/');
    return idx < 0 ? trimmed : trimmed.substring(idx + 1);
  }
}