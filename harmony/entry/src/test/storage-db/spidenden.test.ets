/*
 * SpiderDen / GalleryProvider2 纯逻辑单测（不需要设备、不需要网络、不需要 GL）
 *
 * 为什么这几条值得逐条断言：它们决定「下载目录里的文件能不能被正确找到」——
 *   文件名格式错一个字符 → 重启应用后已下载的图全部"消失"（用户视角是丢数据）；
 *   扩展名嗅探错 → 拷贝会产出错误后缀，画廊按白名单过滤时读不到；
 *   白名单大小写敏感 → Android 上 `.JPG` 的旧目录迁移过来后整页空白。
 * 这三类错误都不会让编译失败，只在真机上看图时暴露，所以必须由断言兜住。
 */

import { SpiderDen, StartWithFilenameFilter, SUPPORT_IMAGE_EXTENSIONS, MODE_READ, MODE_DOWNLOAD } from '../../main/ets/hippo/ehviewer/spider/SpiderDen';
import { GalleryInfo } from '../../main/ets/hippo/ehviewer/client/data/GalleryInfo';
import { GalleryProvider2 } from '../../main/ets/hippo/ehviewer/gallery/GalleryProvider2';
import { UniFile } from '../../main/ets/hippo/unifile/UniFile';
import { OutputStreamPipe, ByteSink } from '../../main/ets/hippo/streampipe/OutputStreamPipe';
import { Settings } from '../../main/ets/hippo/ehviewer/Settings';
import fs from '@ohos.file.fs';

let pass = 0;
const fails: string[] = [];

function eq(name: string, got: unknown, want: unknown): void {
  const g = JSON.stringify(got);
  const w = JSON.stringify(want);
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
    fails.push(name);
  }
}

function bytes(values: number[]): ArrayBuffer {
  const buf: ArrayBuffer = new ArrayBuffer(values.length);
  const view: Uint8Array = new Uint8Array(buf);
  for (let i = 0; i < values.length; i++) {
    view[i] = values[i];
  }
  return buf;
}

// ================================================================ 1) 文件名格式（%08d + index+1）

{
  // 上游 String.format(Locale.US, "%08d%s", index + 1, extension)
  eq('第 0 页 → 00000001', SpiderDen.generateImageFilename(0, '.jpg'), '00000001.jpg');
  eq('第 6 页 → 00000007', SpiderDen.generateImageFilename(6, '.jpg'), '00000007.jpg');
  eq('第 7 页 → 00000008', SpiderDen.generateImageFilename(7, '.png'), '00000008.png');
  eq('第 8 页 → 00000009', SpiderDen.generateImageFilename(8, '.gif'), '00000009.gif');
  eq('第 9 页进位 → 00000010', SpiderDen.generateImageFilename(9, '.webp'), '00000010.webp');
  eq('第 99 页 → 00000100', SpiderDen.generateImageFilename(99, '.jpg'), '00000100.jpg');
  // 超过 8 位不截断（上游 %08d 是最小宽度，不是最大宽度）
  eq('9 位不截断', SpiderDen.generateImageFilename(99999999, '.jpg'), '100000000.jpg');
  // 空扩展名（部分下载器先写再改名）
  eq('空扩展名', SpiderDen.generateImageFilename(0, ''), '00000001');
}

// ================================================================ 2) 扩展名嗅探（替代 BitmapFactory 的 outMimeType）

