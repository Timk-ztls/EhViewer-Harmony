/**
 * 上游：app/src/main/res/values-v21/styles.xml
 * 该目录是 Android 的限定词变体，HarmonyOS 限定词体系里没有对应目录（实测 restool 报 Invalid qualifier key）。
 * 生效路径：内容已合并进 resources/base/element/styles.json（高版本覆盖低版本），运行期不需要读本文件。
 * 本文件的作用：保留该限定词目录的原始覆盖项，供逐条比对与后续回归。
 */
export interface StyleOverride {
  readonly style: string;
  /** "attr|value"；parent 记为 "parent|X" */
  readonly attrs: string[];
}

export const V21_STYLES: StyleOverride[] = [
  { style: 'Widget.Ehviewer.AppWidget.Container', attrs: ['parent|android:Widget', 'android:id|@android:id/background', 'android:padding|?attr/appWidgetPadding', 'android:background|@drawable/app_widget_background'] },
  { style: 'Widget.Ehviewer.AppWidget.InnerView', attrs: ['parent|android:Widget', 'android:padding|?attr/appWidgetPadding', 'android:background|@drawable/app_widget_inner_view_background', 'android:textColor|?android:attr/textColorPrimary'] },
];

export default V21_STYLES;
