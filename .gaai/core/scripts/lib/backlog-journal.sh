#!/usr/bin/env bash
# Policy-bound, provider-neutral delivery lifecycle journal.
#
# Sourcing this library has no filesystem side effect. A caller may mutate its
# working-copy backlog only when backlog_journal_emit returns 0 with outcome
# "emitted". Replay and every ambiguous state are deliberately non-authorizing.

BACKLOG_JOURNAL_OUTCOME=""
BACKLOG_JOURNAL_REASON=""
BACKLOG_JOURNAL_RECORD_PATH=""
BACKLOG_JOURNAL_RECORD_DIGEST=""
BACKLOG_JOURNAL_SEQUENCE=""
BACKLOG_JOURNAL_RUN_TOKEN=""

_backlog_journal_safe_story() {
  [[ "${1:-}" =~ ^[A-Za-z][A-Za-z0-9._-]{0,63}$ ]] && printf '%s' "$1" || printf '-'
}

_backlog_journal_safe_field() {
  case "${1:-}" in
    status|phase_status|started_at|completed_at|blocked_reason|pr_url|pr_number|pr_status|cost_usd)
      printf '%s' "$1"
      ;;
    *) printf '-' ;;
  esac
}

_backlog_journal_safe_writer() {
  local value="${1:-}"
  if (( ${#value} <= 64 )) && [[ "$value" =~ ^[a-z][a-z0-9]*([._-][a-z0-9]+){0,7}$ ]]; then
    printf '%s' "$value"
  else
    printf '-'
  fi
}

_backlog_journal_shell_diagnostic() {
  local story_id="${1:-}" field="${2:-}" writer="${3:-}" reason="${4:-policy_invalid}"
  printf '[BACKLOG-JOURNAL] story=%s field=%s writer=%s seq=0 source=- record=- attempt=rejected outcome=rejected reason=%s\n' \
    "$(_backlog_journal_safe_story "$story_id")" \
    "$(_backlog_journal_safe_field "$field")" \
    "$(_backlog_journal_safe_writer "$writer")" \
    "$reason" >&2
}

# Mint and durably register a 256-bit token for one normalized writer context.
# Usage: backlog_journal_begin_run <backlog-file> <writer-context>
backlog_journal_begin_run() {
  local backlog_file="${1:-}" writer_context="${2:-}"
  local result rc

  BACKLOG_JOURNAL_OUTCOME=""
  BACKLOG_JOURNAL_REASON=""
  BACKLOG_JOURNAL_RUN_TOKEN=""

  if ! command -v python3 >/dev/null 2>&1; then
    BACKLOG_JOURNAL_OUTCOME="rejected"
    BACKLOG_JOURNAL_REASON="runtime_missing:python3"
    _backlog_journal_shell_diagnostic "-" "-" "$writer_context" "$BACKLOG_JOURNAL_REASON"
    return 1
  fi

  if result=$(python3 - "$backlog_file" "$writer_context" <<'PY'
import datetime
import hashlib
import json
import os
import re
import secrets
import sys


WRITER_RE = re.compile(r"^[a-z][a-z0-9]*(?:[._-][a-z0-9]+){0,7}$")


def canonical_json(value):
    return json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False)


def fail(reason):
    print(f"rejected\t{reason}\t-")
    raise SystemExit(1)


backlog_file, writer = sys.argv[1:3]
if not WRITER_RE.fullmatch(writer or "") or len(writer.encode("ascii", "ignore")) > 64:
    fail("writer_context_invalid")
if not backlog_file:
    fail("backlog_missing")

backlog_abs = os.path.realpath(backlog_file)
backlog_dir = os.path.dirname(backlog_abs)
journal_root = os.path.realpath(os.environ.get(
    "GAAI_BACKLOG_JOURNAL_DIR",
    os.path.join(backlog_dir, ".delivery-locks", "journal"),
))
registrations = os.path.join(journal_root, "registrations")
try:
    os.makedirs(registrations, mode=0o700, exist_ok=True)
    if os.stat(registrations).st_mode & 0o077:
        fail("journal_storage_permissions")
except OSError:
    fail("journal_storage_unavailable")

while True:
    token = secrets.token_hex(32)
    registration = {
        "schema_version": "1.0.0",
        "run_token": token,
        "writer_context": writer,
        "issued_at": datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
    }
    digest = hashlib.sha256(canonical_json(registration).encode("utf-8")).hexdigest()
    wrapper = {"registration": registration, "digest": digest}
    payload = (canonical_json(wrapper) + "\n").encode("utf-8")
    final_path = os.path.join(registrations, f"{token}.json")
    temp_path = os.path.join(registrations, f".{token}.{os.getpid()}.tmp")
    try:
        fd = os.open(temp_path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
        try:
            view = memoryview(payload)
            while view:
                written = os.write(fd, view)
                if written <= 0:
                    raise OSError("short write")
                view = view[written:]
            os.fsync(fd)
        finally:
            os.close(fd)
        os.link(temp_path, final_path)
        os.unlink(temp_path)
        dir_fd = os.open(registrations, os.O_RDONLY)
        try:
            os.fsync(dir_fd)
        finally:
            os.close(dir_fd)
        print(f"minted\tnone\t{token}")
        break
    except FileExistsError:
        try:
            os.unlink(temp_path)
        except OSError:
            pass
        continue
    except PermissionError:
        fail("journal_storage_permissions")
    except OSError:
        fail("append_interrupted")
PY
  ); then
    rc=0
  else
    rc=$?
  fi

  IFS=$'\t' read -r BACKLOG_JOURNAL_OUTCOME BACKLOG_JOURNAL_REASON BACKLOG_JOURNAL_RUN_TOKEN <<< "$result"
  if [[ $rc -ne 0 || "$BACKLOG_JOURNAL_OUTCOME" != "minted" || \
        ! "$BACKLOG_JOURNAL_RUN_TOKEN" =~ ^[0-9a-f]{64}$ ]]; then
    BACKLOG_JOURNAL_OUTCOME="${BACKLOG_JOURNAL_OUTCOME:-rejected}"
    BACKLOG_JOURNAL_REASON="${BACKLOG_JOURNAL_REASON:-policy_invalid}"
    BACKLOG_JOURNAL_RUN_TOKEN=""
    _backlog_journal_shell_diagnostic "-" "-" "$writer_context" "$BACKLOG_JOURNAL_REASON"
    return 1
  fi
  return 0
}

# Emit exactly one durable record. Return values:
#   0  emitted (the sole mutation-authorizing outcome)
#   10 pending replay (record locator returned, backlog mutation forbidden)
#   1  all other closed rejections/pending evidence
backlog_journal_emit() {
  local backlog_file="${1:-}" story_id="${2:-}" field="${3:-}" new_value="${4:-}"
  local writer_context="${5:-${GAAI_BACKLOG_JOURNAL_WRITER_CONTEXT:-backlog-scheduler.journal-set}}"
  local run_token="${6:-${GAAI_BACKLOG_JOURNAL_RUN_TOKEN:-}}"
  local result rc

  BACKLOG_JOURNAL_OUTCOME=""
  BACKLOG_JOURNAL_REASON=""
  BACKLOG_JOURNAL_RECORD_PATH=""
  BACKLOG_JOURNAL_RECORD_DIGEST=""
  BACKLOG_JOURNAL_SEQUENCE=""

  if ! command -v python3 >/dev/null 2>&1; then
    BACKLOG_JOURNAL_OUTCOME="rejected"
    BACKLOG_JOURNAL_REASON="runtime_missing:python3"
    _backlog_journal_shell_diagnostic "$story_id" "$field" "$writer_context" "$BACKLOG_JOURNAL_REASON"
    return 1
  fi

  if result=$(python3 - "$backlog_file" "$story_id" "$field" "$new_value" \
      "$writer_context" "$run_token" <<'PY'
import datetime
import decimal
import errno
import fcntl
import glob
import hashlib
import json
import os
import re
import stat
import subprocess
import sys


class JournalError(Exception):
    def __init__(self, reason, sequence=0, source_digest="", record_digest="", attempt="rejected"):
        super().__init__(reason)
        self.reason = reason
        self.sequence = sequence
        self.source_digest = source_digest
        self.record_digest = record_digest
        self.attempt = attempt


ALLOWED_FIELDS = {
    "status", "phase_status", "started_at", "completed_at", "blocked_reason",
    "pr_url", "pr_number", "pr_status", "cost_usd",
}
STATUS_VALUES = {
    "draft", "refined", "in_progress", "done", "failed", "blocked",
    "cancelled", "superseded", "escalated", "deferred",
}
STATUS_EDGES = {
    "draft": {"refined", "cancelled", "superseded"},
    "refined": {"in_progress", "blocked", "cancelled", "superseded"},
    "in_progress": {"done", "failed", "blocked", "escalated", "cancelled", "superseded"},
    "failed": {"blocked", "cancelled", "superseded"},
    "escalated": {"blocked", "cancelled", "superseded"},
    "blocked": {"draft", "refined", "in_progress", "done", "cancelled", "superseded"},
    "done": {"cancelled", "superseded"},
    "deferred": {"cancelled", "superseded"},
    "cancelled": set(),
    "superseded": set(),
}
PHASE_VALUES = {
    "not_started", "planned", "implemented", "qa_passed", "qa_failed",
    "qa_escalated", "commit_stalled", "done", "failed", "escalated",
}
PHASE_EDGES = {
    "not_started": {"planned", "failed"},
    "planned": {"implemented", "failed"},
    "implemented": {"qa_passed", "qa_failed", "qa_escalated", "failed"},
    "qa_failed": {"not_started", "planned", "implemented", "qa_escalated", "failed"},
    "qa_passed": {"implemented", "commit_stalled", "done", "failed", "escalated"},
    "qa_escalated": set(),
    "commit_stalled": set(),
    "done": set(),
    "failed": set(),
    "escalated": set(),
}
PR_STATUSES = {
    "merged", "pending_review", "open", "closed", "closed_superseded",
    "not_created_superseded", "created", "none",
}
WRITER_RE = re.compile(r"^[a-z][a-z0-9]*(?:[._-][a-z0-9]+){0,7}$")
STORY_RE = re.compile(r"^[A-Za-z][A-Za-z0-9._-]{0,63}$")
TOKEN_RE = re.compile(r"^[0-9a-f]{64}$")
OBJECT_RE = re.compile(r"^(?:[0-9a-f]{40}|[0-9a-f]{64})$")
SOURCE_REF_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._/-]{0,255}$")
TIMESTAMP_RE = re.compile(r"^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$")
PR_URL_RE = re.compile(r"^https://github\.com/[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+/pull/[1-9][0-9]*$")
POSITIVE_INT_RE = re.compile(r"^[1-9][0-9]*$")
COST_RE = re.compile(r"^(?:0|[1-9][0-9]*)(?:\.[0-9]+)?$")


def canonical_json(value):
    return json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False)


def sha256(value):
    return hashlib.sha256(value).hexdigest()


def safe_label(value, pattern, byte_limit=64):
    try:
        encoded = (value or "").encode("ascii")
    except UnicodeError:
        return "-"
    return value if len(encoded) <= byte_limit and pattern.fullmatch(value or "") else "-"


def diagnostic(story_id, field, writer, sequence, source_digest, record_digest,
               attempt, outcome, reason):
    print(
        "[BACKLOG-JOURNAL] "
        f"story={safe_label(story_id, STORY_RE)} "
        f"field={field if field in ALLOWED_FIELDS else '-'} "
        f"writer={safe_label(writer, WRITER_RE)} seq={sequence} "
        f"source={source_digest[:12] if source_digest else '-'} "
        f"record={record_digest[:12] if record_digest else '-'} "
        f"attempt={attempt if attempt in {'initial', 'replay', 'recovery', 'rejected'} else 'rejected'} "
        f"outcome={outcome} reason={reason}",
        file=sys.stderr,
    )


def git_output(args):
    try:
        return subprocess.check_output(args, stderr=subprocess.DEVNULL, text=True).strip()
    except (OSError, subprocess.CalledProcessError):
        raise JournalError("source_unresolvable")


def git_content(args):
    try:
        return subprocess.check_output(args, stderr=subprocess.DEVNULL, text=True)
    except (OSError, subprocess.CalledProcessError, UnicodeError):
        raise JournalError("source_unresolvable")


def load_yaml_source(source, target_story_id):
    try:
        import yaml
    except ImportError:
        raise JournalError("runtime_missing:pyyaml")

    try:
        class BacklogSafeLoader(yaml.SafeLoader):
            pass

        # Preserve integer, decimal and timestamp lexemes. Policy validation
        # inspects the composed scalar node before these strings are
        # canonicalized, so PyYAML cannot normalize a forbidden presentation.
        for tag in (
            "tag:yaml.org,2002:int",
            "tag:yaml.org,2002:float",
            "tag:yaml.org,2002:timestamp",
        ):
            BacklogSafeLoader.add_constructor(
                tag,
                lambda loader, node: loader.construct_scalar(node),
            )

        root = yaml.compose(source, Loader=BacklogSafeLoader)
        if not isinstance(root, yaml.MappingNode):
            raise JournalError("backlog_unsafe_yaml")
        if any(not isinstance(key, yaml.ScalarNode) for key, _ in root.value):
            raise JournalError("backlog_unsafe_yaml")
        items_nodes = [value for key, value in root.value if key.value == "items"]
        if len(items_nodes) != 1 or not isinstance(items_nodes[0], yaml.SequenceNode):
            raise JournalError("backlog_unsafe_yaml")
        target_nodes = []
        for item_node in items_nodes[0].value:
            if not isinstance(item_node, yaml.MappingNode):
                raise JournalError("backlog_unsafe_yaml")
            if any(not isinstance(key, yaml.ScalarNode) for key, _ in item_node.value):
                raise JournalError("backlog_unsafe_yaml")
            id_nodes = [value for key, value in item_node.value if key.value == "id"]
            if len(id_nodes) != 1 or not isinstance(id_nodes[0], yaml.ScalarNode):
                raise JournalError("backlog_unsafe_yaml")
            if id_nodes[0].value == target_story_id:
                target_nodes.append(item_node)
        if len(target_nodes) > 1:
            raise JournalError("story_duplicate")
        target_field_nodes = {}
        if target_nodes:
            keys = [key.value for key, _ in target_nodes[0].value]
            if "<<" in keys or len(keys) != len(set(keys)):
                raise JournalError("backlog_unsafe_yaml")
            target_field_nodes = {key.value: value for key, value in target_nodes[0].value}
        # SafeLoader prevents executable/object construction. Duplicate legacy
        # fields in unrelated rows do not influence the target row and are not
        # accepted as target identity or mutation authority.
        document = yaml.load(source, Loader=BacklogSafeLoader)
        if not isinstance(document, dict) or not isinstance(document.get("items"), list):
            raise JournalError("backlog_unsafe_yaml")
        matches = [
            item for item in document["items"]
            if isinstance(item, dict) and str(item.get("id")) == target_story_id
        ]
        if not matches:
            raise JournalError("story_missing")
        if len(matches) != 1:
            raise JournalError("story_duplicate")
        return matches[0], target_field_nodes, yaml
    except JournalError:
        raise
    except (UnicodeError, yaml.YAMLError):
        raise JournalError("backlog_unsafe_yaml")


def load_yaml_path(path, target_story_id):
    try:
        with open(path, "r", encoding="utf-8") as handle:
            return load_yaml_source(handle.read(), target_story_id)
    except JournalError:
        raise
    except (OSError, UnicodeError):
        raise JournalError("backlog_unsafe_yaml")


def canonical_timestamp(value):
    if value is None:
        return None
    if isinstance(value, datetime.datetime):
        if value.tzinfo is None:
            raise JournalError("value_malformed")
        value = value.astimezone(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    if not isinstance(value, str) or not TIMESTAMP_RE.fullmatch(value):
        raise JournalError("value_malformed")
    try:
        datetime.datetime.strptime(value, "%Y-%m-%dT%H:%M:%SZ")
    except ValueError:
        raise JournalError("value_malformed")
    return value


def canonical_blocked_reason(value):
    if value is None:
        return None
    if not isinstance(value, str) or not value:
        raise JournalError("value_malformed")
    for char in value:
        code = ord(char)
        if (code <= 31 or 127 <= code <= 159 or 0xD800 <= code <= 0xDFFF
                or code in {0x2028, 0x2029}):
            raise JournalError("value_malformed")
    return value


def canonical_pr_url(value):
    if value is None:
        return None
    if not isinstance(value, str) or not PR_URL_RE.fullmatch(value):
        raise JournalError("value_malformed")
    return value


def canonical_pr_number(value):
    if value is None:
        return None
    if isinstance(value, bool):
        raise JournalError("value_malformed")
    raw = str(value)
    if not POSITIVE_INT_RE.fullmatch(raw):
        raise JournalError("value_malformed")
    return int(raw)


def canonical_pr_status(value):
    if value is None:
        return None
    if not isinstance(value, str) or value not in PR_STATUSES:
        raise JournalError("value_malformed")
    return value


def canonical_cost(value, from_cli=False):
    if value is None:
        return None
    if isinstance(value, bool):
        raise JournalError("value_malformed")
    raw = str(value)
    if (from_cli or isinstance(value, str)) and not COST_RE.fullmatch(raw):
        raise JournalError("value_malformed")
    try:
        parsed = decimal.Decimal(raw)
    except decimal.InvalidOperation:
        raise JournalError("value_malformed")
    if not parsed.is_finite() or parsed < 0:
        raise JournalError("value_malformed")
    canonical = format(parsed, "f")
    if "." in canonical:
        canonical = canonical.rstrip("0").rstrip(".")
    return canonical or "0"


def canonical_scalar(field, value):
    if field in {"started_at", "completed_at"}:
        return canonical_timestamp(value)
    if field == "blocked_reason":
        return canonical_blocked_reason(value)
    if field == "pr_url":
        return canonical_pr_url(value)
    if field == "pr_number":
        return canonical_pr_number(value)
    if field == "pr_status":
        return canonical_pr_status(value)
    if field == "cost_usd":
        return canonical_cost(value)
    raise JournalError("field_not_allowed")


def resolve_predecessor(field, item, field_nodes, yaml):
    required = field in {"status", "phase_status"}
    node = field_nodes.get(field)
    if node is None:
        if required:
            raise JournalError("backlog_unsafe_yaml")
        return None
    if not isinstance(node, yaml.ScalarNode) or node.style in {"|", ">"}:
        raise JournalError("backlog_unsafe_yaml")

    null_tag = "tag:yaml.org,2002:null"
    string_tag = "tag:yaml.org,2002:str"
    allowed_tags = {
        "status": {string_tag},
        "phase_status": {string_tag},
        "started_at": {null_tag, string_tag, "tag:yaml.org,2002:timestamp"},
        "completed_at": {null_tag, string_tag, "tag:yaml.org,2002:timestamp"},
        "blocked_reason": {null_tag, string_tag},
        "pr_url": {null_tag, string_tag},
        "pr_number": {null_tag, "tag:yaml.org,2002:int"},
        "pr_status": {null_tag, string_tag},
        "cost_usd": {null_tag, "tag:yaml.org,2002:int", "tag:yaml.org,2002:float"},
    }
    if node.tag not in allowed_tags[field]:
        raise JournalError("value_malformed")

    value = item.get(field)
    if field == "status":
        if not isinstance(value, str) or value not in STATUS_VALUES:
            raise JournalError("value_malformed")
        return value
    if field == "phase_status":
        if not isinstance(value, str) or value not in PHASE_VALUES:
            raise JournalError("value_malformed")
        return value
    return canonical_scalar(field, value)


def parse_new_scalar(field, raw):
    if field == "blocked_reason":
        if raw == "null":
            value = None
        elif raw.startswith("json:"):
            try:
                value = json.loads(raw[5:])
            except json.JSONDecodeError:
                raise JournalError("value_malformed")
            if not isinstance(value, str):
                raise JournalError("value_malformed")
        else:
            raise JournalError("value_malformed")
        return canonical_blocked_reason(value)
    value = None if raw == "null" else raw
    if field == "cost_usd":
        return canonical_cost(value, from_cli=True)
    return canonical_scalar(field, value)


def validate_policy(field, old_value, raw_new_value):
    if field not in ALLOWED_FIELDS:
        raise JournalError("field_not_allowed")
    if field == "status":
        if not isinstance(old_value, str) or old_value not in STATUS_VALUES:
            raise JournalError("value_malformed")
        if raw_new_value not in STATUS_VALUES:
            raise JournalError("value_malformed")
        if raw_new_value not in STATUS_EDGES[old_value]:
            raise JournalError("transition_invalid")
        return old_value, raw_new_value
    if field == "phase_status":
        if not isinstance(old_value, str) or old_value not in PHASE_VALUES:
            raise JournalError("value_malformed")
        if raw_new_value not in PHASE_VALUES:
            raise JournalError("value_malformed")
        if raw_new_value not in PHASE_EDGES[old_value]:
            raise JournalError("transition_invalid")
        return old_value, raw_new_value
    return canonical_scalar(field, old_value), parse_new_scalar(field, raw_new_value)


def load_registration(path, token, writer):
    try:
        mode = os.stat(path, follow_symlinks=False).st_mode
        if not stat.S_ISREG(mode) or mode & 0o077:
            raise ValueError
        with open(path, "r", encoding="utf-8") as handle:
            wrapper = json.load(handle)
        registration = wrapper["registration"]
        digest = wrapper["digest"]
        if set(wrapper) != {"registration", "digest"}:
            raise ValueError
        if set(registration) != {"schema_version", "run_token", "writer_context", "issued_at"}:
            raise ValueError
        if registration.get("schema_version") != "1.0.0":
            raise ValueError
        if registration.get("run_token") != token or registration.get("writer_context") != writer:
            raise ValueError
        if canonical_timestamp(registration.get("issued_at")) != registration.get("issued_at"):
            raise ValueError
        if not re.fullmatch(r"[0-9a-f]{64}", digest or ""):
            raise ValueError
        if sha256(canonical_json(registration).encode("utf-8")) != digest:
            raise ValueError
    except (OSError, ValueError, KeyError, TypeError, json.JSONDecodeError, JournalError):
        raise JournalError("run_token_unregistered")


def load_record(path, writer, registrations_dir):
    try:
        mode = os.stat(path, follow_symlinks=False).st_mode
        if not stat.S_ISREG(mode) or mode & 0o077:
            raise ValueError
        with open(path, "r", encoding="utf-8") as handle:
            wrapper = json.load(handle)
        record = wrapper["record"]
        digest = wrapper["digest"]
        intent_digest = wrapper["intent_digest"]
        expected_record_keys = {
            "schema_version", "story_id", "field", "old_value", "new_value",
            "source_commit", "source_blob", "writer_context", "run_token",
            "intent_digest", "sequence", "emitted_at",
        }
        if set(wrapper) != {"record", "intent_digest", "digest"} or set(record) != expected_record_keys:
            raise ValueError
        if record.get("schema_version") != "1.0.0":
            raise ValueError
        if record.get("writer_context") != writer:
            raise ValueError
        if (not STORY_RE.fullmatch(record.get("story_id") or "")
                or record.get("field") not in ALLOWED_FIELDS
                or not WRITER_RE.fullmatch(record.get("writer_context") or "")
                or not TOKEN_RE.fullmatch(record.get("run_token") or "")
                or not OBJECT_RE.fullmatch(record.get("source_commit") or "")
                or not OBJECT_RE.fullmatch(record.get("source_blob") or "")
                or canonical_timestamp(record.get("emitted_at")) != record.get("emitted_at")):
            raise ValueError
        if record.get("intent_digest") != intent_digest:
            raise ValueError
        if (isinstance(record.get("sequence"), bool)
                or not isinstance(record.get("sequence"), int)
                or record["sequence"] < 1):
            raise ValueError
        if not re.fullmatch(r"[0-9a-f]{64}", digest or ""):
            raise ValueError
        if not re.fullmatch(r"[0-9a-f]{64}", intent_digest or ""):
            raise ValueError
        if sha256(canonical_json(record).encode("utf-8")) != digest:
            raise ValueError
        try:
            if record["field"] in {"status", "phase_status"}:
                canonical_old, canonical_new = validate_policy(
                    record["field"], record["old_value"], record["new_value"]
                )
            else:
                canonical_old = canonical_scalar(record["field"], record["old_value"])
                canonical_new = canonical_scalar(record["field"], record["new_value"])
        except JournalError:
            raise ValueError
        if canonical_old != record["old_value"] or canonical_new != record["new_value"]:
            raise ValueError
        intent = {key: record[key] for key in (
            "schema_version", "story_id", "field", "old_value", "new_value",
            "source_commit", "source_blob", "writer_context", "run_token",
        )}
        if sha256(canonical_json(intent).encode("utf-8")) != intent_digest:
            raise ValueError
        expected_name = f"{record['sequence']:020d}-{intent_digest[:16]}.json"
        if os.path.basename(path) != expected_name:
            raise ValueError
        load_registration(
            os.path.join(registrations_dir, f"{record['run_token']}.json"),
            record["run_token"],
            writer,
        )
        return wrapper
    except JournalError as exc:
        if exc.reason == "run_token_unregistered":
            raise
        raise JournalError("digest_mismatch")
    except (OSError, ValueError, KeyError, TypeError, json.JSONDecodeError):
        raise JournalError("digest_mismatch")


def fsync_dir(path):
    fd = os.open(path, os.O_RDONLY)
    try:
        os.fsync(fd)
    finally:
        os.close(fd)


def write_sequence(writer_dir, sequence):
    sequence_path = os.path.join(writer_dir, ".sequence")
    temp_path = os.path.join(writer_dir, f".sequence.{os.getpid()}.tmp")
    try:
        fd = os.open(temp_path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
        try:
            view = memoryview(f"{sequence}\n".encode("ascii"))
            while view:
                if os.environ.get("GAAI_BACKLOG_JOURNAL_FAULT") == "sequence_short_write":
                    written = 0
                else:
                    written = os.write(fd, view)
                if written <= 0:
                    raise OSError(errno.EIO, "short write")
                view = view[written:]
            os.fsync(fd)
        finally:
            os.close(fd)
        os.replace(temp_path, sequence_path)
        fsync_dir(writer_dir)
    except PermissionError:
        raise JournalError("journal_storage_permissions", sequence=sequence)
    except OSError:
        raise JournalError("append_interrupted", sequence=sequence, attempt="recovery")


def publish_record(records_dir, sequence, intent_digest, payload, record_digest):
    final_path = os.path.join(records_dir, f"{sequence:020d}-{intent_digest[:16]}.json")
    temp_path = os.path.join(records_dir, f".{sequence:020d}-{intent_digest[:16]}.{os.getpid()}.tmp")
    try:
        fd = os.open(temp_path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
        try:
            view = memoryview(payload)
            while view:
                written = os.write(fd, view)
                if written <= 0:
                    raise OSError(errno.EIO, "short write")
                view = view[written:]
            os.fsync(fd)
        finally:
            os.close(fd)
        if os.environ.get("GAAI_BACKLOG_JOURNAL_FAULT") == "after_temp_fsync":
            raise JournalError("append_interrupted", sequence, "", record_digest, "recovery")
        os.link(temp_path, final_path)
        os.unlink(temp_path)
        fsync_dir(records_dir)
        return final_path
    except JournalError:
        raise
    except FileExistsError:
        raise JournalError("conflicting_duplicate", sequence, "", record_digest, "recovery")
    except PermissionError:
        raise JournalError("journal_storage_permissions", sequence, "", record_digest, "recovery")
    except OSError:
        raise JournalError("append_interrupted", sequence, "", record_digest, "recovery")


def run(backlog_file, story_id, field, raw_new_value, writer, token):
    if not backlog_file or not os.path.isfile(backlog_file):
        raise JournalError("backlog_missing")
    if not STORY_RE.fullmatch(story_id or ""):
        raise JournalError("story_missing")
    try:
        writer_bytes = writer.encode("ascii")
    except UnicodeError:
        raise JournalError("writer_context_invalid")
    if len(writer_bytes) > 64 or not WRITER_RE.fullmatch(writer or ""):
        raise JournalError("writer_context_invalid")
    if not TOKEN_RE.fullmatch(token or ""):
        raise JournalError("run_token_unregistered")
    if field not in ALLOWED_FIELDS:
        raise JournalError("field_not_allowed")

    backlog_abs = os.path.realpath(backlog_file)
    backlog_dir = os.path.dirname(backlog_abs)
    repo_root = os.path.realpath(git_output(["git", "-C", backlog_dir, "rev-parse", "--show-toplevel"]))
    try:
        if os.path.commonpath([repo_root, backlog_abs]) != repo_root:
            raise ValueError
    except ValueError:
        raise JournalError("source_unresolvable")
    source_ref = os.environ.get("GAAI_BACKLOG_JOURNAL_SOURCE_REF", "HEAD")
    if (not SOURCE_REF_RE.fullmatch(source_ref)
            or any(part in {"", ".", ".."} for part in source_ref.split("/"))
            or ".." in source_ref):
        raise JournalError("source_unresolvable")
    source_commit = git_output([
        "git", "-C", repo_root, "rev-parse", "--verify", "--end-of-options",
        f"{source_ref}^{{commit}}",
    ])
    relative_path = os.path.relpath(backlog_abs, repo_root)
    source_blob = git_output(["git", "-C", repo_root, "rev-parse", f"{source_commit}:{relative_path}"])
    if not OBJECT_RE.fullmatch(source_commit) or not OBJECT_RE.fullmatch(source_blob):
        raise JournalError("source_unresolvable")

    try:
        working_item, working_nodes, yaml = load_yaml_path(backlog_abs, story_id)
        source_text = git_content(["git", "-C", repo_root, "cat-file", "blob", source_blob])
        source_item, source_nodes, source_yaml = load_yaml_source(source_text, story_id)
        working_old = resolve_predecessor(field, working_item, working_nodes, yaml)
        source_old = resolve_predecessor(field, source_item, source_nodes, source_yaml)
        if working_old != source_old:
            raise JournalError("source_value_mismatch")
        old_value, new_value = validate_policy(field, working_old, raw_new_value)
        if old_value != source_old:
            raise JournalError("source_value_mismatch")
    except JournalError as exc:
        exc.source_digest = source_blob
        raise

    journal_root = os.path.realpath(os.environ.get(
        "GAAI_BACKLOG_JOURNAL_DIR",
        os.path.join(backlog_dir, ".delivery-locks", "journal"),
    ))
    registration_path = os.path.join(journal_root, "registrations", f"{token}.json")
    try:
        load_registration(registration_path, token, writer)
    except JournalError as exc:
        exc.source_digest = source_blob
        raise

    writer_key = sha256(writer.encode("ascii"))
    writer_dir = os.path.join(journal_root, "writers", writer_key)
    records_dir = os.path.join(writer_dir, "records")
    try:
        writers_dir = os.path.dirname(writer_dir)
        os.makedirs(writers_dir, mode=0o700, exist_ok=True)
        os.makedirs(writer_dir, mode=0o700, exist_ok=True)
        os.makedirs(records_dir, mode=0o700, exist_ok=True)
        if (os.stat(writers_dir).st_mode & 0o077 or os.stat(writer_dir).st_mode & 0o077
                or os.stat(records_dir).st_mode & 0o077):
            raise JournalError("journal_storage_permissions", source_digest=source_blob)
        lock_fd = os.open(os.path.join(writer_dir, ".lock"), os.O_RDWR | os.O_CREAT, 0o600)
    except JournalError:
        raise
    except PermissionError:
        raise JournalError("journal_storage_permissions", source_digest=source_blob)
    except OSError:
        raise JournalError("journal_storage_unavailable", source_digest=source_blob)

    intent = {
        "schema_version": "1.0.0",
        "story_id": story_id,
        "field": field,
        "old_value": old_value,
        "new_value": new_value,
        "source_commit": source_commit,
        "source_blob": source_blob,
        "writer_context": writer,
        "run_token": token,
    }
    intent_digest = sha256(canonical_json(intent).encode("utf-8"))

    with os.fdopen(lock_fd, "a+", encoding="ascii") as lock_handle:
        try:
            fcntl.flock(lock_handle.fileno(), fcntl.LOCK_EX)
        except OSError:
            raise JournalError("journal_storage_unavailable", source_digest=source_blob)

        temp_records = glob.glob(os.path.join(records_dir, ".*.tmp"))
        if temp_records:
            raise JournalError("append_interrupted", source_digest=source_blob, attempt="recovery")

        sequence_to_record = {}
        matching = []
        for path in sorted(glob.glob(os.path.join(records_dir, "*.json"))):
            try:
                wrapper = load_record(path, writer, os.path.dirname(registration_path))
            except JournalError as exc:
                exc.source_digest = source_blob
                raise
            sequence = wrapper["record"]["sequence"]
            if sequence in sequence_to_record:
                raise JournalError("conflicting_duplicate", sequence, source_blob, attempt="recovery")
            sequence_to_record[sequence] = wrapper
            if wrapper["intent_digest"] == intent_digest:
                matching.append((path, wrapper))
        if len(matching) > 1:
            raise JournalError("conflicting_duplicate", matching[0][1]["record"]["sequence"], source_blob,
                               matching[0][1]["digest"], "recovery")

        max_record_sequence = max(sequence_to_record, default=0)
        if sequence_to_record and set(sequence_to_record) != set(range(1, max_record_sequence + 1)):
            raise JournalError("sequence_fork", max_record_sequence, source_blob, attempt="recovery")
        sequence_path = os.path.join(writer_dir, ".sequence")
        durable_sequence = 0
        if os.path.exists(sequence_path):
            try:
                sequence_mode = os.stat(sequence_path, follow_symlinks=False).st_mode
                if not stat.S_ISREG(sequence_mode) or sequence_mode & 0o077:
                    raise ValueError
                with open(sequence_path, "r", encoding="ascii") as handle:
                    raw_sequence = handle.read().strip()
                if not re.fullmatch(r"[1-9][0-9]*", raw_sequence):
                    raise ValueError
                durable_sequence = int(raw_sequence)
            except (OSError, UnicodeError, ValueError):
                raise JournalError("sequence_fork", source_digest=source_blob, attempt="recovery")
        if durable_sequence > max_record_sequence:
            raise JournalError("sequence_fork", durable_sequence, source_blob, attempt="recovery")
        recovered = durable_sequence < max_record_sequence
        if recovered:
            try:
                write_sequence(writer_dir, max_record_sequence)
            except JournalError as exc:
                exc.source_digest = source_blob
                raise
            durable_sequence = max_record_sequence

        if matching:
            path, wrapper = matching[0]
            record = wrapper["record"]
            return (
                "pending:replay", path, wrapper["digest"], record["sequence"], source_blob,
                "recovery" if recovered else "replay", "replay",
            )

        sequence = max(durable_sequence, max_record_sequence) + 1
        record = dict(intent)
        record.update({
            "intent_digest": intent_digest,
            "sequence": sequence,
            "emitted_at": datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        })
        record_digest = sha256(canonical_json(record).encode("utf-8"))
        wrapper = {"record": record, "intent_digest": intent_digest, "digest": record_digest}
        payload = (canonical_json(wrapper) + "\n").encode("utf-8")
        try:
            final_path = publish_record(records_dir, sequence, intent_digest, payload, record_digest)
        except JournalError as exc:
            exc.source_digest = source_blob
            raise
        if os.environ.get("GAAI_BACKLOG_JOURNAL_FAULT") == "after_record_publish":
            raise JournalError("append_interrupted", sequence, source_blob, record_digest, "recovery")
        try:
            write_sequence(writer_dir, sequence)
        except JournalError as exc:
            exc.source_digest = source_blob
            exc.record_digest = record_digest
            raise
        if os.environ.get("GAAI_BACKLOG_JOURNAL_FAULT") == "after_sequence_update":
            raise JournalError("append_interrupted", sequence, source_blob, record_digest, "recovery")
        return "emitted", final_path, record_digest, sequence, source_blob, "initial", "none"


backlog_file, story_id, field, raw_new_value, writer, token = sys.argv[1:7]
try:
    outcome, path, record_digest, sequence, source_digest, attempt, reason = run(
        backlog_file, story_id, field, raw_new_value, writer, token
    )
    diagnostic(story_id, field, writer, sequence, source_digest, record_digest,
               attempt, outcome, reason)
    print(f"{outcome}\t{path}\t{record_digest}\t{sequence}\t{reason}")
    if outcome == "pending:replay":
        raise SystemExit(10)
except JournalError as exc:
    diagnostic(story_id, field, writer, exc.sequence, exc.source_digest,
               exc.record_digest, exc.attempt, "rejected", exc.reason)
    print(f"rejected\t-\t-\t{exc.sequence}\t{exc.reason}")
    raise SystemExit(1)
PY
  ); then
    rc=0
  else
    rc=$?
  fi

  IFS=$'\t' read -r BACKLOG_JOURNAL_OUTCOME BACKLOG_JOURNAL_RECORD_PATH \
    BACKLOG_JOURNAL_RECORD_DIGEST BACKLOG_JOURNAL_SEQUENCE BACKLOG_JOURNAL_REASON <<< "$result"
  if [[ "$BACKLOG_JOURNAL_RECORD_PATH" == "-" ]]; then
    BACKLOG_JOURNAL_RECORD_PATH=""
  fi
  if [[ "$BACKLOG_JOURNAL_RECORD_DIGEST" == "-" ]]; then
    BACKLOG_JOURNAL_RECORD_DIGEST=""
  fi
  return "$rc"
}
