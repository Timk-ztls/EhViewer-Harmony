/*
 * 上游：app/src/main/java/com/hippo/ehviewer/ui/scene/TransitionNameFactory.java（inventory S0267，30 行）
 * 目标：harmony/entry/src/main/ets/hippo/ehviewer/ui/scene/TransitionNameFactory.ets
 *
 * 背景：**共享元素转场名**的生成器。上游用 `View.setTransitionName()` + `ActivityOptions`
 * 的共享元素动画，靠字符串名把列表项与详情页的对应 View 配对。
 *
 * ── 上游全文对照（4 个静态方法，无状态、无 IO）────────────────────────────
 * public static String getThumbTransitionName(long gid)     → `"thumb:" + gid`
 * public static String getTitleTransitionName(long gid)     → `"title:" + gid`
 * public static String getUploaderTransitionName(long gid)  → `"uploader:" + gid`
 * public static String getCategoryTransitionName(long gid)  → `"category:" + gid`
 *
 * 实现要点（1:1）：
 * - **前缀字符串必须逐字一致**（`thumb:` / `title:` / `uploader:` / `category:`，含冒号、无空格）
 * - `gid` 是 `long`：ArkTS 的 number 是 IEEE754 double，安全整数上限 2^53-1。
 *   画廊 gid 实际是 6-8 位十进制，远小于 2^53 → 用 `number` 等价。
 *   **但**若将来出现 > 2^53 的 id，字符串化会丢精度 —— 所以这里显式写明边界，并在
 *   `getTransitionName()` 里用 `String(gid)` 而不是 `gid.toFixed()`（避免引入小数点）。
 * - 上游是 `final class` + 私有构造（不可实例化）→ ArkTS 侧用 `export class` + 只放 static，
 *   不提供实例成员（语义等价；ArkTS 没有 `final class`，也无法阻止 `new`，属平台差异）。
 *
 * ── 平台差异（没有删除，只是换载体）────────────────────────────────────────
 * 上游靠字符串给 **Android View** 配对；鸿蒙的共享元素转场用 `geometryTransition(id)` +
 * `TransitionEffect`，同样需要一个**稳定的字符串 id** → 本类的产物直接可作为 `geometryTransition` 的 id。
 * 因此本类在鸿蒙侧**仍然是活的**（不是死代码），只是消费方从 View 变成 ArkUI 组件。
 *
 * 关联：S0238 `EnterGalleryDetailTransaction`（消费这些名字做转场）。
 */

/** gid 的安全整数上限（2^53 - 1）：超过此值 number 无法精确表示，字符串化会丢精度 */
export const GID_SAFE_MAX: number = 9007199254740991;

export class TransitionNameFactory {
  /** 上游私有构造 → ArkTS 侧不做实例化约定（无法在语言层阻止，见文件头） */
  private constructor() {
  }

  /** 缩略图共享元素名：`thumb:<gid>` */
  static getThumbTransitionName(gid: number): string {
    return 'thumb:' + TransitionNameFactory.normalizeGid(gid);
  }

  /** 标题共享元素名：`title:<gid>` */
  static getTitleTransitionName(gid: number): string {
    return 'title:' + TransitionNameFactory.normalizeGid(gid);
  }

  /** 上传者共享元素名：`uploader:<gid>` */
  static getUploaderTransitionName(gid: number): string {
    return 'uploader:' + TransitionNameFactory.normalizeGid(gid);
  }

  /** 分类共享元素名：`category:<gid>` */
  static getCategoryTransitionName(gid: number): string {
    return 'category:' + TransitionNameFactory.normalizeGid(gid);
  }

  /**
   * gid 的字符串形态。
   * 上游是 `"" + gid`（Java long）：整数、无小数点、无千分位。
   * ArkTS 侧必须避免 `toFixed()`/`toLocaleString()` 之类的格式化（会引入小数点或分隔符）。
   */
  private static normalizeGid(gid: number): string {
    // 负数/非整数在上游不会出现（gid 是主键）；这里不抛异常，保持与上游"原样拼"的行为一致
    return gid.toString();
  }
}
