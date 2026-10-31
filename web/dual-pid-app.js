(function(root){
 'use strict';
 function create(options){
  const $=options.getElement,send=options.send,now=options.now||(()=>Date.now());
  let pc=false,vc=false,p=null,v=null,pa=0,va=0,buffer='',pending=null,uncertain=false,session=0,lastPoll=0,lastPosPoll=0,probing=0,lastProbe=0,pNext=null,vNext=null;
  const dirty=new Set(),fields={position:['pos-ms','pos-kp','pos-ki','pos-kd'],speed:['tr-speed-ms','tr-speed-kp','tr-speed-ki','tr-speed-kd','tr-speed-kpos','tr-speed-t']};
  const fresh=t=>t>0&&now()-t<1500,connected=()=>options.isConnected();
  function enabled(bank){const x=bank==='position'?p:v,a=bank==='position'?pa:va,c=bank==='position'?pc:vc;return connected()&&c&&x?.state===0&&fresh(a)&&!pending&&!uncertain&&!options.isMotionLocked?.()&&!(p&&fresh(pa)&&p.state!==0)&&!(v&&fresh(va)&&v.state!==0);}
  function message(s,error=false){$('pid-message').textContent=s;$('pid-message').classList.toggle('error',error);}
  function update(){
   fields.position.concat(fields.speed).forEach(id=>$(id).disabled=false);
   $('pos-apply').disabled=!enabled('position');$('tr-speed-apply').disabled=!enabled('speed');$('tr-t-apply').disabled=!enabled('speed');$('tr-t-query').disabled=!connected()||!!pending||uncertain;
   $('pos-capability').textContent=pc?'POS1 已识别，位置增益只写位置 PID':'等待 POS1；旧固件不开放位置 PID 设置';
   $('tr-speed-capability').textContent=vc?'VEL3 已识别，速度增益只写速度 PID':'等待 VEL3；旧固件不开放速度 PID 设置';
   $('pid-mode').textContent=!vc?'等待 POS1/VEL3；按键新功能需使用本版固件':!v||!fresh(va)?'等待实际外环回读':v.state===0?`停机（上次${v.outer?'速度':'位置'}模式；K1/K3 启动仍进入位置环）`:v.handover?`位置 → 速度交接中，剩余 ${v.handover} ms`:`当前：${v.outer?'速度外环':'位置外环'}`;
   $('tr-friction-info').textContent=`t 为待应用 PWM 计数，范围 0～${v?.maxPwm||2500}。${!vc?'点击查询识别 VEL3 固件':v?.state!==0?'先 X/K4 停机再下发':'停机可单独应用 t，保留板端速度 PID 与周期'}。`;
   if(p)$('pos-actual').textContent=`板端位置：${p.period} ms · Kp=${p.kp.toFixed(6)} · Ki=${p.ki.toFixed(6)} · Kd=${p.kd.toFixed(6)}`;
   if(v){$('tr-speed-actual').textContent=`板端速度：${v.period} ms · Kp=${v.kp.toFixed(6)} · Ki=${v.ki.toFixed(6)} · Kd=${v.kd.toFixed(6)} · Kpos=${v.kpos.toFixed(6)} · t=${v.frictionT}`;$('tr-speed-t').max=String(v.maxPwm||2500);}
  }
  function initialize(bank,frame){const ids=fields[bank],vals=bank==='position'?[frame.period,frame.kp,frame.ki,frame.kd]:[frame.period,frame.kp,frame.ki,frame.kd,frame.kpos,frame.frictionT];ids.forEach((id,i)=>{if(!dirty.has(id))$(id).value=String(vals[i]);});}
  function feed(text){buffer+=text;let i;while((i=buffer.indexOf('\n'))>=0){const line=buffer.slice(0,i).replace(/\r$/,'');buffer=buffer.slice(i+1);const f=Trajectory.parse(line);if(!f)continue;
   if(f.type==='positionCapability'){pc=true;void send('@TPQ\n').catch(e=>message(e.message,true));}
   else if(f.type==='velocityCapability'&&f.version===3){vc=true;const maxPwm=f.maxPwm;speedMax=maxPwm;if(v)v.maxPwm=maxPwm;void send('@TVS\n').catch(e=>message(e.message,true));}
   else if(f.type==='positionStatus'&&pc){if(!p)initialize('position',f);p=f;pa=now();if(pNext===null)pNext=f.id;confirm('position',f);}
   else if(f.type==='velocityStatus'&&f.version===3&&vc){f.maxPwm=speedMax;if(!v)initialize('speed',f);v=f;va=now();if(vNext===null)vNext=f.id;confirm('speed',f);}
  }if(buffer.length>4096)buffer='';update();options.onChange?.();}
  let speedMax=2500;
  function confirm(bank,f){if(pending?.bank===bank&&pending.id===f.id){pending=null;uncertain=false;message(f.code===4?`${bank==='position'?'位置':'速度'}参数已生效，请核对板端回读`:`设置未生效（${f.code===17?'仅允许停机设置':f.code===18?'参数超界':'结果 '+f.code}）`,f.code!==4);}}
  function gain(id,max){const s=$(id).value.trim(),x=Number(s);if(!/^(?:\d+(?:\.\d*)?|\.\d+)$/.test(s)||!Number.isFinite(x)||x<0||x>max)throw Error(`${id.startsWith('pos-')?'位置':'速度'}增益范围 0～${max}`);return Math.round(x*65536);}
  async function request(bank,tail){let id=bank==='position'?pNext:vNext;id=(id||0)%65535+1;if(bank==='speed'&&id===v?.activeId)id=id%65535+1;if(bank==='position')pNext=id;else vNext=id;
   const token=session;pending={bank,id,at:now()};uncertain=false;message('已发送，等待对应参数组的板端确认');update();options.onChange?.();
   try{await send(`@${bank==='position'?'TPC':'TVE'},${id},${tail}\n`);}catch(e){if(token===session){uncertain=true;message(`发送结果不确定：${e.message}；只查询，不重发设置`,true);}}finally{if(token===session){update();options.onChange?.();}}
  }
  async function applyPosition(){if(!enabled('position'))return;try{const period=Trajectory.integer($('pos-ms').value,1,1000,'位置周期/ms'),g=['pos-kp','pos-ki','pos-kd'].map(id=>gain(id,64));await request('position',[period,...g].join(','));}catch(e){message(e.message,true);}}
  async function applySpeed(){if(!enabled('speed'))return;try{const period=Trajectory.integer($('tr-speed-ms').value,5,100,'速度周期/ms'),g=['tr-speed-kp','tr-speed-ki','tr-speed-kd'].map(id=>gain(id,16)),kpos=gain('tr-speed-kpos',10),t=Trajectory.integer($('tr-speed-t').value,0,speedMax,'t/PWM 计数');await request('speed',[period,...g,kpos,t].join(','));}catch(e){message(e.message,true);}}
  async function applyFriction(){if(!enabled('speed'))return;try{const t=Trajectory.integer($('tr-speed-t').value,0,speedMax,'t/PWM 计数');await request('speed',[v.period,...[v.kp,v.ki,v.kd,v.kpos].map(x=>Math.round(x*65536)),t].join(','));}catch(e){message(e.message,true);}}
  async function query(){if(!connected())return;probing++;lastProbe=now();await send('@TPI\n');await send('@TV3\n');if(pc)await send('@TPQ\n');if(vc)await send('@TVS\n');}
  async function poll(){if(!connected())return;if(pending&&now()-pending.at>2500){uncertain=true;message('确认超时；正在查询对应参数组，不自动重发设置',true);}
   try{if((!pc||!vc)&&probing<3&&now()-lastProbe>=1000&&!pending)await query();if(vc&&now()-lastPoll>=250){lastPoll=now();await send('@TVS\n');}if(pc&&now()-lastPosPoll>=1000){lastPosPoll=now();await send('@TPQ\n');}}catch(e){message(e.message,true);}update();options.onChange?.();}
  for(const id of fields.position.concat(fields.speed))$(id).addEventListener('input',()=>dirty.add(id));
  $('pos-apply').addEventListener('click',applyPosition);$('tr-speed-apply').addEventListener('click',applySpeed);$('tr-t-apply').addEventListener('click',applyFriction);$('tr-t-query').addEventListener('click',()=>query().catch(e=>message(e.message,true)));
  function reset(){session++;pc=false;vc=false;p=null;v=null;pa=0;va=0;pending=null;uncertain=false;buffer='';pNext=null;vNext=null;probing=0;lastProbe=0;lastPoll=0;lastPosPoll=0;speedMax=2500;update();}
  update();return {feed,update,poll,query,applyPosition,applySpeed,applyFriction,get locked(){return !!pending||uncertain;},get canRun(){return connected()&&vc&&fresh(va)&&v?.state===4&&v.outer===1&&v.handover===0&&!pending&&!uncertain;},get snapshot(){return {position:p?{...p}:null,speed:v?{...v}:null};},async connected(){reset();await query();},disconnected:reset};
 }
 root.DualPidApp={create};if(typeof module==='object')module.exports={create};
})(typeof globalThis!=='undefined'?globalThis:this);
