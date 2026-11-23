// 其余 13 个 parser 的金样本测试（构造样本，非抓取页面）
//
// 覆盖：JSON 类（VoteComment/RateGallery/SignIn/GalleryTokenApi/GetEditComment）、
//      DOM 类（Forums/Profile/GalleryApi/GalleryPageApi/Torrent/EhEvent/TopList/MyTagLit/EhHome/Favorites）、
//      URL 类（GalleryListUrlParser）、以及各自的失败行为。

import { VoteCommentParser } from '../parser/VoteCommentParser';
import { RateGalleryParser } from '../parser/RateGalleryParser';
import { SignInParser } from '../parser/SignInParser';
import { GalleryTokenApiParser } from '../parser/GalleryTokenApiParser';
import { GetEditCommentParser } from '../parser/GetEditCommentParser';
import { ForumsParser } from '../parser/ForumsParser';
import { ProfileParser } from '../parser/ProfileParser';
import { GalleryApiParser } from '../parser/GalleryApiParser';
import { ComicInfoParser } from '../parser/ComicInfoParser';
import { InputStream } from '../../../unifile/Contracts';
import { GalleryPageApiParser } from '../parser/GalleryPageApiParser';
import { TorrentParser } from '../parser/TorrentParser';
import { EhEventParse } from '../parser/EhEventParse';
import { TopListParser } from '../parser/TopListParser';
import { MyTagLitParser } from '../parser/MyTagLitParser';
import { EhHomeParser } from '../parser/EhHomeParser';
import { FavoritesParser } from '../parser/FavoritesParser';
import { GalleryListUrlParser } from '../parser/GalleryListUrlParser';
import { Jsoup } from '../../../jsoup/index';
import { JsonObject } from '../parser/Json';
import { GalleryInfo } from './GalleryInfo';
import { ListUrlBuilder } from './ListUrlBuilder';
import { EhException } from '../exception/EhException';
import { ParseException } from '../exception/ParseException';
import { OffensiveException } from '../exception/MarkerExceptions';

let pass = 0;
let fail = 0;
const failures: string[] = [];

function eq(name: string, actual: unknown, expected: unknown): void {
  const a = JSON.stringify(actual);
  const e = JSON.stringify(expected);
  if (a === e) {
    pass++;
  } else {
    fail++;
    failures.push(`${name}\n    actual  = ${a}\n    expected= ${e}`);
  }
}

function ok(name: string, cond: boolean): void {
  if (cond) {
    pass++;
  } else {
    fail++;
    failures.push(name);
  }
}

function throwsType(name: string, fn: () => void, ctor: Function): void {
  try {
    fn();
    fail++;
    failures.push(name + '（未抛异常）');
  } catch (e) {
    if (e instanceof ctor) {
      pass++;
    } else {
      fail++;
      failures.push(name + `（抛的是 ${(e as Error).name}: ${(e as Error).message}）`);
    }
  }
}

// ---------- Json（org.json 强制转换语义） ----------
{
  const jo = JsonObject.parse('{"num":3,"str":"1234","flag":true,"nil":null,"arr":[1,2]}');
  eq('getString 数字 → "3"', jo.getString('num'), '3');
  eq('getString 布尔 → "true"', jo.getString('flag'), 'true');
  eq('getLong 字符串 → 1234', jo.getLong('str'), 1234);
  eq('has 真', jo.has('nil'), true);
  eq('isNull 显式 null', jo.isNull('nil'), true);
  eq('isNull 缺失', jo.isNull('nope'), true);
  eq('isNull 有值', jo.isNull('num'), false);
  eq('getJSONArray 长度', jo.getJSONArray('arr').length(), 2);
  throwsType('getString 缺失 → 抛', () => jo.getString('nope'), Error);
}

// ---------- VoteCommentParser ----------
{
  const r = VoteCommentParser.parse('{"comment_id":1253922,"comment_score":-19,"comment_vote":0}', 1);
  eq('vote.id', r.id, 1253922);
  eq('vote.score', r.score, -19);
  eq('vote.vote', r.vote, 0);
  eq('vote.expectVote（回填入参）', r.expectVote, 1);
}

