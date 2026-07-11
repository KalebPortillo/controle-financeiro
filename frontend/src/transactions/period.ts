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

// Intervalo ISO (from/to) de um mês "YYYY-MM" — do dia 1 ao último dia.
export function monthRange(period: string): { from: string; to: string } {
  const [y, m] = period.split('-').map(Number)
  const from = new Date(y, m - 1, 1)
  const to = new Date(y, m, 0) // dia 0 do mês seguinte = último dia deste mês
  const fmt = (d: Date) =>
    `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`
  return { from: fmt(from), to: fmt(to) }
}

// Rótulo curto de uma data ISO "YYYY-MM-DD" → "5 mai".
export function shortDateLabel(iso: string): string {
  const [y, m, d] = iso.split('-').map(Number)
  if (!y || !m || !d) return iso
  return `${d} ${MONTHS[m - 1]}`
}
