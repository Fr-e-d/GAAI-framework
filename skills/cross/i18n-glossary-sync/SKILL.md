---
type: skill
id: i18n-glossary-sync
name: i18n-glossary-sync
description: Maintain a canonical i18n glossary file — sync new terms across all language pairs, detect drift, flag missing translations, and enforce consistent terminology across the codebase.
layer: cross
category: analysis
created_at: 2026-03-02
updated_at: 2026-03-02
---

# Skill: i18n Glossary Sync (Term Consistency)

## Purpose

Ensure all domain-specific terms used in i18n translations are documented in the glossary and applied consistently across all languages. Prevents terminology drift and simplifies future language additions.

> **Usage context:** Post-extraction, post-translation, and ongoing (every release). Keeps glossary in sync with actual usage.

---

## Input

```json
{
  "locales_path": "locales/",
  "glossary_path": "domains/i18n/glossary.md",
  "languages": ["en", "fr", "de", "es"],
  "domain_terms": [
    "lead", "prospect", "expert", "milestone", "direct link",
    "spending limit", "flag", "qualification rate", "trust score"
  ],
  "analysis_mode": "comprehensive",  // or "quick" (just check coverage)
  "output_format": "json"
}
```

## Output

```json
{
  "glossary_summary": {
    "status": "NEEDS_UPDATE",         // UP_TO_DATE, NEEDS_UPDATE, CRITICAL_GAPS
    "glossary_terms": 28,
    "translations_found": 26,
    "missing_translations": 2,
    "inconsistent_usage": 5,
    "new_terms_discovered": 3,
    "deprecated_terms": 1,
    "last_updated": "2026-03-01"
  },
  "term_analysis": [
    {
      "term": "lead",
      "status": "INCONSISTENT",
      "glossary": {
        "en": "lead",
        "fr": "prospect",
        "de": "Lead",
        "es": "prospecto"
      },
      "actual_usage": {
        "en": {
          "usage_count": 12,
          "variants": ["lead", "leads"],
          "consistent": true
        },
        "fr": {
          "usage_count": 11,
          "variants": ["prospect", "prospects", "Leads"],  // ❌ "Leads" is variant
          "consistent": false,
          "inconsistent_instances": [
            {
              "key": "dashboard.leads.header",
              "text": "Mes Leads",
              "should_be": "Mes prospects",
              "file": "locales/fr/dashboard.json",
              "line": 15
            }
          ]
        },
        "de": {
          "usage_count": 8,
          "variants": ["Lead", "Leads"],
          "consistent": true
        },
        "es": {
          "usage_count": 9,
          "variants": ["prospecto", "prospectos"],
          "consistent": true
        }
      },
      "recommendations": [
        "Fix FR usage: change 'Leads' to 'prospect' in dashboard.leads.header",
        "Update glossary note: explain EN 'lead' vs FR 'prospect' distinction"
      ]
    },
    {
      "term": "milestone",
      "status": "COMPLETE",
      "glossary": {
        "en": "milestone",
        "fr": "jalon",
        "de": "Meilenstein",
        "es": "hito"
      },
      "actual_usage": {
        "en": { "usage_count": 24, "variants": ["milestone", "milestones"], "consistent": true },
        "fr": { "usage_count": 24, "variants": ["jalon", "jalons"], "consistent": true },
        "de": { "usage_count": 24, "variants": ["Meilenstein", "Meilensteine"], "consistent": true },
        "es": { "usage_count": 24, "variants": ["hito", "hitos"], "consistent": true }
      },
      "recommendations": []
    },
    {
      "term": "qualification_rate",
      "status": "MISSING_TRANSLATION",
      "glossary": {
        "en": "qualification rate",
        "fr": null,                   // ❌ missing
        "de": null,                   // ❌ missing
        "es": null                    // ❌ missing
      },
      "actual_usage": {
        "en": { "usage_count": 5, "variants": ["qualification rate", "qualification_rate"], "consistent": true },
        "fr": { "usage_count": 4, "variants": ["taux de qualification"], "consistent": true },
        "de": { "usage_count": 4, "variants": ["Qualifizierungsquote"], "consistent": true },
        "es": { "usage_count": 4, "variants": ["tasa de calificación"], "consistent": true }
      },
      "recommendations": [
        "Add FR translation to glossary: 'taux de qualification'",
        "Add DE translation to glossary: 'Qualifizierungsquote'",
        "Add ES translation to glossary: 'tasa de calificación'"
      ]
    }
  ],
  "discovered_terms": [
    {
      "term": "free mode",
      "languages": {
        "en": "free mode",
        "fr": "mode gratuit",
        "de": "kostenloser Modus",
        "es": "modo gratuito"
      },
      "usage_count": 3,
      "recommendation": "Add to glossary (new term in E12S16 direct link pricing)"
    },
    {
      "term": "spending limit",
      "languages": {
        "en": "spending limit",
        "fr": "limite de dépenses",
        "de": "Ausgabenlimit",
        "es": "límite de gasto"
      },
      "usage_count": 8,
      "recommendation": "Already in glossary, but verify ES variant ('límite de gasto' vs 'límite de gastos')"
    }
  ],
  "deprecated_terms": [
    {
      "term": "matchable",
      "glossary_status": "active",
      "usage_count": 0,
      "recommendation": "Remove from glossary — replaced by 'profil visible' (E12S13 milestone rename)"
    }
  ],
  "pluralization_analysis": {
    "status": "NEEDS_REVIEW",
    "note": "Plural forms detected but not formally managed. Consider i18next-plural extension for full support.",
    "examples": [
      {
        "term": "lead/leads",
        "en_variants": ["lead", "leads"],
        "fr_variants": ["prospect", "prospects"],
        "current_handling": "Both forms in translation strings (manual)",
        "recommended": "Use i18next pluralization plugin (lead_singular, lead_plural)"
      }
    ]
  },
  "statistics": {
    "glossary_coverage": "92.8%",     // terms in glossary / discovered terms
    "translation_coverage": {
      "fr": "100%",
      "de": "92.8%",
      "es": "96.4%"
    },
    "consistency_score": {
      "en": "100%",
      "fr": "88%",
      "de": "95%",
      "es": "98%"
    },
    "missing_glossary_entries": 2,
    "inconsistent_term_usage": 5,
    "deprecated_terms": 1
  },
  "glossary_update_proposal": {
    "add_terms": [
      {
        "term": "free mode",
        "translations": {
          "en": "free mode",
          "fr": "mode gratuit",
          "de": "kostenloser Modus",
          "es": "modo gratuito"
        },
        "context": "Direct link feature (E12S16) — when spending limit exceeded",
        "source": "auto-discovered from locales/*/dashboard.json"
      }
    ],
    "update_terms": [
      {
        "term": "qualification rate",
        "action": "add missing translations",
        "add": {
          "fr": "taux de qualification",
          "de": "Qualifizierungsquote",
          "es": "tasa de calificación"
        }
      }
    ],
    "remove_terms": [
      {
        "term": "matchable",
        "reason": "Replaced by 'profil visible' (milestone rename E12S13)",
        "deprecation_date": "2026-03-02"
      }
    ]
  },
  "recommendations": [
    "Update glossary with 'free mode' (new term from E12S16)",
    "Fix FR inconsistency: change 'Mes Leads' → 'Mes prospects' in dashboard.leads.header",
    "Complete glossary translations for 'qualification_rate' (FR, DE, ES already used, just not in glossary)",
    "Consider using i18next pluralization plugin for robust lead/leads handling",
    "Review ES variant: 'límite de gasto' vs 'límite de gastos' (use consistently)",
    "Remove deprecated term 'matchable' from glossary (replaced by 'profil visible')"
  ]
}
```

