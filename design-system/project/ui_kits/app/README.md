# Controle Financeiro — App UI kit

A click-through prototype of the only product surface the brand has: the inbox-first finance webapp.

This is a **cosmetic recreation**, not real code. It implements the visual + interaction patterns specified in [`docs/requisitos-design.md`](https://github.com/KalebPortillo/controle-financeiro/blob/main/docs/requisitos-design.md) using React + plain CSS instead of the production stack (Vite + Tailwind + shadcn/ui). Use it to reach for component shapes, copy, spacing, and interaction recipes when building real designs.

## What's interactive

- **Sidebar navigation** between Inbox / Gastos / Orçamentos / Relatórios / Mais
- **Theme toggle** in the top bar (light ↔ dark, default follows OS)
- **Inbox row → detail sheet** — click any row to open the right-side drawer
- **Accept / Reject** an inbox item (single via sheet, or bulk via the action bar)
- **Multi-select** rows with checkboxes; "Aceitar selecionados (n)" appears as a sticky bottom action bar
- **Search** transactions via the top bar (Cmd+K not wired but `/` focuses)
- **Hotkeys** (when a detail sheet is open): `A` accept, `R` reject, `Esc` close

## File layout

| File | Role |
|---|---|
| `index.html` | Shell — loads React + Babel + every module |
| `icons.jsx`  | Inline Lucide icons exported on `window.CFIcons` |
| `data.jsx`   | Mock workspace data — tags, categories, inbox items, budgets |
| `primitives.jsx` | `Button`, `Badge`, `TagChip`, `Money`, `Input`, `Sheet`, `ProgressBar`, `Card`, `Skeleton`, `ConfidenceDot` |
| `Shell.jsx`  | `Sidebar` + `TopBar` + `BottomNav` |
| `InboxView.jsx`    | Inbox list + row + bulk action bar |
| `DetailSheet.jsx`  | Right-side drawer for editing a pending transaction |
| `GastosView.jsx`   | Consolidated spends with filters + totals |
| `BudgetsView.jsx`  | Monthly budget cards with pastel progress bars |
| `ReportsView.jsx`  | KPI cards + donut + horizontal bars + 12-month line chart |
| `SettingsView.jsx` | "Mais" landing with workspace + sub-sections |
| `App.jsx`          | Root, owns view + theme + selection state |
| `styles.css`, `views.css` | All UI kit CSS, grounded in `colors_and_type.css` tokens |

Components are written for clarity, not production reuse — each view is its own file and pulls primitives off `window.CFUI`.

## What's not implemented

The product spec covers a lot. This kit only mocks visual + interaction shells for the surfaces above. **Not built:**

- Onboarding / login (would be a single-card centered screen — straightforward)
- Split wizard (2-step modal — design lives in `requisitos-design.md`)
- Pluggy Connect handoff
- CSV / OFX upload UI
- Tag and Category management screens
- Recurrents detail
- Workspace invite flow

If you need any of these for a design, lift the patterns from `requisitos-design.md` and the existing primitives.

## When the real frontend lands

This kit was built before any production frontend existed in [`KalebPortillo/controle-financeiro`](https://github.com/KalebPortillo/controle-financeiro). When real React + shadcn/ui code lands in the repo, **re-ground this kit against it**:

1. Read the real `tailwind.config.{ts,js}` and `globals.css` — sync any drifted tokens into `colors_and_type.css`.
2. Pull the real `components/ui/*` from shadcn/ui CLI — replace the JSX in `primitives.jsx` with the actual primitive markup if it differs.
3. Use the real screen layouts as the source of truth for `InboxView`, `DetailSheet`, etc. — keep the kit cosmetic but visually identical.
