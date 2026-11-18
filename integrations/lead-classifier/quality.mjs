import {createHash} from 'node:crypto';
import {readFile,writeFile,mkdir,rm} from 'node:fs/promises';
import {homedir} from 'node:os';
import {join} from 'node:path';
import {fileURLToPath,pathToFileURL} from 'node:url';
import {spawn} from 'node:child_process';
import {MODEL} from './local.mjs';
const folder=join(homedir(),'.sadurni-local-pilot'),file=join(folder,'quality.json');
async function fingerprint(){
 const resp=await fetch('http://127.0.0.1:11434/api/tags',{redirect:'error',signal:AbortSignal.timeout(5000)});
 if(!resp.ok)throw Error('local_model_unavailable');
 const models=(await resp.json()).models,digest=models?.find(x=>x.name===MODEL)?.digest;
 if(typeof digest!=='string'||!/^([a-f0-9]{64}|sha256:[a-f0-9]{64})$/.test(digest))throw Error('local_model_required');
 const h=createHash('sha256').update(digest);
 for(const name of ['core.mjs','local.mjs','evaluation.json','holdout.json','bilingual.json','evaluate.mjs','quality.mjs'])h.update(await readFile(new URL(name,import.meta.url)));
 return h.digest('hex');
}
export async function requireLocalQuality(){
 const r=JSON.parse(await readFile(file,'utf8').catch(()=>'{"passed":false}'));
 if(!r.passed||r.fingerprint!==await fingerprint()||!Number.isFinite(r.at)||r.at>Date.now()||Date.now()-r.at>7*86400000)throw Error('run_local_quality_first');
}
async function run(){
 await mkdir(folder,{recursive:true,mode:0o700});await rm(file,{force:true});
 const before=await fingerprint(), script=fileURLToPath(new URL('evaluate.mjs',import.meta.url));
 let ok=true;
 for(const args of [[],['holdout'],['bilingual']]){
   const exit=await new Promise((resolve,reject)=>{const p=spawn(process.execPath,[script,'ollama',...args],{stdio:'inherit',shell:false});p.once('error',reject);p.once('exit',resolve);});
   ok=ok&&exit===0;
 }
 if(!ok||await fingerprint()!==before)throw Error('quality_gate_failed');
 await writeFile(file,JSON.stringify({passed:true,fingerprint:before,at:Date.now()}),{mode:0o600});
 console.log('Pruebas locales superadas. Manychat no se ha modificado.');
}
if(process.argv[1]&&import.meta.url===pathToFileURL(process.argv[1]).href)run().catch(()=>{console.error('Prueba no superada. Verifica Ollama y revisa los resultados.');process.exitCode=1;});
