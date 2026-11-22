/*
 * download-sync 接手批单测：两条本地导入（S0222 相册 / S0223 归档）
 *
 * 钉住的语义（都是"写错也不报错、但用户看到的东西不对"）：
 *   相册：resolveImportRoot 三分支、自然序排序（a2 < a10）、扩展名回退、目标序号用成功数、
 *        标题空/全空白回退 imported_album_<gid>、archiveUri 前缀 local-album:、已导入全等比较
 *   归档：格式白名单（zip/rar/cbz/cbr，无 7z）、取不到文件名的兜底、标题去最后扩展名、
 *        archiveUri 存裸 uri（不能被 isLocalAlbum 误判）、流程顺序（权限→可读→文件名→格式→重复）
 *
 * 运行：pwsh -File harmony/entry/src/test/ui-scene/run.ps1
 */

import {
  DownloadAlbumImporter, AlbumFileSystem, DirEntryLike, URI_PREFIX, LOCAL_TOKEN, LOCAL_THUMB,
  LOCAL_UPLOADER, AlbumImportOutcome, AlbumDownloadInfoSpec
} from '../../main/ets/hippo/ehviewer/ui/scene/download/part/DownloadAlbumImporter';
import {
  DownloadArchiveImporter, ArchiveFileSource, ARCHIVE_MIME_TYPES, SUPPORTED_ARCHIVE_EXTENSIONS,
  ArchiveImportOutcome, ArchiveDownloadInfoSpec, ARCHIVE_UPLOADER
} from '../../main/ets/hippo/ehviewer/ui/scene/download/part/DownloadArchiveImporter';
import { DownloadInfo } from '../../main/ets/hippo/ehviewer/dao/DownloadInfo';
import { SUPPORT_IMAGE_EXTENSIONS } from '../../main/ets/hippo/ehviewer/spider/SpiderDen';

let pass: number = 0;
const fails: string[] = [];

function eq(name: string, got: Object | null | undefined, want: Object | null | undefined): void {
  const g: string = JSON.stringify(got);
  const w: string = JSON.stringify(want);
  if (g === w) {
    pass++;
  } else {
    fails.push(`${name}\n    got  ${g}\n    want ${w}`);
  }
}

function ok(name: string, cond: boolean): void {
  if (cond) {
    pass++;
  } else {
    fails.push(`${name}  (want true)`);
  }
}

// ---------------------------------------------------------------- 内存文件系统

class MemFs implements AlbumFileSystem {
  /** path → 内容（文件）；目录用 Set 表示 */
  dirs: Set<string> = new Set<string>();
  files: Set<string> = new Set<string>();
  copied: string[] = [];
  deleted: string[] = [];

  mkdir(p: string): void { this.dirs.add(p); }
  touch(p: string): void { this.files.add(p); }

  isDirectory(path: string): boolean { return this.dirs.has(path); }
  isFile(path: string): boolean { return this.files.has(path); }

  list(dir: string): DirEntryLike[] | null {
    if (!this.dirs.has(dir)) {
      return null;
    }
    const out: DirEntryLike[] = [];
    const prefix: string = `${dir}/`;
    this.dirs.forEach((d: string): void => {
      if (d.startsWith(prefix) && d.indexOf('/', prefix.length) === -1) {
        out.push(new DirEntryLike(d.substring(prefix.length), true, false));
      }
    });
    this.files.forEach((f: string): void => {
      if (f.startsWith(prefix) && f.indexOf('/', prefix.length) === -1) {
        out.push(new DirEntryLike(f.substring(prefix.length), false, true));
      }
    });
    return out;
  }

  createFile(dir: string, name: string): boolean {
    this.files.add(`${dir}/${name}`);
    return true;
  }

  exists(dir: string, name: string): boolean {
    return this.files.has(`${dir}/${name}`) || this.dirs.has(`${dir}/${name}`);
  }

  deleteIn(dir: string, name: string): boolean {
    this.deleted.push(`${dir}/${name}`);
    this.files.delete(`${dir}/${name}`);
    return true;
  }

  copyFile(srcPath: string, destPath: string): boolean {
    this.copied.push(`${srcPath}→${destPath}`);
    this.files.add(destPath);
    return true;
  }

  deleteDir(path: string): boolean {
    this.deleted.push(path);
    this.dirs.delete(path);
    return true;
  }
}

