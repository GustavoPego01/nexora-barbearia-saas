import { createClient, type SupabaseClient } from '@supabase/supabase-js'
import { env } from '../config/env'
import { AppError } from './errors'
import type { Database } from '../types/database'

let client: SupabaseClient<Database> | undefined

/** Cliente compartilhado, tipado a partir das migrations do banco. */
export function getSupabase(): SupabaseClient<Database> {
  if (!env.isSupabaseConfigured) {
    throw new AppError('CONFIGURATION', 'A conexão com o sistema ainda não foi configurada.')
  }
  client ??= createClient<Database>(env.supabaseUrl, env.supabasePublishableKey)
  return client
}
