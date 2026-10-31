(function(root){
 'use strict';
 function create({now=()=>Date.now(),limit=20000,cpr=408}={}){
  let entries=[],pending='',session=0,truncated=false,total=0,velocityFrames=0,lastVelocity=null,lastPosition=null;
  function add(kind,raw,extra={}){entries.push({hostTimeMs:now(),session,kind,raw,...extra});total++;if(entries.length>limit+256){entries=entries.slice(-limit);truncated=true;}}
  function decode(line){
   const p=line.split(',');let ix;
   if(p[0]==='@W'&&p.length===18)ix=14;
   else if(p[0]==='@V'&&(p.length===15||p.length===16))ix=11;
   if(ix!==undefined&&/^[0-9A-F]{8}$/.test(p[ix])){
    const q=parseInt(p[ix],16)|0;velocityFrames++;
    lastVelocity={hostTimeMs:now(),rawFrame:line,actualHex:p[ix],actualQ16:q,actualCountsPerSecond:q/65536,actualDegreesPerSecond:q/65536*360/cpr,state:parseInt(p[3],16),outer:parseInt(p[4],16)};
   }
   if(p[0]==='T'&&p.length>=9&&/^[+-]\d+$/.test(p[5]))lastPosition={hostTimeMs:now(),counts:Number(p[5]),source:'T'};
   else if(p[0]==='@T'&&p.length===16&&/^[0-9A-F]{8}$/.test(p[9]))lastPosition={hostTimeMs:now(),counts:parseInt(p[9],16)|0,source:'@T'};
  }
  return {
   connected(metadata={}){session++;pending='';velocityFrames=0;lastVelocity=null;lastPosition=null;add('CONNECT','',metadata);},
   disconnected(){add('DISCONNECT','');pending='';},
   tx(text){add('TX',text);},
   txError(text,error){add('TX_ERROR',text,{error:String(error)});},
   rx(text){pending+=text;let i;while((i=pending.indexOf('\n'))>=0){const line=pending.slice(0,i).replace(/\r$/,'');pending=pending.slice(i+1);if(line){add('RX',line);decode(line);}}if(pending.length>4096){add('RX_PARTIAL',pending);pending='';}},
   snapshot(){return {session,totalEntries:total,retainedEntries:Math.min(entries.length,limit),truncated:truncated||entries.length>limit,velocityFrames,lastVelocity:lastVelocity?{...lastVelocity}:null,lastPosition:lastPosition?{...lastPosition}:null};},
   json(metadata={}){return JSON.stringify({format:'furuta-serial-diagnostic-v1',webBuild:'velocity-zero-diag-20261031',metadata,summary:this.snapshot(),pendingRx:pending,entries:entries.slice(-limit)},null,2);}
  };
 }
 const api={create};root.SerialDiagnostics=api;if(typeof module==='object')module.exports=api;
})(typeof globalThis!=='undefined'?globalThis:this);
