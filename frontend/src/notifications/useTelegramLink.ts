import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { apiFetch } from '../api/client'

export type TelegramLinkStatus = {
  linked: boolean
  chat_title: string | null
  linked_at: string | null
}

export type TelegramLinkCode = {
  deep_link: string
  expires_at: string
}

export const telegramLinkKey = ['telegram_link'] as const

/**
 * Status do vínculo Telegram do workspace (RF17). `poll` liga refetch de 3s —
 * usado enquanto o card aguarda o usuário concluir o /start no grupo.
 */
export function useTelegramLink(poll = false) {
  return useQuery({
    queryKey: telegramLinkKey,
    queryFn: () => apiFetch<TelegramLinkStatus>('/api/v1/telegram_link'),
    refetchInterval: poll ? 3000 : false,
  })
}

export function useCreateTelegramLink() {
  return useMutation({
    mutationFn: () =>
      apiFetch<TelegramLinkCode>('/api/v1/telegram_link', { method: 'POST' }),
  })
}

export function useUnlinkTelegram() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: () => apiFetch('/api/v1/telegram_link', { method: 'DELETE' }),
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: telegramLinkKey })
    },
  })
}
