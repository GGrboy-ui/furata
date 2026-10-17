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
  element('cal-cpr').value='800';element('cal-cpr').handlers.input();app.onFrame(cap);
  assert.equal(element('cal-cpr').value,'800','capability rereads must preserve measured CPR');
  element('cal-cpr').value='408';
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
  // Rejected/lost commands can leave M reporting a previous trial. They must
  // time out as invalid and stop, without fabricating a final board result.
  await element('cal-open').handlers.click();sample();advance(1000);
  await element('cal-precheck').handlers.click();const unaccepted=app.status.pendingTrial;
  for(let i=0;i<210;i++){time+=10;sample({trial:0,result:12});}
  await app.tick();assert.equal(app.status.pendingTrial,null);assert.equal(app.status.session,null);
  assert.equal(unaccepted.result,null);assert.equal(app.model.classify(unaccepted),'invalid');
  assert.match(unaccepted.invalidReason,/未接受/);assert.deepEqual(writes.slice(-3),['X',Calibration.command('e',unaccepted.session),'Q']);
  await element('cal-open').handlers.click();sample();advance(1000);await precheck(1);
  await element('cal-pulse').handlers.click();const overCurrent=result(1);
  element('cal-motion').value='yes';element('cal-current').value='.9';element('cal-vmMin').value='12';
  element('cal-reviewSave').handlers.click();await new Promise(resolve=>setImmediate(resolve));
  assert.equal(app.status.session,null);assert.equal(app.model.classify(overCurrent),'invalid');
  assert.match(overCurrent.invalidReason,/长测试电流/);
  connected=false;app.disconnected();assert.equal(element('cal-open').disabled,true);assert.equal(element('cal-emergency').disabled,true);
  // Upright mode directly measures pendulum movement with additive amplitude
  // and a user-selected output time. Old precheck fields must not gate it.
  connected=true;await app.connected();
  const cap2=Calibration.parseLine((body=>body+','+Calibration.crc8(body).toString(16).padStart(2,'0'))('I,DZCAL2,89ABCDEF,09C4,0198,000A,0064,0078,1388,00C8,0096'));
  app.onFrame(cap2);assert.equal(element('cal-profile').value,'3');
  for(const id of ['cal-vm','cal-ratedVm','cal-motorAllowed','cal-encoderAxis','cal-directionNote','cal-instrument','cal-location'])element(id).value='';
  element('cal-ready').checked=false;element('cal-duration').value='5000';element('cal-angleThreshold').value='.5';element('cal-duty').value='1';element('cal-direction').value='1';
  await element('cal-open').handlers.click();const uprightSid=app.status.session.id;
  assert.deepEqual(writes.slice(-3),['Q','!i\n',Calibration.command('c',uprightSid,408,150,1)]);assert.equal(element('cal-legacyControls').hidden,true);
  sample({coreState:0,actual:300});app.update();assert.equal(app.canPulse(3),false,'STOP is not BALANCE');
  sample({coreState:4,actual:300});app.update();assert.equal(app.canPulse(3),true,'nonzero PID output must not block pulse');
  assert.equal(element('cal-pulse').disabled,false);assert.equal(app.model.prechecked(uprightSid,25),false);
  await element('cal-pulse').handlers.click();const longPulse=app.status.pendingTrial;
  assert.equal(longPulse.profile,3);assert.equal(longPulse.durationMs,5000);assert.equal(longPulse.thresholdAdc,7);assert.equal(writes.at(-1),Calibration.command('p',uprightSid,longPulse.id,25,5000,7));
  assert.equal(element('cal-duration').disabled,true);assert.equal(element('cal-angleThreshold').disabled,true);
  const startMs=boardMs;
  for(let i=0;i<250;i++){time+=10;sample({coreState:4,actual:325,requested:325,active:true,phase:8,trial:longPulse.id});}
  await app.tick();assert.equal(app.status.pendingTrial,longPulse,'5000 ms pulse must not expire at 2000 ms');assert.equal(app.status.session.id,uprightSid);
  for(let i=0;i<250;i++){time+=10;sample({coreState:4,actual:325,requested:325,active:true,phase:8,trial:longPulse.id});}
  sample({coreState:4,actual:300,requested:300,active:false,phase:7,result:14,trial:longPulse.id});
  app.onFrame({type:'N',session:uprightSid,trial:longPulse.id,result:14,tCommand:startMs,tPwm:null,tEdge:startMs+20,tAdc:startMs+40,tEnd:startMs+5000,startPosition:0,endPosition:2,startAdc:999,endAdc:1005,maxDeltaAdc:7,added:25,durationMs:5000,thresholdAdc:7,baseline:300});
  assert.equal(app.status.pendingTrial,null);assert.equal(app.model.classify(longPulse),'success');assert.equal(longPulse.confirmed,null);assert.equal(longPulse.delayMs,40);assert.match(element('cal-message').textContent,/指令后 40 ms/);
  assert.equal(app.canPulse(3),true,'no quiet period or minimum rest after an upright pulse');
  element('cal-duty').value='0';element('cal-duration').value='250';element('cal-angleThreshold').value='1';app.update();await element('cal-pulse').handlers.click();const zeroPulse=app.status.pendingTrial;
  assert.equal(writes.at(-1),Calibration.command('p',uprightSid,zeroPulse.id,0,250,13));
  sample({coreState:4,actual:300,requested:300,trial:zeroPulse.id});
  app.onFrame({type:'N',session:uprightSid,trial:zeroPulse.id,result:15,tCommand:boardMs,tPwm:null,tEdge:null,tAdc:null,tEnd:boardMs+250,startPosition:0,endPosition:0,startAdc:999,endAdc:1000,maxDeltaAdc:1,added:0,durationMs:250,thresholdAdc:13,baseline:300});
  assert.equal(app.model.classify(zeroPulse),'failure');assert.equal(app.model.groups().filter(g=>g.profile===3).length,2);
  element('cal-duty').value='1.2';element('cal-direction').value='-1';element('cal-duration').value='5001';app.update();assert.equal(app.canPulse(3),false);
  element('cal-duration').value='1';element('cal-angleThreshold').value='0';app.update();assert.equal(app.canPulse(3),false);
  element('cal-angleThreshold').value='.5';sample({coreState:4,fault:1});app.update();assert.equal(app.canPulse(3),false);
  sample({coreState:4,fault:0});app.update();assert.equal(app.canPulse(3),true);await element('cal-pulse').handlers.click();const negative=app.status.pendingTrial;
  assert.equal(writes.at(-1),Calibration.command('p',uprightSid,negative.id,-30,1,7));
  // Lost/rejected requests are bounded by selected duration + 1000 ms.
  for(let i=0;i<110;i++){time+=10;sample({coreState:4,trial:zeroPulse.id,active:false});}
  await app.tick();assert.equal(app.status.pendingTrial,null);assert.equal(app.model.classify(negative),'invalid');
  assert.deepEqual(writes.slice(-3),['X',Calibration.command('e',uprightSid),'Q']);
  console.log('PASS: legacy calibration plus DZCAL2 PID-preserving session, direct adjustable amplitude/time, no old preconditions, BALANCE/fault gate, automatic pendulum criterion, 5000 ms deadline, immediate repeat, zero baseline and bounded lost request');
})().catch(error=>{console.error(error);process.exitCode=1;});
