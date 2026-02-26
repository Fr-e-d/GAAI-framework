---
type: memory
category: ops
id: OPS-002
tags:
  - ops
  - channels
  - distribution
  - social-media
created_at: 2026-02-26
updated_at: 2026-02-26
---

# Distribution Channels

> Ce fichier documente les comptes et canaux de distribution configurés pour la Phase 0-1 (cold start).
> Stratégie : personal brand (BIP) — pas de brand account actif avant Phase 3+.
> Référence stratégie : CONTENT-STRATEGY-001, COMMS-001.

---

## Canaux actifs

### X / Twitter — Personal (primary BIP)

| Paramètre | Valeur |
|---|---|
| Handle | `@frederic_geens` |
| Type | Professional |
| Auth | Google (compte perso) |
| Bio | "Builder from Belgium. Building in public: Callibrate (AI expert matching) + .gaai (AgenticOps framework). AI needs rules, not vibes." |
| Notifications | OFF |
| Personnalisation | OFF (toutes options) |
| DMs | Ouverts à tous |
| Langue | English |
| Date création | 2026-02-26 |

### X / Twitter — Brand (dormant/reserved)

| Paramètre | Valeur |
|---|---|
| Handle | `@callibrate_io` |
| Type | Protected (tweets privés) |
| Auth | Google (ops@callibrate.io) |
| Bio | "AI expert matching platform. Coming soon." |
| Notifications | OFF |
| Usage | Réservé — aucune activité avant Phase 3+ |
| Date création | 2026-02-26 |

### Substack — Personal Blog

| Paramètre | Valeur |
|---|---|
| Handle | `fredericgeens` |
| URL | `https://fredericgeens.substack.com` |
| Auth | Email perso (asset personnel, pas ops@) |
| Name | Frédéric Geens |
| Bio | "Building in public. AI agent governance (.gaai) + expert matching (Callibrate). Decisions, code, metrics — no fluff." |
| Catégories | Technology, Artificial Intelligence, Business |
| Paid tier | Non activé (Phase 0-1) |
| Date création | 2026-02-26 |

### dev.to — Cross-post tech

| Paramètre | Valeur |
|---|---|
| Username | `Fr-e-d` |
| URL | `https://dev.to/fr-e-d` |
| Auth | GitHub (`Fr-e-d`) |
| Name | Frédéric Geens |
| Bio | "Building in public: Callibrate (AI expert matching) + .gaai (AgenticOps framework). Program & Ops Manager. Belgium." |
| Tags suivis | #ai, #typescript, #opensource, #productivity, #devops |
| Newsletter | Weekly digest only |
| Date création | 2026-02-26 |

### Reddit — Existing (pre-Phase 0)

| Paramètre | Valeur |
|---|---|
| Username | `Fr-e-d` |
| Subreddit détenu | r/AIAgentGovernance (DEC-99) |
| Usage | Engagement communautaire, seed content |
| Phase | Actif — 9 clusters Reddit identifiés (COMMS-001) |

---

## Canaux planifiés (non actifs)

| Canal | Usage prévu | Condition d'activation |
|---|---|---|
| Hacker News | Flagship content, .gaai launch | Post-Gate 2 (.gaai OSS) |
| Blog Callibrate | Brand content marketing | Phase 3+ |
| `news.callibrate.io` | Email marketing (ESP séparé) | Phase 3+ |

---

## Principes

- **Personal first** : tout le contenu Phase 0-1 sort sous le nom de Frédéric Geens, pas Callibrate.
- **Cross-post avec canonical_url** : Substack = source, dev.to = cross-post avec `canonical_url` pointant vers Substack (SEO).
- **Pas de brand content avant Phase 3+** : `@callibrate_io` et blog Callibrate restent dormants.
- **API keys** : aucune configurée en Phase 0-1 (post manuel). À réévaluer si volume > 3 posts/semaine.
