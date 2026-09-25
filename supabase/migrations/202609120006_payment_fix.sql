begin;
create or replace function public.appointment_action(appointment uuid, new_status public.appointment_status, method public.payment_method default null) returns void
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
 if new_status='completed' and (method is null or not exists(select 1 from public.settings s where s.barbershop_id=a.barbershop_id and method=any(s.accepted_payments))) then raise exception 'Escolha uma forma de pagamento aceita'; end if;
 update public.appointments set status=new_status where id=appointment;
 if new_status='completed' then
 insert into public.payments(barbershop_id,appointment_id,amount_cents,method) values(a.barbershop_id,a.id,a.price_cents,method);
 end if;
end $$;
commit;
