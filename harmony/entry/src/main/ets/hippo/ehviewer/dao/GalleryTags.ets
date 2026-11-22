/*
 * 对位上游：app/src/main/java/com/hippo/ehviewer/dao/GalleryTags.java（GreenDAO 生成实体）
 *
 * 列映射逐字保留（17 列，顺序与 CREATE_TABLE_SQL 一致）：
 *   gid→"GID"(INTEGER PK NOT NULL)、rows→"ROWS"、artist→"ARTIST"、cosplayer→"COSPLAYER"、
 *   character→"CHARACTER"、female→"FEMALE"、group→"GROUP"、language→"LANGUAGE"、male→"MALE"、
 *   misc→"MISC"、mixed→"MIXED"、other→"OTHER"、parody→"PARODY"、reclass→"RECLASS"、
 *   create_time→"CREATE_TIME"(INTEGER)、update_time→"UPDATE_TIME"(INTEGER)、location→"LOCATION"(TEXT)
 *   —— "LOCATION" 与 "ARCHIVE_URI" 是 schema v8 加的列（EhDB 迁移里 ALTER TABLE 追加），
 *   本 port 直接进 createTable，与上游 v8 现状一致，读旧库不会缺列。
 *
 * 平台对位：
 *   - 上游 `java.util.Date` 在 GreenDAO 里映射为 SQLite INTEGER（毫秒时间戳）。ArkTS 有 Date，
 *     保留 Date 字段类型以维持调用点语义，DAO 读写时显式 getTime()/new Date(ms) 转换。
 *   - 上游 toString() 用 fastjson 序列化整个对象；ArkTS 无 fastjson，改为 JSON.stringify(toRecord())，
 *     字段集合与上游一致（fastjson 默认序列化 public 字段）。
 *
 * 可空契约（C-13）：字段用 `T | undefined` 表示"未从库读出"，**getter/setter 对外一律 `T | null`**。
 * 理由：上游 Java 只有 null；ArkTS 的 undefined 语义是"未初始化/缺省参数"，与"数据库列为 NULL"不同。 */

export class GalleryTags {
  public gid: number = 0;
  public rows: string | null = null;
  public artist: string | null = null;
  public cosplayer: string | null = null;
  public character: string | null = null;
  public female: string | null = null;
  public group: string | null = null;
  public language: string | null = null;
  public male: string | null = null;
  public misc: string | null = null;
  public mixed: string | null = null;
  public other: string | null = null;
  public parody: string | null = null;
  public reclass: string | null = null;
  /** 对位 java.util.Date（SQLite 存毫秒 INTEGER）。 *
 * 可空契约（C-13）：字段用 `T | undefined` 表示"未从库读出"，**getter/setter 对外一律 `T | null`**。
 * 理由：上游 Java 只有 null；ArkTS 的 undefined 语义是"未初始化/缺省参数"，与"数据库列为 NULL"不同。 */
  public create_time: Date | null = null;
  public update_time: Date | null = null;
  public location: string | null = null;

  constructor(gid?: number, rows?: string, artist?: string, cosplayer?: string, character?: string,
    female?: string, group?: string, language?: string, male?: string, misc?: string, mixed?: string,
    other?: string, parody?: string, reclass?: string, create_time?: Date, update_time?: Date,
    location?: string) {
    this.gid = gid !== undefined ? gid : 0;
    this.rows = rows !== undefined ? rows : null;
    this.artist = artist !== undefined ? artist : null;
    this.cosplayer = cosplayer !== undefined ? cosplayer : null;
    this.character = character !== undefined ? character : null;
    this.female = female !== undefined ? female : null;
    this.group = group !== undefined ? group : null;
    this.language = language !== undefined ? language : null;
    this.male = male !== undefined ? male : null;
    this.misc = misc !== undefined ? misc : null;
    this.mixed = mixed !== undefined ? mixed : null;
    this.other = other !== undefined ? other : null;
    this.parody = parody !== undefined ? parody : null;
    this.reclass = reclass !== undefined ? reclass : null;
    this.create_time = create_time !== undefined ? create_time : null;
    this.update_time = update_time !== undefined ? update_time : null;
    this.location = location !== undefined ? location : null;
  }

