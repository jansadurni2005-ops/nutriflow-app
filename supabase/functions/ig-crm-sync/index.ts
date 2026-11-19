import {createClient} from 'jsr:@supabase/supabase-js@2.49.4';
import {ACCOUNT,OWNER,graphClient,hash,snapshot,threadId} from './graph.mjs';
const base=Deno.env.get('SUPABASE_URL')!, key=Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
const db=createClient(base,key,{auth:{autoRefreshToken:false,persistSession:false}}),origin='https://jansadurni2005-ops.github.io';
const cors={'Access-Control-Allow-Origin':origin,'Access-Control-Allow-Headers':'content-type,authorization,apikey,x-nf-device','Access-Control-Allow-Methods':'POST,OPTIONS','Cache-Control':'no-store','Referrer-Policy':'no-referrer','Content-Type':'application/json'};
const json=(x:unknown,status=200)=>new Response(JSON.stringify(x),{status,headers:cors});
async function val(q:any){const r=await q;if(r.error)throw Error('database');return r.data;}
const safe=(e:any)=>/^(meta_\d+|unsupported_thread|empty_thread|no_grant|database|stale|invalid_thread)$/.test(e?.message)?e.message:'service_unavailable';
const control=()=>db.from('nf_ig_sync_control');
async function getGrant(){const a=await val(db.from('nf_ig_dm_connection').select('access_token,connected_at,expires_at').eq('account_id',ACCOUNT).gt('expires_at',new Date().toISOString()).maybeSingle());if(!a)throw Error('no_grant');return a;}
const limited=(x:unknown,n:number)=>typeof x==='string'&&x.length>0&&x.length<=n;
async function observe(s:any){if(!s.eligible.length)return;
 await val(db.rpc('nf_ig_observe',{p_tid:s.tid,p_peer:s.peer,p_handle:s.handle,p_rev:s.rev,p_latest:s.latest,p_rows:s.eligible.map((r:any)=>({id:r.id,at:r.at,outgoing:r.outgoing,human:r.human}))}));}
