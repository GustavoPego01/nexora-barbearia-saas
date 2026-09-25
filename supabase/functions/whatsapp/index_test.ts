// Todas as identidades e credenciais deste teste são fictícias; nenhuma rede externa é usada.
let handle!:(request:Request)=>Promise<Response>
const originalServe=Deno.serve
Deno.serve=((handler:typeof handle)=>{handle=handler;return {} as Deno.HttpServer<Deno.NetAddr>}) as typeof Deno.serve
for(const [key,value] of Object.entries({SUPABASE_URL:'https://test.supabase.co',SUPABASE_SERVICE_ROLE_KEY:'test-only',SUPABASE_ANON_KEY:'test-only',META_APP_SECRET:'test-secret',META_VERIFY_TOKEN:'test-verify',WHATSAPP_CRON_SECRET:'test-dispatch',APP_ORIGINS:'https://test.example'}))Deno.env.set(key,value)
const tasks:Promise<unknown>[]=[]
Object.assign(globalThis,{EdgeRuntime:{waitUntil:(task:Promise<unknown>)=>tasks.push(task)}})
await import('./index.ts')
Deno.serve=originalServe
const equal=(actual:unknown,expected:unknown)=>{if(actual!==expected)throw new Error(`Esperado ${expected}; recebido ${actual}`)}
Deno.test('webhook: assinatura, janela, deduplicação no RPC e dispatcher protegido',async()=>{
 const originalFetch=globalThis.fetch
 const calls:string[]=[]
 globalThis.fetch=(input)=>{
  const url=String(input);calls.push(url)
  if(url.endsWith('/rpc/wa_receive'))return Promise.resolve(new Response('null',{headers:{'Content-Type':'application/json'}}))
  if(url.includes('/rpc/wa_claim'))return Promise.resolve(new Response('[]',{headers:{'Content-Type':'application/json'}}))
  if(url.includes('?action=dispatch'))return Promise.resolve(new Response('{}'))
  throw new Error('Requisição inesperada: '+url)
 }
 try{
  const base='https://test.supabase.co/functions/v1/whatsapp'
  equal((await handle(new Request(base+'?action=dispatch',{method:'POST'}))).status,401)
  equal((await handle(new Request(base,{method:'POST',headers:{Origin:'https://untrusted.example'},body:'{}'}))).status,403)
  equal((await handle(new Request(base+'?action=webhook&hub.mode=subscribe&hub.verify_token=test-verify&hub.challenge=123'))).status,200)
  const payload=JSON.stringify({entry:[{changes:[{value:{metadata:{phone_number_id:'123'},messages:[{type:'text',id:'message-1',from:'5511000000001',timestamp:String(Math.floor(Date.now()/1000)),text:{body:'menu'}}]}}]}]})
  equal((await handle(new Request(base+'?action=webhook',{method:'POST',body:payload}))).status,403)
  equal(calls.length,0)
  const key=await crypto.subtle.importKey('raw',new TextEncoder().encode('test-secret'),{name:'HMAC',hash:'SHA-256'},false,['sign'])
  const signature=Array.from(new Uint8Array(await crypto.subtle.sign('HMAC',key,new TextEncoder().encode(payload)))).map(b=>b.toString(16).padStart(2,'0')).join('')
  equal((await handle(new Request(base+'?action=webhook',{method:'POST',headers:{'x-hub-signature-256':'sha256='+signature},body:payload}))).status,200)
  await Promise.all(tasks)
  equal(calls.filter(url=>url.endsWith('/rpc/wa_receive')).length,1)
  equal(calls.filter(url=>url.includes('?action=dispatch')).length,1)
  equal((await handle(new Request(base+'?action=dispatch',{method:'POST',headers:{Authorization:'Bearer test-dispatch'}}))).status,200)
 }finally{globalThis.fetch=originalFetch}
})
