import { useState, type FormEvent } from 'react'
import { Card, CardBody, CardHeader } from '../components/Card'
import { Button } from '../components/Button'
import { Input } from '../components/Input'
import { ApiError } from '../api/client'
import { useMemberships, useInviteByEmail, type Membership } from './useMemberships'

/**
 * Cartão "Membros" — lista quem está no workspace e expõe o convite por
 * email (RF16.3). Erro `user_not_found` vira mensagem específica em PT-BR;
 * outros erros mostram a mensagem do backend.
 */
export function MembersCard({ workspaceId }: { workspaceId: string }) {
  const { data: members, isLoading } = useMemberships(workspaceId)
  const invite = useInviteByEmail(workspaceId)
  const [email, setEmail] = useState('')
  const [feedback, setFeedback] = useState<
    { kind: 'ok' | 'error'; message: string } | null
  >(null)

  const handleSubmit = async (e: FormEvent) => {
    e.preventDefault()
    if (!email.trim()) return
    setFeedback(null)
    try {
      await invite.mutateAsync(email.trim())
      setEmail('')
      setFeedback({ kind: 'ok', message: 'Convite adicionado' })
    } catch (err) {
      if (err instanceof ApiError && err.code === 'user_not_found') {
        setFeedback({
          kind: 'error',
          message: 'Esse email ainda não tem conta. Peça pra entrar primeiro com o Google.',
        })
      } else if (err instanceof ApiError) {
        setFeedback({ kind: 'error', message: err.message })
      } else {
        setFeedback({ kind: 'error', message: 'Erro inesperado. Tente de novo.' })
      }
    }
  }

  return (
    <Card>
      <CardHeader>
        <h2 className="font-sans text-sm font-medium">Membros</h2>
        <p className="text-xs text-muted-foreground">
          Ambos os membros têm visão e edição completas.
        </p>
      </CardHeader>

      <CardBody className="pt-0 space-y-4">
        <ul className="space-y-2" data-testid="members-list">
          {isLoading && (
            <li className="text-xs text-muted-foreground">Carregando…</li>
          )}
          {members?.map((m) => (
            <MemberRow key={m.id} member={m} />
          ))}
        </ul>

        <form onSubmit={handleSubmit} className="flex gap-2 items-stretch">
          <Input
            type="email"
            placeholder="email@exemplo.com"
            value={email}
            onChange={(e) => setEmail(e.target.value)}
            required
            data-testid="invite-email"
          />
          <Button
            type="submit"
            size="md"
            disabled={invite.isPending || !email.trim()}
            data-testid="invite-submit"
          >
            {invite.isPending ? 'Adicionando…' : 'Convidar'}
          </Button>
        </form>

        {feedback && (
          <p
            role={feedback.kind === 'error' ? 'alert' : 'status'}
            className={
              feedback.kind === 'error'
                ? 'text-xs text-destructive'
                : 'text-xs text-success'
            }
            data-testid="invite-feedback"
          >
            {feedback.message}
          </p>
        )}
      </CardBody>
    </Card>
  )
}

function MemberRow({ member }: { member: Membership }) {
  return (
    <li className="flex items-center gap-3 py-1">
      <div className="h-8 w-8 rounded-full bg-muted flex items-center justify-center text-xs font-medium text-muted-foreground overflow-hidden shrink-0">
        {member.user.avatar_url ? (
          <img src={member.user.avatar_url} alt="" className="h-full w-full object-cover" />
        ) : (
          member.user.name.charAt(0).toUpperCase()
        )}
      </div>
      <div className="leading-tight min-w-0">
        <div className="text-xs font-medium text-foreground truncate">{member.user.name}</div>
        <div className="text-[11px] text-muted-foreground truncate">{member.user.email}</div>
      </div>
    </li>
  )
}
