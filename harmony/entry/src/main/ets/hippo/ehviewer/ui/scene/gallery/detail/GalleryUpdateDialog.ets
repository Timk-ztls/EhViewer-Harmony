/*
 * 上游：app/src/main/java/com/hippo/ehviewer/ui/scene/gallery/detail/GalleryUpdateDialog.java
 *       （inventory S0233，68 行）
 * 目标：harmony/entry/src/main/ets/hippo/ehviewer/ui/scene/gallery/detail/GalleryUpdateDialog.ets
 *
 * 背景：详情页发现**新版本**时弹的两个对话框：
 *   ① `showSelectDialog(galleryDetail)`：单选列表，列出各版本的 versionName，选中后**跳转**到该版本
 *   ② `showChooseDialog(url)`：三按钮 —— 取消 / 另存为新 / 覆盖旧
 *
 * ── 上游行为逐条对照 ────────────────────────────────────────────────────────
 * 字段：`detailScene: GalleryDetailScene` / `context` / `galleryDetail` / `dialog` / `choseDialog` /
 *       `public boolean autoDownload = false`
 * `showSelectDialog(gd)`:
 *   ① `if (gd === this.galleryDetail && dialog != null) { dialog.setTitle(new_version); dialog.show(); }`
 *      —— **注意：这里没有 return**，接着还会重建 dialog（见「关键行为」1）
 *   ② `this.galleryDetail = gd`
 *   ③ 单选列表 = `gd.getUpdateVersionName()`（= 各 `newVersions[i].versionName`），默认选中 -1
 *   ④ 选中回调：`dialog.dismiss()` → `createAnnouncerFromClipboardUrl(gd.newVersions[index].versionUrl)`
 *      → `detailScene.startScene(announcer)`
 *   ⑤ `dialog.setTitle(@string/new_version)` + `show()`
 * `showChooseDialog(url)`:
 *   ① `if (choseDialog != null) choseDialog.show();`   —— **同样没有 return**（见「关键行为」2）
 *   ② 标题 `@string/gallery_update_dialog_title` / 内容 `@string/gallery_update_dialog_message`
 *   ③ 中性按钮 `@string/cancel` → `dialog.dismiss()`
 *   ④ 负向按钮 `@string/gallery_update_download_as_new` → `autoDownload = true; detailScene.startDownloadAsNew(url)`
 *   ⑤ 正向按钮 `@string/gallery_update_override_old` → `detailScene.startUpdateDownload(url)`
 *
 * ── 关键行为（照搬上游，不要"顺手修"）──────────────────────────────────────
 * 1. `showSelectDialog` 里第一段 `if (...) { show(); }` **没有 return** —— 语义是"先把已存在的对话框
 *    显示出来，然后照常重建一个新的"。看着像 bug，但**改掉会改变行为**（多一次 show / 少一次重建）。
 *    本实现用 `reusedExisting` 标记如实记录，不吞掉。
 * 2. `showChooseDialog` 里 `if (choseDialog != null) choseDialog.show();` 同理没有 return。
 * 3. **`autoDownload` 是 public 可变字段**，只在"另存为新"分支置 true，且**不重置** ——
 *    它是跨多次调用的状态（上游如此）。本实现保留为可读写字段。
 *
 * ── 平台差异（依赖倒置 + 对话框载体）────────────────────────────────────────
 * 1. **上游直接依赖具体类 `GalleryDetailScene`**（还 import 了 `MainActivity` / `EnterGalleryDetailTransaction`
 *    但代码里未使用 —— 那是历史残留 import）。鸿蒙侧 `GalleryDetailScene` **尚未移植**，
 *    若等待它就会一直阻塞。因此按**依赖倒置**：本文件只声明它实际调用的三个方法
 *    （`startScene` / `startDownloadAsNew` / `startUpdateDownload`）为接口 `GalleryDetailSceneHost`，
 *    Scene 落地后 `implements` 即可接入。
 *    —— 与 Lead 处理 `PageImageDownloader` 的做法一致：**接口下沉到调用方与实现方都已依赖的最底层**。
 * 2. **`AlertDialog` 在 ArkUI 是声明式的**（`AlertDialog.show({...})` / `CustomDialogController`），
 *    不是"builder → create → show"的命令式对象。所以本类不"弹窗"，
 *    而是**产出对话框描述**（`UpdateSelectDialogSpec` / `UpdateChooseDialogSpec`），
 *    由 Scene 用 ArkUI 的对话框 API 渲染；上游的 `dialog`/`choseDialog` 句柄用
 *    `selectDialogVisible` / `chooseDialogVisible` 两个标记表达（对应上游的 `!= null` 与 `show()`）。
 * 3. `createAnnouncerFromClipboardUrl(url)` 是上游 `ClipboardUtil` 的静态导入（本仓库未移植该工具）。
 *    ArkTS 侧改为**回调注入** `resolveAnnouncer`：调用方传入"把 versionUrl 解析成 Announcer"的实现
 *    （ClipboardUtil 落地后一行接上），避免本类依赖未移植模块。
 *
 * ── 关联 ────────────────────────────────────────────────────────────────────
 * - 数据：`GalleryDetail.newVersions: NewVersion[]`（含 `versionName` / `versionUrl`）、`GalleryDetail.getNewGalleryDetail(i)`
 * - 字符串：`@string/new_version` / `gallery_update_dialog_title` / `gallery_update_dialog_message` /
 *           `cancel` / `gallery_update_download_as_new` / `gallery_update_override_old`
 * - 转场：`EnterGalleryDetailTransaction`（S0238，同批已移植）
 */

