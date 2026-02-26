---
type: artefact
artefact_type: strategy
id: COMMS-001
track: discovery
created_at: 2026-02-24
updated_at: 2026-02-24
---

# COMMS-001: Communication & Publication Strategic Plan

> Principe directeur : chaque contenu sert le funnel de lancement orchestré (DEC-77).
> Même contenu, 3 audiences chauffées en parallèle : Callibrate, .gaai OSS, personal brand.
> Budget : **5h/semaine** (hard cap sauf semaines de lancement Gate).

---

## Vue d'ensemble

```
CANAUX ACTIFS          AUDIENCE                   CADENCE
─────────────────────────────────────────────────────────────
X/Twitter (@Fr-e-d)   P3 devs + P4 industry      2-3 threads/semaine
Reddit (19+ subs)     P1 experts + P2 prospects   3-4 interactions/semaine
Blog perso (Substack) P3 devs + P4 industry       1x/mois (milestones)
dev.to                P3 devs                     1x/mois (cross-post)
Hacker News           P3 devs + P4 industry       3-4 Show HN total

CANAUX DIFFÉRÉS
─────────────────────────────────────────────────────────────
LinkedIn              P1 + P2 + P4                Au lancement produit (DEC-31)
GitHub                P3 + P4                     Post Gate 2 PASS (DEC-72)
```

**Références :** GTM-001 (phases/gates), E01S05 (flagship post), SKILL-CRS-021 (automation), DEC-77 (orchestrated launch)

---

## Storytelling Backbone — The .gaai Origin Story

> This narrative arc is the emotional backbone of ALL content. Every piece — the flagship post, X threads, Reddit engagement, HN submissions — should trace back to this story.

### The narrative in 7 beats

**Beat 1 — Who is this person?** (credibility, not CV)
Frédéric Geens. 10+ years autodidact developer. Hundreds (thousands) of hours coding solo, mostly at night. Co-founded a transport company in 2015, built one of Wallonia's first online booking platforms — coding between rides, laptop on knees. Led a non-profit helping founders. Started with SEO, fell in love with SaaS. Devoured Rob Walling's "The SaaS Playbook" — bootstrap philosophy, start small stay small, no VC needed. By day: IT Program Manager (30h/week). By night: builder, explorer of ideas, obsessive thinker about approaches. Key trait: perseverance, curiosity, "painkillers not vitamins." NOT someone who just discovered vibe coding.

**Beat 1b — The human element** (what makes the story stick)
His partner is his guardrail. She watches over his balance, pulls him out of his cave to live adventures beyond the screen. She's the source of his energy, tenacity, and perseverance. Years of watching him stubbornly build project after project at night — most never seeing the light of day — and she's still there. She's the one who said "no laptop in Vietnam." Without that, he never takes the step back. Without the step back, .gaai doesn't exist. The irony is too good not to tell: **a governance framework for AI agents, born because a human imposed governance on the builder.** This is the emotional core — it humanizes the tech, it makes the reader root for the founder, and it's a line that sticks.

**Beat 2 — The digital detox (the constraint that made everything possible)**
6 weeks in Vietnam. His partner banned the laptop — after years of watching him disappear behind the keyboard every night. But the AI world was exploding: OpenClaw security crisis, Claude Cowork launch, B-Mad, Ralph Wiggum, new models every week. The itch was unbearable. So instead of coding... the founder started *thinking*.

**Beat 3 — The research phase (iPhone 8, scientific papers, state-of-the-art)**
From a painfully slow iPhone 8:
- Read scientific papers: impact of separating reflection from execution, context engineering, isolation, persistent memory
- Followed every Anthropic release: skills, sub-agents, agent-teams
- Filtered the noise from YouTube, forums, papers — condensed the signal
- Used Gemini 3 (just released) via Google NotebookLM to synthesize the agentic coding state-of-the-art
- Used ChatGPT 5.2 (just released) to *brutally* challenge every idea — no complacency
- Connected Notion MCP server to ChatGPT to capture everything
- Built on AI-Governor-Framework (own earlier OSS project) — not starting from zero

