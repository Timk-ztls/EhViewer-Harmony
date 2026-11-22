/**
 * 迁移自 app/src/main/java/com/hippo/preference/ActivityPreference.java（inventory S0445，上游 68 行）
 *
 * 判据：**完全重复** —— 上游 = "一行标题/摘要 + 点击 startActivity(intent)"，无自有逻辑。
 * 上游属性：android:title / android:summary / android:icon / intentName（要启动的 Activity 全名）。
 *
 * ArkUI 对位：SettingsItem 行 + `onLaunch` 回调（**路由由调用方实现**：ui-scene 用 router.pushUrl /
 *   wantAgent 启动目标页，ui-widget 不直接依赖页面路由表）。
 * 差异（已登记 MR）：上游用 Intent 全名反射启动任意 Activity；鸿蒙的页面路由是显式声明的
 *   （module.json5 routes），无法按类名启动 → `intentName` 对位为调用方已知的路由键 `routeKey`。
 */
import { SettingsItem } from '../ui/settings/SettingsItem';

@Component
export struct ActivityPreference {
  @Prop title: string = '';
  @Prop summary: string = '';
  @Prop itemEnabled: boolean = true;
  /** 上游 intentName（目标 Activity 全名）→ 鸿蒙侧为调用方定义的路由键 */
  @Prop routeKey: string = '';
  onLaunch: (routeKey: string) => void = (routeKey: string) => {
  };

  build() {
    SettingsItem({
      title: this.title,
      summary: this.summary,
      itemEnabled: this.itemEnabled,
      onItemClick: () => {
        this.onLaunch(this.routeKey);
      }
    })
  }
}
