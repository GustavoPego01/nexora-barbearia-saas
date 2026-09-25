begin;
alter table public.settings add column bot_enabled boolean not null default true, add column bot_booking_enabled boolean not null default true;
alter table public.settings add column bot_welcome_message text not null default 'Olá! Bem-vindo à {{barbearia}}.' check(length(bot_welcome_message) between 1 and 1500);
alter table public.settings add column bot_menu_message text not null default '1 - Agendar horário
2 - Meus agendamentos
3 - Serviços e preços
4 - Falar com atendente
5 - Cancelar agendamento
6 - Remarcar agendamento
7 - Funcionamento' check(length(bot_menu_message) between 1 and 1500);
alter table public.settings add column bot_service_prompt text not null default 'Escolha o serviço:' check(length(bot_service_prompt) between 1 and 1500);
alter table public.settings add column bot_professional_prompt text not null default 'Escolha o profissional:' check(length(bot_professional_prompt) between 1 and 1500);
alter table public.settings add column bot_date_prompt text not null default 'Informe a data AAAA-MM-DD, HOJE ou AMANHÃ.' check(length(bot_date_prompt) between 1 and 1500);
alter table public.settings add column bot_slot_prompt text not null default 'Escolha um horário:' check(length(bot_slot_prompt) between 1 and 1500);
alter table public.settings add column bot_confirmation_message text not null default 'Confirmado!' check(length(bot_confirmation_message) between 1 and 1500);
alter table public.settings add column bot_handoff_message text not null default 'Sua conversa foi encaminhada à equipe. Envie MENU para voltar ao assistente.' check(length(bot_handoff_message) between 1 and 1500);
grant update(bot_enabled,bot_booking_enabled,bot_welcome_message,bot_menu_message,bot_service_prompt,bot_professional_prompt,bot_date_prompt,bot_slot_prompt,bot_confirmation_message,bot_handoff_message) on public.settings to authenticated;
create or replace function public.wa_bot_reply(inbox uuid, public_url text) returns text language plpgsql security definer set search_path='' as $$
declare item private.whatsapp_inbox; session private.whatsapp_sessions; bot_state jsonb; result text; input text; choice integer;
 options jsonb; chosen jsonb; tenant uuid; pro public.professionals; service public.services; shop public.barbershops;
 customer uuid; appointment uuid; starts timestamptz; day date; step_minutes integer; cfg public.settings; old public.appointments;
