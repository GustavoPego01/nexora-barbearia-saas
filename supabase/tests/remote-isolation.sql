-- Somente fixtures transacionais: nenhum dado de teste persiste.
begin;
insert into auth.users(id) values ('91000000-0000-0000-0000-000000000001'),('91000000-0000-0000-0000-000000000002');
insert into public.barbershops(id,name,slug) values
 ('92000000-0000-0000-0000-000000000001','Teste A','isolamento-transacional-a'),
 ('92000000-0000-0000-0000-000000000002','Teste B','isolamento-transacional-b');
insert into public.subscriptions(barbershop_id,plan,status) values
 ('92000000-0000-0000-0000-000000000001','starter','active'),('92000000-0000-0000-0000-000000000002','starter','active');
insert into public.barbershop_members(barbershop_id,user_id,role) values
 ('92000000-0000-0000-0000-000000000001','91000000-0000-0000-0000-000000000001','owner'),
 ('92000000-0000-0000-0000-000000000002','91000000-0000-0000-0000-000000000002','owner');
insert into public.customers(barbershop_id,name,phone) values
 ('92000000-0000-0000-0000-000000000001','Cliente A','11999999999'),
 ('92000000-0000-0000-0000-000000000002','Cliente B','11988888888');
set local role authenticated;
select set_config('request.jwt.claim.sub','91000000-0000-0000-0000-000000000001',true);
do $$ begin
 if (select count(*) from public.customers) <> 1 then raise exception 'RLS vazou dados'; end if;
 begin
  insert into public.customers(barbershop_id,name,phone) values('92000000-0000-0000-0000-000000000002','Ataque','11999999999');
  raise exception 'INSERT cruzado permitido';
 exception when insufficient_privilege then null; end;
 begin
  update public.subscriptions set plan='premium'; raise exception 'Escalada de plano permitida';
 exception when insufficient_privilege then null; end;
end $$;
reset role;
select 'RLS remoto: leitura isolada, INSERT cruzado negado, alteração de plano negada' as result;
rollback;
