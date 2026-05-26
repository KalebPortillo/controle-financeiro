// ============================================================
// Reports view — Overview cards + donut (categories) + bar (top tags)
// + line (12-month evolution). Mimics Tremor's defaults.
// ============================================================

const { Card, Money } = window.CFUI;
const { PERIOD_SUMMARY, CATEGORY_BREAKDOWN, fmtBRL } = window.CFData;

// ---- Top KPI cards ----
function KpiCard({ label, value, delta, deltaPositive }) {
  return (
    <Card padding={20}>
      <div className="cf-caption">{label}</div>
      <div style={{ marginTop: 6 }}>
        <Money value={value} mono size={24} />
      </div>
      {delta != null ? (
        <div className="cf-caption" style={{ marginTop: 4, color: deltaPositive ? 'var(--success)' : 'var(--destructive)' }}>
          {deltaPositive ? '+' : ''}{(delta * 100).toFixed(0)}% vs mês anterior
        </div>
      ) : null}
    </Card>
  );
}

// ---- Donut chart ----
function Donut({ data, size = 200 }) {
  const total = data.reduce((s, d) => s + d.value, 0);
  const cx = size / 2, cy = size / 2;
  const r = size / 2 - 6;
  const innerR = r * 0.66;
  let acc = 0;

  const arc = (start, end) => {
    const a0 = (start / total) * 2 * Math.PI - Math.PI / 2;
    const a1 = (end / total) * 2 * Math.PI - Math.PI / 2;
    const large = end - start > total / 2 ? 1 : 0;
    const x0 = cx + r * Math.cos(a0), y0 = cy + r * Math.sin(a0);
    const x1 = cx + r * Math.cos(a1), y1 = cy + r * Math.sin(a1);
    const xi0 = cx + innerR * Math.cos(a0), yi0 = cy + innerR * Math.sin(a0);
    const xi1 = cx + innerR * Math.cos(a1), yi1 = cy + innerR * Math.sin(a1);
    return `M ${x0} ${y0} A ${r} ${r} 0 ${large} 1 ${x1} ${y1} L ${xi1} ${yi1} A ${innerR} ${innerR} 0 ${large} 0 ${xi0} ${yi0} Z`;
  };

  // Format the total compactly so it doesn't overflow the inner hole.
  const compact = (n) => n >= 1000
    ? `R$ ${(n / 1000).toFixed(1).replace('.', ',')}k`
    : `R$ ${n.toFixed(0)}`;

  return (
    <div className="cf-donut">
      <svg width={size} height={size} viewBox={`0 0 ${size} ${size}`}>
        {data.map((d, i) => {
          const path = arc(acc, acc + d.value);
          acc += d.value;
          return <path key={d.id} d={path} fill={d.color} />;
        })}
        <text x={cx} y={cy - 6} textAnchor="middle" dominantBaseline="middle"
          style={{ font: '500 10px var(--font-sans)', fill: 'var(--muted-foreground)', textTransform: 'uppercase', letterSpacing: '0.06em' }}>
          total mês
        </text>
        <text x={cx} y={cy + 12} textAnchor="middle" dominantBaseline="middle"
          style={{ font: '500 18px var(--font-display)', fill: 'var(--foreground)', letterSpacing: '-0.02em' }}>
          {compact(total)}
        </text>
      </svg>
      <ul className="cf-donut__legend">
        {data.map(d => (
          <li key={d.id}>
            <span className="cf-donut__sw" style={{ background: d.color }} />
            <span>{d.name}</span>
            <span className="cf-donut__val">{fmtBRL(d.value)}</span>
          </li>
        ))}
      </ul>
    </div>
  );
}

// ---- Horizontal bar list (top tags) ----
const TAG_TOP = [
  { id: 't1', name: 'Mercado',     value: 482.30 },
  { id: 't2', name: 'Casa',        value: 740.00 },
  { id: 't3', name: 'Comida fora', value: 488.50 },
  { id: 't4', name: 'Transporte',  value: 412.10 },
  { id: 't5', name: 'Padaria',     value: 128.40 },
  { id: 't6', name: 'Assinatura',  value: 116.80 },
];

function HBar() {
  const max = Math.max(...TAG_TOP.map(t => t.value));
  return (
    <ul className="cf-hbar">
      {TAG_TOP.map(t => (
        <li key={t.id}>
          <div className="cf-hbar__label">{t.name}</div>
          <div className="cf-hbar__track">
            <div className="cf-hbar__fill" style={{ width: `${(t.value / max) * 100}%` }} />
          </div>
          <div className="cf-hbar__val cf-money">{fmtBRL(t.value)}</div>
        </li>
      ))}
    </ul>
  );
}

