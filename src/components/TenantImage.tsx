import { useEffect,useState } from 'react'
import { getSupabase } from '../lib/supabase'
export function TenantImage({bucket,path,alt,className='record-photo'}:{bucket:string;path:unknown;alt:string;className?:string}){
 const [url,setUrl]=useState('')
 useEffect(()=>{let current=true;setUrl('');if(typeof path==='string'&&path)getSupabase().storage.from(bucket).createSignedUrl(path,300).then(({data})=>{if(current&&data)setUrl(data.signedUrl)});return()=>{current=false}},[bucket,path])
 return url?<img src={url} alt={alt} className={className} loading="lazy"/>:null
}
