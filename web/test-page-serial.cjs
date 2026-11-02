'use strict';
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

const html = fs.readFileSync(path.join(__dirname, 'index.html'), 'utf8');
const scripts = [...html.matchAll(/<script\b[^>]*src="([^"]+)"/g)].map(m => m[1]);
const elements = new Map(), writes = [], intervals = [], ports = [];
let time = 100;
const drawing = new Proxy({}, { get: (target, key) => target[key] || (() => {}) });
for (const [, tag, attrs, id] of html.matchAll(/<([a-z][a-z0-9-]*)\b([^>]*\bid="([^"]+)"[^>]*)>/gi)) {
  elements.set(id, {
    value: /\bvalue="([^"]*)"/.exec(attrs)?.[1] || '',
    disabled: /\sdisabled(?:\s|$)/.test(attrs), hidden: /\shidden(?:\s|$)/.test(attrs),
    textContent: '', innerHTML: '', style: {}, handlers: {},
    classList: { toggle() {} }, clientWidth: 900, clientHeight: 370,
    getContext() { return drawing; }, click() {},
    addEventListener(event, handler) { (this.handlers[event] ||= []).push(handler); }
  });
  if (tag.toLowerCase() === 'select') {
    const body = html.slice(html.indexOf(`<${tag}${attrs}>`) + tag.length + attrs.length + 2);
    elements.get(id).value = /<option\b[^>]*value="([^"]*)"/.exec(body)?.[1] || '';
  }
}
const element = id => elements.get(id) || null;
async function click(id) {
  assert.equal(element(id).disabled, false, `${id} must be enabled`);
  for (const handler of element(id).handlers.click || []) await handler();
}
const settle = async () => { for (let i = 0; i < 4; i++) await new Promise(resolve => setImmediate(resolve)); };
class ClockDate extends Date { static now() { return time; } }
const context = vm.createContext({
  TextDecoder, TextEncoder, Blob, Date: ClockDate, performance: { now: () => time },
  location: { href: 'http://localhost:8767/' },
  navigator: { serial: { async requestPort() {
    let controller;
    const port = {
      readable: new ReadableStream({ start(value) { controller = value; } }),
      writable: new WritableStream({ write(bytes) { writes.push(new TextDecoder().decode(bytes)); } }),
      async open() {}, async close() {
        assert.equal(this.readable.locked, false);
        assert.equal(this.writable.locked, false);
      }
    };
    port.receive = text => controller.enqueue(new TextEncoder().encode(text));
    ports.push(port);
    return port;
  } } },
  document: { getElementById: element, createElement: () => ({ click() {} }) },
  window: { isSecureContext: true, devicePixelRatio: 1 },
  URL: { createObjectURL: () => 'test-blob', revokeObjectURL() {} },
  ResizeObserver: class { observe() {} }, requestAnimationFrame() {},
  setInterval(callback) { intervals.push(callback); }, setTimeout() {}
});
const telemetry = 'T,00000000,+000.2,+0000,+0000,+0012,+0000,-0012,+0000\r\n';
const capabilities = '@I,TRJ2,0198,0FF0,001E,0032\r\n@I,ARM1,0198,001E,0FF0\r\n@I,POS1\r\n@I,VEL3,0014,0005,0064,09C4\r\n';
const status = state =>
  `@T,0000,00,${state},0,1,0032,00000000,00000FA0,0000000C,00000000,00000000,00110000,0,0032,0000\r\n` +
  `@R,0000,00,${state},0,0000000C,00000000\r\n` +
  `@P,0000,00,${state},0032,0000992E,00000190,000586A0\r\n` +
  `@W,0000,00,${state},0,0000,0014,0000199A,0000051F,00000000,00008000,0000,00000000,00000000,00000000,00000000,0000,00000000\r\n`;

