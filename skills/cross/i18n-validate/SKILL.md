---
type: skill
id: i18n-validate
name: i18n-validate
description: Validate translation completeness and consistency across all locale files — detect missing keys, untranslated strings, format mismatches, and glossary violations.
layer: cross
category: analysis
created_at: 2026-03-02
updated_at: 2026-03-02
---

# Skill: i18n Validate (Translation Completeness & Consistency)

## Purpose

Validate i18n JSON files for completeness, consistency, and quality across multiple languages. Catch missing translations, orphaned keys, placeholder mismatches, and length violations before deployment.

> **Usage context:** Post-translation (after idiomatique-translate), before committing to codebase. Also useful as CI/CD validation on every PR.

---

## Input

```json
{
  "locales_path": "locales/",
  "languages": ["en", "fr", "de", "es"],
  "reference_language": "en",          // master language (source of truth for keys)
  "validation_rules": {
    "check_missing_translations": true,
    "check_orphaned_keys": true,
    "check_placeholder_consistency": true,
    "check_length_budget": true,        // translations ≤ 120% of EN length
    "check_json_syntax": true,
    "check_glossary_alignment": true    // terms match glossary.md
  },
  "length_budget": {
    "en": "baseline",
    "fr": 1.2,                          // 120% of EN
    "de": 1.3,                          // German is typically longer
    "es": 1.15
  },
  "glossary_path": "domains/i18n/glossary.md",
  "ignore_keys": ["copyright", "version"],  // optional: keys to skip validation
  "output_format": "json"
}
```

## Output

```json
{
  "validation_summary": {
    "status": "FAIL",                   // PASS, FAIL, WARNINGS
    "total_keys": 342,
    "languages_checked": 4,
    "errors": 8,
    "warnings": 12,
    "timestamp": "2026-03-02T03:15:00Z"
  },
  "errors": [
    {
      "type": "missing_translation",
      "severity": "critical",
      "language": "fr",
      "key": "billing.directLink.perRequest",
      "message": "Translation missing in locales/fr/billing.json"
    },
    {
      "type": "orphaned_key",
      "severity": "high",
      "language": "en",
      "key": "onboarding.legacyField",
      "message": "Key exists in locales/en/onboarding.json but is not referenced in codebase (no t('onboarding.legacyField') found)"
    },
    {
      "type": "placeholder_mismatch",
      "severity": "high",
      "key": "errors.welcomeMessage",
      "en_placeholders": ["{userName}", "{date}"],
      "fr_placeholders": ["{userName}"],
      "message": "French translation missing {date} placeholder"
    },
    {
      "type": "length_violation",
      "severity": "medium",
      "key": "buttons.submitForm",
      "en_length": 10,
      "fr_length": 16,
      "budget": 12,
      "en_text": "Submit",
      "fr_text": "Soumettre le formulaire",
      "message": "French translation exceeds 120% length budget (16 > 12 chars)"
    },
    {
      "type": "glossary_mismatch",
      "severity": "warning",
      "key": "dashboard.leads.title",
      "en_text": "Leads",
      "glossary_term": "lead",
      "glossary_fr": "prospect",
      "found_fr": "Leads",
      "message": "Key contains term 'lead' but French translation uses 'Leads' instead of glossary term 'prospect'"
    },
    {
      "type": "json_syntax_error",
      "severity": "critical",
      "language": "de",
      "file": "locales/de/common.json",
      "line": 42,
      "message": "Invalid JSON: unexpected token at line 42 (missing comma)"
    }
  ],
  "warnings": [
    {
      "type": "empty_translation",
      "severity": "warning",
      "language": "es",
      "key": "analytics.description",
      "message": "Spanish translation is empty string (placeholder)"
    },
    {
      "type": "potential_untranslated",
      "severity": "info",
      "key": "footer.copyright",
      "en_text": "© 2026 YourProject",
      "fr_text": "© 2026 YourProject",
      "message": "Text identical to EN — may be intentional (proper noun) or missed translation"
    }
  ],
  "statistics": {
    "by_language": {
      "en": { "total_keys": 342, "complete": true },
      "fr": { "total_keys": 342, "translated": 334, "missing": 8, "completion": "97.7%" },
      "de": { "total_keys": 342, "translated": 340, "missing": 2, "completion": "99.4%" },
      "es": { "total_keys": 342, "translated": 336, "missing": 6, "completion": "98.2%" }
    },
    "by_severity": {
      "critical": 2,
      "high": 4,
      "medium": 3,
      "warning": 3,
      "info": 0
    },
    "completion_percentage": {
      "en": "100%",
      "fr": "97.7%",
      "de": "99.4%",
      "es": "98.2%"
    }
  },
  "recommendations": [
    "Complete 8 missing French translations (billing.directLink.perRequest, etc.)",
    "Remove orphaned key: onboarding.legacyField (not used in codebase)",
    "Fix placeholder mismatch in errors.welcomeMessage (FR missing {date})",
    "Shorten French translation of buttons.submitForm (16 > 12 chars budget)",
    "Verify glossary usage: dashboard.leads.title should use 'prospect' instead of 'Leads'",
    "Fix JSON syntax error in locales/de/common.json line 42"
  ],
  "next_steps": [
    "Address all CRITICAL errors before merging",
    "HIGH errors should be fixed before release",
    "MEDIUM warnings are UX issues (button text overflows on tight layouts)",
    "INFO messages are FYI (proper nouns, intentional repetition)"
  ]
}
```