import { GalleryDetail } from '../../../../client/data/GalleryDetail';
import { Announcer } from '../../../../../scene/Announcer';

/**
 * 本对话框对宿主 Scene 的最小依赖（依赖倒置，见文件头「平台差异」1）。
 * 上游直接持有 `GalleryDetailScene`；这里只声明它实际调用的三个方法。
 */
export interface GalleryDetailSceneHost {
  /** 上游 `detailScene.startScene(announcer)` */
  startScene(announcer: Announcer): void;
  /** 上游 `detailScene.startDownloadAsNew(url)`（"另存为新"） */
  startDownloadAsNew(url: string): void;
  /** 上游 `detailScene.startUpdateDownload(url)`（"覆盖旧"） */
  startUpdateDownload(url: string): void;
}

/** ① 单选版本对话框的描述（上游 `dialog` 那个 AlertDialog） */
export class UpdateSelectDialogSpec {
  /** 标题 `@string/new_version` */
  title: ResourceStr = $r('app.string.new_version');
  /** 单选项文本 = `GalleryDetail.getUpdateVersionName()`（各 newVersions[i].versionName） */
  items: string[] = [];
  /** 默认选中项（上游传 -1 = 不选中） */
  checkedIndex: number = -1;
  /** 上游"已存在旧对话框时先 show 一次"的标记（见文件头「关键行为」1） */
  reusedExisting: boolean = false;
}

/** ② 三按钮选择对话框的描述（上游 `choseDialog`） */
export class UpdateChooseDialogSpec {
  title: ResourceStr = $r('app.string.gallery_update_dialog_title');
  message: ResourceStr = $r('app.string.gallery_update_dialog_message');
  /** 中性按钮（取消） */
  neutralButtonText: ResourceStr = $r('app.string.cancel');
  /** 负向按钮（另存为新） */
  negativeButtonText: ResourceStr = $r('app.string.gallery_update_download_as_new');
  /** 正向按钮（覆盖旧） */
  positiveButtonText: ResourceStr = $r('app.string.gallery_update_override_old');
  /** 上游"已存在旧对话框时先 show 一次"的标记（见文件头「关键行为」2） */
  reusedExisting: boolean = false;
}

export class GalleryUpdateDialog {
  private detailScene: GalleryDetailSceneHost;
  /** 上游 `galleryDetail`：最近一次传入的详情（用于"同一对象则复用对话框"的判断） */
  private galleryDetail: GalleryDetail | null = null;
  /** 上游 `dialog != null` 的等价物 */
  private selectDialogVisible: boolean = false;
  /** 上游 `choseDialog != null` 的等价物 */
  private chooseDialogVisible: boolean = false;
  /** 上游 `public boolean autoDownload`：只在"另存为新"分支置 true，且不重置（跨调用状态） */
  autoDownload: boolean = false;
  /** 把 versionUrl 解析成 Announcer（上游 ClipboardUtil.createAnnouncerFromClipboardUrl 的注入点） */
  private resolveAnnouncer: (url: string) => Announcer;

