// Helpers de período mensal (YYYY-MM) — compartilhados por Gastos e Recorrentes.

const MONTHS = ['jan', 'fev', 'mar', 'abr', 'mai', 'jun', 'jul', 'ago', 'set', 'out', 'nov', 'dez']

// Mês corrente como "YYYY-MM".
export function currentPeriod(): string {
  const now = new Date()
  return `${now.getFullYear()}-${String(now.getMonth() + 1).padStart(2, '0')}`
}

// Avança/retrocede `delta` meses, preservando o formato "YYYY-MM".
export function shiftPeriod(period: string, delta: number): string {
  const [y, m] = period.split('-').map(Number)
  const d = new Date(y, m - 1 + delta, 1)
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}`
}

// Rótulo legível "mai · 2026".
export function periodLabel(period: string): string {
  const [y, m] = period.split('-').map(Number)
  return `${MONTHS[m - 1]} · ${y}`
}
