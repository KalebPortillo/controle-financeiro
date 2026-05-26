// ============================================================
// Controle Financeiro — UI primitives.
// Cosmetic recreations of shadcn/ui primitives the spec calls
// out: Button, Badge, Input, Sheet, Skeleton, TagChip, Money.
// ============================================================

// --------- Button ----------
function Button({
  variant = 'default', size = 'default', icon, hotkey,
  children, onClick, disabled, style, className = '', ...rest
}) {
  return (
    <button
      className={`cf-btn cf-btn--${variant} cf-btn--${size} ${className}`}
      onClick={onClick}
      disabled={disabled}
      style={style}
      {...rest}
    >
      {icon ? <span className="cf-btn__icon">{icon}</span> : null}
      {children ? <span>{children}</span> : null}
      {hotkey ? <kbd className="cf-kbd">{hotkey}</kbd> : null}
    </button>
  );
}

// --------- Badge ----------
function Badge({ variant = 'default', children, style }) {
  return <span className={`cf-badge cf-badge--${variant}`} style={style}>{children}</span>;
}

// --------- Tag chip ----------
function TagChip({ tag, onRemove }) {
  return (
    <span className="cf-tag">
      <span className="cf-tag__dot" style={{ background: tag.color }} />
      {tag.name}
      {onRemove ? <button className="cf-tag__x" onClick={onRemove} aria-label="remover">×</button> : null}
    </span>
  );
}

// --------- Money ----------
function Money({ value, signed = false, mono = true, size = 14, style }) {
  const { fmtBRL } = window.CFData;
  const positive = value > 0;
  const negative = value < 0;
  // Negatives stay neutral (foreground) since the app is mostly expenses.
  // Only positives (receitas) get the bright green to stand out.
  const sign = signed ? (positive ? '+ ' : negative ? '− ' : '') : '';
  const color = signed && positive ? 'var(--success-vivid)' : 'inherit';
  return (
    <span
      className={mono ? 'cf-money' : ''}
      style={{ fontSize: size, color, whiteSpace: 'nowrap', ...style }}
    >
      {sign}{fmtBRL(value)}
    </span>
  );
}

// --------- Confidence dot ----------
function ConfidenceDot({ level }) {
  const c =
    level === 'high'   ? 'var(--confidence-high)' :
    level === 'medium' ? 'var(--confidence-medium)' :
                         'var(--confidence-low)';
  return <span className="cf-confidence" style={{ background: c }} aria-label={`confiança ${level}`} />;
}

// --------- Input ----------
function Input({ leadingIcon, style, ...rest }) {
  if (leadingIcon) {
    return (
      <div className="cf-input-wrap">
        <span className="cf-input-wrap__icon">{leadingIcon}</span>
        <input className="cf-input cf-input--has-leading" style={style} {...rest} />
      </div>
    );
  }
  return <input className="cf-input" style={style} {...rest} />;
}

// --------- Sheet (right-side drawer for desktop detail) ----------
function Sheet({ open, onClose, children, width = 440 }) {
  React.useEffect(() => {
    const onKey = (e) => { if (e.key === 'Escape') onClose?.(); };
    if (open) window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, [open, onClose]);

  return (
    <>
      <div
        className={`cf-sheet-backdrop ${open ? 'is-open' : ''}`}
        onClick={onClose}
      />
      <aside
        className={`cf-sheet ${open ? 'is-open' : ''}`}
        style={{
          width,
          transform: open ? 'translate3d(0, 0, 0)' : `translate3d(${width}px, 0, 0)`,
        }}
        role="dialog"
        aria-hidden={!open}
      >
        {children}
      </aside>
    </>
  );
}

// --------- Skeleton ----------
function Skeleton({ w = '100%', h = 14, style }) {
  return <div className="cf-skeleton" style={{ width: w, height: h, ...style }} />;
}

// --------- Card ----------
function Card({ children, padding = 16, style, className = '' }) {
  return (
    <div
      className={`cf-card ${className}`}
      style={{ padding, ...style }}
    >
      {children}
    </div>
  );
}

// --------- Section header ----------
function SectionHeader({ title, subtitle, actions }) {
  return (
    <div className="cf-section-header">
      <div>
        <h2 className="cf-h1" style={{ margin: 0 }}>{title}</h2>
        {subtitle ? <div className="cf-caption" style={{ marginTop: 4 }}>{subtitle}</div> : null}
      </div>
      {actions ? <div className="cf-section-header__actions">{actions}</div> : null}
    </div>
  );
}

// --------- Progress bar (budget) ----------
function ProgressBar({ value, max }) {
  const pct = Math.min(100, (value / max) * 100);
  return (
    <div className="cf-progress">
      <div className="cf-progress__fill" style={{ width: `${pct}%` }} />
    </div>
  );
}

window.CFUI = {
  Button, Badge, TagChip, Money, ConfidenceDot, Input, Sheet,
  Skeleton, Card, SectionHeader, ProgressBar,
};
