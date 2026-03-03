---
type: skill
id: i18n-extract
name: i18n-extract
description: Scan codebase for hardcoded strings that should be internationalised, classify by domain and priority, and produce a structured extraction report for translation workflows.
layer: cross
category: analysis
created_at: 2026-03-02
updated_at: 2026-03-02
---

# Skill: i18n Extract (Hardcoded String Detection)

## Purpose

Scan a React/TypeScript codebase to identify all hardcoded user-facing strings (not yet i18n-ified) and organize them into a structured extraction report. Enables bulk translation workflow by creating the starting inventory of what needs translation.

> **Usage context:** One-time extraction when setting up i18n, or ongoing extraction to catch newly-added strings that bypass i18n framework.

---

## Input

```json
{
  "codebase_path": "workers/frontend/dashboard",
  "file_patterns": ["**/*.tsx", "**/*.ts"],          // glob patterns to scan
  "exclude_patterns": ["**/*.test.ts", "**/*.spec.tsx", "node_modules/**"],
  "extraction_rules": {
    "detect_strings_in": ["JSX text", "html labels", "placeholder attributes", "aria-labels", "button text"],
    "ignore_patterns": [
      "^[a-z0-9-]+$",                               // kebab-case = probably keys
      "^[A-Z0-9_]+$",                               // UPPER_CASE = probably constants
      "^(http|mailto|tel):",                        // URLs, emails, phone
      "^\\{.*\\}$"                                  // template vars
    ],
    "context_fields": ["component_name", "file_path", "line_number", "surrounding_code"]
  },
  "glossary_reference": "domains/i18n/glossary.md", // optional: flag if string matches known terms
  "output_format": "json"                           // or "yaml", "csv"
}
```

## Output

```json
{
  "extraction_summary": {
    "files_scanned": 45,
    "strings_found": 237,
    "strings_new": 156,
    "strings_already_i18n": 81,
    "potential_false_positives": 12
  },
  "strings": [
    {
      "id": "extract_001",
      "source_string": "Create Your Expert Profile",
      "file": "routes/onboarding.tsx",
      "line": 42,
      "component": "OnboardingStep1",
      "context_snippet": "return <h1>{title}</h1>",
      "confidence": "high",
      "domain": "onboarding",
      "priority": "critical",
      "glossary_match": null,
      "notes": "Title of first onboarding step"
    },
    {
      "id": "extract_002",
      "source_string": "Tell us about your background and expertise",
      "file": "routes/onboarding.tsx",
      "line": 48,
      "component": "OnboardingStep1",
      "context_snippet": "placeholder={description}",
      "confidence": "medium",
      "domain": "onboarding",
      "priority": "high",
      "glossary_match": "expertise",
      "notes": "Placeholder text, might be auto-generated from API"
    },
    {
      "id": "extract_003",
      "source_string": "© 2026 YourProject",
      "file": "components/Footer.tsx",
      "line": 15,
      "component": "Footer",
      "context_snippet": "© 2026 YourProject",
      "confidence": "low",
      "domain": "common",
      "priority": "low",
      "glossary_match": null,
      "notes": "Copyright notice, typically unchanged, but included for completeness"
    }
  ],
  "false_positives": [
    {
      "string": "expert_id",
      "file": "routes/dashboard.tsx",
      "reason": "Likely variable/constant name, not user-facing copy"
    }
  ],
  "statistics": {
    "by_domain": {
      "onboarding": 42,
      "billing": 28,
      "dashboard": 35,
      "errors": 18,
      "common": 33
    },
    "by_priority": {
      "critical": 45,
      "high": 78,
      "medium": 25,
      "low": 8
    },
    "by_confidence": {
      "high": 189,
      "medium": 31,
      "low": 17
    }
  },
  "next_steps": [
    "Review false_positives and remove if not user-facing",
    "Group strings by domain (onboarding.json, billing.json, etc.)",
    "Create i18n keys: domain.componentName.stringId (e.g., onboarding.step1.title)",
    "Extract to locales/en/{domain}.json",
    "Use idiomatique-translate skill to batch-translate to other languages"
  ]
}
```

---

## Detection Algorithm (Best Practices)

### 1. **Patterns to detect:**

