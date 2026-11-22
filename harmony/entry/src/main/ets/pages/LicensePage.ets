import { webview } from '@kit.ArkWeb';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { ThemePalette, ThemeTokens } from '../common/theme/ThemeTokens';
import { LicenseActivity } from '../hippo/ehviewer/ui/LicenseActivity';
import { VArrowLeftDarkX24 } from '../hippo/ui/drawable/v_arrow_left_dark_x24';

const LOG_DOMAIN: number = 0x0000;
const LOG_TAG: string = 'LicensePage';

@Entry
@Component
export struct LicensePage {
  private webController: webview.WebviewController = new webview.WebviewController();
  @State loading: boolean = true;

  private palette(): ThemePalette {
    return ThemeTokens.current();
  }

  private navigateBack(): void {
    try {
      this.getUIContext().getRouter().back();
    } catch (err) {
      hilog.warn(LOG_DOMAIN, LOG_TAG, 'Router back failed: %{public}s', JSON.stringify(err));
    }
  }

  private stopWebControllerSafely(): void {
    try {
      this.webController.stop();
    } catch (err) {
      hilog.warn(LOG_DOMAIN, LOG_TAG, 'WebviewController.stop failed: %{public}s', JSON.stringify(err));
    }
  }

  aboutToDisappear(): void {
    this.stopWebControllerSafely();
  }

  build() {
    Column() {
      Row({ space: 8 }) {
        Button({ type: ButtonType.Normal }) {
          VArrowLeftDarkX24({ iconSize: 24, fillColor: this.palette().toolbarIconColor })
        }
        .width(44)
        .height(44)
        .backgroundColor(Color.Transparent)
        .onClick(() => {
          this.navigateBack();
        })

        Text($r('app.string.license'))
          .fontSize(20)
          .fontWeight(FontWeight.Medium)
          .fontColor('#FFFFFFFF')
          .layoutWeight(1)
      }
      .width('100%')
      .height(56)
      .padding({ left: 8, right: 16 })
      .backgroundColor($r('app.color.teal_500'))

      Stack() {
        Web({ src: $rawfile(LicenseActivity.ASSET_PATH), controller: this.webController })
          .width('100%')
          .height('100%')
          .javaScriptAccess(false)
          .domStorageAccess(false)
          .onPageEnd(() => {
            this.loading = false;
          })
          .onErrorReceive((event: OnErrorReceiveEvent): void => {
            this.loading = false;
            const info: string = event.error !== undefined ? event.error.getErrorInfo() : 'unknown';
            hilog.warn(LOG_DOMAIN, LOG_TAG, 'License WebView load error: %{public}s', info);
          })
          .onDisAppear(() => {
            this.stopWebControllerSafely();
          })

        if (this.loading) {
          Column() {
            LoadingProgress()
              .width(36)
              .height(36)
              .color($r('app.color.teal_500'))
          }
          .width('100%')
          .height('100%')
          .justifyContent(FlexAlign.Center)
          .hitTestBehavior(HitTestMode.None)
        }
      }
      .width('100%')
      .layoutWeight(1)
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.start_window_background'))
  }
}
