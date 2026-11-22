/**
 * `import x from 'libnative-lib.so'` 的类型入口。
 *
 * 真正的声明只有一份：`harmony/entry/src/main/ets/native/index.d.ts`（本文只做转发，
 * 避免两处声明漂移）。工具链要求 NAPI 模块的类型包位于 cpp/types/<soname>/ 下，
 * 所以这里按 DevEco 约定放一个同名包，内容转发过去。
 *
 * 接线（Lead 侧，一行）：`harmony/entry/oh-package.json5` 的 dependencies 里加
 *   "libnative-lib.so": "file:./src/main/cpp/types/libnative-lib"
 * 未接线时 ArkTS 只报 "Currently module for 'libnative-lib.so' is not verified" 警告，
 * 不影响编译（实测：86 个 ArkTS 错误里 native-image 相关 0 个）。
 */
export * from '../../../../ets/native/index';
export { default } from '../../../../ets/native/index';
