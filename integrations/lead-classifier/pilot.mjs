// Single test contact. No credential, name, transcript or provider response in logs.
import {createHash} from 'node:crypto';
import {pathToFileURL} from 'node:url';
import {FIELD_TYPES,fieldUpdate,classify} from './core.mjs';
import {localInference} from './local.mjs';
const MC='https://api.manychat.com', IG='https://graph.instagram.com/v27.0', OWN='17841449201493232';
export async function pilot(mode,config,{http=fetch,infer=localInference()}={}) {
 if(!['inspect','fields','preview','stamp'].includes(mode))throw Error('unknown_mode');
 const {mc,ig,contact,peer,confirmed,audited}=config;
 if(!mc || !ig || !/^\d{1,20}$/.test(peer)||peer===OWN||!Number.isSafeInteger(contact)||contact<=0)throw Error('test_credentials_and_ids_required');
 async function call(base,path,body){
   const r=await http(base+path,{method:body?'POST':'GET',headers:{Authorization:'Bearer '+(base===MC?mc:ig),...(body?{'Content-Type':'application/json'}:{})},...(body?{body:JSON.stringify(body)}:{}),redirect:'error',signal:AbortSignal.timeout(20000)});
   if(!r.ok)throw Error((base===MC?'manychat':'instagram')+'_http_'+r.status);
   const j=await r.json();
   if(base===MC && j.status!=='success')throw Error('manychat_refused');
   return base===MC?j.data:j;
 }
 const getPerson=()=>call(MC,'/fb/subscriber/getInfo?subscriber_id='+contact);
 function verify(person){
   if(String(person?.id)!==String(contact)||typeof person.ig_id!=='string'||person.ig_id!==peer)throw Error('identity_not_verified');
 }
 const person=await getPerson();verify(person);
 const profile=await call(IG,'/me?fields=user_id,username');
 if(String(profile.user_id)!==OWN)throw Error('wrong_ig_account');
 if(mode==='fields'){
   if(!confirmed)throw Error('confirm_create_new_fields');
   const existing=await call(MC,'/fb/page/getCustomFields');
   if(!Array.isArray(existing))throw Error('field_inventory_unavailable');
   for(const [name,type] of Object.entries(FIELD_TYPES)){
     const matches=existing.filter(f=>f.name===name);
     if(matches.length>1||matches.some(f=>f.type!==type))throw Error('field_collision');
   }
   let created=0;
   for(const [name,type] of Object.entries(FIELD_TYPES))if(!existing.some(f=>f.name===name)){
     await call(MC,'/fb/page/createCustomField',{caption:name,type,description:'Clasificador comercial local; sin acciones de envío.'});
     await new Promise(r=>setTimeout(r,1050));created++;
   }
   return {created};
 }
 async function snapshot(){
   const l=await call(IG,'/'+OWN+'/conversations?platform=instagram&user_id='+peer+'&fields=id&limit=2');
   if(l.data?.length!==1||typeof l.data[0].id!=='string'||!l.data[0].id.length)throw Error('unique_thread_required');
   const j=await call(IG,'/'+encodeURIComponent(l.data[0].id)+'?fields='+encodeURIComponent('participants,messages.limit(20){id,created_time,from,to,message,attachments,shares}'));
   const ids=j.participants?.data?.map(x=>String(x.id));
   if(ids?.length!==2||!ids.includes(OWN)||!ids.includes(peer))throw Error('wrong_thread');
   const rows=j.messages?.data;
   if(!Array.isArray(rows)||!rows.length||rows.length>=20||j.messages?.paging?.next)throw Error('partial_history_review');
   const seen=new Set();
   const messages=rows.map(m=>{
     const sender=String(m.from?.id),dest=m.to?.data,at=Date.parse(m.created_time);
     if(!ids.includes(sender)||dest?.length!==1||String(dest[0].id)!==(sender===OWN?peer:OWN)||!Number.isFinite(at)||!m.message?.trim()||m.attachments?.data?.length||m.shares?.data?.length||!m.id||seen.has(m.id))throw Error('unsupported_context');
     seen.add(m.id);return {id:m.id,at:new Date(at).toISOString(),role:sender===OWN?'jan':'athlete',text:m.message};
   }).reverse().sort((a,b)=>a.at.localeCompare(b.at));
   if(messages.at(-1).role!=='athlete')throw Error('waiting_for_athlete');
   const revision=createHash('sha256').update(JSON.stringify(messages)).digest('hex');
   return {revision,messages};
 }
 const snap=await snapshot();
 if(mode==='inspect')return {identity:true,recentTypedMessages:snap.messages.length,unread:'not_available_via_api'};
 if(mode==='stamp'&&(!confirmed||!audited))throw Error('test_only_confirmation_required');
 const result=await classify({history_complete:true,messages:snap.messages},{infer,processingApproved:true});
 if(mode==='preview')return {mode,interest:result.interest_level,flags:result.additional_tags,reason:result.reason_code,review:result.needs_human_review,revision:snap.revision};
 // Controlled experiment BEFORE unread proof. Only the designated tester can receive metadata.
 // No bulk/live worker. Re-check exact identity, revision, opt-out and current-client before writing.
 if(result.needs_human_review)throw Error('review_no_write');
 if(config.revision!==snap.revision)throw Error('not_the_previewed_revision');
 const existing=await call(MC,'/fb/page/getCustomFields');
 if(!Array.isArray(existing)||Object.entries(FIELD_TYPES).some(([k,t])=>existing.filter(f=>f.name===k&&f.type===t).length!==1))throw Error('prepare_fields_first');
 const latest=await getPerson();verify(latest);
 const fields=latest.custom_fields;
 if(!Array.isArray(fields))throw Error('contact_fields_missing');
 const on=v=>v===true||v===1||['true','1','yes'].includes(String(v).toLowerCase());
 for(const flag of ['do_not_contact','current_client'])if(fields.some(f=>f.name==='SN '+flag&&on(f.value)))throw Error('protected_contact');
 if((await snapshot()).revision!==snap.revision)throw Error('newer_turn_preview_again');
 const payload=fieldUpdate(contact,result);
 await call(MC,'/fb/subscriber/setCustomFields',payload);
 const reread=await getPerson();verify(reread);
 if(reread.custom_fields?.find(f=>f.name==='SN Interés')?.value!==result.interest_level)throw Error('field_readback_failed');
 return {mode,stored:result.interest_level,unread:'manual_check_required',outgoing:'verify_from_test_account'};
}
// Short bounded rehearsal only: no tenant-wide enumeration. No transcript written to disk.
export async function watchTester(config,{readbackVerified=false,run=pilot,pause=ms=>new Promise(r=>setTimeout(r,ms)),report=()=>{}}={}){
 if(!readbackVerified || !config.confirmed || !config.audited || !/^[a-f0-9]{64}$/.test(config.revision||''))throw Error('unread_test_required');
 let previous=config.revision;
 for(let i=0;i<10;i++){
   await pause(60000);
   let preview;
   try{preview=await run('preview',config);}catch(e){if(e.message==='waiting_for_athlete')continue;throw e;}
   if(preview.revision===previous)continue;
   if(preview.review){report({mode:'review'});continue;}
   const update=await run('stamp',{...config,revision:preview.revision});
   previous=preview.revision;report(update);
 }
 return {mode:'tester_window_ended'};
}
if(process.argv[1]&&import.meta.url===pathToFileURL(process.argv[1]).href){
 const env=process.env, mode=process.argv[2];
 const config={mc:env.SN_MC_TOKEN,ig:env.SN_IG_TOKEN,contact:Number(env.SN_TEST_MC_ID),peer:env.SN_TEST_IG_ID,confirmed:env.SN_TEST_CONFIRM==='ONE_TESTER',audited:env.SN_TEST_FIELDS_AUDITED==='YES',revision:env.SN_TEST_REVISION};
 try{if(['fields','stamp','watch-tester'].includes(mode))await (await import('./quality.mjs')).requireLocalQuality();
 const r=mode==='watch-tester'?await watchTester(config,{readbackVerified:env.SN_TEST_UNREAD_PASSED==='YES',report:v=>console.log(JSON.stringify(v))}):await pilot(mode,config);
 console.log(JSON.stringify(r));}
 catch(e){console.error(/^[a-z][a-z_0-9]*$/.test(e.message)?e.message:'pilot_blocked');process.exitCode=1;}
}