(async () => {
  // Compare every resource before executing: catches an old server root or mixed assets.
  if (process.argv[2]) {
    const base = new URL(process.argv[2]);
    for (const asset of ['', ...scripts, ...[...html.matchAll(/<link\b[^>]*href="([^"]+)"/g)].map(m => m[1])]) {
      const response = await fetch(new URL(asset, base));
      assert.equal(response.status, 200, `${asset || 'index.html'} HTTP status`);
      const file = asset ? new URL(asset, base).pathname.slice(1) : 'index.html';
      const local = fs.readFileSync(path.join(__dirname, file));
      assert.deepEqual(Buffer.from(await response.arrayBuffer()), local, `${file} must match current checkout`);
      assert.equal(response.headers.get('cache-control'), 'no-store', `${file} must not cache an old module`);
    }
  }
  for (const src of scripts) {
    const filename = src.split('?')[0];
    vm.runInContext(fs.readFileSync(path.join(__dirname, filename), 'utf8'), context, { filename });
  }
  assert.match(element('tr-preview-info').textContent, /规划预览/);
  element('tr-size').value='360';await click('tr-preset');
  assert.equal(element('tr-angle').value,'+360');assert.equal(element('tr-time').value,'22.5');
  element('tr-mode').value='2';await click('tr-preset');
  assert.equal(element('tr-amplitude').value,'360');assert.equal(element('tr-wave-period').value,'75.5');
  element('tr-mode').value='1';element('tr-size').value='60';await click('tr-preset');
  assert.equal(element('tr-time').value,'15');
  element('tr-time').value='30';await click('tr-slow');assert.equal(element('tr-time').value,'30','slowing must not shorten a longer user setting');
  element('tr-mode').value='3';element('tr-time').value='15';element('tr-points').value='+360,-360';await click('tr-slow');
  assert.equal(element('tr-time').value,'45','waypoint timing uses the largest adjacent displacement');
  element('tr-mode').value='1';await click('tr-preset');
  assert.equal(element('tr-state').textContent, '未连接');
  assert.equal(element('arm-state').textContent, '未连接');
  await click('connect');
  await settle();
  for (const command of ['@TI\n', '@TPI\n', '@TV3\n', '@I\n']) assert.ok(writes.includes(command), `handshake ${command}`);
  for (const id of ['tr-state', 'arm-state']) assert.equal(element(id).textContent, '等待板端状态');
  for (const id of ['tr-query', 'arm-query']) assert.equal(element(id).disabled, false);
  await click('start');
  ports.at(-1).receive(telemetry);
  await settle(); intervals[0](); await settle();
  assert.equal(element('count').textContent, '1');
  assert.equal(element('status').textContent, '正在接收角度');
  for (const id of ['tr-state', 'arm-state']) assert.equal(element(id).textContent, '等待板端状态', 'telemetry alone is not control confirmation');
  ports.at(-1).receive(capabilities.slice(0, 19));
  ports.at(-1).receive(capabilities.slice(19) + status(0));
  await settle();
  assert.match(element('tr-capability').textContent, /TRJ2/);
  assert.match(element('arm-capability').textContent, /ARM1/);
  assert.match(element('tr-state').textContent, /停机/);
  assert.match(element('arm-state').textContent, /控制状态 0/);
  for (const id of ['tr-run', 'arm-send']) assert.equal(element(id).disabled, true, 'stop state blocks motion');
  ports.at(-1).receive(status(4));
  await settle();
  for (const id of ['tr-state', 'arm-state']) assert.match(element(id).textContent, /直立平衡/);
  for (const id of ['tr-run', 'arm-send']) assert.equal(element(id).disabled, false, 'fresh matching firmware enables motion');
  ports.at(-1).receive('@I,TRJ1,0198,0FF0,001E,0032\r\n');await settle();
  assert.equal(element('tr-run').disabled,true,'old speed-only firmware must be upgraded');
  assert.match(element('tr-run-help').textContent,/TRJ2/);
  ports.at(-1).receive('@I,TRJ2,0198,0FF0,001E,0032\r\n'+status(4));await settle();
  assert.equal(element('tr-run').disabled,false);
  ports.at(-1).receive(status(4).replace('@W,0000,00,4,0,','@W,0000,00,4,1,'));await settle();
  assert.equal(element('tr-run').disabled,true,'velocity mode must not run position curves');
  ports.at(-1).receive(status(4));await settle();
  assert.equal(element('tr-run').disabled,false);
  time += 1600; intervals[0](); await settle();
  for (const id of ['tr-run', 'arm-send']) assert.equal(element(id).disabled, true, 'stale status blocks motion');
  await click('disconnect');
  for (const id of ['tr-state', 'arm-state']) assert.equal(element(id).textContent, '未连接');
  await click('connect');
  await settle();
  ports.at(-1).receive(telemetry);
  await settle(); intervals[0](); await settle();
  for (const id of ['tr-state', 'arm-state']) assert.equal(element(id).textContent, '等待板端状态');
  for (const id of ['tr-run', 'arm-send']) assert.equal(element(id).disabled, true, 'reconnect requires new capability/status');
  assert.ok(writes.every(s => s === 'P' || s === 'Q' || /^@(TI|TQ|TPI|TPQ|TV3|TVS|I|Q)\n$/.test(s)), 'connection test sends only telemetry and read queries');
  await click('disconnect');
  console.log('PASS: complete HTML script order, one serial connection for telemetry/trajectory/arm/PID, split replies, STOP/freshness interlocks, disconnect/reconnect' + (process.argv[2] ? ', served assets match checkout with no-store' : ''));
})().catch(error => { console.error(error); process.exitCode = 1; });
