/*
 * download-sync 纯逻辑单测：归档导入的顺序与编号契约
 * C-10：harmony/entry/src/test/<module>/
 *
 * 这是 D-η（`listEntries` 未落地、暂时整档解压）唯一能被验证的部分：
 * **页序**。归档导入的正确性完全取决于"第几张图被复制成哪个文件名"，
 * 而这条链（临时目录里的文件顺序）在宿主上不好构造，所以把"顺序决策"抽成纯函数 `planImportOrder`。
 *
 * 编号规则（上游 `ArchiverDownloadCompleter.kt`）：
 *   `for (i in tempPictures.indices) { ... SpiderDen.generateImageFilename(i, ext) }`
 *   —— 用**下标**编号，且 `continue` 的项会**留下空号**（不是压缩编号）。
 *   这条很容易被"优化"成"连续编号"，结果就是与上游页序错位。
 */

import { ArchiverDownloadCompleter, ImportTarget }
  from '../../main/ets/hippo/ehviewer/download/ArchiverDownloadCompleter';
import { SpiderDen } from '../../main/ets/hippo/ehviewer/spider/SpiderDen';

let pass = 0;
const fails: string[] = [];

function eq(name: string, got: Object | null, want: Object | null): void {
  const g: string = JSON.stringify(got);
  const w: string = JSON.stringify(want);
  if (g === w) {
    pass++;
  } else {
    fails.push(`${name}\n    got  ${g}\n    want ${w}`);
  }
}

