import { useEffect,useRef,type ReactNode } from 'react'
export function Header({title,subtitle,children}:{title:string;subtitle?:string;children?:ReactNode}){
 return <header className="page-header"><div><p className="eyebrow">SEU NEGÓCIO, BEM CUIDADO</p><h1>{title}</h1>{subtitle&&<p>{subtitle}</p>}</div><div className="actions">{children}</div></header>
}
export function Notice({text}:{text:string}){return text?<p className="notice" role="status">{text}</p>:null}
export function Loading(){return <div className="skeleton" role="status" aria-label="Carregando dados"/>}
export function Empty({text='Nenhum registro por aqui ainda.'}:{text?:string}){return <div className="empty"><span>✂</span><p>{text}</p></div>}
export function Modal({title,close,children}:{title:string;close:()=>void;children:ReactNode}){
 const ref=useRef<HTMLDialogElement>(null)
 useEffect(()=>{ref.current?.showModal()},[])
 return <dialog ref={ref} onCancel={close}><div className="modal-head"><h2>{title}</h2><button type="button" className="quiet" onClick={close} aria-label="Fechar">×</button></div>{children}</dialog>
}
export function Field({label,children}:{label:string;children:ReactNode}){return <label className="field"><span>{label}</span>{children}</label>}
