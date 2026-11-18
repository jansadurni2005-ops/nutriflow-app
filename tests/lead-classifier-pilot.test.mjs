import test from 'node:test';
import assert from 'node:assert/strict';
import {pilot} from '../integrations/lead-classifier/pilot.mjs';
import {localInference} from '../integrations/lead-classifier/local.mjs';
import {FIELD_TYPES} from '../integrations/lead-classifier/core.mjs';
const own='17841449201493232',peer='12345',contact=2222;
const cfg={mc:'dummy',ig:'dummy',contact,peer,confirmed:true,audited:true};
const result={interest_level:'hot',additional_tags:['call_accepted'],confidence:.9,evidence_ids:['m2'],reason_code:'call_accepted',needs_human_review:false};
function setup(opts={}){
 let reads=0, written;
 const requests=[];
 const http=async(raw,req)=>{
  const u=new URL(raw),p=u.pathname; requests.push([req.method,p]);
  assert.equal(req.redirect,'error');
  let j;
  if(p.endsWith('getInfo')) j={status:'success',data:{id:contact,ig_id:opts.other||peer,custom_fields:written||opts.prior||[]}};
  else if(p.endsWith('/me'))j={user_id:own};
  else if(p.endsWith('/conversations')){assert.equal(u.searchParams.get('user_id'),peer);j={data:[{id:'thread'}]};}
  else if(p.endsWith('/thread')){
   reads++;
   j={participants:{data:[{id:own},{id:peer}]},messages:{data:[{id:'m2',created_time:'2026-11-17T10:00:15Z',message:opts.changed&&reads>1?'nuevo':'sí',from:{id:peer},to:{data:[{id:own}]}},{id:'m1',created_time:'2026-11-17T10:00:01Z',message:'¿Hablamos por teléfono?',from:{id:own},to:{data:[{id:peer}]}}],...(opts.paged?{paging:{next:'do_not_follow'}}:{})}};
  }else if(p.endsWith('getCustomFields'))j={status:'success',data:Object.entries(FIELD_TYPES).map(([name,type])=>({name,type}))};
  else if(p.endsWith('setCustomFields')){written=JSON.parse(req.body).fields.map(({field_name:name,field_value:value})=>({name,value}));j={status:'success'};}
  else throw Error('unexpected_endpoint');
  return {ok:true,json:async()=>j};
 };
 return {http,requests,infer:async()=>result};
}
test('preview fetches only one verified contact and does not write',async()=>{const f=setup();assert.equal((await pilot('preview',cfg,f)).interest,'hot');assert.ok(f.requests.every(x=>x[0]==='GET'));});
test('identity mismatch and incomplete history block before inference',async()=>{for(const opts of [{other:'234'},{paged:true}]){const f=setup(opts);f.infer=()=>assert.fail();await assert.rejects(pilot('preview',cfg,f));assert.ok(f.requests.every(x=>x[0]==='GET'));}});
test('controlled test stamps metadata only and checks read-back; never claims unread',async()=>{const f=setup(),{revision}=await pilot('preview',cfg,f);const r=await pilot('stamp',{...cfg,revision},f);assert.equal(r.unread,'manual_check_required');assert.deepEqual(f.requests.filter(x=>x[0]!=='GET'),[['POST','/fb/subscriber/setCustomFields']]);});
test('new turns, no consent, prior opt-out or client never write',async()=>{const {revision}=await pilot('preview',cfg,setup());for(const [c,opts] of [[{confirmed:false},{}],[{audited:false},{}],[{}, {changed:true}],[{},{prior:[{name:'SN do_not_contact',value:true}]}],[{},{prior:[{name:'SN current_client',value:'1'}]}]]){const f=setup(opts);await assert.rejects(pilot('stamp',{...cfg,revision,...c},f));assert.ok(f.requests.every(x=>x[0]==='GET'));}});
test('no processing against a cloud endpoint, platform IDs are not sent to inference',async()=>{assert.throws(()=>localInference('https://example.org'));let url,data;const infer=localInference('ollama',async(u,o)=>{url=u;data=JSON.parse(o.body);return {ok:true,json:async()=>({message:{content:JSON.stringify({meaning:'resource_only',nutritionist:false,budget:false,already_client:false,opt_out:false,evidence:'t0',certainty:'clear'})}})};});const r=await infer({messages:[{id:'real-platform-id',role:'athlete',text:'La guía, gracias'}]});assert.equal(url,'http://127.0.0.1:11434/api/chat');assert.equal(JSON.stringify(data).includes('real-platform-id'),false);assert.deepEqual(r.evidence_ids,['real-platform-id']);});
import {watchTester} from '../integrations/lead-classifier/pilot.mjs';
test('ten minute tester pilot ignores unchanged revisions, unknown classifications and absent replies',async()=>{
 const initial='a'.repeat(64),next='b'.repeat(64),updates=[];let reads=0;
 const opts={readbackVerified:true,pause:async()=>{},run:async(mode,c)=>{
  if(mode==='stamp'){updates.push(c.revision);return {stored:'hot'};}
  reads++;if(reads===1)throw Error('waiting_for_athlete');
  if(reads===2)return {revision:initial,review:false};
  return {revision:next,review:reads===3};
 }};
 await assert.rejects(watchTester({...cfg,revision:initial},{...opts,readbackVerified:false}),/unread_test_required/);
 await watchTester({...cfg,revision:initial},opts);assert.equal(reads,10);assert.deepEqual(updates,[next]);
});