begin
 select * into item from private.whatsapp_inbox where id=inbox for update;
 if item.id is null or not private.tenant_active(item.barbershop_id) then return null; end if;
 if item.reply is not null then return item.reply; end if;
 if item.received_at<now()-interval '24 hours' then return null; end if;
 tenant:=item.barbershop_id;
 select * into shop from public.barbershops where id=tenant;
 select * into cfg from public.settings where barbershop_id=tenant;
 if not cfg.bot_enabled then update private.whatsapp_inbox set reply='' where id=item.id; return ''; end if;
 insert into private.whatsapp_sessions(barbershop_id,sender) values(tenant,item.sender) on conflict do nothing;
 select * into session from private.whatsapp_sessions where barbershop_id=tenant and sender=item.sender for update;
 bot_state:=case when session.expires_at>now() then session.state else '{"step":"menu"}'::jsonb end;
 input:=lower(trim(item.body));
 if input='menu' then bot_state:='{"step":"menu"}'; end if;
 if input ~ '^\d{1,2}$' then choice:=input::int; end if;
 if bot_state->>'step' in ('cancel_pick','reschedule_pick','cancel_confirm') then
  chosen:=case when choice>0 then bot_state->'options'->(choice-1) else null end;
  if bot_state->>'step'='cancel_confirm' then chosen:=bot_state->'chosen'; end if;
  perform 1 from public.barbershops where id=tenant for update;
  select a.* into old from public.appointments a join public.customers c on c.id=a.customer_id and c.barbershop_id=a.barbershop_id
  where a.barbershop_id=tenant and a.id=(chosen->>'id')::uuid and a.status in ('scheduled','confirmed')
    and (regexp_replace(c.phone,'\D','','g')=item.sender or '55'||regexp_replace(c.phone,'\D','','g')=item.sender) for update of a;
  if old.id is null then result:='Escolha um agendamento válido ou envie MENU.';
  elsif old.starts_at<now()+cfg.cancellation_hours*interval '1 hour' then result:='O prazo para alterar este horário terminou. Fale com a equipe.';bot_state:='{"step":"menu"}';
  elsif bot_state->>'step'='cancel_confirm' then
    if input='sim' then update public.appointments set status='cancelled' where id=old.id and barbershop_id=tenant;result:='Agendamento cancelado. Envie MENU para voltar.';bot_state:='{"step":"menu"}';
    else result:='Envie SIM para confirmar o cancelamento ou MENU para sair.';end if;
  elsif bot_state->>'step'='cancel_pick' then
    bot_state:=jsonb_build_object('step','cancel_confirm','chosen',chosen);result:='Confirma cancelar '||to_char(old.starts_at at time zone shop.timezone,'DD/MM HH24:MI')||'? Envie SIM ou MENU.';
  else bot_state:=jsonb_build_object('step','date','service',old.service_id,'professional',old.professional_id,'existing',old.id);result:=cfg.bot_date_prompt;end if;
 elsif bot_state->>'step'='handoff' and input<>'menu' then
 result:='Sua mensagem foi encaminhada à equipe. Para voltar ao agendamento automático, envie MENU.';
 elsif bot_state->>'step'='menu' then
  if (input='1' or input like '%agend%' or input like '%marcar%' or input like '%horário%' or input like '%horario%') and cfg.bot_booking_enabled then
   select coalesce(jsonb_agg(jsonb_build_object('id',s.id,'name',s.name,'price',s.price_cents) order by s.name),'[]') into options from public.services s where s.barbershop_id=tenant and s.is_active;
   bot_state:=jsonb_build_object('step','service','options',options);
   select cfg.bot_service_prompt||E'\n'||coalesce(string_agg(n::text||' - '||(v->>'name')||' (R$ '||to_char((v->>'price')::numeric/100,'FM999990D00')||')',E'\n'),'Nenhum serviço disponível.') into result from jsonb_array_elements(options) with ordinality t(v,n);
  elsif input in ('5','6') then
   select coalesce(jsonb_agg(jsonb_build_object('id',a.id,'starts',a.starts_at) order by a.starts_at),'[]') into options
   from public.appointments a join public.customers c on c.id=a.customer_id and c.barbershop_id=a.barbershop_id
   where a.barbershop_id=tenant and a.status in ('scheduled','confirmed') and a.starts_at>now()
   and (regexp_replace(c.phone,'\D','','g')=item.sender or '55'||regexp_replace(c.phone,'\D','','g')=item.sender);
   bot_state:=jsonb_build_object('step',case when input='5' then 'cancel_pick' else 'reschedule_pick' end,'options',options);
   select 'Escolha o agendamento:'||E'\n'||coalesce(string_agg(n::text||' - '||to_char((v->>'starts')::timestamptz at time zone shop.timezone,'DD/MM HH24:MI'),E'\n'),'Nenhum agendamento encontrado. Envie MENU.') into result from jsonb_array_elements(options) with ordinality t(v,n);
  elsif input='7' then
   select 'Funcionamento:'||E'\n'||coalesce(string_agg((array['Dom','Seg','Ter','Qua','Qui','Sex','Sáb'])[h.weekday+1]||' '||lpad((h.start_minute/60)::text,2,'0')||':'||lpad((h.start_minute%60)::text,2,'0')||'–'||lpad((h.end_minute/60)::text,2,'0')||':'||lpad((h.end_minute%60)::text,2,'0'),E'\n' order by h.weekday,h.start_minute),'Consulte a equipe.') into result from public.business_hours h where h.barbershop_id=tenant;
  elsif input='2' then
   select 'Seus próximos horários:'||E'\n'||coalesce(string_agg(to_char(a.starts_at at time zone shop.timezone,'DD/MM HH24:MI')||' - '||s.name,E'\n'),'Nenhum agendamento encontrado.') into result
   from public.appointments a join public.customers c on c.id=a.customer_id join public.services s on s.id=a.service_id
   where a.barbershop_id=tenant and a.starts_at>now() and a.status in ('scheduled','confirmed') and
   (regexp_replace(c.phone,'\D','','g')=item.sender or '55'||regexp_replace(c.phone,'\D','','g')=item.sender);
  elsif input='3' or input like '%preço%' or input like '%preco%' then
   select 'Serviços:'||E'\n'||coalesce(string_agg(s.name||' - R$ '||to_char(s.price_cents::numeric/100,'FM999990D00'),E'\n'),'Nenhum serviço disponível.') into result from public.services s where s.barbershop_id=tenant and s.is_active;
  elsif input='4' then bot_state:='{"step":"handoff"}';result:=cfg.bot_handoff_message;
  else result:=replace(cfg.bot_welcome_message,'{{barbearia}}',shop.name)||E'\n'||cfg.bot_menu_message;end if;
 elsif bot_state->>'step'='service' then
  chosen:=case when choice>0 then bot_state->'options'->(choice-1) else null end;
  if chosen is null then result:='Envie o número do serviço ou MENU para recomeçar.';
  else
   select coalesce(jsonb_agg(jsonb_build_object('id',p.id,'name',p.name) order by p.name),'[]') into options from public.professionals p
   join public.professional_services ps on ps.barbershop_id=p.barbershop_id and ps.professional_id=p.id and ps.is_enabled
   where p.barbershop_id=tenant and p.status='available' and ps.service_id=(chosen->>'id')::uuid;
   bot_state:=jsonb_build_object('step','professional','service',chosen->>'id','options',options);
   select E'Escolha o profissional:\n0 - Qualquer disponível\n'||coalesce(string_agg(n::text||' - '||(v->>'name'),E'\n'),'') into result from jsonb_array_elements(options) with ordinality t(v,n);
  end if;
 elsif bot_state->>'step'='professional' then
  chosen:=case when choice>0 then bot_state->'options'->(choice-1) else null end;
  if choice is null or (choice<>0 and chosen is null) then result:='Envie o número do profissional, 0 para qualquer um ou MENU.';
  else
   bot_state:=jsonb_build_object('step','date','service',bot_state->>'service','professional',case when choice=0 then null else chosen->>'id' end);
   result:=cfg.bot_date_prompt;
  end if;
 elsif bot_state->>'step'='date' then
  begin day:=case when input='hoje' then (now() at time zone shop.timezone)::date when input in ('amanhã','amanha') then (now() at time zone shop.timezone)::date+1 when input ~ '^\d{4}-\d{2}-\d{2}$' then input::date else null end; exception when datetime_field_overflow then day:=null; end;
  if day is null or day<(now() at time zone shop.timezone)::date or day>(now() at time zone shop.timezone)::date+365 then result:='Data inválida. Envie AAAA-MM-DD, HOJE ou AMANHÃ.';
  else
   select slot_minutes into step_minutes from public.settings where barbershop_id=tenant;
   select coalesce(jsonb_agg(jsonb_build_object('professional',id,'name',name,'starts',slot) order by slot,name),'[]') into options from
   (select p.id,p.name,(day::timestamp+n*interval '1 minute') at time zone shop.timezone as slot from public.professionals p cross join generate_series(0,1439,step_minutes)n
   where p.barbershop_id=tenant and p.status='available' and (bot_state->>'professional' is null or p.id=(bot_state->>'professional')::uuid)
   and private.slot_available(tenant,p.id,(bot_state->>'service')::uuid,(day::timestamp+n*interval '1 minute') at time zone shop.timezone)
   order by slot,p.name limit 24)t;
   if jsonb_array_length(options)=0 then result:='Não há horários livres nesta data. Envie outra data ou MENU.';
   else bot_state:=bot_state||jsonb_build_object('step','slot','options',options);
    select cfg.bot_slot_prompt||E'\n'||string_agg(n::text||' - '||to_char((v->>'starts')::timestamptz at time zone shop.timezone,'HH24:MI')||' / '||(v->>'name'),E'\n') into result from jsonb_array_elements(options) with ordinality t(v,n);
   end if;
  end if;
 elsif bot_state->>'step'='slot' then
  chosen:=case when choice>0 then bot_state->'options'->(choice-1) else null end;
  if chosen is null then result:='Envie o número do horário ou MENU.';
  else bot_state:=bot_state||jsonb_build_object('step','name','chosen',chosen);result:='Para confirmar, informe seu nome completo (ou MENU para cancelar).';end if;
 elsif bot_state->>'step'='name' then
  if length(trim(item.body))<2 or length(trim(item.body))>150 then result:='Informe um nome entre 2 e 150 caracteres.';
  else
   perform 1 from public.barbershops where id=tenant for update;
   begin
   if not cfg.bot_booking_enabled and bot_state->>'existing' is null then raise exception 'Reservas pausadas' using errcode='42501';end if;
   if bot_state->>'existing' is not null then
    select a.* into old from public.appointments a join public.customers c on c.id=a.customer_id and c.barbershop_id=a.barbershop_id
    where a.id=(bot_state->>'existing')::uuid and a.barbershop_id=tenant and a.status in ('scheduled','confirmed')
    and a.starts_at>=now()+cfg.cancellation_hours*interval '1 hour'
    and (regexp_replace(c.phone,'\D','','g')=item.sender or '55'||regexp_replace(c.phone,'\D','','g')=item.sender) for update of a;
    if old.id is null then raise exception 'Remarcação não permitida' using errcode='42501';end if;
    update public.appointments set status='cancelled' where id=old.id;
   end if;
   chosen:=bot_state->'chosen';starts:=(chosen->>'starts')::timestamptz;
   if not private.slot_available(tenant,(chosen->>'professional')::uuid,(bot_state->>'service')::uuid,starts) then
    raise exception 'Horário indisponível' using errcode='23P01';
   else
    select * into service from public.services where id=(bot_state->>'service')::uuid and barbershop_id=tenant;
    select * into pro from public.professionals where id=(chosen->>'professional')::uuid and barbershop_id=tenant;
    select c.id into customer from public.customers c where c.barbershop_id=tenant and (regexp_replace(c.phone,'\D','','g')=item.sender or '55'||regexp_replace(c.phone,'\D','','g')=item.sender) order by c.created_at limit 1;
    if customer is null then insert into public.customers(barbershop_id,name,phone) values(tenant,trim(item.body),item.sender) returning id into customer;end if;
    if old.id is not null then
     update public.appointments set professional_id=pro.id,service_id=service.id,starts_at=starts,ends_at=starts+service.duration_minutes*interval '1 minute',
     occupied_until=starts+(service.duration_minutes+pro.buffer_minutes)*interval '1 minute',price_cents=service.price_cents,duration_minutes=service.duration_minutes,commission_percent=pro.commission_percent,status='scheduled' where id=old.id and barbershop_id=tenant;
    else
    insert into public.appointments(barbershop_id,customer_id,professional_id,service_id,starts_at,ends_at,occupied_until,price_cents,duration_minutes,commission_percent,source)
    values(tenant,customer,pro.id,service.id,starts,starts+service.duration_minutes*interval '1 minute',starts+(service.duration_minutes+pro.buffer_minutes)*interval '1 minute',service.price_cents,service.duration_minutes,pro.commission_percent,'whatsapp') returning id into appointment;
    end if;
    result:=cfg.bot_confirmation_message||' '||service.name||' com '||pro.name||' em '||to_char(starts at time zone shop.timezone,'DD/MM HH24:MI')||'. Envie MENU para consultar seus horários.';bot_state:='{"step":"menu"}';
   end if;
   exception when exclusion_violation then bot_state:=bot_state||jsonb_build_object('step','date');result:='Esse horário ficou indisponível. Sua reserva anterior foi preservada. Informe outra data.';
   when insufficient_privilege then bot_state:='{"step":"menu"}';result:='Não foi possível remarcar. Fale com a equipe.';
   end;
  end if;
 else bot_state:='{"step":"menu"}';result:='Envie MENU para iniciar.';end if;
 update private.whatsapp_sessions set state=bot_state,expires_at=now()+interval '1 day' where barbershop_id=tenant and sender=item.sender;
 update private.whatsapp_inbox set reply=result where id=item.id;
 return result;
end $$;
create table private.whatsapp_registration (
 barbershop_id uuid not null references public.barbershops(id), phone_id text not null,
 encrypted_pin text not null, primary key(barbershop_id,phone_id)
);
alter table private.whatsapp_registration enable row level security;
create function public.wa_registration_pin(tenant uuid, phone text, ciphertext text) returns text language plpgsql security definer set search_path='' as $$
begin
 insert into private.whatsapp_registration values(tenant,phone,ciphertext) on conflict do nothing;
 return (select encrypted_pin from private.whatsapp_registration where barbershop_id=tenant and phone_id=phone);
end $$;
revoke all on function public.wa_registration_pin(uuid,text,text) from public,anon,authenticated;
grant execute on function public.wa_registration_pin(uuid,text,text) to service_role;
create function public.wa_connection_error(tenant uuid) returns void language sql security definer set search_path='' as $$
 update public.whatsapp_connections set status='error' where barbershop_id=tenant and status<>'connected';
$$;
revoke all on function public.wa_connection_error(uuid) from public,anon,authenticated;
grant execute on function public.wa_connection_error(uuid) to service_role;
commit;
