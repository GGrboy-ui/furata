'use strict';
const vm=require('node:vm'),fs=require('node:fs'),path=require('node:path'),assert=require('node:assert/strict');
const Telemetry=require('./telemetry-core'),Trajectory=require('./trajectory-core');
global.Trajectory=Trajectory;const TrajectoryApp=require('./trajectory-app'),ArmApp=require('./arm-app');
const values={baud:'115200',window:'10',signal:'angle','arm-angle':'+60','tr-mode':'1','tr-angle':'+15','tr-time':'4','tr-wave-period':'12','tr-amplitude':'15','tr-cycles':'3','tr-points':'+15,0,-15,0','tr-dwell':'2','tr-position-ms':'20'};
const elements=new Map(),writes=[],intervals=[];let input,closed=0;
function element(id){if(!elements.has(id))elements.set(id,{value:values[id]||'',disabled:false,hidden:false,textContent:'',innerHTML:'',style:{},handlers:{},classList:{toggle(){}},addEventListener(e,f){this.handlers[e]=f;},click(){},clientWidth:900,clientHeight:370,getContext(){return new Proxy({},{get:(t,k)=>t[k]||(()=>{}),set:(t,k,v)=>(t[k]=v,true)});}});return elements.get(id);}
const port={readable:new ReadableStream({start(c){input=c;}}),writable:new WritableStream({async write(bytes){await new Promise(r=>setImmediate(r));writes.push(new TextDecoder().decode(bytes));}}),async open(){},async close(){assert.equal(this.readable.locked,false);assert.equal(this.writable.locked,false);closed++;}};
const context=vm.createContext({Telemetry,Trajectory,TrajectoryApp,ArmApp,TextDecoder,TextEncoder,Blob,performance,
 navigator:{serial:{async requestPort(){return port;}}},document:{getElementById:element,createElement:()=>({click(){}})},
 window:{isSecureContext:true,devicePixelRatio:1},URL:{createObjectURL(){return'test';},revokeObjectURL(){}},
 ResizeObserver:class{observe(){}},requestAnimationFrame(){},setInterval(f){intervals.push(f);},setTimeout(){}});
vm.runInContext(fs.readFileSync(path.join(__dirname,'app.js'),'utf8'),context);
const flush=()=>new Promise(r=>setImmediate(r));
async function receive(text){for(let i=0;i<text.length;i+=7)input.enqueue(new TextEncoder().encode(text.slice(i,i+7)));await flush();await flush();await flush();}
const report=(id,code,phase,period,active)=>`@T,${id.toString(16).padStart(4,'0')},${code.toString(16).padStart(2,'0')},4,${phase},3,${period.toString(16).padStart(4,'0')},00000064,00005DC0,00000001,00018000,00010000,00000000,0,0014,${active.toString(16).padStart(4,'0')}\r\n`.toUpperCase();
(async()=>{
 await element('connect').handlers.click();assert.deepEqual(writes,['@TI\n','@I\n']);
 await receive('@I,TRJ1,0198,0FF0,001E,0032\r\n@I,ARM1,0198,001E,0FF0\r\n');
 await receive(report(0,0,0,50,0)+'@R,0000,00,4,0,00000000,00000000\r\nT,00000000,+000.0,+0000,+0000,+0000,+0000,+0000,+0000\r\n');
 assert.equal(element('tr-run').disabled,false);assert.equal(element('arm-send').disabled,false);
 await element('tr-period-apply').handlers.click();assert.equal(writes.at(-1),'@TC,1,20\n');assert.equal(element('arm-send').disabled,true);
 await receive(report(1,4,0,20,0));assert.equal(element('arm-send').disabled,false);assert.match(element('tr-period-actual').textContent,/20 ms/);
 element('tr-mode').value='3';element('tr-mode').handlers.input();await element('tr-run').handlers.click();
 assert.equal(writes.at(-1),'@T,2,3,4000,2000,1,4,+150,+0,-150,+0\n');
 await receive(report(2,1,2,20,2)+'T,00000002,+000.1,+0010,+0008,+0001,+0001,+0000,+0000\r\n');
 assert.equal(element('arm-send').disabled,true);assert.equal(element('tr-period-apply').disabled,true);
 assert.equal(vm.runInContext('decoder.invalid',context),0);assert.equal(element('count').textContent,'0'); // Metrics refresh is on the UI interval.
 intervals[0]();assert.equal(element('count').textContent,'2');assert.equal(element('missing').textContent,'1');
 assert.match(vm.runInContext('trajectory.csv()',context),/"20"/);assert.match(vm.runInContext('trajectory.csv()',context),/"telemetry"/);
 await element('disconnect').handlers.click();assert.deepEqual(writes.slice(-2),['X','Q']);assert.equal(closed,1);
 assert.equal(element('tr-run').disabled,true);assert.equal(element('tr-period-apply').disabled,true);
 console.log('PASS: TRJ1/ARM1/T through WebSerial in 7-byte chunks, setting/run/legacy interlocks, gaps, task CSV and disconnect cleanup');
})().catch(e=>{console.error(e);process.exitCode=1;});
