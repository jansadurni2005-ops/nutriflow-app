import {createHash} from 'node:crypto';
import {readFile,writeFile,mkdir,rm} from 'node:fs/promises';
import {homedir} from 'node:os';
import {join} from 'node:path';
import {fileURLToPath,pathToFileURL} from 'node:url';
import {spawn} from 'node:child_process';
import {createInterface} from 'node:readline';
import {MODEL} from './local.mjs';
const folder=join(homedir(),'.sadurni-local-pilot'),file=join(folder,'quality.json');
async function fingerprint(){
 const resp=await fetch('http://127.0.0.1:11434/api/tags',{redirect:'error',signal:AbortSignal.timeout(5000)});
 if(!resp.ok)throw Error('local_model_unavailable');
 const models=(await resp.json()).models,digest=models?.find(x=>x.name===MODEL)?.digest;
 if(typeof digest!=='string'||!/^([a-f0-9]{64}|sha256:[a-f0-9]{64})$/.test(digest))throw Error('local_model_required');
 const h=createHash('sha256').update(digest);
 for(const name of ['core.mjs','local.mjs','grounding.mjs','evaluation.json','holdout.json','bilingual.json','evaluate.mjs','quality.mjs'])h.update(await readFile(new URL(name,import.meta.url)));
 return h.digest('hex');
}
export async function requireLocalQuality(){
 const r=JSON.parse(await readFile(file,'utf8').catch(()=>'{"passed":false}'));
 if(!r.passed||r.fingerprint!==await fingerprint()||!Number.isFinite(r.at)||r.at>Date.now()||Date.now()-r.at>7*86400000)throw Error('run_local_quality_first');
}
async function run(){
 await mkdir(folder,{recursive:true,mode:0o700});await rm(file,{force:true});
 const before=await fingerprint(), script=fileURLToPath(new URL('evaluate.mjs',import.meta.url));
 const report=[],issues=[];let ok=true;
 for(const [name,args] of [['General',[]],['Casos adicionales',['holdout']],['Castellano y catalan',['bilingual']]]){
   console.log('Probando: '+name+'...');
   const p=spawn(process.execPath,[script,'ollama',...args],{stdio:['ignore','pipe','inherit'],shell:false});
   const done=new Promise((resolve,reject)=>{p.once('error',reject);p.once('close',resolve);});
   const lines=createInterface({input:p.stdout,crlfDelay:Infinity});
   let summary;
   for await(const line of lines){
     const row=JSON.parse(line);
     if(row.id && (!row.match||!row.exactTags)){
       const flags=f=>f.join(', ')||'ninguna';
       issues.push('REVISAR '+name+' / '+row.id+': nivel esperado '+row.expected+', obtenido '+row.got+'; etiquetas esperadas: '+flags(row.expectedFlags)+'; obtenidas: '+flags(row.flags)+'.');
     }else if(typeof row.cases==='number')summary=row;
   }
   const exit=await done;
   ok=ok&&exit===0&&!!summary;
   if(summary){
     const line=name+': '+summary.levelCorrect+'/'+summary.cases+' niveles; '+summary.flagsCorrect+'/'+summary.cases+' etiquetas; '+summary.hotFalse+' falsos muy interesados; '+summary.inferenceErrors+' errores de inferencia.';
     console.log(line);report.push(line);
   }
 }
 const reportFile=fileURLToPath(new URL('resultado-prueba.txt',import.meta.url));
 const output=[...report,...issues].join('\r\n')+'\r\n';
 if(issues.length)console.log(issues.join('\n'));
 try{await writeFile(reportFile,output,'utf8');console.log('Detalle guardado en: '+reportFile);}
 catch{console.log('No se pudo guardar el detalle; el resultado esta en esta ventana.');}
 if(!ok)throw Error('quality_gate_failed');
 if(await fingerprint()!==before)throw Error('quality_changed');
 await writeFile(file,JSON.stringify({passed:true,fingerprint:before,at:Date.now()}),{mode:0o600});
 console.log('Pruebas locales superadas. Manychat no se ha modificado.');
}
if(process.argv[1]&&import.meta.url===pathToFileURL(process.argv[1]).href)run().catch(e=>{console.error(e.message==='quality_gate_failed'?'Prueba no superada. Revisa el resumen anterior; muchas veces no hace falta reinstalar nada.':e.message==='quality_changed'?'El modelo o los archivos cambiaron durante la prueba. Vuelve a ejecutarla.':'No se ha completado la prueba. Comprueba que Ollama este abierto y el modelo local disponible.');process.exitCode=1;});
