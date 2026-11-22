/*
 * 上游：app/src/main/java/com/hippo/ehviewer/ui/main/UserImageChange.java（268 行）
 * 目标：harmony/entry/src/main/ets/hippo/ehviewer/ui/main/UserImageChange.ets（S0211）
 *
 * 上游常量（逐个核对，不按名字推断；注意 TAKE_CAMERA/PICK_PHOTO 与两个 permission 码值不同域）：
 *   CHANGE_BACKGROUND = 0 / CHANGE_AVATAR = 1        ← 目标类型
 *   TAKE_CAMERA = 101 / PICK_PHOTO = 102             ← 选择方式
 *   REQUEST_CAMERA_PERMISSION = 1 / REQUEST_STORAGE_PERMISSION = 2
 * 上游实现 PermissionCallBack（权限回调后继续原流程）。
 *
 * Part 1（本批）：目标类型/选择方式常量、权限前置判定、两条路径（拍照 / 相册）的调度与结果裁剪。
 * Part 2 待补：裁剪界面 UI、上传接口调用、失败提示文案。
 */
import { hilog } from '@kit.PerformanceAnalysisKit';

/** 权限接口（生产实现接 @ohos.abilityAccessCtrl） */
export interface PermissionGateLike {
  hasCameraPermission(): Promise<boolean>;
  hasStoragePermission(): Promise<boolean>;
  requestCameraPermission(): void;
  requestStoragePermission(): void;
}

/** 选择器（拍照 / 相册）：成功回传图片 uri */
export interface ImagePickerLike {
  takePhoto(): Promise<string | null>;
  pickPhoto(): Promise<string | null>;
}

/** 裁剪后的上传（上游此处调上传接口，本类只定义契约） */
export interface ImageUploaderLike {
  upload(kind: number, uri: string): Promise<boolean>;
}

export class UnavailablePermissionGate implements PermissionGateLike {
  async hasCameraPermission(): Promise<boolean> { return false; }
  async hasStoragePermission(): Promise<boolean> { return false; }
  requestCameraPermission(): void {
    hilog.warn(0x0000, 'UserImageChange', '权限请求未接线: camera；后果：无法拍照更换');
  }
  requestStoragePermission(): void {
    hilog.warn(0x0000, 'UserImageChange', '权限请求未接线: storage；后果：无法从相册选择');
  }
}

export class UnavailableImagePicker implements ImagePickerLike {
  async takePhoto(): Promise<string | null> { return null; }
  async pickPhoto(): Promise<string | null> { return null; }
}

export class UnavailableImageUploader implements ImageUploaderLike {
  async upload(kind: number, uri: string): Promise<boolean> {
    hilog.warn(0x0000, 'UserImageChange', '上传未接线: kind=%{public}d；后果：图片不生效', kind);
    return false;
  }
}

export class UserImageChange {
  static readonly CHANGE_BACKGROUND: number = 0;
  static readonly CHANGE_AVATAR: number = 1;
  static readonly TAKE_CAMERA: number = 101;
  static readonly PICK_PHOTO: number = 102;
  static readonly REQUEST_CAMERA_PERMISSION: number = 1;
  static readonly REQUEST_STORAGE_PERMISSION: number = 2;

  private readonly kind: number;
  private gate: PermissionGateLike = new UnavailablePermissionGate();
  private picker: ImagePickerLike = new UnavailableImagePicker();
  private uploader: ImageUploaderLike = new UnavailableImageUploader();
  /** 上游 pending 状态：等权限回调后继续原选择方式 */
  private pendingMethod: number = -1;

  constructor(kind: number) {
    this.kind = kind;
  }

  setPermissionGate(g: PermissionGateLike): void { this.gate = g; }
  setImagePicker(p: ImagePickerLike): void { this.picker = p; }
  setUploader(u: ImageUploaderLike): void { this.uploader = u; }

  /**
   * 上游选择后先判权限：有就直接走，没有就记 pendingMethod 再请求。
   * 权限回调（上游 PermissionCallBack.onRequestPermissionsResult）→ handlePermissionResult。
   */
  chooseMethod(method: number): void {
    if (method === UserImageChange.TAKE_CAMERA) {
      this.gate.hasCameraPermission().then((ok: boolean) => {
        if (ok) {
          this.runTakePhoto();
          return;
        }
        this.pendingMethod = method;
        this.gate.requestCameraPermission();
      }).catch((e: Error) => {
        hilog.error(0x0000, 'UserImageChange', 'hasCameraPermission 失败: err=%{public}s；后果：无法确认权限，已中止',
          e.message !== undefined ? e.message : String(e));
      });
      return;
    }
    if (method === UserImageChange.PICK_PHOTO) {
      this.gate.hasStoragePermission().then((ok: boolean) => {
        if (ok) {
          this.runPickPhoto();
          return;
        }
        this.pendingMethod = method;
        this.gate.requestStoragePermission();
      }).catch((e: Error) => {
        hilog.error(0x0000, 'UserImageChange', 'hasStoragePermission 失败: err=%{public}s；后果：无法确认权限，已中止',
          e.message !== undefined ? e.message : String(e));
      });
      return;
    }
    hilog.warn(0x0000, 'UserImageChange', '未知选择方式: %{public}d；后果：无动作', method);
  }

  /** 上游权限回调：granted 才继续 pendingMethod，否则丢弃 */
  handlePermissionResult(requestCode: number, granted: boolean): void {
    const method: number = this.pendingMethod;
    this.pendingMethod = -1;
    if (!granted) {
      hilog.info(0x0000, 'UserImageChange', '权限被拒: requestCode=%{public}d；后果：不进入拍照/相册', requestCode);
      return;
    }
    if (method === UserImageChange.TAKE_CAMERA) {
      this.runTakePhoto();
      return;
    }
    if (method === UserImageChange.PICK_PHOTO) {
      this.runPickPhoto();
    }
  }

  private runTakePhoto(): void {
    this.picker.takePhoto().then((uri: string | null) => {
      if (uri === null) {
        hilog.info(0x0000, 'UserImageChange', '拍照取消或失败；后果：图片不变');
        return;
      }
      this.upload(uri);
    }).catch((e: Error) => {
      hilog.error(0x0000, 'UserImageChange', 'takePhoto 失败: err=%{public}s；后果：图片不变',
        e.message !== undefined ? e.message : String(e));
    });
  }

  private runPickPhoto(): void {
    this.picker.pickPhoto().then((uri: string | null) => {
      if (uri === null) {
        hilog.info(0x0000, 'UserImageChange', '相册未选择；后果：图片不变');
        return;
      }
      this.upload(uri);
    }).catch((e: Error) => {
      hilog.error(0x0000, 'UserImageChange', 'pickPhoto 失败: err=%{public}s；后果：图片不变',
        e.message !== undefined ? e.message : String(e));
    });
  }

  private upload(uri: string): void {
    this.uploader.upload(this.kind, uri).then((ok: boolean) => {
      if (!ok) {
        hilog.warn(0x0000, 'UserImageChange', 'upload 返回 false: kind=%{public}d；后果：图片未更换', this.kind);
      }
    }).catch((e: Error) => {
      hilog.error(0x0000, 'UserImageChange', 'upload 失败: kind=%{public}d err=%{public}s；后果：图片未更换',
        this.kind, e.message !== undefined ? e.message : String(e));
    });
  }

  getKind(): number { return this.kind; }
}
