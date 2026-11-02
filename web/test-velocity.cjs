'use strict';
const assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path');
global.Trajectory=require('./trajectory-core');const {create,plot}=require('./trajectory-app');
let time=100,connected=true;const writes=[],elements=new Map();
const values={'tr-mode':'1','tr-angle':'+15','tr-time':'4','tr-wave-period':'12','tr-amplitude':'15','tr-cycles':'3','tr-points':'+15,0,-15,0','tr-dwell':'2','tr-position-ms':'50','tr-outer':'0','tr-speed-ms':'20','tr-speed-kp':'0.1','tr-speed-ki':'0.02','tr-speed-kpos':'0.5'};
function element(id){if(!elements.has(id))elements.set(id,{value:values[id]||'',hidden:false,disabled:false,textContent:'',innerHTML:'',handlers:{},classList:{toggle(){}},addEventListener(k,f){this.handlers[k]=f;}});return elements.get(id);}
const app=create({getElement:element,isConnected:()=>connected,now:()=>time,send:async s=>writes.push(s),getRecentTelemetry:()=>[],getTaskTelemetry:()=>[],download(){}});
const tr=(id,state=0,phase=0)=>`@T,${id.toString(16).padStart(4,'0')},00,${state},${phase},1,0032,00000000,00000FA0,00000000,00000000,00000000,00110000,0,0032,0002\r\n`.toUpperCase();
const vel=(id=0,state=0,code=0,outer=1)=>`@V,${id.toString(16).padStart(4,'0')},${code.toString(16).padStart(2,'0')},${state},${outer},0014,0000199A,0000051F,00008000,00010000,00018000,FFFF0000,FFFF8000,0002,00000064\r\n`.toUpperCase();
const flush=()=>new Promise(r=>setImmediate(r));
(async()=>{
 await app.connected();app.feed('@I,TRJ2,0198,0FF0,001E,0032\r\n');app.feed(tr(0));await flush();
 assert.equal(element('tr-speed-apply').disabled,true,'old firmware cannot set velocity mode');
 app.feed('@I,VEL1,0014,0005,0064\r\n');await flush();assert.equal(writes.at(-1),'@TVQ\n');
 app.feed(vel(0,0,0,0));assert.equal(element('tr-speed-apply').disabled,false);
 assert.equal(element('tr-speed-t').disabled,false,'t draft remains editable with VEL1');
 assert.equal(element('tr-t-apply').disabled,true,'VEL1 cannot apply t');
 assert.equal(element('tr-outer').value,'0','first board readback shows boot position mode');
 app.feed(tr(0,4));app.feed(vel(0,4,0,0));assert.equal(element('tr-run').disabled,false,'position mode starts TRJ2 trajectory');
 assert.match(element('tr-run-help').textContent,/位置 PID/);
 app.feed(tr(0));app.feed(vel(0,0,0,0));
 assert.match(element('tr-measured-speed').textContent,/-0.882/);
 assert.match(element('tr-target-speed').textContent,/位置环跟踪/);
 element('tr-speed-ms').value='4';await app.applySpeed();assert.match(element('tr-message').textContent,/5～100/);
 element('tr-speed-ms').value='20';element('tr-speed-kp').value='NaN';await app.applySpeed();assert.match(element('tr-message').textContent,/增益/);
 element('tr-speed-kp').value='0.1';await element('tr-enter-speed').handlers.click();assert.equal(writes.at(-1),'@TVC,1,1,20,6554,1311,32768\n');assert.equal(app.locked,true);
 app.feed(tr(1));assert.equal(app.locked,true,'TRJ reply cannot confirm velocity settings');
 app.feed(vel(1,0,4));assert.equal(app.locked,false);assert.match(element('tr-speed-actual').textContent,/0.10001/);
 app.feed(tr(1,4));app.feed(vel(1,4,4));assert.equal(element('tr-speed-apply').disabled,true,'balance-idle cannot switch');
 assert.equal(element('tr-run').disabled,true,'speed mode cannot start position trajectory');app.feed(vel(1,4,4,0));
 await app.run();assert.match(writes.at(-1),/^@T,3,/);app.feed(tr(3,4,2).replace(',0032,0002',',0032,0003'));
 const speedFrame=vel(1,4,4,0).replace(',0002,00000064',',0003,00000064');
 for(const chunk of [speedFrame.slice(0,13),speedFrame.slice(13)])app.feed(chunk);
 assert.match(element('tr-live-velocity').innerHTML,/#f5b868/);assert.match(element('tr-live-velocity').innerHTML,/#62dfc5/);assert.doesNotMatch(element('tr-live-velocity').innerHTML,/#b79bff/,'position mode does not plot inactive speed PID target');
 app.feed(tr(3,4,2).replace(',0032,0002',',0032,0003'));assert.match(element('tr-live-velocity').innerHTML,/#62dfc5/,'TRJ polling must not erase feedback chart');
 const csv=app.csv(),lines=csv.trim().split('\r\n');assert.match(csv,/speed_feedback_counts_per_s/);assert.match(csv,/"velocity"/);
 // Split CSV respecting the JSON-escaped quotes, then verify every row has the header width.
 const split=line=>{let quoted=false,count=1;for(let i=0;i<line.length;i++){if(line[i]===String.fromCharCode(34)){if(quoted&&line[i+1]===line[i])i++;else quoted=!quoted;}else if(line[i]===','&&!quoted)count++;}return Array(count);};
 const columns=split(lines[0]).length;for(const row of lines.slice(1))assert.equal(split(row).length,columns,'CSV column alignment');
 app.feed(speedFrame.replace('@V,0001,04,4,','@V,0001,04,0,'));const stoppedCsv=app.csv();
 app.feed(speedFrame.replace('0000199A','00030000'));assert.equal(app.csv(),stoppedCsv,'settings/readbacks after stop must not enter the old task CSV');
 time+=2600;await app.poll();assert.equal(writes.filter(s=>s.startsWith('@TVC')).length,1,'no automatic config retry');
 assert.equal(element('tr-speed-apply').disabled,true,'stale status locks controls');
 app.disconnected();connected=false;assert.equal(element('tr-speed-apply').disabled,true);
 connected=true;await app.connected();assert.equal(writes.at(-1),'@TI\n');assert.equal(element('tr-speed-apply').disabled,true,'reconnect requires new capability/readback');
 const log=path.join(__dirname,'../build/oss/tb_acg720_velocity/velocity_serial.log');
 if(fs.existsSync(log))for(const line of fs.readFileSync(log,'utf8').trim().split(/\r?\n/))if(line.startsWith('@V,')||line.startsWith('@I,VEL1,'))assert.ok(Trajectory.parse(line),`real RTL frame ${line}`);
 assert.equal(Trajectory.parse(vel().trim()+',0'),null);
 assert.equal(Trajectory.parse(vel().trim().replace('0014','0004')),null);
 // A different running task that disconnects without a stop frame must also
 // remain frozen when the board is rediscovered with the same active task ID.
 app.feed('@I,TRJ2,0198,0FF0,001E,0032\r\n@I,VEL1,0014,0005,0064\r\n');app.feed(tr(3,4,4));app.feed(vel(1,4,4,0));await app.run();assert.match(writes.at(-1),/^@T,4,/);
 app.feed(tr(4,4,2).replace(',0032,0002',',0032,0004'));const task4Speed=speedFrame.replace(',0003,00000064',',0004,00000064');app.feed(task4Speed);
 const disconnectedCsv=app.csv();app.disconnected();await app.connected();app.feed('@I,TRJ2,0198,0FF0,001E,0032\r\n@I,VEL1,0014,0005,0064\r\n');app.feed(task4Speed.replace('0000199A','00030000'));
 assert.equal(app.csv(),disconnectedCsv,'reconnect must not append new parameters to the old task CSV');
 console.log('PASS: VEL1 protocol, stopped config, quantized readback, old firmware, feedback chart, task CSV, stale locks, chunks, reconnect, real RTL log');
})().catch(e=>{console.error(e);process.exitCode=1;});
