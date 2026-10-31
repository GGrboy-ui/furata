'use strict';
const vm=require('node:vm'),fs=require('node:fs'),path=require('node:path'),assert=require('node:assert/strict');
const Telemetry=require('./telemetry-core.js'),ArmApp=require('./arm-app.js');
const elements=new Map(),writes=[];let input,closed=0;
function element(id){if(!elements.has(id))elements.set(id,{value:id==='baud'?'115200':id==='window'?'10':id==='signal'?'angle':'+60',disabled:false,hidden:false,textContent:'',innerHTML:'',style:{},handlers:{},classList:{toggle(){}},addEventListener(e,f){this.handlers[e]=f;},click(){},clientWidth:900,clientHeight:370,getContext(){return new Proxy({},{get:(t,k)=>t[k]||(()=>{}),set:(t,k,v)=>(t[k]=v,true)});}});return elements.get(id);}
const port={readable:new ReadableStream({start(c){input=c;}}),writable:new WritableStream({async write(bytes){await new Promise(r=>setImmediate(r));writes.push(new TextDecoder().decode(bytes));}}),async open(){},async close(){assert.equal(this.readable.locked,false);assert.equal(this.writable.locked,false);closed++;}};
const intervals=[];
const context=vm.createContext({Telemetry,ArmApp,TextDecoder,TextEncoder,Blob,performance,navigator:{serial:{async requestPort(){return port;}}},document:{getElementById:element,createElement:()=>({click(){}})},window:{isSecureContext:true,devicePixelRatio:1},URL:{createObjectURL(){return'test';},revokeObjectURL(){}},ResizeObserver:class{observe(){}},requestAnimationFrame(){},setInterval(f){intervals.push(f);},setTimeout(){}});
vm.runInContext(fs.readFileSync(path.join(__dirname,'app.js'),'utf8'),context);
const flush=()=>new Promise(r=>setImmediate(r));
(async()=>{
  await element('connect').handlers.click();assert.deepEqual(writes,['@I\n']);
  input.enqueue(new TextEncoder().encode('@I,ARM1,0198,001E,0FF0\r\n'));await flush();await flush();assert.equal(writes.at(-1),'@Q\n');
  input.enqueue(new TextEncoder().encode('@R,0000,00,4,0,00000000,00000000\r\n'));await flush();
  assert.equal(element('arm-send').disabled,false);
  await Promise.all([element('start').handlers.click(),element('arm-send').handlers.click()]);
  assert.deepEqual(writes.slice(-2),['P','@M,1,+600\n']);
  input.enqueue(new TextEncoder().encode('T,00000000,+000.0,+0000,+0000,+0000,+0000,+0000,+0000\r\n@R,0001,01,4,1,00000000,0044'));
  await flush();assert.equal(element('arm-send').disabled,true);
  input.enqueue(new TextEncoder().encode('0000\r\n'));await flush();intervals.at(-1)();
  assert.equal(element('count').textContent,'1');assert.match(element('arm-goal').textContent,/60.00/);
  await element('disconnect').handlers.click();assert.deepEqual(writes.slice(-2),['X','Q']);assert.equal(closed,1);assert.equal(element('arm-send').disabled,true);
  // A failed X write must still release both stream locks and close the port.
  port.readable=new ReadableStream({start(c){input=c;}});
  port.writable=new WritableStream({async write(bytes){const command=new TextDecoder().decode(bytes);writes.push(command);if(command==='X')throw new Error('simulated unplug during stop');}});
  await element('connect').handlers.click();
  input.enqueue(new TextEncoder().encode('@I,ARM1,0198,001E,0FF0\r\n'));await flush();await flush();
  input.enqueue(new TextEncoder().encode('@R,0001,01,4,1,00000000,00440000\r\n'));await flush();
  await element('disconnect').handlers.click();assert.equal(closed,2);assert.match(element('message').textContent,/X 未确认/);
  console.log('PASS: ARM1 via app WebSerial, mixed T/reply fragments, serialized writes, UI events, disconnect cleanup including failed X');
})().catch(e=>{console.error(e);process.exitCode=1;});
