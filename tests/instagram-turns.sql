-- Run AFTER loading the proposed schema, within the same BEGIN / ROLLBACK.
do $$
declare
 u uuid:='f209b91f-607b-4b14-9305-6a7d567b90b5';
 a text:='17841449201493232'; b timestamptz:=now()-interval '1 day';
 r jsonb; i integer; d text; n integer;
begin
 if exists(select 1 from public.leads where user_id=u and name like '@nf_test_20261105_%') then raise exception 'fixture collision';end if;
 -- Four turns must not qualify; the fifth must qualify exactly once.
 for i in 1..4 loop
  d:=case when i%2=1 then 'out' else 'in' end;
  r:=public.nf_record_instagram_turn(u,a,'991001','nf_test_a_'||i,b+i*interval '1 second',d,true,'nf_test_20261105_a');
  if r->>'action'<>'waiting' then raise exception 'premature qualification';end if;
 end loop;
 r:=public.nf_record_instagram_turn(u,a,'991001','nf_test_a_5',b+interval '5 seconds','out',true,'nf_test_20261105_a');
 if r->>'action'<>'created' then raise exception 'missing fifth-turn qualification: %',r;end if;
 r:=public.nf_record_instagram_turn(u,a,'991001','nf_test_a_5',b+interval '5 seconds','out',true,'nf_test_20261105_a');
 select count(*) into n from public.leads where user_id=u and name='@nf_test_20261105_a' and source='Instagram' and status='Contacted';
 if n<>1 then raise exception 'duplicate or wrong lead state';end if;
 -- Consecutive outbound messages do not inflate conversation turns.
 for i in 1..5 loop
  r:=public.nf_record_instagram_turn(u,a,'991002','nf_test_b_'||i,b+i*interval '1 second','out',true,'nf_test_20261105_b');
  if r->>'action'<>'waiting' then raise exception 'counted messages instead of turns';end if;
 end loop;
 -- An automatic outbound event is not a human turn.
 r:=public.nf_record_instagram_turn(u,a,'991002','nf_test_auto',b,'out',false,'nf_test_20261105_b');
 if r->>'action'<>'ignored_non_manual' then raise exception 'counted automation';end if;
 -- Out-of-order delivery is evaluated in message timestamp order.
 foreach i in array array[5,3,1,4,2] loop
  d:=case when i%2=1 then 'out' else 'in' end;
  r:=public.nf_record_instagram_turn(u,a,'991003','nf_test_c_'||i,b+i*interval '1 second',d,true,'nf_test_20261105_c');
 end loop;
 if r->>'action'<>'created' then raise exception 'failed delayed delivery';end if;
 -- Existing manual lead links by stable handle, not display name; preserve sale state.
 insert into public.leads(id,user_id,name,source,status,date) values('nf_test_existing',u,'@nf_test_20261105_d','Instagram','Closed',current_date);
 for i in 1..5 loop
  d:=case when i%2=1 then 'out' else 'in' end;
  r:=public.nf_record_instagram_turn(u,a,'991004','nf_test_d_'||i,b+i*interval '1 second',d,true,'nf_test_20261105_d');
 end loop;
 if r->>'action'<>'matched_existing' or r->>'lead_id'<>'nf_test_existing' then raise exception 'did not deduplicate';end if;
 if (select status from public.leads where id='nf_test_existing' and user_id=u)<>'Closed' then raise exception 'regressed sale status';end if;
 -- A deleted qualified lead stays deleted despite later events.
 delete from public.leads where id='ig_'||a||'_991001' and user_id=u;
 r:=public.nf_record_instagram_turn(u,a,'991001','nf_test_a_6',b+interval '6 seconds','in',true,'nf_test_20261105_a');
 if r->>'action'<>'deleted_lead_not_recreated' then raise exception 'recreated deleted lead';end if;
 -- No profile means no guessed identity.
 for i in 1..5 loop
  d:=case when i%2=1 then 'out' else 'in' end;
  r:=public.nf_record_instagram_turn(u,a,'991005','nf_test_e_'||i,b+i*interval '1 second',d,true,'');
 end loop;
 if r->>'action'<>'profile_required' then raise exception 'guessed missing profile';end if;
 -- RPC and event metadata are inaccessible to browser roles.
 if has_table_privilege('anon','public.nf_instagram_turn_events','SELECT') or has_table_privilege('authenticated','public.nf_instagram_turn_events','SELECT') then raise exception 'public metadata access';end if;
 if has_function_privilege('anon','public.nf_record_instagram_turn(uuid,text,text,text,timestamptz,text,boolean,text)','EXECUTE') or has_function_privilege('authenticated','public.nf_record_instagram_turn(uuid,text,text,text,timestamptz,text,boolean,text)','EXECUTE') then raise exception 'public ingestion access';end if;
end;$$;
select 'PASS: 9 database scenarios; fixture and schema changes rolled back' as result;
