import assert from 'node:assert/strict'
import { readFile, readdir, writeFile } from 'node:fs/promises'
import { PGlite } from '@electric-sql/pglite'
import { btree_gist } from '@electric-sql/pglite/contrib/btree_gist'

const db = new PGlite({ extensions: { btree_gist } })
const read = (path) => readFile(new URL(`../${path}`, import.meta.url), 'utf8')
let passed = 0
async function test(name, fn) {
  await fn()
  passed++
  process.stdout.write(`OK ${name}\n`)
}
async function denied(sql, codes = ['42501']) {
  await assert.rejects(db.exec(sql), (error) => codes.includes(error.code))
}
async function asUser(id, fn, role = 'authenticated') {
  await db.exec(`set role ${role}`)
  await db.query("select set_config('request.jwt.claim.sub',$1,false)", [id ?? ''])
  try { await fn() } finally {
    await db.exec('reset role')
    await db.query("select set_config('request.jwt.claim.sub','',false)")
  }
}
const A = '10000000-0000-0000-0000-000000000001'
const B = '10000000-0000-0000-0000-000000000002'
const uid = (n) => `40000000-0000-0000-0000-${String(n).padStart(12,'0')}`
const cid = (n) => `50000000-0000-0000-0000-${String(n).padStart(12,'0')}`
const pro = '20000000-0000-0000-0000-000000000001'
const service = '30000000-0000-0000-0000-000000000001'
const appointment = '60000000-0000-0000-0000-000000000001'

