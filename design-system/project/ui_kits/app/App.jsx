// ============================================================
// App.jsx — root component. Manages active view, theme,
// inbox selection, and the open detail sheet.
// ============================================================

const { useState, useEffect, useMemo } = React;

function App() {
  const [active, setActive] = useState('inbox');
  const [theme, setTheme] = useState(
    typeof window !== 'undefined' &&
    window.matchMedia?.('(prefers-color-scheme: dark)').matches ? 'dark' : 'light'
  );
  const [search, setSearch] = useState('');

  const [inbox, setInbox] = useState(window.CFData.INBOX);
  const [selected, setSelected] = useState(new Set());
  const [openTx, setOpenTx] = useState(null);
  const [toast, setToast] = useState(null);

  useEffect(() => {
    document.documentElement.setAttribute('data-theme', theme);
  }, [theme]);

  // Keyboard shortcuts — A/R when an item is open
  useEffect(() => {
    const handler = (e) => {
      if (e.target.tagName === 'INPUT' || e.target.tagName === 'TEXTAREA') return;
      if (e.key === '/' && !openTx) {
        e.preventDefault();
        document.querySelector('.cf-input')?.focus();
      }
      if (openTx) {
        if (e.key === 'a' || e.key === 'A') { handleAccept(openTx); }
        if (e.key === 'r' || e.key === 'R') { handleReject(openTx); }
      }
    };
    window.addEventListener('keydown', handler);
    return () => window.removeEventListener('keydown', handler);
  }, [openTx]);

  const toggleSelect = (id) => {
    setSelected((prev) => {
      const next = new Set(prev);
      next.has(id) ? next.delete(id) : next.add(id);
      return next;
    });
  };
  const selectAll = () => setSelected(new Set(inbox.map(t => t.id)));
  const clearSelection = () => setSelected(new Set());

  const showToast = (msg) => {
    setToast(msg);
    setTimeout(() => setToast(null), 2200);
  };

  const handleAccept = (tx) => {
    setInbox((prev) => prev.filter(t => t.id !== tx.id));
    setSelected((prev) => {
      const next = new Set(prev); next.delete(tx.id); return next;
    });
    setOpenTx(null);
    showToast('Gasto consolidado');
  };
  const handleReject = (tx) => {
    setInbox((prev) => prev.filter(t => t.id !== tx.id));
    setSelected((prev) => {
      const next = new Set(prev); next.delete(tx.id); return next;
    });
    setOpenTx(null);
    showToast('Gasto rejeitado');
  };
  const handleBulkAccept = () => {
    const n = selected.size;
    setInbox((prev) => prev.filter(t => !selected.has(t.id)));
    setSelected(new Set());
    showToast(`${n} gasto${n > 1 ? 's' : ''} consolidado${n > 1 ? 's' : ''}`);
  };
  const handleBulkReject = () => {
    const n = selected.size;
    setInbox((prev) => prev.filter(t => !selected.has(t.id)));
    setSelected(new Set());
    showToast(`${n} gasto${n > 1 ? 's' : ''} rejeitado${n > 1 ? 's' : ''}`);
  };

  const filteredInbox = useMemo(() => {
    if (!search) return inbox;
    const q = search.toLowerCase();
    return inbox.filter((t) =>
      (t.suggestedTitle ?? '').toLowerCase().includes(q) ||
      t.rawDescription.toLowerCase().includes(q)
    );
  }, [inbox, search]);

  const { Sidebar, TopBar, BottomNav } = window.CFShell;
  const { InboxView } = window.CFInbox;
  const { DetailSheet } = window.CFDetail;
  const { BudgetsView } = window.CFBudgets;
  const { ReportsView } = window.CFReports;
  const { GastosView } = window.CFGastos;
  const { SettingsView } = window.CFSettings;
  const { Check } = window.CFIcons;

  return (
    <div className="cf-app" data-active={active}>
      <Sidebar active={active} onNavigate={(id) => { setActive(id); setOpenTx(null); }} />
      <div className="cf-main">
        <TopBar
          active={active}
          theme={theme}
          onToggleTheme={() => setTheme(t => t === 'dark' ? 'light' : 'dark')}
          search={search}
          onSearch={setSearch}
        />
        <div className="cf-content">
          {active === 'inbox' && (
            <InboxView
              inbox={filteredInbox}
              selected={selected}
              onToggleSelect={toggleSelect}
              onSelectAll={selectAll}
              onClearSelection={clearSelection}
              onOpen={(tx) => setOpenTx(tx)}
              activeId={openTx?.id}
              onAccept={handleBulkAccept}
              onReject={handleBulkReject}
            />
          )}
          {active === 'gastos'     && <GastosView />}
          {active === 'orcamentos' && <BudgetsView />}
          {active === 'relatorios' && <ReportsView />}
          {active === 'mais'       && <SettingsView />}
        </div>
      </div>

      <DetailSheet
        tx={openTx}
        open={!!openTx}
        onClose={() => setOpenTx(null)}
        onAccept={handleAccept}
        onReject={handleReject}
      />

      <BottomNav active={active} onNavigate={(id) => { setActive(id); setOpenTx(null); }} />

      {toast ? (
        <div className="cf-toast" role="status">
          <span style={{ color: 'var(--success)', display: 'inline-flex' }}>
            <Check size={14} />
          </span>
          <span>{toast}</span>
        </div>
      ) : null}
    </div>
  );
}

const root = ReactDOM.createRoot(document.getElementById('root'));
root.render(<App />);
