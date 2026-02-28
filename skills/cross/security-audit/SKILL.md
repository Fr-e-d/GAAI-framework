---
name: security-audit
description: Detect security vulnerabilities and governance violations across delivered code, configurations, and deployed environments. Activate after implementation or periodically as a governance check.
license: MIT
compatibility: Works with any filesystem-based AI coding agent
metadata:
  author: gaai-framework
  version: "1.0"
  category: cross
  track: cross-cutting
  id: SKILL-SECURITY-AUDIT-001
  updated_at: 2026-02-26
  status: experimental
inputs:
  - codebase
  - configuration_files
  - deployed_environment_metadata  (optional)
  - contexts/rules/**  (security rules)
outputs:
  - vulnerability_report
  - severity_scores
  - compliance_status
  - remediation_actions
---

# Security Audit

## Purpose / When to Activate

Activate:
- After implementation as a security gate
- Periodically on active projects
- When security rules are added or updated

Enforces security as a system rule, not a human task.

---

## Process

1. Scan code and configs for common vulnerability patterns
2. Detect secrets exposure and unsafe patterns
3. Validate authentication and authorization flows
4. Check compliance against project security rules
5. Produce severity-ranked vulnerability report with concrete remediation steps

---

## Outputs

- Vulnerability list with severity (critical / high / medium / low)
- Compliance pass/fail report per security rule
- Concrete remediation steps per vulnerability
- Audit trail for governance

---

## Quality Checks

- All findings include severity and remediation steps
- Compliance status is explicit per rule
- No false positives reported without evidence
- Output is actionable, not just informational

---

## Non-Goals

This skill must NOT:
- Fix vulnerabilities (use `remediate-failures` for that)
- Make architectural decisions
- Replace dedicated security tooling

**Prevents high-impact production failures. Security as governance, not afterthought.**
