import assert from 'node:assert/strict'
import { chromium } from '@playwright/test'
const browser=await chromium.launch({channel:'msedge',headless:true})
try{
 const context=await browser.newContext(),page=await context.newPage()
 const base='http://127.0.0.1:4173'
 await page.goto(base+'/login')
 await page.evaluate(()=>navigator.serviceWorker.ready)
 await page.reload({waitUntil:'networkidle'})
 const manifest=await (await page.request.get(base+'/manifest.webmanifest')).json()
 assert.equal(manifest.display,'standalone')
 assert.equal(manifest.icons.length,2)
 const cached=await page.evaluate(async()=>{const names=await caches.keys();return (await Promise.all(names.map(async n=>(await(await caches.open(n)).keys()).map(r=>r.url)))).flat()})
 assert.ok(cached.some(u=>u.includes('/assets/')))
 assert.ok(cached.every(u=>new URL(u).origin===locationOrigin(base)&&!u.includes('/rest/')&&!u.includes('/auth/')))
 await context.setOffline(true)
 await page.goto(base+'/login')
 await page.getByRole('heading',{name:'Bem-vindo de volta.',exact:true}).waitFor()
 process.stdout.write('PWA: manifest, service worker, shell offline e ausência de dados privados no cache: OK.\n')
}finally{await browser.close()}
function locationOrigin(url){return new URL(url).origin}
