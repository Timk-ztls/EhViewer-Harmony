// 小件批（TimeUtils / MutableBoolean / SomethingNeedRefresh / GalleryActivityEvent）断言
global.Observed = (target) => target;
const path = require('path');
const OUT = process.argv[2] || path.join(process.env.TEMP, 'tscheck', 'out9');
const utilDir = path.join(OUT, 'util');
const util = { TimeUtils: require(path.join(utilDir, 'TimeUtils.js')).TimeUtils,
  MutableBoolean: require(path.join(utilDir, 'MutableBoolean.js')).MutableBoolean };
const evDir = path.join(OUT, 'ehviewer', 'event');
const ev = { SomethingNeedRefresh: require(path.join(evDir, 'SomethingNeedRefresh.js')).SomethingNeedRefresh,
  GalleryActivityEvent: require(path.join(evDir, 'GalleryActivityEvent.js')).GalleryActivityEvent };

let fail = 0;
const eq = (a, b, label) => {
  const A = JSON.stringify(a), B = JSON.stringify(b);
  if (A === B) console.log('  PASS  ' + label);
  else { fail++; console.log('  FAIL  ' + label + '\n    实际: ' + A + '\n    期望: ' + B); }
};

const { TimeUtils } = util;
const { SomethingNeedRefresh, GalleryActivityEvent } = ev;
const { MutableBoolean } = util;

// ── TimeUtils：yyyy-MM-dd HH:mm:ss a ──
const s = TimeUtils.getTimeNow();
eq(/^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2} (AM|PM)$/.test(s), true, 'TimeUtils.getTimeNow 匹配 yyyy-MM-dd HH:mm:ss a 格式，实际=' + s);
const hour = Number(s.substring(11, 13));
eq((hour < 12 ? 'AM' : 'PM') === s.substring(20), true, 'AM/PM 标记与小时一致（' + hour + ' → ' + s.substring(20) + '）');
const ss = Number(s.substring(17, 19));
eq(ss >= 0 && ss <= 59 && /^\d{2}$/.test(s.substring(17, 19)), true, '秒数是 00-59 的两位数字（不比对实时时钟，避免跨秒假失败）');

// ── MutableBoolean ──
const mb = new MutableBoolean(false);
eq(mb.value, false, 'MutableBoolean 初值 false');
mb.value = true;
eq(mb.value, true, 'MutableBoolean 可变（对应 Kotlin var value）');

// ── SomethingNeedRefresh ──
const snr = new SomethingNeedRefresh();
eq([snr.isBookmarkDrawNeed(), snr.isDownloadLabelDrawNeed(), snr.isDownloadInfoNeed()], [false, false, false],
  'new SomethingNeedRefresh() 三个标志全 false');
const b = SomethingNeedRefresh.bookmarkDrawNeedRefresh();
eq([b.isBookmarkDrawNeed(), b.isDownloadLabelDrawNeed(), b.isDownloadInfoNeed()], [true, false, false],
  'bookmarkDrawNeedRefresh() 只置 bookmarkDrawNeed');
const l = SomethingNeedRefresh.downloadLabelDrawNeedRefresh();
eq([l.isBookmarkDrawNeed(), l.isDownloadLabelDrawNeed(), l.isDownloadInfoNeed()], [false, true, false],
  'downloadLabelDrawNeedRefresh() 只置 downloadLabelDrawNeed');
const i2 = SomethingNeedRefresh.downloadInfoNeedRefresh();
eq([i2.isBookmarkDrawNeed(), i2.isDownloadLabelDrawNeed(), i2.isDownloadInfoNeed()], [false, false, true],
  'downloadInfoNeedRefresh() 只置 downloadInfoNeed');
snr.setBookmarkDrawNeed(true);
eq(snr.isBookmarkDrawNeed(), true, 'setter 生效');

// ── GalleryActivityEvent ──
const gi = { gid: 42, title: 'T' };
const evt = new GalleryActivityEvent(3, gi);
eq([evt.pagePosition, evt.galleryInfo === gi], [3, true], 'GalleryActivityEvent(pagePosition, galleryInfo) 构造与字段');

console.log('\n' + (fail === 0 ? 'ALL PASS' : fail + ' FAILED'));
process.exit(fail === 0 ? 0 : 1);