{
  // JPEG: FF D8 FF
  eq('JPEG', SpiderDen.sniffImageExtension(bytes([0xff, 0xd8, 0xff, 0xe0, 0x00, 0x10, 0x4a, 0x46, 0x49, 0x46, 0x00, 0x01])), '.jpg');
  // PNG: 89 50 4E 47 0D 0A 1A 0A
  eq('PNG', SpiderDen.sniffImageExtension(bytes([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 0x00, 0x00, 0x00, 0x0d])), '.png');
  // GIF: "GIF8"
  eq('GIF', SpiderDen.sniffImageExtension(bytes([0x47, 0x49, 0x46, 0x38, 0x39, 0x61, 0x01, 0x00, 0x01, 0x00, 0x00, 0x00])), '.gif');
  // WEBP: "RIFF"...."WEBP"
  eq('WEBP', SpiderDen.sniffImageExtension(bytes([0x52, 0x49, 0x46, 0x46, 0x24, 0x00, 0x00, 0x00, 0x57, 0x45, 0x42, 0x50])), '.webp');
  // RIFF 但不是 WEBP（例如 WAV）→ 不认
  eq('RIFF/WAVE 不是图片', SpiderDen.sniffImageExtension(bytes([0x52, 0x49, 0x46, 0x46, 0x24, 0x00, 0x00, 0x00, 0x57, 0x41, 0x56, 0x45])), null);
  // 未知内容
  eq('未知内容', SpiderDen.sniffImageExtension(bytes([0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09, 0x0a, 0x0b])), null);
  // 短读（只有 2 字节）不能越界崩溃
  eq('2 字节不崩溃', SpiderDen.sniffImageExtension(bytes([0xff, 0xd8])), null);
  eq('空 buffer 不崩溃', SpiderDen.sniffImageExtension(new ArrayBuffer(0)), null);
  // 3 字节正好是 JPEG 最短特征
  eq('3 字节 JPEG', SpiderDen.sniffImageExtension(bytes([0xff, 0xd8, 0xff])), '.jpg');
}

// ================================================================ 3) 扩展名白名单单点化

{
  eq('白名单 5 个（与上游一致）', SUPPORT_IMAGE_EXTENSIONS.length, 5);
  eq('白名单内容', SUPPORT_IMAGE_EXTENSIONS, ['.jpg', '.jpeg', '.png', '.gif', '.webp']);
  // 关键：SpiderDen 的导出必须直接引用 GalleryProvider2 的那一份（不是副本）——
  // 若有人重新写字面量，这条会失败，从而挡住「两处漂移」
  ok('SpiderDen 与 GalleryProvider2 共用同一份列表',
    SpiderDen !== null && SUPPORT_IMAGE_EXTENSIONS === GalleryProvider2.SUPPORT_IMAGE_EXTENSIONS);

  ok('isSupportedImageName 小写 .jpg', GalleryProvider2.isSupportedImageName('00000001.jpg'));
  ok('isSupportedImageName 大写 .JPG（旧 Android 目录常见）', GalleryProvider2.isSupportedImageName('00000001.JPG'));
  ok('isSupportedImageName 混合 .WebP', GalleryProvider2.isSupportedImageName('00000001.WebP'));
  ok('isSupportedImageName 拒绝 .bmp（上游白名单不含）', !GalleryProvider2.isSupportedImageName('00000001.bmp'));
  ok('isSupportedImageName 拒绝后缀伪装（.jpg.txt）', !GalleryProvider2.isSupportedImageName('00000001.jpg.txt'));
}

// ================================================================ 4) 目录项前缀过滤（findDownloadDirname 的第 2 步）

{
  // 上游签名 accept(UniFile dir, String filename)；dir 在实现里不参与判定，这里给一个不落盘的实例
  const anyDirMaybe: UniFile | null = UniFile.fromFile('/nonexistent/probe');
  if (anyDirMaybe === null) {
    fails.push('UniFile.fromFile 返回 null，无法构造 dir 参数');
  }
  const anyDir: UniFile = anyDirMaybe !== null ? anyDirMaybe : (null as unknown as UniFile);
  const filter: StartWithFilenameFilter = new StartWithFilenameFilter('12345-');
  ok('命中正确前缀', filter.accept(anyDir, '12345-[作者] 标题'));
  ok('不命中别的 gid', !filter.accept(anyDir, '123456-[作者] 标题'));
  ok('不命中纯 gid（无短横线）', !filter.accept(anyDir, '12345'));
  const empty: StartWithFilenameFilter = new StartWithFilenameFilter('');
  ok('空前缀命中所��', empty.accept(anyDir, 'anything'));
}

// ================================================================ 5) 模式常量（SpiderQueen 落地后从这里 re-export）

{
  eq('MODE_READ', MODE_READ, 0);
  eq('MODE_DOWNLOAD', MODE_DOWNLOAD, 1);
  ok('两个模式不相等', MODE_READ !== MODE_DOWNLOAD);
}

// ================================================================ 6) 缓存侧 / 模式分派（对 SimpleDiskCache 的真实调用）

