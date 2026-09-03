#!/usr/bin/env bash
# Pre-push validator : backlog integrity — dependencies and row structure.
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
#   ERROR — the document is not a mapping carrying `items:`. The daemon's shell
#           helpers query the backlog with `yq '.items[] | ...'`; a bare
#           top-level sequence makes every one of them fail. PyYAML is happy
#           either way, so a checker written in Python will not notice — which
#           is exactly how this shipped: a repair script rebuilt the file from
#           its rows and silently dropped the `cutover_state:` / `items:`
#           header, and the recovery scan went blind for hours while reporting
#           that it had nothing to evaluate.
#
#   ERROR — a row whose `artefact` filename names a DIFFERENT row. Editing a
#           backlog by hand can displace a row's tail onto its neighbour: the
#           YAML stays valid, so nothing complains, while a row now carries
#           another story's artefact, dependencies and notes. A `refined` row in
#           that state dispatches the wrong story under its own id.
#
#   ERROR — a row with no `status`. The 3-phase dispatcher reads status on every
#           poll and dies on an absent one, leaving the entry stuck — and a row
#           only loses its status by being damaged, never by being written.
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
# Fails CLOSED. The parser is repository-controlled — the runtime ships with the
# Framework — so an unavailable parser is a real defect, not a machine-local
# nicety, and a backlog file that cannot be parsed is exactly the damage this
# hook exists to catch. Diagnostics name the offending backlog file and the
# offending ids only; no parser text and no document content is ever echoed.
#
# Cost : ~1s on a large backlog (the vendored parser over every backlog file).
# Failure mode : push aborted, with each offending id named.

set -e

REPO_ROOT="$(git rev-parse --show-toplevel)"
BACKLOG="${GAAI_BACKLOG_PATH:-$REPO_ROOT/.gaai/project/contexts/backlog/active.backlog.yaml}"

[ -f "$BACKLOG" ] || exit 0

# shellcheck source=../../scripts/lib/yaml-runtime.sh
if ! . "$REPO_ROOT/.gaai/core/scripts/lib/yaml-runtime.sh"; then
  echo "" >&2
  echo "❌ pre-push: the repository-controlled YAML runtime is unavailable — push aborted." >&2
  echo "   Verify it with: bash .gaai/core/scripts/lib/yaml-runtime.sh --verify-tuple" >&2
  echo "" >&2
  exit 1
fi
YAML_RUNTIME_ROLE=prepush_dep_integrity

yaml_runtime_run "$BACKLOG" <<'PY'
import sys, glob, os, re, yaml

active_path = sys.argv[1]
backlog_dir = os.path.dirname(active_path)

SAFE_NAME = re.compile(r"[A-Za-z0-9._-]{1,64}")


def named(path):
    """Only the backlog file this hook was asked to validate is ever named."""
    base = os.path.basename(path)
    return base if SAFE_NAME.fullmatch(base) else "-"


def unparsable(path):
    print("", file=sys.stderr)
    print(f"❌ pre-push: {named(path)} is not parsable YAML — push aborted.", file=sys.stderr)
    print("   A backlog file the daemon cannot read is the damage this hook exists to", file=sys.stderr)
    print("   catch, so it is refused rather than skipped. Validate it with:", file=sys.stderr)
    print("     bash .gaai/core/scripts/lib/yaml-runtime.sh --validate .gaai/project/contexts/backlog/active.backlog.yaml", file=sys.stderr)
    print("", file=sys.stderr)
    sys.exit(1)


class _StrictLoader(yaml.SafeLoader):
    """Reject a repeated mapping key instead of silently keeping the last one.

    This hook builds its resolvable-id set from every backlog file, including the
    archives -- and only `active.backlog.yaml` is duplicate-checked before a push.
    Under plain safe_load a repeated `id:` in a sibling file collapses two rows
    into one, so a dependency naming the dropped row resolves against nothing and
    this hook, whose whole purpose is to catch a dangling reference, passes it.
    The loader below is the same semantics every runtime consumer already applies.
    """

    @staticmethod
    def _no_duplicate_keys(loader, node, deep=False):
        mapping = {}
        for key_node, value_node in node.value:
            key = loader.construct_object(key_node, deep=deep)
            if key in mapping:
                raise ValueError("duplicate mapping key %r" % (key,))
            mapping[key] = loader.construct_object(value_node, deep=deep)
        return mapping


_StrictLoader.add_constructor(
    yaml.resolver.BaseResolver.DEFAULT_MAPPING_TAG, _StrictLoader._no_duplicate_keys
)


def load(path):
    try:
        with open(path, encoding="utf-8") as fh:
            doc = yaml.load(fh, Loader=_StrictLoader)
    except Exception:
        unparsable(path)
    if isinstance(doc, dict) and "items" in doc:
        return doc["items"] or []
    return doc or []


