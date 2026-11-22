/**
 * 重绘自 app/src/main/res/drawable/default_avatar.xml  （inventory S0725，上游 41 行）
 * 上游节点：<vector>
 * 生成方式：XML Drawable（shape/selector/vector）→ ArkUI Shape/状态样式（变体: base）；换算规则见 hippo/drawable/DrawableSpec.ets 文件头
 *   <path pathData="M0,12a12,12 0 1,0 24,0a12,12 0 1,0 -24,0" fillColor="@color/teal_500"> → Path().commands('M0,12a12,12 0 1,0 24,0a12,12 0 1,0 -24,0').fill(DrawablePalette.TEAL_500)
 *   <path pathData="M16.5,9.9L16.1,9.6L19.1,5.9C19.2,5.8,19.4,5.8,19.5,5.9L19.5,5.9C19.6,6,19.6,6.2,19.5,6.3L16.5,9.9Z" fillColor="@android:color/black"> → Path().commands('M16.5,9.9L16.1,9.6L19.1,5.9C19.2,5.8,19.4,5.8,19.5,5.9L19.5,5.9C19.6,6,19.6,6.2,19.5,6.3L16.5,9.9Z').fill('#FF000000')
 *   <path pathData="M9.1,8.8L8.6,9.1L6.2,5C6.1,4.9,6.2,4.7,6.3,4.6L6.3,4.6C6.4,4.5,6.6,4.6,6.7,4.7L9.1,8.8Z" fillColor="@android:color/black"> → Path().commands('M9.1,8.8L8.6,9.1L6.2,5C6.1,4.9,6.2,4.7,6.3,4.6L6.3,4.6C6.4,4.5,6.6,4.6,6.7,4.7L9.1,8.8Z').fill('#FF000000')
 *   <path pathData="M1.8,14.6L22.1,16.4C21.4,11.3,17.6,7.9,12.6,7.5C7.8,7,3.4,9.7,1.8,14.6Z" fillColor="@android:color/white"> → Path().commands('M1.8,14.6L22.1,16.4C21.4,11.3,17.6,7.9,12.6,7.5C7.8,7,3.4,9.7,1.8,14.6Z').fill('#FFFFFFFF')
 *   <path pathData="M15.4,11.9a1.1,1.1 0 1,0 2.2,0a1.1,1.1 0 1,0 -2.2,0" fillColor="@android:color/black"> → Path().commands('M15.4,11.9a1.1,1.1 0 1,0 2.2,0a1.1,1.1 0 1,0 -2.2,0').fill('#FF000000')
 *   <path pathData="M7.1,11.2a1.1,1.1 0 1,0 2.2,0a1.1,1.1 0 1,0 -2.2,0" fillColor="@android:color/black"> → Path().commands('M7.1,11.2a1.1,1.1 0 1,0 2.2,0a1.1,1.1 0 1,0 -2.2,0').fill('#FF000000')
 */
import { DrawablePalette } from '../../drawable/DrawablePalette';

@Component
export struct DefaultAvatar {
  /** 上游矢量尺寸 64dp×64dp，viewport 24×24；尺寸走 vp，可与 dp 值一一对应 */
  @Prop iconSize: number = 64;
  build() {
    Shape() {
      Path()
        .commands('M0,12a12,12 0 1,0 24,0a12,12 0 1,0 -24,0')
        .fill(DrawablePalette.TEAL_500)
        .stroke(Color.Transparent)
        .strokeWidth(0)
      Path()
        .commands('M16.5,9.9L16.1,9.6L19.1,5.9C19.2,5.8,19.4,5.8,19.5,5.9L19.5,5.9C19.6,6,19.6,6.2,19.5,6.3L16.5,9.9Z')
        .fill('#FF000000')
        .stroke(Color.Transparent)
        .strokeWidth(0)
      Path()
        .commands('M9.1,8.8L8.6,9.1L6.2,5C6.1,4.9,6.2,4.7,6.3,4.6L6.3,4.6C6.4,4.5,6.6,4.6,6.7,4.7L9.1,8.8Z')
        .fill('#FF000000')
        .stroke(Color.Transparent)
        .strokeWidth(0)
      Path()
        .commands('M1.8,14.6L22.1,16.4C21.4,11.3,17.6,7.9,12.6,7.5C7.8,7,3.4,9.7,1.8,14.6Z')
        .fill('#FFFFFFFF')
        .stroke(Color.Transparent)
        .strokeWidth(0)
      Path()
        .commands('M15.4,11.9a1.1,1.1 0 1,0 2.2,0a1.1,1.1 0 1,0 -2.2,0')
        .fill('#FF000000')
        .stroke(Color.Transparent)
        .strokeWidth(0)
      Path()
        .commands('M7.1,11.2a1.1,1.1 0 1,0 2.2,0a1.1,1.1 0 1,0 -2.2,0')
        .fill('#FF000000')
        .stroke(Color.Transparent)
        .strokeWidth(0)
    }
    .viewPort({ x: 0, y: 0, width: '24px', height: '24px' })
    .width(this.iconSize)
    .height(this.iconSize * 64 / 64)
    .antiAlias(true)
  }
}