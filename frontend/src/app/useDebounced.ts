import { useEffect, useState } from 'react'

// Atrasa um valor: a UI (input, URL) reage na hora, mas o efeito caro (fetch,
// filtro de lista grande) só dispara quando o valor para de mudar.
export function useDebounced<T>(value: T, delay: number): T {
  const [debounced, setDebounced] = useState(value)
  useEffect(() => {
    const t = setTimeout(() => setDebounced(value), delay)
    return () => clearTimeout(t)
  }, [value, delay])
  return debounced
}
