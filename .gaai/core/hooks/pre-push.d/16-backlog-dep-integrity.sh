#!/usr/bin/env bash
# Pre-push validator : backlog dependency integrity.
#
# Enforces the two mechanically-checkable invariants in base.rules.md
# § Backlog Archiving Rules. Both were prose-only for a long time, and both had
# been violated in real backlogs for weeks at a time without anything noticing —
# which is the whole argument for a hook: a rule nothing checks is a rule that
# silently rots.
#
#   ERROR — a `dependencies` id that exists in NEITHER active.backlog.yaml NOR
#           done/*.yaml. Genuinely dangling: a typo, or an item deleted instead of
#           archived. Nothing can ever resolve it.
#
#   ERROR — a duplicate id WITHIN active.backlog.yaml. Per-story extractors are
#           id-keyed and silently take the first match, so a duplicate
#           desynchronises recorded status from actual delivery — the failure
#           presents as a story looping on retries when its work already merged.
#
# Deliberately NOT flagged: a dependency that resolves only through done/*.yaml.
# That is correct by base.rules.md — the resolution set is the union of the active
# backlog and the archive, and the scheduler resolves it the same way. Warning on
# it would fire on every push of any mature backlog, and a warning that always
# fires is a warning nobody reads.
#
# Also not flagged: an id present in both active and an archive file. A minimal
# traceability stub in the active backlog, with the full historical record left in
# the archive, is an explicitly permitted pattern.
#
# Cost : ~100ms (PyYAML over the active backlog plus done/*.yaml).
# Failure mode : push aborted, with each offending id named.

set -e

REPO_ROOT="$(git rev-parse --show-toplevel)"
BACKLOG="$REPO_ROOT/.gaai/project/contexts/backlog/active.backlog.yaml"

[ -f "$BACKLOG" ] || exit 0

python3 - "$REPO_ROOT" <<'PY'
import sys, glob, os, yaml

root = sys.argv[1]
backlog_dir = os.path.join(root, ".gaai/project/contexts/backlog")
active_path = os.path.join(backlog_dir, "active.backlog.yaml")


def load(path):
    with open(path, encoding="utf-8") as fh:
        doc = yaml.safe_load(fh)
    if isinstance(doc, dict) and "items" in doc:
        return doc["items"] or []
    return doc or []


try:
    active = load(active_path)
except Exception:
    # The YAML-parse validator owns parse errors and reports them properly.
    sys.exit(0)

active_ids = {i["id"] for i in active if isinstance(i, dict) and "id" in i}

archived_ids = set()
for path in sorted(glob.glob(os.path.join(backlog_dir, "done", "*.yaml"))):
    try:
        archived_ids.update(
            i["id"] for i in load(path) if isinstance(i, dict) and "id" in i
        )
    except Exception:
        continue

# base.rules.md: the resolution set is active ∪ done/*.yaml.
resolvable = active_ids | archived_ids

seen, duplicates = set(), set()
for item in active:
    if not isinstance(item, dict) or "id" not in item:
        continue
    if item["id"] in seen:
        duplicates.add(item["id"])
    seen.add(item["id"])

dangling = []
for item in active:
    if not isinstance(item, dict):
        continue
    for dep in item.get("dependencies") or []:
        if dep not in resolvable:
            dangling.append((item.get("id", "?"), dep))

if duplicates:
    print("", file=sys.stderr)
    print("❌ pre-push: duplicate ids in active.backlog.yaml — push aborted.", file=sys.stderr)
    for sid in sorted(duplicates):
        print(f"     {sid}", file=sys.stderr)
    print("   Per-story tooling is id-keyed and takes the first match, so a duplicate", file=sys.stderr)
    print("   desynchronises recorded status from actual delivery.", file=sys.stderr)
    print("   Fix: keep one row per id — remove the stale copy, not the live one.", file=sys.stderr)

if dangling:
    print("", file=sys.stderr)
    print("❌ pre-push: backlog dependencies that exist nowhere — push aborted.", file=sys.stderr)
    for sid, dep in dangling:
        print(f"     {sid} -> {dep}", file=sys.stderr)
    print("   The id is in neither active.backlog.yaml nor done/*.yaml: a typo, or an", file=sys.stderr)
    print("   item deleted instead of archived.", file=sys.stderr)
    print("   Fix the id, or replace the story's dependency set via the repair-deps action.", file=sys.stderr)

if duplicates or dangling:
    print("", file=sys.stderr)
    sys.exit(1)

sys.exit(0)
PY