---

## Sync Principles (Industry Best Practices)

### 1. **Single Source of Truth for Terminology**

Glossary is the canonical reference. All translations should match glossary definitions.

```
glossary.md:
  "lead": { "en": "lead", "fr": "prospect", "de": "Lead" }

locales/fr/dashboard.json should use "prospect", not "Leads" or "client"
```

### 2. **Plural Forms Strategy**

Different languages handle pluralization differently. Options:

**Option A: Manual (current MVP approach)**
```json
{
  "leads.singular": "1 lead",
  "leads.plural": "{count} leads"
}
```

**Option B: i18next-plural (recommended post-MVP)**
```json
{
  "lead_one": "1 lead",
  "lead_other": "{count} leads"
}
```

Glossary should document chosen approach.

### 3. **Variant Tracking**

Some terms have multiple forms (singular/plural, capitalized/lowercase). Glossary should document ALL accepted variants.

```
Term: "lead"
Variants:
  - "lead" (singular)
  - "leads" (plural)
  - "Lead" (capitalized, rare)
Status: All variants acceptable if consistent per context
```

### 4. **Deprecation Lifecycle**

When renaming terms (e.g., milestone rename E12S13):

```
1. Add new term to glossary ("profil visible")
2. Mark old term as deprecated ("matchable")
3. Update all usage in translations (batch replace)
4. Keep deprecated entry for 1 release (document why)
5. Remove deprecated entry in next major version
```

---

## Acceptance Criteria

- [ ] **AC1:** Detects all domain terms used in translation files
- [ ] **AC2:** Cross-references against glossary (coverage ≥ 95%)
- [ ] **AC3:** Identifies inconsistent usage (same term, different translations)
- [ ] **AC4:** Flags missing glossary translations (e.g., FR exists in files but not in glossary)
- [ ] **AC5:** Discovers new terms and proposes glossary additions
- [ ] **AC6:** Identifies deprecated terms (in glossary but not used)
- [ ] **AC7:** Analyzes pluralization strategy (singular/plural variants)
- [ ] **AC8:** Provides consistency score per language (target: ≥ 95%)

---

## Glossary File Format

Canonical format (Markdown with YAML table):

```markdown
# {YourProject} i18n Glossary

## Domain Terms

| Term | EN | FR | DE | ES | Context | Notes | Variants |
|---|---|---|---|---|---|---|---|
| dashboard | dashboard | tableau de bord | Dashboard | panel | Navigation | Main overview screen | dashboard, dashboards |
| workspace | workspace | espace de travail | Arbeitsbereich | espacio de trabajo | Multi-tenant | Container for projects/users | workspace, workspaces |
| plan | plan | forfait | Tarif | plan | Billing | Subscription tier name | plan, plans |

## Deprecation Log

| Deprecated | Replaced By | Deprecation Date | Removal Date |
|---|---|---|---|
| matchable | profil visible | 2026-03-02 | 2026-06-02 |
```

---

## Integration with Translation Workflow

1. **Extract strings** → `i18n-extract` skill
2. **Batch translate** → `idiomatique-translate` skill (check glossary reference)
3. **Validate translations** → `i18n-validate` skill
4. **Sync glossary** → `i18n-glossary-sync` skill (this one)
5. **Commit** → All glossary updates included in PR

---

## Notes for Delivery Agent

This skill is **audit + proposal only**. Delivery Agent must:
1. Run this skill (generates report + proposals)
2. Review "glossary_update_proposal" section
3. Manually update `domains/i18n/glossary.md` (or use glossary editor UI post-MVP)
4. Re-run skill to verify sync is complete

Post-MVP: Consider UI editor for glossary management (no-code glossary updates).
