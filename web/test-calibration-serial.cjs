'use strict';
const vm=require('node:vm'),fs=require('node:fs'),path=require('node:path'),assert=require('node:assert/strict');
const Telemetry=require('./telemetry-core.js'),Calibration=require('./calibration-core.js');
const elements=new Map(), writes=[];let controller,closeCount=0;
const defaults={baud:'115200',window:'10',signal:'angle','cal-cpr':'408','cal-travel':'15','cal-encoderSign':'1','cal-vm':'12','cal-ratedVm':'12','cal-motorAllowed':'.8','cal-encoderAxis':'arm','cal-directionNote':'CW','cal-location':'主位置','cal-instrument':'scope/motor-line probe','cal-direction':'1','cal-duty':'1','cal-step':'1','cal-profile':'1','cal-signal':'pwm','cal-motion':'unknown'};
function element(id){if(!elements.has(id))elements.set(id,{value:defaults[id]||'',checked:id==='cal-ready',disabled:false,hidden:false,textContent:'',innerHTML:'',style:{},handlers:{},classList:{toggle(){}},addEventListener(e,cb){this.handlers[e]=cb;},click(){},clientWidth:900,clientHeight:370,getContext(){return new Proxy({},{get:(t,k)=>t[k]||(()=>{}),set:(t,k,v)=>(t[k]=v,true)});}});return elements.get(id);}
const port={readable:new ReadableStream({start(c){controller=c;}}),writable:new WritableStream({async write(bytes){await new Promise(resolve=>setImmediate(resolve));writes.push(new TextDecoder().decode(bytes));}}),async open(){},async close(){assert.equal(this.readable.locked,false);assert.equal(this.writable.locked,false);closeCount++;}};
const intervals=[];
const context=vm.createContext({Telemetry,Calibration,TextDecoder,TextEncoder,Blob,performance,Uint32Array,navigator:{serial:{async requestPort(){return port;}}},document:{getElementById:element,createElement:()=>({click(){}})},window:{isSecureContext:true,devicePixelRatio:1},URL:{createObjectURL(){return'test';},revokeObjectURL(){}},ResizeObserver:class{observe(){}},requestAnimationFrame(){},setInterval(cb){intervals.push(cb);},setTimeout(){}});
for(const name of ['calibration-app.js','app.js'])vm.runInContext(fs.readFileSync(path.join(__dirname,name),'utf8'),context);
const wire=body=>`${body},${Calibration.crc8(body).toString(16).padStart(2,'0').toUpperCase()}\r\n`;
const flush=()=>new Promise(resolve=>setImmediate(resolve));
(async()=>{
  await element('connect').handlers.click();assert.deepEqual(writes,['!i\n']);
  assert.equal(element('cal-open').disabled,true);await element('start').handlers.click();assert.equal(writes.at(-1),'P');
  controller.enqueue(new TextEncoder().encode('T,00000000,+000.2,+0000,+0000\r\n'+wire('I,DZCAL1,12ABCDEF,09C4,0198,000A,0014,0078,0258,00C8,0096')));await flush();
  assert.equal(element('cal-open').disabled,false);intervals.at(-1)();assert.equal(element('count').textContent,'1');
  await element('cal-open').handlers.click();const sid=vm.runInContext('calibration.status.session.id',context);
  assert.deepEqual(writes.slice(-4),['X','Q','!i\n',Calibration.command('c',sid,408,150,1)]);
  controller.enqueue(new TextEncoder().encode(wire(`M,0000000A,${sid.toString(16).padStart(8,'0')},0000,0,0,0,00000000,+0000,+0000,03E7,3`)));await flush();
  await vm.runInContext('calibration.tick()',context);
  assert.equal(element('start').disabled,true);assert.equal(element('stop').disabled,true);assert.equal(element('cal-precheck').disabled,false);
  const before=writes.length;
  await Promise.all([vm.runInContext('calibration.tick()',context),vm.runInContext("writeCommand('!i\\n')",context)]);
  assert.deepEqual(writes.slice(before),[Calibration.command('h',sid),'!i\n']);
  await element('cal-precheck').handlers.click();const tid=vm.runInContext('calibration.status.pendingTrial.id',context);
  assert.equal(writes.at(-1),Calibration.command('b',sid,tid,25,0));
  const sidHex=sid.toString(16).padStart(8,'0'),tidHex=tid.toString(16).padStart(4,'0');
  // An unfinished cached frame cannot release the test latch or enable more PWM.
  controller.enqueue(new TextEncoder().encode(wire(`R,${sidHex},${tidHex},0,0000000A,FFFFFFFF,FFFFFFFF,FFFFFFFF,00000000,00000000,0000,0000,0000`)));await flush();
  assert.equal(vm.runInContext('calibration.status.pendingTrial.id',context),tid);
  await element('disconnect').handlers.click();assert.equal(closeCount,1);assert.deepEqual(writes.slice(-4),['X',Calibration.command('e',sid),'Q','Q']);assert.equal(element('cal-open').disabled,true);
  assert.equal(element('export').disabled,false);assert.equal(element('count').textContent,'1');
  console.log('PASS: shared WebSerial handshake, legacy T parsing, session I re-enable, ordinary P/Q lockout, heartbeat/write serialization, incomplete result rejection, X/e/Q disconnect and retained legacy CSV');
})().catch(error=>{console.error(error);process.exitCode=1;});
