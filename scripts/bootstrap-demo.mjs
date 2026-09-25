import { randomBytes } from 'node:crypto'
import { readFile,writeFile } from 'node:fs/promises'
import { createClient } from '@supabase/supabase-js'
const root=new URL('../',import.meta.url)
const env=Object.fromEntries((await readFile(new URL('.env.local',root),'utf8')).split(/\r?\n/).filter(l=>l.includes('=')).map(l=>[l.slice(0,l.indexOf('=')),l.slice(l.indexOf('=')+1)]))
const secret=process.env.BARBER_SERVICE_KEY
if(!secret)throw new Error('Credencial administrativa temporária ausente')
const admin=createClient(env.VITE_SUPABASE_URL,secret,{auth:{persistSession:false,autoRefreshToken:false}})
const file=new URL('demo-credentials.local',root)
let saved
try{saved=JSON.parse(await readFile(file,'utf8'))}catch{/* primeiro provisionamento */}
if(saved?.project_url&&saved.project_url!==env.VITE_SUPABASE_URL)throw new Error('Credenciais demo pertencem a outro projeto')
if(!saved){
 const password=randomBytes(24).toString('base64url')+'aA1!'
 const email='admin@barbearias.test'
 const {data,error}=await admin.auth.admin.createUser({email,password,email_confirm:true,user_metadata:{full_name:'Administrador Demo'}})
 if(error)throw new Error(`Falha ao criar conta demo (${error.status}): ${error.message.replaceAll(secret,'[redacted]').replaceAll(password,'[redacted]')}`)
 saved={project_url:env.VITE_SUPABASE_URL,email,password,user_id:data.user.id}
 await writeFile(file,JSON.stringify(saved,null,2))
}
const sql=`begin;\ninsert into private.platform_admins(user_id) values('${saved.user_id}') on conflict do nothing;\ncommit;\n`
await writeFile(new URL('supabase/.temp/bootstrap-admin.sql',root),sql)
process.stdout.write('Conta demo preparada. Credenciais apenas em demo-credentials.local; autorização SQL pronta.\n')