// ---------- RateGalleryParser ----------
{
  const r = RateGalleryParser.parse('{"rating_avg":4.5,"rating_cnt":123}');
  eq('rate.rating', r.rating, 4.5);
  eq('rate.count', r.ratingCount, 123);
  eq('rate.ratingCls 默认空', r.ratingCls, '');
  eq('rate.isRatedHighlight() 默认 false', r.isRatedHighlight(), false);
  const rh = RateGalleryParser.parse('{"rating_avg":4.6,"rating_cnt":124,"rating_cls":"irg"}');
  eq('rate.ratingCls=irg', rh.ratingCls, 'irg');
  eq('rate.isRatedHighlight()=true', rh.isRatedHighlight(), true);
  throwsType('rate 非法 JSON → ParseException', () => RateGalleryParser.parse('nope'), ParseException);
  throwsType('rate 缺字段 → ParseException', () => RateGalleryParser.parse('{}'), ParseException);
}

// ---------- SignInParser ----------
{
  eq('signin 成功', SignInParser.parse('<p>You are now logged in as: someone<br>'), 'someone');
  throwsType('signin 错误页(h4) → EhException',
    () => SignInParser.parse('<h4>The error returned was:</h4><p>Bad password</p>'), EhException);
  throwsType('signin 错误页(postcolor) → EhException',
    () => SignInParser.parse('<span class="postcolor">Nope</span>'), EhException);
  throwsType('signin 都不匹配 → ParseException',
    () => SignInParser.parse('<html></html>'), ParseException);
}

// ---------- GalleryTokenApiParser ----------
{
  eq('token 正常', GalleryTokenApiParser.parse('{"tokenlist":[{"gid":618395,"token":"0439fa3666"}]}'),
    '0439fa3666');
  throwsType('token 缺失 → EhException(error)',
    () => GalleryTokenApiParser.parse('{"tokenlist":[{"gid":1,"error":"token error"}]}'), EhException);
}

// ---------- GetEditCommentParser ----------
{
  const r = GetEditCommentParser.parse(JSON.stringify({
    comment_id: 42,
    editable_comment: '<div><textarea name="commenttext_edit">hello &amp; bye</textarea></div>'
  }));
  eq('editcomment.id', r.id, 42);
  eq('editcomment.comment（实体已解码）', r.comment, 'hello & bye');
  throwsType('editcomment error 字段 → EhException',
    () => GetEditCommentParser.parse('{"error":"nope"}'), EhException);
  throwsType('editcomment 无 textarea → ParseException',
    () => GetEditCommentParser.parse('{"comment_id":1,"editable_comment":"<div></div>"}'), ParseException);
  throwsType('editcomment 非法 JSON → ParseException',
    () => GetEditCommentParser.parse('nope'), ParseException);
}

// ---------- ForumsParser ----------
{
  const html = '<html><body><div id="userlinks"><div><div><a href="/user.php?id=1">me</a></div></div></div></body></html>';
  eq('forums 取 href', ForumsParser.parse(html), '/user.php?id=1');
  throwsType('forums 缺 userlinks → ParseException',
    () => ForumsParser.parse('<html></html>'), ParseException);
}

// ---------- ProfileParser ----------
{
  const html = '<html><body><div id="profilename"><b>Someone</b></div>' +
    '<div>x</div><div><img src="/avatar/1.png"></div></body></html>';
  const r = ProfileParser.parse(html);
  eq('profile.displayName', r.displayName, 'Someone');
  eq('profile.avatar（相对路径补 forums 前缀）', r.avatar, 'https://forums.e-hentai.org//avatar/1.png');

  // 反代只转义 '<'（上游只 replaceAll("\\u003C", "<")），故样本里 '>' 保持原样 —— 这本身就是契约
  const escaped = '\\u003Cdiv id="userlinks">\\u003Cdiv>\\u003Cdiv>' +
    '\\u003Cb>NewName\\u003C/b>\\u003C/div>\\u003C/div>\\u003C/div>';
  const r2 = ProfileParser.parseNew(escaped);
  ok('profileNew.displayName 含 NewName', (r2.displayName as string).indexOf('NewName') >= 0);

  const r3 = ProfileParser.parseNew('ERR_CONNECTION_REFUSED whatever');
  eq('profileNew 连接拒绝 → 空 displayName', r3.displayName, '');

  throwsType('profile 缺 profilename → ParseException',
    () => ProfileParser.parse('<html><body></body></html>'), ParseException);
  throwsType('profile profilename 无子元素 → ParseException',
    () => ProfileParser.parse('<div id="profilename"></div>'), ParseException);
  throwsType('profileNew userlinks 层级不全 → ParseException',
    () => ProfileParser.parseNew('<div id="userlinks"><div></div></div>'), ParseException);
}

