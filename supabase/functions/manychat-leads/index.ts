// Dedicated ingestion key grants only this tenant-scoped contact operation.
const OWNER = 'f209b91f-607b-4b14-9305-6a7d567b90b5';
const ACCOUNT = '2379170';
const KEY_HASH = 'fc84457e499439611b39a820d40bd7d4a644a2aed69e48f4380279a600b9899c';
const reply = (data: unknown, status = 200) => new Response(JSON.stringify(data), {status, headers: {'Content-Type':'application/json','Cache-Control':'no-store'}});
Deno.serve(async (req: Request) => {
  if (req.method !== 'POST') return reply({error:'method_not_allowed'},405);
  const key = req.headers.get('x-nutriflow-key') || '';
  if (key.length !== 64) return reply({error:'unauthorized'},401);
  const hash = Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256',new TextEncoder().encode(key))),b=>b.toString(16).padStart(2,'0')).join('');
  let diff=0; for(let i=0;i<64;i++) diff |= hash.charCodeAt(i)^KEY_HASH.charCodeAt(i);
  if(diff) return reply({error:'unauthorized'},401);
  if(Number(req.headers.get('content-length')||0)>8192) return reply({error:'payload_too_large'},413);
  try {
    const raw=await req.text(); if(raw.length>8192) return reply({error:'payload_too_large'},413);
    const b=JSON.parse(raw);
    const id=String(b.contact_id||'');
    if(!/^\d{1,40}$/.test(id)||typeof b.name!=='string'||b.name.length>200||typeof b.username!=='string'||b.username.length>64||!['mc_dm','mc_keyword','mc_unknown'].includes(b.kind)) return reply({error:'invalid_contact'},400);
    const url=Deno.env.get('SUPABASE_URL')!;
    const service=Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
    const result=await fetch(url+'/rest/v1/rpc/nf_ingest_manychat',{method:'POST',headers:{apikey:service,Authorization:'Bearer '+service,'Content-Type':'application/json'},body:JSON.stringify({p_user:OWNER,p_account:ACCOUNT,p_contact:id,p_username:b.username,p_name:b.name,p_kind:b.kind,p_dry_run:b.dry_run===true})});
    if(!result.ok){console.error('Ingestion failed',result.status);return reply({error:'ingestion_failed'},500);}
    return reply(await result.json());
  } catch { return reply({error:'invalid_request'},400); }
});
