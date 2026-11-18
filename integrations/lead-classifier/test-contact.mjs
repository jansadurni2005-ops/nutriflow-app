// Resolve only a numeric contact deliberately chosen by the operator; never search all contacts.
const {SN_MC_TOKEN:token,SN_TEST_MC_ID:id,SN_TEST_HANDLE:handle}=process.env;
try{
 if(!token||!/^\d+$/.test(id)||!Number.isSafeInteger(Number(id))||!/^@?[A-Za-z0-9._]{1,30}$/.test(handle))throw Error();
 const r=await fetch('https://api.manychat.com/fb/subscriber/getInfo?subscriber_id='+id,{headers:{Authorization:'Bearer '+token},redirect:'error',signal:AbortSignal.timeout(10000)});
 if(!r.ok)throw Error();
 const j=await r.json(),p=j?.data;
 if(j.status!=='success'||String(p.id)!==id||p.ig_username?.toLowerCase()!==handle.replace(/^@/,'').toLowerCase()||typeof p.ig_id!=='string'||!/^\d{1,20}$/.test(p.ig_id))throw Error();
 process.stdout.write(p.ig_id);
}catch{console.error('No se pudo verificar la identidad de la cuenta de prueba.');process.exitCode=1;}
