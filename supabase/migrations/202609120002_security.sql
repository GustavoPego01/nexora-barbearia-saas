begin;
-- Helpers privados evitam recursão de RLS. Identidade sempre vem de auth.uid().
create function private.tenant_active(tenant uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.barbershops b join public.subscriptions s on s.barbershop_id=b.id
    where b.id=tenant and b.is_active and s.status in ('active','trial')
    and (s.expires_at is null or s.expires_at > now())
    and (s.status <> 'trial' or s.trial_ends_at > now()));
$$;
create function private.has_role(tenant uuid, roles public.member_role[]) returns boolean
language sql stable security definer set search_path = '' as $$
  select private.tenant_active(tenant) and exists (
    select 1 from public.barbershop_members m where m.barbershop_id=tenant
    and m.user_id=(select auth.uid()) and m.is_active and m.role=any(roles));
$$;
create function private.owns_professional(tenant uuid, professional uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select private.has_role(tenant,array['professional']::public.member_role[]) and exists (
    select 1 from public.professionals p join public.barbershop_members m
      on m.barbershop_id=p.barbershop_id and m.id=p.member_id
    where p.barbershop_id=tenant and p.id=professional and m.user_id=(select auth.uid()));
$$;
create function private.owns_customer(tenant uuid, customer uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select private.tenant_active(tenant) and exists (select 1 from public.customers c
    where c.barbershop_id=tenant and c.id=customer and c.user_id=(select auth.uid()));
$$;
create function private.serves_customer(tenant uuid, customer uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.appointments a where a.barbershop_id=tenant
    and a.customer_id=customer and private.owns_professional(tenant,a.professional_id));
$$;
create function private.own_commission_visible(tenant uuid, professional uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select private.owns_professional(tenant,professional) and exists (
    select 1 from public.settings s where s.barbershop_id=tenant and s.commissions_enabled);
$$;
grant execute on function private.tenant_active(uuid), private.has_role(uuid,public.member_role[]),
  private.owns_professional(uuid,uuid), private.owns_customer(uuid,uuid),
  private.serves_customer(uuid,uuid), private.own_commission_visible(uuid,uuid) to authenticated;

-- Catálogos globais não contêm dados de empresas.
grant select on public.plans, public.themes to anon, authenticated;
create policy plans_read on public.plans for select to anon, authenticated using (true);
create policy themes_read on public.themes for select to anon, authenticated using (true);
grant select on public.profiles to authenticated;
grant update(full_name,phone) on public.profiles to authenticated;
create policy profile_read on public.profiles for select to authenticated using (id=(select auth.uid()));
create policy profile_update on public.profiles for update to authenticated
  using (id=(select auth.uid())) with check (id=(select auth.uid()));

grant select on public.barbershops, public.barbershop_members, public.subscriptions to authenticated;
create policy shop_read on public.barbershops for select to authenticated using
  (private.has_role(id,array['owner','manager','professional','receptionist']::public.member_role[]));
create policy members_read on public.barbershop_members for select to authenticated using
  (private.has_role(barbershop_id,array['owner','manager']::public.member_role[])
    or (user_id=(select auth.uid()) and private.tenant_active(barbershop_id)));
create policy subscription_read on public.subscriptions for select to authenticated using
  (private.has_role(barbershop_id,array['owner']::public.member_role[]));
-- Campos administrativos (is_active, id, created_at) não são atualizáveis pelo cliente.
grant update(name,description,phone,whatsapp,instagram,address,postal_code,city,state,maps_url,
  logo_path,cover_path,welcome_message,theme,primary_color,secondary_color,timezone,
  is_published,onboarding_step,onboarding_completed_at) on public.barbershops to authenticated;
create policy shop_update on public.barbershops for update to authenticated using
  (private.has_role(id,array['owner']::public.member_role[])) with check
  (private.has_role(id,array['owner']::public.member_role[]));

-- Políticas iguais agrupadas; cada WITH CHECK revalida a empresa destino.
do $$ declare table_name text; manage_roles text; begin
  foreach table_name in array array['settings','services','professionals','professional_services',
    'business_hours','professional_schedules','customers','customer_notes','notification_templates'] loop
    manage_roles := case
      when table_name in ('settings','notification_templates') then '''owner'''
      when table_name in ('customers','customer_notes') then '''owner'',''manager'',''receptionist'''
      else '''owner'',''manager''' end;
    execute format('grant select, insert, delete on public.%I to authenticated',table_name);
    execute format('create policy manage_insert on public.%I for insert to authenticated with check
      (private.has_role(barbershop_id,array[%s]::public.member_role[]))',table_name,manage_roles);
    execute format('create policy manage_update on public.%I for update to authenticated using
      (private.has_role(barbershop_id,array[%s]::public.member_role[])) with check
      (private.has_role(barbershop_id,array[%s]::public.member_role[]))',table_name,manage_roles,manage_roles);
    execute format('create policy manage_delete on public.%I for delete to authenticated using
      (private.has_role(barbershop_id,array[%s]::public.member_role[]))',table_name,manage_roles);
    execute format('create policy staff_read on public.%I for select to authenticated using
      (private.has_role(barbershop_id,array[%s]::public.member_role[]))',table_name,
      case when table_name in ('settings','notification_templates') then '''owner'',''manager'''
        else '''owner'',''manager'',''receptionist''' end);
  end loop;
end $$;
-- Inserção de vínculo customer/user somente em operação confiável, nunca por CRUD genérico.
revoke insert on public.customers from authenticated;
grant insert(barbershop_id,name,phone,email), update(name,phone,email) on public.customers to authenticated;
grant update(cancellation_hours,booking_notice_minutes,booking_horizon_days,slot_minutes,
  commissions_enabled,accepted_payments,reminder_24h,reminder_2h) on public.settings to authenticated;
grant update(name,description,price_cents,duration_minutes,image_path,category,is_active) on public.services to authenticated;
grant update(member_id,name,phone,email,photo_path,specialties,status,commission_percent,buffer_minutes) on public.professionals to authenticated;
grant update(body) on public.customer_notes to authenticated;
grant update(enabled,body) on public.notification_templates to authenticated;
grant update(weekday,start_minute,end_minute) on public.business_hours,public.professional_schedules to authenticated;
create policy customer_own_read on public.customers for select to authenticated using
  (private.owns_customer(barbershop_id,id) or private.serves_customer(barbershop_id,id));
-- Professional lê seu cadastro apenas quando comissões estão habilitadas;
-- projeções sem dados financeiros serão entregues com os fluxos da equipe/agenda.
create policy professional_own_read on public.professionals for select to authenticated using
  (private.own_commission_visible(barbershop_id,id));
create policy own_schedule_read on public.professional_schedules for select to authenticated using
  (private.owns_professional(barbershop_id,professional_id));

-- Agenda é somente leitura nesta etapa. RPC transacional de reserva virá na Etapa 10.
-- Não liberar INSERT/UPDATE direto: isso permitiria burlar horários e snapshots.
grant select on public.appointments,public.blocked_times,public.appointment_notes,
  public.payments,public.notifications,public.whatsapp_connections,public.whatsapp_messages,
  public.audit_logs to authenticated;
-- Snapshots de comissão não são expostos a clientes. A API só recebe as colunas abaixo.
revoke select on public.appointments from authenticated;
grant select(id,barbershop_id,customer_id,professional_id,service_id,starts_at,ends_at,occupied_until,
  status,price_cents,duration_minutes,source,created_at,updated_at) on public.appointments to authenticated;
create policy appointment_read on public.appointments for select to authenticated using (
  private.has_role(barbershop_id,array['owner','manager','receptionist']::public.member_role[])
  or private.owns_professional(barbershop_id,professional_id)
  or private.owns_customer(barbershop_id,customer_id));
create policy blocked_read on public.blocked_times for select to authenticated using (
  private.has_role(barbershop_id,array['owner','manager','receptionist']::public.member_role[])
  or private.owns_professional(barbershop_id,professional_id));
create policy appointment_notes_read on public.appointment_notes for select to authenticated using
  (private.has_role(barbershop_id,array['owner','manager','receptionist']::public.member_role[]));
create policy payments_read on public.payments for select to authenticated using
  (private.has_role(barbershop_id,array['owner','manager','receptionist']::public.member_role[]));
create policy notifications_read on public.notifications for select to authenticated using
  (private.has_role(barbershop_id,array['owner','manager']::public.member_role[]));
create policy whatsapp_connection_read on public.whatsapp_connections for select to authenticated using
  (private.has_role(barbershop_id,array['owner']::public.member_role[]));
create policy whatsapp_messages_read on public.whatsapp_messages for select to authenticated using
  (private.has_role(barbershop_id,array['owner','manager','receptionist']::public.member_role[]));
create policy audit_read on public.audit_logs for select to authenticated using
  (private.has_role(barbershop_id,array['owner']::public.member_role[]));

create function private.touch_row() returns trigger language plpgsql set search_path = '' as $$
begin
  if to_jsonb(new)->'id' is distinct from to_jsonb(old)->'id'
    or to_jsonb(new)->'barbershop_id' is distinct from to_jsonb(old)->'barbershop_id' then
    raise exception 'Identidade e empresa do registro são imutáveis' using errcode='23514';
  end if;
  if to_jsonb(new) ? 'updated_at' then new.updated_at := now(); end if;
  return new;
end $$;
create function private.audit_change() returns trigger
language plpgsql security definer set search_path = '' as $$
declare row_data jsonb; tenant uuid;
begin
  row_data := case when tg_op='DELETE' then to_jsonb(old) else to_jsonb(new) end;
  tenant := case when tg_table_name='barbershops' then (row_data->>'id')::uuid
    else (row_data->>'barbershop_id')::uuid end;
  insert into public.audit_logs(barbershop_id,actor_id,action,entity_table,entity_id)
    values (tenant,auth.uid(),lower(tg_op),tg_table_name,coalesce(row_data->>'id',tenant::text));
  -- Não copiar payloads/PII ou segredos para o log.
  return coalesce(new,old);
end $$;
do $$ declare n text; begin
  foreach n in array array['barbershops','subscriptions','barbershop_members','settings','customers',
    'customer_notes','professionals','services','professional_services','business_hours','professional_schedules',
    'appointments','appointment_notes','blocked_times','payments','notification_templates','notifications',
    'whatsapp_connections','whatsapp_messages'] loop
    execute format('create trigger immutable_touch before update on public.%I for each row execute function private.touch_row()',n);
    execute format('create trigger audit_change after insert or update or delete on public.%I for each row execute function private.audit_change()',n);
  end loop;
end $$;
create trigger profile_touch before update on public.profiles for each row execute function private.touch_row();

-- Perfil provisionado sem copiar metadata de autorização.
create function private.create_profile() returns trigger
language plpgsql security definer set search_path = '' as $$
begin insert into public.profiles(id) values(new.id) on conflict do nothing; return new; end $$;
create trigger auth_user_profile after insert on auth.users for each row execute function private.create_profile();
insert into public.profiles(id) select id from auth.users on conflict do nothing;

create function private.validate_shop() returns trigger language plpgsql set search_path = '' as $$
begin
  if not exists(select 1 from pg_catalog.pg_timezone_names where name=new.timezone) then
    raise exception 'Fuso horário inválido' using errcode='23514';
  end if;
  if (new.logo_path is not null and split_part(new.logo_path,'/',1) <> new.id::text)
    or (new.cover_path is not null and split_part(new.cover_path,'/',1) <> new.id::text) then
    raise exception 'Imagem de outra empresa' using errcode='23514';
  end if;
  return new;
end $$;
create trigger shop_validate before insert or update on public.barbershops for each row execute function private.validate_shop();

create function private.professional_limit() returns trigger
language plpgsql security definer set search_path = '' as $$
declare maximum integer; used integer;
begin
  -- Serializa inclusive alterações concorrentes de plano na mesma assinatura.
  perform 1 from public.subscriptions where barbershop_id=new.barbershop_id for update;
  select p.professional_limit into maximum from public.subscriptions s join public.plans p on p.id=s.plan
    where s.barbershop_id=new.barbershop_id;
  if not found then raise exception 'Assinatura obrigatória' using errcode='23514'; end if;
  if new.status <> 'disabled' and maximum is not null then
    select count(*) into used from public.professionals where barbershop_id=new.barbershop_id
      and status <> 'disabled' and id <> new.id;
    if used >= maximum then raise exception 'Limite de profissionais do plano atingido' using errcode='23514'; end if;
  end if;
  if new.photo_path is not null and split_part(new.photo_path,'/',1) <> new.barbershop_id::text then
    raise exception 'Imagem de outra empresa' using errcode='23514';
  end if;
  return new;
end $$;
create trigger professionals_limit before insert or update on public.professionals for each row execute function private.professional_limit();
create function private.validate_plan_change() returns trigger
language plpgsql security definer set search_path = '' as $$
declare maximum integer;
begin
  select professional_limit into maximum from public.plans where id=new.plan;
  if maximum is not null and (select count(*) from public.professionals
    where barbershop_id=new.barbershop_id and status <> 'disabled') > maximum then
    raise exception 'Plano incompatível com a equipe ativa' using errcode='23514';
  end if;
  return new;
end $$;
create trigger subscription_limit before update on public.subscriptions for each row execute function private.validate_plan_change();
create function private.validate_service_image() returns trigger language plpgsql set search_path = '' as $$
begin
  if new.image_path is not null and split_part(new.image_path,'/',1) <> new.barbershop_id::text then
    raise exception 'Imagem de outra empresa' using errcode='23514';
  end if;
  return new;
end $$;
create trigger service_image before insert or update on public.services for each row execute function private.validate_service_image();

-- Serializa bloqueios e reservas da empresa, inclusive bloqueios de dia inteiro.
-- Agenda completa (horários, cancelamento e snapshots) ainda exige RPC futura.
create function private.check_booking_conflict() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  perform 1 from public.barbershops where id=new.barbershop_id for update;
  if tg_table_name='appointments' then
    if new.status <> 'cancelled' and exists(select 1 from public.blocked_times b
      where b.barbershop_id=new.barbershop_id and (b.professional_id is null or b.professional_id=new.professional_id)
      and tstzrange(b.starts_at,b.ends_at,'[)') && tstzrange(new.starts_at,new.occupied_until,'[)')) then
      raise exception 'Horário bloqueado' using errcode='23P01';
    end if;
  else
    if exists(select 1 from public.appointments a where a.barbershop_id=new.barbershop_id
      and (new.professional_id is null or a.professional_id=new.professional_id) and a.status <> 'cancelled'
      and tstzrange(a.starts_at,a.occupied_until,'[)') && tstzrange(new.starts_at,new.ends_at,'[)')) then
      raise exception 'Bloqueio conflita com agendamento' using errcode='23P01';
    end if;
  end if;
  return new;
end $$;
create trigger appointment_conflict before insert or update on public.appointments for each row execute function private.check_booking_conflict();
create trigger blocked_conflict before insert or update on public.blocked_times for each row execute function private.check_booking_conflict();

-- Privilégios de serviço para futuras Edge Functions. Chave secreta nunca no frontend.
grant usage on schema public to anon, authenticated, service_role;
do $$ declare n text; begin
  foreach n in array array['profiles','plans','themes','barbershops','subscriptions','barbershop_members',
    'settings','customers','customer_notes','professionals','services','professional_services','business_hours',
    'professional_schedules','appointments','appointment_notes','blocked_times','payments','notification_templates',
    'notifications','whatsapp_connections','whatsapp_messages'] loop
    execute format('grant select,insert,update,delete on public.%I to service_role',n);
  end loop;
end $$;
grant select,insert on public.audit_logs to service_role;
create function private.audit_support() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  insert into public.audit_logs(barbershop_id,actor_id,action,entity_table,entity_id)
    values(new.barbershop_id,new.admin_id,case when tg_op='INSERT' then 'support_started' else 'support_updated' end,
      'support_sessions',new.id::text);
  return new;
end $$;
create trigger support_audit after insert or update on private.support_sessions for each row execute function private.audit_support();
revoke execute on all functions in schema private from public, anon;
-- Nenhum bypass de suporte é implementado nesta etapa, nem para platform_admins.
commit;
