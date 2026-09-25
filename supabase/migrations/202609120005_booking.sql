begin;
create function public.public_catalog(shop_slug text) returns jsonb language sql stable security definer set search_path='' as $$
 select jsonb_build_object('shop',jsonb_build_object('id',b.id,'name',b.name,'slug',b.slug,'description',b.description,
 'address',b.address,'city',b.city,'phone',b.phone,'whatsapp',b.whatsapp,'instagram',b.instagram,'maps_url',b.maps_url,
 'theme',b.theme,'primary_color',b.primary_color,'secondary_color',b.secondary_color,'welcome_message',b.welcome_message),
 'services',coalesce((select jsonb_agg(jsonb_build_object('id',s.id,'name',s.name,'description',s.description,
 'price_cents',s.price_cents,'duration_minutes',s.duration_minutes)) from public.services s where s.barbershop_id=b.id and s.is_active),'[]'::jsonb),
 'professionals',coalesce((select jsonb_agg(jsonb_build_object('id',p.id,'name',p.name,'specialties',p.specialties))
 from public.professionals p where p.barbershop_id=b.id and p.status='available'),'[]'::jsonb))
 from public.barbershops b where b.slug=shop_slug and b.is_published and private.tenant_active(b.id);
$$;
create function private.slot_available(tenant uuid, professional uuid, service uuid, starts timestamptz) returns boolean
language plpgsql stable security definer set search_path='' as $$
declare local_start timestamp; local_end timestamp; finish timestamptz; shop public.barbershops; opts public.settings;
 s public.services; p public.professionals; day integer; first_min integer; last_min integer;
begin
 select * into shop from public.barbershops where id=tenant;
 select * into opts from public.settings where barbershop_id=tenant;
 select * into s from public.services where barbershop_id=tenant and id=service and is_active;
 select * into p from public.professionals where barbershop_id=tenant and id=professional and status='available';
 if s.id is null or p.id is null or opts.barbershop_id is null or not private.tenant_active(tenant) then return false; end if;
 if not exists(select 1 from public.professional_services where barbershop_id=tenant and professional_id=professional and service_id=service) then return false; end if;
 if starts < now()+opts.booking_notice_minutes*interval '1 minute' or starts>now()+opts.booking_horizon_days*interval '1 day' then return false; end if;
 finish:=starts+(s.duration_minutes+p.buffer_minutes)*interval '1 minute';
 local_start:=starts at time zone shop.timezone; local_end:=finish at time zone shop.timezone;
 if local_start::date <> local_end::date or extract(second from local_start)<>0 then return false; end if;
 day:=extract(dow from local_start); first_min:=extract(hour from local_start)*60+extract(minute from local_start);
 last_min:=extract(hour from local_end)*60+extract(minute from local_end);
 if first_min % opts.slot_minutes<>0 then return false; end if;
 return exists(select 1 from public.business_hours h where h.barbershop_id=tenant and h.weekday=day and h.start_minute<=first_min and h.end_minute>=last_min)
 and exists(select 1 from public.professional_schedules h where h.barbershop_id=tenant and h.professional_id=professional and h.weekday=day and h.start_minute<=first_min and h.end_minute>=last_min)
 and not exists(select 1 from public.blocked_times t where t.barbershop_id=tenant and (t.professional_id is null or t.professional_id=professional)
 and tstzrange(t.starts_at,t.ends_at,'[)') && tstzrange(starts,finish,'[)'))
 and not exists(select 1 from public.appointments a where a.barbershop_id=tenant and a.professional_id=professional and a.status<>'cancelled'
 and tstzrange(a.starts_at,a.occupied_until,'[)') && tstzrange(starts,finish,'[)'));
end $$;
create function public.available_slots(tenant uuid, service uuid, booking_date date, professional uuid default null) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare zone text; step integer; answer jsonb;
begin
 select b.timezone,s.slot_minutes into zone,step from public.barbershops b join public.settings s on s.barbershop_id=b.id
 where b.id=tenant and private.tenant_active(tenant) and (b.is_published or private.has_role(tenant,array['owner','manager','receptionist']::public.member_role[]));
 if zone is null or booking_date < (now() at time zone zone)::date or booking_date > (now() at time zone zone)::date+365 then return '[]'; end if;
 select coalesce(jsonb_agg(jsonb_build_object('starts_at',t.starts,'professional_id',p.id,'professional_name',p.name) order by t.starts,p.name),'[]'::jsonb) into answer
 from public.professionals p cross join lateral
 (select (booking_date::timestamp + n*interval '1 minute') at time zone zone as starts from generate_series(0,1439,step) n) t
 where p.barbershop_id=tenant and p.status='available' and (professional is null or p.id=professional)
 and private.slot_available(tenant,p.id,service,t.starts);
 return answer;
