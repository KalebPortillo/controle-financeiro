// ============================================================
// Detail sheet — opens when an inbox row is clicked.
// Right-side drawer on desktop, full-bleed sheet on mobile.
// ============================================================

const { X, Check, Split, Link2, Trash2, Calendar, TagIcon, FolderIcon,
        CreditCard, MoreHorizontal } = window.CFIcons;
const { Sheet, Button, Badge, TagChip, Money, ConfidenceDot } = window.CFUI;
const { tagsById, categoriesById, accountsById, fmtDate, fmtBRL } = window.CFData;

function Field({ label, icon, children }) {
  return (
    <div className="cf-field">
      <div className="cf-field__label">
        {icon}
        <span>{label}</span>
      </div>
      <div className="cf-field__value">{children}</div>
    </div>
  );
}

function DetailSheet({ tx, open, onClose, onAccept, onReject }) {
  const lastTx = React.useRef(null);
  if (tx) lastTx.current = tx;
  const cur = tx ?? lastTx.current;

  if (!cur) return <Sheet open={false} onClose={onClose}><div /></Sheet>;

  const account = accountsById[cur.accountId];
  const tags = cur.suggestedTagIds.map(id => tagsById[id]).filter(Boolean);
  const category = cur.suggestedCategoryId ? categoriesById[cur.suggestedCategoryId] : null;

  return (
    <Sheet open={open} onClose={onClose} width={460}>
      <div className="cf-sheet__inner">
        {/* Header */}
        <div className="cf-sheet__header">
          <div className="cf-sheet__title-row">
            <ConfidenceDot level={cur.confidence} />
            <div className="cf-sheet__title-block">
              <div className="cf-sheet__title">
                {cur.suggestedTitle ?? cur.rawDescription}
              </div>
              <div className="cf-caption">
                Descrição bruta:{' '}
                <span style={{ fontFamily: 'var(--font-mono)' }}>{cur.rawDescription}</span>
              </div>
            </div>
            <button className="cf-iconbtn" onClick={onClose} aria-label="Fechar">
              <X size={16} />
            </button>
          </div>

          <div className="cf-sheet__amount">
            <Money value={cur.amount} signed size={32} />
          </div>

          {cur.isRefundCandidate ? (
            <div className="cf-callout">
              <Link2 size={16} />
              <div>
                <div style={{ fontWeight: 500 }}>Esta transação é um estorno?</div>
                <div className="cf-caption">
                  Parece relacionada a <strong>{cur.refundCandidateTitle}</strong> ({fmtBRL(cur.refundCandidateAmount)}, 22/05).
                </div>
              </div>
              <Button variant="outline" size="sm">É este</Button>
            </div>
          ) : null}
        </div>

        {/* Body */}
        <div className="cf-sheet__body">
          <Field label="Título" icon={null}>
            <input
              className="cf-input"
              defaultValue={cur.suggestedTitle ?? cur.rawDescription}
              key={cur.id + '-title'}
              style={{ width: '100%' }}
            />
          </Field>

          <div className="cf-field-row">
            <Field label="Valor" icon={null}>
              <input
                className="cf-input cf-money"
                defaultValue={fmtBRL(cur.amount)}
                key={cur.id + '-amt'}
                style={{ width: '100%' }}
              />
            </Field>
            <Field label="Data" icon={<Calendar size={12} />}>
              <input
                className="cf-input"
                defaultValue={fmtDate(cur.date)}
                key={cur.id + '-date'}
                style={{ width: '100%' }}
              />
            </Field>
          </div>

          <Field label="Conta" icon={<CreditCard size={12} />}>
            <div className="cf-input cf-input--readonly">
              {account?.name} <span className="cf-caption">· {cur.person}</span>
            </div>
          </Field>

          <Field label="Tags" icon={<TagIcon size={12} />}>
            <div className="cf-chip-input">
              {tags.map(t => <TagChip key={t.id} tag={t} onRemove={() => {}} />)}
              <input
                className="cf-chip-input__input"
                placeholder="Adicionar tag…"
              />
            </div>
          </Field>

          <Field label="Categoria" icon={<FolderIcon size={12} />}>
            <div className="cf-select">
              <span>{category?.name ?? 'Sem categoria'}</span>
            </div>
            {category ? (
              <div className="cf-caption" style={{ marginTop: 6 }}>
                Agrega tags: {category.tagIds.map(t => tagsById[t]?.name).join(', ')}
              </div>
            ) : null}
          </Field>

          <div className="cf-sheet__moreactions">
            <button className="cf-link"><Link2 size={12} /> Vincular a gasto existente</button>
            <button className="cf-link">Marcar como transferência interna</button>
            <button className="cf-link cf-link--destructive">
              <Trash2 size={12} /> Excluir definitivamente
            </button>
          </div>
        </div>

        {/* Footer */}
        <div className="cf-sheet__footer">
          <Button variant="ghost" hotkey="R" icon={<X size={14} />} onClick={() => onReject(cur)}>
            Rejeitar
          </Button>
          <Button variant="ghost" hotkey="S" icon={<Split size={14} />}>
            Split
          </Button>
          <Button variant="primary" hotkey="A" icon={<Check size={14} />} onClick={() => onAccept(cur)}>
            Aceitar
          </Button>
        </div>
      </div>
    </Sheet>
  );
}

window.CFDetail = { DetailSheet };
