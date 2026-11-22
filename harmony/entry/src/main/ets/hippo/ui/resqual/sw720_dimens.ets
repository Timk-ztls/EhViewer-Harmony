/**
 * 上游：app/src/main/res/values-sw720dp/dimens.xml
 * 该目录是 Android 最小宽度桶（swNdp），HarmonyOS 无此限定词（实测 restool 报 Invalid qualifier key）。
 * 生效路径：内容已合并进 resources/tablet/element/dimens.json（宽者覆盖窄者），运行期按 tablet 设备类型生效。
 * 本文件的作用：保留该桶的原始数值，供逐条比对与后续按窗口宽度做分级适配时引用。
 */
export interface DimenOverride {
  readonly name: string;
  readonly value: string;
}

export const SW720_DIMENS: DimenOverride[] = [
];

export default SW720_DIMENS;
