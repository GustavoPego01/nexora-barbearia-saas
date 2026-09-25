-- DEMO LOCAL SOMENTE. Não cria usuários Auth, senhas ou administradores.
-- supabase db push não executa este arquivo. O dono será vinculado pelo fluxo administrativo futuro.
begin;
insert into public.barbershops(id,name,slug,description) values
 ('10000000-0000-0000-0000-000000000001','Barbearia Prime','barbearia-prime','Barbearia de demonstração local.');
insert into public.subscriptions(barbershop_id,plan,status) values
 ('10000000-0000-0000-0000-000000000001','pro','active');
insert into public.settings(barbershop_id) values ('10000000-0000-0000-0000-000000000001');
insert into public.whatsapp_connections(barbershop_id) values ('10000000-0000-0000-0000-000000000001');
insert into public.professionals(id,barbershop_id,name) values
 ('20000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000001','João'),
 ('20000000-0000-0000-0000-000000000002','10000000-0000-0000-0000-000000000001','Carlos'),
 ('20000000-0000-0000-0000-000000000003','10000000-0000-0000-0000-000000000001','Lucas');
insert into public.services(id,barbershop_id,name,price_cents,duration_minutes) values
 ('30000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000001','Corte',3500,30),
 ('30000000-0000-0000-0000-000000000002','10000000-0000-0000-0000-000000000001','Barba',2500,20),
 ('30000000-0000-0000-0000-000000000003','10000000-0000-0000-0000-000000000001','Corte + Barba',5500,50),
 ('30000000-0000-0000-0000-000000000004','10000000-0000-0000-0000-000000000001','Sobrancelha',1500,10);
insert into public.professional_services(barbershop_id,professional_id,service_id)
  select p.barbershop_id,p.id,s.id from public.professionals p join public.services s using(barbershop_id)
  where p.barbershop_id='10000000-0000-0000-0000-000000000001';
insert into public.business_hours(barbershop_id,weekday,start_minute,end_minute)
  select '10000000-0000-0000-0000-000000000001'::uuid,d,a,b
  from generate_series(1,6) d cross join (values (540,720),(780,1080)) as periods(a,b);
insert into public.professional_schedules(barbershop_id,professional_id,weekday,start_minute,end_minute)
  select p.barbershop_id,p.id,h.weekday,h.start_minute,h.end_minute from public.professionals p
  join public.business_hours h using(barbershop_id) where p.barbershop_id='10000000-0000-0000-0000-000000000001';
insert into public.notification_templates(barbershop_id,event,body)
  values ('10000000-0000-0000-0000-000000000001','confirmation','Olá, {{cliente}}! Seu horário foi confirmado para {{data}} às {{hora}}.');
commit;
