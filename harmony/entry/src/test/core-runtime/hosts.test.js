// Hosts：isValidHost / parseV4 / parseV6 / toInetAddress / CRUD + RdbHostsStore
global.Observed = (target) => target;
const path = require('path');
const OUT = process.argv[2] || path.join(process.env.TEMP, 'tscheck', 'out11');
const { Hosts, HostIpPair, RdbHostsStore } = require(path.join(OUT, 'ehviewer', 'Hosts.js'));

let fail = 0;
const eq = (a, b, label) => {
  const A = JSON.stringify(a), B = JSON.stringify(b);
  if (A === B) console.log('  PASS  ' + label);
  else { fail++; console.log('  FAIL  ' + label + '\n    实际: ' + A + '\n    期望: ' + B); }
};
const arr = (u8) => (u8 === null ? null : Array.from(u8));

(async () => {
  // ── isValidHost ──
  eq(Hosts.isValidHost('example.com'), true, 'isValidHost: 正常域名 → true');
  eq(Hosts.isValidHost(null), false, 'null → false');
  eq(Hosts.isValidHost(''), false, '空串 → false（labelLength=0）');
  eq(Hosts.isValidHost('EXAMPLE.COM'), false, '**大写 → false**（上游只接受小写，照搬）');
  eq(Hosts.isValidHost('a_b.com'), false, '下划线 → false');
  eq(Hosts.isValidHost('a b.com'), false, '空格 → false');
  eq(Hosts.isValidHost('-a.com'), true, '开头连字符 → true（上游不禁止）');
  eq(Hosts.isValidHost('a..com'), false, '连续点 → false');
  eq(Hosts.isValidHost('.com'), false, '开头点 → false');
  eq(Hosts.isValidHost('com.'), false, '结尾点 → false');
  eq(Hosts.isValidHost('a'.repeat(63) + '.com'), true, '63 字符 label → true（上限内）');
  eq(Hosts.isValidHost('a'.repeat(64) + '.com'), false, '64 字符 label → false（超限）');
  eq(Hosts.isValidHost(['a'.repeat(63), 'a'.repeat(63), 'a'.repeat(63), 'a'.repeat(61)].join('.')), true,
    '253 字符（63.63.63.61）→ true（总长上限内且每段 ≤63）');
  eq(Hosts.isValidHost('a'.repeat(253)), false, '单段 253 字符 → false（段长 63 上限先触发）');
  eq(Hosts.isValidHost('a'.repeat(254)), false, '254 字符 → false（超总长）');
  eq(Hosts.isValidHost('192.168.1.1'), true, '纯数字域名形式 → true（isValidHost 不看语义）');

  // ── parseV4 ──
  eq(arr(Hosts.parseV4('127.0.0.1')), [127, 0, 0, 1], 'parseV4: 127.0.0.1');
  eq(arr(Hosts.parseV4('0.0.0.0')), [0, 0, 0, 0], 'parseV4: 0.0.0.0');
  eq(arr(Hosts.parseV4('255.255.255.255')), [255, 255, 255, 255], 'parseV4: 上界 255.255.255.255');
  eq(Hosts.parseV4('256.0.0.1'), null, 'parseV4: 256 → null（超 255）');
  eq(Hosts.parseV4('1.2.3'), null, 'parseV4: 只有 3 段 → null（**严格**，不像 inet_aton）');
  eq(Hosts.parseV4('1.2.3.4.5'), null, 'parseV4: 5 段 → null');
  eq(Hosts.parseV4('1..2.3'), null, 'parseV4: 连续点 → null');
  eq(Hosts.parseV4('1.2.3.'), null, 'parseV4: 结尾点 → null（第 4 段为空）');
  eq(Hosts.parseV4('01.2.3.4'), null, 'parseV4: 前导 0 → null（上游注释 Octets should not start with 0）');
  eq(arr(Hosts.parseV4('0.1.2.3')), [0, 1, 2, 3], 'parseV4: 单写 0 合法');
  eq(Hosts.parseV4('1234.1.1.1'), null, 'parseV4: 4 位数字 → null');
  eq(Hosts.parseV4('1.2.3.a'), null, 'parseV4: 非数字 → null');
  eq(Hosts.parseV4(''), null, 'parseV4: 空串 → null');
  eq(Hosts.parseV4(' 1.2.3.4'), null, 'parseV4: 前导空格 → null');

  // ── parseV6 ──
  eq(arr(Hosts.parseV6('::1')), [0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1], 'parseV6: ::1（回环）');
  eq(arr(Hosts.parseV6('::')), [0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0], 'parseV6: :: （全零）');
  eq(arr(Hosts.parseV6('2001:db8::1')),
    [0x20,0x01,0x0d,0xb8,0,0,0,0,0,0,0,0,0,0,0,1], 'parseV6: 2001:db8::1');
  const full = '1:2:3:4:5:6:7:8';
  eq(arr(Hosts.parseV6(full)), [0,1,0,2,0,3,0,4,0,5,0,6,0,7,0,8], 'parseV6: 完整 8 段');
  eq(Hosts.parseV6('1:2:3:4:5:6:7:8:9'), null, 'parseV6: 9 段 → null');
  eq(arr(Hosts.parseV6('::ffff:192.168.0.1')),
    [0,0,0,0,0,0,0,0,0,0,0xff,0xff,192,168,0,1], 'parseV6: ::ffff:192.168.0.1 → 映射地址');
  eq(Hosts.parseV6('1:2:3:4:5:6:7:192.168.0.1'), null, 'parseV6: IPv4 前已有 7 段 → null（i>6）');
  eq(Hosts.parseV6('1::2::3'), null, 'parseV6: 两个 :: → null');
  eq(Hosts.parseV6(':1:2:3:4:5:6:7'), null, 'parseV6: 单冒号开头 → null');
  eq(Hosts.parseV6('1:2:3:4:5:6:7:'), null, 'parseV6: 单冒号结尾 → null');
  eq(Hosts.parseV6('gggg::1'), null, 'parseV6: 非十六进制 → null');
  eq(Hosts.parseV6('1:2:3'), null, 'parseV6: 3 段且无 :: → null（长度不足 16 字节）');

  // ── isValidIp ──
  eq(Hosts.isValidIp('8.8.8.8'), true, 'isValidIp: v4 → true');
  eq(Hosts.isValidIp('::1'), true, 'isValidIp: v6 → true');
  eq(Hosts.isValidIp('nope'), false, 'isValidIp: 非法 → false');
  eq(Hosts.isValidIp(null), false, 'isValidIp: null → false');

  // ── toInetAddress ──
  eq(arr(Hosts.toInetAddress('example.com', '1.2.3.4')), [1, 2, 3, 4], 'toInetAddress: 正常 v4');
  eq(Hosts.toInetAddress('EXAMPLE.COM', '1.2.3.4'), null, 'toInetAddress: host 非法 → null（即使 ip 合法）');
  eq(Hosts.toInetAddress('example.com', null), null, 'toInetAddress: ip=null → null');
  eq(Hosts.toInetAddress('example.com', 'bad'), null, 'toInetAddress: ip 无法解析 → null');

  // ── CRUD（注入 store）──
  const rows = new Map([['a.com', ['1.1.1.1']], ['b.com', ['2.2.2.2', 'bad', '3.3.3.3']]]);
  const store = {
    queryIps: async (h) => (rows.get(h) || []),
    queryAll: async () => {
      const out = [];
      rows.forEach((ips, h) => ips.forEach((ip) => out.push(new HostIpPair(h, ip))));
      return out;
    },
    contains: async (h) => rows.has(h),
    upsert: async (h, ip) => { rows.set(h, [ip]); },
    deleteByHost: async (h) => { rows.delete(h); },
  };
  const hosts = new Hosts(store);

  eq(arr(await hosts.get('a.com')), [1, 1, 1, 1], 'get: 命中 → 返回首个 IP 字节');
  eq(await hosts.get('nope.com'), null, 'get: 无记录 → null');
  eq(await hosts.get('BAD.com'), null, 'get: host 非法 → null（不查库）');
  eq((await hosts.getList('b.com')).length, 2, 'getList: 跳过无法解析的行（3 条里 2 条有效）');
  eq(await hosts.getList('BAD.com'), null, 'getList: host 非法 → null');
  eq(await hosts.put('c.com', '4.4.4.4'), true, 'put: 合法 → true 并写入');
  eq(await hosts.put('c.com', 'bad-ip'), false, 'put: ip 非法 → false 且**不改库**');
  eq((await hosts.getList('c.com')).length, 1, '…c.com 仍是原来的 4.4.4.4');
  eq(await hosts.put('BAD.com', '4.4.4.4'), false, 'put: host 非法 → false');
  await hosts.delete('a.com');
  eq(await hosts.get('a.com'), null, 'delete 后 get → null');
  const all = await hosts.getAll();
  eq(all.every((p) => Hosts.isValidIp(p.ip)), true, 'getAll: 只返回 IP 可解析的行');

  // ── RdbHostsStore（SELECT/INSERT/UPDATE/DELETE + isColumnNull + 写串行化）──
  const tableRows = [
    { HOST: 'null.com', IP: null },
    { HOST: null, IP: '1.2.3.4' },
    { HOST: 'e-hentai.org', IP: '104.20.134.21' },
  ];
  let createCalls = 0;
  const makeResultSet = (subset) => {
    let idx = -1;
    let closed = false;
    return {
      goToNextRow: () => (++idx < subset.length),
      getColumnIndex: (name) => (name === 'HOST' ? 0 : name === 'IP' ? 1 : -1),
      isColumnNull: (colIdx) => {
        const row = subset[idx];
        return colIdx === 0 ? (row.HOST === null || row.HOST === undefined)
          : (row.IP === null || row.IP === undefined);
      },
      getString: (colIdx) => (colIdx === 0 ? subset[idx].HOST : subset[idx].IP),
      close: () => { closed = true; },
    };
  };
  const fakeDb = {
    querySql: async (sql, args) => {
      await Promise.resolve();
      if (sql.indexOf('WHERE HOST = ?') >= 0) {
        const h = args[0];
        return makeResultSet(tableRows.filter((r) => r.HOST === h));
      }
      return makeResultSet(tableRows.slice());
    },
    executeSql: async (sql, args) => {
      await Promise.resolve();
      if (sql.startsWith('CREATE TABLE')) {
        createCalls++;
        return;
      }
      if (sql.startsWith('INSERT INTO HOSTS')) {
        tableRows.push({ HOST: args[0], IP: args[1] });
        return;
      }
      if (sql.startsWith('UPDATE HOSTS')) {
        for (let i = 0; i < tableRows.length; i++) {
          if (tableRows[i].HOST === args[1]) {
            tableRows[i].IP = args[0];
          }
        }
        return;
      }
      if (sql.startsWith('DELETE FROM HOSTS')) {
        for (let i = tableRows.length - 1; i >= 0; i--) {
          if (tableRows[i].HOST === args[0]) {
            tableRows.splice(i, 1);
          }
        }
      }
    },
  };
  const rdbStore = new RdbHostsStore(fakeDb);
  await Promise.all([rdbStore.ensureTable(), rdbStore.ensureTable()]);
  eq(createCalls, 1, 'RdbHostsStore.ensureTable 幂等去重');

  const rdbHosts = new Hosts(rdbStore);
  eq(arr(await rdbHosts.get('e-hentai.org')), [104, 20, 134, 21], 'RdbHostsStore 读已有行');
  eq(await rdbHosts.get('null.com'), null, 'RdbHostsStore isColumnNull 跳过 NULL IP 行');
  eq((await rdbHosts.getAll()).length, 1, 'RdbHostsStore getAll 跳过 NULL HOST/IP 脏行');

  // 并发 put 同一 host → 写串行化，最终只产生 1 行且为最新 IP
  await Promise.all([
    rdbHosts.put('exhentai.org', '178.175.128.254'),
    rdbHosts.put('exhentai.org', '178.175.132.20'),
  ]);
  const exRows = tableRows.filter((r) => r.HOST === 'exhentai.org');
  eq([exRows.length, exRows[0].IP], [1, '178.175.132.20'], 'RdbHostsStore 并发 upsert 串行化无重复行');

  await rdbHosts.delete('exhentai.org');
  eq(await rdbStore.contains('exhentai.org'), false, 'RdbHostsStore deleteByHost 删除成功');

  // === 4) 内存热缓存命中 + put/delete/clearCache 失效 ===
  let queryCount = 0;
  const cachedMap = new Map([['ehgt.org', ['185.132.132.79']]]);
  const countingStore = {
    async queryIps(host) {
      queryCount++;
      const arr = cachedMap.get(host);
      return arr ? arr.slice() : [];
    },
    async queryAll() { return []; },
    async contains(host) { return cachedMap.has(host); },
    async upsert(host, ip) { cachedMap.set(host, [ip]); },
    async deleteByHost(host) { cachedMap.delete(host); }
  };
  const cachedHosts = new Hosts(countingStore);
  const firstList = await cachedHosts.getList('ehgt.org');
  const secondList = await cachedHosts.getList('ehgt.org');
  const thirdSingle = await cachedHosts.get('ehgt.org');
  eq(queryCount, 1, 'Hosts.getList/get 命中内存缓存仅查库一次');
  eq(firstList.length, 1, '首次 getList 返回 1 条地址');
  eq(secondList.length, 1, '第二次 getList 命中缓存仍返回 1 条地址');
  eq(thirdSingle !== null, true, 'Hosts.get 复用同一主机缓存');

  await cachedHosts.put('ehgt.org', '62.112.8.152');
  eq(queryCount, 1, 'put 仅写库并清缓存（不立即查库）');
  await cachedHosts.getList('ehgt.org');
  eq(queryCount, 2, 'put 使热缓存失效后再次查询才查库');

  await cachedHosts.delete('ehgt.org');
  const afterDel = await cachedHosts.getList('ehgt.org');
  eq(queryCount, 3, 'delete 使热缓存失效后再次查询');
  eq(afterDel.length, 0, 'delete 后查得空列表');

  cachedHosts.clearCache();
  await cachedHosts.getList('ehgt.org');
  eq(queryCount, 4, 'clearCache 清空后再次查询');

  console.log('\n' + (fail === 0 ? 'ALL PASS' : fail + ' FAILED'));
  process.exit(fail === 0 ? 0 : 1);
})();
