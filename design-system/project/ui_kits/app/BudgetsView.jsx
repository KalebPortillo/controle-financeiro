// ============================================================
// Budgets view — list of monthly budget cards w/ progress bars
// ============================================================

const { Plus, ChevronRight } = window.CFIcons;
const { Card, Button, ProgressBar, Money } = window.CFUI;
const { BUDGETS, tagsById, categoriesById, fmtBRL } = window.CFData;

function BudgetCard({ b }) {
  const pct = (b.spent / b.cap) * 100;
  const remaining = b.cap - b.spent;
  const scopeLabel = b.scope === 'tag'
    ? tagsById[b.tagId]?.name
    : categoriesById[b.categoryId]?.name;
  // Mock end-of-month projection
  const projected = b.spent * 1.4;

  // Pct label gets the vibrant color, the bar stays neutral.
  const pctColor =
    pct >= 100 ? 'var(--destructive-vivid)' :
    pct >= 80  ? 'var(--warning-vivid)'    :
                 'var(--success-vivid)';

  return (
    <Card padding={20}>
      <div className="cf-budget__head">
        <div>
          <div className="cf-budget__name">{b.name}</div>
          <div className="cf-caption">
            {b.scope === 'tag' ? 'tag · ' : 'categoria · '}{scopeLabel}
          </div>
        </div>
        <button className="cf-iconbtn" aria-label="Detalhes">
          <ChevronRight size={16} />
        </button>
      </div>

      <div className="cf-budget__amount">
        <Money value={b.spent} mono size={22} />
        <span className="cf-caption" style={{ marginLeft: 8 }}>
          de {fmtBRL(b.cap)}
        </span>
      </div>

      <ProgressBar value={b.spent} max={b.cap} />

      <div className="cf-budget__foot">
        <span className="cf-money" style={{ color: pctColor, fontWeight: 600, fontSize: 13 }}>
          {pct >= 100 ? `+${Math.round(pct - 100)}% acima` : `${Math.round(pct)}%`}
        </span>
        <span className="cf-caption">
          Projeção fim do mês: {fmtBRL(projected)}
        </span>
      </div>
    </Card>
  );
}

function BudgetsView() {
  return (
    <div className="cf-budgets">
      <div className="cf-page-head">
        <div>
          <div className="cf-caption">Maio · 2026</div>
          <h2 className="cf-h1" style={{ margin: '4px 0 0' }}>Orçamentos</h2>
        </div>
        <Button variant="primary" icon={<Plus size={14} />}>Novo orçamento</Button>
      </div>

      <div className="cf-budgets__grid">
        {BUDGETS.map(b => <BudgetCard key={b.id} b={b} />)}
      </div>
    </div>
  );
}

window.CFBudgets = { BudgetsView };
