(function(root) {
  'use strict';
  const names = ['', '五次多项式', '正弦往返', '多点定位', '七段 S 形速度'];
  const smooth = s => s*s*s*(10+s*(-15+6*s));
  const dsmooth = s => 30*s*s*(1-s)*(1-s);
  function angle(text) {
    const s=String(text).trim();
    if(!/^[+-]?\d+(?:\.\d)?$/.test(s) || Math.abs(Number(s))>3600) throw Error('角度范围为 −3600.0°～+3600.0°，最多一位小数');
    return Math.round(Number(s)*10);
  }
  function integer(text,min,max,label) {
    const s=String(text).trim(),v=Number(s);
    if(!/^\d+$/.test(s)||!Number.isSafeInteger(v)||v<min||v>max) throw Error(`${label}须为 ${min}～${max} 的整数`);
    return v;
  }
  function seconds(text,min,max,label) {
    const s=String(text).trim(),n=Number(s);
    if(!/^\d+(?:\.\d{1,3})?$/.test(s)||!Number.isFinite(n)||n<min||n>max) throw Error(`${label}范围 ${min}～${max} s，精度 0.001 s`);
    return Math.round(n*1000);
  }
  function validate(p,maxSpeed=30) {
    integer(p.mode,1,4,'模式');integer(p.time,500,600000,'移动时间/ms');
    integer(p.dwell,0,600000,'停留时间/ms');integer(p.cycles,1,100,'周期数');
    if(!Array.isArray(p.angles)||!p.angles.length||p.angles.length>8) throw Error('须填写 1～8 个目标点');
    p.angles.forEach(a=>integer(Math.abs(a),0,36000,'角度/0.1°'));
    if(p.mode!==3 && (p.angles.length!==1 || p.dwell!==0)) throw Error('该模式只允许一个角度且无停留');
    if(p.mode!==2 && p.cycles!==1) throw Error('仅正弦模式使用周期数');
    if(p.mode===2 && p.angles[0]<=0) throw Error('正弦幅值必须大于零');
    let previous=0;
    for(const a of p.angles) {
      const peak=Math.abs(p.mode===2?a:a-previous)*(p.mode===2?6284:p.mode===4?1600:1875);
      if(peak>maxSpeed*p.time*10) throw Error(`峰值参考速度超过 ${maxSpeed}°/s，请增加时间或减小角度`);
      previous=a;
    }
    return p;
  }
  const total = p => p.mode===2?p.time*p.cycles:p.mode===3?(p.time+p.dwell)*p.angles.length:p.time;
  function scurve(s) {
    const knots=[0,.125,.25,.375,.625,.75,.875,1],signs=[1,-1,-1,1,-1,1,1,-1];
    let q=0,v=0;
    knots.forEach((k,i)=>{const x=Math.max(0,s-k);q+=signs[i]*x*x*x;v+=signs[i]*x*x;});
    return {q:s>=1?1:q*128/15,v:s>=1?0:v*128/5};
  }
  function sample(p,time) {
    const end=total(p),t=Math.max(0,Math.min(end,time));
    if(t>=end) return {q:p.mode===2?0:p.angles.at(-1)/10,v:0};
    if(p.mode===2) {
      const s=(t%p.time)/p.time,x=2*Math.PI*s;
      const r=Math.min(1,t*2/p.time,(end-t)*2/p.time);
      const sign=t*2<p.time?1:(end-t)*2<p.time?-1:0;
      return {q:p.angles[0]/10*smooth(r)*Math.sin(x),
        v:p.angles[0]/10*(smooth(r)*2*Math.PI*Math.cos(x)+sign*2*dsmooth(r)*Math.sin(x))*1000/p.time};
    }
    const index=p.mode===3?Math.floor(t/(p.time+p.dwell)):0;
    const local=p.mode===3?t%(p.time+p.dwell):t,s=Math.min(1,local/p.time);
    const from=index?p.angles[index-1]/10:0,to=p.angles[index]/10;
    const f=p.mode===4?scurve(s):{q:smooth(s),v:dsmooth(s)};
    return {q:from+(to-from)*f.q,v:(to-from)*f.v*1000/p.time};
  }
  function command(id,p) {
    validate(p);
    integer(id,1,65535,'编号');
    return `@T,${id},${p.mode},${p.time},${p.dwell},${p.cycles},${p.angles.length},${p.angles.map(a=>`${a<0?'-':'+'}${Math.abs(a)}`).join(',')}\n`;
  }
  const signed=s=>parseInt(s,16)|0;
  function parse(line) {
    const parts=line.replace(/\r$/,'').split(',');
    if(line==='@I,POS1')return {type:'positionCapability'};
    if(/^@I,VEL3,0014,0005,0064,[0-9A-F]{4}$/.test(line)){
      const maxPwm=parseInt(parts[5],16);if(maxPwm>0&&maxPwm<=32767)return {type:'velocityCapability',version:3,maxPwm,defaultPeriod:20,minPeriod:5,maxPeriod:100};
    }
    if(parts[0]==='@P'){
      const widths=[4,2,1,4,8,8,8];if(parts.length!==8||parts.slice(1).some((x,i)=>!new RegExp(`^[0-9A-F]{${widths[i]}}$`).test(x)))return null;
      const n=parts.slice(1).map(x=>parseInt(x,16));if(n[2]>6||n[3]<1||n[3]>1000||n.slice(4).some(x=>x>4194304))return null;
      return {type:'positionStatus',id:n[0],code:n[1],state:n[2],period:n[3],kp:n[4]/65536,ki:n[5]/65536,kd:n[6]/65536};
    }
    if(parts[0]==='@W'){
      const widths=[4,2,1,1,4,4,8,8,8,8,4,8,8,8,8,4,8];if(parts.length!==18||parts.slice(1).some((x,i)=>!new RegExp(`^[0-9A-F]{${widths[i]}}$`).test(x)))return null;
      const n=parts.slice(1).map(x=>parseInt(x,16));if(n[2]>6||n[3]>1||n[4]>200||n[5]<5||n[5]>100||n.slice(6,9).some(x=>x>1048576)||n[9]>655360)return null;
      return {type:'velocityStatus',version:3,id:n[0],code:n[1],state:n[2],outer:n[3],handover:n[4],period:n[5],kp:n[6]/65536,ki:n[7]/65536,kd:n[8]/65536,kpos:n[9]/65536,frictionT:n[10],reference:signed(parts[12])/65536,target:signed(parts[13])/65536,actual:signed(parts[14])/65536,angleOffset:signed(parts[15])/65536,activeId:n[15],elapsed:n[16]};
    }
    if(line==='@I,VEL1,0014,0005,0064') return {type:'velocityCapability',defaultPeriod:20,minPeriod:5,maxPeriod:100};
    if(/^@I,VEL2,0014,0005,0064,[0-9A-F]{4}$/.test(line)){
      const maxPwm=parseInt(parts[5],16);
      if(maxPwm>0&&maxPwm<=32767)return {type:'velocityCapability',defaultPeriod:20,minPeriod:5,maxPeriod:100,maxPwm};
    }
    if(parts[0]==='@V') {
      const extended=parts.length===16,widths=[4,2,1,1,4,8,8,8,8,8,8,8,4,8,...(extended?[4]:[])];
      if(![15,16].includes(parts.length)||parts.slice(1).some((v,i)=>!new RegExp(`^[0-9A-F]{${widths[i]}}$`).test(v)))return null;
      const n=parts.slice(1).map(v=>parseInt(v,16));
      if(n[2]>6||n[3]>1||n[4]<5||n[4]>100||n[5]>1048576||n[6]>1048576||n[7]>655360)return null;
      return {type:'velocityStatus',id:n[0],code:n[1],state:n[2],outer:n[3],period:n[4],
        kp:n[5]/65536,ki:n[6]/65536,kpos:n[7]/65536,reference:signed(parts[9])/65536,
        target:signed(parts[10])/65536,actual:signed(parts[11])/65536,angleOffset:signed(parts[12])/65536,
        activeId:n[12],elapsed:n[13],frictionT:extended?n[14]:null};
    }
    if(/^@I,TRJ1,(?:[0-9A-F]{4},){3}[0-9A-F]{4}$/.test(line)) {
      const [cpr,limit,speed,defaultPeriod]=parts.slice(2).map(v=>parseInt(v,16));
      if(cpr&&limit&&speed&&defaultPeriod>=1&&defaultPeriod<=1000) return {type:'capability',cpr,limit,speed,defaultPeriod};
    }
    return null;
  }
  function parseStatus(line) {
    const p=line.replace(/\r$/,'').split(',');
    const widths=[4,2,1,1,1,4,8,8,8,8,8,8,1,4,4];
    if(p.length!==16||p[0]!=='@T'||p.slice(1).some((v,i)=>!new RegExp(`^[0-9A-F]{${widths[i]}}$`).test(v))) return null;
    const n=p.slice(1).map(v=>parseInt(v,16));
    if(n[2]>6||n[3]>5||n[4]>4||n[5]<1||n[5]>1000||n[6]>n[7]||n[12]>7) return null;
    return {type:'status',id:n[0],code:n[1],state:n[2],phase:n[3],mode:n[4],period:n[5],elapsed:n[6],total:n[7],
      actual:signed(p[9]),target:signed(p[10])/65536,velocity:signed(p[11])/65536,goal:signed(p[12])/65536,
      point:n[12],taskPeriod:n[13],activeId:n[14]};
  }
  function estimateVelocity(points,cpr) {
    const latest=points.at(-1);if(!latest)return null;
    const p=points.filter(p=>p.session===latest.session&&p.time>=latest.time-200&&p.armPosition!=null);
    if(p.length<2||p.at(-1).time-p[0].time<50)return null;
    const t0=p[0].time,tm=p.reduce((s,p)=>s+p.time-t0,0)/p.length,ym=p.reduce((s,p)=>s+p.armPosition,0)/p.length;
    let xy=0,xx=0;p.forEach(p=>{const x=p.time-t0-tm;xy+=x*(p.armPosition-ym);xx+=x*x;});
    return xx?xy/xx*1000*360/cpr:null;
  }
  const api={names,smooth,dsmooth,angle,integer,seconds,validate,total,sample,command,parse:line=>parse(line)||parseStatus(line),estimateVelocity};
  root.Trajectory=api;if(typeof module==='object')module.exports=api;
})(typeof globalThis!=='undefined'?globalThis:this);
