/*
 * 对位上游：app/src/main/java/com/hippo/ehviewer/dao/BlackList.java（GreenDAO 生成实体）
 *
 * 平台对位：
 *   - @Entity/@Id/@Index 注解在 ArkTS 不存在 → 注解信息转为 Dao 里的常量
 *     （TABLENAME / PK_COLUMN / CREATE_INDEX_SQL），见 BlackListDao.ets。
 *   - 字段与列名映射逐字保留：id→"_id"(INTEGER PK AUTOINCREMENT)、badgayname→"BADGAYNAME"(TEXT, 索引)、
 *     reason→"REASON"、angrywith→"ANGRYWITH"、add_time→"ADD_TIME"、mode→"MODE"。
 *   - 上游 `Long id` / `Integer mode` 是装箱可空类型 → ArkTS `number | undefined`（可空语义一致）。
 *   - 公开字段与 getId()/setId() 一起保留：上游调用点两种写法都有（字段直取 + getter）。
 *
 * 可空契约（C-13）：字段用 `T | undefined` 表示"未从库读出"，**getter/setter 对外一律 `T | null`**。
 * 理由：上游 Java 只有 null；ArkTS 的 undefined 语义是"未初始化/缺省参数"，与"数据库列为 NULL"不同。 */

export class BlackList {
  /** 可空主键（对位 Long id，未插入前为 null）。 *
 * 可空契约（C-13）：字段用 `T | undefined` 表示"未从库读出"，**getter/setter 对外一律 `T | null`**。
 * 理由：上游 Java 只有 null；ArkTS 的 undefined 语义是"未初始化/缺省参数"，与"数据库列为 NULL"不同。 */
  public id: number | null = null;
  public badgayname: string | null = null;
  public reason: string | null = null;
  public angrywith: string | null = null;
  public add_time: string | null = null;
  /** 可空（对位 Integer mode）。 *
 * 可空契约（C-13）：字段用 `T | undefined` 表示"未从库读出"，**getter/setter 对外一律 `T | null`**。
 * 理由：上游 Java 只有 null；ArkTS 的 undefined 语义是"未初始化/缺省参数"，与"数据库列为 NULL"不同。 */
  public mode: number | null = null;

  constructor(id?: number, badgayname?: string, reason?: string, angrywith?: string,
    add_time?: string, mode?: number) {
    this.id = id !== undefined ? id : null;
    this.badgayname = badgayname !== undefined ? badgayname : null;
    this.reason = reason !== undefined ? reason : null;
    this.angrywith = angrywith !== undefined ? angrywith : null;
    this.add_time = add_time !== undefined ? add_time : null;
    this.mode = mode !== undefined ? mode : null;
  }

  getId(): number | null {
    return this.id !== null ? this.id : null;
  }

  setId(id: number | null): void {
    this.id = id;
  }

  getBadgayname(): string | null {
    return this.badgayname !== null ? this.badgayname : null;
  }

  setBadgayname(badgayname: string | null): void {
    this.badgayname = badgayname;
  }

  getReason(): string | null {
    return this.reason !== null ? this.reason : null;
  }

  setReason(reason: string | null): void {
    this.reason = reason;
  }

  getAngrywith(): string | null {
    return this.angrywith !== null ? this.angrywith : null;
  }

  setAngrywith(angrywith: string | null): void {
    this.angrywith = angrywith;
  }

  getAdd_time(): string | null {
    return this.add_time !== null ? this.add_time : null;
  }

  setAdd_time(add_time: string | null): void {
    this.add_time = add_time;
  }

  getMode(): number | null {
    return this.mode !== null ? this.mode : null;
  }

  setMode(mode: number | null): void {
    this.mode = mode;
  }

  /** 对位上游 toString()：返回 badgayname（黑名单条目在 UI 上就是名字本身）。 *
 * 可空契约（C-13）：字段用 `T | undefined` 表示"未从库读出"，**getter/setter 对外一律 `T | null`**。
 * 理由：上游 Java 只有 null；ArkTS 的 undefined 语义是"未初始化/缺省参数"，与"数据库列为 NULL"不同。 */
  toString(): string {
    return this.badgayname !== null ? this.badgayname : '';
  }
}
