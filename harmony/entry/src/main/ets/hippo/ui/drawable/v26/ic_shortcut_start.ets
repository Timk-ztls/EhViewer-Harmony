/**
 * 重绘自 app/src/main/res/drawable-v26/ic_shortcut_start.xml  （inventory S0865，上游 5 行）
 * 上游节点：<adaptive-icon>
 * 生成方式：XML Drawable（shape/selector/vector）→ ArkUI Shape/状态样式（变体: v26）；换算规则见 hippo/drawable/DrawableSpec.ets 文件头
 * 上游 <adaptive-icon>：background=@color/shortcut_bg foreground=@drawable/ic_play_arrow_108dp
 * ArkUI：Stack 两层合成（background 铺满 + foreground 铺满）。
 * 差异：Android 自适应图标的遮罩形状（圆/方/泪滴）由启动器决定，鸿蒙由 AppScope 图标配置决定，本组件只负责图层合成。
 */
import { DrawablePalette } from '../../../drawable/DrawablePalette';
import { IcPlayArrow108dp } from '../ic_play_arrow_108dp';

@Component
export struct IcShortcutStart {
  @Prop iconSize: number = 108;
  build() {
    Stack() {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor(DrawablePalette.SHORTCUT_BG)
      IcPlayArrow108dp({ iconSize: this.iconSize })
    }
    .width(this.iconSize)
    .height(this.iconSize)
  }
}