// ---------- Jsoup Parser 表格隐式 tbody / tr / colgroup ----------
{
  const d1 = Jsoup.parse('<table class="itg" border="1"><tr><td>A</td><td>B</td></tr><tr><td>C</td></tr></table>');
  const t1 = d1.selectFirst('table')!;
  eq('table 属性保留', [t1.attr('class'), t1.attr('border')], ['itg', '1']);
  eq('table.child(0) 自动补 tbody', t1.child(0)!.normalName(), 'tbody');
  eq('implicit tbody 含 2 个 tr', t1.child(0)!.children().size(), 2);
  eq('第一个 tr 含 2 个 td', t1.child(0)!.child(0)!.children().size(), 2);

  const d2 = Jsoup.parse('<table class="itg"><tbody><tr><td>A</td></tr></tbody></table>');
  const t2 = d2.selectFirst('table')!;
  eq('显式 tbody 不重复包裹', [t2.children().size(), t2.child(0)!.normalName(), t2.child(0)!.child(0)!.normalName()],
    [1, 'tbody', 'tr']);

  const d3 = Jsoup.parse('<table><thead><tr><th>H</th></tr></thead><tr><td>D</td></tr><tfoot><tr><td>F</td></tr></tfoot></table>');
  const t3 = d3.selectFirst('table')!;
  eq('thead + 隐式 tbody + tfoot 平级挂在 table 下',
    [t3.child(0)!.normalName(), t3.child(1)!.normalName(), t3.child(2)!.normalName()],
    ['thead', 'tbody', 'tfoot']);

  const d4 = Jsoup.parse('<table><col><col><tr><td>A</td></tr></table>');
  const t4 = d4.selectFirst('table')!;
  eq('col 自动补 colgroup 后再遇 tr 补 tbody',
    [t4.child(0)!.normalName(), t4.child(0)!.children().size(), t4.child(1)!.normalName()],
    ['colgroup', 2, 'tbody']);

  const d5 = Jsoup.parse('<table><td>X</td><td>Y</td></table>');
  const t5 = d5.selectFirst('table')!;
  eq('table 内直接 td 自动补 tbody+tr',
    [t5.child(0)!.normalName(), t5.child(0)!.child(0)!.normalName(), t5.child(0)!.child(0)!.children().size()],
    ['tbody', 'tr', 2]);

  const d6 = Jsoup.parse('<table><tr><td><table><tr><td>In</td></tr></table></td></tr></table>');
  const innerTable = d6.select('table').get(1);
  eq('嵌套 table 各自有隐式 tbody',
    [innerTable.child(0)!.normalName(), innerTable.child(0)!.child(0)!.text()],
    ['tbody', 'In']);

  const d7 = Jsoup.parse('<div><td>X</td></div>');
  eq('非 table 内 td 不插入 tbody', d7.selectFirst('div')!.child(0)!.normalName(), 'td');
}

// ---------- GalleryApiParser ----------
{
  const list: GalleryInfo[] = [new GalleryInfo()];
  list[0].gid = 100;
  const body = JSON.stringify({
    gmetadata: [{
      gid: 100, title: ' T ', title_jpn: ' J ', category: 'Manga',
      thumb: 'https://ehgt.org/t/a_250.jpg', uploader: 'up',
      posted: 1577934240, rating: 4.25,
      tags: ['language:chinese', 'male:male'], filecount: 42
    }, {
      gid: 999, title: 'ignored'
    }]
  });
  GalleryApiParser.parse(body, list);
  eq('api.title（trim）', list[0].title, 'T');
  eq('api.titleJpn', list[0].titleJpn, 'J');
  eq('api.category（Manga → 0x4）', list[0].category, 0x4);
  eq('api.uploader', list[0].uploader, 'up');
  eq('api.pages', list[0].pages, 42);
  eq('api.rating', list[0].rating, 4.25);
  eq('api.simpleTags', list[0].simpleTags, ['language:chinese', 'male:male']);
  ok('api.posted 已格式化', (list[0].posted as string).length > 0);
  ok('api.postedAt 已刷新（C-7）', list[0].postedAt > 0);
  eq('api.simpleLanguage（含 language:chinese → ZH）', list[0].simpleLanguage, 'ZH');
  eq('api 不新建对象（gid 999 忽略）', list.length, 1);

  // 上游 9cbb77f7：含 error 或 title 为 null 的画廊跳过，不中断同批其余画廊回填
  const giOk = new GalleryInfo();
  giOk.gid = 100;
  const giErr = new GalleryInfo();
  giErr.gid = 101;
  const giNullTitle = new GalleryInfo();
  giNullTitle.gid = 102;
  const batchBody = JSON.stringify({
    gmetadata: [
      { gid: 101, error: 'Key missing' },
      { gid: 102, title: null },
      {
        gid: 100, title: 'Valid After Error', title_jpn: '', category: 'Doujinshi',
        thumb: 'https://ehgt.org/t/b_250.jpg', uploader: 'up2',
        posted: 1577934240, rating: 4.0, tags: [], filecount: 10
      }
    ]
  });
  GalleryApiParser.parse(batchBody, [giErr, giNullTitle, giOk]);
  eq('api error 项被跳过（保持空 title）', giErr.title, '');
  eq('api title:null 项被跳过（保持空 title）', giNullTitle.title, '');
  eq('api 同批后续有效项仍成功回填', giOk.title, 'Valid After Error');
}

