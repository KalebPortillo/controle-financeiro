import { useState, type FormEvent } from 'react'
import { X } from 'lucide-react'
import { Button } from '../components/Button'
import { Input } from '../components/Input'
import { ApiError } from '../api/client'
import { useTags, useCreateTag, useDeleteTag, type Tag } from '../transactions/useTags'
import { SuggestedTagsList } from '../transactions/SuggestedTagsList'
import { useAdvanceOnboarding } from './useOnboarding'

/**
 * Passo 3 do onboarding (RF22) — tags. Mesmo modelo da página Tags:
 * - lista de tags ACEITAS (reais) no topo, com criar na hora + excluir;
 * - lista de tags SUGERIDAS pela IA abaixo (aceitar = vira real, recusar).
 * "Continuar" só avança (tagging→categorizing) — as tags já foram criadas
 * incrementalmente, então a transição dispara a 2ª análise (categorias).
 */
export function OnboardingStep2Tags() {
  const { data: tags, isLoading } = useTags()
  const createTag = useCreateTag()
  const advance = useAdvanceOnboarding()
  const [newName, setNewName] = useState('')
  const [error, setError] = useState<string | null>(null)

  const handleCreate = async (e: FormEvent) => {
    e.preventDefault()
    const name = newName.trim()
    if (!name) return
    setError(null)
    try {
      await createTag.mutateAsync(name)
      setNewName('')
    } catch (err) {
      setError(err instanceof ApiError ? err.message : 'Erro ao criar tag')
    }
  }

  return (
    <div className="space-y-6" data-testid="onboarding-step-tags">
      <div className="space-y-2">
        <h1 className="text-2xl font-semibold tracking-tight">Suas tags</h1>
        <p className="text-sm text-muted-foreground">
          Aceite as sugestões da IA ou crie as suas. As tags aceitas viram a base
          das suas categorias no próximo passo.
        </p>
      </div>

      <form onSubmit={handleCreate} className="flex gap-2 items-stretch">
        <Input
          value={newName}
          onChange={(e) => setNewName(e.target.value)}
          placeholder="Nova tag…"
          data-testid="new-tag-name"
        />
        <Button type="submit" disabled={createTag.isPending || !newName.trim()} data-testid="new-tag-submit">
          {createTag.isPending ? 'Criando…' : 'Adicionar'}
        </Button>
      </form>
      {error && <p className="text-xs text-destructive" role="alert">{error}</p>}

      <div className="border border-border rounded-lg overflow-hidden">
        {isLoading && <p className="text-xs text-muted-foreground px-4 py-3">Carregando…</p>}
        {!isLoading && (tags?.length ?? 0) === 0 && (
          <p className="text-sm text-muted-foreground px-4 py-3" data-testid="accepted-tags-empty">
            Nenhuma tag aceita ainda. Aceite uma sugestão abaixo ou crie a sua.
          </p>
        )}
        {tags?.map((tag) => (
          <AcceptedTagRow key={tag.id} tag={tag} />
        ))}
      </div>

      <SuggestedTagsList />

      <div className="flex items-center justify-end border-t border-border pt-4">
        <Button
          onClick={() => advance.mutate()}
          disabled={advance.isPending}
          data-testid="continue-tags"
        >
          {advance.isPending ? 'Continuando…' : 'Continuar'}
        </Button>
      </div>
    </div>
  )
}

function AcceptedTagRow({ tag }: { tag: Tag }) {
  const del = useDeleteTag()
  return (
    <div
      className="px-4 py-3 border-b border-border last:border-b-0 flex items-center gap-3"
      data-testid={`accepted-tag-${tag.id}`}
    >
      <span
        className="h-2.5 w-2.5 rounded-full shrink-0"
        style={{ background: tag.color || 'var(--muted-foreground)' }}
      />
      <span className="text-sm font-medium flex-1 min-w-0 truncate">{tag.name}</span>
      <Button
        variant="ghost"
        size="sm"
        onClick={() => del.mutate(tag.id)}
        disabled={del.isPending}
        aria-label={`Remover ${tag.name}`}
        data-testid={`remove-tag-${tag.id}`}
      >
        <X size={14} />
      </Button>
    </div>
  )
}
