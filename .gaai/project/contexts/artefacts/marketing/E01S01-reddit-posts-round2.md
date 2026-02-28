---
type: artefact
artefact_type: marketing
id: E01S01-REDDIT-R2
track: discovery
related_backlog_id: E01S01
created_at: 2026-02-19
updated_at: 2026-02-19
---

# Reddit — Posts Round 2 (Hypothèses non confirmées)

> Objectif : valider H3, H4, H5, H12, H13 et le vocabulaire restant.
> Règle : un subreddit = un post. Pas de double post sur les subreddits déjà actifs.
> Subreddits utilisés : r/gohighlevel, r/Upwork, r/ClaudeAI, r/freelancing, r/buhaydigital, r/ArtificialNtelligence

---

## r/gohighlevel — H4 (critères d'admissibilité)
**Audience :** Agency owners GHL, consultants automation
**Hypothèse visée :** H4 — Les experts veulent contrôler leurs critères de sélection client

**Titre :**
```
What are your non-negotiables before taking on a new AI automation client?
```

**Body :**
```
Been thinking about this after getting burned a few times by clients who seemed promising
but weren't actually ready.

What are the 3 criteria you absolutely need to see before saying yes to a new project?

Mine are starting to look like: minimum budget, someone with actual decision-making power,
and a defined problem (not "we want to do AI stuff"). But curious what others use to filter.

What disqualifies a prospect for you immediately?
```

> Signal attendu : liste de critères spontanés → confirme H4 (experts veulent un filtre contrôlable). La phrase "disqualifies immediately" est volontaire — pousse les réponses vers des critères précis.

---

## r/freelancing — H5 (peur de payer sans ROI)
**Audience :** Freelancers généralistes et spécialisés
**Hypothèse visée :** H5 — La peur de payer pour des leads sans ROI est le principal frein

**Titre :**
```
Has anyone here actually paid for leads or a client acquisition service? Honest results?
```

**Body :**
```
Considering testing a few paid options for getting clients — lead gen services,
directories, paid platforms.

Before I spend anything: has anyone here actually tried paying for leads or
a subscription to get client introductions?

- What did you try?
- What was the ROI honestly?
- Would you do it again?

Not interested in the pitch, just real numbers if you have them.
```

> Signal attendu : "j'ai essayé X et ça n'a rien donné" → confirme H5. Ou au contraire "ça marche si le lead est bien qualifié" → nuance importante pour le modèle de pricing.

---

## r/Upwork — H12 (absence de concurrent direct)
**Audience :** Freelancers sur Upwork, dont AI/automation
**Hypothèse visée :** H12 — Aucune plateforme spécialisée AI automation + matching qualifié n'existe

**Titre :**
```
Is there a better platform than Upwork specifically for AI automation work?
```

**Body :**
```
Upwork works but it feels like the wrong tool for AI automation consulting specifically.

The issue: clients posting on Upwork for "AI automation" often don't really know what
they need, and the review system doesn't differentiate between a $200 Zapier job
and a $5k custom workflow build.

Has anyone found a platform or community that's better calibrated for this niche?
Something where the clients come in more qualified, or where your specific expertise
is actually searchable?

Or is Upwork still the default and everyone just deals with it?
```

> Signal attendu : si personne ne nomme une plateforme spécialisée → H12 ✅ confirmée. Si quelqu'un en nomme une → concurrent direct identifié, information critique.

---

## r/ClaudeAI — H13 (marché en croissance) + vocabulaire
**Audience :** Builders Claude, développeurs AI
**Hypothèses visées :** H13 + validation vocabulaire "automation specialist" vs "workflow architect"

**Titre :**
```
How would you describe what you do to a non-technical client in one sentence?
```

**Body :**
```
Genuine question for people building AI tools and automations for clients.

When a non-technical business owner asks what you do — not the tech stack,
just the value — what do you say?

I've been testing different framings:
- "I build AI automations"
- "I connect your tools with AI to save you time"
- "I'm a workflow architect"
- Something else entirely?

What actually lands with clients vs. what makes them glaze over?
```

> Signal attendu : quel vocabulaire les experts utilisent naturellement pour se vendre → valide ou invalide "workflow architect", "automation specialist", etc. Bonus : si beaucoup de réponses → confirme H13 (communauté active et en croissance).

