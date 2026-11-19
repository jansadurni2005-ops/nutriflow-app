import {test} from 'node:test';
import assert from 'node:assert/strict';
import {localInference} from '../integrations/lead-classifier/local.mjs';
function withModel(replies,calls){
 return localInference('ollama',async(url,opts)=>{
   assert.equal(url,'http://127.0.0.1:11434/api/chat');
   const {format}=JSON.parse(opts.body),key=Object.keys(format.properties)[0];
   calls.push(key);assert.ok(Object.hasOwn(replies,key),'unexpected verification: '+key);
   const answer=key==='meaning'?replies.meaning:{[key]:replies[key]};
   return {ok:true,json:async()=>({message:{content:JSON.stringify(answer)}})};
 });
}
const base={meaning:'service_question',nutritionist:false,budget:true,already_client:false,opt_out:false,certainty:'clear'};
async function classify(turns,out={}){
 const calls=[];const messages=turns.map(([role,text],i)=>({id:'msg'+i,role,text}));
 const index=messages.findLastIndex(m=>m.role==='athlete');
 const infer=withModel({...out,meaning:{...base,evidence:'t'+index,...out.meaning}},calls);
 const r=await infer({messages});return [r,calls];
}
test('pure fee questions in Spanish and Catalan never acquire a price objection from the initial inference',async()=>{
 for(const phrase of ['Hola, ¿cuánto cuesta el programa mensual?','Va, a quant surt el seguiment?']){
  const [r,c]=await classify([['jan','Te cuento sobre mi asesoría'],['athlete',phrase]]);
  assert.deepEqual(c,['meaning']);assert.equal(r.interest_level,'hot');assert.deepEqual(r.additional_tags,[]);
 }
});
test('budget evidence can coexist with a concrete commercial question',async()=>{
 for(const [text,quote] of [['¿Cuánto cuesta tu plan? Tengo el presupuesto muy ajustado.','Tengo el presupuesto muy ajustado'],['Quin preu té? Aquest mes no m’ho puc permetre.','no m’ho puc permetre']]){
  const [r]=await classify([['athlete',text]],{quote,decision:'service_question'});
  assert.equal(r.interest_level,'hot');assert.deepEqual(r.additional_tags,['price_objection']);
 }
});
test('a quote attributed only to Jan cannot become an athlete budget objection',async()=>{
 const [r]=await classify([['jan','¿Se te va de presupuesto?'],['athlete','Solo quiero ver qué incluye la asesoría.']],{quote:'Se te va de presupuesto',decision:'service_question'});
 assert.equal(r.interest_level,'hot');assert.deepEqual(r.additional_tags,[]);
});
test('a prior affordability issue is evaluated rather than erased by a later fee question',async()=>{
 const [r]=await classify([['athlete','No me llega el sueldo.'],['jan','Hay otro servicio'],['athlete','¿Cuánto cuesta?']],{quote:'No me llega el sueldo'});
 assert.deepEqual(r.additional_tags,['price_objection']);
});
test('an erroneous commercial prediction for tentative interest stays warm in either language',async()=>{
 for(const text of ["M’interessa, però primer he de parlar-ne amb la família.",'Me interesa, pero antes necesito consultarlo.']){
  const [r,c]=await classify([['athlete',text]],{meaning:{budget:false}});
  assert.equal(r.interest_level,'warm');assert.deepEqual(c,['meaning']);
 }
});
test('how-to question follows the recipe, even if the first inference suggested coaching',async()=>{
 const [r]=await classify([['jan','Et passo la recepta de casa.'],['athlete','I com ho fas?']],{meaning:{budget:false}});
 assert.equal(r.interest_level,'neutral');assert.deepEqual(r.additional_tags,[]);
});
test('ambiguous reference to a personal service stays under review',async()=>{
 const [r]=await classify([['athlete','¿Y esto cómo va?']],{meaning:{budget:false},decision:'context_missing'});
 assert.equal(r.interest_level,'unknown');assert.equal(r.needs_human_review,true);
});
test('ordinary background cannot reach hot after independent review finds no sales enquiry',async()=>{
 const [r]=await classify([['athlete','Compito en pista cuatro días al mes.']],{meaning:{budget:false},decision:'social_reply'});
 assert.equal(r.interest_level,'neutral');
});

test('explicit coaching enquiries stay commercial even when the first model mistakes them for an ordinary goal',async()=>{
 const rows=[
  [['jan','Et parlo del meu assessorament.'],['athlete','I com ho fas?']],
  [['athlete','Tengo una dietista, pero me gustaría saber cómo trabajas.']],
  [['athlete','Et puc preguntar què inclou el teu seguiment?']],
  [['athlete','¿Tienes algún hueco para trabajar contigo la próxima temporada?']]
 ];
 for(const turns of rows){
  const [r]=await classify(turns,{meaning:{meaning:'nutrition_goal',budget:false},accepted:'other'});
  assert.equal(r.interest_level,'hot');assert.deepEqual(r.additional_tags,[]);
 }
});
test('a declined offer or a request to explain a free recipe is never promoted by explicit method wording',async()=>{
 const [a]=await classify([['athlete','No quiero saber cómo trabajas.']],{meaning:{meaning:'explicit_decline',budget:false}});
 const [b]=await classify([['jan','Te explico la receta de arroz gratis.'],['athlete','¿Y cómo lo haces?']],{meaning:{meaning:'resource_only',budget:false},accepted:'other'});
 assert.equal(a.interest_level,'cold');assert.equal(b.interest_level,'neutral');
});

test('a clear commercial phrase cannot legitimize invalid base-model evidence',async()=>{
 await assert.rejects(classify([['athlete','¿Cómo trabajas?']],{meaning:{evidence:'t999',budget:false}}),/invalid_semantics/);
});
