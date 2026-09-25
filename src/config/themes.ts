import type { Theme } from '../types/domain'

export const themes: Record<Theme, { label: string; description: string }> = {
  premium: { label: 'Premium Dark', description: 'Grafite, detalhes elegantes e superfícies escuras.' },
  classic: { label: 'Classic Barber', description: 'Tipografia marcante e inspiração tradicional.' },
  modern: { label: 'Modern Clean', description: 'Superfícies claras e composição minimalista.' },
}

export const defaultTheme: Theme = 'premium'
