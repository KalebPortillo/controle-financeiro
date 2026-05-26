---
name: controle-financeiro-design
description: Use this skill to generate well-branded interfaces and assets for Controle Financeiro, an inbox-first personal-finance webapp for a couple, either for production or throwaway prototypes/mocks. Contains essential design guidelines, colors, type, fonts, assets, and a UI kit recreating the inbox-first app surface (inbox, transaction detail, budgets, reports, settings).
user-invocable: true
---

# Controle Financeiro design skill

Read `README.md` in this skill first — it is the canonical reference for content + visual + iconography rules. Then browse the rest:

- `colors_and_type.css` — every design token (light + dark, type, spacing, radii, budget pastels). Import this on every artifact.
- `preview/` — small cards that show each token / component in isolation. Reference them when you need to remember the exact treatment.
- `ui_kits/app/` — React click-through prototype of the inbox-first app. Lift component shapes, copy, spacing, and interaction recipes from here. See `ui_kits/app/README.md` for the file map.
- `assets/` — the wallet logo SVG (custom minimalist mark, monochrome). Reference with `currentColor` so it inherits theme color.

## When the user invokes this skill

If they give no other guidance, ask them what they want to build. Useful questions:

- What surface? (whole app, single screen, marketing slide, mobile vs desktop)
- Light or dark theme? Default = light, but the system has full dark token coverage.
- Is this a faithful recreation or a divergent exploration?
- Are they bringing real data (a CSV, a screenshot of their bank statement), or is mock data fine?

Then act as an expert designer:

- **Production code**: copy `colors_and_type.css` into the codebase, and lift component recipes from `ui_kits/app/` while pointing the user at the real shadcn/ui equivalents (`Button`, `Sheet`, `Card`, `Toast`, `Badge`). Tell them where each token maps in a shadcn/Tailwind theme file.
- **Throwaway prototype / mock**: copy `colors_and_type.css` into a new HTML file, and either reuse the kit's JSX as a starting point or hand-write minimal JSX that matches the visual vocabulary.
- **Slide / marketing artifact**: this brand has no marketing surface yet, so anything you create is a small extrapolation. Stay within the visual rules in README — flat near-black backgrounds, single Violet accent, Geist + Space Grotesk display, no gradients, no illustrations. Lucide icons only. Wallet logo from `assets/logo.svg`.

## Hard rules (don't bend without asking)

- **Linear/Notion clean & minimal vibe.** No glass, no gradient backgrounds, no rounded-2xl, no pills, no shadows on cards.
- **Borders, not shadows**, for separation. Shadows only on overlays (modal, popover, toast).
- **Lucide icons only**, no emoji, no unicode arrow glyphs.
- **PT-BR copy**, sentence case, no trailing periods on short strings, no emoji in UI strings.
- **Money is monospace**, tabular-nums, formatted `R$ 1.234,56`. Negatives use `−` (em-dash), not `-`.
- **No marketing voice.** Toasts are sober: "Gasto consolidado", not "🎉 Saved!".

## Caveats

- The source repo currently has docs only (no frontend code), so the UI kit was built from the design spec alone. If a real frontend has landed since, re-ground against it.
- Custom wallet logo is in `assets/logo.svg` (replaces the spec's default of "use the Lucide wallet icon"). If the project prefers the Lucide wallet, switch to `<Wallet />` from `lucide-react` or the SVG in `ui_kits/app/icons.jsx`.
- Geist webfonts load from Google Fonts via `colors_and_type.css`. No woff2 files are committed.
