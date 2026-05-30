import { useState, useEffect } from 'react'
import { FolderTree, Plus, X, Check } from 'lucide-react'
import { useOnboarding } from './useOnboarding'

interface OnboardingStep3CategoriesProps {
  onComplete: () => void
}

export function OnboardingStep3Categories({ onComplete }: OnboardingStep3CategoriesProps) {
  const { state, saveCategories } = useOnboarding()
  const [categories, setCategories] = useState<string[]>([])
  const [input, setInput] = useState('')
  const [saving, setSaving] = useState(false)

  useEffect(() => {
    if (state?.discovered_categories) setCategories(state.discovered_categories)
  }, [state?.discovered_categories])

  const handleAdd = () => {
    const trimmed = input.trim()
    if (trimmed && !categories.includes(trimmed)) {
      setCategories([...categories, trimmed])
      setInput('')
    }
  }

  const handleRemove = (cat: string) => {
    setCategories(categories.filter((c) => c !== cat))
  }

  const handleComplete = async () => {
    setSaving(true)
    try {
      await saveCategories(categories)
      onComplete()
    } finally {
      setSaving(false)
    }
  }

  return (
    <div className="flex flex-col gap-6">
      <div className="flex flex-col gap-2">
        <FolderTree className="size-6 text-violet" />
        <h1 className="text-2xl font-semibold text-fg">Crie categorias</h1>
        <p className="text-sm text-fg-muted">
          Categorias agrupam seus gastos por tema
        </p>
      </div>
      <div className="flex gap-2">
        <input
          value={input}
          onChange={(e) => setInput(e.target.value)}
          onKeyDown={(e) => e.key === 'Enter' && handleAdd()}
          placeholder="Nome da categoria"
          className="flex-1 rounded-md border border-border bg-bg px-3 py-2 text-sm text-fg"
        />
        <button
          onClick={handleAdd}
          aria-label="Adicionar categoria"
          className="flex items-center gap-1 rounded-md bg-violet px-3 py-2 text-sm text-white"
        >
          <Plus className="size-4" />
        </button>
      </div>
      <div className="flex flex-wrap gap-2">
        {categories.map((cat) => (
          <span
            key={cat}
            className="flex items-center gap-1 rounded-md border border-border px-2 py-1 text-sm text-fg"
          >
            {cat}
            <button onClick={() => handleRemove(cat)} aria-label={`Remover ${cat}`}>
              <X className="size-3 text-fg-muted" />
            </button>
          </span>
        ))}
      </div>
      <button
        onClick={handleComplete}
        disabled={saving}
        className="flex items-center justify-center gap-2 rounded-md bg-violet px-4 py-2 text-sm text-white disabled:opacity-60"
      >
        Concluir
        <Check className="size-4" />
      </button>
    </div>
  )
}
