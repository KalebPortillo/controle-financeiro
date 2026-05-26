// ============================================================
// Gastos consolidados — accepted spends with filters.
// Same row anatomy as inbox; no checkboxes; period totals shown.
// ============================================================

const { Filter, ChevronDown, CreditCard, Plus } = window.CFIcons;
const { Button, Badge, TagChip, Money } = window.CFUI;
const { tagsById, accountsById, fmtBRL, fmtDate } = window.CFData;

// A handful of consolidated spends — narrative-y mock.
const CONSOLIDATED = [
  { id: 'g_1', title: 'Mercado da semana', amount: -312.40, date: '2026-05-19', accountId: 'a_nu_cor', tagIds: ['t_mercado'], person: 'Kaleb' },
  { id: 'g_2', title: 'Condomínio',         amount: -740.00, date: '2026-05-18', accountId: 'a_nu_cor', tagIds: ['t_casa'], person: 'Ana', recurring: true },
  { id: 'g_3', title: 'Salário maio',       amount:  6500.00,date: '2026-05-05', accountId: 'a_nu_cor', tagIds: [], person: 'Kaleb', recurring: true, kind: 'income' },
  { id: 'g_4', title: 'Pizza sexta',        amount: -89.90,  date: '2026-05-15', accountId: 'a_nu_cc',  tagIds: ['t_comida_fora'], person: 'Kaleb' },
  { id: 'g_5', title: 'Farmácia',           amount: -84.30,  date: '2026-05-20', accountId: 'a_nu_ana', tagIds: ['t_saude'], person: 'Ana' },
  { id: 'g_6', title: 'Uber centro',        amount: -19.80,  date: '2026-05-17', accountId: 'a_nu_cc',  tagIds: ['t_transporte'], person: 'Kaleb' },
  { id: 'g_7', title: 'Netflix',            amount: -55.90,  date: '2026-05-16', accountId: 'a_nu_cc',  tagIds: ['t_assinatura','t_lazer'], person: 'Kaleb', recurring: true },
  { id: 'g_8', title: 'Curso Inglês · 3/12',amount: -180.00, date: '2026-05-14', accountId: 'a_nu_cc',  tagIds: ['t_lazer'], person: 'Ana', installment: '3/12' },
];

function ConsolidatedRow({ tx }) {
  const tags = tx.tagIds.map(id => tagsById[id]).filter(Boolean);
  const account = accountsById[tx.accountId];
  return (
    <div className="cf-row cf-row--consolidated">
      <div style={{ width: 8 }} />
      <div className="cf-row__main">
        <div className="cf-row__title">
          <span>{tx.title}</span>
          {tx.recurring ? <Badge variant="outline">recorrente</Badge> : null}
          {tx.installment ? <Badge variant="secondary">{tx.installment}</Badge> : null}
        </div>
        <div className="cf-row__meta">
          <CreditCard size={12} />
          <span>{account?.name}</span>
          <span className="cf-row__dot">·</span>
          <span>{fmtDate(tx.date)}</span>
          <span className="cf-row__dot">·</span>
          <span>{tx.person}</span>
        </div>
      </div>
      <div className="cf-row__tags">
        {tags.slice(0,2).map(t => <TagChip key={t.id} tag={t} />)}
        {tags.length > 2 ? <span className="cf-caption">+{tags.length - 2}</span> : null}
      </div>
      <div className="cf-row__amount">
        <Money value={tx.amount} signed size={14} />
      </div>
    </div>
  );
}

function GastosView() {
  const totalSpent = CONSOLIDATED.filter(t => t.amount < 0).reduce((s,t) => s + t.amount, 0);
  const totalRecv  = CONSOLIDATED.filter(t => t.amount > 0).reduce((s,t) => s + t.amount, 0);

  return (
    <div className="cf-gastos">
      <div className="cf-page-head">
        <div>
          <div className="cf-caption">Maio · 2026 · todas as contas</div>
          <h2 className="cf-h1" style={{ margin: '4px 0 0' }}>Gastos consolidados</h2>
        </div>
        <Button variant="outline" icon={<Plus size={14} />}>Lançar manualmente</Button>
      </div>

      <div className="cf-totals">
        <div>
          <span className="cf-money" style={{ fontSize: 22, fontWeight: 600 }}>{fmtBRL(totalSpent)}</span>
          <span className="cf-caption" style={{ marginLeft: 8 }}>em {CONSOLIDATED.filter(t=>t.amount<0).length} gastos</span>
        </div>
        <div>
          <span className="cf-caption">Receita</span>{' '}
          <span className="cf-money" style={{ color: 'var(--success)', fontSize: 14, fontWeight: 600 }}>+ {fmtBRL(totalRecv)}</span>
        </div>
      </div>

      <div className="cf-filterbar">
        <Button variant="outline" size="sm" icon={<Filter size={14} />}>Filtros</Button>
        <Button variant="outline" size="sm" icon={<ChevronDown size={14} />}>Maio · 2026</Button>
        <Button variant="outline" size="sm" icon={<ChevronDown size={14} />}>Todas as contas</Button>
        <Button variant="outline" size="sm" icon={<ChevronDown size={14} />}>Todas as tags</Button>
        <Button variant="ghost" size="sm">Todos · Kaleb · Ana</Button>
      </div>

      <div className="cf-table-head">
        <span style={{ width: 8 }} />
        <span>Descrição</span>
        <span>Tags</span>
        <span style={{ textAlign: 'right' }}>Valor</span>
      </div>
      <div className="cf-inbox__list">
        {CONSOLIDATED.map(t => <ConsolidatedRow key={t.id} tx={t} />)}
      </div>
    </div>
  );
}

window.CFGastos = { GastosView };
