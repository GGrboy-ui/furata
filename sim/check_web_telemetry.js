// Validate simulated physical UART bytes using the actual local website decoder.
// Usage: node sim/check_web_telemetry.js [website URL] [serial log path]
'use strict';
const fs = require('node:fs');
const vm = require('node:vm');
const path = require('node:path');
const assert = require('node:assert/strict');
async function main() {
  const base = process.argv[2] || 'http://localhost:8765/';
  const log = process.argv[3] || path.join(__dirname, '../build/oss/tb_uart_telemetry/telemetry_serial.log');
  const response = await fetch(new URL('telemetry-core.js', base));
  if (!response.ok) throw new Error(`Website decoder HTTP ${response.status}`);
  const context = { module: { exports: {} } };
  vm.runInNewContext(await response.text(), context, { timeout: 1000 });
  const { LineDecoder, Recording, importText } = context.module.exports;
  const serial = fs.readFileSync(log, 'utf8');
  for (const width of [1, 2, 7, 19, serial.length]) {
    const frames = [];
    const decoder = new LineDecoder(frame => frames.push(frame));
    for (let offset = 0; offset < serial.length; offset += width)
      decoder.feed(serial.slice(offset, offset + width));
    assert.equal(decoder.invalid, 0);
    assert.equal(frames.length, 9);
    assert.equal(frames[0].angle, -12.3);
    assert.equal(frames[0].requestedPwm, -2500);
    assert.equal(frames[0].actualPwm, -17);
    assert.equal(frames[1].angle, 999.9);
    assert.equal(frames[1].requestedPwm, 2500);
    assert.equal(frames[1].actualPwm, 0);
    assert.equal(frames[5].sequence, 0xfffffffe);
    assert.equal(frames[6].sequence, 0xffffffff);
    assert.equal(frames[7].sequence, 0);
    assert.equal(frames[8].sequence, 3);
    const recording = new Recording();
    frames.forEach(frame => recording.add(frame));
    const imported = importText(recording.csv());
    assert.equal(imported.length, 9);
    assert.equal(imported[0].actualPwm, -17);
  }
  console.log('PASS: website decoded 9 physical UART frames at 5 chunk sizes; PWM and CSV roundtrip verified.');
}
main().catch(error => { console.error(error); process.exitCode = 1; });
