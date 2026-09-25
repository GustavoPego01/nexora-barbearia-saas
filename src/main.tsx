import { StrictMode } from 'react'
import { createRoot } from 'react-dom/client'
import { AppRouter } from './app/Router'
import { ErrorBoundary } from './components/ErrorBoundary'
import { defaultTheme } from './config/themes'
import './themes/base.css'
import './themes/app.css'

document.documentElement.dataset.theme = defaultTheme
const root = document.getElementById('root')
if (!root) throw new Error('Elemento raiz não encontrado.')

createRoot(root).render(
  <StrictMode><ErrorBoundary><AppRouter /></ErrorBoundary></StrictMode>,
)

if (import.meta.env.PROD && 'serviceWorker' in navigator) {
  window.addEventListener('load', () => { void navigator.serviceWorker.register('/sw.js').catch(() => {}) })
}