**Beat 4 — Assembly (.gaai is born)**
Piece by piece, the framework took shape in Notion. Dual-Track (separate thinking from doing). Persistent memory (agents remember). Decision logging (every choice is traceable). Skill-based execution (agents do what they're told, nothing more). The iPhone was painfully slow. But the ideas were forming.

**Beat 5 — The return (first implementation)**
Back in Belgium. Laptop open. First real implementation with Claude Code. The result? *Far beyond expectations.* Not just faster development — confident shipping. The kind of confidence where you push to production and sleep well.

**Beat 6 — The validation decision**
Immediate reaction: "I need to share this and open-source it." But the founder's instinct kicked in: validate first. Don't hype an untested framework. Build a real, complex project with it — Callibrate, an AI expert matching marketplace — and see if .gaai holds up. Not a toy demo. A real SaaS with auth, billing, matching engines, queue workers, AI extraction, booking flows.

**Beat 7 — The proof (where we are now)**
39+ stories delivered. 77+ decisions documented. 260+ tests passing. 7 epics. Full platform built by governed AI agents. The framework held. It didn't just hold — it made the complexity manageable. And now it's time to share what was built.

### Why this story works

- **Relatable constraint** — everyone knows the itch of wanting to code but being forced to think
- **Authenticity** — iPhone 8, digital detox, girlfriend banning laptop = memorable, human, can't be faked
- **Intellectual rigor** — cross-validated with competing AI models (Gemini + ChatGPT), read scientific papers, didn't just follow one hype cycle
- **Credibility** — 10+ years of building, not a newcomer who discovered AI last month
- **Integrity** — chose to validate on a real project before open-sourcing, didn't rush to hype
- **Results** — concrete numbers, not promises

### How to use the story across channels

| Channel | Story usage | Length |
|---------|-------------|--------|
| Flagship blog post (E01S05) | Full narrative arc (Beats 1-7), first third of the post | ~800 words |
| X thread (origin story) | Beats 2-5 compressed, one tweet per beat | 5-7 tweets |
| HN submission | Story implicit in the post, referenced in comments when asked "how did you build this?" | As needed |
| Reddit | Bits of the story woven into replies ("I actually designed this framework from my phone during a 6-week digital detox in Vietnam") | 1-2 sentences |
| LinkedIn (launch day) | Beat 1 (who am I) + Beat 7 (what I built) — professional framing | 3-4 paragraphs |
| .gaai OSS README | Beat 6-7 only — why this framework exists and what it proved | 2 paragraphs |

---

## Part 0 — Writing Style Guide (AI-Assisted Human Voice)

> Référence : recherche best practices 2025-2026 (Wikipedia Signs of AI Writing, Every.to, SurferSEO, Paul Graham analysis, Julia Evans analysis, HN/Reddit/dev.to channel studies). Appliqué à TOUT le contenu produit par SKILL-CRS-021 et édité par le founder.

### The 3-Phase Workflow (Context Engineering > Prompt Engineering)

1. **OBSERVE** — gather raw materials BEFORE writing: decision log entries, backlog data, test results, Reddit quotes, real metrics
2. **DISTILL** — convert into narrative context: what happened, why it matters, what the reader gains
3. **CRYSTALLIZE** — AI drafts with full context loaded, founder edits for voice and personality

### 10 Non-Negotiable Writing Rules

1. **Specific beats comprehensive.** "79 decisions in 4 days" not "many decisions made quickly."
2. **Opinion beats hedging.** "This approach is wrong because..." not "While some may argue..."
3. **Kill every AI tell word.** See kill list below. Search-and-destroy before publishing.
4. **Front-load value.** First 25% of any piece delivers 50% of the insight.
5. **Show the work.** Code, screenshots, data, real examples. Not theory.
6. **Write for one reader.** Picture a specific person (P3 dev using Claude Code) and write to them.
7. **Match the channel.** HN = technical depth. X = hooks. Reddit = community value. dev.to = tutorials.
8. **The 90/10 rule.** Give value 90% of the time. Promote 10%.
9. **Read it aloud.** If it sounds like a corporate press release, rewrite.
10. **10-15% informality quota.** Contractions, sentence fragments, conversational asides. "It's" not "it is."

### AI Writing Kill List (words/phrases to ELIMINATE)

**Dead giveaway words:** delve, tapestry, landscape (as metaphor), beacon, crucible, labyrinth, gossamer, whimsical, enigma, virtuoso, symphony (metaphorical), treasure trove, bustling

**Overused transitions (replace or delete):** Furthermore → [delete], Moreover → [delete], Additionally → "Also" or nothing, In conclusion → [stop writing before you need this], It's worth noting that → just state the thing, Subsequently → "Then", Consequently → "So", Nevertheless → "But" or "Still"

**Inflated importance (deflate or cut):** "A testament to..." → say what it demonstrates. "Plays a vital/crucial/pivotal role" → say what it does. "Transformative" → say what it transformed, from what to what. "Watershed moment" → be specific about what changed.

**Structural tells to avoid:**
- Negative parallelism overuse ("It's not X, it's Y" — AI uses this every 3rd paragraph)
- Trailing -ing clauses ("...highlighting the importance of..." — cut them)
- "Despite its [positives], [subject] faces challenges..." — name the specific challenges or cut
- The everything sandwich ("In today's fast-paced X..." → [DELETE ENTIRE SENTENCE])
- Bolded bullet point headers ("**Scalability:** The system scales..." — let content speak)
- Weasel attribution ("Industry reports suggest..." — name the source or cut)

**The replacement test:** For every AI word, ask "What would I say to a colleague at a whiteboard?"
- "Leverage AI capabilities" → "use AI"
- "Navigate the complex landscape" → "figure out"
- "A robust and scalable solution" → "it handles load well"
- "Embark on a transformative journey" → [DELETE]

### Channel-Specific Adaptation Rules

**Hacker News:**
- Zero marketing language. If it reads like a press release, it dies.
- Factual title with a concrete detail: "79 decisions, 39 stories: governing AI agents to build a SaaS in 4 days"
- Post link, add context as first comment explaining the backstory
- Engage every reply with data and reasoning, never defensiveness
- Post Tue/Wed 9am-12pm Pacific

**X/Twitter threads:**
- Hook tweet is everything. Write 10-15 versions before choosing.
- Patterns that work: surprising stat, provocative question, bold claim, "I [did X] and [unexpected result]"
- Each tweet = one clear point. One sentence per line where possible.
- 5-15 tweets optimal. Under 5 feels thin; over 15 loses readers.
- Include 1-2 visuals (screenshots, diagrams, before/after)
- End with clear CTA in last tweet only

**Reddit:**
- 90/10 rule: 90% genuine community value, 10% own work
- New accounts posting links = auto-flagged. 2-4 weeks warm-up minimum.
- Roughen the writing style: shorter sentences, contractions, deliberate imperfection
- TL;DR at the top for longer posts
- Disclose affiliation: "Full disclosure: I built this"
- Link to project at END, after providing value

**dev.to:**
- Cover image (mandatory for visibility)
- Canonical URL if cross-posting from blog
- Tutorial-style with code blocks and step-by-step
- 4 tags, lead with most popular relevant tag

### Techniques from the Best Technical Writers

**Paul Graham style:**
- Self-riffing: introduce a word, then call attention to it ("That word 'governance' is the key")
- Deliberate chattiness: mix contractions with formal constructions
- Relentless curation: every essay is 1,000 ideas narrowed to 13
- Shorten sentences as you approach a key point, then pause

**Julia Evans style:**
- Narrate the journey from confusion to understanding
- Wonder and curiosity as tone: "I just figured this out and it's wild"
- Specific is better than comprehensive: deep dive on one thing beats survey of 50

---

## Part 1 — Empathy Maps

### P1 — Expert AI/Automation (paying customer Callibrate)

**Archetype :** Caio Valadares — automation engineer, Europe/Brussels, n8n/Python/Claude. Trouve ses clients via Reddit et Upwork faute de mieux. A les compétences pour builder un lead gen engine lui-même mais pas le temps.

| Dimension | Contenu |
|-----------|---------|
| **THINK** | "Je passe la moitié de ma semaine à chasser des leads au lieu de faire le travail pour lequel je suis bon." — "90% de l'inbound c'est des tire kickers à $50." (Littlecutsie, r/n8n_ai_agents — H1 validé) — "Si j'augmente mes prix, mon pipeline se tarit ? Si je baisse, je me sous-évalue ?" — "Upwork c'est le défaut et tout le monde fait avec." (SilentButDeadlySquid, Top 1% r/Upwork — H12 validé) |
| **FEEL** | Frustré : 6-7h/semaine de lead gen qui donne surtout du non qualifié (H2 validé). Anxieux : revenus feast-or-famine imprévisibles. Méfiant envers les plateformes qui promettent des leads (déjà eu de mauvaises expériences). Fier de son craft mais amer que le marketing compte plus que les compétences techniques. |
| **SEE** | LinkedIn rempli de "AI consultant" sans substance. Upwork race to the bottom. Plateformes génériques qui ne différencient pas un job Zapier à $200 d'un workflow custom à $5k. D'autres experts qui semblent avoir un pipeline mais ne partagent jamais comment. |
| **HEAR** | "Marketing and sales is part of the job" (r/Upwork — résignation). "Best leads come from niche communities and partnerships, not open marketplaces" (Rich-Emu-1561 — H5 validé). "Anything and everywhere. I would stand on a street corner." (SilentButDeadlySquid — fragmentation desperate). |
| **SAY** | "My ideal clients are unresponsive" (r/aisolobusinesses). "Half my week finding decent leads" (vocabulaire validé). "I need clients who have budget, timeline, and a decision-maker at the table." |
| **DO** | 30-50% du temps de travail en lead generation et qualification (H2 validé). Browse Reddit, Upwork, LinkedIn chaque jour. Build ses propres funnels Typeform/n8n pour filtrer l'inbound. Accepte des projets sous-optimaux pendant les périodes creuses. |
| **PAIN** | Budget = deal-breaker #1 (Academic-Highlight10 — H1 validé). Temps gaspillé sur des prospects qui ghostent après le discovery call. Plateformes où "prompt engineers with a Zapier account" compétent sur le même listing. Peur de payer pour un service qui livre des leads poubelle. |
| **GAIN** | 3-5 leads pré-qualifiés/mois avec budget confirmé et décisionnaire. Récupérer 6-7h/semaine perdues en filtrage. Pipeline prévisible sans hustle LinkedIn ni cold outreach. Contrôle sur ce qu'il accepte : budget min, vertical, type de projet. |

---

### P2 — Prospect PME (produit livré via Callibrate)

**Archetype :** Directeur opérations d'une SaaS 30 personnes. A besoin d'automatiser le screening CV mais ne sait pas évaluer qui peut vraiment le faire. A été brûlé par un "consultant" qui a livré une chaîne Zapier cassée après une semaine.

| Dimension | Contenu |
|-----------|---------|
| **THINK** | "Je ne sais pas ce que je ne sais pas sur l'AI automation." — "Comment distinguer quelqu'un qui comprend la logique métier de quelqu'un qui connaît juste les outils ?" — "J'ai mis 3 mois la dernière fois. Je n'ai pas ce temps." (Present-Access-2260 — H7 validé) — "10-15% des profils Upwork peuvent vraiment faire de l'architecture workflow." (PathStoneAnalytics — H8 validé) |
| **FEEL** | Overwhelmed par le volume de choix sur les plateformes génériques (200 profils, impossible de comparer). Méfiant : brûlé une fois, maintenant hyper-prudent. Anxieux côté budget : projets AI = chers, outcomes incertains. Soulagé quand il trouve finalement quelqu'un de compétent, mais ce soulagement a pris trop longtemps. |
| **SEE** | Profils Upwork qui se ressemblent tous : "AI automation expert, 5 stars, $50/hr". LinkedIn connections qui pitchent des services AI non sollicités. Collègues qui ont trouvé de bons consultants via réseau perso inaccessible. |
| **HEAR** | "Tu devrais automatiser ça" (board, pairs, médias). "Mon pote a utilisé un gars super..." (bouche-à-oreille qu'il n'a pas). "Vague AI automation claims are a red flag" (vocabulaire validé). "Anyone who refuses a paid audit either can't do it or doesn't need your business" (PathStoneAnalytics). |
| **SAY** | "I'm looking for a workflow architect, not just someone who knows Zapier." (vocabulaire validé) — "How do I know this person actually understands my industry?" — "Budget is defined, but I need confidence before I spend it." |
| **DO** | Cherche Upwork/LinkedIn, se sent overwhelmed, reporte sa décision. Paie des audits à $100-200 pour vérifier les consultants (PathStoneAnalytics — H9 validé). Demande à son réseau pro des recommandations (lent, peu fiable). Finit par se contenter de "good enough" après des semaines de recherche. |
| **PAIN** | 3 mois en moyenne pour trouver le bon expert (H7 validé). 85-90% des profils platform ne sont pas de vrais workflow architects (H8 validé). Bouche-à-oreille = meilleur canal mais exclut ceux sans le bon réseau. Risque de gaspiller le budget sur un consultant incompétent. |
| **GAIN** | Matché avec 2-3 spécialistes pré-sélectionnés filtrés par budget, industrie et type de projet. Confiance que l'expert a été vérifié et comprend son contexte métier. De "j'ai besoin d'aide" à "je suis en call avec la bonne personne" en <48h au lieu de 3 mois. |

---

### P3 — Developer/AI Builder (ICP pour .gaai OSS + build-in-public)

**Archetype :** Solo dev utilisant Claude Code quotidiennement. A construit 3 side projects avec l'assistance AI. Chaque nouvelle conversation repart de zéro — contexte perdu, décisions oubliées, mêmes erreurs répétées. Suit r/ClaudeAI et Hacker News.

| Dimension | Contenu |
|-----------|---------|
| **THINK** | "Chaque session Claude Code, je repars de zéro. Il ne se souvient pas de ce qu'on a décidé la semaine dernière." — "J'ai besoin d'un système, pas juste d'une interface chat." — "Les outils AI sont géniaux au niveau tâche mais terribles au niveau projet." — "La crise OpenClaw (800+ skills malicieux, 30K instances exposées) était prévisible — pas de guardrails, pas de governance." |
| **FEEL** | Excité par le dev assisté par AI mais frustré par ses limites. Overwhelmed par le rythme des nouveaux outils (Cowork, Agent SDK, MCP, nouveaux modèles chaque mois). Sceptique envers "AI governance" qui n'est que du marketing — veut voir une implem réelle. Impressionné par les builders qui montrent leur travail avec des vrais chiffres. |
| **SEE** | Nouveaux outils AI chaque semaine, chacun prétendant être différent. Posts HN sur des agents AI qui dérapent. Build-in-public threads de founders qui partagent des métriques réelles. AI governance discutée théoriquement mais rarement implémentée. |
| **HEAR** | "AI agents need guardrails" (dit souvent, implémenté rarement). "Use CLAUDE.md for context" (basique, perd la cohérence entre sessions). "Show me the code" (le standard HN/dev de preuve). |
| **SAY** | "How do you maintain context across 50+ AI sessions on the same project?" — "Is there a framework for this or is everyone winging it?" — "Show me your decision log, not your architecture diagram." — "I'd use this if it doesn't add overhead to my workflow." |
| **DO** | Start new Claude Code sessions daily, re-explain context each time. Create ad-hoc CLAUDE.md files. Track decisions dans des notes éparses ou pas du tout. Follow AI tool releases sur X, HN, Reddit. Try new frameworks, abandon most after 1-2 sessions. |
| **PAIN** | Context evaporation : chaque session est un cold start. Decision amnesia : redécouvrir les mêmes trade-offs. Pas de séparation entre "réfléchir à quoi faire" et "le faire". Agents AI qui dérapent sans comprendre le projet. Anxiety de l'overhead : tout framework de governance doit être near-zero friction. |
| **GAIN** | Mémoire persistante qui traverse les sessions automatiquement. Dual-Track : Discovery réfléchit, Delivery exécute. Decision trail : chaque choix loggé, searchable, auditable. Agent AI qui reste dans les limites définies. Un vrai exemple de governance qui marche sur un vrai projet avec des vrais chiffres (pas de la théorie). Framework open-source adaptable. |

---

### P4 — AI Industry / Recruiters (audience implicite)

**Archetype :** DevRel lead chez Anthropic. Lit Hacker News quotidiennement. Évalue les recrues potentielles par leur travail public. Cherche des gens qui pensent profondément à la gouvernance des agents AI avec preuve d'exécution.

| Dimension | Contenu |
|-----------|---------|
| **THINK** | "Everyone talks about AI safety. Who is actually building governance into their daily workflow?" — "Show me the body of work, not the resume." — "MCP was step one. Governance is step two. Who is going to define it?" |
| **FEEL** | Fatigué par le volume de hype AI et de contenu superficiel. Excité quand il trouve quelqu'un qui combine profondeur de pensée et shipping speed. Pression pour trouver/construire la couche governance avant que les régulateurs l'imposent. |
| **SEE** | Des milliers de profils "AI builder" sans travail public substantiel. Occasionnellement un post HN avec des données réelles qui se démarque nettement. EU AI Act qui avance vers l'obligation d'audit trails pour les décisions AI. OpenClaw security crisis. |
| **HEAR** | "The best engineers write well" (valeur culturelle Anthropic). "Safety is our brand" (positionnement Anthropic). "Have you seen this person's work?" (le referral peer est le canal de signal hiring). |
| **SAY** | "Send me a link to something they've built." — "Do they have a blog? A Show HN? Open-source work?" — "The governance problem is harder than the capability problem." |
| **DO** | Scan HN, X, dev.to pour des builders avec de la substance. Évaluent les candidats par artefacts publics : blog posts, open-source, talks. Partagent le travail intéressant en interne ("look at what this person built"). |
| **PAIN** | Trop de bruit, pas assez de signal dans le marché talent AI. Difficile d'évaluer la "governance thinking" depuis un CV ou un profil LinkedIn. La plupart des candidats parlent de safety mais ne l'ont jamais implémenté. |
| **GAIN** | Un candidat avec 77+ décisions documentées, 39+ stories livrées avec AI governance. Preuve publique de travail : blog posts, framework open-source, métriques réelles. Quelqu'un qui a construit un système de production en utilisant exactement le paradigme pour lequel ils recrutent. |

---

## Part 2 — Channel Strategy Matrix

### X/Twitter (@Fr-e-d)

**Personas :** P3 (devs), P4 (industry), P1 (experts — secondaire)
**Tone :** Direct, analytique, légèrement irrévérencieux. Confiant sans arrogance. "Here's what happened and what I learned." Data over opinions.

**Formats :**
- Threads (5-7 tweets) : deep dives sur des décisions spécifiques, choix d'architecture, métriques hebdo
- Single tweets : un insight, un screenshot, un data point
- Screenshots : terminal output (Claude Code + .gaai), decision log entries, backlog state, test results
- Terminal recordings (asciinema) : clips courts du Dual-Track en action

**Axes éditoriaux :**

| Axe | Exemple | Fréquence |
|-----|---------|-----------|
| "Decision of the week" | "Why I removed KV from my cache architecture (and what replaced it)" — DEC-69 | 1x/semaine |
| "Metrics update" | "Week 6: 39 stories, 77 decisions, 260 tests. Here's what moved." | 1x/semaine |
| "AI governance real talk" | "Your AI agent made 47 decisions today. Can you name 3 of them?" | 1x/2 semaines |
| "Build-in-public milestone" | "Gate 1 passed. Full loop working. Here's the timeline." | Aux gates |
| "The obvious mistake" | "I accumulated 19 PRs without merging. Never do this." — DEC-71 | Ad hoc |
| "Teaser" | "The framework behind this will be open-source soon." | 1 tease / 3-4 threads |

**Cadence :** 2-3 threads/semaine (30 min chaque). Best times : Tue/Wed/Thu 10am-12pm ET.

**Cold start (de E01-xcom-strategy.md) :**
1. J1-J3 : Follow 50-100 comptes actifs dans le niche
2. J3-J5 : Commenter 5-10 posts populaires (vraies réponses, pas du spam)
3. J5 : Premier build-in-public thread + $20 promoted tweet
4. J7 : Analyse résultats. 5+ interactions qualité → continuer. 0 → tester un autre angle.

**Engagement rules :**
- Répondre à chaque commentaire substantiel dans les 6 premières heures
- Quote-tweet les réponses intéressantes avec un insight ajouté
- NE PAS engager avec les trolls ou les arguments de mauvaise foi. Le silence est la réponse.
- Ne jamais pitcher Callibrate directement. Laisser les threads référencer naturellement la plateforme en construction.

---

### Reddit (19+ subreddits, déjà actif)

**Personas :** P1 (experts), P2 (prospects), P3 (devs)
**Tone :** Authentique, casual, question-driven. NEVER pitch. NEVER mention the platform name. Style volontairement imparfait (leçon r/digitalnomad bot detection).

**Stratégie par cluster :**

| Cluster subreddits | Persona | Angle | Type engagement |
|--------------------|---------|-------|-----------------|
| r/aisolobusinesses, r/AiSolopreneurs | P1 experts | Lead gen pain, time waste, pipeline | Discussion + replies |
| r/AiAutomations, r/Automate | P1 experts | Where clients come from, platform gaps | Discussion + replies |
| r/gohighlevel | P1 experts | Client quality, non-negotiable criteria | Replies only |
| r/Upwork, r/freelancing, r/freelance_forhire | P1 experts | Platform frustration, alternatives | Discussion + observation |
| r/AiForSmallBusiness, r/smallbusiness | P2 prospects | Finding the right expert, trust | Replies to "how do I find..." |
| r/ClaudeAI, r/artificial | P3 devs | AI governance, persistent memory | Discussion + "here's how I solved X" |
| r/LocalLLaMA | P3 devs | Framework structure, agent governance | Replies (technique deep) |
| r/EntreprendreenFrance | P2 prospects FR | PME cherchant consultant AI | Discussion en français |
| **r/AIAgentGovernance** (owned) | P3 devs | Decision logging, memory, context eng., multi-agent governance | Cross-posts only (seed 1x/mois). Primary venue post-Gate 2 (.gaai OSS). DEC-99 |

**Cadence :** 3-4 interactions substantielles/semaine. Max 1 nouveau post par subreddit par 2 semaines (spam radar). Les réponses sont illimitées et meilleur ROI.

**Règle non-négociable :** NE JAMAIS révéler le nom de la plateforme ou linker vers Callibrate avant le lancement. Le shift vers les mentions naturelles ("I built something for this") se fait uniquement APRÈS le lancement et uniquement dans les subs où le karma/trust est établi.

---

### Blog personnel

**Personas :** P3 (devs), P4 (industry), P1 (pour les case studies)
**Tone :** Analytique long-form. "Stratechery information density, Julia Evans accessibility" (E01S05 AC7). Technique pour la crédibilité, mais accessible. First-person, honnête sur les échecs et pivots.

**Plateforme recommandée :** **Substack** pour les 3 premiers mois (zéro setup, newsletter built-in, bon SEO, gratuit). Migration vers Hugo on CF Pages si traction justifie le contrôle total.

**Calendrier éditorial :**

| Post # | Timing | Titre / Angle | Audience |
|--------|--------|---------------|----------|
| 1 (flagship) | Gate 1 PASS | "I governed AI agents to build a SaaS solo — here's what 77 decisions taught me" | P3 + P4 |
| 2 | Gate 2 PASS | ".gaai is now open-source — here's how to structure your AI sessions" | P3 |
| 3 | Post-Phase 2 | "How I validated a marketplace in 19 subreddits without revealing the product" | P1 + P2 + P4 |
| 4 | Gate 3 PASS | "First 10 paid leads: what the data says about AI expert matching" | P1 + P2 |
| Mensuels | Ongoing | "Month X: [stories], [decisions], [revenue]. Here's what moved." | All |

**Règles :**
- Chaque post termine avec un hook teasant au moins 2 de : Callibrate, .gaai OSS, le builder's journey
- Canonical URL toujours sur le blog perso (pas dev.to, pas Medium)
- Pas de gating : article complet visible, pas d'email requis pour lire
- Section commentaires monitorée 72h post-publication

---

### dev.to

**Personas :** P3 (devs)
**Tone :** Identique au blog, légèrement plus tutorial-oriented.
**Format :** Cross-posts depuis le blog avec canonical URL → blog perso. Tags dev.to : #ai, #productivity, #devops, #opensource.
**Cadence :** 1x/mois (miroir du blog). Même jour que la publication blog.

---

### Hacker News

**Personas :** P3 (devs), P4 (industry)
**Tone :** Factuel, aucun hype. HN pénalise les superlatifs. Titre spécifique avec un détail concret.

**Bons titres HN :**
- "Show HN: I used 77 documented decisions to govern AI agents building a SaaS"
- "Show HN: .gaai — a governance framework for AI agent sessions (MIT)"
- PAS : "I built an amazing AI framework that changes everything"

**Cadence :** Maximum 3-4 Show HN total sur toute la timeline. Réserver pour les vrais milestones.
**Timing :** Tuesday or Wednesday, 10am-11am ET (pic trafic HN).

**Engagement rules :**
- Après submission, monitorer le thread en continu pendant 4-6h
- Répondre à CHAQUE commentaire, même critiques — HN récompense l'engagement
- Criticism = attendu. Répondre avec des données et de l'honnêteté, pas de la défensive.
- Si le post prend de la traction (top 30), clear the schedule pour la journée
- Ne jamais demander des upvotes. Ne jamais cross-poster "check out my HN post" sur d'autres canaux.

---

### LinkedIn (DIFFÉRÉ)

**Contrainte :** Risque employeur. Activation SIMULTANÉE avec le lancement produit (DEC-31).

**Préparation pré-lancement (zéro activité publique) :**
- Drafter 3 hand raiser posts (expert FR, expert EN, prospect FR) — déjà fait (E01S02, E01S03)
- Drafter le manifesto post (premier post LinkedIn ever = haute visibilité)
- Préparer le profil : headline, bio, banner (ready to flip the switch)

**Séquence jour de lancement :**
1. Mettre à jour le profil avec positionnement Callibrate
2. Publier le manifesto post (long-form, le "why" story)
3. Publier expert hand raiser post
4. Publier prospect hand raiser post
5. Engager chaque commentaire pendant 72h

---

### GitHub (DIFFÉRÉ — post Gate 2)

**Séquence de lancement .gaai OSS :**
1. Nettoyer .gaai des références Callibrate-spécifiques
2. Écrire README complet avec exemples réels
3. LICENSE MIT
4. Badge "Built with .gaai" → callibrate.io dans le README
5. Jour 1 : Push repo + blog #2 + Show HN
6. Jour 2 : r/ClaudeAI + r/LocalLLaMA
7. Jour 3 : X thread

---

## Part 3 — Personal Brand Guidelines

### Brand Personality

**Le founder EST :**
- Un builder qui montre le travail (screenshots, métriques, decision logs — pas du marketing poli)
- Analytique et méthodique (77+ décisions documentées = la preuve)
- Honnête sur les échecs (19 PRs non mergées, r/digitalnomad bot detection, pivots)
- Opinionated avec data backing (chaque claim forte référence une hypothèse validée ou une décision)
- Un praticien, pas un thought leader (build first, write about what worked)
- Accessible : explique des concepts complexes sans condescendance

**Le founder N'EST PAS :**
- Un guru ou influenceur (pas de face cam, pas de contenu "motivation", pas d'anecdotes perso non liées au travail)
- Un marketeur corporate (pas de buzzwords, pas de "synergy", pas de "revolutionize")
- Un hype machine (pas de "this changes everything", pas de "10x your productivity")
- Un perfectionniste en public (ship des choses imparfaites et itère visiblement)
- Agressif en acquisition (jamais de cold-DM, jamais de spam, jamais de demande de follows)

### Voice & Tone Rules

| Attribut | DO | DON'T |
|----------|-----|-------|
| Spécificité | "77 decisions, 39 stories, 260 passing tests" | "Lots of progress" |
| Honnêteté | "I accumulated 19 PRs and it cost me 2 hours of conflict resolution" | "We learn from every challenge" |
| Confiance | "This is what worked for me and the data behind it" | "I think maybe this could possibly work" |
| Humilité | "This is N=1. Your mileage may vary." | "Everyone should do this" |
| Profondeur technique | "Cache chain: Cache API L1 (60s TTL) → D1 edge SQL → Hyperdrive fallback" | "We use advanced caching" |
| Teasers | "The framework behind this will be open-source soon" | "HUGE ANNOUNCEMENT COMING" |
| CTA | "If this resonates, the code will be on GitHub next month" | "LIKE FOLLOW SUBSCRIBE" |

**Règles de langue :**
- Anglais pour tout le contenu public (reach international > niche FR)
- Exception : r/EntreprendreenFrance, LinkedIn FR hand raisers, communautés business FR
- Pas d'emojis dans le corps des threads. Max 1 emoji dans une ligne CTA. Aucun dans les blog posts.
- Chaque claim doit être traçable à un entry decision log, une validation hypothèse ou une métrique

**Mots/phrases interdits :**
- "Game-changer", "Revolutionary", "Disruptive", "10x", "Unlock"
- "I'm excited to announce" (just announce)
- "Thought leader" (let others say it)
- "LFG", "ship it", "let's gooo"
- "We" (solo founder — utiliser "I")
- "AI-powered" comme modificateur générique (spécifier ce que l'AI fait)

### Bio Templates

**X/Twitter (@Fr-e-d) :**
```
Building in public. AI agent governance + expert matching.
Callibrate: qualified matches, booked calls.
.gaai: how AI agents should be governed.
DMs open.
```

**dev.to :**
```
Solo founder building Callibrate (AI expert matching) and .gaai (AI agent governance framework).
Writing about what works and what doesn't in AI-assisted solo development.
```

**GitHub (Fr-e-d) :**
```
Building .gaai — governance for AI agents. And Callibrate — where AI experts meet qualified prospects.
77+ documented decisions. 39+ stories delivered by governed AI agents.
```

**Hacker News :**
```
Building callibrate.io (AI expert matching) and .gaai (agent governance framework). Solo founder, build in public.
```

**Blog/Substack :**
```
I build products with AI agents — and I built the governance framework that keeps them in line.

Callibrate is an AI-powered matching platform connecting businesses with vetted AI automation experts.
.gaai is the framework I use to govern the AI agents that build it.

This blog documents both: the product, the framework, and the decisions behind them.
No video. No hype. Just the work and the numbers.
```

**LinkedIn (prêt pour le jour de lancement) :**
```
Building Callibrate — the trusted intermediary that matches businesses with qualified AI automation experts.
Also building .gaai, an open-source governance framework for AI agents.
```

### Identité visuelle

- **Terminal screenshots :** dark theme, font monospace système, annotés avec 1 caption, infos sensibles redactées
- **Diagrammes architecture :** clean, minimal, noir/blanc ou 2-3 couleurs max, style ASCII art ou box diagrams
- **Métriques :** plain text ou table format, toujours avec date range, montrer le delta depuis le dernier report
- **X threads :** chaque tweet auto-suffisant (lisible sans le thread). Numérotés (1/7, 2/7...) si >4 tweets.
- **Reddit :** formatting natif Reddit. Pas d'images markdown (cassent). Text-only avec inline code blocks.
- **Blog :** headers, code blocks, pull quotes pour les data points clés. Mobile-first.

---

## Part 4 — Launch Orchestration Calendar

### Phase 1 : NOW → Gate 1 (J0-J21)

**Objectif :** Construire le momentum content à partir des artefacts de delivery. Établir la présence X. Continuer Reddit. Accumuler le matériel pour le flagship post.

| Semaine | Contenu | Canal | Persona | Tease |
|---------|---------|-------|---------|-------|
| W1 | "260 tests, 77 decisions, 39 stories. 5 days. Solo + AI agents." — thread d'ouverture | X | P3, P4 | .gaai existe; quelque chose se construit |
| W1 | Screenshot thread : un entry decision log réel (ex. DEC-41 Cal.com pivot) annoté | X | P3, P4 | Governance empêche le travail gaspillé |
| W1 | Continue engagement r/AiForSmallBusiness + r/aisolobusinesses (non-revealing) | Reddit | P1, P2 | Aucun (signal gathering) |
| W2 | "What happens when your AI coding agent has no memory?" — thread sur la perte de contexte | X | P3 | .gaai memory system |
| W2 | Weekly metrics post : chiffres semaine 1 | X | P3, P4 | Cadence build-in-public établie |
| W2 | Reddit : répondre aux threads r/ClaudeAI sur la structure agent | Reddit | P3 | Approche structurée existe |
| W3 | "AI agents are dangerous without guardrails" — thread riding OpenClaw crisis | X | P3, P4 | .gaai comme governance layer |
| W3 | Screenshot : backlog.yaml montrant 39 done stories en format structuré | X | P3 | Preuve que le dev AI structuré marche |
| W3 | Weekly metrics : cumul semaine 2 | X | P3, P4 | Trajectoire de croissance |

### Gate 1 Moment : Distribution du flagship post (E01S05)

**Prérequis :** Gate 1 PASS. E01S05 Discovery complété (angles, données, visuels, distribution).

**J0 (pré-publication) :**
- Proofread final + test "Would I share this?" avec 2-3 personnes de confiance
- Préparer tous les matériaux de distribution : X thread (7 tweets), Reddit post text, HN title
- Ne rien pré-programmer (authentic timing)

**J1 (Tuesday ou Wednesday, 10am ET) :**
- Publier sur blog perso (Substack ou Hugo)
- Cross-poster sur dev.to avec canonical URL → blog
- Soumettre sur Hacker News : titre factuel et spécifique
- Poster sur r/ClaudeAI avec intro 2-3 paragraphes + lien
- Poster sur r/artificial avec contexte adapté
- **Budget J1 : 2h publication + 3h monitoring commentaires = 5h (exception)**

**J2 :**
- X thread (5-7 tweets, Golden Circle, lien vers le full post)
- Engager chaque commentaire HN et Reddit
- **Budget J2 : 1h thread + 2h engagement = 3h**

**J3-J7 :**
- Follow-up engagement sur tous les canaux
- Si HN traction : thread follow-up "lessons learned" sur X
- **Budget J3+ : 30 min/jour**

**Total Gate 1 moment : ~12-15h sur une semaine. Exception unique — réduire le dev cette semaine.**

### Phase 2 : J21-J45 — Real Users

| Semaine | Contenu | Canal | Persona | Tease |
|---------|---------|-------|---------|-------|
| W4 | "First real expert onboarded" — thread documentant le flow (anonymisé) | X | P1, P3 | Callibrate est réel et utilisé |
| W4 | Reddit : post dans r/aisolobusinesses sur le problème matching (peut hint qu'on build quelque chose) | Reddit | P1 | Outreach contacts leads.md |
| W5 | "First match computed" — thread avec scoring breakdown anonymisé | X | P3, P4 | Matching engine sophistiqué |
| W5 | Weekly metrics : experts onboarded, prospects submitted, match scores | X | All | Vrais chiffres de traction |
| W6 | "Why I'll open-source my AI governance framework (soon)" — teaser thread | X | P3 | .gaai OSS arrive |
| W7 | First booking documenté (anonymisé) : "Expert X got a pre-qualified lead and a booked call" | X | P1 | Callibrate délivre de la valeur |

### Gate 2 Moment : Lancement .gaai OSS

**Prérequis :** Gate 2 PASS + framework stable 2+ semaines.

**J1 (Tue/Wed 10am ET) :**
- Push .gaai sur GitHub (public, MIT)
- Publier blog #2 + Show HN
- r/ClaudeAI + r/LocalLLaMA + r/artificial
- X thread

**J2-J7 :**
- Engager chaque GitHub issue, commentaire HN, commentaire Reddit
- **Total : ~10-12h sur une semaine**

### Phase 3 : J45-J90 — Revenue Content

| Semaine | Contenu | Canal | Persona | Tease |
|---------|---------|-------|---------|-------|
| W8-W9 | "Expert paid for their first lead" — anonymized transaction thread | X | P1, P3, P4 | Callibrate generates revenue |
| W10 | Revenue milestone : "$X GMV in Y weeks" | X | P4 | The system works end-to-end |
| W11 | ".gaai in production: X stories, Y decisions, Z tests later" — retro thread | X | P3 | .gaai est battle-tested |
| W12 | Full case study blog post : "From 0 to first revenue with AI agents" | Blog + HN + Reddit | All | Complete narrative arc |
| W13 | .gaai Cloud waitlist tease : "What if .gaai worked without the terminal?" | X | P3, P4 | .gaai Cloud vision |

---

## Part 5 — Comment Response Strategy

### Système 3-tier

**TIER 1 — RÉPONDRE IMMÉDIATEMENT (< 2h)**

Interactions haute valeur qui servent directement le funnel.

- Questions techniques sur .gaai ou l'architecture — futur utilisateur. Répondre avec des spécificités, référencer un DEC entry.
- "How can I try this?" — signal d'intérêt direct. Répondre avec timeline + offrir de notifier.
- Expert ou prospect qualifié — match ICP Callibrate. Engager, comprendre sa situation, noter dans `leads.md`.
- Commentateur influent — large following, nom connu dans la communauté AI, employé Anthropic/OpenAI. Engager de manière réfléchie.
- Critique genuine avec substance — quelqu'un qui pointe une vraie faiblesse. Répondre honnêtement. Ces réponses buildent plus de crédibilité que les éloges.

**TIER 2 — RÉPONDRE QUAND LE TEMPS PERMET (< 24h)**

Utile mais pas urgent.

- Fellow builder partageant son expérience — relate, partager un insight, build la connexion
- Intérêt général / "cool project" — remercier brièvement, linker vers quelque chose de spécifique
- Questions tangentielles ("which AI model do you use?") — réponse factuelle brève
- Comparaisons avec d'autres outils ("how is this different from Cursor/Devin?") — différenciation factuelle, jamais trash competitors

**TIER 3 — NE PAS RÉPONDRE**

- Trolls et arguments de mauvaise foi — le silence est la réponse. L'engagement nourrit les trolls.
- Commentaires hors-sujet
- Éloges génériques sans substance ("nice!" / fire emoji) — un like/upvote suffit
- Débats politiques/idéologiques sur l'AI — pas de fond, pas d'engagement
- Auto-promotion (quelqu'un qui utilise ton thread pour promouvoir son produit)

### Templates de réponse

**Template A — Question technique :**
```
Good question. [Réponse directe en 1-2 phrases].

In practice, [exemple spécifique du projet — référencer un DEC entry ou story].

[Si deep : "I wrote about this in more detail here: [link]"]
```

**Template B — Sceptique ("this seems overengineered / unnecessary") :**
```
Fair pushback. [Reconnaître le noyau valide de l'objection].

The difference I found was [avant/après spécifique avec un nombre concret].
For example, [DEC-41: Cal.com platform closed — the decision log caught it in 30 seconds
instead of discovering it in production].

[Never defensive. Facts, not arguments.]
```

**Template C — Prospect / expert intéressé :**
```
That matches exactly what I'm building.

[Description brève de l'état d'avancement — honnête sur le timeline].
If you want to be notified when [feature spécifique] is ready, [CTA: follow on X / drop email].

[Poser une question pour comprendre sa situation spécifique — c'est du signal gathering.]
```

**Template D — Fellow builder :**
```
[Reconnaître leur expérience spécifique — citer quelque chose qu'ils ont dit].

I hit something similar with [expérience liée du projet].
What worked for me was [approche spécifique + résultat].

[Échange genuine, pas du positionnement.]
```

### AI-Assisted Response Strategy

- **Drafter les réponses avec Claude :** coller le commentaire, demander une réponse factuelle dans la voix du founder. Relire 30 secondes, éditer pour le personal touch, poster. 5 min → 90 secondes.
- **Ne JAMAIS auto-poster.** Chaque réponse passe par des yeux humains. La voix du founder = le différentiateur.
- **AI-assisted triage :** au début de chaque session engagement, coller tous les commentaires non lus dans Claude et demander : "Classify each as Tier 1, Tier 2, or Tier 3. Draft responses for Tier 1 only." Divise le temps de triage par 2.

### Reddit-specific rules

- NE PAS s'auto-promouvoir avant Gate 1. Les communautés Reddit punissent la promotion prématurée avec une méfiance permanente.
- Après Gate 1 : le blog post est le véhicule de self-promotion — Reddit tolère bien "here's what I built + detailed writeup".
- Engager les commentaires minimum 72h après chaque post. L'algo Reddit récompense l'engagement précoce de qualité.
- Ne jamais poster le même contenu sur plusieurs subreddits simultanément. Stagger de 24h et adapter le framing.

---

## Part 6 — Content Pipeline & Automation

### Weekly Routine (time blocks exacts)

```
SAMEDI MATIN (1h)
  00:00-00:15  Review tous les drafts SKILL-CRS-021 générés cette semaine
  00:15-00:30  Sélectionner et éditer 2-3 threads pour la semaine suivante
  00:30-00:45  Drafter le weekly metrics post (chiffres du backlog + tests)
  00:45-01:00  Préparer screenshots/visuels nécessaires

DIMANCHE SOIR (15 min)
  Poster weekly metrics sur X

LUNDI MATIN (15 min)
  Poster Thread #1

MARDI SOIR (15 min)
  Reddit session : scan r/ClaudeAI, r/aisolobusinesses, r/AiForSmallBusiness
  Répondre aux threads pertinents. Checker les nouveaux leads.

MERCREDI MATIN (30 min)
  Poster Thread #2 + comment triage (AI-assisted Tier classification)

JEUDI SOIR (15 min)
  Reddit session : continuer engagement. Répondre aux commentaires sur ses propres posts.

VENDREDI MATIN (45 min)
  Thread #3 (optionnel, seulement si un draft fort est dispo)
  Engagement catch-up : répondre à tous les Tier 2 restants
  Logger les nouveaux leads/signaux dans contacts/leads.md

TOTAL : ~3h15 routine + 1h45 buffer = 5h
```

### Flux SKILL-CRS-021

```
Story livrée (QA PASS, PR mergée)
    │
    ▼
SKILL-CRS-021 auto-triggered (fin du cycle delivery)
    │
    ▼
Drafts générés dans contexts/artefacts/content/drafts/
    - {id}-thread.md  (X thread, 5-7 tweets, Golden Circle)
    - {id}-blog.md    (blog snippet, milestone stories only)
    - week-{N}-metrics.md (si dernière story de la semaine)
    │
    ▼
Founder batch review (samedi matin, 15 min)
    - Lire tous les drafts générés depuis le dernier review
    - Sélectionner 2-3 threads les plus forts pour la semaine
    - Éditer pour la voix personnelle (WHY/HOW/WHAT structuré → ajouter personnalité)
    - Discard les stories triviales (config changes, bug fixes)
    │
    ▼
Poster pendant la semaine (Lun/Mer/Ven, 10 min chaque)
    │
    ▼
Après publication : move de drafts/ à published/
```

### Outils

| Outil | Usage | Coût | Priorité |
|-------|-------|------|----------|
| X/Twitter (@Fr-e-d) | Canal contenu primaire | Gratuit ($20 promoted tweet Gate 1) | NOW |
| Substack | Blog platform flagship post | Gratuit | AVANT Gate 1 |
| dev.to | Cross-posting (canonical → blog) | Gratuit | AVANT Gate 1 |
| PostHog | Track blog + satellite traffic | Déjà provisionné (E07) | Fait |
| asciinema | Terminal recordings | Gratuit | Phase 2 |
| Google NotebookLM | Infographics pour blog posts | Gratuit | AVANT Gate 1 |

### Métriques qui comptent (vs vanité)

**Tracker chaque semaine :**

| Métrique | Pourquoi ça compte | Où checker |
|----------|---------------------|------------|
| X followers growth rate (pas le count absolu) | L'audience grandit-elle ? % week-over-week | X Analytics |
| Engagement rate par thread (replies + quotes / impressions) | Le contenu résonne-t-il ? | X Analytics |
| Blog post reads | Le long-form trouve-t-il une audience ? | Substack / PostHog |
| HN points + comment count | La communauté dev a-t-elle réagi ? | Hacker News |
| Reddit upvotes + qualité des commentaires | Les bonnes personnes engagent ? | Reddit |
| Leads ajoutés à leads.md | Le contenu drive-t-il des utilisateurs potentiels ? | Count manuel |
| GitHub stars .gaai (post Gate 2) | L'OSS gagne-t-il en traction ? | GitHub |
| Expert sign-ups sourced from content (post Phase 2) | Le contenu drive-t-il des conversions ? | PostHog (attribution) |

**Métriques vanité à ignorer :** follower count absolu, likes sans replies, impressions sans engagement, nombre de posts publiés.

### Escalation triggers

Le budget contenu reste à 5h/semaine SAUF si un trigger fire :

| Trigger | Action | Nouveau budget |
|---------|--------|----------------|
| Semaine Gate 1 (flagship post) | Clear the schedule. Engager chaque commentaire 72h. | 12-15h cette semaine |
| Semaine Gate 2 (OSS launch) | Idem Gate 1. | 10-12h cette semaine |
| Viral post (>500 HN points, >10K X impressions, >100 Reddit upvotes) | Voir Part 7. | 8-10h cette semaine |
| Inbound > 5 expert sign-ups/semaine from content | Content works — investir plus. +1 blog post/semaine. | 7h/semaine |
| Inbound from Anthropic/OpenAI (engagement d'un employé) | Traiter comme Tier 1. Réponses réfléchies et détaillées. | Pas de changement budget, mais prioriser |

---

## Part 7 — Risk Mitigation

### A — Post viral

**Plan de capacité :**
1. **< 1h :** Répondre à chaque commentaire Tier 1. Utiliser AI-assisted drafting.
2. **< 4h :** Clear the evening calendar. L'attention est la ressource la plus rare et le ROI le plus élevé.
3. **< 24h :** Poster un follow-up thread qui répond aux questions les plus communes. Plus efficace que de répondre individuellement.
4. **< 48h :** Si intérêt sign-up élevé, setup une simple waitlist (Substack subscribe ou Tally form — 10 min).
5. **NE PAS :** scramble to ship features faster (virality is temporary, broken code is permanent), changer le GTM timeline (les gates sont les gates), over-promise timelines.
6. **J5+ :** Écrire un thread rétrospectif ("what happened when my post hit #1 on HN"). Étend la queue d'engagement.

**Assets pré-préparés (prêts AVANT Gate 1) :**
- Un paragraphe "about me" pour quand les gens demandent
- Un paragraphe "what is Callibrate" pour quand les gens demandent
- Un paragraphe "what is .gaai" pour quand les gens demandent
- Une URL simple de capture email (Substack subscribe ou Tally form)

### B — Post qui flop

**C'est le cas attendu.** La plupart des posts underperforment.

1. Ne pas supprimer le post. Les posts floppés existent encore en search results.
2. Analyser pourquoi (5 min) : titre faible ? Mauvais timing ? Mauvais canal ? Mauvaise audience ?
3. **"3-at-bat" rule :** chaque idée importante reçoit au moins 3 tentatives (angle différent, canal différent, timing différent) avant de conclure que l'idée ne résonne pas.
4. Ne jamais arrêter de poster à cause d'un flop. La consistance est la seule stratégie qui compose. 1 thread/semaine minimum, indépendamment de la performance.

### C — Contrainte employeur

**Règles non-négociables :**
- LinkedIn OFF jusqu'au lancement produit (DEC-31). Pas d'exception.
- Aucune mention du nom d'employeur, entreprise ou industrie dans aucun contenu. Jamais.
- Pas de mention "side project" ou "while working full-time" — ça invite les questions.
- La persona publique est "solo founder building with AI agents." L'emploi est privé.
- Si un post devient viral et quelqu'un identifie l'employeur : ne pas engager. Ne pas confirmer. Ne pas nier. Silence.
- Bio X : mentionner "building Callibrate + .gaai" sans aucune référence emploi.

### D — Copycats

**L'obscurité est un risque plus grand que les copycats (DEC-77).**

Protections naturelles :
1. **First-mover narrative :** Git history timestampée. Decision log timestampé. Build-in-public content timestampé. Tout copycat est prouvablement second.
2. **Speed of iteration :** 39 stories en 5 jours. Un copycat part de zéro.
3. **Community moat :** L'audience suit le builder, pas le produit. Un copycat peut cloner le code mais pas la communauté.
4. **Data flywheel :** Une fois les données de matching réelles (Phase 2+), les composite scores et matching weights deviennent de l'intelligence propriétaire non réplicable.
5. **NE PAS :** retarder la publication pour "protéger" des idées, ajouter des barrières artificielles à .gaai OSS, obsess sur les concurrents au lieu des clients.
