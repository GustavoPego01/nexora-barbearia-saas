begin;
create index wa_conversation_pending on private.whatsapp_inbox(barbershop_id,sender,received_at,id)
 where state in ('pending','processing');

create or replace function public.wa_claim() returns jsonb language plpgsql security definer set search_path='' as $$
declare result jsonb;
begin
 update private.whatsapp_inbox set state='failed',locked_until=null
 where state in ('pending','processing') and attempts>=5 and (locked_until is null or locked_until<now());
 with picked as (
 select i.id from private.whatsapp_inbox i
 join public.whatsapp_connections w on w.barbershop_id=i.barbershop_id and w.status='connected'
 join private.whatsapp_credentials k on k.barbershop_id=i.barbershop_id
 where (i.state='pending' or (i.state='processing' and i.locked_until<now())) and i.attempts<5
 and private.tenant_active(i.barbershop_id)
 and not exists(select 1 from private.whatsapp_inbox older
   where older.barbershop_id=i.barbershop_id and older.sender=i.sender and older.state in ('pending','processing')
   and (older.received_at,older.id)<(i.received_at,i.id))
 order by i.received_at,i.id for update of i skip locked limit 5
 ), claimed as (
 update private.whatsapp_inbox i set state='processing',locked_until=now()+interval '5 minutes',attempts=attempts+1
 from picked p where i.id=p.id returning i.*)
 select jsonb_agg(to_jsonb(c)||jsonb_build_object('phone_number_id',w.phone_number_id,'token',k.encrypted_token) order by c.received_at,c.id)
 into result from claimed c join public.whatsapp_connections w on w.barbershop_id=c.barbershop_id
 join private.whatsapp_credentials k on k.barbershop_id=c.barbershop_id;
 return coalesce(result,'[]'::jsonb);
end $$;

create or replace function public.wa_finish(inbox_id uuid, successful boolean) returns void language plpgsql security definer set search_path='' as $$
begin
 update private.whatsapp_inbox set state=case when successful then 'done' when attempts>=5 then 'failed' else 'pending' end,locked_until=null
 where id=inbox_id and state='processing';
end $$;

create function public.wa_delivery_allowed(tenant uuid, phone text, ciphertext text, delivery uuid, notification boolean default false) returns boolean language sql stable security definer set search_path='' as $$
 select private.tenant_active($1) and exists(
  select 1 from public.whatsapp_connections w join private.whatsapp_credentials k on k.barbershop_id=w.barbershop_id
  where w.barbershop_id=$1 and w.status='connected' and w.phone_number_id=$2 and k.encrypted_token=$3)
 and case when $5 then exists(select 1 from public.notifications where barbershop_id=$1 and id=$4 and status='processing')
 else exists(select 1 from private.whatsapp_inbox where barbershop_id=$1 and id=$4 and state='processing') end;
$$;
revoke all on function public.wa_delivery_allowed(uuid,text,text,uuid,boolean) from public,anon,authenticated;
grant execute on function public.wa_delivery_allowed(uuid,text,text,uuid,boolean) to service_role;

create function public.wa_disconnect(tenant uuid) returns void language plpgsql security definer set search_path='' as $$
begin
 if not private.has_role(tenant,array['owner']::public.member_role[]) then raise exception 'Acesso negado' using errcode='42501';end if;
 update public.whatsapp_connections set status='disconnected',phone_number_id=null,business_account_id=null,connected_at=null where barbershop_id=tenant;
 delete from private.whatsapp_credentials where barbershop_id=tenant;
 delete from private.whatsapp_auth_states where barbershop_id=tenant;
 delete from private.whatsapp_sessions where barbershop_id=tenant;
 update private.whatsapp_inbox set state='failed',locked_until=null where barbershop_id=tenant and state in ('pending','processing');
 update public.notifications set status='cancelled' where barbershop_id=tenant and status in ('pending','processing');
end $$;
revoke all on function public.wa_disconnect(uuid) from public,anon;
grant execute on function public.wa_disconnect(uuid) to authenticated;

create function public.appointment_payment_methods(tenant uuid) returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
 if not private.has_role(tenant,array['owner','manager','receptionist','professional']::public.member_role[]) then raise exception 'Acesso negado' using errcode='42501';end if;
 return (select to_jsonb(accepted_payments) from public.settings where barbershop_id=tenant);
end $$;
revoke all on function public.appointment_payment_methods(uuid) from public,anon;
grant execute on function public.appointment_payment_methods(uuid) to authenticated;
create or replace function public.wa_claim_notifications() returns jsonb language plpgsql security definer set search_path='' as $$
declare result jsonb;
begin
 update public.notifications set status='failed',processing_started_at=null where status='processing' and attempts>=5 and processing_started_at<now()-interval '5 minutes';
 with picked as (
 select n.id from public.notifications n join public.notification_templates t on t.barbershop_id=n.barbershop_id and t.event=n.event
 join public.whatsapp_connections w on w.barbershop_id=n.barbershop_id
 where (n.status='pending' or (n.status='processing' and n.processing_started_at<now()-interval '5 minutes'))
 and n.scheduled_at<=now() and n.attempts<5 and t.enabled and t.meta_name is not null and w.status='connected' and private.tenant_active(n.barbershop_id)
 order by n.scheduled_at for update of n skip locked limit 5),
 claimed as (update public.notifications n set status='processing',processing_started_at=now(),attempts=attempts+1 from picked p where n.id=p.id returning n.*)
 select jsonb_agg(jsonb_build_object('id',n.id,'tenant',n.barbershop_id,'phone',c.phone,'customer',c.name,'service',s.name,'professional',p.name,
 'date',to_char(a.starts_at at time zone b.timezone,'DD/MM/YYYY'),'time',to_char(a.starts_at at time zone b.timezone,'HH24:MI'),
 'shop',b.name,'meta_name',t.meta_name,'meta_language',t.meta_language,'body',t.body,'phone_id',w.phone_number_id,'token',k.encrypted_token))
 into result
 from claimed n join public.appointments a on a.id=n.appointment_id join public.customers c on c.id=a.customer_id
 join public.professionals p on p.id=a.professional_id join public.services s on s.id=a.service_id join public.barbershops b on b.id=n.barbershop_id
 join public.notification_templates t on t.barbershop_id=n.barbershop_id and t.event=n.event
 join public.whatsapp_connections w on w.barbershop_id=n.barbershop_id join private.whatsapp_credentials k on k.barbershop_id=n.barbershop_id;
 return coalesce(result,'[]'::jsonb);
end $$;

commit;
