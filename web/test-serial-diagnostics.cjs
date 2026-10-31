'use strict';
const assert=require('node:assert/strict'),fs=require('node:fs');const {create}=require('./serial-diagnostics');
let t=100;const d=create({now:()=>t,limit:3});d.connected({baudRate:115200});
const frame='@W,0000,00,0,0,0000,0014,0000199A,0000051F,00000000,00008000,0000,00000000,00000000,00010000,00000000,0000,00000000';
d.rx(frame.slice(0,70));assert.equal(d.snapshot().velocityFrames,0);d.rx(frame.slice(70)+'\r\nT,00000000,+000.0,+0000,+0000,+0012,+0000,+0000,+0000\r\n');
assert.equal(d.snapshot().lastVelocity.actualQ16,65536);assert.equal(d.snapshot().lastPosition.counts,12);d.tx('@TVS\n');const j=JSON.parse(d.json({pageUrl:'http://localhost:8767/'}));assert.equal(j.summary.lastVelocity.actualCountsPerSecond,1);assert.equal(j.entries.length,3);assert.equal(j.summary.truncated,true);assert.ok(j.entries.some(e=>e.raw===frame));
d.disconnected();d.connected();assert.equal(d.snapshot().lastVelocity,null);d.rx(frame.replace('00010000','FFFF0000')+'\n');assert.equal(d.snapshot().lastVelocity.actualCountsPerSecond,-1);
d.rx(frame.replace('00010000','00000000')+'\n');assert.equal(d.snapshot().lastVelocity.actualQ16,0);assert.equal(d.snapshot().lastVelocity.actualHex,'00000000');
const log=__dirname+'/../build/velocity_zero_diagnosis_20261031/board.log';if(fs.existsSync(log)){const live=create();live.rx(fs.readFileSync(log,'utf8'));assert.ok(live.snapshot().lastVelocity.actualCountsPerSecond>0,'real RTL physical frame must remain nonzero');}
console.log('PASS: passive diagnostic records, fragmented raw UART, exact Q16 field, zero/negative distinction, bounded export, reconnect isolation, real board frame');
