'use strict';
const vm = require('node:vm');
const fs = require('node:fs');
const path = require('node:path');
const assert = require('node:assert/strict');
const Calibration = require('./calibration-core.js');
let time=100000, connected=true, writes=[], boardMs=0, saved=[];
const defaults={ 'cal-cpr':'408','cal-travel':'15','cal-encoderSign':'1','cal-vm':'12','cal-ratedVm':'12','cal-motorAllowed':'0.8','cal-encoderAxis':'arm','cal-directionNote':'俯视顺时针','cal-location':'主位置','cal-instrument':'电机单线电流探头/示波器','cal-environment':'摆杆下垂','cal-direction':'1','cal-duty':'1','cal-step':'1','cal-profile':'1','cal-signal':'pwm','cal-motion':'unknown' };
const elements=new Map();
function element(id){if(!elements.has(id))elements.set(id,{value:defaults[id]||'',checked:id==='cal-ready',disabled:false,innerHTML:'',textContent:'',style:{},handlers:{},classList:{toggle(){}},files:[],clientWidth:900,addEventListener(event,callback){this.handlers[event]=callback;},getContext(){return new Proxy({},{get:(t,k)=>t[k]||(()=>{}),set:(t,k,v)=>(t[k]=v,true)});}});return elements.get(id);}
const context=vm.createContext({Calibration,Date,TextEncoder,Blob,Uint32Array,window:{devicePixelRatio:1},document:{createElement(){return{click(){saved.push(this.download);}};}},URL:{createObjectURL(){return'test';},revokeObjectURL(){}},setTimeout(){},setInterval(){}});
vm.runInContext(fs.readFileSync(path.join(__dirname,'calibration-app.js'),'utf8'),context);
const app=context.CalibrationApp.create({getElement:element,send:async command=>writes.push(command),isConnected:()=>connected,now:()=>time,setInterval(){}});
const cap=Calibration.parseLine((body=>body+','+Calibration.crc8(body).toString(16).padStart(2,'0'))('I,DZCAL1,12ABCDEF,09C4,0198,000A,0014,0078,0258,00C8,0096'));
function sample(extra={}) {boardMs+=10;app.onFrame({type:'M',ms:boardMs,session:app.status.session?.id||app.model.trials.at(-1)?.session||0,trial:app.status.pendingTrial?.id||0,phase:0,result:0,fault:0,position:0,requested:0,actual:0,sample:999,flags:3,sampleValid:true,sessionActive:true,active:false,...extra});}
function advance(ms) {for(let i=0;i<ms/10;i++){time+=10;sample();}app.update();}
function result(code,extra={}) {const t=app.status.pendingTrial;time+=10;sample({trial:t.id});app.onFrame({type:'R',session:t.session,trial:t.id,result:code,tCommand:boardMs-5,tPwm:boardMs,tEdge:code===1||code===2?boardMs+10:null,tEnd:boardMs+20,startPosition:0,endPosition:code===1||code===2?2:0,windows:[1,1,1],...extra});return t;}
async function precheck(percent){element('cal-duty').value=String(percent);advance(1000);await element('cal-precheck').handlers.click();assert.equal(app.status.pendingTrial.profile,0);result(13);element('cal-current').value='.6';element('cal-vmMin').value='11.8';element('cal-reviewSave').handlers.click();advance(1000);}
async function startSuccess(){await element('cal-pulse').handlers.click();assert.equal(app.status.pendingTrial.profile,1);const t=result(1);element('cal-motion').value='yes';element('cal-reviewSave').handlers.click();advance(1000);return t;}
(async()=>{
  await app.connected();assert.deepEqual(writes,['!i\n']);assert.equal(element('cal-open').disabled,true);assert.equal(element('cal-precheck').disabled,true);
  // Command echoes cannot authorize motion.
  app.feed('!i\n!c,1,408,150,1,00\n');assert.equal(element('cal-open').disabled,true);
  app.onFrame(cap);assert.equal(element('cal-open').disabled,false);
  await element('cal-open').handlers.click();const sid=app.status.session.id;
  assert.deepEqual(writes.slice(1,4),['X','Q','!i\n']);assert.equal(writes.at(-1),Calibration.command('c',sid,408,150,1));
  assert.equal(element('cal-precheck').disabled,true);assert.equal(element('cal-cpr').disabled,true);
  sample();advance(1000);assert.equal(app.status.session.acknowledged,true);assert.equal(element('cal-precheck').disabled,false);assert.equal(element('cal-pulse').disabled,true);
  await precheck(1);assert.equal(app.model.prechecked(sid,25),true);assert.equal(element('cal-pulse').disabled,false);
  const initialWrites=writes.length;await app.tick();assert.equal(writes.length,initialWrites+1);assert.equal(writes.at(-1),Calibration.command('h',sid));
  await startSuccess();assert.equal(app.model.groups()[0].success,1);assert.equal(app.model.threshold('主位置',1,1),null);
  for(let i=0;i<4;i++)await startSuccess();assert.equal(app.model.threshold('主位置',1,1).counts,25);
  const oldLength=writes.length;element('cal-next').handlers.click();assert.equal(element('cal-duty').value,'2.0');assert.equal(writes.length,oldLength);assert.equal(element('cal-pulse').disabled,true);
  await precheck(2);element('cal-profile').value='2';element('cal-duty').value='0';app.update();
  assert.equal(app.canPulse(0),false);assert.equal(app.canPulse(1),false);assert.equal(app.canPulse(2),true);
  await element('cal-pulse').handlers.click();const run=app.status.pendingTrial;assert.equal(run.kick,50);assert.equal(run.counts,0);assert.equal(writes.at(-1),Calibration.command('r',sid,run.id,50,0));
  result(4);assert.match(element('cal-motionTitle').textContent,/维持/);element('cal-motion').value='no';element('cal-reviewSave').handlers.click();assert.equal(app.model.classify(run),'failure');
  advance(1000);element('cal-direction').value='-1';element('cal-duty').value='1';element('cal-profile').value='1';app.update();assert.equal(element('cal-pulse').disabled,true);
  await precheck(1);await element('cal-pulse').handlers.click();const interrupted=app.status.pendingTrial;
  // Lost monitoring marks a trial invalid and sends STOP, not another test.
  time+=300;await app.tick();assert.equal(app.status.session,null);assert.match(interrupted.invalidReason,/中断/);assert.deepEqual(writes.slice(-3),['X',Calibration.command('e',sid),'Q']);
  app.onFrame({type:'R',session:sid,trial:interrupted.id,result:1,tCommand:1,tPwm:2,tEdge:3,tEnd:4,startPosition:0,endPosition:-2,windows:[1,1,1]});assert.equal(app.model.classify(interrupted),'invalid');
  await element('cal-queryResult').handlers.click();assert.equal(writes.at(-1),Calibration.command('g',sid,interrupted.id));
  element('cal-raw').handlers.click();element('cal-summary').handlers.click();element('cal-report').handlers.click();assert.deepEqual(saved,['furuta-calibration-raw.csv','furuta-calibration-summary.csv','furuta-calibration-report.html']);
  // A new session always has a new origin and ID, with no inherited precheck.
  await element('cal-open').handlers.click();const nextSid=app.status.session.id;assert.notEqual(nextSid,sid);sample();advance(1000);assert.equal(app.model.prechecked(nextSid,-25),false);
  await element('cal-precheck').handlers.click();result(13);element('cal-current').value='.81';element('cal-vmMin').value='12';element('cal-reviewSave').handlers.click();await new Promise(resolve=>setImmediate(resolve));assert.equal(app.status.session,null);assert.equal(element('cal-pulse').disabled,true);
  connected=false;app.disconnected();assert.equal(element('cal-open').disabled,true);assert.equal(element('cal-emergency').disabled,true);
  console.log('PASS: capability-only authorization, fresh session/origin, heartbeat, signed per-PWM electrical gate, manual one-shot scan, 5-repeat threshold, zero-hold kick, physical confirmation, data-loss stop, cache query, export and abnormal-current stop');
})().catch(error=>{console.error(error);process.exitCode=1;});
