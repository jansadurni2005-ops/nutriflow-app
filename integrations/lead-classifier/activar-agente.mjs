import {copyFile,mkdir,readFile,writeFile,rm} from 'node:fs/promises';
import {join,resolve,dirname} from 'node:path';
import {fileURLToPath,pathToFileURL} from 'node:url';
import {randomBytes} from 'node:crypto';
import {spawnSync} from 'node:child_process';
import {createServer} from 'node:net';
export const files=['activar-agente.mjs','agente-crm.mjs','core.mjs','local.mjs','grounding.mjs','quality.mjs','evaluate.mjs','evaluation.json','holdout.json','bilingual.json','Desactivar-en-Windows.cmd'];
if(process.argv[1]&&import.meta.url===pathToFileURL(process.argv[1]).href){
 if(process.platform!=='win32')throw Error('Este asistente requiere Windows.');
 const dir=join(process.env.LOCALAPPDATA,'SadurniInstagram'),src=dirname(fileURLToPath(import.meta.url)),mode=process.argv[2];
 function ps(cmd,input=''){const r=spawnSync('powershell.exe',['-NoProfile','-NonInteractive','-Command',cmd],{input,encoding:'utf8',windowsHide:true});if(r.status!==0)throw Error('No se pudo acceder al almacenamiento protegido de Windows.');return r.stdout.trim();}
 const startup=ps("[Environment]::GetFolderPath('Startup')");if(!startup)throw Error('No se encuentra la carpeta de inicio.');
 const hook=join(startup,'Agente Instagram Sadurni.cmd');
 if(mode==='--off'){await rm(hook,{force:true});console.log('Inicio automatico desactivado. Cierra la ventana del agente para detenerlo ahora.');process.exit(0);}
 await mkdir(dir,{recursive:true});
 if(mode!=='--inicio'){
   for(const f of files)if(resolve(src,f)!==resolve(dir,f))await copyFile(join(src,f),join(dir,f));
   await writeFile(hook,'@echo off\r\n"'+process.execPath.replace(/%/g,'%%')+'" "%LOCALAPPDATA%\\SadurniInstagram\\activar-agente.mjs" --inicio\r\n','utf8');
 }
 const lock=createServer(s=>s.destroy());let conflict=false;
 await new Promise((done,reject)=>{lock.once('error',e=>{if(e.code==='EADDRINUSE'){conflict=true;done();}else reject(e);});lock.listen(19762,'127.0.0.1',done);});
 if(conflict){console.log('Ya hay una instancia del agente abierta o su puerto local está en uso.');process.exit(0);}
 const dpapi="Add-Type -AssemblyName System.Security; $s=[Security.Cryptography.DataProtectionScope]::CurrentUser; $v=[Console]::In.ReadToEnd().Trim(); ";
 const path=join(dir,'dispositivo.dpapi');let enc;
 try{enc=(await readFile(path,'utf8')).trim();}catch(e){if(e.code!=='ENOENT')throw e;enc=ps(dpapi+"[Convert]::ToBase64String([Security.Cryptography.ProtectedData]::Protect([Convert]::FromBase64String($v),$null,$s))",randomBytes(32).toString('base64'));await writeFile(path,enc,{flag:'wx'});}
 const value=ps(dpapi+"[Convert]::ToBase64String([Security.Cryptography.ProtectedData]::Unprotect([Convert]::FromBase64String($v),$null,$s))",enc);
 const key=Buffer.from(value,'base64');if(key.length!==32)throw Error('Vinculación de equipo inválida.');
 process.env.NF_IG_DEVICE=key.toString('hex');key.fill(0);
 console.log('Agente IG del CRM. Se inicia al entrar en tu Windows. Cierra esta ventana para pausarlo. Desactivar-en-Windows.cmd quita el inicio automatico.');
 await import(pathToFileURL(join(dir,'agente-crm.mjs')).href);
}
