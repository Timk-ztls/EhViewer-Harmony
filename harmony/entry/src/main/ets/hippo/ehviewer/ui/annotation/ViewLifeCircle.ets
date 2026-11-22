/*
 * 上游：app/src/main/java/com/hippo/ehviewer/ui/annotation/ViewLifeCircle.java
 * 目标：harmony/entry/src/main/ets/hippo/ehviewer/ui/annotation/ViewLifeCircle.ets（inventory S0186）
 *
 * ── 上游真实语义（重要，与「回调接口」的直觉不同）─────────────────────────────
 * 上游是 **FIELD 级** 标记：`@Retention(SOURCE) @Target(ElementType.FIELD) @interface ViewLifeCircle {}`
 * 用法（WarningScene.java）：
 *     @ViewLifeCircle
 *     private var mXxx: Xxx? = null
 * 语义 = 该字段的生命周期跟随「视图」：View 销毁（onDestroyView）时重置为 null，
 *        下次访问再重建。Java 侧靠注解处理器/反射识别字段并在对应时机置空。
 *
 * ── ArkTS 等价（D-023）──────────────────────────────────────────────────────
 * ArkTS 无注解、无反射，故改为**显式作用域持有者**：
 *     private mXxx: ScopedViewField<Xxx> = new ScopedViewField<Xxx>(() => new Xxx());
 *     ... this.mXxx.get() ...        // 懒建
 *     ... this.mXxx.reset() ...      // 通常由 SceneFragment 在 onDrawerClosed 时统一调用
 * 字段类型变了（T → Scoped*Field<T>），但"何时建、何时失效"的语义与上游一致，且不依赖反射。
 */

/** 可被 SceneFragment 统一重置的作用域成员（三个注解的公共协议） */
export interface LifeCircleScoped {
  reset(): void;
  isCreated(): boolean;
}

/**
 * 对位 `@ViewLifeCircle`：视图生命周期作用域。
 * reset 时机 = SceneFragment 收到 onSceneViewDestroyed（上游 onDestroyView）。
 */
export class ScopedViewField<T> implements LifeCircleScoped {
  private readonly factory: () => T;
  private value: T | null = null;

  constructor(factory: () => T) {
    this.factory = factory;
  }

  /** 懒建：首次访问时创建（等价上游"字段为 null 则重建"） */
  get(): T {
    if (this.value === null) {
      this.value = this.factory();
    }
    return this.value;
  }

  /** 视图销毁时释放（上游在 onDestroyView 把字段置 null） */
  reset(): void {
    this.value = null;
  }

  isCreated(): boolean {
    return this.value !== null;
  }
}
