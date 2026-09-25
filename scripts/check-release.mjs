import assert from 'node:assert/strict'
import { readdir, readFile } from 'node:fs/promises'
const root=new URL('../dist/',import.meta.url)
const allowed=new Set(['index.html','sw.js','manifest.webmanifest','icon-192.png','icon-512.png','_headers','_redirects'])
async function check(path=''){
 for(const entry of await readdir(new URL(path,root),{withFileTypes:true})){
  const name=path+entry.name
  if(entry.isDirectory()){
   assert.equal(name,'assets','Diretório inesperado na publicação: '+name)
   await check(name+'/')
  }else{
   assert.ok(allowed.has(name)||/^assets\/[\w.-]+\.(js|css|woff2?|png|svg|webp|jpg)$/.test(name),'Arquivo interno ou inesperado na publicação: '+name)
   if(/\.(html|js|css|webmanifest)$/.test(name)){
    const text=await readFile(new URL(name,root),'utf8')
    assert.ok(!/sb_secret_[\w-]{20,}|sbp_[\w-]{20,}|-----BEGIN .*PRIVATE KEY-----/.test(text),'Segredo detectado na publicação')
    for(const jwt of text.matchAll(/eyJ[\w-]+\.([\w-]+)\.[\w-]+/g)){
     let payload
     try{payload=JSON.parse(Buffer.from(jwt[1],'base64url').toString())}catch{continue}
     assert.notEqual(payload.role,'service_role','Chave de serviço detectada na publicação')
    }
    assert.ok(!/sourceMappingURL=/.test(text),'Source map não deve ser publicado')
   }
  }
 }
}
await check()
assert.ok((await readFile(new URL('index.html',root),'utf8')).includes('/assets/'))
process.stdout.write('Publicação: somente arquivos do site, sem documentos internos, credenciais ou source maps.\n')
