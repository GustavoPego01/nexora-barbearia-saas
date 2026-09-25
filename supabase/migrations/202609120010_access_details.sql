begin;
create function public.team_members(tenant uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
 if not private.has_role(tenant,array['owner','manager']::public.member_role[]) then raise exception 'Acesso negado' using errcode='42501'; end if;
 return coalesce((select jsonb_agg(jsonb_build_object('id',m.id,'user_id',m.user_id,'role',m.role,'is_active',m.is_active,'name',p.full_name,'email',u.email))
 from public.barbershop_members m join auth.users u on u.id=m.user_id left join public.profiles p on p.id=m.user_id where m.barbershop_id=tenant),'[]');
end $$;
create function public.plan_details(tenant uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
 if not private.has_role(tenant,array['owner']::public.member_role[]) then raise exception 'Acesso negado' using errcode='42501'; end if;
 return (select to_jsonb(s)||jsonb_build_object('professional_limit',p.professional_limit,'professionals',(select count(*) from public.professionals r where r.barbershop_id=tenant and r.status<>'disabled')) from public.subscriptions s join public.plans p on p.id=s.plan where s.barbershop_id=tenant);
end $$;
create function public.complete_onboarding(tenant uuid) returns void language plpgsql security definer set search_path='' as $$
begin
 if not private.has_role(tenant,array['owner']::public.member_role[]) then raise exception 'Acesso negado' using errcode='42501'; end if;
 if not exists(select 1 from public.professionals p join public.professional_services ps on ps.barbershop_id=p.barbershop_id and ps.professional_id=p.id and ps.is_enabled
 join public.services s on s.barbershop_id=p.barbershop_id and s.id=ps.service_id and s.is_active
 join public.professional_schedules h on h.barbershop_id=p.barbershop_id and h.professional_id=p.id
 join public.business_hours b on b.barbershop_id=p.barbershop_id and b.weekday=h.weekday and int4range(b.start_minute,b.end_minute) && int4range(h.start_minute,h.end_minute)
 where p.barbershop_id=tenant and p.status='available') then raise exception 'Vincule um serviço ativo a um profissional disponível e configure horários compatíveis.'; end if;
 update public.barbershops set onboarding_completed_at=now(),onboarding_step=8 where id=tenant;
end $$;
revoke update(onboarding_completed_at) on public.barbershops from authenticated;
create function public.my_commissions(tenant uuid, from_date timestamptz, until_date timestamptz) returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
 return coalesce((select jsonb_agg(jsonb_build_object('id',a.id,'starts_at',a.starts_at,'commission_cents',round(p.amount_cents*a.commission_percent/100)))
 from public.appointments a join public.payments p on p.appointment_id=a.id where a.barbershop_id=tenant and private.own_commission_visible(tenant,a.professional_id)
 and p.paid_at>=from_date and p.paid_at<until_date),'[]');
end $$;
revoke all on function public.team_members(uuid),public.plan_details(uuid),public.complete_onboarding(uuid),public.my_commissions(uuid,timestamptz,timestamptz) from public,anon;
grant execute on function public.team_members(uuid),public.plan_details(uuid),public.complete_onboarding(uuid),public.my_commissions(uuid,timestamptz,timestamptz) to authenticated;
commit;
