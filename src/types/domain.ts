export type MemberRole = 'owner' | 'manager' | 'professional' | 'receptionist'
export type UserRole = MemberRole | 'customer' | 'super_admin'
export type Plan = 'starter' | 'pro' | 'premium'
export type Theme = 'premium' | 'classic' | 'modern'
export type SubscriptionStatus = 'trial' | 'active' | 'past_due' | 'cancelled' | 'blocked'
export type AppointmentStatus =
  | 'scheduled' | 'confirmed' | 'in_progress' | 'completed' | 'cancelled' | 'no_show'

/** Contexto carregado de membership validada; nunca de um parâmetro da URL isolado. */
export interface TenantMembership {
  barbershop_id: string
  user_id: string
  role: MemberRole
}