def top_level_shape(path):
    """The shape the daemon's yq queries require, not the shape the parser tolerates."""
    try:
        with open(path, encoding="utf-8") as fh:
            doc = yaml.load(fh, Loader=_StrictLoader)
    except Exception:
        unparsable(path)
    if not isinstance(doc, dict):
        return f"a top-level {type(doc).__name__}, not a mapping"
    if "items" not in doc:
        return "a mapping with no `items:` key"
    return None


active = load(active_path)


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
    # A blocked or archived backlog file that cannot be read is refused, not
    # skipped: an unreadable resolution set silently turns every dependency into
    # a false dangling reference or hides a real one.
    resolvable.update(
        i["id"] for i in load(path)
        if isinstance(i, dict) and isinstance(i.get("id"), str)
    )

# Structural damage from hand-editing. Both were real: a Discovery run once
# inserted rows and rotated the artefact-to-notes tail of thirteen rows across
# four epics, deleting the status block of six of them. Every check below held
# — valid YAML, resolvable dependencies, unique ids — and it went unnoticed for
# a day, until two `refined` rows were found pointing at another epic's stories.
ID_LIKE = re.compile(r"^E\d+(S\d+[a-z]?)?$")
BOUNDED_ID = re.compile(r"[A-Za-z][A-Za-z0-9._-]{0,63}")


def named_id(value):
    """Ids reach the diagnostic only after matching the bounded id shape."""
    return value if isinstance(value, str) and BOUNDED_ID.fullmatch(value) else "-"


mispointed, statusless = [], []
for item in active:
    if not isinstance(item, dict) or not isinstance(item.get("id"), str):
        continue
    art = item.get("artefact")
    if isinstance(art, str) and art.strip():
        stem = os.path.basename(art).split(".")[0]
        # Only compare when the filename is itself an id — plenty of artefacts are
        # legitimately named for a topic rather than a row.
        if ID_LIKE.match(stem) and stem != item["id"]:
            mispointed.append((item["id"], os.path.basename(art)))
    if item.get("status") in (None, ""):
        statusless.append(item["id"])

shape_problem = top_level_shape(active_path)
if shape_problem:
    print("", file=sys.stderr)
    print(f"❌ pre-push: {named(active_path)} is {shape_problem} — push aborted.",
          file=sys.stderr)
    print("   The daemon queries this file with `yq '.items[] | ...'`, which fails outright", file=sys.stderr)
    print("   on a bare sequence — every shell helper then returns empty, and the recovery", file=sys.stderr)
    print("   scan reports it has nothing to evaluate while stories sit stranded.", file=sys.stderr)
    print("   A YAML parser accepts both shapes, so this survives any parser-side check.", file=sys.stderr)
    print("   Fix: restore the `cutover_state:` block and the `items:` key above the rows.", file=sys.stderr)
    print("", file=sys.stderr)
    sys.exit(1)

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
        print(f"     {named_id(sid)}", file=sys.stderr)
    print("   Per-story tooling is id-keyed and takes the first match, so a duplicate", file=sys.stderr)
    print("   desynchronises recorded status from actual delivery.", file=sys.stderr)
    print("   Fix: keep one row per id — remove the stale copy, not the live one.", file=sys.stderr)

if dangling:
    print("", file=sys.stderr)
    print("❌ pre-push: backlog dependencies that exist nowhere — push aborted.", file=sys.stderr)
    for sid, dep in dangling:
        print(f"     {named_id(sid)} -> {named_id(dep)}", file=sys.stderr)
    print("   The id names no row in active.backlog.yaml, blocked.backlog.yaml or", file=sys.stderr)
    print("   done/*.yaml: a typo, or an item deleted instead of archived.", file=sys.stderr)
    print("   Fix the id, or correct that item's dependency list in the backlog.", file=sys.stderr)

if mispointed:
    print("", file=sys.stderr)
    print("❌ pre-push: rows whose artefact belongs to another row — push aborted.", file=sys.stderr)
    for sid, fn in mispointed:
        print(f"     {named_id(sid)} -> {named(fn)}", file=sys.stderr)
    print("   This is the signature of a displaced row tail: the artefact, and usually", file=sys.stderr)
    print("   the dependencies and notes with it, sit on the wrong row. A `refined` row", file=sys.stderr)
    print("   in this state delivers a different story under its own id.", file=sys.stderr)
    print("   Fix: give each row back its own tail — do not just rewrite the path.", file=sys.stderr)

if statusless:
    print("", file=sys.stderr)
    print("❌ pre-push: backlog rows with no status — push aborted.", file=sys.stderr)
    for sid in statusless:
        print(f"     {named_id(sid)}", file=sys.stderr)
    print("   The 3-phase dispatcher reads status on every poll and dies on an absent", file=sys.stderr)
    print("   one. A row does not lose its status by being written, only by being", file=sys.stderr)
    print("   damaged — so check what else that row lost before restoring the field.", file=sys.stderr)

if duplicates or dangling or mispointed or statusless:
    print("", file=sys.stderr)
    sys.exit(1)

sys.exit(0)
PY
