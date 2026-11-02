'use strict';
const assert=require('node:assert/strict');global.Trajectory=require('./trajectory-core');const {create}=require('./trajectory-app');
let time=100,connected=true,legacy=false;const writes=[],elements=new Map();
const defaults={'tr-mode':'1','tr-angle':'+15','tr-time':'4','tr-wave-period':'12','tr-amplitude':'15','tr-cycles':'3','tr-points':'+15,0,-15,0','tr-dwell':'2','tr-position-ms':'50'};
function element(id){if(!elements.has(id))elements.set(id,{value:defaults[id]||'',hidden:false,disabled:false,textContent:'',innerHTML:'',handlers:{},classList:{toggle(){}},addEventListener(k,f){this.handlers[k]=f;}});return elements.get(id);}
const app=create({getElement:element,isConnected:()=>connected,legacyLocked:()=>legacy,now:()=>time,send:async s=>writes.push(s),getRecentTelemetry:()=>[],getTaskTelemetry:()=>[],download(){}});
const status=(id,code,state=4,phase=0,period=50,active=0)=>`@T,${id.toString(16).padStart(4,'0')},${code.toString(16).padStart(2,'0')},${state},${phase},1,${period.toString(16).padStart(4,'0')},00000000,00000FA0,00000000,00000000,00000000,00110000,0,${period.toString(16).padStart(4,'0')},${active.toString(16).padStart(4,'0')}\r\n`.toUpperCase();
const flush=()=>new Promise(r=>setImmediate(r));
(async()=>{
 assert.equal(element('tr-run').disabled,true);await app.connected();assert.equal(writes.at(-1),'@TI\n');
 app.feed('@I,TRJ2,0198,0FF0,001E,0032\r\n');await flush();app.feed(status(0,0,0));
 assert.equal(element('tr-run').disabled,true);assert.equal(element('tr-period-apply').disabled,false);
 element('tr-position-ms').value='0';await app.applyPeriod();assert.match(element('tr-message').textContent,/1～1000/);
 element('tr-position-ms').value='20';await app.applyPeriod();assert.equal(writes.at(-1),'@TC,1,20\n');assert.equal(app.locked,true);
 app.feed(status(1,4,0,0,20));assert.equal(app.locked,false);assert.match(element('tr-period-actual').textContent,/20 ms/);
 app.feed(status(1,4,4,0,20));await app.run();assert.equal(writes.at(-1),'@T,2,1,4000,0,1,1,+150\n');
 app.feed(status(2,1,4,2,20,2));assert.equal(element('tr-period-apply').disabled,true);assert.equal(element('tr-run').disabled,true);
 await app.applyPeriod();assert.equal(writes.filter(s=>s.startsWith('@TC')).length,1);
 time+=2600;await app.poll();assert.equal(writes.filter(s=>s.startsWith('@T,')).length,1,'no automatic retry');
 app.feed(status(2,2,4,4,20,2));assert.equal(app.locked,false);assert.match(app.csv(),/position_period_ms/);assert.match(app.csv(),/"20"/);
 legacy=true;app.update();assert.equal(element('tr-run').disabled,true);assert.equal(element('tr-period-apply').disabled,true);legacy=false;app.update();
 for(const mode of ['2','3','4']){element('tr-mode').value=mode;element('tr-mode').handlers.input();assert.match(element('tr-preview-info').textContent,/规划预览/);assert.ok(element('tr-preview-position').innerHTML.includes('<svg'));}
 await app.run();assert.equal(writes.at(-1),'@T,3,4,4000,0,1,1,+150\n');
 time+=2600;await app.poll();assert.equal(app.locked,true);assert.equal(writes.filter(s=>s.startsWith('@T,')).length,2);
 await app.beforeDisconnect();assert.equal(writes.at(-1),'X');
 await app.emergency();app.feed(status(3,3,0,5,20,3));assert.equal(app.locked,false);
 await app.applyPeriod(true);assert.equal(writes.at(-1),'@TC,4,50\n');app.feed(status(4,4,0,5,50,3));
 app.disconnected();connected=false;assert.equal(element('tr-run').disabled,true);
 connected=true;await app.connected();assert.equal(writes.at(-1),'@TI\n');assert.equal(element('tr-period-apply').disabled,true,'no capability means no runtime setting');
 console.log('PASS: preview, capability, STOP/balance period setting, board readback, exclusions, four modes, no retry, task export, defaults, disconnect');
})().catch(e=>{console.error(e);process.exitCode=1;});
