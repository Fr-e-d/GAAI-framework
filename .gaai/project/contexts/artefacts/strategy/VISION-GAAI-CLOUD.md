---
type: artefact
artefact_type: strategy
id: VISION-GAAI-CLOUD
track: discovery
status: vision — not scoped, not planned
created_at: 2026-02-24
updated_at: 2026-02-24
---

# VISION-GAAI-CLOUD: .gaai comme SaaS universel de gouvernance d'agents AI

> **Statut : Vision long-terme.** Pas un plan actif. Pas dans le backlog.
> Callibrate reste le véhicule principal. Cette vision se débloque *après* Callibrate.
> Références : DEC-2026-02-24-74, DEC-2026-02-24-75

---

## La thèse

```
MCP = protocole pour connecter des outils aux agents
.gaai = protocole pour gouverner des agents qui utilisent ces outils
```

MCP résout "comment l'agent parle à mes outils."
.gaai résout "comment l'agent structure mon travail, retient mon contexte,
et sépare réflexion / exécution."

Personne ne fait ça aujourd'hui de manière tool-agnostic.

---

## Signaux de marché

| Signal | Source | Date | Implication |
|---|---|---|---|
| Claude Cowork lancé | Anthropic | 2026-01-12 | Runtime agent grand public existe — manque la gouvernance |
| Cowork Plugins | Anthropic | 2026-01-30 | .gaai peut se brancher comme plugin Cowork |
| OpenClaw acqui-hire | OpenAI / Sam Altman | 2026-02-15 | "Next generation of personal agents" — les grands investissent |
| $285B SaaS selloff | Bloomberg | 2026-02 | Le marché price le remplacement des SaaS par des agents |
| EU AI Act | EU | En cours | Audit trail des agents → obligation réglementaire à venir |

---

## Les deux piliers de confiance

### 1. Sécurité — "l'agent ne peut PAS faire ce que je n'ai pas autorisé"

Modèle de permission progressive, par outil et par type d'action :

| Niveau | Comportement | Exemple |
|---|---|---|
| 0 — Suggest | L'agent suggère, l'humain fait | "Tu devrais répondre à Dupont" |
| 1 — Approve | L'agent fait, l'humain approuve avant | "J'ai rédigé la réponse. Envoyer ?" |
| 2 — Review | L'agent fait, l'humain review après | Email envoyé → notification + undo 5 min |
| 3 — Autonomous | L'agent fait dans un périmètre défini | Lecture de fichiers, recherche, analyse |

L'utilisateur choisit le niveau par outil et par type d'action.
Envoyer un email = niveau 1. Lire un fichier = niveau 3. Supprimer des données = niveau 0.

Transposition de .gaai : le backlog autorise, les artefacts documentent, les gates valident.

### 2. Observabilité — "je vois tout ce que l'agent fait, a fait, et pourquoi"

Pas des logs techniques. Un flux lisible par un humain non-technique :

| Composant | Ce que voit l'utilisateur |
|---|---|
| Live feed | "Je lis ton email de Dupont... J'ai trouvé une demande de devis... Je prépare une réponse..." |
| Decision trail | "J'ai choisi le template Devis Pro parce que le budget dépasse 10k€ (ta règle #3)" |
| Memory inspector | "Voici ce que je sais sur toi" — éditable, supprimable, exportable |
| Action history | Timeline complète avec undo sur les actions réversibles |
| Billing transparency | "Ce mois-ci : 47 actions exécutées, 12 approbations demandées, 0 erreurs" |

---

## Architecture technique — 3 couches progressives

### Couche 1 — Cowork Plugin (MVP, validation marché, 0 infra)

.gaai est déjà structurellement un plugin Cowork : skills, agents, slash commands, même format fichier.
Les plugins Cowork sont cross-compatibles Code ↔ Cowork. Distribution via le plugin marketplace.

