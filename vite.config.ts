import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'
import { readFileSync,writeFileSync } from 'node:fs'
import { resolve } from 'node:path'

export default defineConfig({ plugins: [react(),{
  name:'version-service-worker',
  apply:'build',
  writeBundle(options){
    const path=resolve(options.dir??'dist','sw.js')
    writeFileSync(path,readFileSync(path,'utf8').replace('nexora-shell-v1',`nexora-shell-${Date.now()}`))
  },
}] })