class FakeSource implements ArchiveFileSource {
  permission: boolean = true;
  openable: boolean = true;
  name: string | null = 'gallery.cbz';

  takePersistableReadPermission(_uri: string): boolean { return this.permission; }
  canOpen(_uri: string): boolean { return this.openable; }
  fileNameOf(_uri: string): string | null { return this.name; }
}

// ---------------------------------------------------------------- 相册：常量与判定

function testAlbumConstants(): void {
  eq('archiveUri 前缀', URI_PREFIX, 'local-album:');
  eq('token 占位', LOCAL_TOKEN, 'local');
  eq('thumb 占位', LOCAL_THUMB, 'local');
  eq('uploader 显示名', LOCAL_UPLOADER, 'Local Album');
  eq('archiveUri 拼接', DownloadAlbumImporter.archiveUriOf('content://a'), 'local-album:content://a');

  // isLocalAlbum：只有 local-album: 前缀才算
  const albumInfo: DownloadInfo = new DownloadInfo();
  albumInfo.archiveUri = 'local-album:content://a';
  eq('local-album: 是本地相册', DownloadAlbumImporter.isLocalAlbum(albumInfo), true);

  const archiveInfo: DownloadInfo = new DownloadInfo();
  archiveInfo.archiveUri = 'content://a';
  eq('裸 uri 不是本地相册', DownloadAlbumImporter.isLocalAlbum(archiveInfo), false);

  const nullUri: DownloadInfo = new DownloadInfo();
  nullUri.archiveUri = null;
  eq('archiveUri 为 null → false', DownloadAlbumImporter.isLocalAlbum(nullUri), false);
  eq('info 为 null → false', DownloadAlbumImporter.isLocalAlbum(null), false);
}

function testAlbumDuplicate(): void {
  const a: DownloadInfo = new DownloadInfo();
  a.archiveUri = 'local-album:u1';
  const b: DownloadInfo = new DownloadInfo();
  b.archiveUri = 'local-album:u2';
  eq('同 uri → 已导入', DownloadAlbumImporter.isAlreadyImported('local-album:u1', [a, b]), true);
  eq('不同 uri → 未导入', DownloadAlbumImporter.isAlreadyImported('local-album:u3', [a, b]), false);
  eq('空列表 → 未导入', DownloadAlbumImporter.isAlreadyImported('local-album:u1', []), false);
  eq('前缀相同但更长 → 不算（全等比较）',
    DownloadAlbumImporter.isAlreadyImported('local-album:u1x', [a]), false);
}

// ---------------------------------------------------------------- 相册：路径解析

function testAlbumRoot(): void {
  // ① 本层有图 → 本层
  const fs1: MemFs = new MemFs();
  fs1.mkdir('/root');
  fs1.touch('/root/001.jpg');
  fs1.mkdir('/root/sub');
  eq('本层有图 → 用本层', DownloadAlbumImporter.resolveImportRoot(fs1, '/root'), '/root');

  // ② 唯一子目录 → 下钻
  const fs2: MemFs = new MemFs();
  fs2.mkdir('/root');
  fs2.mkdir('/root/inner');
  fs2.touch('/root/inner/001.jpg');
  eq('唯一子目录 → 下钻', DownloadAlbumImporter.resolveImportRoot(fs2, '/root'), '/root/inner');

  // ②b 下钻两层
  const fs2b: MemFs = new MemFs();
  fs2b.mkdir('/root');
  fs2b.mkdir('/root/a');
  fs2b.mkdir('/root/a/b');
  fs2b.touch('/root/a/b/1.png');
  eq('两层单子目录 → 下钻到底',
    DownloadAlbumImporter.resolveImportRoot(fs2b, '/root'), '/root/a/b');

  // ③ 多个子目录 → 用本层
  const fs3: MemFs = new MemFs();
  fs3.mkdir('/root');
  fs3.mkdir('/root/a');
  fs3.mkdir('/root/b');
  eq('多个子目录 → 用本层', DownloadAlbumImporter.resolveImportRoot(fs3, '/root'), '/root');

  // ④ 非目录 → null
  const fs4: MemFs = new MemFs();
  fs4.touch('/root/file.txt');
  eq('非目录 → null', DownloadAlbumImporter.resolveImportRoot(fs4, '/root/file.txt'), null);
}

