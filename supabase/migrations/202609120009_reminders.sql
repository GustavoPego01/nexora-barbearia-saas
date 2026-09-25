begin;
alter table public.notification_templates add column meta_name text check(meta_name is null or meta_name ~ '^[a-z0-9_]{1,512}$');
alter table public.notification_templates add column meta_language text not null default 'pt_BR';
grant update(meta_name,meta_language) on public.notification_templates to authenticated;
alter table public.notifications add column processing_started_at timestamptz;
create function public.wa_claim_notifications() returns jsonb language plpgsql security definer set search_path='' as $$
begin
 return coalesce((with picked as (
 select n.id from public.notifications n join public.notification_templates t on t.barbershop_id=n.barbershop_id and t.event=n.event
 join public.whatsapp_connections w on w.barbershop_id=n.barbershop_id
 where (n.status='pending' or (n.status='processing' and n.processing_started_at<now()-interval '5 minutes'))
 and n.scheduled_at<=now() and n.attempts<5 and t.enabled and t.meta_name is not null and w.status='connected' and private.tenant_active(n.barbershop_id)
 order by n.scheduled_at for update of n skip locked limit 20),
 claimed as (update public.notifications n set status='processing',processing_started_at=now(),attempts=attempts+1 from picked p where n.id=p.id returning n.*)
 select jsonb_agg(jsonb_build_object('id',n.id,'tenant',n.barbershop_id,'phone',c.phone,'customer',c.name,'service',s.name,'professional',p.name,
 'date',to_char(a.starts_at at time zone b.timezone,'DD/MM/YYYY'),'time',to_char(a.starts_at at time zone b.timezone,'HH24:MI'),
 'shop',b.name,'meta_name',t.meta_name,'meta_language',t.meta_language,'body',t.body,'phone_id',w.phone_number_id,'token',k.encrypted_token))
 from claimed n join public.appointments a on a.id=n.appointment_id join public.customers c on c.id=a.customer_id
 join public.professionals p on p.id=a.professional_id join public.services s on s.id=a.service_id join public.barbershops b on b.id=n.barbershop_id
 join public.notification_templates t on t.barbershop_id=n.barbershop_id and t.event=n.event
 join public.whatsapp_connections w on w.barbershop_id=n.barbershop_id join private.whatsapp_credentials k on k.barbershop_id=n.barbershop_id),'[]');
end $$;
create function public.wa_finish_notification(notification uuid, successful boolean) returns void language plpgsql security definer set search_path='' as $$
begin
 update public.notifications set status=case when successful then 'sent' when attempts>=5 then 'failed' else 'pending' end,processing_started_at=null where id=notification and status='processing';
end $$;
revoke all on function public.wa_claim_notifications(),public.wa_finish_notification(uuid,boolean) from public,anon,authenticated;
grant execute on function public.wa_claim_notifications(),public.wa_finish_notification(uuid,boolean) to service_role;
commit;