// ---------- ComicInfoParser（上游 9cbb77f7） ----------
{
  const makeStream = (bytes: Uint8Array): InputStream => {
    let pos = 0;
    return {
      read(): number {
        return pos >= bytes.length ? -1 : bytes[pos++];
      },
      readBuffer(buffer: ArrayBuffer): number {
        const view = new Uint8Array(buffer);
        let n = 0;
        while (n < view.length && pos < bytes.length) {
          view[n++] = bytes[pos++];
        }
        return n === 0 ? -1 : n;
      },
      readBytes(buffer: ArrayBuffer, off: number, len: number): number {
        const view = new Uint8Array(buffer);
        let n = 0;
        while (n < len && pos < bytes.length && off + n < view.length) {
          view[off + n] = bytes[pos++];
          n++;
        }
        return n === 0 ? -1 : n;
      },
      skip(n: number): number {
        const step = Math.min(n, bytes.length - pos);
        pos += step;
        return step;
      },
      available(): number {
        return bytes.length - pos;
      },
      close(): void { }
    };
  };

  const sampleXml =
    "<?xml version='1.0' encoding='UTF-8' ?>\n" +
    '<ComicInfo>\n' +
    '  <Series>Sanitized Sample Gallery</Series>\n' +
    '  <Web>https://exhentai.org/g/900000002/0000000000</Web>\n' +
    '  <PageCount>77</PageCount>\n' +
    '</ComicInfo>\n';

  const rStr = ComicInfoParser.parse(sampleXml);
  ok('ComicInfoParser.parse 从 Web 读取成功', rStr !== null);
  eq('ComicInfoParser.parse gid', rStr !== null ? rStr.gid : -1, 900000002);
  eq('ComicInfoParser.parse token', rStr !== null ? rStr.token : '', '0000000000');

  const encodeUtf8 = (s: string): Uint8Array => {
    const out: number[] = [];
    for (let i = 0; i < s.length; i++) {
      const c = s.charCodeAt(i);
      if (c < 0x80) {
        out.push(c);
      } else if (c < 0x800) {
        out.push(0xC0 | (c >> 6), 0x80 | (c & 0x3F));
      } else if (c >= 0xD800 && c <= 0xDBFF && i + 1 < s.length) {
        const c2 = s.charCodeAt(i + 1);
        const cp = 0x10000 + ((c - 0xD800) << 10) + (c2 - 0xDC00);
        out.push(0xF0 | (cp >> 18), 0x80 | ((cp >> 12) & 0x3F), 0x80 | ((cp >> 6) & 0x3F), 0x80 | (cp & 0x3F));
        i++;
      } else {
        out.push(0xE0 | (c >> 12), 0x80 | ((c >> 6) & 0x3F), 0x80 | (c & 0x3F));
      }
    }
    return new Uint8Array(out);
  };

  const sampleXmlUtf8 =
    "<?xml version='1.0' encoding='UTF-8' ?>\n" +
    '<ComicInfo>\n' +
    '  <Series>中文标题😀</Series>\n' +
    '  <Web>https://exhentai.org/g/900000002/0000000000</Web>\n' +
    '  <PageCount>77</PageCount>\n' +
    '</ComicInfo>\n';
  const sampleBytes = encodeUtf8(sampleXmlUtf8);
  const rStream = ComicInfoParser.parseStream(makeStream(sampleBytes));
  ok('ComicInfoParser.parseStream 成功', rStream !== null);
  eq('ComicInfoParser.parseStream gid', rStream !== null ? rStream.gid : -1, 900000002);
  eq('ComicInfoParser.parseStream token', rStream !== null ? rStream.token : '', '0000000000');

  eq('ComicInfoParser 无 Web → null', ComicInfoParser.parse('<ComicInfo><Series>Only</Series></ComicInfo>'), null);
  eq('ComicInfoParser 空串 → null', ComicInfoParser.parse(''), null);
  eq('ComicInfoParser null → null', ComicInfoParser.parse(null), null);
  eq('ComicInfoParser.parseStream(null) → null', ComicInfoParser.parseStream(null), null);

  const oversized = new Uint8Array(256 * 1024 + 10);
  oversized.fill(0x20);
  eq('ComicInfoParser.parseStream 超 256KB → null', ComicInfoParser.parseStream(makeStream(oversized)), null);
}