{
  SpiderDen.resetCache();
  const g: GalleryInfo = new GalleryInfo();
  g.gid = 1;
  const den: SpiderDen = new SpiderDen(g);

  eq('默认 READ 模式 isDownloadMode=false', den.isDownloadMode(), false);
  den.setMode(MODE_DOWNLOAD);
  eq('setMode(MODE_DOWNLOAD) 生效', den.isDownloadMode(), true);
  den.setMode(MODE_READ);

  // ① 设置未注入时，凡是会问"边读边存"的入口**必须抛错**（不是静默按 false 走）——
  //    静默 false 会让"边读边存"永远不生效，属于行为降级。
  let threwIn: boolean = false;
  let msgIn: string = '';
  try {
    den.openInputStreamPipe(0);
  } catch (e) {
    threwIn = true;
    msgIn = (e as Error).message !== undefined ? (e as Error).message : '';
  }
  ok('READ 模式未注入设置 → openInputStreamPipe 抛错（不静默）', threwIn);
  ok('错误信息点名 getSyncDownloadWhileReading', msgIn.indexOf('getSyncDownloadWhileReading') >= 0);
  ok('错误信息给出上游 key（可检索）', msgIn.indexOf('sync_download_while_reading') >= 0);

  // ② 注入「不开启」后，所有读取入口安全返回空值（缓存未初始化 / 无下载目录）
  SpiderDen.setSyncDownloadSettingProvider({ getSyncDownloadWhileReading: (): boolean => false });
  eq('READ 模式未初始化缓存 → isReady()=false', den.isReady(), false);
  eq('无缓存无目录 → contain(0)=false', den.contain(0), false);
  eq('无缓存无目录 → remove(0)=false', den.remove(0), false);
  eq('无缓存无目录 → openInputStreamPipe(0)=null', den.openInputStreamPipe(0), null);
  eq('无缓存 → openOutputStreamPipe(0, .jpg)=null', den.openOutputStreamPipe(0, '.jpg'), null);
  eq('没有下载目录 → getDownloadDir()=null', den.getDownloadDir(), null);

  // ③ 下载模式：shouldWriteToDownloadDir 恒 true（不读设置）
  den.setMode(MODE_DOWNLOAD);
  eq('DOWNLOAD 模式 → shouldWriteToDownloadDir()=true', den.shouldWriteToDownloadDir(), true);
  eq('DOWNLOAD 模式未就绪 → isReady()=false（没有目录）', den.isReady(), false);
  den.setMode(MODE_READ);

  // ④ 注入「开启」后 READ 模式的 shouldWriteToDownloadDir 为 true
  SpiderDen.setSyncDownloadSettingProvider({ getSyncDownloadWhileReading: (): boolean => true });
  eq('注入 true → READ 模式 shouldWriteToDownloadDir()=true', den.shouldWriteToDownloadDir(), true);
  SpiderDen.setSyncDownloadSettingProvider(null);
}

{
  // initialize() 会 clamp(40,640)MB 后建 SimpleDiskCache —— 验证"能建起来 + isReady 变 true"
  SpiderDen.resetCache();
  SpiderDen.initialize('/tmp/cache-dir', 10);   // 低于下限 40 → 被 clamp
  SpiderDen.setSyncDownloadSettingProvider({ getSyncDownloadWhileReading: (): boolean => false });
  const g: GalleryInfo = new GalleryInfo();
  g.gid = 2;
  const den: SpiderDen = new SpiderDen(g);
  eq('initialize 后 READ 模式 isReady()=true', den.isReady(), true);
  eq('空缓存 contain(0)=false', den.contain(0), false);
  eq('空缓存 openInputStreamPipe(0)=null', den.openInputStreamPipe(0), null);
  SpiderDen.resetCache();
  SpiderDen.setSyncDownloadSettingProvider(null);
}
// ================================================================ ② remove 必须删"全部扩展名"
{
  const names: string[] = SpiderDen.imageFilenamesFor(3);
  eq('候选文件名数量 = 扩展名数量（5）', names.length, SUPPORT_IMAGE_EXTENSIONS.length);
  ok('候选数量不是 1（反证：只删一个扩展名会漏删）', names.length !== 1);
  for (const ext of SUPPORT_IMAGE_EXTENSIONS) {
    ok(`候选包含 ${ext}`, names.some((n: string): boolean => n.endsWith(ext)));
  }
  // 不猜字面量：直接与 generateImageFilename 的输出比（index=3 → 序号 4 → 8 位补零）
  eq('候选 = generateImageFilename(index, ext) 逐项', names, SUPPORT_IMAGE_EXTENSIONS.map((e: string): string => SpiderDen.generateImageFilename(3, e)));
  eq('序号是 index+1 的 8 位补零', names[0], '00000004.jpg');
  ok('候选数 > findImageFile 的返回数上限（1）—— 两者不能互换', names.length > 1);
}

