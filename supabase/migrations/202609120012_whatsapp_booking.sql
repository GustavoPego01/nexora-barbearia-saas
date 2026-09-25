begin;
alter table private.whatsapp_inbox add column reply text;
alter table public.whatsapp_messages add column sender_phone text;
create table private.whatsapp_sessions(
 barbershop_id uuid not null references public.barbershops(id), sender text not null,
 state jsonb not null default '{"step":"menu"}', expires_at timestamptz not null default now()+interval '1 day',
 primary key(barbershop_id,sender)
);
alter table private.whatsapp_sessions enable row level security;
create or replace function public.wa_receive(phone_id text, provider_id text, sender_phone text, message_body text) returns void language plpgsql security definer set search_path='' as $$
declare tenant uuid;
begin
 select barbershop_id into tenant from public.whatsapp_connections where phone_number_id=phone_id and status='connected';
 if tenant is null or not private.tenant_active(tenant) then return; end if;
 insert into private.whatsapp_inbox(barbershop_id,message_id,sender,body) values(tenant,provider_id,sender_phone,left(message_body,4096)) on conflict(message_id) do nothing;
 insert into public.whatsapp_messages(barbershop_id,provider_message_id,direction,status,body,sender_phone)
 values(tenant,provider_id,'inbound','received',left(message_body,4096),sender_phone) on conflict(provider_message_id) do nothing;
end $$;
create function public.wa_bot_reply(inbox uuid, public_url text) returns text language plpgsql security definer set search_path='' as $$
declare item private.whatsapp_inbox; session private.whatsapp_sessions; bot_state jsonb; result text; input text; choice integer;
 options jsonb; chosen jsonb; tenant uuid; pro public.professionals; service public.services; shop public.barbershops;
 customer uuid; appointment uuid; starts timestamptz; day date; step_minutes integer;
begin
 select * into item from private.whatsapp_inbox where id=inbox for update;
 if item.id is null or not private.tenant_active(item.barbershop_id) then return null; end if;
 if item.reply is not null then return item.reply; end if;
 if item.received_at<now()-interval '24 hours' then return null; end if;
 tenant:=item.barbershop_id;
 select * into shop from public.barbershops where id=tenant;
 insert into private.whatsapp_sessions(barbershop_id,sender) values(tenant,item.sender) on conflict do nothing;
 select * into session from private.whatsapp_sessions where barbershop_id=tenant and sender=item.sender for update;
 bot_state:=case when session.expires_at>now() then session.state else '{"step":"menu"}'::jsonb end;
 input:=lower(trim(item.body));
 if input='menu' then bot_state:='{"step":"menu"}'; end if;
 if input ~ '^\d{1,2}$' then choice:=input::int; end if;
 if bot_state->>'step'='handoff' and input<>'menu' then
 result:='Sua mensagem foi encaminhada à equipe. Para voltar ao agendamento automático, envie MENU.';
 elsif bot_state->>'step'='menu' then
  if input='1' or input like '%agend%' or input like '%marcar%' or input like '%horário%' or input like '%horario%' then
   select coalesce(jsonb_agg(jsonb_build_object('id',s.id,'name',s.name,'price',s.price_cents) order by s.name),'[]') into options from public.services s where s.barbershop_id=tenant and s.is_active;
   bot_state:=jsonb_build_object('step','service','options',options);
   select 'Escolha o serviço:'||E'\n'||coalesce(string_agg(n::text||' - '||(v->>'name')||' (R$ '||to_char((v->>'price')::numeric/100,'FM999990D00')||')',E'\n'),'Nenhum serviço disponível.') into result from jsonb_array_elements(options) with ordinality t(v,n);
  elsif input='2' then
   select 'Seus próximos horários:'||E'\n'||coalesce(string_agg(to_char(a.starts_at at time zone shop.timezone,'DD/MM HH24:MI')||' - '||s.name,E'\n'),'Nenhum agendamento encontrado.') into result
   from public.appointments a join public.customers c on c.id=a.customer_id join public.services s on s.id=a.service_id
   where a.barbershop_id=tenant and a.starts_at>now() and a.status in ('scheduled','confirmed') and
   (regexp_replace(c.phone,'\D','','g')=item.sender or '55'||regexp_replace(c.phone,'\D','','g')=item.sender);
  elsif input='3' or input like '%preço%' or input like '%preco%' then
   select 'Serviços:'||E'\n'||coalesce(string_agg(s.name||' - R$ '||to_char(s.price_cents::numeric/100,'FM999990D00'),E'\n'),'Nenhum serviço disponível.') into result from public.services s where s.barbershop_id=tenant and s.is_active;
  elsif input='4' then bot_state:='{"step":"handoff"}';result:='Sua conversa foi encaminhada à equipe. Envie MENU para voltar ao assistente.';
  else result:='Olá! Bem-vindo à '||shop.name||E'.\n1 - Agendar horário\n2 - Meus agendamentos\n3 - Serviços e preços\n4 - Falar com atendente';end if;
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
   result:='Informe a data no formato AAAA-MM-DD (ex.: '||to_char((now() at time zone shop.timezone)::date+1,'YYYY-MM-DD')||'), ou envie HOJE / AMANHÃ.';
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
    select 'Escolha um horário:'||E'\n'||string_agg(n::text||' - '||to_char((v->>'starts')::timestamptz at time zone shop.timezone,'HH24:MI')||' / '||(v->>'name'),E'\n') into result from jsonb_array_elements(options) with ordinality t(v,n);
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
   chosen:=bot_state->'chosen';starts:=(chosen->>'starts')::timestamptz;
   if not private.slot_available(tenant,(chosen->>'professional')::uuid,(bot_state->>'service')::uuid,starts) then
    bot_state:=bot_state||jsonb_build_object('step','date');result:='Esse horário foi reservado por outra pessoa. Informe outra data para consultar novamente.';
   else
    select * into service from public.services where id=(bot_state->>'service')::uuid and barbershop_id=tenant;
    select * into pro from public.professionals where id=(chosen->>'professional')::uuid and barbershop_id=tenant;
    select c.id into customer from public.customers c where c.barbershop_id=tenant and (regexp_replace(c.phone,'\D','','g')=item.sender or '55'||regexp_replace(c.phone,'\D','','g')=item.sender) order by c.created_at limit 1;
    if customer is null then insert into public.customers(barbershop_id,name,phone) values(tenant,trim(item.body),item.sender) returning id into customer;end if;
    insert into public.appointments(barbershop_id,customer_id,professional_id,service_id,starts_at,ends_at,occupied_until,price_cents,duration_minutes,commission_percent,source)
    values(tenant,customer,pro.id,service.id,starts,starts+service.duration_minutes*interval '1 minute',starts+(service.duration_minutes+pro.buffer_minutes)*interval '1 minute',service.price_cents,service.duration_minutes,pro.commission_percent,'whatsapp') returning id into appointment;
    result:='Confirmado! '||service.name||' com '||pro.name||' em '||to_char(starts at time zone shop.timezone,'DD/MM HH24:MI')||'. Envie MENU para consultar seus horários.';bot_state:='{"step":"menu"}';
   end if;
  end if;
 else bot_state:='{"step":"menu"}';result:='Envie MENU para iniciar.';end if;
 update private.whatsapp_sessions set state=bot_state,expires_at=now()+interval '1 day' where barbershop_id=tenant and sender=item.sender;
 update private.whatsapp_inbox set reply=result where id=item.id;
 return result;
end $$;
revoke all on function public.wa_bot_reply(uuid,text) from public,anon,authenticated;
grant execute on function public.wa_bot_reply(uuid,text) to service_role;
commit;
