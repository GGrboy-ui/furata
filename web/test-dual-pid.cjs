 'use strict';
const assert=require('node:assert/strict'),fs=require('node:fs');global.Trajectory=require('./trajectory-core');const {create}=require('./dual-pid-app');
let time=100,connected=true,motion=false;const elements=new Map(),writes=[];
function el(id){if(!elements.has(id))elements.set(id,{value:'0',disabled:false,textContent:'',handlers:{},classList:{toggle(){}},addEventListener(k,f){this.handlers[k]=f;}});return elements.get(id);}
const app=create({getElement:el,send:async s=>writes.push(s),now:()=>time,isConnected:()=>connected,isMotionLocked:()=>motion});
const h=(n,w)=>(n>>>0).toString(16).toUpperCase().padStart(w,'0');
const pos=(id=0,code=0,state=0,kp=39214)=>`@P,${h(id,4)},${h(code,2)},${state},0032,${h(kp,8)},00000190,000586A0\r\n`;
const vel=(id=0,code=0,state=0,outer=0,remain=0)=>`@W,${h(id,4)},${h(code,2)},${state},${outer},${h(remain,4)},0014,0000199A,0000051F,00000000,00008000,0000,00000000,00000000,00000000,00000000,0000,00000000\r\n`;
(async()=>{
 await app.connected();assert.deepEqual(writes.slice(0,2),['@TPI\n','@TV3\n']);assert.equal(el('pos-apply').disabled,true);
 app.feed('@I,POS1\r\n@I,VEL3,0014,0005,0064,09C4\r\n'+pos()+vel());
 const before=app.snapshot.speed;el('pos-kp').value='2';await app.applyPosition();assert.equal(writes.at(-1),'@TPC,1,50,131072,400,362144\n');assert.deepEqual(app.snapshot.speed,before);
 app.feed(vel(1,4));assert.equal(app.locked,true,'other bank same id cannot confirm');app.feed(pos(1,4,0,131072));assert.equal(app.locked,false);assert.equal(app.snapshot.position.kp,2);
 el('tr-speed-kd').value='0.1';await app.applySpeed();assert.equal(writes.at(-1),'@TVE,1,20,6554,1311,6554,32768,0\n');
 app.feed(pos(1,4,0,131072));assert.equal(app.locked,true);app.feed(vel(1,4));assert.equal(app.locked,false);assert.equal(app.snapshot.position.kp,2);
 el('tr-speed-kp').value='9';el('tr-speed-kd').value='9';el('tr-speed-t').value='80';await app.applyFriction();assert.equal(writes.at(-1),'@TVE,2,20,6554,1311,0,32768,80\n','t only uses actual speed PID');app.feed(vel(2,4));
 app.feed(pos(2,4,4,131072)+vel(2,4,4,1,200));assert.equal(app.canRun,false);assert.equal(el('pos-apply').disabled,true);assert.equal(el('tr-speed-apply').disabled,true);assert.equal(el('tr-speed-t').disabled,false);assert.match(el('pid-mode').textContent,/交接中/);
 app.feed(vel(2,4,4,1,0));assert.equal(app.canRun,true);const count=writes.length;await app.applySpeed();assert.equal(writes.length,count);
 time+=2000;app.update();assert.equal(app.canRun,false,'stale control state locks execution');app.disconnected();assert.equal(el('pos-apply').disabled,true);assert.equal(el('pos-kp').disabled,false);
 app.feed('@I,VEL1,0014,0005,0064\r\n');assert.equal(el('tr-speed-apply').disabled,true,'no VEL3 fallback writes');
 for(const bad of [pos().replace('0032','0000'),vel().replace('0014','0004'),vel().replace('00000000,00008000','00100001,00008000')])assert.equal(Trajectory.parse(bad.trim()),null);
 const log=__dirname+'/../build/oss/tb_acg720_velocity/velocity_serial.log';if(fs.existsSync(log))for(const l of fs.readFileSync(log,'utf8').split(/\r?\n/))if(/^@(P|W),/.test(l)||l.startsWith('@I,POS1')||l.startsWith('@I,VEL3,'))assert.ok(Trajectory.parse(l),'real RTL frame '+l);
 console.log('PASS: independent position/speed banks and request IDs, only-t preserves actual PID, stopped interlocks, handover, fresh mode, reconnect, typed frame validation');
})().catch(e=>{console.error(e);process.exitCode=1;});
