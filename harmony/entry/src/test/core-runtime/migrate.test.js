// EhDB.migrate() 的 SQL 文本断言（P3 验收：必须能导入原 App 的 .db，表结构需与上游逐字一致）
// 做法：从 EhDB.ets 的 migrate() 里抽出所有单引号 SQL 片段，按语句拼起来，与上游 Java 的
// db.execSQL(...) 参数逐条对比。上游文本来自
//   git show origin/upstream:app/src/main/java/com/hippo/ehviewer/EhDB.java (L109-185)
const fs = require('fs');
const path = require('path');

const srcPath = process.argv[2] || path.join(__dirname, '../../main/ets/hippo/ehviewer/EhDB.ets');
const src = fs.readFileSync(srcPath, 'utf8');

// 只取 migrate 方法体
const start = src.indexOf('static async migrate(');
if (start < 0) { console.error('FAIL: 找不到 migrate 方法'); process.exit(1); }
const body = src.slice(start, src.indexOf('// ── ', start) > 0 ? src.indexOf('// ── ', start) : src.length);

// 抽 SQL：所有 executeSql('...') 的实参（允许跨行字符串拼接）
const stmts = [];
const re = /executeSql\(\s*((?:'[^']*'\s*\+?\s*)+)\)/g;
let m;
while ((m = re.exec(body)) !== null) {
  const parts = m[1].match(/'[^']*'/g) || [];
  stmts.push(parts.map(p => p.slice(1, -1)).join(''));
}

// 上游逐字期望（从 Java 源码抄，去掉 Java 字符串拼接符）
const EXPECT = {
  to3: [
    'CREATE TABLE "FILTER2" ("_id" INTEGER PRIMARY KEY ,"MODE" INTEGER NOT NULL ,"TEXT" TEXT,"ENABLE" INTEGER);',
    'INSERT INTO "FILTER2" (_id, MODE, TEXT, ENABLE)SELECT _id, MODE, TEXT, 1 FROM [FILTER];',
    'DROP TABLE [FILTER]',
    'ALTER TABLE FILTER2 RENAME TO [FILTER]',
  ],
  to4: [
    'CREATE TABLE "QUICK_SEARCH2" ("_id" INTEGER PRIMARY KEY ,"NAME" TEXT,"MODE" INTEGER NOT NULL ,"CATEGORY" INTEGER NOT NULL ,"KEYWORD" TEXT,"ADVANCE_SEARCH" INTEGER NOT NULL ,"MIN_RATING" INTEGER NOT NULL ,"PAGE_FROM" INTEGER NOT NULL ,"PAGE_TO" INTEGER NOT NULL ,"TIME" INTEGER NOT NULL );',
    'INSERT INTO "QUICK_SEARCH2" (_id, NAME, MODE, CATEGORY, KEYWORD, ADVANCE_SEARCH, MIN_RATING, PAGE_FROM, PAGE_TO, TIME)SELECT _id, NAME, MODE, CATEGORY, KEYWORD, ADVANCE_SEARCH, MIN_RATING, -1, -1, TIME FROM QUICK_SEARCH;',
    'DROP TABLE QUICK_SEARCH',
    'ALTER TABLE QUICK_SEARCH2 RENAME TO QUICK_SEARCH',
  ],
  to5: [
    'DROP TABLE IF EXISTS "Black_List"',
    'CREATE TABLE "Black_List" ("_id" INTEGER PRIMARY KEY AUTOINCREMENT ,"BADGAYNAME" TEXT,"REASON" TEXT,"ANGRYWITH" TEXT,"ADD_TIME" TEXT,"MODE" INTEGER);',
  ],
  to6: [
    'DROP TABLE IF EXISTS "Gallery_Tags"',
    'CREATE TABLE "Gallery_Tags" ("GID" INTEGER PRIMARY KEY NOT NULL ,"ROWS" TEXT,"ARTIST" TEXT,"COSPLAYER" TEXT,"CHARACTER" TEXT,"FEMALE" TEXT,"GROUP" TEXT,"LANGUAGE" TEXT,"MALE" TEXT,"MISC" TEXT,"MIXED" TEXT,"OTHER" TEXT,"PARODY" TEXT,"RECLASS" TEXT,"CREATE_TIME" INTEGER,"UPDATE_TIME" INTEGER);',
  ],
  to7: ['ALTER TABLE "DOWNLOADS" ADD COLUMN "ARCHIVE_URI" TEXT'],
  to8: ['ALTER TABLE "Gallery_Tags" ADD COLUMN "LOCATION" TEXT'],
};
const ALL = [].concat(EXPECT.to3, EXPECT.to4, EXPECT.to5, EXPECT.to6, EXPECT.to7, EXPECT.to8);

let fail = 0;
const eq = (a, b, label) => {
  if (a === b) { console.log('  PASS  ' + label); }
  else { fail++; console.log('  FAIL  ' + label + '\n    实际: ' + JSON.stringify(a) + '\n    期望: ' + JSON.stringify(b)); }
};

// 1) 语句总数与顺序
eq(stmts.length, ALL.length, 'SQL 语句总数 = ' + ALL.length);
ALL.forEach((want, i) => eq(stmts[i], want, '第 ' + (i + 1) + ' 条逐字一致'));

// 2) 版本分级顺序判断（不能是 switch/fall-through 依赖）
eq(/if \(oldVersion < 3\)/.test(body), true, '使用 if (oldVersion < n) 顺序判断');
eq(/switch\s*\(/.test(body), false, '不使用 switch（防 fall-through 语义）');

// 3) 事务包裹
eq(/beginTransaction\(\)/.test(body), true, 'beginTransaction');
eq(/store\.commit\(\)/.test(body), true, 'commit');
eq(/rollBack\(\)/.test(body), true, '失败时 rollBack');
eq(/throw e as Error/.test(body), true, '回滚后重新抛出');

// 4) 两条 ALTER 允许吞异常
const alterTryCount = (body.match(/try\s*\{\s*await store\.executeSql\('ALTER TABLE/g) || []).length;
eq(alterTryCount, 2, '两条 ALTER 各自 try/catch（列已存在可吞）');

console.log('\n' + (fail === 0 ? 'ALL PASS' : fail + ' FAILED'));
process.exit(fail === 0 ? 0 : 1);