  getGid(): number {
    return this.gid;
  }

  setGid(gid: number): void {
    this.gid = gid;
  }

  getRows(): string | null {
    return this.rows;
  }

  setRows(rows: string | null): void {
    this.rows = rows;
  }

  getArtist(): string | null {
    return this.artist;
  }

  setArtist(artist: string | null): void {
    this.artist = artist;
  }

  getCosplayer(): string | null {
    return this.cosplayer;
  }

  setCosplayer(cosplayer: string | null): void {
    this.cosplayer = cosplayer;
  }

  getCharacter(): string | null {
    return this.character;
  }

  setCharacter(character: string | null): void {
    this.character = character;
  }

  getFemale(): string | null {
    return this.female;
  }

  setFemale(female: string | null): void {
    this.female = female;
  }

  getGroup(): string | null {
    return this.group;
  }

  setGroup(group: string | null): void {
    this.group = group;
  }

  getLanguage(): string | null {
    return this.language;
  }

  setLanguage(language: string | null): void {
    this.language = language;
  }

  getMale(): string | null {
    return this.male;
  }

  setMale(male: string | null): void {
    this.male = male;
  }

  getMisc(): string | null {
    return this.misc;
  }

  setMisc(misc: string | null): void {
    this.misc = misc;
  }

  getMixed(): string | null {
    return this.mixed;
  }

  setMixed(mixed: string | null): void {
    this.mixed = mixed;
  }

  getOther(): string | null {
    return this.other;
  }

  setOther(other: string | null): void {
    this.other = other;
  }

  getParody(): string | null {
    return this.parody;
  }

  setParody(parody: string | null): void {
    this.parody = parody;
  }

  getReclass(): string | null {
    return this.reclass;
  }

  setReclass(reclass: string | null): void {
    this.reclass = reclass;
  }

  getCreate_time(): Date | null {
    return this.create_time;
  }

  setCreate_time(create_time: Date | null): void {
    this.create_time = create_time;
  }

  getUpdate_time(): Date | null {
    return this.update_time;
  }

  setUpdate_time(update_time: Date | null): void {
    this.update_time = update_time;
  }

  getLocation(): string | null {
    return this.location;
  }

  setLocation(location: string | null): void {
    this.location = location;
  }

  /** 对位上游 toString()（fastjson 序列化 public 字段）。 *
 * 可空契约（C-13）：字段用 `T | undefined` 表示"未从库读出"，**getter/setter 对外一律 `T | null`**。
 * 理由：上游 Java 只有 null；ArkTS 的 undefined 语义是"未初始化/缺省参数"，与"数据库列为 NULL"不同。 */
  toRecord(): Record<string, Object | null> {
    const r: Record<string, Object | null> = {};
    r.gid = this.gid;
    r.rows = this.rows !== null ? this.rows : null;
    r.artist = this.artist !== null ? this.artist : null;
    r.cosplayer = this.cosplayer !== null ? this.cosplayer : null;
    r.character = this.character !== null ? this.character : null;
    r.female = this.female !== null ? this.female : null;
    r.group = this.group !== null ? this.group : null;
    r.language = this.language !== null ? this.language : null;
    r.male = this.male !== null ? this.male : null;
    r.misc = this.misc !== null ? this.misc : null;
    r.mixed = this.mixed !== null ? this.mixed : null;
    r.other = this.other !== null ? this.other : null;
    r.parody = this.parody !== null ? this.parody : null;
    r.reclass = this.reclass !== null ? this.reclass : null;
    r.create_time = this.create_time !== null ? this.create_time.getTime() : null;
    r.update_time = this.update_time !== null ? this.update_time.getTime() : null;
    r.location = this.location !== null ? this.location : null;
    return r;
  }

  toString(): string {
    return JSON.stringify(this.toRecord());
  }
}
