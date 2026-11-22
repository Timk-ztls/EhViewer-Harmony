/*
 * 对位上游：app/src/main/java/com/hippo/ehviewer/dao/Filter.java（GreenDAO 生成实体）
 *
 * 列映射逐字保留：id→"_id"(INTEGER PK)、mode→"MODE"(INTEGER NOT NULL)、text→"TEXT"(TEXT)、
 *                 enable→"ENABLE"(INTEGER，可空)。
 * equals/hashCode 行为必须与上游一致：EhDB.backup 用 `currentFilterList.contains(filter)` 去重，
 * 依赖的正是 equals（mode + text），不是 id。
 *   - 上游 hashCode = HashCodeUtils.hashCode(mode, text) = 31*(31*0 + mode) + text.hashCode()
 *   - Java String.hashCode 是 s[0]*31^(n-1)+...+s[n-1]，本文件用 javaStringHash() 复刻，
 *     保证跨端 hash 值一致（若下游用 Set/Map 去重也能对齐）。
 *
 * 可空契约（C-13）：字段用 `T | undefined` 表示"未从库读出"，**getter/setter 对外一律 `T | null`**。
 * 理由：上游 Java 只有 null；ArkTS 的 undefined 语义是"未初始化/缺省参数"，与"数据库列为 NULL"不同。 */

export class Filter {
  private id: number | null = null;
  public mode: number = 0;
  public text: string | null = null;
  /** 可空（对位 Boolean enable，SQLite 存 0/1/NULL）。 *
 * 可空契约（C-13）：字段用 `T | undefined` 表示"未从库读出"，**getter/setter 对外一律 `T | null`**。
 * 理由：上游 Java 只有 null；ArkTS 的 undefined 语义是"未初始化/缺省参数"，与"数据库列为 NULL"不同。 */
  public enable: boolean | null = null;

  constructor(id?: number, mode?: number, text?: string, enable?: boolean) {
    this.id = id !== undefined ? id : null;
    this.mode = mode !== undefined ? mode : 0;
    this.text = text !== undefined ? text : null;
    this.enable = enable !== undefined ? enable : null;
  }

  getId(): number | null {
    return this.id !== null ? this.id : null;
  }

  setId(id: number | null): void {
    this.id = id;
  }

  getMode(): number {
    return this.mode;
  }

  setMode(mode: number): void {
    this.mode = mode;
  }

  getText(): string | null {
    return this.text !== null ? this.text : null;
  }

  setText(text: string | null): void {
    this.text = text;
  }

  getEnable(): boolean | null {
    return this.enable !== null ? this.enable : null;
  }

  setEnable(enable: boolean | null): void {
    this.enable = enable;
  }

  /** 对位上游 hashCode()。 *
 * 可空契约（C-13）：字段用 `T | undefined` 表示"未从库读出"，**getter/setter 对外一律 `T | null`**。
 * 理由：上游 Java 只有 null；ArkTS 的 undefined 语义是"未初始化/缺省参数"，与"数据库列为 NULL"不同。 */
  hashCode(): number {
    const textHash: number = this.text !== null ? javaStringHash(this.text) : 0;
    return 31 * (31 * 0 + this.mode) + textHash;
  }

  /** 对位上游 equals(Object)：只比 mode 与 text。 *
 * 可空契约（C-13）：字段用 `T | undefined` 表示"未从库读出"，**getter/setter 对外一律 `T | null`**。
 * 理由：上游 Java 只有 null；ArkTS 的 undefined 语义是"未初始化/缺省参数"，与"数据库列为 NULL"不同。 */
  equals(o: Object | null | undefined): boolean {
    if (o === null || o === undefined) {
      return false;
    }
    if (!(o instanceof Filter)) {
      return false;
    }
    const filter: Filter = o as Filter;
    return filter.mode === this.mode && filter.text === this.text;
  }
}

/** Java String.hashCode 的等价实现（int32 溢出语义）。 *
 * 可空契约（C-13）：字段用 `T | undefined` 表示"未从库读出"，**getter/setter 对外一律 `T | null`**。
 * 理由：上游 Java 只有 null；ArkTS 的 undefined 语义是"未初始化/缺省参数"，与"数据库列为 NULL"不同。 */
function javaStringHash(s: string): number {
  let h: number = 0;
  for (let i = 0; i < s.length; i++) {
    h = (Math.imul(31, h) + s.charCodeAt(i)) | 0;
  }
  return h;
}
