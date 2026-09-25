begin;
create table private.whatsapp_credentials(
 barbershop_id uuid primary key references public.barbershops(id), encrypted_token text not null,
 updated_at timestamptz not null default now()
);
create table private.whatsapp_auth_states(
 state_hash text primary key, barbershop_id uuid not null references public.barbershops(id),
 user_id uuid not null references auth.users(id), expires_at timestamptz not null default now()+interval '10 minutes', consumed_at timestamptz
);
create table private.whatsapp_inbox(
 id uuid primary key default gen_random_uuid(), barbershop_id uuid not null references public.barbershops(id),
 message_id text not null unique, sender text not null, body text not null, received_at timestamptz not null default now(),
 state text not null default 'pending' check(state in ('pending','processing','done','failed')),
 attempts int not null default 0, locked_until timestamptz
);
alter table private.whatsapp_credentials enable row level security;
alter table private.whatsapp_auth_states enable row level security;
alter table private.whatsapp_inbox enable row level security;
create index wa_pending on private.whatsapp_inbox(received_at) where state in ('pending','processing');
create function public.wa_begin(tenant uuid, state_hash text) returns void language plpgsql security definer set search_path='' as $$
begin
 if not private.has_role(tenant,array['owner']::public.member_role[]) then raise exception 'Acesso negado' using errcode='42501'; end if;
 delete from private.whatsapp_auth_states where expires_at<now() or (barbershop_id=tenant and user_id=auth.uid());
 insert into private.whatsapp_auth_states(state_hash,barbershop_id,user_id) values(state_hash,tenant,auth.uid());
 update public.whatsapp_connections set status='configuring' where barbershop_id=tenant and status<>'connected';
end $$;
create function public.wa_consume(state text) returns uuid language plpgsql security definer set search_path='' as $$
declare tenant uuid;
begin
 update private.whatsapp_auth_states set consumed_at=now() where state_hash=state and user_id=auth.uid() and consumed_at is null and expires_at>now()
 and private.has_role(barbershop_id,array['owner']::public.member_role[]) returning barbershop_id into tenant;
 if tenant is null then raise exception 'Autorização expirada. Inicie novamente.' using errcode='42501'; end if;
 return tenant;
end $$;
create function public.wa_save(tenant uuid, phone_id text, account_id text, ciphertext text) returns void language plpgsql security definer set search_path='' as $$
begin
 insert into private.whatsapp_credentials(barbershop_id,encrypted_token) values(tenant,ciphertext)
 on conflict(barbershop_id) do update set encrypted_token=excluded.encrypted_token,updated_at=now();
 update public.whatsapp_connections set status='connected',phone_number_id=phone_id,business_account_id=account_id,connected_at=now() where barbershop_id=tenant;
end $$;
create function public.wa_receive(phone_id text, provider_id text, sender_phone text, message_body text) returns void language plpgsql security definer set search_path='' as $$
declare tenant uuid;
begin
 select barbershop_id into tenant from public.whatsapp_connections where phone_number_id=phone_id and status='connected';
 if tenant is null or not private.tenant_active(tenant) then return; end if;
 insert into private.whatsapp_inbox(barbershop_id,message_id,sender,body) values(tenant,provider_id,sender_phone,left(message_body,4096)) on conflict(message_id) do nothing;
end $$;
create function public.wa_claim() returns jsonb language plpgsql security definer set search_path='' as $$
begin
 return coalesce((with picked as (select id from private.whatsapp_inbox where (state='pending' or (state='processing' and locked_until<now())) and attempts<5 order by received_at for update skip locked limit 20),
 claimed as (update private.whatsapp_inbox i set state='processing',locked_until=now()+interval '5 minutes',attempts=attempts+1 from picked p where i.id=p.id returning i.*)
 select jsonb_agg(to_jsonb(c)||jsonb_build_object('phone_number_id',w.phone_number_id,'token',k.encrypted_token,'shop_name',b.name,'slug',b.slug))
 from claimed c join public.whatsapp_connections w on w.barbershop_id=c.barbershop_id join private.whatsapp_credentials k on k.barbershop_id=c.barbershop_id join public.barbershops b on b.id=c.barbershop_id
 where private.tenant_active(c.barbershop_id)),'[]');
end $$;
create function public.wa_finish(inbox_id uuid, successful boolean) returns void language plpgsql security definer set search_path='' as $$
begin
 update private.whatsapp_inbox set state=case when successful then 'done' when attempts>=5 then 'failed' else 'pending' end,locked_until=null where id=inbox_id;
end $$;
create function private.queue_notifications() returns trigger language plpgsql security definer set search_path='' as $$
declare event_name text; cfg public.settings;
begin
 select * into cfg from public.settings where barbershop_id=new.barbershop_id;
 if tg_op='INSERT' then event_name:='confirmation';
 elsif new.status='cancelled' then event_name:='cancellation';
 elsif new.status='completed' then event_name:='thanks';
 elsif new.starts_at is distinct from old.starts_at then event_name:='reschedule';
 else return new; end if;
 if tg_op='UPDATE' then update public.notifications set status='cancelled' where barbershop_id=new.barbershop_id and appointment_id=new.id and status='pending'; end if;
 if exists(select 1 from public.notification_templates where barbershop_id=new.barbershop_id and event=event_name and enabled) then
 insert into public.notifications(barbershop_id,appointment_id,event,scheduled_at,deduplication_key)
 values(new.barbershop_id,new.id,event_name,now(),new.id::text||':'||event_name||':'||new.updated_at::text) on conflict do nothing;
 end if;
 if new.status in ('scheduled','confirmed') and exists(select 1 from public.notification_templates where barbershop_id=new.barbershop_id and event='reminder' and enabled) then
 if cfg.reminder_24h and new.starts_at>now()+interval '24 hours' then
 insert into public.notifications(barbershop_id,appointment_id,event,scheduled_at,deduplication_key) values(new.barbershop_id,new.id,'reminder',new.starts_at-interval '24 hours',new.id::text||':24h:'||new.starts_at::text) on conflict do nothing; end if;
 if cfg.reminder_2h and new.starts_at>now()+interval '2 hours' then
 insert into public.notifications(barbershop_id,appointment_id,event,scheduled_at,deduplication_key) values(new.barbershop_id,new.id,'reminder',new.starts_at-interval '2 hours',new.id::text||':2h:'||new.starts_at::text) on conflict do nothing; end if;
 end if;
 return new;
end $$;
create trigger appointment_notifications after insert or update on public.appointments for each row execute function private.queue_notifications();
revoke all on function public.wa_begin(uuid,text),public.wa_consume(text),public.wa_save(uuid,text,text,text),public.wa_receive(text,text,text,text),public.wa_claim(),public.wa_finish(uuid,boolean),private.queue_notifications() from public,anon,authenticated;
grant execute on function public.wa_begin(uuid,text),public.wa_consume(text) to authenticated;
grant execute on function public.wa_save(uuid,text,text,text),public.wa_receive(text,text,text,text),public.wa_claim(),public.wa_finish(uuid,boolean) to service_role;
commit;
