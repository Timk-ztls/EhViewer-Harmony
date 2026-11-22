/*
 * 上游：app/src/main/java/com/hippo/ehviewer/ui/annotation/DrawerLifeCircle.java
 * 目标：harmony/entry/src/main/ets/hippo/ehviewer/ui/annotation/DrawerLifeCircle.ets（inventory S0185）
 *
 * ── 上游真实语义（重要，与「回调接口」的直觉不同）─────────────────────────────
 * 上游是 **FIELD 级** 标记：`@Retention(SOURCE) @Target(ElementType.FIELD) @interface DrawerLifeCircle {}`
 * 用法（FavoritesScene.kt）：
 *     @DrawerLifeCircle
 *     private var mXxx: Xxx? = null
 * 语义 = 该字段的生命周期跟随「抽屉」：抽屉关闭（或场景退到抽屉后）时重置为 null，
 *        下次访问再重建。Java 侧靠注解处理器/反射识别字段并在对应时机置空。
 *
 * ── ArkTS 等价（D-023）──────────────────────────────────────────────────────
 * ArkTS 无注解、无反射，故改为**显式作用域持有者**：
 *     private mXxx: ScopedDrawerField<Xxx> = new ScopedDrawerField<Xxx>(() => new Xxx());
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
 * 对位 `@DrawerLifeCircle`：抽屉生命周期作用域。
 * reset 时机 = SceneFragment 收到 onDrawerClosed。
 */
export class ScopedDrawerField<T> implements LifeCircleScoped {
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

  /** 抽屉关闭时释放（上游把字段置 null） */
  reset(): void {
    this.value = null;
  }

  isCreated(): boolean {
    return this.value !== null;
  }
}
