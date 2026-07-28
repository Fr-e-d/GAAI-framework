#!/usr/bin/env bash
# Pre-push validator : backlog dependency integrity.
#
# Checks two things from base.rules.md § Backlog Archiving Rules that a machine
# can decide. Both were prose-only for a long time, and both had been violated in
# real backlogs for weeks without anything noticing — which is the argument for a
# hook at all: a rule nothing checks is a rule that silently rots.
#
#   ERROR — a dependency id that names a row in NO backlog file (active, blocked,
#           or any done/*.yaml). Genuinely dangling: a typo, or an item deleted
#           instead of archived. Nothing can ever resolve it.
#
#   ERROR — a duplicate id WITHIN active.backlog.yaml. Per-story tooling is
#           id-keyed and silently takes the first match, so a duplicate
#           desynchronises recorded status from actual delivery — it presents as
#           a story looping on retries when its work has already merged.
#
# Deliberately NOT flagged: a dependency resolving only through done/*.yaml. That
# is correct — the resolution set is the union of all backlog files, and the
# scheduler resolves it the same way. Warning on it would fire on every push of
# any mature backlog, and a warning that always fires is one nobody reads.
#
# Existence, not satisfaction: this hook answers "is the referenced row findable",
# never "is that dependency complete". Satisfaction is status-based and belongs to
# the scheduler; duplicating that logic here would be a second source of truth.
#
# Fails OPEN when python3 or PyYAML is unavailable. Core tooling does not assume
# PyYAML, and a governance nicety must never be the reason a push is refused on a
# machine whose backlog is fine.
#
# Cost : ~1s on a large backlog (PyYAML over every backlog file).
# Failure mode : push aborted, with each offending id named.

set -e

REPO_ROOT="$(git rev-parse --show-toplevel)"
BACKLOG="${GAAI_BACKLOG_PATH:-$REPO_ROOT/.gaai/project/contexts/backlog/active.backlog.yaml}"

[ -f "$BACKLOG" ] || exit 0
command -v python3 >/dev/null 2>&1 || exit 0
python3 -c "import yaml" >/dev/null 2>&1 || exit 0

python3 - "$BACKLOG" <<'PY'
import sys, glob, os, yaml

active_path = sys.argv[1]
backlog_dir = os.path.dirname(active_path)


def load(path):
    with open(path, encoding="utf-8") as fh:
        doc = yaml.safe_load(fh)
    if isinstance(doc, dict) and "items" in doc:
        return doc["items"] or []
    return doc or []


try:
    active = load(active_path)
except Exception as exc:
    print(f"⚠  pre-push: could not parse {os.path.basename(active_path)} "
          f"({exc.__class__.__name__}) — dependency check skipped.", file=sys.stderr)
    sys.exit(0)


def deps_of(item):
    """The scheduler accepts `dependencies:` and `depends_on:`, list or string."""
    out = []
    for key in ("dependencies", "depends_on"):
        raw = item.get(key)
        if raw is None:
            continue
        if isinstance(raw, str):
            raw = [p.strip() for p in raw.strip("[]").split(",")]
        if isinstance(raw, (list, tuple)):
            out.extend(d.strip() for d in raw if isinstance(d, str) and d.strip())
    return out


# Resolution set = every backlog file: active, blocked, and the archive.
resolvable = set()
sibling_files = [active_path]
blocked_path = os.path.join(backlog_dir, "blocked.backlog.yaml")
if os.path.isfile(blocked_path):
    sibling_files.append(blocked_path)
sibling_files.extend(sorted(glob.glob(os.path.join(backlog_dir, "done", "*.yaml"))))

for path in sibling_files:
    try:
        resolvable.update(
            i["id"] for i in load(path)
            if isinstance(i, dict) and isinstance(i.get("id"), str)
        )
    except Exception:
        continue

seen, duplicates = set(), set()
for item in active:
    if not isinstance(item, dict) or not isinstance(item.get("id"), str):
        continue
    if item["id"] in seen:
        duplicates.add(item["id"])
    seen.add(item["id"])

dangling = []
for item in active:
    if not isinstance(item, dict):
        continue
    for dep in deps_of(item):
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
    print("   The id names no row in active.backlog.yaml, blocked.backlog.yaml or", file=sys.stderr)
    print("   done/*.yaml: a typo, or an item deleted instead of archived.", file=sys.stderr)
    print("   Fix the id, or correct that item's dependency list in the backlog.", file=sys.stderr)

if duplicates or dangling:
    print("", file=sys.stderr)
    sys.exit(1)

sys.exit(0)
PY
