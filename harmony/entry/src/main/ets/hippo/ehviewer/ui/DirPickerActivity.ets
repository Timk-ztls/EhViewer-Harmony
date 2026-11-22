/*
 * 上游：app/src/main/java/com/hippo/ehviewer/ui/DirPickerActivity.java（158 行）
 * 目标：harmony/entry/src/main/ets/hippo/ehviewer/ui/DirPickerActivity.ets（S0195）
 *
 * 上游事实：extends ToolbarActivity
 *   KEY_FILE_URI = "file_uri" / KEY_FILE_PATH = "file_path"   ← 进出参
 *   字段 mPath(当前路径显示) / mDirExplorer(目录浏览) / mDefault(恢复默认按钮) / mOk(确定按钮)
 *   onInit 从 intent 取 KEY_FILE_URI；onRestore 从 savedInstanceState 取 KEY_FILE_PATH
 * 语义：选目录 → 路径回写 → 结果带回调用方。
 */
import { hilog } from '@kit.PerformanceAnalysisKit';
import { SceneArgs } from '../../scene/SceneTypes';

/** 目录浏览（上游 DirExplorer） */
export interface DirectoryExplorerLike {
  /** 列出当前目录下的子目录（只列目录，不列文件） */
  listDirectories(path: string): Promise<string[]>;
  /** 路径是否可写（上游不校验，但落盘前需要；失败按不可写处理） */
  isWritable(path: string): Promise<boolean>;
}

export class UnavailableDirectoryExplorer implements DirectoryExplorerLike {
  async listDirectories(path: string): Promise<string[]> {
    hilog.warn(0x0000, 'DirPickerActivity', 'listDirectories 未接线: path=%{public}s；后果：目录列表为空', path);
    return [];
  }
  async isWritable(path: string): Promise<boolean> {
    return false;
  }
}

export class DirPickerActivity {
  static readonly KEY_FILE_URI: string = 'file_uri';
  static readonly KEY_FILE_PATH: string = 'file_path';

  private explorer: DirectoryExplorerLike = new UnavailableDirectoryExplorer();
  private currentPath: string = '';
  private entries: string[] = [];
  private loading: boolean = false;

  setExplorer(e: DirectoryExplorerLike): void { this.explorer = e; }

  /** 上游 onInit / onRestore：URI 优先，其次上次保存的路径 */
  init(args: SceneArgs | null): void {
    if (args !== null) {
      const uri: Object | undefined = args.get(DirPickerActivity.KEY_FILE_PATH);
      if (uri !== undefined && typeof uri === 'string') {
        this.currentPath = uri as string;
      }
    }
    this.refresh();
  }

  getCurrentPath(): string { return this.currentPath; }
  getEntries(): string[] { return this.entries; }
  isLoading(): boolean { return this.loading; }

  /** 上游 DirExplorer 的目录刷新 */
  refresh(): void {
    if (this.loading) {
      return;
    }
    this.loading = true;
    this.explorer.listDirectories(this.currentPath).then((list: string[]) => {
      this.loading = false;
      this.entries = list;
    }).catch((e: Error) => {
      this.loading = false;
      hilog.error(0x0000, 'DirPickerActivity', 'listDirectories failed: path=%{public}s err=%{public}s；后果：目录列表停留在上一状态',
        this.currentPath, e.message !== undefined ? e.message : String(e));
    });
  }

  /** 进入子目录（上游点击目录项） */
  enter(path: string): void {
    this.currentPath = path;
    this.refresh();
  }

  /** 上游返回上级：到根就不再上（上游同样停在根） */
  goUp(): void {
    const idx: number = this.currentPath.lastIndexOf('/');
    if (idx <= 0) {
      return;
    }
    this.currentPath = this.currentPath.substring(0, idx);
    this.refresh();
  }

  /** 上游 mDefault 按钮：回到默认目录（由调用方注入，不在此硬编码路径） */
  resetToDefault(defaultPath: string): void {
    this.currentPath = defaultPath;
    this.refresh();
  }

  /**
   * 上游 mOk：把当前路径作为结果回传。不可写时**不**回传（上游会让用户继续选）。
   */
  confirm(): Promise<string | null> {
    return this.explorer.isWritable(this.currentPath).then((ok: boolean) => {
      if (!ok) {
        hilog.warn(0x0000, 'DirPickerActivity', 'confirm: 目录不可写 path=%{public}s；后果：不返回结果，停留在选择页',
          this.currentPath);
        return null;
      }
      return this.currentPath;
    }).catch((e: Error) => {
      hilog.error(0x0000, 'DirPickerActivity', 'isWritable failed: path=%{public}s err=%{public}s；后果：不返回结果',
        this.currentPath, e.message !== undefined ? e.message : String(e));
      return null;
    });
  }
}