try {
  await db.exec(await read('supabase/tests/bootstrap.sql'))
  const migrations = (await readdir(new URL('../supabase/migrations',import.meta.url))).sort()
  for (const file of migrations) await test(`migration ${file}`, async () => {
    await db.exec(await read(`supabase/migrations/${file}`))
  })
  await test('seed completo', async () => { await db.exec(await read('supabase/seed.sql')) })
  await db.exec(`
    insert into auth.users(id) select ('40000000-0000-0000-0000-'||lpad(n::text,12,'0'))::uuid from generate_series(1,8) n;
    insert into public.barbershops(id,name,slug) values('${B}','Outra Barbearia','outra-barbearia');
    insert into public.subscriptions(barbershop_id,plan,status) values('${B}','starter','active');
    insert into public.settings(barbershop_id) values('${B}');
    insert into public.barbershop_members(barbershop_id,user_id,role) values
      ('${A}','${uid(1)}','owner'),('${B}','${uid(2)}','owner'),
      ('${A}','${uid(3)}','manager'),('${A}','${uid(4)}','receptionist'),('${A}','${uid(5)}','professional');
    update public.professionals set member_id=(select id from public.barbershop_members where user_id='${uid(5)}') where id='${pro}';
    insert into public.customers(id,barbershop_id,user_id,name,phone) values
      ('${cid(1)}','${A}','${uid(6)}','Cliente A','11999999999'),
      ('${cid(2)}','${B}','${uid(7)}','Cliente B','11988888888'),
      ('${cid(3)}','${A}',null,'Cliente sem vínculo','11977777777');
    insert into public.customer_notes(barbershop_id,customer_id,body) values('${A}','${cid(1)}','Nota privada');
    insert into public.appointments(id,barbershop_id,customer_id,professional_id,service_id,starts_at,ends_at,occupied_until,price_cents,duration_minutes)
      values('${appointment}','${A}','${cid(1)}','${pro}','${service}', '2030-09-12 12:00Z','2030-09-12 12:30Z','2030-09-12 12:40Z',3500,30);
    insert into private.platform_admins(user_id) values('${uid(8)}');
  `)
  await test('RLS em todas as tabelas públicas e privadas', async () => {
    const { rows } = await db.query("select relname from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname in ('public','private') and c.relkind='r' and not c.relrowsecurity")
    assert.deepEqual(rows, [])
  })
  await test('functions definer têm search_path fixo e sem EXECUTE público', async () => {
    const { rows } = await db.query(`select p.proname from pg_proc p join pg_namespace n on n.oid=p.pronamespace
      where n.nspname='private' and (p.prosecdef and not ('search_path=""'=any(p.proconfig))
        or exists (select 1 from aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) x where x.grantee=0 and x.privilege_type='EXECUTE'))`)
    assert.deepEqual(rows, [])
  })
  await test('relacionamentos entre entidades tenant incluem barbershop_id',async()=>{
    const {rows}=await db.query(`select c.conname from pg_constraint c
      join pg_class r on r.oid=c.conrelid join pg_namespace n on n.oid=r.relnamespace
      where c.contype='f' and n.nspname='public'
      and exists(select 1 from pg_attribute a where a.attrelid=c.confrelid and a.attname='barbershop_id')
      and not exists(select 1 from pg_attribute a where a.attrelid=c.conrelid and a.attname='barbershop_id' and a.attnum=any(c.conkey))`)
    assert.deepEqual(rows,[])
  })
  await test('perfil Auth criado sem promoção de função e campos imutáveis',()=>asUser(uid(1),async()=>{
    assert.deepEqual((await db.query('select id from public.profiles')).rows.map(r=>r.id),[uid(1)])
    await db.exec("update public.profiles set full_name='Proprietário'")
    await denied(`update public.profiles set id='${uid(2)}'`)
  }))
  await test('owner lê apenas sua empresa; CRUD próprio; ataque entre tenants', () => asUser(uid(1),async () => {
    await db.exec(`update public.settings set bot_welcome_message='Teste por empresa' where barbershop_id='${A}'`)
    assert.equal((await db.query(`update public.settings set bot_enabled=false where barbershop_id='${B}' returning barbershop_id`)).rows.length,0)
    await denied(`select public.wa_registration_pin('${A}','forged','secret')`)
    await denied(`select public.wa_connection_error('${B}')`)
    const { rows } = await db.query('select id from public.customers order by id')
    assert.deepEqual(rows.map(r=>r.id),[cid(1),cid(3)])
    await db.exec(`insert into public.customers(barbershop_id,name,phone) values('${A}','Novo cliente','11900000000')`)
    await denied(`insert into public.customers(barbershop_id,name,phone) values('${B}','Invasão','11900000000')`)
    assert.equal((await db.query(`update public.customers set name='Invadido' where barbershop_id='${B}' returning id`)).rows.length,0)
    assert.equal((await db.query(`delete from public.customers where barbershop_id='${B}' returning id`)).rows.length,0)
    await denied(`update public.customers set barbershop_id='${B}' where id='${cid(1)}'`)
    await denied(`insert into public.customers(barbershop_id,user_id,name,phone) values('${A}','${uid(7)}','Vínculo forjado','11900000000')`)
  }))
  await test('tenant B não lê tenant A', () => asUser(uid(2),async () => {
    assert.deepEqual((await db.query('select id from public.customers')).rows.map(r=>r.id),[cid(2)])
    assert.equal((await db.query('select id from public.services')).rows.length,0)
  }))
  await test('manager administra catálogo mas não marca/assinatura/membership', () => asUser(uid(3),async () => {
    await db.exec(`update public.services set price_cents=3600 where id='${service}'`)
    assert.equal((await db.query(`update public.barbershops set name='Invadido' where id='${A}' returning id`)).rows.length,0)
    await denied(`update public.subscriptions set plan='premium' where barbershop_id='${A}'`)
    await denied(`insert into public.barbershop_members(barbershop_id,user_id,role) values('${A}','${uid(8)}','owner')`)
  }))
  await test('recepção acessa clientes mas não edita serviços', () => asUser(uid(4),async () => {
    assert.ok((await db.query('select id from public.customers')).rows.length>=2)
    assert.equal((await db.query(`update public.services set price_cents=1 returning id`)).rows.length,0)
    await denied(`insert into public.services(barbershop_id,name,price_cents,duration_minutes) values('${A}','Fraude',1,30)`)
  }))
  await test('profissional vê apenas clientes atendidos e sua agenda', () => asUser(uid(5),async () => {
    assert.deepEqual((await db.query('select id from public.customers')).rows.map(r=>r.id),[cid(1)])
    assert.deepEqual((await db.query('select id from public.appointments')).rows.map(r=>r.id),[appointment])
    assert.equal((await db.query('select id from public.payments')).rows.length,0)
  }))
  await test('comissão profissional depende de configuração da própria empresa',async()=>{
    await asUser(uid(5),async()=>assert.equal((await db.query('select id from public.professionals')).rows.length,0))
    await db.exec(`update public.settings set commissions_enabled=true where barbershop_id='${A}'`)
    await asUser(uid(5),async()=>assert.deepEqual((await db.query('select id from public.professionals')).rows.map(r=>r.id),[pro]))
  })
  await test('cliente vê apenas seus registros sem notas/comissões', () => asUser(uid(6),async () => {
    assert.deepEqual((await db.query('select id from public.customers')).rows.map(r=>r.id),[cid(1)])
    assert.deepEqual((await db.query('select id from public.appointments')).rows.map(r=>r.id),[appointment])
    assert.equal((await db.query('select id from public.customer_notes')).rows.length,0)
    await denied('select commission_percent from public.appointments')
  }))
  await test('anônimo não lê tabelas privadas; só catálogos globais', () => asUser(null,async () => {
    await denied('select * from public.customers')
    await denied('select * from public.barbershops')
    assert.equal((await db.query('select * from public.plans')).rows.length,3)
  },'anon'))
  await test('super admin sem sessão de suporte não ganha bypass', () => asUser(uid(8),async () => {
    assert.equal((await db.query('select id from public.customers')).rows.length,0)
    await denied('select * from private.platform_admins')
    await denied(`insert into private.platform_admins(user_id) values('${uid(1)}')`)
  }))
  await test('FK composta impede customer de outra empresa mesmo com RLS bypass',async () => {
    await denied(`insert into public.customer_notes(barbershop_id,customer_id,body) values('${A}','${cid(2)}','Ataque')`,['23503'])
    await denied(`update public.appointments set customer_id='${cid(2)}' where id='${appointment}'`,['23503'])
    await denied(`insert into public.professional_services(barbershop_id,professional_id,service_id) values('${B}','${pro}','${service}')`,['23503'])
    await denied(`update public.customers set barbershop_id='${B}' where id='${cid(3)}'`,['23514'])
  })
  await test('horários inválidos/sobrepostos e imagem de outro tenant são rejeitados',async()=>{
    await denied(`insert into public.business_hours(barbershop_id,weekday,start_minute,end_minute) values('${A}',1,540,600)`,['23P01'])
    await denied(`insert into public.business_hours(barbershop_id,weekday,start_minute,end_minute) values('${A}',1,700,600)`,['23514'])
    await denied(`update public.barbershops set timezone='fuso-inexistente' where id='${A}'`,['23514'])
    await denied(`update public.barbershops set logo_path='${B}/logo.png' where id='${A}'`,['23514'])
    await denied(`update public.services set image_path='${B}/corte.png' where id='${service}'`,['23514'])
  })
  await test('sobreposição e intervalo protegidos; fronteira adjacente permitida',async () => {
    const insert = (start,end) => `insert into public.appointments(barbershop_id,customer_id,professional_id,service_id,starts_at,ends_at,occupied_until,price_cents,duration_minutes)
      values('${A}','${cid(1)}','${pro}','${service}','2030-09-12 ${start}Z','2030-09-12 ${end}Z','2030-09-12 ${end}Z',3500,30)`
    await denied(insert('12:30','13:00'),['23P01'])
    await db.exec(insert('12:40','13:10'))
    await denied(`insert into public.blocked_times(barbershop_id,starts_at,ends_at,reason)
      values('${A}','2030-09-12 12:00Z','2030-09-12 13:00Z','day_off')`,['23P01'])
    await db.exec(`insert into public.blocked_times(barbershop_id,starts_at,ends_at,reason)
      values('${A}','2030-09-12 14:00Z','2030-09-12 15:00Z','day_off')`)
    await denied(insert('14:00','14:30'),['23P01'])
  })
  await test('limites do plano e downgrade',async () => {
    await db.exec(`insert into public.professionals(barbershop_id,name) values('${B}','Um'),('${B}','Dois')`)
    await denied(`insert into public.professionals(barbershop_id,name) values('${B}','Três')`,['23514'])
    await denied(`update public.subscriptions set plan='starter' where barbershop_id='${A}'`,['23514'])
  })
  await test('auditoria automática não é editável pelo owner', () => asUser(uid(1),async () => {
    assert.ok((await db.query('select id from public.audit_logs')).rows.length>0)
    await denied('delete from public.audit_logs')
    await denied(`insert into public.audit_logs(barbershop_id,action,entity_table) values('${A}','forjado','x')`)
    await denied(`update public.barbershops set is_active=false where id='${A}'`)
    await denied(`update public.appointments set status='completed' where id='${appointment}'`)
    await denied(`insert into public.payments(barbershop_id,appointment_id,amount_cents,method) values('${A}','${appointment}',1,'pix')`)
  }))
  await test('sessão de suporte gera registro com administrador identificado',async()=>{
    await db.exec(`insert into private.support_sessions(barbershop_id,admin_id,reason,expires_at)
      values('${A}','${uid(8)}','Diagnóstico solicitado pelo proprietário',now()+interval '30 minutes')`)
    const {rows}=await db.query("select actor_id from public.audit_logs where action='support_started'")
    assert.deepEqual(rows.map(r=>r.actor_id),[uid(8)])
  })
  await test('receita não pode ser duplicada por atendimento',async()=>{
    const sql=`insert into public.payments(barbershop_id,appointment_id,amount_cents,method) values('${A}','${appointment}',3500,'pix')`
    await db.exec(sql)
    await denied(sql,['23505'])
  })
  await test('Storage: escrita própria, bloqueio cruzado e nome inválido', () => asUser(uid(1),async () => {
    await db.exec(`insert into storage.objects(bucket_id,name) values('logos','${A}/logo.png')`)
    await denied(`insert into storage.objects(bucket_id,name) values('logos','${B}/logo.png')`)
    await denied(`update storage.objects set name='${B}/roubado.png' where name='${A}/logo.png'`)
    await denied(`insert into storage.objects(bucket_id,name) values('logos','invalido/logo.png')`)
    await denied(`insert into storage.objects(bucket_id,name) values('logos','${A}/../logo.png')`)
  }))
  await test('Storage não permite leitura de outra empresa ou anônima',async () => {
    await asUser(uid(2),async()=>assert.equal((await db.query('select * from storage.objects')).rows.length,0))
    await asUser(null,async()=>assert.equal((await db.query('select * from storage.objects')).rows.length,0),'anon')
  })
  await test('conta bloqueada revoga leitura, escrita e Storage',async () => {
    await db.exec(`update public.subscriptions set status='blocked' where barbershop_id='${A}'`)
    await asUser(uid(1),async()=>{
      assert.equal((await db.query('select id from public.customers')).rows.length,0)
      assert.equal((await db.query('select * from storage.objects')).rows.length,0)
      await denied(`insert into public.customers(barbershop_id,name,phone) values('${A}','Bloqueado','11900000000')`)
    })
    await asUser(uid(6),async()=>assert.equal((await db.query('select id from public.appointments')).rows.length,0))
    await db.exec(`update public.subscriptions set status='active' where barbershop_id='${A}'`)
  })
  await test('membership inativa e trial expirado revogam acesso',async () => {
    await db.exec(`update public.barbershop_members set is_active=false where user_id='${uid(1)}'`)
    await asUser(uid(1),async()=>assert.equal((await db.query('select id from public.customers')).rows.length,0))
    await db.exec(`update public.subscriptions set status='trial',trial_ends_at=now()-interval '1 day' where barbershop_id='${B}'`)
    await asUser(uid(2),async()=>assert.equal((await db.query('select id from public.customers')).rows.length,0))
  })
  await test('fluxo transacional completo de agendamento e pagamento',async()=>{await db.exec(await read('supabase/tests/booking-flow.sql'))})
  await test('WhatsApp: tenant, replay OAuth e sigilo das credenciais',async()=>{await db.exec(await read('supabase/tests/whatsapp-isolation.sql'))})
  await test('WhatsApp: conversa de agendamento e replay idempotente',async()=>{await db.exec(await read('supabase/tests/whatsapp-booking.sql'))})
  await test('workers compilam e retornam filas vazias sem credenciais',async()=>{
    const {rows}=await db.query('select public.wa_claim() as inbox, public.wa_claim_notifications() as notifications')
    assert.deepEqual(rows,[{inbox:[],notifications:[]}])
  })
  await test('WhatsApp: ordem, isolamento e revogação da fila',async()=>{await db.exec(await read('supabase/tests/whatsapp-delivery.sql'))})
  if (process.argv.includes('--types')) {
    const { generateTypes } = await import('./database-types.mjs')
    await writeFile(new URL('../src/types/database.ts',import.meta.url),await generateTypes(db))
    process.stdout.write('Tipos gerados a partir das migrations executadas.\n')
  }
  process.stdout.write(`${passed} verificações passaram (PostgreSQL PGlite; Auth/Storage simulados).\n`)
} finally { await db.close() }
