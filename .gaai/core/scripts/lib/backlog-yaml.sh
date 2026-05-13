#!/usr/bin/env bash
# backlog-yaml.sh — yq-backed helper for reading status/phase_status from GAAI backlog YAML
#
# Usage: source "$SCRIPT_DIR/lib/backlog-yaml.sh" (or equivalent path)
#
# Requires: yq v4 (mikefarah/yq). Falls back to Python3 regex if yq absent.
# Limitation: Python fallback does NOT support YAML flow-style ({status: in_progress}).
#
# Return contract (all per-ID lookup functions):
#   stdout = value string (or whitespace-separated ID list for backlog_in_progress_ids)
#   exit 0 = found
#   exit 1 = id not in backlog (or field absent)
#   exit 2 = malformed YAML / unreadable file

set -euo pipefail

_BACKLOG_YQ_AVAILABLE=""

_backlog_yaml_detect_yq() {
  [[ -n "$_BACKLOG_YQ_AVAILABLE" ]] && return
  if command -v yq &>/dev/null && yq --version 2>/dev/null | grep -q 'mikefarah/yq'; then
    _BACKLOG_YQ_AVAILABLE="yes"
  else
    _BACKLOG_YQ_AVAILABLE="no"
    >&2 echo "[backlog-yaml] yq unavailable — using quote-tolerant regex fallback"
  fi
}

_backlog_get_field() {
  local id="$1" field="$2" backlog_path="$3"
  _backlog_yaml_detect_yq

  if [[ "$_BACKLOG_YQ_AVAILABLE" == "yes" ]]; then
    local result
    result=$(yq ".items[] | select(.id == \"${id}\") | .${field}" "$backlog_path" 2>/dev/null) || {
      return 2
    }
    [[ -z "$result" || "$result" == "null" ]] && return 1
    echo "$result"
    return 0
  fi

  # Python3 fallback
  python3 - "$id" "$field" "$backlog_path" << 'PYEOF' || return $?
import sys, re

_, sid, field_name, path = sys.argv

FIELD_RE = re.compile(
    r"^\s*(status|phase_status):\s*['\"]?([a-z_]+)['\"]?\s*(#.*)?$"
)

try:
    with open(path, "r") as f:
        lines = f.readlines()
except (FileNotFoundError, PermissionError):
    sys.exit(2)

in_target_block = False
found_id = False

for line in lines:
    stripped = line.rstrip()

    if stripped.startswith("- id:"):
        cur_id = stripped[len("- id:"):].strip().strip("'\"")
        in_target_block = (cur_id == sid)
        if in_target_block:
            found_id = True
        continue

    if in_target_block:
        if stripped and not stripped[0].isspace() and not stripped.startswith("#"):
            break
        m = FIELD_RE.match(stripped)
        if m and m.group(1) == field_name:
            print(m.group(2))
            sys.exit(0)

if not found_id:
    sys.exit(1)
sys.exit(1)
PYEOF
}

backlog_status() {
  local id="$1" backlog_path="$2"
  _backlog_get_field "$id" "status" "$backlog_path"
}

backlog_phase_status() {
  local id="$1" backlog_path="$2"
  _backlog_get_field "$id" "phase_status" "$backlog_path"
}

backlog_in_progress_ids() {
  local backlog_path="$1"
  _backlog_yaml_detect_yq

  if [[ "$_BACKLOG_YQ_AVAILABLE" == "yes" ]]; then
    local result
    result=$(yq '.items[] | select(.status == "in_progress") | .id' "$backlog_path" 2>/dev/null) || {
      return 2
    }
    [[ -z "$result" ]] && return 1
    echo "$result"
    return 0
  fi

  # Python3 fallback
  python3 - "$backlog_path" << 'PYEOF' || return $?
import sys, re

_, path = sys.argv

FIELD_RE = re.compile(
    r"^\s*(status|phase_status):\s*['\"]?([a-z_]+)['\"]?\s*(#.*)?$"
)

try:
    with open(path, "r") as f:
        lines = f.readlines()
except (FileNotFoundError, PermissionError):
    sys.exit(2)

current_id = None
current_status = None
results = []

for line in lines:
    stripped = line.rstrip()

    if stripped.startswith("- id:"):
        if current_id is not None and current_status == "in_progress":
            results.append(current_id)
        current_id = stripped[len("- id:"):].strip().strip("'\"")
        current_status = None
        continue

    m = FIELD_RE.match(stripped)
    if m and m.group(1) == "status":
        current_status = m.group(2)

if current_id is not None and current_status == "in_progress":
    results.append(current_id)

if results:
    print("\n".join(results))
    sys.exit(0)
sys.exit(1)
PYEOF
}

backlog_ids_by_status() {
  local status="$1" backlog_path="$2"
  _backlog_yaml_detect_yq

  if [[ "$_BACKLOG_YQ_AVAILABLE" == "yes" ]]; then
    local result
    result=$(yq ".items[] | select(.status == \"${status}\") | .id" "$backlog_path" 2>/dev/null) || {
      return 2
    }
    [[ -z "$result" ]] && return 1
    echo "$result"
    return 0
  fi

  # Python3 fallback
  python3 - "$status" "$backlog_path" << 'PYEOF' || return $?
import sys, re

_, target_status, path = sys.argv

FIELD_RE = re.compile(
    r"^\s*(status|phase_status):\s*['\"]?([a-z_]+)['\"]?\s*(#.*)?$"
)

try:
    with open(path, "r") as f:
        lines = f.readlines()
except (FileNotFoundError, PermissionError):
    sys.exit(2)

current_id = None
current_status = None
results = []

for line in lines:
    stripped = line.rstrip()

    if stripped.startswith("- id:"):
        if current_id is not None and current_status == target_status:
            results.append(current_id)
        current_id = stripped[len("- id:"):].strip().strip("'\"")
        current_status = None
        continue

    m = FIELD_RE.match(stripped)
    if m and m.group(1) == "status":
        current_status = m.group(2)

if current_id is not None and current_status == target_status:
    results.append(current_id)

if results:
    print("\n".join(results))
    sys.exit(0)
sys.exit(1)
PYEOF
}