---

## Validation Rules (Industry Standard)

### 1. **Missing Translations**

Every key in reference language (EN) must have a translation in all target languages.

```
en/common.json has "buttons.save"
├─ fr/common.json has "buttons.save" ✅
├─ de/common.json is MISSING "buttons.save" ❌
└─ es/common.json has "buttons.save" ✅

Result: ERROR (missing in de)
```

### 2. **Orphaned Keys**

Keys in i18n files but not referenced in codebase (no `t('key')` call).

```
locales/en/onboarding.json has "onboarding.legacyField"
Search codebase for t('onboarding.legacyField')
Result: NOT FOUND ❌

Result: ERROR (orphaned key, should be removed)
```

### 3. **Placeholder Consistency**

Template variables (e.g., `{userName}`, `{date}`) must appear in all translations.

```
en: "Welcome, {userName}! Your next call is {date}."
fr: "Bienvenue, {userName}! Votre prochain appel est {date}." ✅

en: "Welcome, {userName}! Your next call is {date}."
fr: "Bienvenue, {userName}!" ❌ (missing {date})

Result: ERROR (placeholder mismatch)
```

### 4. **Length Budget**

Translated text should not exceed language-specific length budgets (account for verbose languages).

```
en: "Submit" (6 chars)
Budget for FR: 6 × 1.2 = 7.2 chars
fr: "Soumettre" (9 chars) ❌ exceeds budget

Result: WARNING (UI may break on narrow screens)
```

### 5. **JSON Syntax**

All JSON files must be valid.

```json
❌ Missing comma:
{ "key": "value" "another": "value" }

✅ Valid:
{ "key": "value", "another": "value" }
```

### 6. **Glossary Alignment**

Translations should use terms defined in `domains/i18n/glossary.md`.

```
Glossary: "lead" → { "en": "lead", "fr": "prospect" }
Translation: "leads" → "Leads" ❌ should be "Prospects"

Result: WARNING (inconsistent terminology)
```

---

## Acceptance Criteria

- [ ] **AC1:** Detects all missing translations across languages
- [ ] **AC2:** Identifies orphaned keys (defined but not used in codebase)
- [ ] **AC3:** Flags placeholder mismatches (e.g., EN has `{date}`, FR doesn't)
- [ ] **AC4:** Checks length budgets per language (FR ≤ 120%, DE ≤ 130%, etc.)
- [ ] **AC5:** Validates JSON syntax in all locale files
- [ ] **AC6:** Cross-references glossary for term consistency
- [ ] **AC7:** Provides completion percentage per language
- [ ] **AC8:** Categorizes errors by severity (critical, high, medium, warning, info)
- [ ] **AC9:** Generates actionable recommendations

---

## Output for CI/CD Integration

For automated validation (e.g., GitHub Actions):

```json
{
  "status": "FAIL",
  "exit_code": 1,              // non-zero for CI/CD failure
  "error_count": 8,
  "critical_errors": 2,
  "warnings": 12,
  "report_url": "gs://bucket/reports/2026-03-02.json"
}
```

Exit code rules:
- `0` = PASS (all validations successful)
- `1` = FAIL (critical or high errors)
- `2` = WARNINGS (only medium/low issues)

---

## Integration with i18next

Best practice: Run this validation:
1. **Before merge:** Every PR that modifies locale files
2. **Before deploy:** Pre-release validation
3. **Post-build:** After bundle creation (verify all keys are present)

Example GitHub Actions workflow:

```yaml
- name: Validate i18n
  run: |
    # invokes i18n-validate skill
    # outputs report, exits with code 0/1/2
    # blocks merge if exit_code > 0 and critical errors
```

---

## Known Constraints

- **Dynamic keys:** Keys generated at runtime (e.g., `errors.${errorCode}`) cannot be detected statically
- **String concatenation:** Translations built from multiple keys (e.g., `t('errors.prefix') + t('errors.code')`) are harder to validate
- **Component context:** Same string used in different contexts (button vs heading) may need different translations — not detected
- **Pluralization:** Plural forms (e.g., "1 lead", "2 leads") require special handling (not in basic validation)

---

## Notes for Delivery Agent

This skill is **validation & reporting only**. It does NOT:
- Auto-fix errors
- Generate missing translations
- Remove orphaned keys
- Shorten long translations

Delivery Agent must:
1. Run this skill
2. Review errors + recommendations
3. Manually fix issues (add missing translations, remove orphaned keys, etc.)
4. Re-run validation until PASS

For bulk fixes (e.g., "translate all missing FR strings"), use `idiomatique-translate` skill.