```
Utilisateur Cowork installe le plugin .gaai
  → Discovery Agent + Delivery Agent disponibles
  → Memory persistante dans le workspace local
  → Dual-Track activé via slash commands
  → Cowork gère le runtime, l'auth, le modèle
```

| Avantage | Limite |
|---|---|
| Zéro infra à builder | Locké chez Anthropic |
| Distribution marketplace Cowork | Pas de multi-tenant |
| Validation marché rapide (jours) | Pas de dashboard web |
| Cross-compatible Code/Cowork | Pas d'audit centralisé |

**C'est le premier move technique.** Pas un SaaS. Un plugin.

### Couche 2 — Agent SDK Backend (le vrai SaaS, multi-tenant)

```
┌──────────────────┐
│    Web App        │  ← Dashboard, live feed, approvals, memory inspector
│   (Next.js)       │
└────────┬─────────┘
         │ API
┌────────▼─────────────────────────────────────┐
│         GAAI Orchestration Engine              │
│                                                │
│  ┌───────────────┐   ┌────────────────────┐   │
│  │  .gaai Core    │   │  Agent Runtime     │   │
│  │  (TS library)  │   │                    │   │
│  │                │   │  Claude Agent SDK   │   │
│  │  - Dual-Track  │   │  + OpenAI Agents   │   │
│  │  - Backlog     │   │  + any LLM API     │   │
│  │  - Permissions │   │  (tool-agnostic)   │   │
│  │  - Audit       │   └─────────┬──────────┘   │
│  │  - Memory      │             │              │
│  └───────────────┘    ┌─────────▼──────────┐   │
│                       │  Hosted MCP        │   │
│                       │  (UCL / Composio   │   │
│                       │   / self-hosted)   │   │
│                       └────────────────────┘   │
└────────────────────────────────────────────────┘
         │ Storage
┌────────▼─────────┐
│  Supabase / D1    │  ← Memory, audit trail, user config, playbooks
│  + R2             │
└──────────────────┘
```

**Composants clés :**

| Composant | Rôle | Tech | Nature |
|---|---|---|---|
| .gaai Core | Protocole de gouvernance — la vraie IP | TypeScript library | Open-source |
| Agent Runtime | Exécute Discovery/Delivery agents | Claude Agent SDK + OpenAI Agents API | Multi-provider |
| Hosted MCP | Connecte les outils de l'utilisateur | UCL, Composio, ou self-hosted | Externalisé ou self-hosted |
| Web App | Dashboard, live feed, approvals | Next.js / React | Propriétaire |
| Storage | Memory, audit, config, playbooks | Supabase (connu) + D1/R2 (CF) | Managed |

**Insight clé :** L'Agent SDK donne les capacités de Claude Code **sans le CLI**.
L'utilisateur interagit via une web app. L'agent raisonne avec Claude (ou GPT, ou les deux),
agit via MCP, et tout passe par la couche de gouvernance .gaai.

### Couche 3 — .gaai Protocol (standard ouvert)

.gaai Core publié comme spec ouverte. D'autres runtimes et plateformes l'adoptent.
Même dynamique que MCP : Anthropic publie le protocole, l'écosystème l'implémente.

### Briques existantes qui rendent ça possible (2026)

| Brique | Avant | Maintenant |
|---|---|---|
| Runtime agent grand public | N'existait pas | Cowork + plugins (Anthropic) |
| SDK pour agents custom | Bricolage | Claude Agent SDK (TS + Python) |
| Connexions outils standardisées | Chaque agent code ses intégrations | MCP + hosted gateways (UCL, Composio) |
| Exécution multi-provider | Locké chez un provider | MCP est provider-agnostic |
| Multi-tenant MCP hosting | N'existait pas | UCL ("Vercel for MCP"), Composio, Microsoft Foundry |

**Tout l'infra existe.** Ce qui manque : la couche de gouvernance entre l'utilisateur et ses agents.

---

## Adaptation par métier : Playbooks

Pas un produit différent par métier. Un runtime unique + des "Playbooks" :