---

## r/ArtificialNtelligence — H10 (rapidité) + H12
**Audience :** Communauté AI généraliste, mixte
**Hypothèses visées :** H10 + H12

**Titre :**
```
When you needed an AI consultant urgently — how long did finding the right one actually take?
```

**Body :**
```
Curious about the real timeline for finding an AI automation consultant when
you actually need one.

Not the ideal scenario — the real one. You have a project, you need someone,
you start searching.

- How long from "I need help" to "I found the right person"?
- What slowed you down the most?
- Was there a moment where you thought "there should be a better way to do this"?
```

> Signal attendu : "it took 2-3 weeks" → confirme que <48h serait un différenciateur fort (H10). "I wish there was..." → signal H12 direct sur l'absence de solution perçue.

---

## Observation Log — Round 2

| Subreddit | Post publié le | Score | Comments | Phrases clés | Hypothèse confirmée ? |
|---|---|---|---|---|---|
| **r/gohighlevel** | ✅ 19/02/2026 | **8** | **12** | "money upfront", "card on file / auto billing / credit position", "modular or nothing", **"found time" > "automation"**, platform lock-in awareness, architecture acceptance avant engagement | H4 ✅ critères sophistiqués : paiement + alignement méthodo + stack acceptée |
| r/freelancing | ✅ 19/02/2026 | 1 | 0 | — (aucun commentaire reçu) | ⬜ |
| **r/Upwork** | ✅ 19/02/2026 | 1 | **16** | "Upwork brings volume but not qualified AI buyers", **"vague postings"**, "niche communities or partnerships > marketplaces", "right clients couldn't find me" (SilkLoverX) | H12 ✅ aucune alternative nommée. H1 ✅ vague postings = leads non qualifiés |
| r/ClaudeAI | ✅ 19/02/2026 | 1 | 2 | Removed by moderator (insuffisamment lié à Claude/Anthropic) | ❌ removed |
| **r/ArtificialNtelligence** | ✅ 19/02/2026 | 1 | **3** | HotNeon : "No one needs an AI consultant", "speed to hire isn't top 5 considerations" | H10 ⚠️ enterprise perspective — ne s'applique pas aux PME/SMB |

---

### r/gohighlevel — Détail commentaires (API extraction 24/02/2026)

**Thread :** "What are your non-negotiables before taking on a new AI automation client?"

**heyiamnickk** (score: 4) — Expert response clé
- Non-négociable #1 : client doit accepter d'externaliser la logique hors GHL (n8n ou custom code)
- "If they can't handle that... it's a hard no"
- Protection réputation : "I know the system won't fail"
- **Signal H4 :** critères allant bien au-delà du budget — architecture et méthodologie
- Fred reply : question sur comment ce filtre apparaît avant le scoping call

**greekhop** (score: 3) — Prospect-side curiosity
- "What is it that n8n solves or does better?" → question genuine d'un GHL user

**Maxazillion1** (score: 2)
- "Money upfront" — baseline

**MachadoEsq** (score: 1)
- "Card on file. Auto billing enabled. Credit position."

### r/Upwork (v2) — Détail commentaires (API extraction 24/02/2026)

**Thread :** "Is there a better platform than Upwork specifically for AI automation work?"

**Own_Constant_2331** (score: 2)
- "Upwork is still the default and everyone just deals with it"
- Fred reply : "the calibration problem feels real — a $200 Zapier job and a $5k custom workflow build look identical"

**Rich-Emu-1561** (score: 2)
- "Upwork still brings volume but not always qualified AI buyers"
- "Most serious AI consulting leads come from niche communities or partnerships"

**SilkLoverX** (score: 1) × 2 commentaires
- "The problem wasn't only budget — the right clients couldn't find me"
- "The 'AI automation' label on Upwork means anything and everything"
- "I found more qualified clients in AI builder communities on Discord and Slack"

**hustler108** (score: 1)
- "How to build that custom $5K workflow?" — prospect-side curiosity

**Signal clé :** Aucun concurrent direct nommé. "Niche communities" confirmé comme canal alternatif — mais fragmenté et non scalable. Exactement le gap que Callibrate comble.
