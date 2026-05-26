# Controle Financeiro — Design System

A design system for **Controle Financeiro**, a private, self-hosted, inbox-first personal-finance webapp built for a couple to share full visibility of their spending. The brand language is **Linear/Notion clean & minimal** — content first, chrome second, almost zero ornament.

This system is derived directly from the product's own specification documents (see "Sources" below), so every token, scale, component decision and copy convention here is canonical, not inferred.

---

## What the product is

> "Aplicação privada para gestão financeira de um casal (você + esposa), com login individual por usuário e visão compartilhada total dentro de um workspace comum. Objetivo central: ter uma visão consolidada e categorizada de todos os gastos por período, com busca automática das transações e o mínimo de fricção manual — mas sempre com supervisão humana antes de qualquer lançamento ser oficializado."

A few defining product principles that shape the design language:

1. **Inbox-first.** The home screen is an inbox of pending transactions that need the user's review *before* they count toward reports/budgets — like email.
2. **AI suggests, humans confirm.** Every imported transaction gets a suggested title and tags with a confidence indicator; nothing is auto-applied.
3. **Tags are flat, Categories aggregate.** A spend can carry many tags; categories are a separate entity that groups tags for reporting + budgeting.
4. **Mobile-first, desktop is differentiated.** Phone uses a bottom-nav + drawer (Sheet) detail. Desktop adds keyboard shortcuts (J/K/A/R/E/S/Cmd+K), denser tables, a left sidebar.
5. **Self-hosted on the user's Oracle VPS** — there are no marketing pages, no marketplace, no plans/upsell surface. The entire product is the app.

Five product surfaces matter visually:

| Surface | What lives here |
|---|---|
| **Inbox** | Pending imported transactions awaiting acceptance |
| **Gastos consolidados** | Accepted spends, with filters by period/account/tag/category/person |
| **Orçamentos** | Monthly budgets per tag, category or composite |
| **Relatórios** | Donut/bar/line charts (Tremor) over consolidated spends |
| **Mais (Settings)** | Workspace + members, accounts, tags, categories, rules, recurrents, imports |

---

## Sources

Everything in this system is lifted from the canonical product docs in the repo:

