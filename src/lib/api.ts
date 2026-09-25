import { env } from '../config/env'
import { getSupabase } from './supabase'
import type { Database } from '../types/database'

export type Row = Record<string, string | number | boolean | null>
export type Entity = 'services' | 'professionals' | 'customers' | 'barbershops' | 'settings' | 'business_hours' | 'professional_schedules' | 'blocked_times' | 'notification_templates' | 'barbershop_members' | 'audit_logs' | 'whatsapp_connections' | 'customer_notes' | 'whatsapp_messages'
type Functions = Database['public']['Functions']
export function message(error: unknown): string {
  if (error instanceof Error && error.message.startsWith('APP:')) return error.message.slice(4)
  return 'Não foi possível concluir. Confira os dados e sua conexão.'
}
function fail(error: { code?: string; message?: string }): never {
  const known: Record<string,string> = { '42501':'Você não tem permissão para esta operação.', '23503':'Este registro está vinculado a outros dados. Desative-o para preservar o histórico.', '23505':'Este registro já existe.', '23P01':'Este horário acabou de ficar indisponível. Escolha outro.', '23514':'Confira os horários, os valores e o limite do seu plano.' }
  throw new Error(`APP:${error.code==='P0001' ? error.message : known[error.code ?? ''] ?? 'Não foi possível salvar os dados.'}`)
}
export async function rpc<T>(name: keyof Functions, args: Record<string, unknown> = {}): Promise<T> {
  // Fronteira de formulários dinâmicos; autorização e validação permanecem nas RPCs.
  const {data,error}=await getSupabase().rpc(name,args as never)
  if(error) fail(error)
  return data as T
}
export async function records(table: Entity, tenant: string, method='GET', body?: object, id?: string): Promise<Row[]> {
  const {data:{session}}=await getSupabase().auth.getSession()
  if(!session) throw new Error('APP:Faça login novamente.')
  const params=new URLSearchParams({select:'*'})
  if(table==='whatsapp_messages'&&method==='GET'){params.set('order','created_at.desc');params.set('limit','30')}
  params.set(table==='barbershops'?'id':'barbershop_id',`eq.${tenant}`)
  if(id && table!=='barbershops') params.set('id',`eq.${id}`)
  const response=await fetch(`${env.supabaseUrl}/rest/v1/${table}?${params}`,{
    method,cache:'no-store',headers:{apikey:env.supabasePublishableKey,Authorization:`Bearer ${session.access_token}`,
      'Content-Type':'application/json',Prefer:'return=representation'},body:body?JSON.stringify(body):undefined,
  })
  const data=await response.json()
  if(!response.ok) fail(data)
  return data as Row[]
}
export const money=(cents:number)=>new Intl.NumberFormat('pt-BR',{style:'currency',currency:'BRL'}).format(cents/100)
export const dateTime=(value:string)=>new Date(value).toLocaleString('pt-BR',{timeZone:'America/Sao_Paulo',dateStyle:'short',timeStyle:'short'})
