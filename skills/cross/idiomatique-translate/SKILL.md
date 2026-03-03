---
type: skill
id: idiomatique-translate
name: idiomatique-translate
description: Translate strings idiomatically across multiple target languages using a project glossary, preserving tone, domain terminology, and format placeholders while flagging untranslatable content.
layer: cross
category: content
created_at: 2026-03-02
updated_at: 2026-03-02
---

# Skill: Idiomatique Translate (Multi-Language)

## Purpose

Translate copy from any source language to any target language with idiomatic fluency, cultural awareness, domain expertise, and consistent voice — language-agnostic pattern optimized for B2B SaaS platforms.

> **Usage context:** Bulk translation of UI copy, help text, error messages, and onboarding content. Automatically detects source language. Replaces mechanical translation with culturally-aware, tonally-consistent output in the target language.

---

## Input

```json
{
  "source_string": "You pay $0.50 per direct link request",
  "source_language": null,                    // null = auto-detect, or explicit: "en", "fr", "de", "es"
  "target_language": "fr",                    // required: "en", "fr", "de", "es", "it", "pt", "nl", etc.
  "context": {
    "domain": "billing",                       // domain expertise context
    "component": "PricingCard",
    "tone": "transparent",                     // transparent, benevolent, precise, casual, formal, technical
    "audience": "expert",                      // expert, prospect, admin, user
    "key": "billing.directLink.perRequest"
  },
  "glossary": {
    "direct link": "lien direct",              // source term : target term (or multi-lang)
    "request": "demande",
    "lead": "prospect",
    "milestone": "jalon"
    // Can also use language-keyed format:
    // "direct link": { "fr": "lien direct", "de": "direkter Link", "es": "enlace directo" }
  },
  "regional_preferences": {
    "currency": "EUR",                         // override default currency ($→€, etc.)
    "date_format": "DD/MM/YYYY",
    "number_format": "de_DE"                   // locale code for number formatting
  },
  "notes": "Avoid formal 'vous' / use informal 'tu', clarify that €0.50 is machine cost not per-lead"
}
```

## Output

```json
{
  "translated_string": "Tu paies 0,50 € par demande traitée",
  "source_language_detected": "en",
  "target_language": "fr",
  "confidence": "high",                         // high, medium, low
  "idiomaticity_score": 4.5,                    // 1-5 scale (5 = native speaker fluency)
  "notes": "Changed 'requête' to 'demande' (more natural in billing context). Used '€' instead of '$' for FR audience. Used informal 'tu' per context. Tone: factual, reassuring.",
  "alternatives": [
    {
      "text": "Tu paies 0,50 € par traitement de demande",
      "note": "More formal variant"
    },
    {
      "text": "Chaque demande te coûte 0,50 €",
      "note": "More casual variant"
    }
  ],
  "cultural_notes": "French audience expects € currency and informal 'tu' in UX context. 'Demande' is more natural than 'requête' in billing."
}
```

---

## Translation Principles (Universal)

### 1. **Idiomatic > Literal**
- ❌ "You pay $0.50 per request" → literal French: "Vous payez 0,50 $ par requête"
- ✅ "You pay $0.50 per request" → idiomatic French: "Vous payez 0,50 € par demande"

(Reasoning: FR audience expects €, not $. "Demande" is more natural than "requête" in billing context.)

**For any language pair:** Prioritize cultural norms, expected terminology, and natural phrasing over word-for-word mapping.

### 2. **Domain-Aware Glossary Alignment**

Glossary can be:
- **Flat (single language pair):** `{ "source": "target" }`
- **Multi-language keyed:** `{ "term": { "en": "...", "fr": "...", "de": "..." } }`

Example (project domain):

| EN | FR | DE | ES |
|---|---|---|---|
| **Lead** | prospect | Lead / Interessent | prospecto |
| **Direct link** | lien direct | direkter Link | enlace directo |
| **Milestone** | jalon | Meilenstein | hito |
| **Expertise** | domaine de compétence | Fachgebiet | área de expertise |
| **Spending limit** | limite de dépenses | Ausgabenlimit | límite de gasto |

**Skill behavior:** Always check glossary first. If term exists in target language, use it. If not, translate idiomatically and flag for glossary update.

### 3. **Universal Tone & Voice Principles**

Define voice once, apply across all languages:

| Attribute | Principle | EN Example | FR Example | DE Example |
|---|---|---|---|---|
| **Transparent** | Explain the WHY | "You pay for qualified leads" | "Vous payez pour les prospects qualifiés" | "Sie zahlen für qualifizierte Leads" |
| **Benevolent** | Avoid blame | "Honest experts get better leads" | "Les experts honnêtes reçoivent de meilleurs prospects" | "Ehrliche Experten erhalten bessere Leads" |
| **Precise** | Avoid vague terms | "50 free requests" | "50 demandes gratuites" | "50 kostenlose Anfragen" |
| **Multi-lang ready** | Avoid untranslatable idioms | Prefer universal phrasing | Structure that works across languages | Cultural idioms verified in target lang |

### 4. **Context-Aware Adaptation**

