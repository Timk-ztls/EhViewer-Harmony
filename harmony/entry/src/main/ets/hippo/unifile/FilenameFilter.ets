/*
 * 对位上游：app/src/main/java/com/hippo/unifile/FilenameFilter.java
 *
 * 平台对位：纯接口，无行为差异。
 *   - ArkTS 的 interface 可以出现在循环 import 中（只做类型引用），本文件与 UniFile.ets 互相引用，
 *     但双方都不在模块求值期解引用对方绑定，故不存在 TDZ 问题（同上游 Java 的惰性链接效果）。
 */

import { UniFile } from './UniFile';

/**
 * 对位上游 FilenameFilter：按目录 + 文件名过滤。
 * 注意：参数顺序与上游一致（dir, filename），实现方不要调换，
 * 因为多数调用点是匿名类直接迁移过来的。
 */
export interface FilenameFilter {
  /**
   * @param dir 文件所在目录（对位上游 UniFile dir）
   * @param filename 待判定的文件名（不是全路径）
   * @return true 表示保留
   */
  accept(dir: UniFile, filename: string): boolean;
}
