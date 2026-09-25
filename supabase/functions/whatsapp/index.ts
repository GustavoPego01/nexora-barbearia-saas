import { createClient } from 'npm:@supabase/supabase-js@2'
declare const EdgeRuntime:{waitUntil:(task:Promise<unknown>)=>void}
const env=(key:string)=>Deno.env.get(key)??''
const admin=createClient(env('SUPABASE_URL'),env('SUPABASE_SERVICE_ROLE_KEY'),{auth:{persistSession:false}})
const json=(data:unknown,status=200,headers:Record<string,string>={})=>new Response(JSON.stringify(data),{status,headers:{'Content-Type':'application/json',...headers}})
const hex=(bytes:ArrayBuffer)=>Array.from(new Uint8Array(bytes)).map(b=>b.toString(16).padStart(2,'0')).join('')
const hash=async(value:string)=>hex(await crypto.subtle.digest('SHA-256',new TextEncoder().encode(value)))
const allowedOrigins=()=>env('APP_ORIGINS').split(',').filter(Boolean)
async function encrypt(token:string){
 const raw=Uint8Array.from(atob(env('WHATSAPP_ENCRYPTION_KEY')),c=>c.charCodeAt(0))
 const key=await crypto.subtle.importKey('raw',raw,'AES-GCM',false,['encrypt'])
 const iv=crypto.getRandomValues(new Uint8Array(12)),cipher=await crypto.subtle.encrypt({name:'AES-GCM',iv},key,new TextEncoder().encode(token))
 return btoa(String.fromCharCode(...iv,...new Uint8Array(cipher)))
}
async function decrypt(value:string){
 const raw=Uint8Array.from(atob(env('WHATSAPP_ENCRYPTION_KEY')),c=>c.charCodeAt(0)),bytes=Uint8Array.from(atob(value),c=>c.charCodeAt(0))
 const key=await crypto.subtle.importKey('raw',raw,'AES-GCM',false,['decrypt'])
 return new TextDecoder().decode(await crypto.subtle.decrypt({name:'AES-GCM',iv:bytes.slice(0,12)},key,bytes.slice(12)))
}
async function graph(path:string,token:string,method='GET',body?:unknown){
 const response=await fetch(`https://graph.facebook.com/${env('META_GRAPH_VERSION')}/${path}`,{method,signal:AbortSignal.timeout(8000),headers:{Authorization:`Bearer ${token}`,'Content-Type':'application/json'},body:body?JSON.stringify(body):undefined})
 const data=await response.json();if(!response.ok)throw new Error('A Meta não autorizou esta operação. Confira sua conta comercial.');return data
}
Deno.serve(async(req:Request)=>{
 let connectingTenant:string|null=null
 const url=new URL(req.url),action=url.searchParams.get('action'),origin=req.headers.get('origin')??''
 const cors:Record<string,string>=allowedOrigins().includes(origin)?{'Access-Control-Allow-Origin':origin,'Access-Control-Allow-Headers':'authorization,apikey,content-type,x-client-info','Vary':'Origin'}:{}
 if(req.method==='OPTIONS')return new Response(null,{status:204,headers:cors})
 try{
  if(action==='webhook'){
   if(!env('META_APP_SECRET')||!env('META_VERIFY_TOKEN'))return json({error:'Integração não configurada'},503)
   if(req.method==='GET')return url.searchParams.get('hub.mode')==='subscribe'&&url.searchParams.get('hub.verify_token')===env('META_VERIFY_TOKEN')?new Response(url.searchParams.get('hub.challenge')):new Response('Forbidden',{status:403})
   if(req.method!=='POST')return new Response('Method not allowed',{status:405})
   const raw=await req.text();if(raw.length>1048576)return new Response('Too large',{status:413})
   const key=await crypto.subtle.importKey('raw',new TextEncoder().encode(env('META_APP_SECRET')),{name:'HMAC',hash:'SHA-256'},false,['verify'])
   const signature=req.headers.get('x-hub-signature-256')?.replace(/^sha256=/,'')??''
   if(!/^[a-f0-9]{64}$/.test(signature))return new Response('Forbidden',{status:403})
   const bytes=Uint8Array.from(signature.match(/../g)!,v=>parseInt(v,16))
   if(!await crypto.subtle.verify('HMAC',key,bytes,new TextEncoder().encode(raw)))return new Response('Forbidden',{status:403})
   const payload=JSON.parse(raw)
   let received=false
   for(const entry of payload.entry??[])for(const change of entry.changes??[]){const value=change.value;for(const m of value?.messages??[]){if(m.type!=='text'||!Number.isFinite(Number(m.timestamp))||Number(m.timestamp)<Date.now()/1000-86400)continue;const {error}=await admin.rpc('wa_receive',{phone_id:value.metadata.phone_number_id,provider_id:m.id,sender_phone:m.from,message_body:m.text.body});if(error)throw new Error('Falha ao enfileirar mensagem');received=true}}
   if(received&&env('WHATSAPP_CRON_SECRET'))EdgeRuntime.waitUntil(fetch(`${env('SUPABASE_URL')}/functions/v1/whatsapp?action=dispatch`,{method:'POST',headers:{Authorization:`Bearer ${env('WHATSAPP_CRON_SECRET')}`},signal:AbortSignal.timeout(60000)}).then(response=>response.body?.cancel()).catch(()=>{/* Cron retoma a fila persistida. */}))
   return json({received:true})
  }
  if(action==='dispatch'){
   if(!env('WHATSAPP_CRON_SECRET')||req.headers.get('authorization')!==`Bearer ${env('WHATSAPP_CRON_SECRET')}`)return json({error:'Unauthorized'},401)
   const {data:items,error}=await admin.rpc('wa_claim');if(error)throw error
   const deadline=Date.now()+45000
   let sent=0
   for(const item of items??[]){let successful=false;try{
    if(Date.now()>deadline)break
    const {data:allowed,error:permissionError}=await admin.rpc('wa_delivery_allowed',{tenant:item.barbershop_id,phone:item.phone_number_id,ciphertext:item.token,delivery:item.id})
    if(permissionError)throw permissionError
    if(!allowed)continue
    const token=await decrypt(item.token)
    const {data:reply,error:botError}=await admin.rpc('wa_bot_reply',{inbox:item.id,public_url:env('APP_PUBLIC_URL')})
    if(botError)throw botError
    if(!reply){await admin.rpc('wa_finish',{inbox_id:item.id,successful:true});continue}
    for(const chunk of String(reply).match(/[\s\S]{1,4000}/gu)??[]){
     if(Date.now()>deadline)throw new Error('Tempo de envio excedido')
     await graph(`${item.phone_number_id}/messages`,token,'POST',{messaging_product:'whatsapp',to:item.sender,type:'text',text:{body:chunk}})
    }
    successful=true;sent++
   }catch{/* fila limita tentativas; nenhum token é registrado */}
    await admin.rpc('wa_finish',{inbox_id:item.id,successful})
   }
   const {data:notifications,error:notificationError}=await admin.rpc('wa_claim_notifications');if(notificationError)throw notificationError
   for(const item of notifications??[]){let successful=false;try{
    if(Date.now()>deadline)break
    const {data:allowed,error:permissionError}=await admin.rpc('wa_delivery_allowed',{tenant:item.tenant,phone:item.phone_id,ciphertext:item.token,delivery:item.id,notification:true})
    if(permissionError)throw permissionError
    if(!allowed)continue
    const token=await decrypt(item.token),variables:Record<string,string>={cliente:item.customer,servico:item.service,profissional:item.professional,data:item.date,hora:item.time,barbearia:item.shop}
    const parameters=[...item.body.matchAll(/\{\{(cliente|servico|profissional|data|hora|barbearia)\}\}/g)].map((match:RegExpMatchArray)=>({type:'text',text:variables[match[1]]}))
    let to=item.phone.replace(/\D/g,'');if(to.length===10||to.length===11)to='55'+to
    await graph(`${item.phone_id}/messages`,token,'POST',{messaging_product:'whatsapp',to,type:'template',template:{name:item.meta_name,language:{code:item.meta_language},...(parameters.length?{components:[{type:'body',parameters}]}:{})}})
    successful=true;sent++
   }catch{/* status de erro sem tokens ou dados pessoais nos logs */}
    await admin.rpc('wa_finish_notification',{notification:item.id,successful})
   }
   return json({sent})
  }
  if(!allowedOrigins().includes(origin))return json({error:'Origem não autorizada'},403)
  const authorization=req.headers.get('authorization')??''
  const userClient=createClient(env('SUPABASE_URL'),env('SUPABASE_ANON_KEY'),{global:{headers:{Authorization:authorization}},auth:{persistSession:false}})
  const {data:{user},error:authError}=await userClient.auth.getUser();if(authError||!user)return json({error:'Faça login'},401,cors)
  const body=await req.json()
  if(!env('META_APP_ID')||!env('META_LOGIN_CONFIG_ID')||!env('META_APP_SECRET')||!env('META_GRAPH_VERSION')||!env('WHATSAPP_ENCRYPTION_KEY'))return json({error:'A plataforma ainda aguarda a habilitação oficial da Meta. Nenhum token precisa ser informado pela barbearia.'},503,cors)
  if(body.action==='start'){
   const state=crypto.randomUUID()+crypto.randomUUID(),{error}=await userClient.rpc('wa_begin',{tenant:body.tenant,state_hash:await hash(state)})
   if(error)return json({error:'Somente o proprietário pode conectar este número'},403,cors)
   return json({state,appId:env('META_APP_ID'),configId:env('META_LOGIN_CONFIG_ID'),version:env('META_GRAPH_VERSION')},200,cors)
  }
  if(body.action==='complete'){
   if(!body.state||!body.code||!/^\d+$/.test(body.phoneId)||!/^\d+$/.test(body.wabaId))return json({error:'Autorização incompleta'},400,cors)
   const {data:tenant,error}=await userClient.rpc('wa_consume',{state:await hash(body.state)});if(error||!tenant)return json({error:'Autorização expirada. Tente novamente.'},403,cors)
   connectingTenant=tenant
   const exchange=new URL(`https://graph.facebook.com/${env('META_GRAPH_VERSION')}/oauth/access_token`)
   exchange.search=new URLSearchParams({client_id:env('META_APP_ID'),client_secret:env('META_APP_SECRET'),code:body.code}).toString()
   const tokenResponse=await fetch(exchange,{signal:AbortSignal.timeout(8000)}),tokenData=await tokenResponse.json();if(!tokenResponse.ok||!tokenData.access_token)throw new Error('Autorização da Meta recusada')
   const phones=await graph(`${body.wabaId}/phone_numbers?fields=id`,tokenData.access_token)
   if(!phones.data?.some((p:{id:string})=>p.id===body.phoneId))throw new Error('O número não pertence à conta autorizada')
   await graph(`${body.wabaId}/subscribed_apps`,tokenData.access_token,'POST')
   const pin=String(crypto.getRandomValues(new Uint32Array(1))[0]%1000000).padStart(6,'0')
   const {data:savedPin,error:pinError}=await admin.rpc('wa_registration_pin',{tenant,phone:body.phoneId,ciphertext:await encrypt(pin)})
   if(pinError||!savedPin)throw new Error('Não foi possível preparar o registro do número')
   await graph(`${body.phoneId}/register`,tokenData.access_token,'POST',{messaging_product:'whatsapp',pin:await decrypt(savedPin)})
   const {error:saveError}=await admin.rpc('wa_save',{tenant,phone_id:body.phoneId,account_id:body.wabaId,ciphertext:await encrypt(tokenData.access_token)})
   if(saveError)throw new Error('Não foi possível salvar a conexão')
   return json({connected:true},200,cors)
  }
  return json({error:'Operação inválida'},400,cors)
 }catch{if(connectingTenant)await admin.rpc('wa_connection_error',{tenant:connectingTenant});return json({error:'Não foi possível concluir a operação. Tente novamente.'},502,cors)}
})