// ---------- GalleryPageApiParser ----------
{
  const body = JSON.stringify({
    i3: '<img id="img" src="https://x/1.jpg" style="x">',
    i6: '<a href="#" onclick="return nl(\'abc123\')">skip</a>' +
      '<a href="#" onclick="prompt(\'Copy the URL below.\', \'https://x/other.jpg\')">other</a>',
    i7: null
  });
  const r = GalleryPageApiParser.parse(body);
  eq('pageapi.imageUrl', r.imageUrl, 'https://x/1.jpg');
  eq('pageapi.skipHathKey', r.skipHathKey, 'abc123');
  eq('pageapi.otherImageUrl', r.otherImageUrl, 'https://x/other.jpg');

  const body2 = JSON.stringify({
    i3: '<img src="https://x/2.jpg" style="y">', i6: '',
    i7: '<a href="https://x/fullimg-path">big</a>'
  });
  const r2 = GalleryPageApiParser.parse(body2);
  eq('pageapi.originImageUrl（拼 fullimg）', r2.originImageUrl, 'https://x/fullimg-path');
  throwsType('pageapi error 字段 → ParseException',
    () => GalleryPageApiParser.parse('{"error":"nope"}'), ParseException);
  throwsType('pageapi 无 imageUrl → ParseException',
    () => GalleryPageApiParser.parse('{"i3":"","i6":"","i7":null}'), ParseException);
}

// ---------- TorrentParser ----------
{
  const html = '<form><span>Posted: </span><span>2020-01-02 03:04</span>' +
    '<table><tr><td colspan="5">&nbsp;<a href="https://e-hentai.org/torrent/1.torrent?p=9">Name</a></td></tr></table></form>' +
    '<form><td colspan="5">&nbsp;<a href="https://e-hentai.org/torrent/2.torrent">Name2</a></td></form>';
  const list = TorrentParser.parse(html);
  eq('torrent 2 条', list.length, 2);
  eq('torrent[0].url（去掉 ?p=）', list[0].url, 'https://e-hentai.org/torrent/1.torrent');
  eq('torrent[0].name', list[0].name, 'Name');
  eq('torrent[0].posted', list[0].posted, '2020-01-02 03:04');
  eq('torrent[1].posted（缺省空）', list[1].posted, '');
}

// ---------- EhEventParse ----------
{
  eq('event 取 innerHTML',
    EhEventParse.parse('<html><body><div id="eventpane"><p>hi</p></div></body></html>'),
    '<p>hi</p>');
  eq('event 缺失 → null', EhEventParse.parse('<html></html>'), null);
}

