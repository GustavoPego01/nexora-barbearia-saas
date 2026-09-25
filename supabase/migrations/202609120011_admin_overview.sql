begin;
create table private.platform_access_logs(id uuid primary key default gen_random_uuid(),actor_id uuid not null,action text not null,created_at timestamptz not null default now());
alter table private.platform_access_logs enable row level security;
create function public.admin_overview() returns jsonb language plpgsql security definer set search_path='' as $$
begin
 if not private.is_admin() then raise exception 'Acesso negado' using errcode='42501'; end if;
 insert into private.platform_access_logs(actor_id,action) values(auth.uid(),'admin_overview');
 return jsonb_build_object('users',coalesce((select jsonb_agg(jsonb_build_object('id',u.id,'email',u.email,'created_at',u.created_at,'last_sign_in_at',u.last_sign_in_at)) from auth.users u),'[]'::jsonb),
 'logs',coalesce((select jsonb_agg(to_jsonb(l)) from (select a.id,a.barbershop_id,b.name as shop_name,a.actor_id,a.action,a.entity_table,a.created_at from public.audit_logs a join public.barbershops b on b.id=a.barbershop_id order by a.created_at desc limit 200)l),'[]'::jsonb));
end $$;
revoke all on function public.admin_overview() from public,anon;
grant execute on function public.admin_overview() to authenticated;
commit;