These apply to ANY language pair:
- **Audience:** Expert (formal) vs Prospect (friendly) → affects formality level
- **Urgency:** Error message (concise) vs Help text (detailed) → affects length
- **Domain:** Billing (precise) vs Onboarding (encouraging) → affects tone
- **Length:** Button text has tight constraints → abbreviation strategies per language
- **Regional preferences:** Currency, date format, number separators (e.g., $, €, CHF; DD/MM/YYYY vs MM/DD/YYYY; 1.000,50 vs 1,000.50)

---

## Acceptance Criteria for Translation Quality (Universal)

- [ ] **AC1:** No word-for-word translation (idiomatic fluency required in target language)
- [ ] **AC2:** Glossary consistency — if term exists, use it; if not, flag for addition
- [ ] **AC3:** Tone matches voice definition (transparent, benevolent, precise) across language
- [ ] **AC4:** No untranslatable idioms (if source uses culturally-specific metaphor, adapt to target culture)
- [ ] **AC5:** Character length ≤ 120% of original (avoid unnecessary bloat on buttons/short fields)
- [ ] **AC6:** Regional preferences respected (currency, date format, number formatting)
- [ ] **AC7:** If uncertainty, provide 2-3 alternatives + rationale for each
- [ ] **AC8:** Cultural notes provided (e.g., "German audience expects formal 'Sie' in B2B context")

---

## Output Format

Always return:
1. **translated_string** — the translated text in target language
2. **source_language_detected** — auto-detected or confirmed source language (ISO 639-1: en, fr, de, es, etc.)
3. **target_language** — target language (as requested)
4. **confidence** — "high", "medium", "low" (based on ambiguity or cultural nuance)
5. **idiomaticity_score** — 1-5 scale (5 = native speaker fluency, 1 = mechanical)
6. **notes** — why this translation was chosen (reasoning, cultural decisions, tone adjustments)
7. **alternatives** — 2-3 alternative translations with rationale for each
8. **cultural_notes** — any culture-specific context or expectations in target language region

---

## Batch Workflow (Recommended)

Translate in batches (language pair agnostic):

```
Input: Array of {
  source_string,
  source_language: null or "en"/"fr"/"de"/etc.,
  target_language: "fr" or "de" or "es"/etc.,
  context,
  glossary
}

Process:
1. Auto-detect source language (if not provided)
2. Translate each string to target language
3. Apply domain glossary, tone, regional preferences
4. Provide alternatives + confidence scores

Output: JSON array {
  key,
  source_language_detected,
  target_language,
  translated_string,
  confidence,
  idiomaticity_score,
  notes,
  alternatives,
  cultural_notes
}

Review: Human expert reads all "medium/low" confidence items + "idiomaticity_score" < 4.0
Finalize: Choose final translation or iterate with skill
```

**Velocity:** ~50-80 strings per batch per language pair (1-2 hours with review).
**Scaling:** Batch translate to DE, ES, IT simultaneously (parallel skill invocations).

---

## Known Constraints

- **Terminology drift:** New terms must update glossary immediately (reuse across all language pairs)
  - Example: "qualification_rate" → glossary should map: `{ "qualification_rate": { "en": "qualification rate", "fr": "taux de qualification", "de": "Qualifizierungsquote" } }`
- **Context dependency:** Same source phrase can translate differently in billing vs error context — always provide context
- **Humor/idioms:** Culture-specific wordplay is hard to translate idiomatically — flag for manual review or rephrase
- **Regional variants:** Same language can have regional differences (e.g., European Spanish vs Latin American Spanish, European Portuguese vs Brazilian Portuguese)
- **Names/proper nouns:** Keep unchanged (your project name, n8n, Zapier, OpenAI, etc.)
- **Currency/date/number:** Use regional preferences to adapt formatting

---

## Language Coverage & Auto-Detection

**Supported languages (confidence > 95%):**
- EN (English), FR (Français), DE (Deutsch), ES (Español), IT (Italiano), PT (Português), NL (Nederlands)
- Extensible to others (JA, ZH, etc.) with similar workflow

**Auto-detection:** Claude's native language detection used if `source_language` is null. Explicit source language preferred if known.

---

## Notes for Delivery Agent

This skill is **discovery-phase only** (creates translated content artefacts). The Delivery Agent will:

1. **Extract strings** from codebase → JSON with `source_language`, `target_language`, `context`
2. **Batch translate** to one or more target languages (parallel invocations OK)
3. **Use skill** to generate translations with glossary + tone
4. **Review output** — all "medium/low" confidence + idiomaticity_score < 4.0
5. **Iterate** with skill if needed (provide feedback, alternative examples)
6. **Integrate** into i18n JSON files (structure: `locales/{lang}/*.json`)
7. **Commit** to version control
8. **Update glossary** with any new terms discovered during translation

**Post-MVP automation:** CI/CD pipeline can auto-translate new strings → PR (human review required for merge). This skill can handle the automation.

**Multi-language parallelization:** Extract strings once, translate to FR, DE, ES simultaneously (3 parallel skill invocations = faster than sequential).
