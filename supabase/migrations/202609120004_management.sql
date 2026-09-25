begin;
create function private.is_admin() returns boolean language sql stable security definer set search_path='' as $$
 select exists(select 1 from private.platform_admins where user_id=auth.uid());
$$;
create function public.session_context() returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
 if auth.uid() is null then raise exception 'Sessão necessária' using errcode='42501'; end if;
 return jsonb_build_object('is_admin',private.is_admin(),'memberships',coalesce((select jsonb_agg(jsonb_build_object(
 'barbershop_id',m.barbershop_id,'role',m.role,'name',b.name,'slug',b.slug,'active',private.tenant_active(b.id),
 'onboarding_completed_at',b.onboarding_completed_at)) from public.barbershop_members m join public.barbershops b on b.id=m.barbershop_id
 where m.user_id=auth.uid() and m.is_active),'[]'::jsonb));
end $$;
create function public.admin_shops() returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
 if not private.is_admin() then raise exception 'Acesso negado' using errcode='42501'; end if;
 return coalesce((select jsonb_agg(jsonb_build_object('id',b.id,'name',b.name,'slug',b.slug,'is_active',b.is_active,
 'plan',s.plan,'status',s.status,'created_at',b.created_at,'phone',b.phone,
 'appointments',(select count(*) from public.appointments a where a.barbershop_id=b.id),
 'members',(select count(*) from public.barbershop_members m where m.barbershop_id=b.id),
 'whatsapp',(select w.status from public.whatsapp_connections w where w.barbershop_id=b.id)))
 from public.barbershops b join public.subscriptions s on s.barbershop_id=b.id),'[]'::jsonb);
end $$;
create function public.admin_create_shop(shop_name text, owner_email text, selected_plan text default 'starter') returns uuid
language plpgsql security definer set search_path='' as $$
declare tenant uuid:=gen_random_uuid(); owner_id uuid; new_slug text;
begin
 if not private.is_admin() then raise exception 'Acesso negado' using errcode='42501'; end if;
 select id into owner_id from auth.users where lower(email)=lower(trim(owner_email)) and email_confirmed_at is not null;
 if owner_id is null then raise exception 'Proprietário deve cadastrar e confirmar seu e-mail antes da liberação'; end if;
 new_slug:=trim(both '-' from regexp_replace(lower(shop_name),'[^a-z0-9]+','-','g'));
 if new_slug='' then new_slug:='barbearia'; end if;
 new_slug:=left(new_slug,85)||'-'||left(tenant::text,8);
 insert into public.barbershops(id,name,slug) values(tenant,shop_name,new_slug);
 insert into public.subscriptions(barbershop_id,plan,status,trial_ends_at) values(tenant,selected_plan,'trial',now()+interval '14 days');
 insert into public.barbershop_members(barbershop_id,user_id,role) values(tenant,owner_id,'owner');
 insert into public.settings(barbershop_id) values(tenant);
 insert into public.whatsapp_connections(barbershop_id) values(tenant);
 return tenant;
end $$;
create function public.admin_update_shop(tenant uuid, selected_plan text, selected_status public.subscription_status) returns void
language plpgsql security definer set search_path='' as $$
begin
 if not private.is_admin() then raise exception 'Acesso negado' using errcode='42501'; end if;
 update public.subscriptions set plan=selected_plan,status=selected_status,
 trial_ends_at=case when selected_status='trial' then now()+interval '14 days' else trial_ends_at end where barbershop_id=tenant;
 if not found then raise exception 'Empresa não encontrada'; end if;
 update public.barbershops set is_active=(selected_status <> 'blocked') where id=tenant;
end $$;
create function public.start_support(tenant uuid, reason text) returns uuid language plpgsql security definer set search_path='' as $$
declare session_id uuid;
begin
 if not private.is_admin() then raise exception 'Acesso negado' using errcode='42501'; end if;
 insert into private.support_sessions(barbershop_id,admin_id,reason,expires_at) values(tenant,auth.uid(),reason,now()+interval '1 hour') returning id into session_id;
 return session_id;
end $$;
create function public.end_support(tenant uuid) returns void language plpgsql security definer set search_path='' as $$
begin
 update private.support_sessions set ended_at=now() where barbershop_id=tenant and admin_id=auth.uid() and ended_at is null;
end $$;
create or replace function private.has_role(tenant uuid, roles public.member_role[]) returns boolean
language sql stable security definer set search_path='' as $$
 select private.tenant_active(tenant) and (exists(select 1 from public.barbershop_members m
 where m.barbershop_id=tenant and m.user_id=auth.uid() and m.is_active and m.role=any(roles))
 or ('owner'::public.member_role=any(roles) and private.is_admin() and exists(select 1 from private.support_sessions s
 where s.barbershop_id=tenant and s.admin_id=auth.uid() and s.ended_at is null and s.expires_at>now())));
$$;
create function public.manage_member(tenant uuid, member_email text, member_role public.member_role, enabled boolean default true) returns void
language plpgsql security definer set search_path='' as $$
declare target uuid;
begin
 if not private.has_role(tenant,array['owner']::public.member_role[]) then raise exception 'Acesso negado' using errcode='42501'; end if;
 select id into target from auth.users where lower(email)=lower(trim(member_email)) and email_confirmed_at is not null;
 if target is null then raise exception 'Usuário precisa cadastrar e confirmar seu e-mail'; end if;
 if target=auth.uid() then raise exception 'Não altere seu próprio vínculo'; end if;
 if exists(select 1 from public.barbershop_members where barbershop_id=tenant and user_id=target and role='owner') then
 raise exception 'Transferência de propriedade exige administrador'; end if;
 insert into public.barbershop_members(barbershop_id,user_id,role,is_active) values(tenant,target,member_role,enabled)
 on conflict(barbershop_id,user_id) do update set role=excluded.role,is_active=excluded.is_active;
end $$;
-- RPC única para substituir vínculos serviço/profissional, com validação de tenant pelas FKs.
create function public.set_professional_services(tenant uuid, professional uuid, service_ids uuid[]) returns void
language plpgsql security definer set search_path='' as $$
begin
 if not private.has_role(tenant,array['owner','manager']::public.member_role[]) then raise exception 'Acesso negado' using errcode='42501'; end if;
 -- Vínculos históricos não são removidos; serviços inativos não aparecem na reserva.
 insert into public.professional_services(barbershop_id,professional_id,service_id)
 select tenant,professional,unnest(service_ids) on conflict do nothing;
end $$;
revoke all on function public.session_context(),public.admin_shops(),public.admin_create_shop(text,text,text),
 public.admin_update_shop(uuid,text,public.subscription_status),public.start_support(uuid,text),public.end_support(uuid),
 public.manage_member(uuid,text,public.member_role,boolean),public.set_professional_services(uuid,uuid,uuid[]) from public,anon;
grant execute on function public.session_context(),public.admin_shops(),public.admin_create_shop(text,text,text),
 public.admin_update_shop(uuid,text,public.subscription_status),public.start_support(uuid,text),public.end_support(uuid),
 public.manage_member(uuid,text,public.member_role,boolean),public.set_professional_services(uuid,uuid,uuid[]) to authenticated;
revoke all on function private.is_admin() from public,anon,authenticated;
commit;