// ---------- GalleryListUrlParser ----------
{
  const b1 = GalleryListUrlParser.parse('https://e-hentai.org/?f_search=a+b&f_cats=1017');
  ok('listUrl 根路径 → MODE_NORMAL', b1 !== null && b1.getMode() === ListUrlBuilder.MODE_NORMAL);
  eq('listUrl 根路径 keyword 解码', b1 === null ? null : b1.getKeyword(), 'a b');

  const b2 = GalleryListUrlParser.parse('https://e-hentai.org/uploader/some%20up/2');
  ok('listUrl uploader 模式', b2 !== null && b2.getMode() === ListUrlBuilder.MODE_UPLOADER);
  eq('listUrl uploader keyword', b2 === null ? null : b2.getKeyword(), 'some up');

  const b3 = GalleryListUrlParser.parse('https://exhentai.org/tag/language%3Achinese');
  ok('listUrl tag 模式', b3 !== null && b3.getMode() === ListUrlBuilder.MODE_TAG);
  eq('listUrl tag keyword', b3 === null ? null : b3.getKeyword(), 'language:chinese');

  const b4 = GalleryListUrlParser.parse('https://e-hentai.org/6');
  eq('listUrl 分类路径 → category=6', b4 === null ? -1 : b4.getCategory(), 6);

  eq('listUrl 非三站域名 → null', GalleryListUrlParser.parse('https://example.com/'), null);
  eq('listUrl 非法 URL → null', GalleryListUrlParser.parse('not a url'), null);
}

// ---------- TopListParser ----------
{
  const item = (v: string): string => `<div class="tun"><a href="/g/${v}">${v}</a></div>`;
  // 上游 parseInfo 取 segment.child(1).child(0) 再在它里面找 .tun，故结构必须是
  // <div><span/><div><div class="tunbox">…</div></div></div>
  const seg = (): string => `<div><span>t</span><div><div class="tunbox">${item('a')}${item('b')}</div></div></div>`;
  // 每个榜单是一个**包一层的 div**（ido 的第 1/3/5/7/9/11/13 个子元素），内部才排 4 个时间段
  const info = (): string => `<div><div>x</div>${seg()}${seg()}${seg()}${seg()}</div>`;
  // 真实页面 `.ido` 有 14 个子元素：标题 + (榜单, 分隔) × 7 → 榜单在 1/3/5/7/9/11/13
  const sep = (): string => `<div class="sep"></div>`;
  const body7 = Array.from({ length: 7 }, () => `${info()}${sep()}`).join('');
  const html = `<html><body><div class="ido"><div>Top Title</div>` +
    `${body7}</div></body></html>`;
  const d = TopListParser.parse(html);
  eq('toplist.title', d.title, 'Top Title');
  ok('toplist 七个榜单都有', d.get(0) !== null && d.get(6) !== null && d.get(7) === null);
  eq('toplist.gallery.type', (d.galleryTopListInfo as { type: number }).type, 0);
  const arr = (d.galleryTopListInfo as { allTimeTopList: { length(): number; get(i: number): { value: string; href: string } } }).allTimeTopList;
  eq('toplist allTime 长度', arr.length(), 2);
  eq('toplist allTime[0].value', arr.get(0).value, 'a');
  eq('toplist allTime[0].href', arr.get(0).href, '/g/a');
  throwsType('toplist offensive → OffensiveException',
    () => TopListParser.parse('<p>(And if you choose to ignore this warning, you lose all rights to complain about it in the future.)</p>'),
    OffensiveException);
}

// ---------- MyTagLitParser ----------
{
  const html = '<html><body><div id="usertags_outer">' +
    '<div>header（跳过）</div>' +
    '<div id="usertag_12345">' +
    '<div id="tagpreview_12345" title="female:swimsuit"></div>' +
    '<input id="tagwatch_12345" checked="checked"><input id="taghide_12345">' +
    '<input id="tagcolor_12345" placeholder="ff0000"><input id="tagweight_12345" value="10">' +
    '</div></div></body></html>';
  const list = MyTagLitParser.parse(html);
  eq('mytag 1 条（跳过第 0 个）', list.size(), 1);
  const t = list.get(0);
  eq('mytag.userTagId', t.userTagId, 'usertag_12345');
  eq('mytag.tagName', t.tagName, 'female:swimsuit');
  eq('mytag.watched', t.watched, true);
  eq('mytag.hidden', t.hidden, false);
  eq('mytag.color', t.color, 'ff0000');
  eq('mytag.tagWeight', t.tagWeight, 10);
  eq('mytag.getId()', t.getId(), 12345);
  ok('mytag.deleteParam 含 modify_usertags%5B%5D=12345',
    t.deleteParam().indexOf('modify_usertags%5B%5D=12345') >= 0);

  throwsType('mytag 错误页 → EhException',
    () => MyTagLitParser.parse('<div class="d">\n<p>Some error</p>'), EhException);
  eq('mytag 缺 usertags_outer → 空列表', MyTagLitParser.parse('<html></html>').size(), 0);
}