function testAlbumCollectAndSort(): void {
  const fs: MemFs = new MemFs();
  fs.mkdir('/r');
  fs.mkdir('/r/sub');
  fs.touch('/r/2.jpg');
  fs.touch('/r/10.jpg');
  fs.touch('/r/sub/1.png');
  fs.touch('/r/readme.txt');

  const paths: string[] = DownloadAlbumImporter.collectImagePaths(fs, '/r');
  eq('递归收集到 3 张图（不含 txt）', paths.length, 3);
  ok('含子目录里的图', paths.some((p: string): boolean => p === '/r/sub/1.png'));

  // 自然序：a2 在 a10 之前（字典序会反过来）
  const sorted: string[] = DownloadAlbumImporter.sortNatural(['/r/10.jpg', '/r/2.jpg', '/r/1.jpg']);
  eq('自然序 1,2,10',
    sorted.map((p: string): string => DownloadAlbumImporter.basename(p)), ['1.jpg', '2.jpg', '10.jpg']);
  ok('字典序确实不同（这是排序的意义）',
    ['/r/10.jpg', '/r/1.jpg', '/r/2.jpg'].sort()[0] === '/r/1.jpg');
}

function testAlbumNames(): void {
  eq('jpg 是图片', DownloadAlbumImporter.isImageName('a.JPG'.toLowerCase()), true);
  eq('大写扩展名也认', DownloadAlbumImporter.isImageName('A.JPG'), true);
  eq('txt 不是', DownloadAlbumImporter.isImageName('a.txt'), false);

  eq('扩展名含点', DownloadAlbumImporter.imageExtensionOf('a.JPG'), '.jpg');
  eq('不支持的扩展名 → 回退第一项',
    DownloadAlbumImporter.imageExtensionOf('a.txt'), SUPPORT_IMAGE_EXTENSIONS[0]);
  eq('无扩展名 → 回退', DownloadAlbumImporter.imageExtensionOf('noext'), SUPPORT_IMAGE_EXTENSIONS[0]);
  eq('null → 回退', DownloadAlbumImporter.imageExtensionOf(null), SUPPORT_IMAGE_EXTENSIONS[0]);
  eq('多点文件名取最后一个点', DownloadAlbumImporter.imageExtensionOf('a.b.png'), '.png');

  // 目标名：序号来自"成功数"，而 SpiderDen.generateImageFilename 是 **1 基**
  // （`String.format("%08d", index + 1)`）—— 所以 copiedCount=0 得到 00000001
  eq('copiedCount=0 → 00000001（1 基）', DownloadAlbumImporter.targetNameOf(0, 'x.png'), '00000001.png');
  eq('copiedCount=3 → 00000004', DownloadAlbumImporter.targetNameOf(3, 'x.jpg'), '00000004.jpg');
}

function testAlbumCopyOne(): void {
  const fs: MemFs = new MemFs();
  fs.mkdir('/dest');
  fs.touch('/src/a.png');
  eq('复制成功', DownloadAlbumImporter.copyOne(fs, '/src/a.png', '/dest', 0), true);
  eq('目标名按成功数编号（1 基）', fs.copied[0].endsWith('/dest/00000001.png'), true);

  // 源不存在 → 不复制
  eq('源不存在 → 失败', DownloadAlbumImporter.copyOne(fs, '/src/missing.png', '/dest', 1), false);

  // 同名已存在 → 先删再建（copiedCount=1 → 目标 00000002）
  fs.touch('/dest/00000002.png');
  eq('同名先删后建', DownloadAlbumImporter.copyOne(fs, '/src/a.png', '/dest', 1), true);
  ok('删除过同名文件', fs.deleted.some((d: string): boolean => d === '/dest/00000002.png'));
}

