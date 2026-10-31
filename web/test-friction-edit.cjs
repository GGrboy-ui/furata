 'use strict';
const assert=require('node:assert/strict');global.Trajectory=require('./trajectory-core');const {create}=require('./trajectory-app');
let time=100,connected=false;const writes=[],elements=new Map();
const defaults={'tr-mode':'1','tr-angle':'+15','tr-time':'4','tr-speed-t':'0','tr-outer':'1','tr-speed-ms':'20','tr-speed-kp':'0.1','tr-speed-ki':'0.02','tr-speed-kpos':'0.5'};
function el(id){if(!elements.has(id))elements.set(id,{value:defaults[id]||'',disabled:false,textContent:'',innerHTML:'',handlers:{},classList:{toggle(){}},addEventListener(k,f){this.handlers[k]=f;}});return elements.get(id);}
const app=create({getElement:el,isConnected:()=>connected,now:()=>time,send:async s=>writes.push(s),getRecentTelemetry:()=>[],getTaskTelemetry:()=>[],download(){}});
const tr=(state=0)=>`@T,0000,00,${state},0,1,0032,00000000,00000FA0,00000000,00000000,00000000,00110000,0,0032,0000\r\n`;
const vel=(state=0,id=0,code=0,t=0)=>`@V,${id.toString(16).padStart(4,'0')},${code.toString(16).padStart(2,'0')},${state},1,0014,0000199A,0000051F,00008000,00000000,00000000,00000000,00000000,0000,00000000,${t.toString(16).padStart(4,'0')}\r\n`.toUpperCase();
const flush=()=>new Promise(r=>setImmediate(r));
(async()=>{
 assert.equal(el('tr-speed-t').disabled,false,'disconnected input must accept a draft');assert.equal(el('tr-t-apply').disabled,true);
 el('tr-speed-t').value='80';el('tr-speed-t').handlers.input();await app.applyFriction();assert.equal(writes.length,0);
 connected=true;await app.connected();app.feed('@I,TRJ1,0198,0FF0,001E,0032\r\n'+tr());app.feed('@I,VEL1,0014,0005,0064\r\n');await flush();
 assert.equal(writes.filter(s=>s==='@TV2\n').length,1);
 // Drop the first VEL2 reply; a stopped idle poll should retry capability discovery.
 time+=1000;app.feed(tr());await app.poll();assert.equal(writes.filter(s=>s==='@TV2\n').length,2);
 time+=1000;app.feed(tr());await app.poll();assert.equal(writes.filter(s=>s==='@TV2\n').length,3);
 time+=1000;app.feed(tr());await app.poll();assert.equal(writes.filter(s=>s==='@TV2\n').length,3,'bounded automatic retries on old firmware');
 await el('tr-t-query').handlers.click();assert.equal(writes.filter(s=>s==='@TV2\n').length,4,'manual recovery remains available');
 app.feed('@I,VEL2,0014,0005,0064,09C4\r\n'+vel());await flush();assert.equal(el('tr-speed-t').value,'80','first status must not erase typed t');assert.equal(el('tr-t-apply').disabled,false);
 el('tr-speed-kp').value='9';el('tr-outer').value='0';await app.applyFriction();
 assert.equal(writes.at(-1),'@TVD,1,1,20,6554,1311,32768,80\n','t-only apply preserves board mode and PI despite different drafts');
 el('tr-speed-t').value='90';el('tr-speed-t').handlers.input();app.feed(vel(0,1,4,80));assert.match(el('tr-speed-actual').textContent,/t=80 PWM/);assert.equal(el('tr-speed-t').value,'90','confirmation must preserve a newer draft');
 app.feed(tr(4)+vel(4,1,4,80));const count=writes.length;await app.applyFriction();assert.equal(writes.length,count,'balance cannot apply t');assert.equal(el('tr-speed-t').disabled,false);assert.match(el('tr-friction-info').textContent,/停机/);
 app.disconnected();assert.equal(el('tr-speed-t').value,'90');await app.connected();assert.equal(el('tr-t-apply').disabled,true);
 app.feed('@I,TRJ1,0198,0FF0,001E,0032\r\n'+tr());app.feed('@I,VEL1,0014,0005,0064\r\n');app.feed(vel().replace(/,0000\r\n$/,'\r\n'));await flush();
 const before=writes.length;await app.applySpeed();assert.equal(writes.length,before,'unsupported t draft must not be silently dropped from group apply');assert.match(el('tr-message').textContent,/未下发任何参数/);
 console.log('PASS: editable t draft offline/running, safe t-only apply, preserve actual PI and newer drafts, lost capability retry, bounded/manual discovery, old firmware guard, reconnect');
})().catch(e=>{console.error(e);process.exitCode=1;});
