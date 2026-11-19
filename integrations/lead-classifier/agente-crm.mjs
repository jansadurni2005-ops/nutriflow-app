// Live classifier on Jan's PC. No contact sends/reads; no transcript on disk.
import {createHash} from 'node:crypto';
import {execFile,spawn} from 'node:child_process';
import {fileURLToPath} from 'node:url';
import {setTimeout as pause} from 'node:timers/promises';
import {classify} from './core.mjs';
import {localInference} from './local.mjs';
import {requireLocalQuality} from './quality.mjs';
const url='https://nrxltxmbpkplhgycodob.supabase.co/functions/v1/ig-crm-sync';
const page='https://jansadurni2005-ops.github.io/nutriflow-app/instagram-conexion.html';
const key=process.env.NF_IG_DEVICE;delete process.env.NF_IG_DEVICE;
if(!/^[a-f0-9]{64}$/.test(key||''))throw Error('Abre Activar-en-Windows.cmd.');
async function request(op,p={}){
 const r=await fetch(url,{method:'POST',headers:{'Content-Type':'application/json','x-nf-device':key},body:JSON.stringify({op,...p}),redirect:'error',signal:AbortSignal.timeout(45000)});
 const d=await r.json().catch(()=>({}));if(!r.ok)throw Error(d.error||'sin_conexion');return d;
}
const infer=localInference();let first=true,needsPair=false,lastQuality=0;
async function checkQuality(){
 if(Date.now()-lastQuality<86400000)return;
 try{await requireLocalQuality();}catch(e){
  if(e.message!=='run_local_quality_first')throw Error('no_ollama');
  console.log('Validando el modelo local automáticamente. No se consultan mensajes mientras tanto.');
  const n=await new Promise((resolve,reject)=>{const p=spawn(process.execPath,[fileURLToPath(new URL('quality.mjs',import.meta.url))],{stdio:'inherit'});p.on('error',reject);p.on('close',resolve);});if(n!==0)throw Error('modelo_no_validado');await requireLocalQuality();
 }
 lastQuality=Date.now();
}
for(;;){
 try{
  const {threads}=await request('queue');needsPair=false;
  if(first){console.log('Ordenador vinculado. El agente revisa la cola del CRM mientras Ollama esté abierto.');first=false;}
  if(threads.length){await checkQuality();}
  for(const t of threads){
   const s=await request('thread',{tid:t.thread_id});if(s.already)continue;
   const rows=s.rows||[],lastAthlete=rows.findLastIndex(r=>r.role==='athlete'),messages=rows.slice(0,lastAthlete+1).map((v,i)=>({id:'m'+i,at:v.at,role:v.role,text:v.text}));
   const workable=s.complete&&messages.length&&messages.at(-1).role==='athlete'&&messages.every(m=>m.text.length<=4000)&&messages.reduce((n,m)=>n+m.text.length,0)<=24000;
   let localError=false;
   const out=workable?await classify({messages,history_complete:true},{processingApproved:true,infer:async q=>{try{return await infer(q)}catch(e){if(e.message!=='context_exceeds_pilot')localError=true;throw e;}}}):{interest_level:'unknown',additional_tags:[],evidence_ids:[],needs_human_review:true};
   if(localError)throw Error('no_ollama');
   out.evidence_ids=out.evidence_ids.map(mid=>rows[Number(mid.slice(1))].id);
   await request('score',{tid:t.thread_id,rev:s.rev,result:{interest_level:out.interest_level,additional_tags:out.additional_tags,evidence_ids:out.evidence_ids,needs_human_review:out.needs_human_review}});
  }
  await pause(threads.length>=8?5000:120000);
 }catch(e){
  if(e.message==='device_not_linked'){
   if(!needsPair){const digest=createHash('sha256').update(key).digest('hex');const link=page+'#equipo='+digest;
    console.log('En la página del CRM, compara este código y pulsa Vincular: '+digest.slice(0,8).toUpperCase());console.log(link);
    if(process.platform==='win32')execFile('explorer.exe',[link],()=>{});needsPair=true;}
   await pause(12000);
  }else{console.log(e.message==='no_ollama'?'Ollama no está disponible. Se reintentará.':e.message==='modelo_no_validado'?'El modelo no ha pasado el control; se ha pausado la clasificación.':'No se pudo completar la actualización. Se reintentará.');await pause(e.message==='modelo_no_validado'?1800000:60000);}
 }
}
