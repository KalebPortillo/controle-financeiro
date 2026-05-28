import { useQuery } from '@tanstack/react-query'
import { apiFetch } from './client'

/**
 * Config pública do app, decidida pelo backend em runtime (RAILS_ENV). Não é
 * build-time: staging e produção rodam a mesma imagem, então o que muda entre
 * eles (ex.: sandbox do Pluggy) vem daqui, não de `import.meta.env`.
 */
export type AppConfig = {
  environment: string
  pluggy: {
    include_sandbox: boolean
    connector_ids: number[] | null
  }
}

export function useAppConfig() {
  return useQuery({
    queryKey: ['app_config'],
    queryFn: () => apiFetch<AppConfig>('/api/v1/app_config'),
    staleTime: Infinity, // não muda durante a sessão.
  })
}
