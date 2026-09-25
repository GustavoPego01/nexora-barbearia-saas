const url = import.meta.env.VITE_SUPABASE_URL?.trim() ?? ''
const publishableKey = import.meta.env.VITE_SUPABASE_PUBLISHABLE_KEY?.trim() ?? ''

function validUrl(value: string): boolean {
  try {
    const parsed = new URL(value)
    return parsed.protocol === 'https:' ||
      (parsed.protocol === 'http:' && ['localhost', '127.0.0.1'].includes(parsed.hostname))
  } catch {
    return false
  }
}

export const env = Object.freeze({
  supabaseUrl: url,
  supabasePublishableKey: publishableKey,
  // Só aceita o formato de chave pública. Chaves legadas ficam fora desta base.
  isSupabaseConfigured: validUrl(url) && publishableKey.startsWith('sb_publishable_'),
})
