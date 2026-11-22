/*
 * 对位上游：app/src/main/java/com/hippo/ehviewer/dao/DownloadLabel.java（GreenDAO 生成实体）
 *
 * 列映射逐字保留：id→"_id"(INTEGER PK)、label→"LABEL"(TEXT)、time→"TIME"(INTEGER NOT NULL)。
 * 上游字段是 private + getter/setter（与 BlackList 的 public 风格不同），这里同样保持 private。
 * 上游 `long time` 是非空基本类型 → ArkTS number，默认 0（与 SQLite 建表 "NOT NULL" 一致）。
 *
 * 可空契约（C-13）：字段用 `T | undefined` 表示"未从库读出"，**getter/setter 对外一律 `T | null`**。
 * 理由：上游 Java 只有 null；ArkTS 的 undefined 语义是"未初始化/缺省参数"，与"数据库列为 NULL"不同。 */

export class DownloadLabel {
  private id: number | null = null;
  private label: string | null = null;
  private time: number = 0;

  constructor(id?: number, label?: string, time?: number) {
    this.id = id !== undefined ? id : null;
    this.label = label !== undefined ? label : null;
    this.time = time !== undefined ? time : 0;
  }

  getId(): number | null {
    return this.id !== null ? this.id : null;
  }

  setId(id: number | null): void {
    this.id = id;
  }

  getLabel(): string | null {
    return this.label !== null ? this.label : null;
  }

  setLabel(label: string | null): void {
    this.label = label;
  }

  getTime(): number {
    return this.time;
  }

  setTime(time: number): void {
    this.time = time;
  }
}
