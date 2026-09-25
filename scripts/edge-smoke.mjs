import assert from 'node:assert/strict'
import { readFile } from 'node:fs/promises'
import { createClient } from '@supabase/supabase-js'
const env=Object.fromEntries((await readFile(new URL('../.env.local',import.meta.url),'utf8')).split(/\r?\n/).filter(l=>l.includes('=')).map(l=>[l.slice(0,l.indexOf('=')),l.slice(l.indexOf('=')+1)]))
const endpoint=env.VITE_SUPABASE_URL+'/functions/v1/whatsapp'
assert.equal((await fetch(endpoint+'?action=dispatch',{method:'POST'})).status,401)
assert.equal((await fetch(endpoint,{method:'POST',headers:{Origin:'https://untrusted.example','Content-Type':'application/json'},body:'{}'})).status,403)
const credentials=JSON.parse(await readFile(new URL('../demo-credentials.local',import.meta.url),'utf8'))
const client=createClient(env.VITE_SUPABASE_URL,env.VITE_SUPABASE_PUBLISHABLE_KEY,{auth:{persistSession:false}})
const {data,error}=await client.auth.signInWithPassword({email:credentials.email,password:credentials.password})
assert.equal(error,null)
const response=await fetch(endpoint,{method:'POST',headers:{Origin:'http://127.0.0.1:5173','Content-Type':'application/json',Authorization:`Bearer ${data.session.access_token}`,apikey:env.VITE_SUPABASE_PUBLISHABLE_KEY},body:JSON.stringify({action:'start',tenant:credentials.demo_tenant})})
assert.equal(response.status,503,'Sem configuração Meta, não deve representar conexão concluída')
assert.match((await response.json()).error,/Meta/)
await client.auth.signOut()
process.stdout.write('Edge Function: dispatcher protegido, origem negada e configuração Meta pendente corretamente informada: OK.\n')
