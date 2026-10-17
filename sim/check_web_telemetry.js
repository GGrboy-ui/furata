// Validate simulated physical UART bytes using the actual local website decoder.
// Usage: node sim/check_web_telemetry.js [website URL | --local] [serial log path]
'use strict';
const fs = require('node:fs');
const vm = require('node:vm');
const path = require('node:path');
const assert = require('node:assert/strict');
async function main() {
  const base = process.argv[2] || 'http://localhost:8765/';
  const log = process.argv[3] || path.join(__dirname, '../build/oss/tb_uart_telemetry/telemetry_serial.log');
  let decoderSource;
  if (base === '--local') {
    decoderSource = fs.readFileSync(path.join(__dirname, '../web/telemetry-core.js'), 'utf8');
  } else {
    const response = await fetch(new URL('telemetry-core.js', base));
    if (!response.ok) throw new Error(`Website decoder HTTP ${response.status}`);
    decoderSource = await response.text();
  }
  const context = { module: { exports: {} } };
  vm.runInNewContext(decoderSource, context, { timeout: 1000 });
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
  const extendedLog = path.join(__dirname, '../build/oss/tb_uart_telemetry_position/telemetry_position_serial.log');
  if (fs.existsSync(extendedLog)) {
    const extendedSerial = fs.readFileSync(extendedLog, 'utf8');
    for (const width of [1, 2, 7, 19, extendedSerial.length]) {
      const extendedFrames = [];
      const decoder = new LineDecoder(frame => extendedFrames.push(frame));
      for (let offset = 0; offset < extendedSerial.length; offset += width) decoder.feed(extendedSerial.slice(offset, offset + width));
      assert.equal(decoder.invalid, 0);assert.equal(extendedFrames.length, 3);
      assert.deepEqual(extendedFrames.map(f => [f.sequence, f.armPosition, f.positionTarget, f.positionError, f.targetAngleOffsetAdc]),
        [[0,408,0,-408,-12.5],[1,-816,5,821,100],[2,-816,5,821,100]]);
      const recording = new Recording();extendedFrames.forEach(f => recording.add(f));
      const recovered = importText(recording.csv());
      assert.equal(recovered[0].targetAngleOffsetAdc, -12.5);
      assert.equal(recovered[2].positionError, 821);
    }
    console.log('PASS: website decoded 55-byte physical UART at 5 chunk sizes; position/offset CSV roundtrip verified.');
  }
}
main().catch(error => { console.error(error); process.exitCode = 1; });
