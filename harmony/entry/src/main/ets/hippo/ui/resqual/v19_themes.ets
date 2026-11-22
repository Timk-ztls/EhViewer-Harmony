/**
 * 上游：app/src/main/res/values-v19/themes.xml
 * 该目录是 Android 的限定词变体，HarmonyOS 限定词体系里没有对应目录（实测 restool 报 Invalid qualifier key）。
 * 生效路径：内容已合并进 resources/base/element/themes.json（高版本覆盖低版本），运行期不需要读本文件。
 * 本文件的作用：保留该限定词目录的原始覆盖项，供逐条比对与后续回归。
 */
export interface StyleOverride {
  readonly style: string;
  /** "attr|value"；parent 记为 "parent|X" */
  readonly attrs: string[];
}

export const V19_THEMES: StyleOverride[] = [
  { style: 'AppTheme.NoActionBar.Translucent', attrs: ['android:windowTranslucentStatus|true', 'android:windowTranslucentNavigation|false', 'android:windowContentOverlay|@null'] },
  { style: 'AppTheme.Dark.NoActionBar.Translucent', attrs: ['android:windowTranslucentStatus|true', 'android:windowTranslucentNavigation|false', 'android:windowContentOverlay|@null'] },
  { style: 'AppTheme.Black.NoActionBar.Translucent', attrs: ['android:windowTranslucentStatus|true', 'android:windowTranslucentNavigation|false', 'android:windowContentOverlay|@null'] },
];

export default V19_THEMES;