// ---------- EhHomeParser ----------
{
  const html = '<html><body>' +
    '<div class="homebox"><div><p>You are currently at <strong>10</strong> towards a limit of <strong>5000</strong>.</p>' +
    '\\n<p>Reset Cost: <strong>100</strong> GP</p></div></div>' +
    '<div class="homebox">b</div>' +
    '<div class="homebox"><div><div><div><div>1,000</div></div><div><div>2,000</div></div>' +
    '<div><div>3,000</div></div><div><div>4,000</div></div></div></div></div>' +
    '<div class="homebox">d</div>' +
    '<div class="homebox"><div><div><div><div><div>9,999</div></div></div></div></div></div>' +
    '</body></html>';
  const h = EhHomeParser.parse(html);
  eq('home.used', h.getUsed(), 10);
  eq('home.total', h.getTotal(), 5000);
  eq('home.resetCost()', h.resetCost(), 100);
  eq('home.getResetCost()（带 Gp）', h.getResetCost(), '100 Gp');
  eq('home.fromGalleryVisits（带 Gp）', h.getFromGalleryVisits(), '1000 Gp');
  eq('home.getImageLimits', h.getImageLimits({ getIpBaseLimits: (): string => 'IP' }), '10/5000');
  eq('home 空页面 → 全 0', EhHomeParser.parse('<html></html>').getUsed(), 0);

  // Harmony jsoup Element.html() 无换行拼接 + 千分位逗号
  const realHtml = '<html><body><div class="homebox"><div>' +
    '<p>You are currently at <strong>1,250</strong> towards your account limit of <strong>5,000</strong>.</p>' +
    '<p>You can reset your image quota by spending <strong>150</strong> GP.</p>' +
    '</div></div></body></html>';
  const rh = EhHomeParser.parse(realHtml);
  eq('home real no-newline used', rh.getUsed(), 1250);
  eq('home real no-newline total', rh.getTotal(), 5000);
  eq('home real no-newline resetCost', rh.resetCost(), 150);
  eq('home real no-newline getImageLimits', rh.getImageLimits({ getIpBaseLimits: (): string => 'IP' }), '1250/5000');

  // 无重置费用段落时兜底解析 used/total
  const freeHtml = '<html><body><div class="homebox"><div>' +
    '<p>You are currently at <strong>42</strong> towards your account limit of <strong>5,000</strong>.</p>' +
    '<p>No reset needed.</p></div></div></body></html>';
  const fh = EhHomeParser.parse(freeHtml);
  eq('home fallback used', fh.getUsed(), 42);
  eq('home fallback total', fh.getTotal(), 5000);
  eq('home fallback resetCost', fh.resetCost(), 0);
}

// ---------- FavoritesParser ----------
{
  const fps: string = Array.from({ length: 11 }, (_v, i) =>
    `<div class="fp"><div>${i}</div><div>x</div><div>${i === 10 ? '' : 'cat' + i}</div></div>`).join('');
  const html = '<html><body><div class="ido">' + fps +
    '<div class="searchnav"><select><option value="f" selected>F</option></select></div></div>' +
    '<table class="ptt"><tbody><tr><td><div>1</div></td><td>1</td><td><a href="?page=1">n</a></td></tr></tbody></table>' +
    // 收藏页也要有一条真实画廊项，否则 GalleryListParser 会以 "Can't parse gallery list" 失败
    '<div class="itg gld"><div class="gl1e"><div class="glink glname">' +
    '<a href="https://e-hentai.org/g/1234567/abcdef0123/">Fav Item</a></div></div></div>' +
    '</body></html>';
  const r = FavoritesParser.parse(html);
  eq('fav.countArray[3]', r.countArray[3], 3);
  eq('fav.catArray[3]', r.catArray[3], 'cat3');
  eq('fav.favOrder', r.favOrder, 'f');
  eq('fav.pages', r.pages, 1);

  throwsType('fav 未登录 → EhException',
    () => FavoritesParser.parse('<p>This page requires you to log on.</p>'), EhException);
  throwsType('fav .fp 数量不对 → ParseException',
    () => FavoritesParser.parse('<html><body><div class="ido"><div class="fp"></div></div></body></html>'),
    ParseException);
}

// ---------- 汇总 ----------
console.log(`\n=== 结果：${pass} passed, ${fail} failed ===`);
if (fail > 0) {
  for (const f of failures) {
    console.log('  FAIL ' + f);
  }
  throw new Error('parser 断言失败：' + fail);
}
