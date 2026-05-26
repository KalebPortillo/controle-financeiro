// ============================================================
// Controle Financeiro — mock data for the click-thru prototype.
// Reflects PRD entities: inbox transactions, consolidated spends,
// budgets, accounts, tags, categories, workspace members.
// ============================================================

const TAGS = [
  { id: 't_mercado', name: 'Mercado',     color: '#7C3AED' },
  { id: 't_padaria', name: 'Padaria',     color: '#16A34A' },
  { id: 't_comida_fora', name: 'Comida fora', color: '#F59E0B' },
  { id: 't_transporte', name: 'Transporte',  color: '#0EA5E9' },
  { id: 't_assinatura', name: 'Assinatura',  color: '#EC4899' },
  { id: 't_saude',   name: 'Saúde',       color: '#DC2626' },
  { id: 't_casa',    name: 'Casa',        color: '#8B5CF6' },
  { id: 't_lazer',   name: 'Lazer',       color: '#14B8A6' },
];

const CATEGORIES = [
  { id: 'c_alim', name: 'Alimentação', tagIds: ['t_mercado','t_padaria','t_comida_fora'] },
  { id: 'c_trans', name: 'Transporte', tagIds: ['t_transporte'] },
  { id: 'c_casa', name: 'Casa',        tagIds: ['t_casa'] },
  { id: 'c_assina', name: 'Assinaturas', tagIds: ['t_assinatura'] },
  { id: 'c_saude', name: 'Saúde',      tagIds: ['t_saude'] },
  { id: 'c_lazer', name: 'Lazer',      tagIds: ['t_lazer','t_comida_fora'] },
];

const ACCOUNTS = [
  { id: 'a_nu_cc',  name: 'Nubank · cartão',  kind: 'credit_card', owner: 'Kaleb' },
  { id: 'a_nu_cor', name: 'Nubank · conta',   kind: 'checking',    owner: 'Kaleb' },
  { id: 'a_nu_ana', name: 'Nubank · Ana',     kind: 'credit_card', owner: 'Ana'   },
];

// Inbox = imported transactions, not yet consolidated.
// confidence: 'high' | 'medium' | 'low' — drives the dot color.
const INBOX = [
  {
    id: 'i_1',
    rawDescription: 'PADARIA IPIRANGA SP',
    suggestedTitle: 'Almoço Padaria',
    amount: -28.50,
    date: '2026-05-22',
    accountId: 'a_nu_cc',
    suggestedTagIds: ['t_padaria','t_comida_fora'],
    suggestedCategoryId: 'c_alim',
    confidence: 'high',
    person: 'Kaleb',
  },
  {
    id: 'i_2',
    rawDescription: 'IFOOD*REST ANDORINHA',
    suggestedTitle: null,
    amount: -62.00,
    date: '2026-05-22',
    accountId: 'a_nu_cc',
    suggestedTagIds: [],
    suggestedCategoryId: null,
    confidence: 'low',
    person: 'Kaleb',
  },
  {
    id: 'i_3',
    rawDescription: 'UBER *TRIP',
    suggestedTitle: 'Uber casa',
    amount: -23.90,
    date: '2026-05-21',
    accountId: 'a_nu_cc',
    suggestedTagIds: ['t_transporte'],
    suggestedCategoryId: 'c_trans',
    confidence: 'high',
    person: 'Kaleb',
  },
  {
    id: 'i_4',
    rawDescription: 'PAGAMENTO PIX REC ANA M.',
    suggestedTitle: 'Almoço dividido com Ana',
    amount: 31.00,
    date: '2026-05-21',
    accountId: 'a_nu_cor',
    suggestedTagIds: ['t_comida_fora'],
    suggestedCategoryId: 'c_alim',
    confidence: 'medium',
    person: 'Kaleb',
    isRefundCandidate: true,
    refundCandidateTitle: 'Almoço Padaria',
    refundCandidateAmount: 62.00,
  },
  {
    id: 'i_5',
    rawDescription: 'NETFLIX.COM',
    suggestedTitle: 'Netflix',
    amount: -55.90,
    date: '2026-05-20',
    accountId: 'a_nu_cc',
    suggestedTagIds: ['t_assinatura','t_lazer'],
    suggestedCategoryId: 'c_assina',
    confidence: 'high',
    person: 'Kaleb',
    isRecurring: true,
  },
  {
    id: 'i_6',
    rawDescription: 'DROGARIA SP DISTRITO',
    suggestedTitle: 'Farmácia',
    amount: -84.30,
    date: '2026-05-20',
    accountId: 'a_nu_ana',
    suggestedTagIds: ['t_saude'],
    suggestedCategoryId: 'c_saude',
    confidence: 'medium',
    person: 'Ana',
  },
  {
    id: 'i_7',
    rawDescription: 'MERCADO SAO LUIZ',
    suggestedTitle: 'Mercado da semana',
    amount: -312.40,
    date: '2026-05-19',
    accountId: 'a_nu_cor',
    suggestedTagIds: ['t_mercado'],
    suggestedCategoryId: 'c_alim',
    confidence: 'high',
    person: 'Kaleb',
  },
  {
    id: 'i_8',
    rawDescription: 'PAGTO BOLETO COND',
    suggestedTitle: 'Condomínio',
    amount: -740.00,
    date: '2026-05-18',
    accountId: 'a_nu_cor',
    suggestedTagIds: ['t_casa'],
    suggestedCategoryId: 'c_casa',
    confidence: 'high',
    person: 'Ana',
    isRecurring: true,
  },
];

