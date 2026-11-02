 'use strict';
const assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path');
global.Trajectory=require('./trajectory-core');const {create}=require('./trajectory-app');
let time=100;const writes=[],elements=new Map();
const values={'tr-mode':'1','tr-angle':'+15','tr-time':'4','tr-wave-period':'12','tr-amplitude':'15','tr-cycles':'3','tr-points':'+15,0,-15,0','tr-dwell':'2','tr-position-ms':'50','tr-outer':'0','tr-speed-ms':'20','tr-speed-kp':'0.1','tr-speed-ki':'0.02','tr-speed-kpos':'0.5','tr-speed-t':'0'};
function element(id){if(!elements.has(id))elements.set(id,{value:values[id]||'',disabled:false,textContent:'',innerHTML:'',handlers:{},classList:{toggle(){}},addEventListener(k,f){this.handlers[k]=f;}});return elements.get(id);}
const app=create({getElement:element,isConnected:()=>true,now:()=>time,send:async s=>writes.push(s),getRecentTelemetry:()=>[],getTaskTelemetry:()=>[],download(){}});
const tr=(id=0,state=0)=>`@T,${id.toString(16).padStart(4,'0')},00,${state},0,1,0032,00000000,00000FA0,00000000,00000000,00000000,00110000,0,0032,0002\r\n`.toUpperCase();
const vel=(id=0,state=0,code=0,t=0,outer=1)=>`@V,${id.toString(16).padStart(4,'0')},${code.toString(16).padStart(2,'0')},${state},${outer},0014,0000199A,0000051F,00008000,00010000,00018000,FFFF0000,FFFF8000,0002,00000064,${t.toString(16).padStart(4,'0')}\r\n`.toUpperCase();
(async()=>{
 await app.connected();app.feed('@I,TRJ2,0198,0FF0,001E,0032\r\n');app.feed(tr());
 app.feed('@I,VEL2,0014,0005,0064,09C4\r\n');assert.equal(writes.at(-1),'@TVR\n');
 assert.equal(element('tr-speed-t').disabled,false,'draft editable before readback');
 assert.equal(element('tr-t-apply').disabled,true,'wait for extended board readback before applying');
 app.feed(vel());assert.equal(element('tr-speed-t').disabled,false);assert.equal(element('tr-speed-t').max,'2500');
 for(const bad of ['-1','1.5','2501','NaN','']){element('tr-speed-t').value=bad;await app.applySpeed();assert.match(element('tr-message').textContent,/静摩擦补偿/);}
 element('tr-speed-t').value='80';await app.applySpeed(1);assert.equal(writes.at(-1),'@TVD,1,1,20,6554,1311,32768,80\n');
 app.feed(vel(1,0,4,80).replace(',0050\r\n','\r\n'));assert.equal(app.locked,true,'legacy VEL1 snapshot cannot confirm new t');
 app.feed(vel(1,0,4,80));assert.equal(app.locked,false);assert.match(element('tr-speed-actual').textContent,/t=80 PWM/);
 app.feed(tr(1,4));app.feed(vel(1,4,4,80,0));assert.equal(element('tr-speed-t').disabled,false,'running permits drafting t');assert.equal(element('tr-t-apply').disabled,true,'running locks application');
 await app.run();app.feed(vel(1,4,4,80).replace(',0002,00000064',',0003,00000064'));assert.match(app.csv(),/friction_t_pwm_counts/);assert.match(app.csv(),/""frictionT"":80/);
 for(const line of app.csv().trim().split('\r\n').slice(1))assert.match(line,/,"80"(?:,""){5}$/,'CSV final t column uses board value');
 time+=300;await app.poll();assert.equal(writes.at(-1),'@TVR\n');
 app.disconnected();await app.connected();assert.equal(element('tr-speed-t').disabled,false,'draft survives reconnect');assert.equal(element('tr-t-apply').disabled,true,'reconnect requires capability to apply');
 assert.equal(Trajectory.parse('@I,VEL2,0014,0005,0064,0000'),null);
 assert.equal(Trajectory.parse(vel().trim().replace(',0000',',ZZZZ')),null);
 const log=path.join(__dirname,'../build/oss/tb_acg720_velocity/velocity_serial.log');
 if(fs.existsSync(log))for(const line of fs.readFileSync(log,'utf8').split(/\r?\n/))if(line.startsWith('@V,')||line.startsWith('@I,VEL2,'))assert.ok(Trajectory.parse(line),'real RTL '+line);
 console.log('PASS: VEL2 t capability/range, atomic PWM-count setting/readback, legacy replies, running lock, CSV, reconnect, real RTL logs');
})().catch(e=>{console.error(e);process.exitCode=1;});
