import { useCallback, useEffect, useRef, useState } from "react"

/** Carga datos async con estado de error, recarga y refresco manual. */
export function useLoad<T>(fn: () => Promise<T>) {
  const [data, setData] = useState<T | null>(null)
  const [error, setError] = useState<string | null>(null)
  const [refreshing, setRefreshing] = useState(false)
  const fnRef = useRef(fn)
  fnRef.current = fn

  const reload = useCallback(async () => {
    setError(null)
    setRefreshing(true)
    try {
      setData(await fnRef.current())
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e))
    } finally {
      setRefreshing(false)
    }
  }, [])

  useEffect(() => {
    reload()
  }, [reload])

  return { data, setData, error, refreshing, reload }
}
