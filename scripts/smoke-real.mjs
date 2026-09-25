import assert from 'node:assert/strict'
import { readFile,writeFile } from 'node:fs/promises'
import { createClient } from '@supabase/supabase-js'
const root=new URL('../',import.meta.url)
const env=Object.fromEntries((await readFile(new URL('.env.local',root),'utf8')).split(/\r?\n/).filter(l=>l.includes('=')).map(l=>[l.slice(0,l.indexOf('=')),l.slice(l.indexOf('=')+1)]))
const creds=JSON.parse(await readFile(new URL('demo-credentials.local',root),'utf8'))
const db=createClient(env.VITE_SUPABASE_URL,env.VITE_SUPABASE_PUBLISHABLE_KEY,{auth:{persistSession:false,autoRefreshToken:false}})
const ok=async promise=>{const r=await promise;if(r.error)throw new Error(`${r.error.code??''} ${r.error.message}`);return r.data}
await ok(db.auth.signInWithPassword({email:creds.email,password:creds.password}))
const context=await ok(db.rpc('session_context'));assert.equal(context.is_admin,true)
let shops=await ok(db.rpc('admin_shops'))
let shop=shops.find(s=>s.slug===creds.demo_slug || s.name==='Barbearia Prime Demo')
if(!shop){const id=await ok(db.rpc('admin_create_shop',{shop_name:'Barbearia Prime Demo',owner_email:creds.email,selected_plan:'pro'}));shops=await ok(db.rpc('admin_shops'));shop=shops.find(s=>s.id===id)}
const tenant=shop.id
await ok(db.from('barbershops').update({is_published:true,onboarding_step:8,description:'Ambiente demonstrativo para conhecer a plataforma.',city:'São Paulo'}).eq('id',tenant))
let services=await ok(db.from('services').select('*').eq('barbershop_id',tenant))
if(!services.length)services=await ok(db.from('services').insert([{barbershop_id:tenant,name:'Corte',price_cents:3500,duration_minutes:30},{barbershop_id:tenant,name:'Barba',price_cents:2500,duration_minutes:20},{barbershop_id:tenant,name:'Corte + Barba',price_cents:5500,duration_minutes:50}]).select())
let pros=await ok(db.from('professionals').select('*').eq('barbershop_id',tenant))
if(!pros.length)pros=await ok(db.from('professionals').insert(['João','Carlos','Lucas'].map(name=>({barbershop_id:tenant,name,commission_percent:40}))).select())
for(const p of pros)await ok(db.rpc('set_professional_services',{tenant,professional:p.id,service_ids:services.map(s=>s.id)}))
const hours=await ok(db.from('business_hours').select('id').eq('barbershop_id',tenant))
if(!hours.length){const periods=[];for(let d=1;d<=6;d++)for(const [a,b]of [[540,720],[780,1080]])periods.push({barbershop_id:tenant,weekday:d,start_minute:a,end_minute:b});await ok(db.from('business_hours').insert(periods));for(const p of pros)await ok(db.from('professional_schedules').insert(periods.map(h=>({...h,professional_id:p.id}))))}
await ok(db.rpc('complete_onboarding',{tenant}));
creds.demo_tenant=tenant;creds.demo_slug=shop.slug;await writeFile(new URL('demo-credentials.local',root),JSON.stringify(creds,null,2))
const publicClient=createClient(env.VITE_SUPABASE_URL,env.VITE_SUPABASE_PUBLISHABLE_KEY,{auth:{persistSession:false}})
assert.equal((await ok(publicClient.rpc('public_catalog',{shop_slug:shop.slug}))).shop.id,tenant)
const privateRead=await publicClient.from('customers').select('id');assert.ok(privateRead.error||privateRead.data.length===0)
let slots=[]
for(let d=1;d<8&&!slots.length;d++){const day=new Date(Date.now()+d*86400000).toLocaleDateString('en-CA',{timeZone:'America/Sao_Paulo'});slots=await ok(db.rpc('available_slots',{tenant,service:services[0].id,booking_date:day,professional:pros[0].id}))}
assert.ok(slots.length)
const slot=slots[0],args={tenant,service:services[0].id,professional:slot.professional_id,starts:slot.starts_at,customer_name:'Teste concorrência DEMO',customer_phone:'11900000000'}
const results=await Promise.all([db.rpc('book_appointment',args),db.rpc('book_appointment',args)])
assert.equal(results.filter(r=>!r.error).length,1,'Apenas uma reserva concorrente pode vencer')
assert.ok(results.find(r=>r.error)?.error)
const booked=results.find(r=>!r.error).data
await ok(db.rpc('appointment_action',{appointment:booked,new_status:'cancelled'}))
const uploaded=await ok(db.storage.from('logos').upload(`${tenant}/smoke-${Date.now()}.png`,new Uint8Array(await readFile(new URL('public/icon-192.png',root))),{contentType:'image/png'}))
await ok(db.storage.from('logos').remove([uploaded.path]))
process.stdout.write('Login real, Super Admin, empresa demo, catálogo público, privacidade, duas reservas concorrentes e upload privado: OK.\n')
await db.auth.signOut()