function testAlbumInfoSpec(): void {
  const spec: AlbumDownloadInfoSpec =
    DownloadAlbumImporter.buildInfoSpec(1700000000000, 'My Album', 'local-album:u', 7, 'labelA');
  eq('gid', spec.gid, 1700000000000);
  eq('time = gid', spec.time, 1700000000000);
  eq('token 占位', spec.token, LOCAL_TOKEN);
  eq('thumb 占位', spec.thumb, LOCAL_THUMB);
  eq('uploader', spec.uploader, LOCAL_UPLOADER);
  eq('rating -1', spec.rating, -1);
  eq('state FINISH', spec.state, DownloadInfo.STATE_FINISH);
  eq('legacy 0', spec.legacy, 0);
  eq('total = 图片数', spec.total, 7);
  eq('finished = 图片数', spec.finished, 7);
  eq('标题用文件夹名', spec.title, 'My Album');
  eq('label 透传', spec.label, 'labelA');
  eq('archiveUri', spec.archiveUri, 'local-album:u');

  // 名字为空/空白 → 回退 imported_album_<gid>
  eq('null 名 → 回退', DownloadAlbumImporter.buildInfoSpec(42, null, 'u', 1, null).title,
    'imported_album_42');
  eq('空串 → 回退', DownloadAlbumImporter.buildInfoSpec(42, '', 'u', 1, null).title,
    'imported_album_42');
  eq('全空白 → 回退', DownloadAlbumImporter.buildInfoSpec(42, '   ', 'u', 1, null).title,
    'imported_album_42');
}

function testAlbumOutcome(): void {
  eq('成功文案', DownloadAlbumImporter.toastResOf(AlbumImportOutcome.SUCCESS), 'import_album_success');
  eq('已导入文案', DownloadAlbumImporter.toastResOf(AlbumImportOutcome.ALREADY_IMPORTED),
    'import_album_already_imported');
  eq('无图文案', DownloadAlbumImporter.toastResOf(AlbumImportOutcome.NO_IMAGES),
    'import_album_no_images');
  eq('下载位置无效', DownloadAlbumImporter.toastResOf(AlbumImportOutcome.INVALID_DOWNLOAD_LOCATION),
    'settings_download_invalid_download_location');
  eq('失败文案', DownloadAlbumImporter.toastResOf(AlbumImportOutcome.FAILED), 'import_album_failed');
}

// ---------------------------------------------------------------- 归档

function testArchiveConstants(): void {
  eq('MIME 8 项', ARCHIVE_MIME_TYPES.length, 8);
  eq('第一个是 application/zip', ARCHIVE_MIME_TYPES[0], 'application/zip');
  eq('扩展名白名单 4 项', SUPPORTED_ARCHIVE_EXTENSIONS.length, 4);
  eq('uploader', ARCHIVE_UPLOADER, 'Local Archive');

  eq('zip 支持', DownloadArchiveImporter.isValidArchiveFormat('a.zip'), true);
  eq('ZIP 大写支持', DownloadArchiveImporter.isValidArchiveFormat('a.ZIP'), true);
  eq('rar/cbz/cbr 支持',
    [DownloadArchiveImporter.isValidArchiveFormat('a.rar'),
      DownloadArchiveImporter.isValidArchiveFormat('a.cbz'),
      DownloadArchiveImporter.isValidArchiveFormat('a.cbr')], [true, true, true]);
  eq('7z 不支持', DownloadArchiveImporter.isValidArchiveFormat('a.7z'), false);
  eq('无扩展名不支持', DownloadArchiveImporter.isValidArchiveFormat('noext'), false);
  eq('null 不支持', DownloadArchiveImporter.isValidArchiveFormat(null), false);
}

function testArchiveNames(): void {
  eq('取不到文件名 → 兜底 imported_archive_<now>',
    DownloadArchiveImporter.resolveFileName(null, 1234), 'imported_archive_1234');
  eq('有文件名就原样用', DownloadArchiveImporter.resolveFileName('a.cbz', 1234), 'a.cbz');

  eq('去最后扩展名', DownloadArchiveImporter.titleOf('gallery.cbz'), 'gallery');
  eq('多点只去最后一个', DownloadArchiveImporter.titleOf('a.b.cbr'), 'a.b');
  eq('没有点 → 原样', DownloadArchiveImporter.titleOf('noext'), 'noext');
  eq('兜底名没有扩展名 → 标题原样（后面格式校验会拦）',
    DownloadArchiveImporter.titleOf('imported_archive_99'), 'imported_archive_99');
}

