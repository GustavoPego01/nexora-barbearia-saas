begin;
alter table public.professional_services add column is_enabled boolean not null default true;
create or replace function public.set_professional_services(tenant uuid, professional uuid, service_ids uuid[]) returns void
language plpgsql security definer set search_path='' as $$
begin
 if not private.has_role(tenant,array['owner','manager']::public.member_role[]) then raise exception 'Acesso negado' using errcode='42501'; end if;
 update public.professional_services set is_enabled=false where barbershop_id=tenant and professional_id=professional;
 insert into public.professional_services(barbershop_id,professional_id,service_id,is_enabled)
 select tenant,professional,unnest(service_ids),true
 on conflict(barbershop_id,professional_id,service_id) do update set is_enabled=true;
end $$;
create function public.professional_service_ids(tenant uuid, professional uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
 if not private.has_role(tenant,array['owner','manager']::public.member_role[]) then raise exception 'Acesso negado' using errcode='42501'; end if;
 return coalesce((select jsonb_agg(service_id) from public.professional_services where barbershop_id=tenant and professional_id=professional and is_enabled),'[]');
end $$;
create function public.customer_summary(tenant uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
 if not private.has_role(tenant,array['owner','manager','receptionist']::public.member_role[]) then raise exception 'Acesso negado' using errcode='42501'; end if;
 return coalesce((select jsonb_agg(to_jsonb(c)||jsonb_build_object('visits',(select count(*) from public.appointments a where a.barbershop_id=tenant and a.customer_id=c.id and a.status='completed'),
 'last_visit',(select max(a.starts_at) from public.appointments a where a.barbershop_id=tenant and a.customer_id=c.id and a.status='completed'),
 'spent_cents',(select coalesce(sum(p.amount_cents),0) from public.payments p join public.appointments a on a.id=p.appointment_id where a.barbershop_id=tenant and a.customer_id=c.id)))
 from public.customers c where c.barbershop_id=tenant),'[]');
end $$;
create function public.customer_history(tenant uuid, customer uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
 if not private.has_role(tenant,array['owner','manager','receptionist']::public.member_role[]) then raise exception 'Acesso negado' using errcode='42501'; end if;
 return jsonb_build_object('appointments',coalesce((select jsonb_agg(jsonb_build_object('id',a.id,'starts_at',a.starts_at,'service',s.name,'status',a.status,'price_cents',a.price_cents) order by a.starts_at desc)
 from public.appointments a join public.services s on s.id=a.service_id where a.barbershop_id=tenant and a.customer_id=customer),'[]'::jsonb),
 'notes',coalesce((select jsonb_agg(jsonb_build_object('id',n.id,'body',n.body,'created_at',n.created_at) order by n.created_at desc) from public.customer_notes n where n.barbershop_id=tenant and n.customer_id=customer),'[]'::jsonb));
end $$;
create function private.public_image(bucket text, path text) returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.barbershops b where b.is_published and private.tenant_active(b.id) and
 (bucket='logos' and b.logo_path=path or bucket='covers' and b.cover_path=path
 or bucket='professionals' and exists(select 1 from public.professionals p where p.barbershop_id=b.id and p.status='available' and p.photo_path=path)
 or bucket='service-images' and exists(select 1 from public.services s where s.barbershop_id=b.id and s.is_active and s.image_path=path)));
$$;
grant usage on schema private to anon;
revoke execute on function private.public_image(text,text) from public;
grant execute on function private.public_image(text,text) to anon,authenticated;
create policy published_images_read on storage.objects for select to anon,authenticated using(private.public_image(bucket_id,name));
revoke all on function public.professional_service_ids(uuid,uuid),public.customer_summary(uuid),public.customer_history(uuid,uuid) from public,anon;
grant execute on function public.professional_service_ids(uuid,uuid),public.customer_summary(uuid),public.customer_history(uuid,uuid) to authenticated;
create or replace function public.public_catalog(shop_slug text) returns jsonb language sql stable security definer set search_path='' as $$
 select jsonb_build_object('shop',jsonb_build_object('id',b.id,'name',b.name,'slug',b.slug,'description',b.description,
 'address',b.address,'city',b.city,'phone',b.phone,'whatsapp',b.whatsapp,'instagram',b.instagram,'maps_url',b.maps_url,
 'logo_path',b.logo_path,'cover_path',b.cover_path,'theme',b.theme,'primary_color',b.primary_color,'secondary_color',b.secondary_color,'welcome_message',b.welcome_message),
 'services',coalesce((select jsonb_agg(jsonb_build_object('id',s.id,'name',s.name,'description',s.description,
 'image_path',s.image_path,'price_cents',s.price_cents,'duration_minutes',s.duration_minutes)) from public.services s where s.barbershop_id=b.id and s.is_active),'[]'::jsonb),
 'professionals',coalesce((select jsonb_agg(jsonb_build_object('id',p.id,'name',p.name,'specialties',p.specialties,'photo_path',p.photo_path))
 from public.professionals p where p.barbershop_id=b.id and p.status='available'),'[]'::jsonb))
 from public.barbershops b where b.slug=shop_slug and b.is_published and private.tenant_active(b.id);
$$;
create or replace function private.slot_available(tenant uuid, professional uuid, service uuid, starts timestamptz) returns boolean
language plpgsql stable security definer set search_path='' as $$
declare local_start timestamp; local_end timestamp; finish timestamptz; shop public.barbershops; opts public.settings;
 s public.services; p public.professionals; day integer; first_min integer; last_min integer;
begin
 select * into shop from public.barbershops where id=tenant;
 select * into opts from public.settings where barbershop_id=tenant;
 select * into s from public.services where barbershop_id=tenant and id=service and is_active;
 select * into p from public.professionals where barbershop_id=tenant and id=professional and status='available';
 if s.id is null or p.id is null or opts.barbershop_id is null or not private.tenant_active(tenant) then return false; end if;
 if not exists(select 1 from public.professional_services where barbershop_id=tenant and professional_id=professional and service_id=service and is_enabled) then return false; end if;
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
commit;
