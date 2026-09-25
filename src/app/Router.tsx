import { useEffect,useState } from 'react'
import { createBrowserRouter,Link,NavLink,Navigate,Outlet,RouterProvider,useLocation,useNavigate,useParams } from 'react-router-dom'
import { useSession } from './session'
import { SessionProvider } from './SessionProvider'
import { getSupabase } from '../lib/supabase'
import { records,rpc,type Row } from '../lib/api'
import { Profile } from '../features/Profile'
import { Auth } from '../features/Auth'
import { Catalog } from '../features/Catalog'
import { Settings,Hours } from '../features/Settings'
import { Admin } from '../features/Admin'
import { Agenda,CustomerArea,PublicPage } from '../features/Booking'
import { Reports,Commissions } from '../features/Reports'
import { Onboarding,Blocks,WhatsApp } from '../features/Setup'
import { Loading } from '../components/ui'
import { can,type Permission } from '../config/access'
function Guard({admin=false}:{admin?:boolean}){const s=useSession(),loc=useLocation();if(s.loading)return <Loading/>;if(!s.session)return <Navigate to={`/login?next=${encodeURIComponent(loc.pathname)}`} replace/>;if(admin&&!s.admin)return <Navigate to="/app" replace/>;return <Outlet/>}
function Home(){const s=useSession();if(s.loading)return <Loading/>;if(!s.session)return <Navigate to="/login" replace/>;if(s.admin)return <Navigate to="/admin" replace/>;const m=s.memberships.find(m=>m.active);return <Navigate to={m?`/app/${m.barbershop_id}/${m.role==='professional'?'agenda':'dashboard'}`:'/cliente'} replace/>}
const menu:{path:string;label:string;icon:string;permission:Permission}[]=[{path:'dashboard',label:'Visão geral',icon:'◫',permission:'reports:read'},{path:'agenda',label:'Agenda',icon:'▦',permission:'appointments:own'},{path:'clientes',label:'Clientes',icon:'◎',permission:'customers:manage'},{path:'servicos',label:'Serviços',icon:'✂',permission:'services:manage'},{path:'equipe',label:'Equipe',icon:'♙',permission:'team:manage'},{path:'horarios',label:'Horários',icon:'◷',permission:'team:manage'},{path:'bloqueios',label:'Bloqueios',icon:'⊘',permission:'team:manage'},{path:'financeiro',label:'Financeiro',icon:'↗',permission:'payments:manage'},{path:'configuracoes',label:'Configurações',icon:'⚙',permission:'settings:manage'},{path:'whatsapp',label:'WhatsApp',icon:'◉',permission:'settings:manage'}]
function Shell(){
 const s=useSession(),{tenant}=useParams(),loc=useLocation(),navigate=useNavigate(),[shop,setShop]=useState<Row|null>(null),[drawer,setDrawer]=useState(false)
 const member=s.memberships.find(m=>m.barbershop_id===tenant),role=member?.role??(s.admin?'owner':null)
 useEffect(()=>{setDrawer(false)},[loc.pathname])
 useEffect(()=>{let active=true;setShop(null);if(tenant)records('barbershops',tenant).then(rows=>{if(!active)return;const b=rows[0]??null;setShop(b);if(b){document.documentElement.dataset.theme=String(b.theme);document.documentElement.style.setProperty('--accent',String(b.primary_color))}}).catch(()=>{if(active)setShop(null)});return()=>{active=false}},[tenant,loc.pathname])
 if(tenant&&!member&&!s.admin)return <Navigate to="/app" replace/>
 const section=menu.find(m=>loc.pathname.endsWith('/'+m.path))
 if(tenant&&section&&!(section.path==='agenda'?(can(role,'appointments:own')||can(role,'appointments:manage')):can(role,section.permission)))return <Navigate to={`/app/${tenant}/agenda`} replace/>
 if(member&&!member.active)return <main className="startup"><h1>Conta indisponível</h1><p>Entre em contato com a administração da plataforma.</p><Link to="/cliente">Meus agendamentos</Link></main>
 if(tenant&&member?.role==='owner'&&!member.onboarding_completed_at&&!loc.pathname.includes('onboarding')&&!['configuracoes','servicos','equipe','horarios','whatsapp'].some(p=>loc.pathname.endsWith(p)))return <Navigate to={`/app/${tenant}/onboarding`} replace/>
 return <div className="app-shell"><aside className={drawer?'sidebar open':'sidebar'}><Link className="brand" to="/app">NEXORA<span>BARBER</span></Link><div className="shop-switch"><small>SEU ESPAÇO</small><strong>{shop?.name|| (s.admin?'Administração':'Área do cliente')}</strong>{s.memberships.length>0&&<select aria-label="Trocar barbearia" value={tenant??''} onChange={e=>navigate(`/app/${e.target.value}/dashboard`)}><option value="">Selecione</option>{s.memberships.map(m=><option value={m.barbershop_id} key={m.barbershop_id}>{m.name}</option>)}</select>}</div><nav>{tenant?menu.filter(m=>m.path==='agenda'?(can(role,'appointments:own')||can(role,'appointments:manage')):can(role,m.permission)).map(m=><NavLink key={m.path} to={`/app/${tenant}/${m.path}`}><span>{m.icon}</span>{m.label}</NavLink>):<NavLink to="/cliente">◎ Meus agendamentos</NavLink>}{tenant&&member?.role==='professional'&&<NavLink to={'/app/'+tenant+'/comissoes'}>Minhas comissões</NavLink>}{tenant&&member&&!member.onboarding_completed_at&&<NavLink to={`/app/${tenant}/onboarding`}>Concluir configuração</NavLink>}{s.admin&&<NavLink to="/admin">◇ Super Admin</NavLink>}</nav>{shop?.slug&&tenant&&<Link className="public-link" to={`/b/${shop.slug}`}>Página pública ↗</Link>}<div className="sidebar-bottom"><Link to="/perfil">Meu perfil</Link><small>{s.session?.user.email}</small><button onClick={()=>void getSupabase().auth.signOut()}>Sair da conta</button></div></aside><div className="workspace"><header className="topbar"><button className="menu-toggle" onClick={()=>setDrawer(!drawer)} aria-label="Abrir menu">☰</button><span>{tenant?'PAINEL DA BARBEARIA':'NEXORA BARBER'}</span><div className="actions"><span className="badge">{role==='owner'?'Proprietário':role??'Cliente'}</span><div className="avatar small">{s.session?.user.email?.slice(0,2).toUpperCase()}</div></div></header>{tenant&&s.admin&&!member&&<div className="support-banner">Modo suporte · acesso temporário e auditado <button onClick={async()=>{await rpc('end_support',{tenant});navigate('/admin')}}>Encerrar suporte</button></div>}<main className="content"><Outlet key={loc.pathname}/></main><footer className="app-footer">Nexora Barber · Seu negócio, bem cuidado.</footer></div></div>
}
function NotFound(){return <main className="startup"><h1>Página não encontrada</h1><Link to="/app">Voltar ao início</Link></main>}
const router=createBrowserRouter([
 {path:'/',element:<Home/>},{path:'/login',element:<Auth/>},{path:'/cadastro',element:<Auth mode="signup"/>},{path:'/recuperar-senha',element:<Auth mode="recover"/>},{path:'/redefinir-senha',element:<Auth mode="reset"/>},{path:'/b/:slug',element:<PublicPage/>},
 {element:<Guard/>,children:[{path:'/app',element:<Home/>},{element:<Shell/>,children:[{path:'/cliente',element:<CustomerArea/>},{path:'/perfil',element:<Profile/>}]},
 {path:'/app/:tenant',element:<Shell/>,children:[{index:true,element:<Navigate to="dashboard" replace/>},{path:'dashboard',element:<Reports dashboard/>},{path:'agenda',element:<Agenda/>},{path:'financeiro',element:<Reports/>},{path:'comissoes',element:<Commissions/>},{path:'configuracoes',element:<Settings/>},{path:'horarios',element:<Hours/>},{path:'onboarding',element:<Onboarding/>},{path:'bloqueios',element:<Blocks/>},{path:'whatsapp',element:<WhatsApp/>},{path:':module',element:<Catalog/>}]}]},
 {element:<Guard admin/>,children:[{element:<Shell/>,children:[{path:'/admin',element:<Admin/>}]}]},{path:'*',element:<NotFound/>},
])
export function AppRouter(){return <SessionProvider><RouterProvider router={router}/></SessionProvider>}
