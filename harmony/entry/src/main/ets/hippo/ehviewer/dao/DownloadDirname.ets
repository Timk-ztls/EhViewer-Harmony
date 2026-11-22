/*
 * 对位上游：app/src/main/java/com/hippo/ehviewer/dao/DownloadDirname.java（GreenDAO 生成实体）
 *
 * 列映射逐字保留：gid→"GID"(INTEGER PK NOT NULL)、dirname→"DIRNAME"(TEXT)。
 * 用途：图库目录名缓存（下载目录 → gid 的映射），SpiderDen 会读写它。
 *
 * 可空契约（C-13）：字段用 `T | undefined` 表示"未从库读出"，**getter/setter 对外一律 `T | null`**。
 * 理由：上游 Java 只有 null；ArkTS 的 undefined 语义是"未初始化/缺省参数"，与"数据库列为 NULL"不同。 */

export class DownloadDirname {
  private gid: number = 0;
  private dirname: string | null = null;

  constructor(gid?: number, dirname?: string) {
    this.gid = gid !== undefined ? gid : 0;
    this.dirname = dirname !== undefined ? dirname : null;
  }

  getGid(): number {
    return this.gid;
  }

  setGid(gid: number): void {
    this.gid = gid;
  }

  getDirname(): string | null {
    return this.dirname !== null ? this.dirname : null;
  }

  setDirname(dirname: string | null): void {
    this.dirname = dirname;
  }
}
