(function(root) {
 'use strict';
 const codes={0:'状态已更新',1:'已接受，正在执行轨迹',2:'已到位，保持目标位置',3:'任务已取消',4:'位置环周期已生效',
  16:'板端忙，拒绝新请求',17:'当前状态不允许此操作',18:'参数、峰值速度或完整行程超界',19:'命令格式错误或超时',20:'重复编号，未再次执行'};
 const phaseNames=['空闲','校验整条轨迹','执行中','轨迹结束，等待到位','已到位，保持目标位置','已取消'];
 function plot(series,velocity=false) {
  const valid=series.filter(s=>Number.isFinite(s.q));if(!valid.length)return '';
  const w=720,h=180,left=55,right=700,top=20,bottom=145;
  let min=Math.min(0,...valid.map(s=>s.q)),max=Math.max(0,...valid.map(s=>s.q));
  if(max-min<1){min-=.5;max+=.5;}const pad=(max-min)*.12;min-=pad;max+=pad;
  const total=Math.max(1,...valid.map(s=>s.t));
  const paths=[...new Set(valid.map(s=>s.group||0))].map(group=>{const path=valid.filter(s=>(s.group||0)===group).map((s,i)=>`${i?'L':'M'}${(left+s.t/total*(right-left)).toFixed(2)},${(bottom-(s.q-min)/(max-min)*(bottom-top)).toFixed(2)}`).join(' ');return `<path d="${path}" fill="none" stroke="${['#f5b868','#62dfc5','#b79bff'][group]||'#62dfc5'}" stroke-width="2"/>`;}).join('');
  return `<svg viewBox="0 0 ${w} ${h}" role="img" aria-label="${velocity?'参考速度':'参考位置'}曲线"><path d="M${left},${top}V${bottom}H${right}" fill="none" stroke="#526076"/>${paths}<g fill="#aebbd0" font-size="12"><text x="5" y="16">${velocity?'°/s':'°'}</text><text x="5" y="35">${max.toFixed(1)}</text><text x="5" y="145">${min.toFixed(1)}</text><text x="55" y="168">0</text><text x="635" y="168">${(total/1000).toFixed(1)} s</text></g></svg>`;
 }
 function create(options) {
  const $=options.getElement,now=options.now||(()=>Date.now()),send=options.send;
  let pid=null;
  let capability=null,status=null,lastAt=0,lastQuery=0,pending=false,uncertain=false,stopping=false,expected=0,nextId=0,sentAt=0;
  let buffer='',session=0,queryWriting=false,preview=null,task=null,taskRows=[],truncated=false;
  let velocityCapability=false,frictionMax=null,velocityStatus=null,velocityAt=0,speedRows=[],pendingType='',idSeeded=false;
  let frictionDraft=false,frictionQueryWriting=false,frictionProbeCount=0,lastFrictionProbe=0;
  const speedFields=['tr-outer','tr-speed-ms','tr-speed-kp','tr-speed-ki','tr-speed-kpos'];
  const connected=()=>options.isConnected(),fresh=()=>!!lastAt&&now()-lastAt<1500;
  const busy=()=>!!status&&[1,2,3].includes(status.phase);
  const locked=()=>pending||uncertain||busy()||!!pid?.locked;
  function show(text,error=false){$('tr-message').textContent=text;$('tr-message').classList.toggle('error',error);}
  function params(validate=true) {
   const mode=Trajectory.integer($('tr-mode').value,1,4,'模式');
   const time=Trajectory.seconds($(mode===2?'tr-wave-period':'tr-time').value,.5,600,mode===2?'正弦周期':'每段移动用时');
   let angles;
   if(mode===3){const text=$('tr-points').value.trim();angles=text.split(/[\s,，;；]+/).filter(Boolean).map(Trajectory.angle);}
   else angles=[Trajectory.angle($(mode===2?'tr-amplitude':'tr-angle').value)];
   const config={mode,time,dwell:mode===3?Trajectory.seconds($('tr-dwell').value,0,600,'停留时间'):0,
    cycles:mode===2?Trajectory.integer($('tr-cycles').value,1,100,'周期数'):1,angles};
   return validate?Trajectory.validate(config,capability?.speed||30):config;
  }
  function slowTime() {
   try{const config=params(false),time=Math.max(config.time,Trajectory.recommendedTime(config,capability?.speed||30));
    $(config.mode===2?'tr-wave-period':'tr-time').value=String(time/1000);
    refreshPreview();
   }catch(e){show(e.message,true);}
  }
  function preset() {
   const angle=Trajectory.integer($('tr-size').value,60,360,'推荐角度'),sign=$('tr-angle').value.trim().startsWith('-')?-1:1;
   $('tr-angle').value=`${sign<0?'-':'+'}${angle}`;$('tr-amplitude').value=String(angle);
   $('tr-points').value=`${sign*angle}, 0, ${-sign*angle}, 0`;
   $('tr-time').value='15';$('tr-wave-period').value='20';
   slowTime();
  }
  function refreshPreview() {
   const mode=Number($('tr-mode').value);
   $('tr-angle-field').hidden=mode===2||mode===3;$('tr-time-field').hidden=mode===2;
   $('tr-sine-fields').hidden=mode!==2;$('tr-waypoint-fields').hidden=mode!==3;
   try {
    preview=params();const total=Trajectory.total(preview);
    const samples=Math.max(241,preview.mode===2?preview.cycles*64+1:preview.mode===3?preview.angles.length*80+1:241);
    const points=Array.from({length:samples},(_,i)=>({t:total*i/(samples-1),...Trajectory.sample(preview,total*i/(samples-1))}));
    $('tr-preview-position').innerHTML=plot(points.map(p=>({t:p.t,q:p.q})));
    $('tr-preview-velocity').innerHTML=plot(points.map(p=>({t:p.t,q:p.v})),true);
    const vmax=Math.max(...points.map(p=>Math.abs(p.v)));
    $('tr-preview-info').textContent=`位置环规划预览（相对本次起点，非实测）：${Trajectory.names[mode]} · ${(total/1000).toFixed(3)} s · 峰值参考速度约 ${vmax.toFixed(2)}°/s${mode===4?' · 七段时长比 1:1:1:2:1:1:1':''}`;
   }catch(e){preview=null;$('tr-preview-info').textContent=e.message;$('tr-preview-position').innerHTML='';$('tr-preview-velocity').innerHTML='';}
   update();
  }
  function update() {
   const motionLocked=locked()||!!options.legacyLocked?.();
   $('tr-run').disabled=(pid&&!pid.canRun)||!connected()||capability?.version!==2||!fresh()||status?.state!==4||motionLocked||!preview||(velocityCapability&&(!velocityStatus||velocityStatus.outer!==0||now()-velocityAt>=1500));
   if(!pid){$('tr-period-apply').disabled=!connected()||!capability||!fresh()||![0,4].includes(status?.state)||motionLocked;
   $('tr-period-default').disabled=$('tr-period-apply').disabled;
   }
   $('tr-emergency').disabled=!connected();$('tr-query').disabled=!connected()||queryWriting;
   $('tr-export').disabled=!taskRows.length&&!speedRows.length;
   if(!pid){
   const speedEnabled=connected()&&velocityCapability&&(frictionMax===null||velocityStatus?.frictionT!=null)&&fresh()&&status?.state===0&&velocityStatus?.state===0&&now()-velocityAt<1500&&!motionLocked;
   $('tr-speed-apply').disabled=!speedEnabled;
   $('tr-enter-speed').disabled=!speedEnabled;$('tr-enter-position').disabled=!speedEnabled;
   speedFields.forEach(id=>$(id).disabled=!speedEnabled);
   $('tr-speed-t').disabled=false;
   $('tr-t-apply').disabled=!speedEnabled||frictionMax===null;
   $('tr-t-query').disabled=!connected()||frictionQueryWriting||motionLocked;
   const tReason=!connected()?'未连接串口':frictionMax===null?'未识别支持 t 的固件，点击“识别／查询 t 配置”；旧固件需先下载 VEL2 固件':!fresh()||!velocityStatus||now()-velocityAt>=1500||velocityStatus.frictionT==null?'等待板端配置回读':status?.state!==0||velocityStatus.state!==0?'请先按 X 或 K4 停机':motionLocked?'等待当前请求确认':'可点击“仅应用 t（停机）”下发';
   $('tr-friction-info').textContent=`t 输入为待应用值，编辑不会直接改变板端。${tReason}。范围 0～${frictionMax??2500} PWM 计数，0 关闭。`;
   if(frictionMax!==null)$('tr-speed-t').max=String(frictionMax);
   $('tr-speed-capability').textContent=velocityCapability?`${frictionMax===null?'VEL1':'VEL2'} 已识别 · ${!velocityStatus||now()-velocityAt>=1500?'等待板端回读':velocityStatus.state!==0?'请先 X/K4 停机后设置':'可设置模式、Kp、Ki、Kpos 和速度周期'}`:'未识别 VEL1；速度外环设置不可用，旧固件仍可使用原功能';
   }else pid.update();
   $('tr-run-help').textContent=capability?.version!==2?'请下载 TRJ2 位置轨迹固件；旧 TRJ1 轨迹使用速度环，本页面不执行旧模式。':!connected()?'连接串口后查询板端状态。':!velocityStatus||now()-velocityAt>=1500?'等待板端实际外环回读。':velocityStatus.outer!==0?'当前为速度环。请先 X/K4 停机，再按 K1/K3 进入位置平衡后执行轨迹。':status?.state!==4?'请按 K1 起摆或 K3 进入位置环直立平衡，再执行轨迹。':'位置 PID 跟随规划位置，速度曲线为该位置曲线的导数；保持位置模式，不按 K2 切速度环。';
   $('tr-capability').textContent=capability?`TRJ${capability.version} · ${capability.version===2?'位置环轨迹':'旧速度环轨迹，需升级'} · ${capability.cpr} counts/圈 · 最大 ${capability.speed}°/s · 行程 ±${capability.limit*360/capability.cpr}°`:'需要支持 TRJ2 的位置轨迹固件；旧 ARM1 普通移动保留';
   $('tr-state').textContent=!connected()?'未连接':!fresh()?'等待板端状态':`${status.state===4?'直立平衡':status.state===0?'停机':`控制状态 ${status.state}`} · ${phaseNames[status.phase]}${pending?' · 等待请求确认':''}${uncertain?' · 结果不确定':''}`;
   options.onStateChange?.();
  }
  function telemetry() {return options.getRecentTelemetry?.()||[];}
  function displayStatus(s) {
   const scale=360/capability.cpr,estimated=Trajectory.estimateVelocity(telemetry(),capability.cpr);
   if(!pid)$('tr-period-actual').textContent=`${s.period} ms / ${(1000/s.period).toFixed(2)} Hz`;
   $('tr-progress').textContent=`${(s.elapsed/1000).toFixed(3)} / ${(s.total/1000).toFixed(3)} s · 点 ${s.point+1}`;
   $('tr-reference').textContent=`${(s.target*scale).toFixed(3)}°`;
   $('tr-actual').textContent=`${(s.actual*scale).toFixed(3)}°`;
   $('tr-reference-speed').textContent=`${(s.velocity*scale).toFixed(3)}°/s`;
   $('tr-actual-speed').textContent=estimated===null?'等待至少 50 ms 位置数据':`${estimated.toFixed(2)}°/s（最近 200 ms 拟合）`;
   if(task&&s.activeId===task.id&&s.mode===task.config.mode) {
    task.period=s.taskPeriod;
    if([4,5].includes(s.phase)&&task.endTime==null)task.endTime=telemetry().at(-1)?.time??null;
    const last=taskRows.at(-1);
    if(!last||last.elapsed!==s.elapsed||last.phase!==s.phase) {
     taskRows.push({...s,estimatedVelocity:estimated,telemetryTime:telemetry().at(-1)?.time??null});
     if(taskRows.length>20000){taskRows.shift();truncated=true;}
    }
    const rows=taskRows.slice(-1200);
    $('tr-live-position').innerHTML=plot(rows.flatMap(r=>[{t:r.elapsed,q:r.target*scale,group:0},{t:r.elapsed,q:r.actual*scale,group:1}]));
    if(!velocityCapability)$('tr-live-velocity').innerHTML=plot(rows.map(r=>({t:r.elapsed,q:r.velocity*scale})),true);
   }
  }
  function feed(text) {
   pid?.feed(text);
   buffer+=text;let index;
   while((index=buffer.indexOf('\n'))>=0){
    const line=buffer.slice(0,index).replace(/\r$/,'');buffer=buffer.slice(index+1);
    const frame=Trajectory.parse(line);if(!frame)continue;
    if(frame.type==='positionCapability'||frame.type==='positionStatus')continue;
    if(frame.type==='velocityCapability'){
     velocityCapability=true;
     if(pid){frictionMax=frame.maxPwm||frictionMax;}else if(frame.maxPwm){frictionMax=frame.maxPwm;void send('@TVR\n').catch(e=>show(e.message,true));}
     else {void queryFriction();void send('@TVQ\n').catch(e=>show(e.message,true));}
    } else if(frame.type==='velocityStatus'){
     if(frictionMax!==null&&frame.frictionT==null)continue;
     if(!pid&&!frictionDraft&&frame.frictionT!=null&&velocityStatus?.frictionT==null)$('tr-speed-t').value=String(frame.frictionT);
     if(!pid&&!velocityStatus){
      $('tr-outer').value=String(frame.outer);$('tr-speed-ms').value=String(frame.period);
      $('tr-speed-kp').value=String(frame.kp);$('tr-speed-ki').value=String(frame.ki);$('tr-speed-kpos').value=String(frame.kpos);
     }
     velocityStatus=frame;velocityAt=now();
     const scale=360/(capability?.cpr||408);
     if(!pid)$('tr-speed-actual').textContent=`板端：${frame.outer?'速度外环':'位置外环'} · ${frame.period} ms · Kp=${frame.kp.toFixed(5)} · Ki=${frame.ki.toFixed(5)} · Kpos=${frame.kpos.toFixed(5)} · t=${frame.frictionT==null?'未支持':frame.frictionT+' PWM 计数'}`;
     $('tr-measured-speed').textContent=`${(frame.actual*scale).toFixed(3)}°/s`;
     $('tr-target-speed').textContent=frame.outer===0?'—（位置环跟踪）':`${(frame.target*scale).toFixed(3)}°/s`;
     if(expected&&frame.id===expected&&pendingType==='speed'){
      pending=false;uncertain=false;pendingType='';show(frame.code===4?'外环及速度参数已生效，以上为板端回读':codes[frame.code]||'设置失败',frame.code!==4);
     }
     if(task&&frame.activeId===task.id&&!task.speedClosed){
      speedRows.push({...frame});if(frame.state!==4)task.speedClosed=true;if(speedRows.length>20000){speedRows.shift();truncated=true;}
      const rows=speedRows.slice(-1200),points=[];
      rows.forEach(r=>{points.push({t:r.elapsed,q:r.reference*scale,group:0},...(r.outer===0?[{t:r.elapsed,q:r.actual*scale,group:1}]:[{t:r.elapsed,q:r.target*scale,group:1},{t:r.elapsed,q:r.actual*scale,group:2}]));});
      $('tr-live-velocity').innerHTML=plot(points,true);
     }
    } else if(frame.type==='capability'){capability=frame;show(frame.version===2?'已识别位置环轨迹。按 K1/K3 进入位置平衡，使用 60°～360°预设及较长用时；无需切速度环。':'已识别旧 TRJ1 速度轨迹固件；请升级 TRJ2 后使用位置环轨迹。',frame.version!==2);void query();if(!pid)void send('@TVI\n').catch(e=>show(e.message,true));}
    else if(capability){
     status=frame;lastAt=now();if(!idSeeded&&!pending&&!uncertain){nextId=frame.id;idSeeded=true;}
     if(expected&&frame.id===expected&&pendingType!=='speed'){
      pending=false;uncertain=false;show(codes[frame.code]||`板端结果 ${frame.code}`,frame.code>=16);
     }
     if(stopping&&frame.state===0&&![1,2,3].includes(frame.phase)){pending=false;uncertain=false;stopping=false;show('板端已停机，任务取消。');}
     displayStatus(frame);
    }
   }
   if(buffer.length>4096)buffer='';update();
  }
  async function query(){
   if(!connected()||queryWriting)return;const token=session;queryWriting=true;update();
   try{await send(capability?'@TQ\n':'@TI\n');}catch(e){if(token===session)show(`查询失败：${e.message}`,true);}
   finally{if(token===session){queryWriting=false;update();}}
  }
  async function request(command){
   const token=session;pending=true;uncertain=false;sentAt=now();show('已提交请求，等待板端确认实际生效。');update();
   try{await send(command);}catch(e){if(token===session){uncertain=true;show(`发送结果不确定：${e.message}；只查询，不自动重发。`,true);}}
   finally{if(token===session)update();}
  }
  const allocate=()=>{nextId=nextId%65535+1;if(nextId===status?.activeId)nextId=nextId%65535+1;expected=nextId;return nextId;};
  async function run(){
   if($('tr-run').disabled)return;
   try{
    const config=params(),id=allocate(),last=telemetry().at(-1);
    task={id,config,position:pid?.snapshot.position??null,speed:velocityStatus?{outer:velocityStatus.outer,period:velocityStatus.period,kp:velocityStatus.kp,ki:velocityStatus.ki,kd:velocityStatus.kd,kpos:velocityStatus.kpos,frictionT:velocityStatus.frictionT}:null,period:status.period,startTime:last?.time??null,session:last?.session??null};taskRows=[];speedRows=[];truncated=false;pendingType='trajectory';
    await request(Trajectory.command(id,config));
   }catch(e){show(e.message,true);}
  }
  async function applySpeed(outerOverride){
   if($('tr-speed-apply').disabled)return;
   try{
    const outer=Trajectory.integer(outerOverride===0||outerOverride===1?outerOverride:$('tr-outer').value,0,1,'外环');
    const period=Trajectory.integer($('tr-speed-ms').value,5,100,'速度周期/ms');
    const gains=['tr-speed-kp','tr-speed-ki','tr-speed-kpos'].map((id,i)=>{
     const text=$(id).value.trim(),value=Number(text),max=i===2?10:16;
     if(!/^(?:\d+(?:\.\d*)?|\.\d+)$/.test(text)||!Number.isFinite(value)||value<0||value>max)throw Error(`增益须为 0～${max} 的数值`);
     return Math.round(value*65536);
    });
    if(frictionMax===null&&frictionDraft&&$('tr-speed-t').value.trim()!=='0')throw Error('t 尚未识别，未下发任何参数；请点击“识别／查询 t 配置”或下载 VEL2 固件');
    const friction=frictionMax===null?null:Trajectory.integer($('tr-speed-t').value,0,frictionMax,'静摩擦补偿 t/PWM 计数');
    if(frictionMax!==null&&velocityStatus?.frictionT==null)throw Error('等待支持 t 的板端配置回读');
    $('tr-outer').value=String(outer);
    const id=allocate();pendingType='speed';await request(`@TV${friction===null?'C':'D'},${id},${outer},${period},${gains.join(',')}${friction===null?'':','+friction}\n`);
   }catch(e){show(e.message,true);}
  }
  async function applyFriction(){
   if($('tr-t-apply').disabled)return;
   try{
    const t=Trajectory.integer($('tr-speed-t').value,0,frictionMax,'静摩擦补偿 t/PWM 计数');
    // Preserve the board's actual mode/PI/period, including unsent form drafts.
    const v=velocityStatus,id=allocate();pendingType='speed';
    await request(`@TVD,${id},${v.outer},${v.period},${[v.kp,v.ki,v.kpos].map(x=>Math.round(x*65536)).join(',')},${t}\n`);
   }catch(e){show(e.message,true);}
  }
  async function queryFriction(){
   if(!connected()||frictionQueryWriting||locked()||options.legacyLocked?.())return;
   const token=session;frictionQueryWriting=true;update();
   try{
    if(frictionMax===null){frictionProbeCount++;lastFrictionProbe=now();}
    await send(frictionMax===null?'@TV2\n':'@TVR\n');
   }catch(e){if(token===session)show(`t 配置查询失败：${e.message}`,true);}
   finally{if(token===session){frictionQueryWriting=false;update();}}
  }
  async function applyPeriod(useDefault=false){
   if($('tr-period-apply').disabled)return;
   try{const value=useDefault?capability.defaultPeriod:Trajectory.integer($('tr-position-ms').value,1,1000,'位置环周期/ms');
    if(useDefault)$('tr-position-ms').value=String(value);
    const id=allocate();pendingType='period';await request(`@TC,${id},${value}\n`);
   }catch(e){show(e.message,true);}
  }
  async function emergency(){
   if(!connected())return;stopping=true;uncertain=true;update();
   try{await send('X');show('已发送 X，等待板端停机确认。');}catch(e){show(`X 发送失败：${e.message}；请使用实体 K4。`,true);}
   await query();
  }
  async function poll(){
   if(!connected())return;
   if(pid)await pid.poll();
   if(pending&&now()-sentAt>2500){uncertain=true;show('未收到匹配确认；正在查询板端，不自动重发。',true);}
   if(capability&&now()-lastQuery>=250&&!queryWriting){lastQuery=now();await query();if(!pid&&velocityCapability)await send(frictionMax===null?'@TVQ\n':'@TVR\n').catch(e=>show(e.message,true));}
   if(!pid&&velocityCapability&&frictionMax===null&&frictionProbeCount<3&&fresh()&&status?.state===0&&now()-lastFrictionProbe>=1000)await queryFriction();
   update();
  }
  function csv(){
   if(!task)return '';
   const esc=v=>v==null?'':`"${String(v).replace(/"/g,'""')}"`;
   const header=['kind','task_id','mode','position_period_ms','config_json','elapsed_ms','phase','actual_counts','reference_counts','reference_velocity_counts_per_s','estimated_velocity_deg_per_s','telemetry_time_ms','sequence','pendulum_angle_deg','requested_pwm_counts','actual_pwm_counts','session','status_rows_truncated'];
   const metadata=[task.id,task.config.mode,task.period,JSON.stringify({...task.config,position:task.position,speed:task.speed})];
   const rows=taskRows.map(r=>['status',...metadata,r.elapsed,r.phase,r.actual,r.target,r.velocity,r.estimatedVelocity,r.telemetryTime,'','','','',task.session,truncated]);
   for(const p of options.getTaskTelemetry?.(task)||[])
    rows.push(['telemetry',...metadata,'','',p.armPosition,p.positionTarget,'','',p.time,p.sequence,p.angle,p.requestedPwm,p.actualPwm,p.session,truncated]);
   header.push('outer_mode','speed_period_ms','speed_kp','speed_ki','position_kpos','speed_target_counts_per_s','speed_feedback_counts_per_s','angle_target_offset_adc','friction_t_pwm_counts','position_kp','position_ki','position_kd','speed_kd','handover_remaining_ms');
   rows.forEach(r=>r.push(task.speed?.outer??'',task.speed?.period??'',task.speed?.kp??'',task.speed?.ki??'',task.speed?.kpos??'','','','',task.speed?.frictionT??'',task.position?.kp??'',task.position?.ki??'',task.position?.kd??'',task.speed?.kd??'',''));
   speedRows.forEach(r=>rows.push(['velocity',...metadata,r.elapsed,'','','',r.reference,'','','','','','',task.session,truncated,
    r.outer,r.period,r.kp,r.ki,r.kpos,r.target,r.actual,r.angleOffset,r.frictionT,task.position?.kp??'',task.position?.ki??'',task.position?.kd??'',r.kd??'',r.handover??'']));
   return '\ufeff'+[header,...rows].map(r=>r.map(esc).join(',')).join('\r\n')+'\r\n';
  }
  if(typeof DualPidApp!=='undefined')pid=DualPidApp.create({...options,isMotionLocked:()=>pending||uncertain||busy()||!!options.legacyLocked?.(),onChange:update});
  if(!pid){
  $('tr-speed-t').addEventListener('input',()=>{frictionDraft=true;update();});
  $('tr-t-apply').addEventListener('click',applyFriction);
  $('tr-t-query').addEventListener('click',queryFriction);
  $('tr-speed-apply').addEventListener('click',()=>applySpeed());
  $('tr-enter-speed').addEventListener('click',()=>applySpeed(1));
  $('tr-enter-position').addEventListener('click',()=>applySpeed(0));
  }
  $('tr-run').addEventListener('click',run);$('tr-query').addEventListener('click',query);$('tr-emergency').addEventListener('click',emergency);
  $('tr-preset').addEventListener('click',preset);$('tr-size').addEventListener('change',preset);$('tr-slow').addEventListener('click',slowTime);
  if(!pid)$('tr-period-apply').addEventListener('click',()=>applyPeriod());if(!pid)$('tr-period-default').addEventListener('click',()=>applyPeriod(true));
  for(const id of ['tr-mode','tr-angle','tr-time','tr-wave-period','tr-amplitude','tr-cycles','tr-points','tr-dwell'])$(id).addEventListener('input',refreshPreview);
  $('tr-export').addEventListener('click',()=>options.download(csv(),`furuta-trajectory-${Date.now()}.task.csv`));
  refreshPreview();
  return {feed,poll,update,run,query,applySpeed,applyFriction,queryFriction,applyPeriod,emergency,csv,get locked(){return locked();},
   async connected(){if(task)task.speedClosed=true;session++;capability=null;status=null;velocityCapability=false;frictionMax=null;frictionQueryWriting=false;frictionProbeCount=0;lastFrictionProbe=0;velocityStatus=null;velocityAt=0;pendingType='';idSeeded=false;lastAt=0;pending=false;uncertain=false;stopping=false;expected=0;buffer='';queryWriting=false;await query();if(pid)await pid.connected();},
   disconnected(){if(task)task.speedClosed=true;pid?.disconnected();session++;capability=null;status=null;velocityCapability=false;frictionMax=null;frictionQueryWriting=false;frictionProbeCount=0;lastFrictionProbe=0;velocityStatus=null;velocityAt=0;pendingType='';idSeeded=false;lastAt=0;pending=false;uncertain=false;queryWriting=false;stopping=false;buffer='';show('串口已断开；重连不会自动恢复任务。');update();},
   async beforeDisconnect(){if(locked())await send('X');}
  };
 }
 const api={create,plot};root.TrajectoryApp=api;if(typeof module==='object')module.exports=api;
})(typeof globalThis!=='undefined'?globalThis:this);
