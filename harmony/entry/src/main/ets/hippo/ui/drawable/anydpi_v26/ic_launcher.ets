/**
 * 重绘自 app/src/main/res/mipmap-anydpi-v26/ic_launcher.xml  （inventory S0892，上游 5 行）
 * 上游节点：<adaptive-icon>
 * 生成方式：XML Drawable（shape/selector/vector）→ ArkUI Shape/状态样式（变体: anydpi-v26）；换算规则见 hippo/drawable/DrawableSpec.ets 文件头
 * 上游 <adaptive-icon>：background=@mipmap/ic_launcher_background foreground=@mipmap/ic_launcher_foreground
 * ArkUI：Stack 两层合成（background 铺满 + foreground 铺满）。
 * 差异：Android 自适应图标的遮罩形状（圆/方/泪滴）由启动器决定，鸿蒙由 AppScope 图标配置决定，本组件只负责图层合成。
 */


@Component
export struct IcLauncher {
  @Prop iconSize: number = 108;
  /** 上游 background（@mipmap 位图，由 ui-scene 的 resources 移植后传入 $r('app.media.xxx')） */
  @Prop backgroundSrc: ResourceStr = '';
  /** 上游 foreground（@mipmap 位图，同上） */
  @Prop foregroundSrc: ResourceStr = '';
  build() {
    Stack() {
      if (this.backgroundSrc !== '') {
        Image(this.backgroundSrc).width('100%').height('100%').objectFit(ImageFit.Cover)
      }
      if (this.foregroundSrc !== '') {
        Image(this.foregroundSrc).width('100%').height('100%').objectFit(ImageFit.Contain)
      }
    }
    .width(this.iconSize)
    .height(this.iconSize)
  }
}