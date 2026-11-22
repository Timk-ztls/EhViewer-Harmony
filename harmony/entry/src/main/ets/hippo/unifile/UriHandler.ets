/*
 * 对位上游：app/src/main/java/com/hippo/unifile/UriHandler.java
 *
 * 平台对位：
 *   - 上游签名是 fromUri(Context context, Uri uri)：Context 用来取 ContentResolver。
 *     鸿蒙的文件层不依赖 Context（fs 直接吃路径/URI），故参数收缩为 (uri)。
 *     这是本模块唯一一处「公开接口签名收缩」，已在 MR 里列为跨模块交接点：
 *     注册方（core-runtime 的 EhApplication 等价物）实现时不需要 Context。
 *   - 用途不变：给 UniFile.fromUri 挂自定义 scheme 的扩展点（本工程暂无使用者，
 *     保留是为了上游调用点与后续扩展形状一致）。
 */

import { UniFile } from './UniFile';

/** 对位上游 UriHandler：把自定义 URI 转成 UniFile 的扩展点。 */
export interface UriHandler {
  /**
   * @param uri 待解析的 URI（鸿蒙侧为 file:// 形式或自定义 scheme 串）
   * @return UniFile；不认领该 URI 时返回 null，由后续 handler / 内建分派继续处理
   */
  fromUri(uri: string): UniFile | null;
}
