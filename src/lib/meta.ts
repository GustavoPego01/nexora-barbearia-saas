import { getSupabase } from './supabase'
type Facebook={init:(options:object)=>void;login:(callback:(response:{authResponse?:{code?:string}})=>void,options:object)=>void}
declare global {interface Window {FB?:Facebook}}
export async function prepareWhatsApp(tenant:string):Promise<()=>Promise<void>>{
 const client=getSupabase()
 const start=await client.functions.invoke('whatsapp',{body:{action:'start',tenant}})
 if(start.error){let detail='A conexão oficial da Meta ainda não está disponível.';try{const body=await start.error.context.json();detail=body.error??detail}catch{/* erro de transporte */}throw new Error('APP:'+detail)}
 const {state,appId,configId,version}=start.data
 if(!window.FB)await new Promise<void>((resolve,reject)=>{const script=document.createElement('script');script.src='https://connect.facebook.net/pt_BR/sdk.js';script.async=true;script.onload=()=>resolve();script.onerror=()=>reject(new Error('APP:Não foi possível abrir a Meta.'));document.head.appendChild(script)})
 window.FB!.init({appId,version,xfbml:false,autoLogAppEvents:false})
 return async()=>{
 const authorization=await new Promise<{code:string;phoneId:string;wabaId:string}>((resolve,reject)=>{
  let code='',phoneId='',wabaId='';const cleanup=()=>{clearTimeout(timer);window.removeEventListener('message',receive)}
  const finish=()=>{if(code&&phoneId&&wabaId){cleanup();resolve({code,phoneId,wabaId})}}
  const receive=(event:MessageEvent)=>{if(!['https://www.facebook.com','https://web.facebook.com'].includes(event.origin))return;try{const payload=typeof event.data==='string'?JSON.parse(event.data):event.data;if(payload.type!=='WA_EMBEDDED_SIGNUP')return;if(payload.event==='FINISH'){phoneId=payload.data.phone_number_id;wabaId=payload.data.waba_id;finish()}else if(['CANCEL','ERROR'].includes(payload.event)){cleanup();reject(new Error('APP:Conexão não concluída. Você pode tentar novamente.'))}}catch{/* mensagens de outros widgets */}}
  const timer=setTimeout(()=>{cleanup();reject(new Error('APP:Autorização expirada. Tente novamente.'))},600000)
  window.addEventListener('message',receive)
  window.FB!.login(response=>{code=response.authResponse?.code??'';if(!code){cleanup();reject(new Error('APP:Autorização cancelada.'))}else finish()},{config_id:configId,response_type:'code',override_default_response_type:true,extras:{setup:{},sessionInfoVersion:'3'}})
 })
 const result=await client.functions.invoke('whatsapp',{body:{action:'complete',state,...authorization}})
 if(result.error||!result.data?.connected)throw new Error('APP:Não foi possível concluir a conexão oficial. Tente novamente.')
 }
}