- **Playbook** = ensemble de skills + MCPs + rules + memory template pour un métier
- Playbook "Comptable" = outils comptables + règles fiscales + skills extraction factures
- Playbook "Marketeur" = outils CMS + email + analytics + skills création contenu
- Playbook "RH" = outils ATS + calendrier + skills screening CV

L'utilisateur installe un playbook comme une app. Le runtime reste le même.
Les playbooks peuvent être créés par la communauté (marketplace).

---

## Pricing

| Tier | Contenu | Prix indicatif |
|---|---|---|
| Free | 1 playbook, niveaux 0-1 (suggestions), 50 actions/mois | 0€ |
| Pro | Playbooks illimités, tous niveaux, 500 actions/mois, memory persistante | ~29€/mois |
| Team | Multi-user, shared memory, audit compliance, playbooks privés | ~99€/mois |

Pricing par actions = alignement des incentives. Le SaaS facture quand l'agent délivre.

---

## Moats (avantages défendables)

1. **Memory lock-in.** Plus l'agent te connaît, plus il est efficace. Changer = repartir à zéro. Même dynamique que Spotify (playlists) ou Notion (workspace).

2. **Playbook marketplace.** Effets de réseau : plus de playbooks → plus d'utilisateurs → plus de créateurs.

3. **Audit trail comme standard de compliance.** Agent AI qui log chaque décision et action = obligation réglementaire à venir (EU AI Act). Être le standard d'audit = moat massif.

---

## Risques identifiés

| Risque | Probabilité | Mitigation |
|---|---|---|
| Anthropic/OpenAI ajoutent la gouvernance eux-mêmes | Élevée | Être tool-agnostic (pas dépendant d'un provider). Avance sur le protocole. |
| Vente d'infra product = cycle long | Élevée | Callibrate génère du revenu pendant le développement. Playbook marketplace = self-serve. |
| Non-devs ne veulent pas du Dual-Track | Moyenne | Hypothèse à tester. Le Dual-Track peut être invisible (UX simplifiée). |
| Le framework bouge trop pour être productisé | Moyenne | Callibrate stabilise .gaai sur usage réel avant productisation. |

---

## Séquence technique (progressive, chaque étape valide la suivante)

```
MAINTENANT        Callibrate + .gaai mûrit sur usage réel
                  ↓
Gate 2 PASS  →    Plugin Cowork .gaai (0 infra, validation marché non-dev)
                  Open-source .gaai Core (acquisition, feedback)
                  ↓
Gate 3 PASS  →    Case study Callibrate publié (crédibilité)
                  Formation payante (monétisation framework)
                  ↓
Adoption OSS →    .gaai Cloud MVP — Agent SDK backend (SaaS multi-tenant)
visible           Playbook marketplace
                  ↓
Traction     →    .gaai Protocol — spec ouverte (d'autres runtimes l'adoptent)
SaaS
```

Callibrate n'est pas un détour. C'est le proof of concept, le revenu runway,
et le case study marketing de .gaai Cloud.

La fenêtre de tir : être le premier protocole de gouvernance tool-agnostic
pendant que les grands construisent leurs runtimes propriétaires.
Callibrate donne 3-6 mois pour maturer .gaai gratuitement.

Le plugin Cowork est le **quick win** : faisable en jours, pas en mois,
et valide l'hypothèse critique "est-ce que des non-devs veulent du Dual-Track ?"
sans investissement infra.

---

## Prochaines étapes (pas maintenant — quand le moment viendra)

1. Packager .gaai comme plugin Cowork (premier move technique — jours, pas mois)
2. Valider l'hypothèse "non-devs veulent du Dual-Track" via adoption plugin
3. Identifier le premier playbook non-dev (quel métier ? quel pain point ?)
4. Publier .gaai Core comme TS library open-source
5. Landing page + waitlist .gaai Cloud
6. MVP SaaS : Next.js + Agent SDK + hosted MCP + Supabase

> **Rappel : aucune de ces étapes n'est active.** Callibrate d'abord.
