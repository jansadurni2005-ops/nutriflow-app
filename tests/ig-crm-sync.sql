do $$
declare tid constant text:='synthetic'; peer constant text:='11113333'; rev constant text:=repeat('a',64); rows jsonb; a text; n int;b boolean;
begin
 select jsonb_agg(jsonb_build_object('id','m'||i,'outgoing',(i%2=1),'human',false,'at',now()-interval '1 hour'+i*interval '5 seconds') order by i) into rows from generate_series(1,5)i;
 perform public.nf_ig_observe(tid,peer,'example',rev,now(),rows);
 perform public.nf_ig_observe(tid,peer,'example',rev,now(),rows);
 if (select count(*) from public.nf_ig_sync_observed where thread_id=tid)<>5 or exists(select 1 from public.leads where name='@example') then raise exception 'echo or duplicate created lead';end if;
 perform public.nf_ig_scored(tid,rev,'hot','{}',false);
 a:=public.nf_ig_confirm_outgoing(tid,rev,array['m1','m3']); if a<>'waiting' then raise exception 'early creation';end if;
 a:=public.nf_ig_confirm_outgoing(tid,rev,array['m5']);if a<>'created' then raise exception 'fifth turn failed';end if;
 if (select count(*) from public.leads where name='@example' and source='Instagram' and status='Contacted' and lead_interest='high')<>1 then raise exception 'wrong projection';end if;
 a:=public.nf_ig_confirm_outgoing(tid,rev,array['m5']);if a<>'existing' then raise exception 'not idempotent';end if;
 perform public.nf_ig_scored(tid,rev,'cold',array['do_not_contact'],false);perform public.nf_ig_scored(tid,rev,'hot','{}',false);
 if not(select flags@>array['do_not_contact'] from public.nf_ig_sync_threads where thread_id=tid) then raise exception 'removed optout';end if;
 if public.nf_ig_scored(tid,repeat('b',64),'hot','{}',false) then raise exception 'stale write';end if;
 update public.leads set status='Closed',lead_interest='medium' where name='@example';perform public.nf_ig_scored(tid,rev,'hot','{}',false);
 if not exists(select 1 from public.leads where name='@example' and status='Closed' and lead_interest='medium')then raise exception 'changed customer';end if;
 -- A second conversation with explicit provider-origin evidence qualifies by itself.
 select jsonb_agg(jsonb_build_object('id','h'||i,'outgoing',(i%2=1),'human',(i%2=1),'at',now()-interval '2 hours'+i*interval '5 seconds') order by i) into rows from generate_series(1,5)i;
 perform public.nf_ig_observe('tagged','11114444','taggedfixture',rev,now(),rows);
 if (select count(*) from public.leads where name='@taggedfixture' and status='Contacted')<>1 then raise exception 'tagged qualification failed';end if;
 if has_table_privilege('anon','public.nf_ig_sync_control','select') or has_table_privilege('authenticated','public.nf_ig_sync_observed','select') or has_function_privilege('authenticated','public.nf_ig_confirm_outgoing(text,text,text[])','execute') then raise exception 'excess grants';end if;
end $$;
