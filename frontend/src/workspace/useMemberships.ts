import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query'
import { apiFetch, ApiError } from '../api/client'

export type Membership = {
  id: string
  role: 'editor' | 'viewer'
  joined_at: string
  user: { id: string; email: string; name: string; avatar_url: string | null }
}

export const membershipsKey = (workspaceId: string) => ['memberships', workspaceId] as const

export function useMemberships(workspaceId: string | null | undefined) {
  return useQuery({
    queryKey: membershipsKey(workspaceId ?? '_'),
    enabled: !!workspaceId,
    queryFn: () =>
      apiFetch<{ memberships: Membership[] }>(
        `/api/v1/workspaces/${workspaceId}/memberships`
      ).then((r) => r.memberships),
  })
}

export function useInviteByEmail(workspaceId: string) {
  const qc = useQueryClient()
  return useMutation<Membership, ApiError, string>({
    mutationFn: (email: string) =>
      apiFetch<{ membership: Membership }>(`/api/v1/workspaces/${workspaceId}/memberships`, {
        method: 'POST',
        body: { email },
      }).then((r) => r.membership),
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: membershipsKey(workspaceId) })
    },
  })
}
