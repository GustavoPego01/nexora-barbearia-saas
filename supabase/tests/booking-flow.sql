begin;
insert into auth.users(id,email,email_confirmed_at) values
 ('93000000-0000-0000-0000-000000000001','owner-flow@barbearias.test',now()),
 ('93000000-0000-0000-0000-000000000002','customer-flow@barbearias.test',now());
insert into public.barbershops(id,name,slug,is_published) values('94000000-0000-0000-0000-000000000001','Teste de fluxo','teste-fluxo-transacional',true);
insert into public.subscriptions(barbershop_id,plan,status) values('94000000-0000-0000-0000-000000000001','pro','active');
insert into public.settings(barbershop_id,booking_notice_minutes) values('94000000-0000-0000-0000-000000000001',0);
insert into public.barbershop_members(barbershop_id,user_id,role) values('94000000-0000-0000-0000-000000000001','93000000-0000-0000-0000-000000000001','owner');
insert into public.professionals(id,barbershop_id,name,commission_percent,buffer_minutes) values
 ('95000000-0000-0000-0000-000000000001','94000000-0000-0000-0000-000000000001','Profissional',40,10);
insert into public.services(id,barbershop_id,name,price_cents,duration_minutes) values
 ('96000000-0000-0000-0000-000000000001','94000000-0000-0000-0000-000000000001','Corte',5000,30);
insert into public.professional_services values('94000000-0000-0000-0000-000000000001','95000000-0000-0000-0000-000000000001','96000000-0000-0000-0000-000000000001');
insert into public.business_hours(barbershop_id,weekday,start_minute,end_minute) select '94000000-0000-0000-0000-000000000001',n,540,1080 from generate_series(0,6)n;
insert into public.professional_schedules(barbershop_id,professional_id,weekday,start_minute,end_minute)
 select '94000000-0000-0000-0000-000000000001','95000000-0000-0000-0000-000000000001',n,540,1080 from generate_series(0,6)n;
set local role authenticated;
select set_config('request.jwt.claim.sub','93000000-0000-0000-0000-000000000002',true);
do $$ declare a uuid; starts timestamptz:=((now() at time zone 'America/Sao_Paulo')::date+1+time '12:00') at time zone 'America/Sao_Paulo'; begin
 if jsonb_array_length(public.available_slots('94000000-0000-0000-0000-000000000001','96000000-0000-0000-0000-000000000001',(starts at time zone 'America/Sao_Paulo')::date))=0 then raise exception 'Disponibilidade vazia'; end if;
 a:=public.book_appointment('94000000-0000-0000-0000-000000000001','96000000-0000-0000-0000-000000000001','95000000-0000-0000-0000-000000000001',starts,'Cliente','11999999999');
 begin
 perform public.book_appointment('94000000-0000-0000-0000-000000000001','96000000-0000-0000-0000-000000000001','95000000-0000-0000-0000-000000000001',starts,'Outro','11999999999');
 raise exception 'Reserva duplicada aceita'; exception when exclusion_violation then null; end;
 perform public.book_appointment('94000000-0000-0000-0000-000000000001','96000000-0000-0000-0000-000000000001','95000000-0000-0000-0000-000000000001',starts+interval '1 hour','Cliente','11999999999',null,a);
 perform set_config('test.appointment_id',a::text,true);
end $$;
reset role;
set local role authenticated;
select set_config('request.jwt.claim.sub','93000000-0000-0000-0000-000000000001',true);
do $$ declare a uuid:=current_setting('test.appointment_id')::uuid; report jsonb; begin
 begin
 perform public.appointment_action(a,'completed','other'); raise exception 'Pagamento não aceito passou';
 exception when raise_exception then if sqlerrm='Pagamento não aceito passou' then raise; end if; end;
 perform public.appointment_action(a,'completed','pix');
 report:=public.finance_report('94000000-0000-0000-0000-000000000001',now()-interval '1 hour',now()+interval '1 hour');
 if (report->0->>'amount_cents')::int<>5000 or (report->0->>'commission_cents')::int<>2000 then raise exception 'Receita ou comissão incorreta'; end if;
 begin perform public.appointment_action(a,'completed','pix'); raise exception 'Conclusão repetida aceita';
 exception when raise_exception then if sqlerrm='Conclusão repetida aceita' then raise; end if; end;
end $$;
reset role;
select 'Reserva, conflito, remarcação, forma aceita, receita, comissão e idempotência: OK' as result;
rollback;