function testArchiveInfoSpec(): void {
  const spec: ArchiveDownloadInfoSpec =
    DownloadArchiveImporter.buildInfoSpec(1700000000001, 'content://x', 'My Gallery.cbz');
  eq('gid', spec.gid, 1700000000001);
  eq('token 是空串（不是 null）', spec.token, '');
  eq('标题去扩展名', spec.title, 'My Gallery');
  eq('thumb 为 null', spec.thumb, null);
  eq('uploader', spec.uploader, ARCHIVE_UPLOADER);
  eq('rating -1', spec.rating, -1);
  eq('state FINISH', spec.state, DownloadInfo.STATE_FINISH);
  eq('total 0（由 provider 之后补）', spec.total, 0);
  eq('finished 0', spec.finished, 0);
  eq('time = gid', spec.time, 1700000000001);
  eq('label null', spec.label, null);
  eq('archiveUri 存裸 uri（不带 local-album:）', spec.archiveUri, 'content://x');
  ok('裸 uri 不会被 isLocalAlbum 误判',
    DownloadAlbumImporter.isLocalAlbum(((): DownloadInfo => {
      const info: DownloadInfo = new DownloadInfo();
      info.archiveUri = spec.archiveUri;
      return info;
    })()) === false);
}

function testArchiveFlow(): void {
  const container: Set<number> = new Set<number>();
  const contains = (gid: number): boolean => container.has(gid);

  // ① 正常
  const src1: FakeSource = new FakeSource();
  const r1 = DownloadArchiveImporter.planImport('content://a', src1, 500, contains);
  eq('正常 → SUCCESS', r1.outcome, ArchiveImportOutcome.SUCCESS);
  eq('gid = now', r1.gid, 500);
  eq('标题去扩展名', r1.title, 'gallery');

  // ② 权限丢失
  const src2: FakeSource = new FakeSource();
  src2.permission = false;
  eq('权限申请失败 → PERMISSION_LOST',
    DownloadArchiveImporter.planImport('content://a', src2, 500, contains).outcome,
    ArchiveImportOutcome.PERMISSION_LOST);

  // ③ 打不开（权限在但流失败）
  const src3: FakeSource = new FakeSource();
  src3.openable = false;
  eq('打不开 → FAILED',
    DownloadArchiveImporter.planImport('content://a', src3, 500, contains).outcome,
    ArchiveImportOutcome.FAILED);

  // ④ 格式不支持
  const src4: FakeSource = new FakeSource();
  src4.name = 'a.7z';
  eq('7z → INVALID_FORMAT',
    DownloadArchiveImporter.planImport('content://a', src4, 500, contains).outcome,
    ArchiveImportOutcome.INVALID_FORMAT);

  // ⑤ 取不到文件名 → 兜底名无扩展名 → 格式不合法（上游既有行为）
  const src5: FakeSource = new FakeSource();
  src5.name = null;
  eq('取不到文件名 → INVALID_FORMAT（不是 FAILED）',
    DownloadArchiveImporter.planImport('content://a', src5, 777, contains).outcome,
    ArchiveImportOutcome.INVALID_FORMAT);

  // ⑥ 已存在
  container.add(600);
  const src6: FakeSource = new FakeSource();
  eq('已存在 → ALREADY_IMPORTED',
    DownloadArchiveImporter.planImport('content://a', src6, 600, contains).outcome,
    ArchiveImportOutcome.ALREADY_IMPORTED);

  // 文案
  eq('成功文案', DownloadArchiveImporter.toastResOf(ArchiveImportOutcome.SUCCESS),
    'import_archive_success');
  eq('权限丢失用专属文案',
    DownloadArchiveImporter.toastResOf(ArchiveImportOutcome.PERMISSION_LOST), 'archive_permission_lost');
  eq('格式非法文案',
    DownloadArchiveImporter.toastResOf(ArchiveImportOutcome.INVALID_FORMAT),
    'import_archive_invalid_format');
}

// ---------------------------------------------------------------- 入口

function main(): void {
  testAlbumConstants();
  testAlbumDuplicate();
  testAlbumRoot();
  testAlbumCollectAndSort();
  testAlbumNames();
  testAlbumCopyOne();
  testAlbumInfoSpec();
  testAlbumOutcome();
  testArchiveConstants();
  testArchiveNames();
  testArchiveInfoSpec();
  testArchiveFlow();

  if (fails.length > 0) {
    console.error(`\n✗ ${fails.length} 条失败 / ${pass + fails.length} 条断言`);
    for (const f of fails) {
      console.error('  - ' + f);
    }
    throw new Error('download-sync local import test failed');
  }
  console.log(`✓ download-sync 本地导入批: ${pass} 条断言全部通过`);
}

main();
