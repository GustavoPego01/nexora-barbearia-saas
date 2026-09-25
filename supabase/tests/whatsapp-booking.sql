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
insert into public.whatsapp_connections(barbershop_id,phone_number_id,status) values('94000000-0000-0000-0000-000000000001','teste-numero-bot','connected');
do $$ declare input text; msg text; inbox uuid; reply text; begin
 foreach input in array array['1','99','1','1',to_char((now() at time zone 'America/Sao_Paulo')::date+1,'YYYY-MM-DD'),'1','Cliente WhatsApp'] loop
  msg:=gen_random_uuid()::text;
  perform public.wa_receive('teste-numero-bot',msg,'5511999998888',input);
  select id into inbox from private.whatsapp_inbox where message_id=msg;
  reply:=public.wa_bot_reply(inbox,'https://example.test');
  if reply is null then raise exception 'Bot retornou resposta vazia'; end if;
 end loop;
 if reply not like 'Confirmado!%' then raise exception 'Bot não concluiu reserva: %',reply; end if;
 if (select count(*) from public.appointments where barbershop_id='94000000-0000-0000-0000-000000000001' and source='whatsapp')<>1 then raise exception 'Reserva WhatsApp incorreta'; end if;
 perform public.wa_bot_reply(inbox,'https://example.test');
 perform public.wa_receive('teste-numero-bot',msg,'5511999998888','Cliente WhatsApp');
 if (select count(*) from public.appointments where barbershop_id='94000000-0000-0000-0000-000000000001')<>1 then raise exception 'Replay criou reserva duplicada'; end if;
end $$;
create function pg_temp.bot(input text, sender text default '5511999998888') returns text language plpgsql as $$
declare msg text:=gen_random_uuid()::text; inbox uuid;
begin
 perform public.wa_receive('teste-numero-bot',msg,sender,input);
 select id into inbox from private.whatsapp_inbox where message_id=msg;
 return public.wa_bot_reply(inbox,'https://example.test');
end $$;
do $$ declare original public.appointments; result text; chosen jsonb; block uuid; begin
 select * into original from public.appointments where barbershop_id='94000000-0000-0000-0000-000000000001';
 perform pg_temp.bot('6');perform pg_temp.bot('1');
 perform pg_temp.bot(to_char((now() at time zone 'America/Sao_Paulo')::date+2,'YYYY-MM-DD'));
 perform pg_temp.bot('1');
 select state->'chosen' into chosen from private.whatsapp_sessions where barbershop_id=original.barbershop_id and sender='5511999998888';
 insert into public.blocked_times(barbershop_id,starts_at,ends_at,reason)
 values(original.barbershop_id,(chosen->>'starts')::timestamptz,(chosen->>'starts')::timestamptz+interval '1 hour','other') returning id into block;
 result:=pg_temp.bot('Cliente WhatsApp');
 if result not like '%preservada%' or not exists(select 1 from public.appointments where id=original.id and starts_at=original.starts_at and status=original.status) then raise exception 'Remarcação em conflito perdeu reserva: %',result;end if;
 delete from public.blocked_times where id=block;
 perform pg_temp.bot(to_char((now() at time zone 'America/Sao_Paulo')::date+2,'YYYY-MM-DD'));
 perform pg_temp.bot('1');result:=pg_temp.bot('Cliente WhatsApp');
 if result not like 'Confirmado!%' or not exists(select 1 from public.appointments where id=original.id and starts_at<>original.starts_at and status='scheduled') then raise exception 'Remarcação falhou: %',result;end if;
 result:=pg_temp.bot('5','5511888887777');
 if result not like '%Nenhum agendamento%' then raise exception 'Remetente leu horários alheios';end if;
 perform pg_temp.bot('1','5511888887777');perform pg_temp.bot('sim','5511888887777');
 if exists(select 1 from public.appointments where id=original.id and status='cancelled') then raise exception 'Remetente cancelou horário alheio';end if;
 perform pg_temp.bot('5');perform pg_temp.bot('1');result:=pg_temp.bot('sim');
 if result not like 'Agendamento cancelado%' or not exists(select 1 from public.appointments where id=original.id and status='cancelled') then raise exception 'Cancelamento falhou: %',result;end if;
 update public.settings set bot_welcome_message='Bem-vindo {{barbearia}}' where barbershop_id=original.barbershop_id;
 result:=pg_temp.bot('menu');if result not like 'Bem-vindo Teste de fluxo%' then raise exception 'Personalização ignorada';end if;
 update public.settings set bot_booking_enabled=false where barbershop_id=original.barbershop_id;
 result:=pg_temp.bot('1');if result like 'Escolha o serviço%' then raise exception 'Reservas pausadas foram aceitas';end if;
 update public.settings set bot_enabled=false where barbershop_id=original.barbershop_id;
 if pg_temp.bot('menu')<>'' then raise exception 'Bot desativado respondeu';end if;
end $$;
select 'WhatsApp: reserva, replay, remarcação, conflito, cancelamento, remetente e automação: OK' as result;
rollback;
