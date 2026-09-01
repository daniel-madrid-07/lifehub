import { api } from "./api"

/** ¿El dispositivo soporta Web Push? (iPhone: solo en la PWA instalada) */
export function pushSupported(): boolean {
  return "serviceWorker" in navigator && "PushManager" in window && "Notification" in window
}

export function pushPermission(): NotificationPermission {
  return typeof Notification !== "undefined" ? Notification.permission : "denied"
}

export async function isSubscribed(): Promise<boolean> {
  if (!pushSupported()) return false
  const reg = await navigator.serviceWorker.getRegistration()
  if (!reg) return false
  const sub = await reg.pushManager.getSubscription()
  return sub !== null
}

/** Pide permiso, se suscribe y manda la suscripción al backend. */
export async function enablePush(): Promise<"ok" | "denied" | "unsupported"> {
  if (!pushSupported()) return "unsupported"
  const permission = await Notification.requestPermission()
  if (permission !== "granted") return "denied"

  const reg = await navigator.serviceWorker.ready
  const { key } = await api.push.vapid()
  if (!key) return "unsupported"

  let sub = await reg.pushManager.getSubscription()
  if (!sub) {
    sub = await reg.pushManager.subscribe({
      userVisibleOnly: true,
      applicationServerKey: urlBase64ToUint8Array(key) as BufferSource,
    })
  }
  await api.push.subscribe(sub.toJSON())
  return "ok"
}

function urlBase64ToUint8Array(base64: string): Uint8Array {
  const padding = "=".repeat((4 - (base64.length % 4)) % 4)
  const b64 = (base64 + padding).replace(/-/g, "+").replace(/_/g, "/")
  const raw = atob(b64)
  const out = new Uint8Array(raw.length)
  for (let i = 0; i < raw.length; i++) out[i] = raw.charCodeAt(i)
  return out
}