end $$;
create function public.book_appointment(tenant uuid, service uuid, professional uuid, starts timestamptz,
 customer_name text, customer_phone text, customer uuid default null, existing_appointment uuid default null) returns uuid
language plpgsql security definer set search_path='' as $$
declare staff boolean; person uuid; result uuid; s public.services; p public.professionals; old public.appointments; cancel_hours integer;
begin
 if auth.uid() is null then raise exception 'Faça login para agendar' using errcode='42501'; end if;
 perform 1 from public.barbershops where id=tenant for update;
 staff:=private.has_role(tenant,array['owner','manager','receptionist']::public.member_role[]);
 if not staff and not exists(select 1 from public.barbershops where id=tenant and is_published) then raise exception 'Agendamento indisponível'; end if;
 if existing_appointment is not null then
 select * into old from public.appointments where id=existing_appointment and barbershop_id=tenant for update;
 select cancellation_hours into cancel_hours from public.settings where barbershop_id=tenant;
 if old.id is null or old.status not in ('scheduled','confirmed') or (not staff and (not private.owns_customer(tenant,old.customer_id)
 or old.starts_at<now()+cancel_hours*interval '1 hour')) then raise exception 'Remarcação não permitida' using errcode='42501'; end if;
 update public.appointments set status='cancelled' where id=old.id;
 end if;
 if not private.slot_available(tenant,professional,service,starts) then raise exception 'Horário indisponível. Escolha outro horário.' using errcode='23P01'; end if;
 if existing_appointment is not null then person:=old.customer_id;
 elsif staff and customer is not null then
 select id into person from public.customers where id=customer and barbershop_id=tenant;
 if person is null then raise exception 'Cliente inválido'; end if;
 elsif staff then
 insert into public.customers(barbershop_id,name,phone) values(tenant,customer_name,customer_phone) returning id into person;
 else
 insert into public.customers(barbershop_id,user_id,name,phone) values(tenant,auth.uid(),customer_name,customer_phone)
 on conflict(barbershop_id,user_id) do update set name=excluded.name,phone=excluded.phone returning id into person;
 end if;
 select * into s from public.services where id=service and barbershop_id=tenant;
 select * into p from public.professionals where id=professional and barbershop_id=tenant;
 if existing_appointment is null then
 insert into public.appointments(barbershop_id,customer_id,professional_id,service_id,starts_at,ends_at,occupied_until,
 price_cents,duration_minutes,commission_percent,source)
 values(tenant,person,professional,service,starts,starts+s.duration_minutes*interval '1 minute',starts+(s.duration_minutes+p.buffer_minutes)*interval '1 minute',
 s.price_cents,s.duration_minutes,p.commission_percent,case when staff then 'panel' else 'public' end) returning id into result;
 else
 update public.appointments set professional_id=professional,service_id=service,starts_at=starts,
 ends_at=starts+s.duration_minutes*interval '1 minute',occupied_until=starts+(s.duration_minutes+p.buffer_minutes)*interval '1 minute',
 price_cents=s.price_cents,duration_minutes=s.duration_minutes,commission_percent=p.commission_percent,status='scheduled' where id=old.id returning id into result;
 end if;
 return result;
end $$;
create function public.appointment_action(appointment uuid, new_status public.appointment_status, method public.payment_method default null) returns void
language plpgsql security definer set search_path='' as $$
declare a public.appointments; staff boolean; cancel_hours integer;
begin
 select * into a from public.appointments where id=appointment;
 if a.id is null then raise exception 'Agendamento não encontrado'; end if;
 perform 1 from public.barbershops where id=a.barbershop_id for update;
 select * into a from public.appointments where id=appointment for update;
 staff:=private.has_role(a.barbershop_id,array['owner','manager','receptionist']::public.member_role[])
 or private.owns_professional(a.barbershop_id,a.professional_id);
 select cancellation_hours into cancel_hours from public.settings where barbershop_id=a.barbershop_id;
 if not staff and not (new_status='cancelled' and private.owns_customer(a.barbershop_id,a.customer_id)
 and a.starts_at>=now()+cancel_hours*interval '1 hour') then raise exception 'Ação não permitida' using errcode='42501'; end if;
 if a.status in ('completed','cancelled','no_show') then raise exception 'Atendimento encerrado'; end if;
 if new_status='scheduled' then raise exception 'Use remarcação'; end if;
 if new_status='completed' and (method is null or not method=any((select accepted_payments from public.settings where barbershop_id=a.barbershop_id))) then raise exception 'Escolha uma forma de pagamento aceita'; end if;
 update public.appointments set status=new_status where id=appointment;
 if new_status='completed' then
 insert into public.payments(barbershop_id,appointment_id,amount_cents,method) values(a.barbershop_id,a.id,a.price_cents,method);
 end if;