  constructor(detailScene: GalleryDetailSceneHost, resolveAnnouncer: (url: string) => Announcer) {
    this.detailScene = detailScene;
    this.resolveAnnouncer = resolveAnnouncer;
  }

  /**
   * 上游 `showSelectDialog(galleryDetail)`：
   * 产出"单选版本列表"描述；点选某一项时调用 `selectVersion(index)`。
   */
  showSelectDialog(galleryDetail: GalleryDetail): UpdateSelectDialogSpec {
    const spec = new UpdateSelectDialogSpec();
    // 上游 ①：同一对象且已有对话框 → 先 show 一次（**没有 return**，接着照样重建）
    if (this.galleryDetail === galleryDetail && this.selectDialogVisible) {
      spec.reusedExisting = true;   // 渲染方据此先 show 旧对话框（等价上游 dialog.show()）
    }
    // 上游 ②：记住当前详情
    this.galleryDetail = galleryDetail;
    // 上游 ③：单选项 = getUpdateVersionName()（newVersions[i].versionName）；默认 -1
    const versions = galleryDetail.newVersions;
    const names: string[] = [];
    if (versions !== null) {
      for (let i = 0; i < versions.length; i++) {
        names.push(versions[i].versionName);
      }
    }
    spec.items = names;
    spec.checkedIndex = -1;
    // 上游 ⑤：setTitle + show → 渲染方负责
    this.selectDialogVisible = true;
    return spec;
  }

  /**
   * 上游单选列表的点击回调：
   * `dialog.dismiss()` → 解析 announcer → `detailScene.startScene(announcer)`。
   * 返回 false 表示该 index 没有对应版本（上游会因为 `newVersions[index]` 越界抛异常，
   * 这里显式返回 false 并由调用方决定如何处理，**不静默**）。
   */
  selectVersion(index: number): boolean {
    const gd = this.galleryDetail;
    if (gd === null) {
      return false;
    }
    const versions = gd.newVersions;
    if (versions === null || index < 0 || index >= versions.length) {
      return false;
    }
    // 上游：dialog.dismiss()
    this.selectDialogVisible = false;
    // 上游：createAnnouncerFromClipboardUrl(galleryDetail.newVersions[index].versionUrl)
    const announcer: Announcer = this.resolveAnnouncer(versions[index].versionUrl);
    // 上游：detailScene.startScene(announcer)
    this.detailScene.startScene(announcer);
    return true;
  }

  /** 上游 `showChooseDialog(url)`：产出三按钮对话框描述；按钮回调见下面三个方法 */
  showChooseDialog(url: string): UpdateChooseDialogSpec {
    const spec = new UpdateChooseDialogSpec();
    // 上游 ①：已有 chooseDialog → 先 show（**没有 return**）
    if (this.chooseDialogVisible) {
      spec.reusedExisting = true;
    }
    // 上游 ②~⑤：标题/内容/三个按钮（文案见类定义）；show() 由渲染方执行
    this.chooseDialogVisible = true;
    this.pendingUrl = url;
    return spec;
  }

  /** 中性按钮（取消）：上游 `dialog.dismiss()` */
  onChooseCancel(): void {
    this.chooseDialogVisible = false;
    this.pendingUrl = '';
  }

  /** 负向按钮（另存为新）：`autoDownload = true; detailScene.startDownloadAsNew(url)` */
  onChooseDownloadAsNew(): void {
    this.autoDownload = true;
    const url = this.pendingUrl;
    this.chooseDialogVisible = false;
    this.detailScene.startDownloadAsNew(url);
  }

  /** 正向按钮（覆盖旧）：`detailScene.startUpdateDownload(url)` */
  onChooseOverrideOld(): void {
    const url = this.pendingUrl;
    this.chooseDialogVisible = false;
    this.detailScene.startUpdateDownload(url);
  }

  /** 上游 `showChooseDialog(url)` 的 url 参数（按钮回调时要用，上游用闭包捕获） */
  private pendingUrl: string = '';
}
