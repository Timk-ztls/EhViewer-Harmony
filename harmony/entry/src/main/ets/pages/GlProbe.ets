// GL 探针页（Lead 维护，C-11；不写入生产 main_pages.json）
//
// 唯一职责：提供 XComponent 宿主并挂载纯色 #FF6200EE GLView，供真机 scripts/device_test_gl.ps1
// 验证 C-1 命令流 13 个 NAPI 接口与 EGL/GLES3 首帧出图。
import { hilog } from '@kit.PerformanceAnalysisKit';
import { GLView } from '../hippo/lib/glview/view/GLView';
import { GLRootViewController } from '../hippo/lib/glview/view/GLRootViewController';

const DOMAIN: number = 0x0000;
const TAG: string = 'GlProbe';

class ProbeColorView extends GLView {
  constructor(bgColor: number) {
    super();
    this.setBackgroundColor(bgColor);
  }
}

@Entry
@Component
struct GlProbe {
  @State surfaceReady: boolean = false;
  @State surfaceWidth: number = 0;
  @State surfaceHeight: number = 0;

  private xcController: XComponentController = new XComponentController();
  private controller: GLRootViewController | null = null;

  aboutToDisappear(): void {
    this.teardown();
  }

  private teardown(): void {
    const ctrl: GLRootViewController | null = this.controller;
    if (ctrl !== null) {
      ctrl.setContentPane(null);
      ctrl.release();
      this.controller = null;
    }
    this.surfaceReady = false;
  }

  build() {
    Column({ space: 8 }) {
      XComponent({
        id: 'glprobe',
        type: XComponentType.SURFACE,
        libraryname: 'native-lib',
        controller: this.xcController
      })
        .onLoad((ctx: object) => {
          this.teardown();
          this.surfaceReady = true;
          const ctrl: GLRootViewController = new GLRootViewController(ctx);
          ctrl.setContentPane(new ProbeColorView(0xFF6200EE));
          const rect = this.xcController.getXComponentSurfaceRect();
          this.surfaceWidth = Math.trunc(rect.surfaceWidth);
          this.surfaceHeight = Math.trunc(rect.surfaceHeight);
          ctrl.notifySurfaceSize(this.surfaceWidth, this.surfaceHeight);
          ctrl.start();
          ctrl.renderNow();
          this.controller = ctrl;
          hilog.info(DOMAIN, TAG, 'surface ready %{public}dx%{public}d',
            this.surfaceWidth, this.surfaceHeight);
        })
        .onDestroy(() => {
          this.teardown();
          hilog.info(DOMAIN, TAG, 'XComponent destroyed');
        })
        .width('100%')
        .layoutWeight(1)

      Text(this.surfaceReady ? $r('app.string.gallery_gl_fallback_action_close') : $r('app.string.loading'))
        .fontSize(12)
        .fontColor(this.surfaceReady ? '#FF2E7D32' : '#FF757575')
        .margin({ bottom: 8 })
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#FFFFFFFF')
  }
}
