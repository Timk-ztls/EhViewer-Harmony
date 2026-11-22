/**
 * 迁移自 app/src/main/java/com/hippo/reveal/RevealLinearLayout.java（inventory S0453，上游 73 行）
 *
 * 上游与 RevealView 的**唯一区别**是宿主：LinearLayout 而不是 View。
 *   draw(canvas)：mReveal → save() → Path.addCircle → clipPath → super.draw() → restoreToCount()
 *   init()：不支持硬件圆形揭示时才 setWillNotDraw(false)（保证走软件层裁剪）
 *   setRevealEnable / setReveal → invalidate()
 *
 * ArkUI 对位：
 *   宿主 = Column(vertical=true) / Row(vertical=false)（对位 LinearLayout 的 orientation）
 *   裁剪 = `.clipShape(new Path({ commands }))`，与 RevealView 完全同一套（复用 RevealController）
 *   init() 里的 setWillNotDraw 在 ArkUI 无对应概念：ArkUI 的 clipShape 恒生效，无硬件层限制。
 *
 * 差异：ArkUI 的 LinearLayout 等价物没有 weight 之外的测量回调；如需"子项按权重分配"，
 *      用 Column/Row 的 `layoutWeight`（已在文件尾注释给出用法），不影响裁剪行为。
 */
import { RevealController } from './RevealView';

@Component
export struct RevealLinearLayout {
  controller: RevealController = new RevealController();
  /** 对位 LinearLayout 的 android:orientation，默认 vertical */
  @Prop vertical: boolean = true;
  @BuilderParam content: () => void = this.empty;
  @State clipCmd: string = 'M0,0 L10000,0 L10000,10000 L0,10000 Z';

  @Builder
  empty(): void {
  }

  aboutToAppear(): void {
    this.controller.attach(() => {
      this.clipCmd = this.controller.clipCommands();
    });
  }

  aboutToDisappear(): void {
    this.controller.detach();
  }

  build() {
    Column() {
      if (this.vertical) {
        Column() {
          this.content()
        }
        .width('100%')
      } else {
        Row() {
          this.content()
        }
        .width('100%')
      }
    }
    .width('100%')
    .height('100%')
    .clipShape(new Path({ commands: this.clipCmd }))
    .onAreaChange((oldValue: Area, newValue: Area) => {
      this.controller.onSizeChanged(newValue.width as number, newValue.height as number);
    })
  }
}

// 用法（对位 LinearLayout 的 layout_weight）：
//   RevealLinearLayout({ controller: this.ctrl }) {
//     Row().layoutWeight(1).width('100%')
//     Row().layoutWeight(2).width('100%')
//   }