```typescript
// JSX text nodes
<h1>Create Your Expert Profile</h1>                    ✅ detect

// String attributes
<input placeholder="Enter your name" />                 ✅ detect
<button aria-label="Close modal">X</button>            ✅ detect

// Template literals
const msg = `Welcome, ${user.name}`;                    ✅ detect (extract "Welcome, {name}")

// Object literals (common)
const labels = { save: "Save", cancel: "Cancel" };     ✅ detect values

// Already i18n-ified
<h1>{t('onboarding.step1.title')}</h1>               ❌ skip (already key)
const msg = t('errors.notFound');                      ❌ skip
```

### 2. **Ignore patterns (false positives):**

```
kebab-case identifiers (expert-id, user-name)
UPPER_CASE constants (MAX_LENGTH, ERROR_CODES)
URLs, emails, phone numbers (mailto:, http://, tel:)
Variable interpolations if already i18n-keyed
Comments (usually developer notes, not UX text)
Code blocks / regex patterns
Project-specific proper nouns (keep as-is)
```

### 3. **Context extraction:**

For each string, capture:
- **Line number** — quick location reference
- **Component name** — which React component
- **File path** — which file (for grouping by feature)
- **Surrounding code** — 1-2 lines of context (helps human review)
- **Domain tag** — onboarding, billing, errors, dashboard, common (for JSON structure)

### 4. **Confidence scoring:**

| Factor | Score |
|---|---|
| JSX text node | high (99% user-facing) |
| label/placeholder attribute | high |
| aria-label / title | high |
| Template literal with vars | medium (check context) |
| Object value (potentially config) | medium |
| Comment or code | low |
| Already has `t()` call | skip |

---

## Acceptance Criteria

- [ ] **AC1:** Script identifies 100+ hardcoded strings in dashboard codebase
- [ ] **AC2:** Confidence scoring applied (high/medium/low) with reasoning
- [ ] **AC3:** Domain tags assigned (onboarding, billing, errors, dashboard, common)
- [ ] **AC4:** False positives flagged separately (developer review before removal)
- [ ] **AC5:** Glossary cross-reference: if string contains a known glossary term (e.g., "lead", "milestone"), it's flagged in output
- [ ] **AC6:** Output includes: extracted string, file, line, component, context, confidence, domain, priority, glossary match
- [ ] **AC7:** Summary statistics (count by domain, priority, confidence)
- [ ] **AC8:** Next steps provided (group by domain, create i18n keys, extract to JSON)

---

## Output Structure for Delivery

Recommended file structure for extracted strings (ready for i18next):

```
domains/i18n/
├── extraction/
│   ├── all-strings.json              (complete list, all strings)
│   ├── by-domain/
│   │   ├── onboarding.json           (grouped by domain)
│   │   ├── billing.json
│   │   ├── errors.json
│   │   ├── dashboard.json
│   │   └── common.json
│   └── extraction-report.md          (human-readable summary + next steps)
└── glossary.md                       (canonical term reference)
```

---

## Known Constraints

- **False positives:** Some strings may be auto-generated (API responses, config values). Manual review recommended.
- **Pluralization:** Plural forms not auto-detected (e.g., "lead" vs "leads"). Flagged for glossary review.
- **Component context:** JSX components may be dynamically rendered — extraction includes all static text, even if conditionally shown.
- **Dynamic strings:** Strings created via template literals or string concat (e.g., `"Error: " + error.code`) are detected but may need manual grouping.
- **Non-English source:** Extraction assumes English source. If codebase has mixed languages, detection accuracy reduces.

---

## Post-Extraction Workflow

1. **Human review:** Scan false_positives, remove non-UX strings
2. **Group by domain:** Organize extracted strings into `locales/en/{domain}.json`
3. **Create i18n keys:** Convert strings to hierarchical keys (e.g., `onboarding.step1.title`)
4. **Batch translate:** Use `idiomatique-translate` skill to translate to other languages
5. **Validate:** Use `i18n-validate` skill to check completeness
6. **Commit:** Integrate into codebase, update components to use `t()` calls

---

## Notes for Delivery Agent

This skill produces the **starting inventory** for i18n. It is **not the refactoring** — Delivery still needs to:
1. Replace hardcoded strings with `t('key.name')` calls
2. Integrate JSON files into i18next config
3. Test language switching in browser

The output of this skill is input to E14S02 (Extract critical strings + idiomatique translate).
