import { createContext, useContext } from 'react'
import type { Session } from '@supabase/supabase-js'
import type { MemberRole } from '../types/domain'
export interface Membership { barbershop_id:string; name:string; slug:string; role:MemberRole; active:boolean; onboarding_completed_at:string|null }
export interface SessionState { session:Session|null; loading:boolean; admin:boolean; memberships:Membership[]; reload:()=>Promise<void> }
export const SessionContext=createContext<SessionState>({session:null,loading:true,admin:false,memberships:[],reload:async()=>{}})
export const useSession=()=>useContext(SessionContext)
