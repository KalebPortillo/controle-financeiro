import { useState, useEffect } from 'react'
import { Tag, Plus, X, ArrowRight } from 'lucide-react'
import { useOnboarding } from './useOnboarding'

interface OnboardingStep2TagsProps {
  onAdvance: () => void
}

export function OnboardingStep2Tags({ onAdvance }: OnboardingStep2TagsProps) {
  const { state, saveTags } = useOnboarding()
  const [tags, setTags] = useState<string[]>([])
  const [input, setInput] = useState('')
  const [saving, setSaving] = useState(false)

  useEffect(() => {
    if (state?.discovered_tags) setTags(state.discovered_tags)
  }, [state?.discovered_tags])

  const handleAdd = () => {
    const trimmed = input.trim()
    if (trimmed && !tags.includes(trimmed)) {
      setTags([...tags, trimmed])
      setInput('')
    }
  }

  const handleRemove = (tag: string) => {
    setTags(tags.filter((t) => t !== tag))
  }

  const handleContinue = async () => {
    setSaving(true)
    try {
      await saveTags(tags)
      onAdvance()
    } finally {
      setSaving(false)
    }
  }

  return (
    <div className="flex flex-col gap-6">
      <div className="flex flex-col gap-2">
        <Tag className="size-6 text-violet" />
        <h1 className="text-2xl font-semibold text-fg">Adicione tags</h1>
        <p className="text-sm text-fg-muted">
          Tags ajudam a organizar seus gastos
        </p>
      </div>
      <div className="flex gap-2">
        <input
          value={input}
          onChange={(e) => setInput(e.target.value)}
          onKeyDown={(e) => e.key === 'Enter' && handleAdd()}
          placeholder="Nome da tag"
          className="flex-1 rounded-md border border-border bg-bg px-3 py-2 text-sm text-fg"
        />
        <button
          onClick={handleAdd}
          aria-label="Adicionar tag"
          className="flex items-center gap-1 rounded-md bg-violet px-3 py-2 text-sm text-white"
        >
          <Plus className="size-4" />
        </button>
      </div>
      <div className="flex flex-wrap gap-2">
        {tags.map((tag) => (
          <span
            key={tag}
            className="flex items-center gap-1 rounded-md border border-border px-2 py-1 text-sm text-fg"
          >
            {tag}
            <button onClick={() => handleRemove(tag)} aria-label={`Remover ${tag}`}>
              <X className="size-3 text-fg-muted" />
            </button>
          </span>
        ))}
      </div>
      <button
        onClick={handleContinue}
        disabled={saving}
        className="flex items-center justify-center gap-2 rounded-md bg-violet px-4 py-2 text-sm text-white disabled:opacity-60"
      >
        Continuar
        <ArrowRight className="size-4" />
      </button>
    </div>
  )
}
