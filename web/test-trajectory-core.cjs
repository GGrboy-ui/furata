'use strict';
const assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path');
const T=require('./trajectory-core'),Telemetry=require('./telemetry-core');
const defaults=[1,2,3,4].map(mode=>({mode,time:mode===2?12000:4000,dwell:mode===3?2000:0,cycles:mode===2?3:1,angles:mode===3?[150,0,-150,0]:[150]}));
for(const p of defaults){T.validate(p);assert.equal(T.sample(p,0).q,0);assert.equal(T.sample(p,0).v,0);assert.equal(T.sample(p,T.total(p)).v,0);}
assert.equal(T.sample(defaults[0],2000).q,7.5);assert.equal(T.total(defaults[2]),24000);
for(const p of defaults)for(let i=1;i<1000;i++){const t=T.total(p)*i/1000,h=.01,finite=(T.sample(p,t+h).q-T.sample(p,t-h).q)/(2*h)*1000;assert.ok(Math.abs(finite-T.sample(p,t).v)<.0001,`derivative mode ${p.mode}`);}
assert.equal(T.command(17,defaults[2]),'@T,17,3,4000,2000,1,4,+150,+0,-150,+0\n');
for(const value of ['1e2','NaN','+5X','1.01','3600.1'])assert.throws(()=>T.angle(value));
assert.throws(()=>T.validate({...defaults[0],time:500,angles:[36000]}));
assert.throws(()=>T.validate({...defaults[1],angles:[0]}));
assert.throws(()=>T.validate({...defaults[2],angles:Array(9).fill(0)}));
assert.equal(T.seconds('0.501',.5,600,'time'),501);assert.throws(()=>T.integer('1.2',1,1000,'period'));
assert.equal(T.parse('@I,TRJ1,0198,0FF0,001E,0032').defaultPeriod,50);
const status='@T,0003,01,4,2,1,0014,00000064,00000FA0,FFFFFFF0,00018000,FFFF0000,00020000,0,0014,0003';
const parsed=T.parse(status);assert.equal(parsed.actual,-16);assert.equal(parsed.target,1.5);assert.equal(parsed.velocity,-1);assert.equal(parsed.period,20);
for(const bad of [status+',0',status.replace('0014','0000'),status.replace('FFFFFFF0','oops')])assert.equal(T.parse(bad),null);
const points=Array.from({length:41},(_,i)=>({time:i*5,armPosition:i*.05,session:0}));
assert.ok(Math.abs(T.estimateVelocity(points,408)-10*360/408)<1e-10);
assert.equal(T.estimateVelocity(points.slice(0,2),408),null);
let frames=0;const decoder=new Telemetry.LineDecoder(()=>frames++);decoder.feed(status+'\r\n');assert.equal(decoder.invalid,0);assert.equal(frames,0);
const file=path.join(__dirname,'../build/oss/tb_acg720_trajectory/trajectory_serial.log');
if(fs.existsSync(file)){
 const text=fs.readFileSync(file,'utf8'),lines=text.trim().split(/\r?\n/),trj=lines.filter(s=>s.startsWith('@T,')||s.startsWith('@I,TRJ1,'));
 assert.ok(trj.length>=6);for(const line of trj)assert.ok(T.parse(line),`real RTL response: ${line}`);
 decoder.feed(text);assert.equal(decoder.invalid,0);assert.ok(frames>0);
}
console.log('PASS: four reference profiles/derivatives, limits, TRJ1 framing, velocity estimate, real RTL log and telemetry isolation');
