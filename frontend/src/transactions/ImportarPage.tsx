import { useRef, useState } from 'react'
import { Upload, FileText, CheckCircle2, AlertTriangle } from 'lucide-react'
import { Badge } from '../components/Badge'
import { ApiError } from '../api/client'
import { useImports, useImport, useCreateImport, type Import } from './useImports'

/**
 * RF20 — importação de extratos por arquivo (CSV no MVP). Sobe o arquivo, mostra
 * o processamento (status processing) e o resumo ao fim (criados/duplicados/
 * erros), com o histórico de importações abaixo.
 */
export function ImportarPage() {
  const create = useCreateImport()
  const [activeId, setActiveId] = useState<string | null>(null)
  const [error, setError] = useState<string | null>(null)
  const { data: active } = useImport(activeId)
  const inputRef = useRef<HTMLInputElement>(null)

  const upload = async (file: File) => {
    setError(null)
    try {
      const imp = await create.mutateAsync({ file })
      setActiveId(imp.id)
    } catch (err) {
      setError(err instanceof ApiError ? err.message : 'Falha ao enviar o arquivo')
    }
  }

  const onPick = (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0]
    if (file) upload(file)
  }

  return (
    <div className="max-w-2xl mx-auto space-y-6">
      <section className="space-y-1">
        <div className="flex items-center gap-2">
          <Upload className="size-5" />
          <h1 className="font-sans text-2xl font-semibold tracking-tight">Importar arquivo</h1>
        </div>
        <p className="text-sm text-muted-foreground">
          Suba um extrato em CSV. Os lançamentos caem na inbox pra você revisar.
        </p>
      </section>

      <button
        type="button"
        onClick={() => inputRef.current?.click()}
        disabled={create.isPending}
        className="w-full border border-dashed border-border rounded-lg py-10 flex flex-col items-center gap-2 text-muted-foreground hover:bg-muted/50 disabled:opacity-50"
        data-testid="upload-dropzone"
      >
        <FileText size={24} />
        <span className="text-sm">{create.isPending ? 'Enviando…' : 'Selecionar arquivo CSV'}</span>
      </button>
      <input
        ref={inputRef}
        type="file"
        accept=".csv,text/csv"
        className="hidden"
        onChange={onPick}
        data-testid="file-input"
      />
      {error && <p className="text-xs text-destructive" role="alert">{error}</p>}

      {active && <ActiveImport import={active} />}

      <ImportHistory />
    </div>
  )
}

function ActiveImport({ import: imp }: { import: Import }) {
  const processing = imp.status === 'pending' || imp.status === 'processing'
  return (
    <div className="border border-border rounded-lg p-4 space-y-2" data-testid="active-import">
      <div className="flex items-center gap-2 text-sm font-medium">
        <FileText size={15} />
        {imp.filename}
        <ImportStatusBadge status={imp.status} />
      </div>
      {processing && (
        <div className="h-1.5 w-full overflow-hidden rounded-full bg-muted">
          <div className="h-full w-1/2 rounded-full bg-accent animate-pulse" />
        </div>
      )}
      {imp.status === 'completed' && <ImportSummary import={imp} />}
      {imp.status === 'failed' && (
        <p className="text-xs text-destructive">{imp.error_log[0]?.message ?? 'Falha no processamento'}</p>
      )}
    </div>
  )
}

function ImportSummary({ import: imp }: { import: Import }) {
  const [showErrors, setShowErrors] = useState(false)
  return (
    <div className="space-y-1.5">
      <p className="text-sm" data-testid="import-summary">
        <strong>{imp.created_count}</strong> criados · <strong>{imp.duplicate_count}</strong> duplicados
        {imp.error_count > 0 && <> · <strong>{imp.error_count}</strong> com erro</>}
      </p>
      {imp.error_count > 0 && (
        <button
          type="button"
          onClick={() => setShowErrors((v) => !v)}
          className="text-xs text-muted-foreground hover:text-foreground underline"
          data-testid="toggle-errors"
        >
          {showErrors ? 'Ocultar detalhes' : 'Ver detalhes'}
        </button>
      )}
      {showErrors && (
        <ul className="text-[11px] text-muted-foreground space-y-0.5" data-testid="error-details">
          {imp.error_log.map((e, i) => (
            <li key={i} className="flex items-center gap-1.5">
              <AlertTriangle size={11} className="text-destructive shrink-0" />
              {e.row ? `Linha ${e.row}: ` : ''}{e.message}
            </li>
          ))}
        </ul>
      )}
    </div>
  )
}

function ImportHistory() {
  const { data: imports, isLoading } = useImports()
  if (isLoading) return null
  if (!imports || imports.length === 0) return null

  return (
    <section className="space-y-2">
      <h2 className="text-sm font-medium">Importações anteriores</h2>
      <div className="border border-border rounded-lg overflow-hidden">
        {imports.map((imp) => (
          <div
            key={imp.id}
            className="px-4 py-3 border-b border-border last:border-b-0 flex items-center gap-3"
            data-testid={`import-row-${imp.id}`}
          >
            <FileText size={15} className="text-muted-foreground shrink-0" />
            <span className="text-sm flex-1 min-w-0 truncate">{imp.filename}</span>
            {imp.status === 'completed' && (
              <span className="text-xs text-muted-foreground">
                {imp.created_count} criados · {imp.duplicate_count} dup
              </span>
            )}
            <ImportStatusBadge status={imp.status} />
          </div>
        ))}
      </div>
    </section>
  )
}

function ImportStatusBadge({ status }: { status: Import['status'] }) {
  if (status === 'completed') {
    return (
      <Badge variant="secondary">
        <CheckCircle2 size={11} className="text-success" /> concluído
      </Badge>
    )
  }
  if (status === 'failed') return <Badge variant="destructive">falhou</Badge>
  return <Badge variant="outline">processando</Badge>
}
