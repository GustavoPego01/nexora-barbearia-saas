begin;
insert into auth.users(id) values('91000000-0000-0000-0000-000000000001'),('91000000-0000-0000-0000-000000000002');
insert into public.barbershops(id,name,slug) values
 ('92000000-0000-0000-0000-000000000001','Fila A','teste-fila-a'),('92000000-0000-0000-0000-000000000002','Fila B','teste-fila-b');
insert into public.subscriptions(barbershop_id,plan,status) select id,'pro','active' from public.barbershops where slug in ('teste-fila-a','teste-fila-b');
insert into public.barbershop_members(barbershop_id,user_id,role) values
 ('92000000-0000-0000-0000-000000000001','91000000-0000-0000-0000-000000000001','owner'),
 ('92000000-0000-0000-0000-000000000002','91000000-0000-0000-0000-000000000002','owner');
insert into public.whatsapp_connections(barbershop_id,status,phone_number_id) values
 ('92000000-0000-0000-0000-000000000001','connected','delivery-test-a'),('92000000-0000-0000-0000-000000000002','connected','delivery-test-b');
insert into private.whatsapp_credentials values
 ('92000000-0000-0000-0000-000000000001','fake-cipher-a',now()),('92000000-0000-0000-0000-000000000002','fake-cipher-b',now());
insert into private.whatsapp_inbox(barbershop_id,message_id,sender,body,received_at) values
 ('92000000-0000-0000-0000-000000000001','delivery-first','5511000000001','1',now()-interval '3 seconds'),
 ('92000000-0000-0000-0000-000000000001','delivery-second','5511000000001','2',now()-interval '2 seconds'),
 ('92000000-0000-0000-0000-000000000002','delivery-other-tenant','5511000000001','1',now()-interval '1 second');
do $$ declare result jsonb; first_id uuid; begin
 result:=public.wa_claim();
 if not exists(select 1 from jsonb_array_elements(result) x where x->>'message_id'='delivery-first') or
 exists(select 1 from jsonb_array_elements(result) x where x->>'message_id'='delivery-second') or
 not exists(select 1 from jsonb_array_elements(result) x where x->>'message_id'='delivery-other-tenant') then raise exception 'Ordem/isolation incorreta na fila';end if;
 if exists(select 1 from jsonb_array_elements(public.wa_claim()) x where x->>'message_id'='delivery-second') then raise exception 'Conversa em processamento foi ultrapassada';end if;
 select id into first_id from private.whatsapp_inbox where message_id='delivery-first';
 if not public.wa_delivery_allowed('92000000-0000-0000-0000-000000000001','delivery-test-a','fake-cipher-a',first_id) then raise exception 'Entrega válida negada';end if;
 if public.wa_delivery_allowed('92000000-0000-0000-0000-000000000002','delivery-test-b','fake-cipher-b',first_id) then raise exception 'Entrega entre tenants permitida';end if;
 update private.whatsapp_inbox set attempts=5,locked_until=now()-interval '1 minute' where id=first_id;
 result:=public.wa_claim();
 if not exists(select 1 from jsonb_array_elements(result) x where x->>'message_id'='delivery-second') then raise exception 'Tentativas esgotadas bloquearam a conversa';end if;
end $$;
set local role authenticated;
select set_config('request.jwt.claim.sub','91000000-0000-0000-0000-000000000001',true);
do $$ begin
 begin perform public.wa_disconnect('92000000-0000-0000-0000-000000000002');raise exception 'Desconexão cruzada permitida';exception when insufficient_privilege then null;end;
 perform public.wa_disconnect('92000000-0000-0000-0000-000000000001');
end $$;
reset role;
do $$ declare delivery uuid; begin
 select id into delivery from private.whatsapp_inbox where message_id='delivery-second';
 if public.wa_delivery_allowed('92000000-0000-0000-0000-000000000001','delivery-test-a','fake-cipher-a',delivery) then raise exception 'Envio permitido após desconexão';end if;
 perform public.wa_finish(delivery,false);
 if exists(select 1 from private.whatsapp_inbox where id=delivery and state='pending') then raise exception 'Worker reativou envio cancelado';end if;
 if exists(select 1 from private.whatsapp_credentials where barbershop_id='92000000-0000-0000-0000-000000000001') then raise exception 'Credencial não revogada';end if;
 if not exists(select 1 from private.whatsapp_credentials where barbershop_id='92000000-0000-0000-0000-000000000002') then raise exception 'Outra empresa foi alterada';end if;
end $$;
select 'Fila: ordem, isolamento, tentativas esgotadas e desconexão: OK' as result;
rollback;
