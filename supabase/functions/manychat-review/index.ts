const origin='https://jansadurni2005-ops.github.io';
const headers={'Content-Type':'application/json','Cache-Control':'no-store','Access-Control-Allow-Origin':origin,'Access-Control-Allow-Headers':'authorization,content-type','Access-Control-Allow-Methods':'GET,POST,OPTIONS'};
const reply=(data:unknown,status=200)=>new Response(JSON.stringify(data),{status,headers});
Deno.serve(async(req:Request)=>{
 if(req.method==='OPTIONS')return new Response(null,{status:204,headers});
 if(!['GET','POST'].includes(req.method))return reply({error:'method_not_allowed'},405);
 const url=Deno.env.get('SUPABASE_URL')!,key=Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,auth=req.headers.get('authorization')||'';
 if(!auth.startsWith('Bearer '))return reply({error:'unauthorized'},401);
 try{
  const userResp=await fetch(url+'/auth/v1/user',{headers:{apikey:key,Authorization:auth}});
  if(!userResp.ok)return reply({error:'unauthorized'},401);
  const user=await userResp.json();
  const h={apikey:key,Authorization:'Bearer '+key,'Content-Type':'application/json'};
  if(req.method==='GET'){
   const r=await fetch(url+'/rest/v1/nf_manychat_links?user_id=eq.'+encodeURIComponent(user.id)+'&state=eq.review&select=account_id,contact_id,username,contact_name,acquisition_type,candidate_ids&order=first_seen.asc&limit=100',{headers:h});
   if(!r.ok)return reply({error:'read_failed'},500);return reply({pending:await r.json()});
  }
  const raw=await req.text();if(raw.length>2048)return reply({error:'too_large'},413);
  const b=JSON.parse(raw);
  if(!/^\d{1,30}$/.test(b.account_id)||!/^\d{1,40}$/.test(b.contact_id)||(b.lead_id!==null&&typeof b.lead_id!=='string'))return reply({error:'invalid_request'},400);
  const r=await fetch(url+'/rest/v1/rpc/nf_resolve_manychat',{method:'POST',headers:h,body:JSON.stringify({p_user:user.id,p_account:b.account_id,p_contact:b.contact_id,p_lead:b.lead_id})});
  if(!r.ok)return reply({error:'resolution_failed'},409);return reply(await r.json());
 }catch{return reply({error:'request_failed'},500);}
});