// ---- Line chart (12 months) ----
function LineChart() {
  const values = [3120, 3450, 2980, 3340, 3990, 4120, 3800, 3650, 4220, 3980, 4560, 4320];
  const labels = ['Jun','Jul','Ago','Set','Out','Nov','Dez','Jan','Fev','Mar','Abr','Mai'];
  const w = 560, h = 160, pad = 28;
  const max = Math.max(...values) * 1.1;
  const points = values.map((v, i) => {
    const x = pad + (i / (values.length - 1)) * (w - pad * 2);
    const y = h - pad - (v / max) * (h - pad * 2);
    return [x, y];
  });
  const path = points.map((p, i) => (i === 0 ? `M ${p[0]} ${p[1]}` : `L ${p[0]} ${p[1]}`)).join(' ');
  const area = path + ` L ${points[points.length-1][0]} ${h - pad} L ${points[0][0]} ${h - pad} Z`;

  return (
    <svg viewBox={`0 0 ${w} ${h}`} width="100%" style={{ display: 'block' }}>
      {/* grid */}
      {[0.25, 0.5, 0.75].map(t => (
        <line key={t} x1={pad} x2={w - pad} y1={pad + t * (h - pad * 2)} y2={pad + t * (h - pad * 2)}
              stroke="var(--border)" strokeDasharray="2 4" />
      ))}
      <path d={area} fill="var(--accent)" opacity="0.08" />
      <path d={path} fill="none" stroke="var(--accent)" strokeWidth="1.75" />
      {points.map((p, i) => (
        <circle key={i} cx={p[0]} cy={p[1]} r="2.5" fill="var(--background)" stroke="var(--accent)" strokeWidth="1.5" />
      ))}
      {labels.map((l, i) => (
        <text key={l} x={pad + (i / (labels.length - 1)) * (w - pad * 2)} y={h - 8}
              textAnchor="middle"
              style={{ font: '500 10px var(--font-sans)', fill: 'var(--muted-foreground)' }}>
          {l}
        </text>
      ))}
    </svg>
  );
}

function ReportsView() {
  const p = PERIOD_SUMMARY;
  const saldo = p.totalReceived - p.totalSpent;
  return (
    <div className="cf-reports">
      <div className="cf-page-head">
        <div>
          <div className="cf-caption">{p.label}</div>
          <h2 className="cf-h1" style={{ margin: '4px 0 0' }}>Relatórios</h2>
        </div>
      </div>

      <div className="cf-kpis">
        <KpiCard label="Total gasto"    value={-p.totalSpent}    delta={p.vsLastMonth} deltaPositive={false} />
        <KpiCard label="Total recebido" value={p.totalReceived} />
        <KpiCard label="Saldo do mês"   value={saldo} />
        <KpiCard label="Gastos no mês"  value={p.spendCount} />
      </div>

      <div className="cf-reports__grid">
        <div className="cf-card cf-reports__panel">
          <div className="cf-panel-head">
            <div className="cf-h2" style={{ fontSize: 15 }}>Gastos por categoria</div>
            <div className="cf-caption">5 categorias · maio</div>
          </div>
          <Donut data={CATEGORY_BREAKDOWN} />
          <div className="cf-callout cf-callout--info" style={{ marginTop: 16 }}>
            <span style={{ color: 'var(--muted-foreground)' }}>ⓘ</span>
            <div className="cf-caption" style={{ flex: 1 }}>
              Alguns gastos aparecem em mais de uma categoria; a soma das categorias pode ser maior que o total real.
            </div>
          </div>
        </div>

        <div className="cf-card cf-reports__panel">
          <div className="cf-panel-head">
            <div className="cf-h2" style={{ fontSize: 15 }}>Top tags do período</div>
            <div className="cf-caption">6 tags com maior gasto</div>
          </div>
          <HBar />
        </div>
      </div>

      <div className="cf-card cf-reports__panel" style={{ marginTop: 16 }}>
        <div className="cf-panel-head">
          <div className="cf-h2" style={{ fontSize: 15 }}>Evolução mensal · últimos 12 meses</div>
          <div className="cf-caption">total gasto</div>
        </div>
        <LineChart />
      </div>
    </div>
  );
}

window.CFReports = { ReportsView };
