import { useEffect,useState,type FormEvent } from 'react'
import { Link,useNavigate,useSearchParams } from 'react-router-dom'
import { getSupabase } from '../lib/supabase'
import { Field,Notice } from '../components/ui'
import { useSession } from '../app/session'
export function Auth({mode='login'}:{mode?:'login'|'signup'|'recover'|'reset'}){
 const auth=useSession()
 const [notice,setNotice]=useState(''),[busy,setBusy]=useState(false)
 const [redirect,setRedirect]=useState(false)
 const navigate=useNavigate(),[params]=useSearchParams()
 const candidate=params.get('next'),next=candidate?.startsWith('/')&&!candidate.startsWith('//')&&!candidate.includes('\\')?candidate:'/app'
 useEffect(()=>{if(redirect&&auth.session&&!auth.loading)navigate(next)},[redirect,auth.session,auth.loading,navigate,next])
 const titles={login:'Bem-vindo de volta.',signup:'Seu próximo horário começa aqui.',recover:'Recupere seu acesso.',reset:'Escolha uma nova senha.'}
 async function submit(e:FormEvent<HTMLFormElement>){e.preventDefault();setBusy(true);setNotice('');const f=new FormData(e.currentTarget)
  const email=String(f.get('email')),password=String(f.get('password'));let error
  try{
   if(mode==='login')({error}=await getSupabase().auth.signInWithPassword({email,password}))
   if(mode==='signup')({error}=await getSupabase().auth.signUp({email,password,options:{emailRedirectTo:location.origin+'/login?next='+encodeURIComponent(next)}}))
   if(mode==='recover')({error}=await getSupabase().auth.resetPasswordForEmail(email,{redirectTo:location.origin+'/redefinir-senha'}))
   if(mode==='reset')({error}=await getSupabase().auth.updateUser({password}))
   if(error)setNotice('Confira os dados. Se necessário, confirme seu e-mail ou recupere a senha.')
   else if(mode==='login'||mode==='reset'){await auth.reload();setRedirect(true)}
   else setNotice('Confira sua caixa de entrada para concluir a solicitação. Se o e-mail não chegar, aguarde antes de tentar novamente.')
  }catch{setNotice('Não foi possível conectar. Tente novamente.')}finally{setBusy(false)}
 }
 return <main className="auth"><section className="auth-story"><Link className="brand" to="/">NEXORA<span>BARBER</span></Link><div><p className="eyebrow">MAIS TEMPO PARA O QUE IMPORTA</p><h1>Sua barbearia.<br/>No próximo nível.</h1><p>Agenda, equipe e clientes em um só lugar.</p></div><small>Gestão feita para o seu ritmo.</small></section><section className="auth-form"><h2>{titles[mode]}</h2><p>{mode==='login'?'Entre para acessar seu espaço.':'Preencha os dados para continuar.'}</p><form onSubmit={submit}>
 {mode!=='reset'&&<Field label="E-mail"><input name="email" type="email" required autoComplete="email"/></Field>}
 {mode!=='recover'&&<Field label="Senha"><input name="password" type="password" minLength={8} required autoComplete={mode==='login'?'current-password':'new-password'}/></Field>}
 <Notice text={notice}/><button className="primary" disabled={busy}>{busy?'Aguarde…':mode==='login'?'Entrar':mode==='signup'?'Criar conta':'Continuar'}</button></form>
 <div className="auth-links"><Link to={`/login?next=${encodeURIComponent(next)}`}>Entrar</Link><Link to={`/cadastro?next=${encodeURIComponent(next)}`}>Criar conta</Link><Link to="/recuperar-senha">Esqueci a senha</Link></div></section></main>
}