function main(): void {
  // ---------------------------------------------- 1) 过滤规则
  eq('跳过非图片扩展名',
    ArchiverDownloadCompleter.planImportOrder(['a.jpg', 'readme.txt', 'b.png'], true),
    ['a.jpg', 'b.png']);
  eq('跳过空项', ArchiverDownloadCompleter.planImportOrder(['a.jpg', '', 'b.jpg'], true), ['a.jpg', 'b.jpg']);
  eq('跳过含 .. 的路径（防目录穿越）',
    ArchiverDownloadCompleter.planImportOrder(['a.jpg', '../evil.jpg'], true), ['a.jpg']);
  eq('无扩展名被跳过',
    ArchiverDownloadCompleter.planImportOrder(['noext', 'ok.png'], true), ['ok.png']);

  // ---------------------------------------------- 2) byEntryOrder = false：按文件名排序
  //
  // 这是当前实现（zlib 整档解压后，临时目录里的顺序不可靠，上游按 name 排序）。
  eq('文件名排序：1 / 10 / 2（字典序，与上游一致）',
    ArchiverDownloadCompleter.planImportOrder(['2.jpg', '10.jpg', '1.jpg'], false),
    ['1.jpg', '10.jpg', '2.jpg']);
  eq('文件名排序忽略目录前缀（只看 baseName）',
    ArchiverDownloadCompleter.planImportOrder(['b/2.jpg', 'a/1.jpg'], false),
    ['a/1.jpg', 'b/2.jpg']);

  // ---------------------------------------------- 3) byEntryOrder = true：保持归档条目序
  //
  // 这是 `listEntries` 落地后的目标行为：压缩包里的 1,2,…,10 就该按这个顺序导入。
  eq('条目序：1 / 2 / 10（压缩包原本页序）',
    ArchiverDownloadCompleter.planImportOrder(['1.jpg', '2.jpg', '10.jpg'], true),
    ['1.jpg', '2.jpg', '10.jpg']);
  eq('条目序：不做任何重排（传入即传出，只过滤）',
    ArchiverDownloadCompleter.planImportOrder(['z.jpg', 'a.jpg', 'm.jpg'], true),
    ['z.jpg', 'a.jpg', 'm.jpg']);

  // ---------------------------------------------- 4) 编号契约（下标编号 + 空号保留）
  const entries: string[] = ArchiverDownloadCompleter.planImportOrder(
    ['1.jpg', 'readme.txt', '2.jpg', '10.jpg'], true);
  eq('过滤后仍按条目序', entries, ['1.jpg', '2.jpg', '10.jpg']);
  eq('编号用下标，从 0 开始（SpiderDen.generateImageFilename 是 1-based 显示）',
    entries.map((_e: string, i: number): string => SpiderDen.generateImageFilename(i, '.jpg')),
    ['00000001.jpg', '00000002.jpg', '00000003.jpg']);

  // 空号契约：上游对"文件缺失"的项 continue，编号仍按原下标 → 会出现 00000002 缺失。
  // 这里用"只给存在的项编号"模拟上游行为，确认它**不是**连续编号。
  const withMissing: string[] = ['1.jpg', '2.jpg', '3.jpg'];
  const skipped: string[] = [];
  for (let i = 0; i < withMissing.length; i++) {
    if (i === 1) {
      continue;   // 模拟 picture.isFile === false
    }
    skipped.push(SpiderDen.generateImageFilename(i, '.jpg'));
  }
  eq('跳过的项留下空号（上游 for-indices 语义，不压缩编号）',
    skipped, ['00000001.jpg', '00000003.jpg']);

  // ---------------------------------------------- 5) 真实路径形态（getArchiveEntries 会给这些）
  //
  // 5a 纯数字条目（顺序 = 条目序，不重排）
  eq('5a 纯数字：001..010 保持条目序',
    ArchiverDownloadCompleter.planImportOrder(
      ['001.jpg', '002.jpg', '003.jpg', '004.jpg', '005.jpg', '006.jpg', '007.jpg', '008.jpg',
        '009.jpg', '010.jpg'], true).length, 10);
  eq('5a 首项与末项未被重排',
    ((): string[] => {
      const r: string[] = ArchiverDownloadCompleter.planImportOrder(
        ['001.jpg', '002.jpg', '010.jpg'], true);
      return [r[0], r[2]];
    })(), ['001.jpg', '010.jpg']);

  // 同样输入走 byEntryOrder=false → 会被排成 001,002,010（字典序与数值序恰好一致，看不出差别）
  // 所以下面用 1/10/2 这种"字典序 ≠ 数值序"的输入来区分两个分支。
  eq('5a 反例：1.jpg/10.jpg/2.jpg 按文件名排 → 1,10,2（字典序）',
    ArchiverDownloadCompleter.planImportOrder(['1.jpg', '10.jpg', '2.jpg'], false),
    ['1.jpg', '10.jpg', '2.jpg']);
  eq('5a 反例：同输入按条目序 → 保持 1,10,2 的原顺序（本例输入恰好相同，故再用乱序验证）',
    ArchiverDownloadCompleter.planImportOrder(['2.jpg', '10.jpg', '1.jpg'], true),
    ['2.jpg', '10.jpg', '1.jpg']);

  // 5b 带目录层级（用户手动整理的 漫画名/第01话/001.jpg）
  eq('5b 带目录：ch1/ch2 层级保持条目序',
    ArchiverDownloadCompleter.planImportOrder(
      ['ch1/001.jpg', 'ch1/002.jpg', 'ch2/001.jpg'], true),
    ['ch1/001.jpg', 'ch1/002.jpg', 'ch2/001.jpg']);
  eq('5b 带目录：跨章顺序不被文件名排序打乱（byEntryOrder=false 会按 baseName 重排）',
    ArchiverDownloadCompleter.planImportOrder(
      ['ch2/001.jpg', 'ch1/002.jpg', 'ch1/001.jpg'], false),
    ['ch2/001.jpg', 'ch1/001.jpg', 'ch1/002.jpg']);

  // 5c 混入元数据（macOS 压缩必带 __MACOSX/ + ._ 资源分支；Windows 带 Thumbs.db）
  //
  // ⚠️ 重要：上游**同样不过滤** `__MACOSX/` 与 `._xxx`（ArchiverDownloadCompleter.kt L344-352
  // 只做"递归目录 + 扩展名判断"）。`._001.jpg` 以 .jpg 结尾，因此**会被当图片导入** ——
  // 而它其实是 AppleDouble 元数据，不是有效 JPEG。这是**上游缺陷**，本移植 1:1 保留，
  // 已登记为候选 D-xxx（等 getArchiveEntries() 落地后可在条目级廉价修掉）。
  // 下面的断言**钉住当前行为**，避免以后有人误以为"测过所以是故意的"。
  const withMeta: string[] = ArchiverDownloadCompleter.planImportOrder(
    ['__MACOSX/ch1/._001.jpg', 'ch1/001.jpg', 'Thumbs.db', '.DS_Store'], true);
  eq('5c Thumbs.db / .DS_Store 被过滤（非图片扩展名）',
    withMeta.indexOf('Thumbs.db') < 0 && withMeta.indexOf('.DS_Store') < 0, true);
  eq('5c ⚠️ `._001.jpg` **仍被保留**（上游同样不过滤，属上游缺陷，候选 D-xxx）',
    withMeta, ['__MACOSX/ch1/._001.jpg', 'ch1/001.jpg']);

  // 5d 乱序条目（zip 条目顺序 = 写入顺序，不保证与文件名一致）—— 最关键的一条
  eq('5d 乱序：003,001,002 → 按条目序原样（**不排序**）',
    ArchiverDownloadCompleter.planImportOrder(['003.jpg', '001.jpg', '002.jpg'], true),
    ['003.jpg', '001.jpg', '002.jpg']);
  eq('5d 对照：同样输入按文件名排序 → 001,002,003（这就是 byEntryOrder 的意义）',
    ArchiverDownloadCompleter.planImportOrder(['003.jpg', '001.jpg', '002.jpg'], false),
    ['001.jpg', '002.jpg', '003.jpg']);

  // 5e 非图片混入
  eq('5e readme.txt 被过滤，cover.png 与 001.jpg 保留且保持条目序',
    ArchiverDownloadCompleter.planImportOrder(['readme.txt', 'cover.png', '001.jpg'], true),
    ['cover.png', '001.jpg']);
  // ---------------------------------------------- 6) planImportTargets：条目 → 落盘任务（层 2 的纯函数部分）
  //
  // 这一层把"顺序/过滤/编号"三个决策合成为**可执行任务列表**，真正的 IO 只剩循环。
  // entryPaths 的形态按 A7ZipArchive.create() 的过滤结果给（已剔非图片/目录/加密）：
  //   - 不带 __MACOSX/（已被 create() 过滤 —— 见 5c 的说明：那两条断言验证的是"若进来会怎样"）
  //   - 保留相对路径层级（ch1/001.jpg）
  //   - 顺序 = 归档内顺序（不保证按文件名）

  const entryPaths: string[] = ['003.jpg', 'ch1/002.jpg', 'note.txt', 'ch1/001.jpg'];
  const targets: ImportTarget[] = ArchiverDownloadCompleter.planImportTargets(entryPaths, true);
  eq('6 非图片条目被剔除（note.txt）', targets.length, 3);
  eq('6 条目序保持（003 排第一，**不按文件名排序**）',
    targets.map((x: ImportTarget): string => x.entryPath), ['003.jpg', 'ch1/002.jpg', 'ch1/001.jpg']);
  eq('6 entryIndex 指回归档下标（不是排序后的位次）',
    targets.map((x: ImportTarget): number => x.entryIndex), [0, 1, 3]);
  eq('6 落盘文件名按下标从 1 开始编号',
    targets.map((x: ImportTarget): string => x.fileName),
    ['00000001.jpg', '00000002.jpg', '00000003.jpg']);

  // 带目录层级 + 非 ASCII 路径不应破坏编号
  const targets2: ImportTarget[] = ArchiverDownloadCompleter.planImportTargets(
    ['漫画/ch1/001.jpg', '漫画/ch1/002.png'], true);
  eq('6 中文目录层级：编号仍从 1 起、扩展名各自保留',
    targets2.map((x: ImportTarget): string => x.fileName), ['00000001.jpg', '00000002.png']);

  // byEntryOrder=false 的对照：同输入按文件名排序
  const targets3: ImportTarget[] = ArchiverDownloadCompleter.planImportTargets(entryPaths, false);
  eq('6 byEntryOrder=false → 按 baseName 字典序（001 排前）',
    targets3.map((x: ImportTarget): string => x.entryPath), ['ch1/001.jpg', 'ch1/002.jpg', '003.jpg']);

  // 空输入不崩
  eq('6 空条目列表 → 空任务列表', ArchiverDownloadCompleter.planImportTargets([], true).length, 0);
  // ---------------------------------------------- 汇总
  if (fails.length > 0) {
    console.error(`\n✗ ${fails.length} 条失败 / ${pass + fails.length} 条断言`);
    for (const f of fails) {
      console.error('  - ' + f);
    }
    throw new Error('import-order test failed');
  }
  console.log(`✓ import-order: ${pass} 条断言全部通过`);
}

main();
