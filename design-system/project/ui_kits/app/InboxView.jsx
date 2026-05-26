// ============================================================
// Inbox — the home screen. Pending imported transactions.
// Desktop = dense table with checkboxes + hotkeys.
// ============================================================

const { Check, X, Split, Link2, Trash2, Filter, CreditCard, Wallet, ChevronDown }
  = window.CFIcons;
const { Button, Badge, TagChip, Money, ConfidenceDot } = window.CFUI;
const { INBOX, tagsById, accountsById, fmtBRL, fmtDate } = window.CFData;

function InboxRow({ tx, selected, onToggleSelect, onOpen, active }) {
  const tags = tx.suggestedTagIds.map(id => tagsById[id]).filter(Boolean);
  const account = accountsById[tx.accountId];
  return (
    <div
      className={`cf-row ${selected ? 'is-selected' : ''} ${active ? 'is-active' : ''}`}
      onClick={() => onOpen(tx)}
    >
      <label className="cf-row__check" onClick={(e) => e.stopPropagation()}>
        <input
          type="checkbox"
          checked={selected}
          onChange={() => onToggleSelect(tx.id)}
          aria-label="Selecionar"
        />
      </label>

      <ConfidenceDot level={tx.confidence} />

      <div className="cf-row__main">
        <div className="cf-row__title">
          {tx.suggestedTitle ? (
            <span>{tx.suggestedTitle}</span>
          ) : (
            <span style={{ fontFamily: 'var(--font-mono)', color: 'var(--muted-foreground)' }}>
              {tx.rawDescription}
            </span>
          )}
          {tx.isRecurring ? <Badge variant="outline">recorrente</Badge> : null}
          {tx.isRefundCandidate ? <Badge variant="secondary">possível estorno</Badge> : null}
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
        {tags.slice(0, 2).map(t => <TagChip key={t.id} tag={t} />)}
        {tags.length > 2 ? <span className="cf-caption">+{tags.length - 2}</span> : null}
      </div>

      <div className="cf-row__amount">
        <Money value={tx.amount} signed size={14} />
      </div>
    </div>
  );
}

function InboxView({ inbox, selected, onToggleSelect, onSelectAll, onClearSelection,
                     onOpen, activeId, onAccept, onReject }) {
  const allSelected = selected.size > 0 && selected.size === inbox.length;
  const someSelected = selected.size > 0;

  return (
    <div className="cf-inbox">
      <div className="cf-inbox__toolbar">
        <div className="cf-inbox__totals">
          <strong className="cf-h2" style={{ fontSize: 16, margin: 0 }}>
            {inbox.length} pendentes
          </strong>
          <span className="cf-caption">esperando revisão</span>
        </div>
        <div className="cf-inbox__filters">
          <Button variant="outline" size="sm" icon={<Filter size={14} />}>
            Filtros
          </Button>
          <Button variant="outline" size="sm" icon={<ChevronDown size={14} />}>
            Maio · 2026
          </Button>
        </div>
      </div>

      <div className="cf-table-head">
        <label className="cf-table-head__check">
          <input
            type="checkbox"
            checked={allSelected}
            onChange={(e) => e.target.checked ? onSelectAll() : onClearSelection()}
            aria-label="Selecionar todos"
          />
        </label>
        <span></span>
        <span>Descrição</span>
        <span>Tags</span>
        <span style={{ textAlign: 'right' }}>Valor</span>
      </div>

      <div className="cf-inbox__list">
        {inbox.map(tx => (
          <InboxRow
            key={tx.id}
            tx={tx}
            selected={selected.has(tx.id)}
            onToggleSelect={onToggleSelect}
            onOpen={onOpen}
            active={activeId === tx.id}
          />
        ))}
      </div>

      {someSelected ? (
        <div className="cf-action-bar">
          <div className="cf-action-bar__count">
            {selected.size} selecionado{selected.size > 1 ? 's' : ''}
            <button
              className="cf-action-bar__clear"
              onClick={onClearSelection}
            >
              limpar
            </button>
          </div>
          <div className="cf-action-bar__actions">
            <Button variant="ghost" icon={<X size={14} />} onClick={onReject}>
              Rejeitar
            </Button>
            <Button variant="primary" icon={<Check size={14} />} hotkey="A" onClick={onAccept}>
              Aceitar selecionados ({selected.size})
            </Button>
          </div>
        </div>
      ) : null}
    </div>
  );
}

window.CFInbox = { InboxView, InboxRow };
