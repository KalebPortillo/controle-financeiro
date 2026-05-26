// ============================================================
// App shell: Sidebar (desktop left), TopBar, BottomNav (mobile)
// ============================================================

const { Wallet, Inbox, PieChartIcon, BarChart3, MoreHorizontal,
        Search, Sun, Moon, Bell, Plus } = window.CFIcons;
const { Badge, Button, Input } = window.CFUI;

const NAV_ITEMS = [
  { id: 'inbox',      label: 'Inbox',      Icon: Inbox,         badge: 8 },
  { id: 'gastos',     label: 'Gastos',     Icon: Wallet,        badge: null },
  { id: 'orcamentos', label: 'Orçamentos', Icon: PieChartIcon,  badge: null },
  { id: 'relatorios', label: 'Relatórios', Icon: BarChart3,     badge: null },
  { id: 'mais',       label: 'Mais',       Icon: MoreHorizontal, badge: null },
];

function Sidebar({ active, onNavigate }) {
  return (
    <aside className="cf-sidebar">
      <div className="cf-sidebar__brand">
        <Wallet size={20} />
        <span>Controle Financeiro</span>
      </div>
      <nav className="cf-sidebar__nav">
        {NAV_ITEMS.map(({ id, label, Icon, badge }) => (
          <button
            key={id}
            className={`cf-sidebar__item ${active === id ? 'is-active' : ''}`}
            onClick={() => onNavigate(id)}
          >
            <Icon size={16} />
            <span>{label}</span>
            {badge ? <span className="cf-sidebar__badge"><Badge variant="default">{badge}</Badge></span> : null}
          </button>
        ))}
      </nav>

      <div className="cf-sidebar__footer">
        <div className="cf-workspace">
          <div className="cf-avatar">K</div>
          <div className="cf-workspace__info">
            <div className="cf-workspace__name">Casa do Kaleb</div>
            <div className="cf-workspace__sub">kaleb@email.com</div>
          </div>
        </div>
      </div>
    </aside>
  );
}

function TopBar({ active, theme, onToggleTheme, search, onSearch }) {
  const title = NAV_ITEMS.find(n => n.id === active)?.label ?? '';
  return (
    <header className="cf-topbar">
      <div className="cf-topbar__title">
        <h1 className="cf-h1" style={{ margin: 0, fontSize: 18 }}>{title}</h1>
      </div>
      <div className="cf-topbar__search">
        <Input
          leadingIcon={<Search size={14} />}
          placeholder="Buscar gastos, tags, contas…"
          value={search}
          onChange={(e) => onSearch?.(e.target.value)}
        />
        <kbd className="cf-kbd cf-kbd--inline">/</kbd>
      </div>
      <div className="cf-topbar__actions">
        <button className="cf-iconbtn" aria-label="Tema" onClick={onToggleTheme}>
          {theme === 'dark' ? <Sun size={16} /> : <Moon size={16} />}
        </button>
        <button className="cf-iconbtn" aria-label="Notificações">
          <Bell size={16} />
          <span className="cf-iconbtn__dot" />
        </button>
      </div>
    </header>
  );
}

function BottomNav({ active, onNavigate }) {
  return (
    <nav className="cf-bottomnav" role="navigation">
      {NAV_ITEMS.map(({ id, label, Icon, badge }) => (
        <button
          key={id}
          className={`cf-bottomnav__item ${active === id ? 'is-active' : ''}`}
          onClick={() => onNavigate(id)}
        >
          <span className="cf-bottomnav__icon">
            <Icon size={20} />
            {badge ? <span className="cf-bottomnav__badge">{badge}</span> : null}
          </span>
          <span className="cf-bottomnav__label">{label}</span>
        </button>
      ))}
    </nav>
  );
}

window.CFShell = { Sidebar, TopBar, BottomNav, NAV_ITEMS };