async function sync(c:any){
 const start=new Date(),until=new Date(+start+180000).toISOString();
 const locked=await val(control().update({lease_until:until}).eq('id',1).lt('lease_until',start.toISOString()).select('id').maybeSingle());
 if(!locked)return json({state:'busy'});
 try{
  const a=await getGrant();
  if(Date.parse(a.expires_at)-Date.now()<7*86400000 && Date.now()-Date.parse(a.connected_at)>86400000 && (!c.refresh_attempt||Date.now()-Date.parse(c.refresh_attempt)>86400000)){
    await val(control().update({refresh_attempt:start.toISOString()}).eq('id',1));
    const u=new URL('https://graph.instagram.com/refresh_access_token');u.search=new URLSearchParams({grant_type:'ig_refresh_token',access_token:a.access_token}).toString();
    try{const rr=await fetch(u,{redirect:'error',signal:AbortSignal.timeout(8000)}),j=await rr.json();
     if(rr.ok&&typeof j.access_token==='string'&&Number(j.expires_in)>0){const saved=await val(db.from('nf_ig_dm_connection').update({access_token:j.access_token,expires_at:new Date(Date.now()+Number(j.expires_in)*1000).toISOString()}).eq('account_id',ACCOUNT).eq('connected_at',a.connected_at).select('account_id').maybeSingle());if(saved)a.access_token=j.access_token;}
    }catch{/* Keep the existing valid grant. Retry on the next day. */}
  }
  const g=graphClient(a.access_token),begin=c.since_at||a.connected_at;
  const pass=c.pass_at||start.toISOString(), cutoff=Date.parse(begin)-60000;
  const page=await g.list(c.cursor_value||null);if(!Array.isArray(page.data))throw Error('meta_502');
  let done=false,skips=0,observed=0;
  for(let i=0;i<page.data.length;i+=3){
   const batch=page.data.slice(i,i+3);
   const results=await Promise.allSettled(batch.map(async(th:any)=>{
    if(Number.isFinite(Date.parse(th.updated_time))&&Date.parse(th.updated_time)<cutoff){return 'old';}
    const s=await snapshot(await g.thread(th.id),a.connected_at);await observe(s);return s.eligible.length?'seen':'old';
   }));
   for(const x of results){if(x.status==='fulfilled'){if(x.value==='seen')observed++;}else if(['unsupported_thread','empty_thread'].includes(x.reason?.message))skips++;else throw x.reason;}
  }
  // Do not assume a mixed page is sorted: only stop early on a whole older page.
  if(page.data.length&&page.data.every((th:any)=>Number.isFinite(Date.parse(th.updated_time))&&Date.parse(th.updated_time)<cutoff))done=true;
  const after=!done&&page.paging?.next&&page.paging?.cursors?.after||null;
  if(after && (!limited(after,4096)||after===c.cursor_value))throw Error('meta_502');
  await val(control().update({cursor_value:after,pass_at:after?pass:null,since_at:after?begin:pass,last_ok:start.toISOString(),last_error:skips?'unsupported_thread':null,lease_until:start.toISOString()}).eq('id',1).eq('lease_until',until));return json({state:skips?'partial':'ok',threads:observed});
 }catch(e){const code=safe(e);await val(control().update({last_error:code,lease_until:start.toISOString()}).eq('id',1).eq('lease_until',until));return json({error:code},code==='no_grant'?409:502);}
}
Deno.serve(async req=>{
 if(req.method==='OPTIONS')return new Response(null,{status:204,headers:cors});
 if(req.method!=='POST')return json({error:'method'},405);
 if(req.headers.get('origin')&&req.headers.get('origin')!==origin)return json({error:'origin'},403);
 try{
  if(Number(req.headers.get('content-length')||0)>12000)return json({error:'size'},413);
  const b=await req.text();if(b.length>12000)return json({error:'size'},413);const p=JSON.parse(b);if(typeof p?.op!=='string')return json({error:'request'},400);
  const gate=req.headers.get('x-nf-sync'), device=req.headers.get('x-nf-device'),auth=req.headers.get('authorization');
  if(!gate&&!device&&!auth)return json({error:'unauthorized'},401);
  const c=await val(control().select('*').eq('id',1).single());
  const same=(a:string,b:string)=>{if(!a||!b||a.length!==b.length)return false;let d=0;for(let i=0;i<a.length;i++)d|=a.charCodeAt(i)^b.charCodeAt(i);return d===0;};
  if(gate){
   if(p.op!=='sync'||!/^[a-f0-9]{64}$/.test(gate)||!c.ticket_until||!same(await hash(gate),c.sync_key))return json({error:'unauthorized'},401);
   const consumed=await val(control().update({ticket_until:null}).eq('id',1).eq('sync_key',c.sync_key).gt('ticket_until',new Date().toISOString()).select('id').maybeSingle());
   if(!consumed)return json({error:'unauthorized'},401);return await sync(c);
  }
  let owner=false;
  if(device){if(!/^[0-9a-f]{64}$/.test(device)||!c.device_hash||!same(await hash(device),c.device_hash)||!['queue','thread','score'].includes(p.op))return json({error:'device_not_linked'},401);}
  else{if(!auth?.startsWith('Bearer '))return json({error:'unauthorized'},401);const {data,error}=await db.auth.getUser(auth.slice(7));owner=!error&&data.user?.id===OWNER;if(!owner)return json({error:'owner_required'},403);}
  if(p.op==='status'&&owner){const grant=await val(db.from('nf_ig_dm_connection').select('expires_at').eq('account_id',ACCOUNT).gt('expires_at',new Date().toISOString()).maybeSingle());return json({connected:!!grant,sync_at:c.last_ok,error:c.last_error,worker_seen:c.device_seen,paired:!!c.device_hash});}
  if(p.op==='pair'&&owner){if(!/^[0-9a-f]{64}$/.test(p.digest))return json({error:'invalid_device'},400);await val(control().update({device_hash:p.digest,device_seen:null}).eq('id',1));return json({paired:true});}
  if(p.op==='unpair'&&owner){await val(control().update({device_hash:null,device_seen:null}).eq('id',1));return json({paired:false});}
  if(p.op==='queue'&&device){await val(control().update({device_seen:new Date().toISOString()}).eq('id',1));const data=await val(db.from('nf_ig_sync_queue').select('thread_id,revision').order('latest_at',{ascending:false}).limit(8));return json({threads:data});}
  if(p.op==='list'&&owner){const offset=Number.isInteger(p.offset)&&p.offset>=0?Math.min(p.offset,100000):0;
   const rows=await val(db.from('nf_ig_sync_threads').select('thread_id,handle,revision,latest_at,outgoing_count,incoming_count,level,flags,review').order('latest_at',{ascending:false}).range(offset,offset+29));return json({threads:rows});}
  if(!threadId(p.tid)||!['thread','score','confirm'].includes(p.op))return json({error:'request'},400);
  const known=await val(db.from('nf_ig_sync_threads').select('thread_id,peer,revision,classified_revision').eq('thread_id',p.tid).maybeSingle());if(!known)return json({error:'thread_unknown'},404);
  const a=await getGrant(),s=await snapshot(await graphClient(a.access_token).thread(p.tid),a.connected_at);
  if(s.peer!==known.peer||s.tid!==p.tid)return json({error:'identity'},409);await observe(s);
  if(!s.eligible.length)return json({error:'scope'},409);
  if(p.op==='thread'){
    if(device&&known.classified_revision===s.rev)return json({complete:false,already:true,rev:s.rev,rows:[]});
    const manually=owner?await val(db.from('nf_ig_sync_observed').select('mid').eq('thread_id',s.tid).eq('manual',true).in('mid',s.rows.map((r:any)=>r.id))):[];
    const yes=new Set(manually.map((r:any)=>r.mid)),canSee=(r:any)=>Date.parse(r.at)>=Date.parse(a.connected_at);
    const rows=s.rows.filter(canSee).map((r:any)=>({id:r.id,at:r.at,role:r.role,text:r.text,media:r.media,manual:yes.has(r.id)}));
    return json({handle:s.handle,rev:s.rev,complete:s.complete&&rows.length===s.rows.length,rows});
  }
  if(p.rev!==s.rev)return json({error:'stale'},409);
  if(p.op==='confirm'&&owner){if(!Array.isArray(p.ids)||p.ids.length<1||p.ids.length>20||p.ids.some((id:any)=>!s.eligible.some((r:any)=>r.id===id&&r.outgoing)))return json({error:'invalid_selection'},400);
   const action=await val(db.rpc('nf_ig_confirm_outgoing',{p_tid:s.tid,p_rev:s.rev,p_ids:p.ids}));return json({action});}
  if(p.op==='score'&&device){
   const out=p.result;const levels=['unknown','neutral','cold','warm','hot'],allowed=['has_nutritionist','call_accepted','call_scheduled','current_client','do_not_contact','price_objection'];
   if(!out||!levels.includes(out.interest_level)||typeof out.needs_human_review!=='boolean'||!Array.isArray(out.additional_tags)||out.additional_tags.length>6||out.additional_tags.some((f:any)=>!allowed.includes(f))||!Array.isArray(out.evidence_ids)||out.evidence_ids.some((id:any)=>!s.eligible.some((r:any)=>!r.outgoing&&r.id===id)))return json({error:'invalid_score'},400);
   if(out.interest_level!=='unknown'&&(!s.complete||s.eligible.length!==s.rows.length||!out.evidence_ids.length))return json({error:'incomplete_context'},409);
   const saved=await val(db.rpc('nf_ig_scored',{p_tid:s.tid,p_rev:s.rev,p_level:out.interest_level,p_flags:out.additional_tags,p_review:out.needs_human_review}));return json({saved});
  }
  return json({error:'forbidden'},403);
 }catch(e){return json({error:safe(e)},e instanceof SyntaxError?400:502);}
});
