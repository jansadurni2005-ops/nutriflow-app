export const ACCOUNT='17841449201493232', OWNER='f209b91f-607b-4b14-9305-6a7d567b90b5';
export async function hash(s){return Array.from(new Uint8Array(await crypto.subtle.digest('SHA-256',new TextEncoder().encode(s))),b=>b.toString(16).padStart(2,'0')).join('');}
export function threadId(x){return typeof x==='string'&&/^[A-Za-z0-9_=:+./-]{1,512}$/.test(x)&&!x.includes('..');}
export function numberId(x){return typeof x==='string'&&/^\d{1,40}$/.test(x);}
export async function snapshot(data,fromDate){
 const parts=data.participants?.data;if(!threadId(data.id)||!Array.isArray(parts)||parts.length!==2||!parts.some(p=>p.id===ACCOUNT))throw Error('unsupported_thread');
 const other=parts.find(p=>p.id!==ACCOUNT);if(!numberId(other?.id))throw Error('unsupported_thread');
 const raw=data.messages?.data;if(!Array.isArray(raw)||!raw.length)throw Error('empty_thread');
 const ids=new Set(),rows=[];
 for(const m of raw){
   const from=m.from?.id,to=m.to?.data,at=Date.parse(m.created_time);const out=from===ACCOUNT;
   if(typeof m.id!=='string'||!m.id.length||m.id.length>300||ids.has(m.id)||(!out&&from!==other.id)||!Array.isArray(to)||to.length!==1||to[0]?.id!==(out?other.id:ACCOUNT)||!Number.isFinite(at))throw Error('unsupported_thread');
   ids.add(m.id);
   // Only a provider tag, never message text, echo status, or a missing app ID. When
   // the provider omits provenance the owner can confirm the selected messages.
   const human=out&&Array.isArray(m.tags?.data)&&m.tags.data.some(t=>t?.name==='HUMAN_AGENT');
   rows.push({id:m.id,at:new Date(at).toISOString(),role:out?'jan':'athlete',outgoing:out,human,text:typeof m.message==='string'?m.message:'',media:!!(m.attachments?.data?.length||m.shares?.data?.length||m.is_unsupported)});
 }
 rows.sort((a,b)=>a.at.localeCompare(b.at)||a.id.localeCompare(b.id));
 const handle=typeof other.username==='string'&&/^[A-Za-z0-9_.]{1,64}$/.test(other.username)?other.username.toLowerCase():'';
 const rev=await hash(JSON.stringify(rows.map(m=>[m.id,m.at,m.role,m.human,m.text,m.media])));
 return {tid:data.id,peer:other.id,handle,rev,latest:rows.at(-1).at,eligible:rows.filter(x=>Date.parse(x.at)>=Date.parse(fromDate)),rows,complete:!data.messages.paging?.next&&rows.length<20&&rows.every(x=>!x.media&&x.text.trim())};
}
export function graphClient(token,fetcher=fetch){
 const root='https://graph.instagram.com/v27.0/';
 async function get(path,params){
  const u=new URL(root+path);for(const [k,v] of Object.entries(params))if(v)u.searchParams.set(k,v);
  const r=await fetcher(u,{headers:{Authorization:'Bearer '+token},redirect:'error',signal:AbortSignal.timeout(10000)});
  const j=await r.json().catch(()=>({}));if(!r.ok)throw Object.assign(Error('meta_'+(Number(j.error?.code)||r.status)),{status:r.status,code:Number(j.error?.code)});return j;
 }
 return {
  list:(after)=>get(ACCOUNT+'/conversations',{platform:'instagram',fields:'id,updated_time',limit:'12',after}),
  async thread(tid){if(!threadId(tid))throw Error('invalid_thread');
   const msg='id,created_time,from,to,message,attachments,shares';
   try{return await get(encodeURIComponent(tid),{fields:'id,participants,messages.limit(20){'+msg+',tags}'});}
   catch(e){if(e.code!==100)throw e;return get(encodeURIComponent(tid),{fields:'id,participants,messages.limit(20){'+msg+'}'});}
  }
 };
}