// ================================================================ ③ P1 #11 & #10: 懒 getDownloadDir + 边读边存自动建目录 + 魔数修正扩展名
{
  const dlRootPath: string = '/tmp/m42_den_root';
  fs.mkdirSync(dlRootPath, true);
  const dlRoot: UniFile | null = UniFile.fromFile(dlRootPath);
  if (dlRoot !== null) {
    Settings.putDownloadLocation(dlRoot);
  }
  SpiderDen.setTitleProvider({
    getSuitableTitle: (info: GalleryInfo): string => info.title !== null ? info.title : 'title'
  });
  SpiderDen.setDirnameStore({
    getDownloadDirname: async (): Promise<string | null> => null,
    putDownloadDirname: async (): Promise<void> => {}
  });

  // 1) 懒解析：磁盘已存在 9101-Existing 时，新 SpiderDen.getDownloadDir() 无需预先 prepareDownloadStorage
  const preExistingDir: string = `${dlRootPath}/9101-Existing`;
  fs.mkdirSync(preExistingDir, true);
  const gPre: GalleryInfo = new GalleryInfo();
  gPre.gid = 9101;
  gPre.title = 'Existing';
  const denLazy: SpiderDen = new SpiderDen(gPre);
  const resolved: UniFile | null = denLazy.getDownloadDir();
  ok('P1 #11: getDownloadDir() 懒解析到已有下载目录',
    resolved !== null && resolved.getName() === '9101-Existing');

  // 2) 边读边存（MODE_READ + syncDownloadWhileReading=true）：openOutputStreamPipe 自动建目录并写入
  SpiderDen.setSyncDownloadSettingProvider({ getSyncDownloadWhileReading: (): boolean => true });
  const gSync: GalleryInfo = new GalleryInfo();
  gSync.gid = 9102;
  gSync.title = 'SyncRead';
  const denSync: SpiderDen = new SpiderDen(gSync);
  denSync.setMode(MODE_READ);
  const pipe: OutputStreamPipe | null = denSync.openOutputStreamPipe(0, null);
  ok('P1 #11: MODE_READ + 边读边存时 openOutputStreamPipe 返回非空写端', pipe !== null);
  ok('P1 #11: 边读边存已自动建好下载目录', denSync.getDownloadDir() !== null);
  if (pipe !== null) {
    pipe.obtain();
    const sink: ByteSink = pipe.open();
    sink.write(bytes([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]));
    pipe.close();
    pipe.release();
    // 3) P1 #10: fixDownloadedExtension 按魔数重命名为 00000001.png
    denSync.fixDownloadedExtension(0);
    const syncDir: UniFile | null = denSync.getDownloadDir();
    const renamed: UniFile | null = syncDir !== null ? syncDir.findFile('00000001.png') : null;
    ok('P1 #10: fixDownloadedExtension 根据魔数将 .jpg 修正为 00000001.png', renamed !== null);
  }

  SpiderDen.setSyncDownloadSettingProvider(null);
  SpiderDen.setDirnameStore(null);
  SpiderDen.setTitleProvider(null);
  SpiderDen.resetCache();
}

// ================================================================ 汇总

if (fails.length > 0) {
  console.log(`\n${fails.length} 个断言失败：`);
  for (const f of fails) {
    console.log(`  ✗ ${f}`);
  }
  console.log(`\n通过 ${pass}，失败 ${fails.length}`);
  process.exit(1);
}
console.log(`全部通过：${pass} 个断言`);