const BUDGETS = [
  { id: 'b_1', name: 'Mercado',     scope: 'tag', tagId: 't_mercado', cap: 800, spent: 423.00 },
  { id: 'b_2', name: 'Comida fora', scope: 'tag', tagId: 't_comida_fora', cap: 600, spent: 488.50 },
  { id: 'b_3', name: 'Transporte',  scope: 'category', categoryId: 'c_trans', cap: 500, spent: 620.10 },
  { id: 'b_4', name: 'Casa',        scope: 'category', categoryId: 'c_casa', cap: 1200, spent: 740.00 },
];

const PERIOD_SUMMARY = {
  label: 'Maio · 2026',
  totalSpent: 4320.00,
  totalReceived: 6500.00,
  spendCount: 87,
  vsLastMonth: -0.07, // -7%
};

const CATEGORY_BREAKDOWN = [
  { id: 'c_alim',  name: 'Alimentação', value: 1840.50, color: '#7C3AED' },
  { id: 'c_casa',  name: 'Casa',        value: 1120.00, color: '#0EA5E9' },
  { id: 'c_trans', name: 'Transporte',  value: 620.10,  color: '#F59E0B' },
  { id: 'c_assina',name: 'Assinaturas', value: 215.80,  color: '#EC4899' },
  { id: 'c_saude', name: 'Saúde',       value: 184.30,  color: '#DC2626' },
  { id: 'c_lazer', name: 'Lazer',       value: 339.30,  color: '#14B8A6' },
];

const WORKSPACE = {
  name: 'Casa do Kaleb',
  members: [
    { id: 'u_1', name: 'Kaleb',  email: 'kaleb@email.com',  initials: 'K' },
    { id: 'u_2', name: 'Ana M.', email: 'ana@email.com',    initials: 'A' },
  ],
};

// Helpers
const fmtBRL = (v) =>
  new Intl.NumberFormat('pt-BR', { style: 'currency', currency: 'BRL' })
    .format(Math.abs(v));

const fmtDate = (iso) => {
  const d = new Date(iso + 'T12:00:00');
  const days = ['Dom','Seg','Ter','Qua','Qui','Sex','Sáb'];
  const dd = String(d.getDate()).padStart(2,'0');
  const mm = String(d.getMonth()+1).padStart(2,'0');
  return `${days[d.getDay()]} ${dd}/${mm}`;
};

const tagsById = Object.fromEntries(TAGS.map(t => [t.id, t]));
const categoriesById = Object.fromEntries(CATEGORIES.map(c => [c.id, c]));
const accountsById = Object.fromEntries(ACCOUNTS.map(a => [a.id, a]));

window.CFData = {
  TAGS, CATEGORIES, ACCOUNTS, INBOX, BUDGETS, PERIOD_SUMMARY,
  CATEGORY_BREAKDOWN, WORKSPACE,
  tagsById, categoriesById, accountsById,
  fmtBRL, fmtDate,
};