end $$;
create function public.agenda(tenant uuid, from_date timestamptz, until_date timestamptz) returns jsonb
language plpgsql stable security definer set search_path='' as $$
begin
 if auth.uid() is null or until_date-from_date>interval '366 days' then raise exception 'Consulta inválida' using errcode='42501'; end if;
 return coalesce((select jsonb_agg(jsonb_build_object('id',a.id,'barbershop_id',a.barbershop_id,'shop_name',b.name,'slug',b.slug,
 'customer_id',c.id,'customer_name',c.name,'customer_phone',c.phone,'professional_id',p.id,'professional_name',p.name,
 'service_id',s.id,'service_name',s.name,'starts_at',a.starts_at,'ends_at',a.ends_at,'status',a.status,'price_cents',a.price_cents) order by a.starts_at)
 from public.appointments a join public.customers c on c.id=a.customer_id join public.professionals p on p.id=a.professional_id
 join public.services s on s.id=a.service_id join public.barbershops b on b.id=a.barbershop_id
 where (tenant is null or a.barbershop_id=tenant) and a.starts_at>=from_date and a.starts_at<until_date
 and (private.has_role(a.barbershop_id,array['owner','manager','receptionist']::public.member_role[])
 or private.owns_professional(a.barbershop_id,a.professional_id) or private.owns_customer(a.barbershop_id,a.customer_id))),'[]'::jsonb);
end $$;
create function public.finance_report(tenant uuid, from_date timestamptz, until_date timestamptz) returns jsonb
language plpgsql stable security definer set search_path='' as $$
begin
 if not private.has_role(tenant,array['owner','manager','receptionist']::public.member_role[]) then raise exception 'Acesso negado' using errcode='42501'; end if;
 return coalesce((select jsonb_agg(jsonb_build_object('id',p.id,'paid_at',p.paid_at,'amount_cents',p.amount_cents,'method',p.method,
 'customer_name',c.name,'professional_name',r.name,'service_name',s.name,'commission_cents',round(p.amount_cents*a.commission_percent/100)))
 from public.payments p join public.appointments a on a.id=p.appointment_id join public.customers c on c.id=a.customer_id
 join public.professionals r on r.id=a.professional_id join public.services s on s.id=a.service_id
 where p.barbershop_id=tenant and p.paid_at>=from_date and p.paid_at<until_date),'[]'::jsonb);
end $$;
create function public.manage_block(tenant uuid, starts timestamptz, ends timestamptz, reason text, professional uuid default null, block_id uuid default null) returns void
language plpgsql security definer set search_path='' as $$
begin
 if not private.has_role(tenant,array['owner','manager']::public.member_role[]) then raise exception 'Acesso negado' using errcode='42501'; end if;
 perform 1 from public.barbershops where id=tenant for update;
 if block_id is not null then delete from public.blocked_times where id=block_id and barbershop_id=tenant;
 else insert into public.blocked_times(barbershop_id,professional_id,starts_at,ends_at,reason) values(tenant,professional,starts,ends,reason); end if;
end $$;
revoke all on function private.slot_available(uuid,uuid,uuid,timestamptz) from public,anon,authenticated;
revoke all on function public.public_catalog(text),public.available_slots(uuid,uuid,date,uuid),
 public.book_appointment(uuid,uuid,uuid,timestamptz,text,text,uuid,uuid),public.appointment_action(uuid,public.appointment_status,public.payment_method),
 public.agenda(uuid,timestamptz,timestamptz),public.finance_report(uuid,timestamptz,timestamptz),public.manage_block(uuid,timestamptz,timestamptz,text,uuid,uuid) from public,anon;
grant execute on function public.public_catalog(text),public.available_slots(uuid,uuid,date,uuid) to anon,authenticated;
grant execute on function public.book_appointment(uuid,uuid,uuid,timestamptz,text,text,uuid,uuid),public.appointment_action(uuid,public.appointment_status,public.payment_method),
 public.agenda(uuid,timestamptz,timestamptz),public.finance_report(uuid,timestamptz,timestamptz),public.manage_block(uuid,timestamptz,timestamptz,text,uuid,uuid) to authenticated;
commit;
