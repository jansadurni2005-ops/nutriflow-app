import {readFile} from 'node:fs/promises';
import {classify} from './core.mjs';
import {localInference} from './local.mjs';
const cases=JSON.parse(await readFile(new URL(process.argv[3]==='bilingual'?'./bilingual.json':process.argv[3]==='holdout'?'./holdout.json':'./evaluation.json',import.meta.url),'utf8'));
const infer=localInference(process.argv[2]||'ollama');
let correct=0,pred=0,tp=0,miss=0,flags=0,fail=0,critical=0;
for(const c of cases){
 const messages=c.conversation.map(([role,text],i)=>({id:'m'+i,role,text,at:new Date(1e12+i*1000).toISOString()}));
 const r=await classify({messages,history_complete:true},{processingApproved:true,infer:async q=>{try{return await infer(q);}catch(e){fail++;throw e;}}});
 const match=r.interest_level===c.expected_level, exactTags=[...r.additional_tags].sort().join() === [...c.expected_flags].sort().join();
 correct+=match; flags+=exactTags;
 if(r.interest_level==='hot'){pred++; if(match)tp++;}else if(c.expected_level==='hot')miss++;
 if(['yes-call','yes-resource','yes-goal','catalan-stop','recent-rejection','missing-context'].includes(c.id)&&(!match||!exactTags))critical++;
 console.log(JSON.stringify({id:c.id,expected:c.expected_level,got:r.interest_level,flags:r.additional_tags,match,exactTags}));
}
console.log(JSON.stringify({cases:cases.length,levelCorrect:correct,flagsCorrect:flags,hotTrue:tp,hotFalse:pred-tp,hotMissed:miss,inferenceErrors:fail,criticalFailures:critical}));
if((process.argv[3]==='bilingual' && correct!==cases.length)||fail||critical||tp===0||pred!==tp||correct/cases.length<0.875||flags!==cases.length) process.exitCode=1;
