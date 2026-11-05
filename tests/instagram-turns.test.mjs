import {test} from 'node:test';
import assert from 'node:assert/strict';
import {createHandler} from '../supabase/functions/instagram-turns/handler.mjs';
const key = 'a'.repeat(64);
const env = name => ({INSTAGRAM_CONVERSATION_KEY:key,SUPABASE_URL:'https://example.test',SUPABASE_SERVICE_ROLE_KEY:'server-only'})[name];
const event = {account_id:'17841449201493232',contact_id:'123',message_id:'mid.1',sent_at:'2026-11-05T10:00:00Z',direction:'out',manual:true,username:'example'};
const request = (body=event, secret=key) => new Request('https://example.test',{method:'POST',headers:{'x-nutriflow-conversation-key':secret},body:JSON.stringify(body)});
test('fails closed until an event source has been connected',async()=>{
 assert.equal((await createHandler(()=>undefined)(request())).status,503);
});
test('rejects unauthenticated requests before processing events',async()=>{
 assert.equal((await createHandler(env)(request(event,'b'.repeat(64)))).status,401);
});
test('does not count automatic or unknown outbound messages',async()=>{
 const handler=createHandler(env,()=>{throw Error('must not call database');});
 for(const manual of [false,undefined,'true']) assert.equal((await (await handler(request({...event,manual}))).json()).action,'ignored_non_manual');
});
test('rejects other accounts and invalid metadata',async()=>{
 for(const change of [{account_id:'999'},{contact_id:'x'},{sent_at:'invalid'},{username:'../bad'},{direction:'seen'}])
 assert.equal((await createHandler(env)(request({...event,...change}))).status,400);
});
test('forwards only metadata with a fixed owner; never message contents',async()=>{
 let sent;
 const handler=createHandler(env,async(url,options)=>{sent=JSON.parse(options.body);return Response.json({action:'waiting'});});
 assert.equal((await handler(request({...event,user_id:'untrusted',text:'private message',attachments:['private']}))).status,200);
 assert.equal(sent.p_user,'f209b91f-607b-4b14-9305-6a7d567b90b5');
 assert.equal('text' in sent,false); assert.equal('attachments' in sent,false);
 assert.equal(sent.p_direction,'out'); assert.equal(sent.p_manual,true);
});
test('surfaces database errors to allow delivery retries',async()=>{
 assert.equal((await createHandler(env,async()=>new Response('',{status:500}))(request())).status,502);
});
