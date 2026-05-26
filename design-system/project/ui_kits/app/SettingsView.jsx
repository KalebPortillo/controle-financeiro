// ============================================================
// "Mais" — Settings landing. Surfaces workspace + sub-sections.
// ============================================================

const { ChevronRight, Wallet, CreditCard, TagIcon, FolderIcon, Plus,
        Sun, Bell, MoreHorizontal } = window.CFIcons;
const { Card, Badge, Button } = window.CFUI;
const { WORKSPACE, ACCOUNTS, TAGS, CATEGORIES } = window.CFData;

function SettingsRow({ icon, title, sub, badge }) {
  return (
    <button className="cf-settings__row">
      <span className="cf-settings__icon">{icon}</span>
      <span className="cf-settings__text">
        <span className="cf-settings__title">{title}</span>
        {sub ? <span className="cf-caption">{sub}</span> : null}
      </span>
      {badge ? <Badge variant="secondary">{badge}</Badge> : null}
      <ChevronRight size={14} style={{ color: 'var(--muted-foreground)' }} />
    </button>
  );
}

function SettingsView() {
  return (
    <div className="cf-settings">
      <div className="cf-page-head">
        <div>
          <div className="cf-caption">Workspace + ajustes</div>
          <h2 className="cf-h1" style={{ margin: '4px 0 0' }}>Mais</h2>
        </div>
      </div>

      <Card padding={20}>
        <div className="cf-h2" style={{ fontSize: 14, marginBottom: 12 }}>Workspace</div>
        <div className="cf-workspace cf-workspace--lg">
          <div className="cf-avatar cf-avatar--lg">K</div>
          <div className="cf-workspace__info">
            <div className="cf-workspace__name">{WORKSPACE.name}</div>
            <div className="cf-workspace__sub">{WORKSPACE.members.length} membros</div>
          </div>
          <Button variant="outline" size="sm" icon={<Plus size={14} />}>Convidar</Button>
        </div>
        <ul className="cf-members">
          {WORKSPACE.members.map(m => (
            <li key={m.id}>
              <div className="cf-avatar">{m.initials}</div>
              <div className="cf-members__info">
                <div className="cf-members__name">{m.name}</div>
                <div className="cf-caption">{m.email}</div>
              </div>
              <span className="cf-caption">editor</span>
            </li>
          ))}
        </ul>
      </Card>

      <Card padding={0} style={{ marginTop: 16 }}>
        <SettingsRow icon={<CreditCard size={16} />} title="Contas e cartões" sub="Pluggy + manuais" badge={`${ACCOUNTS.length}`} />
        <SettingsRow icon={<TagIcon size={16} />}   title="Tags" sub="planas, múltiplas por gasto" badge={`${TAGS.length}`} />
        <SettingsRow icon={<FolderIcon size={16} />} title="Categorias" sub="agrega tags para relatório e orçamento" badge={`${CATEGORIES.length}`} />
        <SettingsRow icon={<MoreHorizontal size={16} />} title="Regras manuais" sub="ex.: IFood* → tag Comida fora" />
        <SettingsRow icon={<Wallet size={16} />} title="Recorrentes" sub="detectadas + cadastradas manualmente" />
        <SettingsRow icon={<Plus size={16} />} title="Importações CSV / OFX" sub="upload de arquivos exportados" />
        <SettingsRow icon={<Bell size={16} />} title="Notificações" sub="in-app · push e email em breve" />
        <SettingsRow icon={<Sun size={16} />}  title="Aparência" sub="tema claro · escuro · sistema" />
      </Card>
    </div>
  );
}

window.CFSettings = { SettingsView };
