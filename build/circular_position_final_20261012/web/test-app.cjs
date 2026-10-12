'use strict';
const vm = require('node:vm');
const fs = require('node:fs');
const path = require('node:path');
const assert = require('node:assert/strict');
const Telemetry = require('./telemetry-core.js');
const elements = new Map();
function element(id) {
  if (!elements.has(id)) elements.set(id, {
    value: id === 'baud' ? '115200' : id === 'window' ? '10' : '',
    disabled: false, hidden: false, textContent: '', innerHTML: '', style: {}, handlers: {},
    classList: { toggle() {} }, addEventListener(event, callback) { this.handlers[event] = callback; },
    click() {}, clientWidth: 900, clientHeight: 370,
    getContext() { return new Proxy({}, { get: (target, key) => target[key] || (() => {}), set: (target, key, value) => (target[key] = value, true) }); }
  });
  return elements.get(id);
}
let controller, writes = [], openOptions, closeCount = 0;
const port = {
  readable: new ReadableStream({ start(c) { controller = c; } }),
  writable: new WritableStream({ write(bytes) { writes.push(new TextDecoder().decode(bytes)); } }),
  async open(options) { openOptions = options; },
  async close() { assert.equal(this.readable.locked, false); assert.equal(this.writable.locked, false); closeCount++; }
};
let intervals = [];
const context = vm.createContext({
  Telemetry, TextDecoder, TextEncoder, Blob, performance,
  navigator: { serial: { async requestPort() { return port; } } },
  document: { getElementById: element, createElement: () => ({ click() {} }) },
  window: { isSecureContext: true, devicePixelRatio: 1 },
  URL: { createObjectURL() { return 'test-blob'; }, revokeObjectURL() {} },
  ResizeObserver: class { observe() {} }, requestAnimationFrame() {},
  setInterval(callback) { intervals.push(callback); }, setTimeout() {}
});
vm.runInContext(fs.readFileSync(path.join(__dirname, 'app.js'), 'utf8'), context);
const flush = () => new Promise(resolve => setImmediate(resolve));
(async () => {
  assert.equal(element('start').disabled, true);
  await element('connect').handlers.click();
  assert.equal(openOptions.baudRate, 115200); assert.equal(element('start').disabled, false);
  await element('start').handlers.click(); assert.deepEqual(writes, ['P']);
  controller.enqueue(new TextEncoder().encode('T,00000000,+012'));
  await flush(); intervals[0](); assert.equal(element('count').textContent, '0');
  controller.enqueue(new TextEncoder().encode('.3,-1250,+1000\r\nT,00000002,-005.6,+2500,-2500\r\n'));
  await flush(); intervals[0]();
  assert.equal(element('count').textContent, '2'); assert.equal(element('missing').textContent, '1');
  assert.match(element('current').innerHTML, /-5\.6/);
  assert.equal(element('requestedPwm').textContent, '100.00%');
  assert.equal(element('actualPwm').textContent, '-100.00%');
  element('signal').value = 'pwm';
  element('signal').handlers.change();
  vm.runInContext('draw()', context);
  assert.equal(element('chartTitle').textContent, '要求与实际 PWM');
  assert.match(element('chartLegend').innerHTML, /要求 PWM.*实际 PWM/);
  element('freeze').handlers.click(); assert.equal(element('freeze').textContent, '继续绘图');
  element('clear').handlers.click(); assert.equal(element('count').textContent, '0');
  await element('stop').handlers.click(); assert.deepEqual(writes, ['P', 'Q']);
  await element('disconnect').handlers.click();
  assert.deepEqual(writes, ['P', 'Q', 'Q']); assert.equal(closeCount, 1);
  assert.equal(element('start').disabled, true);
  element('file').files = [{ name: 'test.csv', size: 100, async text() {
    return 'time_ms,sequence,angle_deviation_deg,session\n0,0,1.2,0\n5,1,-1.2,0';
  } }];
  await element('file').handlers.change();
  assert.equal(element('count').textContent, '2'); assert.match(element('current').innerHTML, /-1\.2/);
  assert.equal(element('export').disabled, false);
  assert.equal(element('requestedPwm').textContent, '—');
  assert.equal(element('actualPwm').textContent, '—');
  vm.runInContext('draw()', context);
  assert.match(element('range').textContent, /没有 PWM/);
  element('file').files = [{ name: 'pwm.csv', size: 140, async text() {
    return 'time_ms,sequence,angle_deviation_deg,session,pwm_requested_counts,pwm_actual_counts\n0,0,1.2,0,-1250,1000\n5,1,-1.2,0,0,0';
  } }];
  await element('file').handlers.change();
  assert.equal(element('requestedPwm').textContent, '0.00%');
  assert.equal(element('actualPwm').textContent, '0.00%');
  controller = null;
  const packet = 'T,00000000,+000.2,+0000,+0000,+0012,+0000,-0012,-0125\r\n';
  vm.runInContext(`recording.clear(); decoder.feed(${JSON.stringify(packet)}); refreshMetrics();`, context);
  assert.equal(element('armPosition').textContent, '12 counts');
  assert.equal(element('positionTarget').textContent, '0 counts');
  assert.equal(element('positionError').textContent, '-12 counts');
  assert.equal(element('targetAngleOffset').textContent, '-1.016°');
  element('signal').value = 'position';vm.runInContext('draw()', context);
  assert.match(element('chartTitle').textContent, /最短误差/);
  assert.match(element('range').textContent, /counts/);
  element('signal').value = 'offset';vm.runInContext('draw()', context);
  assert.match(element('chartTitle').textContent, /目标倾角偏移/);
  console.log('PASS: mocked serial PWM reception, chart selector, old/new CSV import, missing vs zero, P/Q and lock cleanup');
})().catch(error => { console.error(error); process.exitCode = 1; });
