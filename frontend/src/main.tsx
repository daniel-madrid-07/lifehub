import { StrictMode } from 'react'
import { createRoot } from 'react-dom/client'
import { MotionConfig } from 'framer-motion'
import './index.css'
import App from './App.tsx'
import AuthGate from './components/AuthGate.tsx'

createRoot(document.getElementById('root')!).render(
  <StrictMode>
    <MotionConfig reducedMotion="user">
      <AuthGate>
        <App />
      </AuthGate>
    </MotionConfig>
  </StrictMode>,
)

// Service worker (necesario para las notificaciones push)
if ("serviceWorker" in navigator) {
  window.addEventListener("load", () => {
    navigator.serviceWorker.register("/sw.js").catch(() => {})
  })
}

// iOS no deja bloquear la rotación: en horizontal (solo móvil) rotamos toda la
// app 90° para que se siga viendo vertical. El sentido depende de hacia qué
// lado se gire el teléfono (data-rotate "cw" o "ccw").
function applyOrientation() {
  const root = document.documentElement
  const landscapeSmall = window.innerWidth > window.innerHeight && window.innerHeight <= 600
  if (!landscapeSmall) {
    delete root.dataset.rotate
    return
  }
  const legacy = (window as unknown as { orientation?: number }).orientation
  const angle = screen?.orientation?.angle ?? legacy ?? 0
  root.dataset.rotate = angle === 270 || angle === -90 ? "cw" : "ccw"
}
window.addEventListener("resize", applyOrientation)
window.addEventListener("orientationchange", applyOrientation)
applyOrientation()
