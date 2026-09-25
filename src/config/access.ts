import type { MemberRole, Plan } from '../types/domain'

export type Permission =
  | 'appointments:manage' | 'appointments:own' | 'customers:manage'
  | 'services:manage' | 'team:manage' | 'reports:read'
  | 'payments:manage' | 'settings:manage' | 'subscription:manage'

const permissions: Record<MemberRole, readonly Permission[]> = {
  owner: ['appointments:manage', 'appointments:own', 'customers:manage', 'services:manage',
    'team:manage', 'reports:read', 'payments:manage', 'settings:manage', 'subscription:manage'],
  manager: ['appointments:manage', 'appointments:own', 'customers:manage', 'services:manage',
    'team:manage', 'reports:read', 'payments:manage'],
  professional: ['appointments:own'],
  receptionist: ['appointments:manage', 'customers:manage', 'payments:manage'],
}

/** UX apenas: RLS e RPCs deverão repetir a autorização no banco. */
export function can(role: MemberRole | null, permission: Permission): boolean {
  return role !== null && permissions[role].includes(permission)
}

export const plans: Record<Plan, { label: string; professionalLimit: number | null }> = {
  starter: { label: 'Starter', professionalLimit: 2 },
  pro: { label: 'Pro', professionalLimit: 5 },
  premium: { label: 'Premium', professionalLimit: null },
}
