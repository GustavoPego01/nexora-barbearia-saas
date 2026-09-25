import { useEffect,useState,useCallback,useRef,type ReactNode } from 'react'
import { SessionContext,type SessionState } from './session'
import { getSupabase } from '../lib/supabase'
import { rpc } from '../lib/api'
import { env } from '../config/env'

export function SessionProvider({children}:{children:ReactNode}) {
  const [state,setState]=useState<Omit<SessionState,'reload'>>({session:null,loading:true,admin:false,memberships:[]})
  const generation=useRef(0)
  const reload=useCallback(async()=>{
    const current=++generation.current
    if(!env.isSupabaseConfigured){setState({session:null,loading:false,admin:false,memberships:[]});return}
    const {data:{session}}=await getSupabase().auth.getSession()
    if(current!==generation.current)return
    if(!session){setState({session:null,loading:false,admin:false,memberships:[]});return}
    try {
      const context=await rpc<{is_admin:boolean;memberships:SessionState['memberships']}>('session_context')
      if(current!==generation.current)return
      setState({session,loading:false,admin:context.is_admin,memberships:context.memberships})
    } catch {if(current===generation.current)setState({session,loading:false,admin:false,memberships:[]})}
  },[])
  useEffect(()=>{
    const invalidate=()=>{++generation.current}
    void reload()
    if(!env.isSupabaseConfigured)return
    const {data:{subscription}}=getSupabase().auth.onAuthStateChange((event)=>{
      ++generation.current
      if(event==='SIGNED_OUT')setState({session:null,loading:false,admin:false,memberships:[]})
      else setTimeout(()=>void reload(),0)
    })
    return ()=>{invalidate();subscription.unsubscribe()}
  },[reload])
  return <SessionContext.Provider value={{...state,reload}}>{children}</SessionContext.Provider>
}