- **Repository:** [`KalebPortillo/controle-financeiro`](https://github.com/KalebPortillo/controle-financeiro)
- **Design spec:** [`docs/requisitos-design.md`](https://github.com/KalebPortillo/controle-financeiro/blob/main/docs/requisitos-design.md) — *the source of truth for every token and pattern in this folder*
- **Product spec (PRD v1.2):** [`docs/requisitos-produto.md`](https://github.com/KalebPortillo/controle-financeiro/blob/main/docs/requisitos-produto.md)
- **Technical spec:** [`docs/requisitos-tecnicos.md`](https://github.com/KalebPortillo/controle-financeiro/blob/main/docs/requisitos-tecnicos.md)
- **Data model:** [`docs/modelo-de-dados.md`](https://github.com/KalebPortillo/controle-financeiro/blob/main/docs/modelo-de-dados.md)
- **API contracts:** [`docs/contratos-api.md`](https://github.com/KalebPortillo/controle-financeiro/blob/main/docs/contratos-api.md)

If you're using this skill on a brand-new design, read `requisitos-design.md` end-to-end first. It is short, complete, and resolves every visual ambiguity (logo, accent, defaults, etc.) better than any inference.

> ⚠️ **No production frontend exists yet.** The repository currently contains only specs (`docs/*.md`) — no app code. Every component recreation in `ui_kits/` was built directly from the design spec, not lifted from existing JSX. If/when the real frontend lands in the repo, this design system should be re-grounded against it.

---

## CONTENT FUNDAMENTALS

Voice is **terse, second-person Brazilian Portuguese, lowercase by habit, friendly but unsentimental** — the way a calm spouse would write a shared spreadsheet's column headers. No marketing voice. No exclamation marks except where literal celebration matters (it doesn't, here).

### Language

- **PT-BR único no MVP.** All UI strings are Portuguese. Structure uses `i18next`/`react-intl` for future EN/ES, but ship strings as PT-BR keys.
- Currency: `Intl.NumberFormat('pt-BR', { style: 'currency', currency: 'BRL' })` → `R$ 1.234,56`
- Dates: short `dd/MM/yyyy`, long `D MMM yyyy`. Day-of-week prefix on inbox rows: `Sex, 22/05`.
- Numbers: thousand-separator `.`, decimal `,`.

### Tone

- **Direct, factual, no praise.** "Gasto consolidado." not "🎉 Awesome, you saved a transaction!"
- **Sober feedback.** The design doc is explicit: *"Sem confetes nem celebrações exageradas — vibe Linear é sóbria."*
- **You/your-implicit.** PT-BR drops pronouns naturally; "Aceitar selecionados (3)" not "Aceite seus 3 itens selecionados".
- **System speaks in third person about itself** in error contexts ("Falha de sincronização"), never "I" or "we".
- **No emoji in UI strings.** Information density comes from a confidence dot, a colored bar, a badge — never an emoji. Emoji are used **only** in this README's source docs as inline annotation; they do not appear in product.
- **No icons inside button labels** except in icon-only buttons. A button says `Aceitar`, not `✓ Aceitar`.

### Casing & punctuation

- **Sentence case everywhere.** Buttons, headings, navigation, toasts: `Aceitar selecionados`, not `Aceitar Selecionados` or `ACEITAR`.
- **No trailing periods** on short UI strings (buttons, badges, captions, table headers, toasts).
- **Periods on body sentences and empty-state messages.** `"Tudo em dia. Volte depois ou conecte uma conta para começar."`
- **Numerals always digits** — never spelled out. `3 itens`, not `três itens`.

### Example strings (canon)

| Surface | Copy |
|---|---|
| Empty inbox | `Tudo em dia. Volte depois ou conecte uma conta para começar.` |
| Empty budgets | `Crie seu primeiro orçamento` |
| Inbox bulk CTA | `Aceitar selecionados (3)` |
| Detail primary | `Aceitar` / `Rejeitar` / `Split` |
| Refund prompt | `Esta transação é um estorno?` |
| Refund confirm | `Estorno vinculado a {{título}}. Valor consolidado de {{título}} agora é R$ X.` |
| Loading button | `Aceitando…` |
| Import summary | `47 criados · 8 duplicados · 1 com erro` |
| Period header | `R$ 4.320,00 em 87 gastos · Receita R$ 6.500,00` |
| Overlap callout | `ℹ Alguns gastos aparecem em mais de uma categoria; a soma das categorias pode ser maior que o total real.` |
| Toast success | `Gasto consolidado` |
| Workspace prompt | `Casa do {{first_name}}` (default name) |

### Money formatting

Always monospace (`Geist Mono` / `JetBrains Mono`), `tabular-nums`, `font-medium`. Right-aligned in tables, left-aligned in detail forms. Negative amounts use `--destructive`; positives (receitas) use `--success`. The currency symbol `R$` is never separated from the number across a wrap — wrap with `white-space: nowrap` on the money cell.

---

## VISUAL FOUNDATIONS

The aesthetic target named in the spec is explicit: **Linear & Notion**. Concretely that means:

### Palette — light

| Token | Hex | Role |
|---|---|---|
| `background` | `#FFFFFF` | page |
| `foreground` | `#0A0A0A` | primary text |
| `card` | `#FFFFFF` | cards/panels (no fill difference from page) |
| `muted` | `#F5F5F5` | toolbar, sidebar, subtle surface |
| `muted-foreground` | `#737373` | secondary text |
| `border` | `#E5E5E5` | dividers, input strokes |
| `primary` | `#171717` | primary CTAs ("Aceitar") |
| `accent` | `#7C3AED` | links, focus ring, discrete highlights (Violet 600) |
| `success` | `#16A34A` | receita, positive amounts |
| `warning` | `#F59E0B` | budget ≥ 80% |
| `destructive` | `#DC2626` | reject, refund, delete |

### Palette — dark

Mirrors light with a single near-black surface stack and Violet 400 (`#A78BFA`) accent. **Default follows `prefers-color-scheme`**; explicit toggle persists to `localStorage`. There is no auto-applied tint or gradient — dark is `#0A0A0A` flat.

### Type

- **Sans:** Geist Sans (Vercel). Fallback: Inter. Both loaded from Google Fonts.
- **Mono:** Geist Mono. Fallback: JetBrains Mono. Used for **every** monetary value and inline code.
- **Scale** (Tailwind names, 14px body base): display 36/600, h1 24/600, h2 20/500, body 14/400, caption 12/400, money mono/500/tabular-nums.
- **No serifs anywhere.** No display font. The whole product is two families and the math takes the mono.

### Spacing & radius

- 4px base scale (Tailwind default). Card padding: `p-4` (16px) mobile, `p-6` (24px) desktop. Section gap: 24–32px.
- Radii: `4px` chips, `6px` default (buttons, inputs, sm cards), `8px` for cards/panels. **Never** `rounded-2xl`, never full pills. The spec is explicit: *"vibe Linear é discreta."*
- Mobile touch targets ≥ 44×44px. Bottom nav 56px. Header 56px. Sidebar 256px open / 56px collapsed.

### Backgrounds, gradients, imagery

- **None.** No hero images, no illustrations in product chrome, no gradient backgrounds, no photo backdrops, no patterns, no textures, no grain.
- Empty states use a **discrete monochromatic line illustration** (single weight, single color = `muted-foreground`) above the headline. Nothing else.
- Brand "logo" is the Lucide `wallet` icon at `foreground` color. No custom mark in MVP.

### Borders, shadows, elevation

- **Borders carry separation, not shadows.** `1px solid var(--border)`. Cards on background look identical to the page in fill — only the border distinguishes them.
- **Shadows are almost absent.** Only `Dialog`, `Popover`, `DropdownMenu`, `Sheet` (when floating), `Toast` get `shadow-lg`. Cards, headers, sidebars get **no shadow**.
- No inner shadows. No "neumorphic" anything.

### Animation & motion

- **Brief and functional.** Sheet/Dialog slide: 200ms cubic-bezier(0.16, 1, 0.3, 1). Toast fade-in 150ms.
- **No bounce, no spring overshoot, no looping animations.**
- **No skeletons that pulse aggressively** — shadcn's default `Skeleton` (gentle opacity oscillation, ~1.5s) is the only loading shimmer.
- Respect `prefers-reduced-motion` — fall back to instant transitions.

### Interaction states

| State | Treatment |
|---|---|
| **Hover (button)** | background darkens 4–6% (`primary` → near-black; `secondary` → `--muted` shade) |
| **Hover (row/card)** | background = `--muted` (light) / slight lift to `#1F1F1F` (dark) |
| **Hover (link)** | underline appears; color stays `--accent` |
| **Press / active** | background darkens further; **no scale-down**, no shrink animation |
| **Focus** | `outline: 2px solid var(--ring); outline-offset: 2px;` — visible always (keyboard-first product) |
| **Disabled** | `opacity: 0.5; cursor: not-allowed;` |

### Density & layout rules

- Default density is **comfortable**. Compact mode (denser list rows) is a future-day setting referenced in the spec.
- **Sidebar (desktop):** fixed left, 256px → 56px on collapse, items vertically stacked with 12px row height padding.
- **Bottom nav (mobile):** fixed bottom, full-width, 5 items with icon + 11px caption, 56px tall.
- **Header (both):** fixed top, 56px, contains breadcrumb or screen title left, search/avatar right.
- **Detail surfaces:** Sheet from bottom on mobile, Sheet from right on desktop (or Dialog for short forms).
- **No fixed floating CTAs** outside the bottom action bar on multi-select.

### Transparency & blur

- **Almost never.** No frosted glass, no backdrop-blur on chrome.
- The single exception is the **modal overlay**: `rgba(0, 0, 0, 0.5)` on light, `rgba(0, 0, 0, 0.7)` on dark, no blur.

### Charts (Tremor)

- Donut for category share. Bar for top tags. Line for monthly evolution.
- Palette draws from `--accent` + tints, with `--success`/`--destructive`/`--warning` reserved for semantic series only (e.g. income vs expense).
- Grid lines: `--border`. Axis text: `--muted-foreground`. No 3D, no gradients on bars, no drop shadow on chart elements.

---

## ICONOGRAPHY

The icon system is **Lucide** ([`lucide-react`](https://lucide.dev)) — same family shadcn/ui ships with. No other icon set is used in product.

- **Default size:** `h-4 w-4` (16px) in inline contexts (table cells, buttons, nav items).
- **Primary actions:** `h-5 w-5` (20px) — FAB on mobile, sidebar items at default state.
- **Stroke width:** Lucide default (`1.5px`). Do not override.
- **Color:** inherits `currentColor` from the parent — so icons are always `--foreground`, `--muted-foreground` in secondary roles, or `--accent` when "active". Never a hard-coded hex on an icon.
- **No emoji in UI.** None.
- **No unicode replacement glyphs** (no `→`, `✓`, `⋯` as icons — use `arrow-right`, `check`, `more-horizontal` from Lucide).
- **Logo mark** = Lucide `wallet` icon, sized 20–24px next to the wordmark "Controle Financeiro". Spec lists alternatives in the same family if a swap is wanted: `coins`, `banknote`, `landmark`, `piggy-bank`.

Because Lucide is delivered as a tree-shakable component library, **no SVG assets are committed to `assets/`**. The kit references icons by name (`<Wallet />`, `<Inbox />`, etc.) and the runtime renders them.

A small handful of Lucide icons are loaded inline as SVGs in this preview folder for the card previews — they are exact copies of the Lucide source (MIT-licensed) and live under `assets/icons/` for offline rendering of cards in the Design System tab.

### Icon vocabulary by surface

| Surface | Icons used |
|---|---|
| Sidebar / bottom nav | `inbox`, `wallet`, `pie-chart`, `bar-chart-3`, `more-horizontal` |
| Inbox row actions | `check` (aceitar), `x` (rejeitar), `split` (split), `link` (vincular estorno), `trash-2` (excluir) |
| Detail form | `calendar`, `tag`, `folder`, `credit-card`, `landmark` |
| Settings | `users`, `link-2`, `tag`, `folder`, `repeat`, `upload`, `bell`, `sun`/`moon` |
| Status | `loader-2` (spinner), `alert-circle`, `info`, `check-circle-2` |

---

## VISUAL ASSETS

| Asset | Path | Notes |
|---|---|---|
| Custom wallet mark | `assets/logo.svg` | Solid monochrome glyph, chamfered top-right, single accent dot. Color = `currentColor`. |
| Dark-variant mark | `assets/logo-dark.svg` | Same shape, accent dot punched against the dark surface. |
| Lucide `wallet` | rendered live | The spec's original default. Still valid — swap in if you prefer the pure Lucide look. |
| Favicons | not yet generated | Spec says: derive from the wallet mark at 16, 32, 192, 512 for PWA-readiness. |
| Brand illustrations | none | Spec is intentionally illustration-free. |
| Photography | none | The product does not use photography. |

---

## FONT SUBSTITUTION FLAG

Geist Sans and Geist Mono **are** available on Google Fonts (the spec lists Inter + JetBrains Mono only as fallbacks). The CSS in `colors_and_type.css` loads both Geist families from Google Fonts and falls back through Inter / JetBrains Mono / system stacks if the network blocks the import. **No font files are committed to `fonts/`** — there is no need to self-host given Geist's Google Fonts availability and the product's web-only delivery. If you want self-hosted woff2 files for offline rendering, request them and I'll bundle them.

---

## Index

```
README.md                   ← you are here
SKILL.md                    ← cross-compatible Agent Skill manifest
colors_and_type.css         ← single source of all tokens (light + dark)
assets/
  logo.svg                  ← custom minimalist wallet mark
  logo-dark.svg             ← dark variant
preview/                    ← 25 Design System tab cards
  _preview.css              ← shared base for preview cards
  colors-*.html             ← palette cards (neutrals light/dark, accent, semantic, AI confidence)
  type-*.html               ← typography specimens (display, headings, body+caption, money)
  spacing-*.html            ← 4px scale, radii, elevation
  components-*.html         ← buttons, badges, inputs, tag chips, inbox row, budget bar, detail footer, toast, confidence dot
  brand-*.html              ← logo & wordmark, empty state, app shell
ui_kits/
  app/                      ← the only product surface
    README.md
    index.html              ← click-through prototype: inbox · detail · gastos · budgets · reports · settings
    icons.jsx, data.jsx, primitives.jsx
    Shell.jsx, InboxView.jsx, DetailSheet.jsx
    GastosView.jsx, BudgetsView.jsx, ReportsView.jsx, SettingsView.jsx
    App.jsx, styles.css, views.css
```

---

## CAVEATS for the user

- The repo contains specs only — **no frontend code exists yet**. UI kit components are built from the design spec, not lifted from real JSX. Re-ground against the real app once it lands.
- No real logo file — using Lucide `wallet` per spec.
- No brand photography or illustrations — the product intentionally has none.
- Geist webfonts are pulled from Google Fonts. If you need woff2 files committed locally for offline/SSR fidelity, ask.
