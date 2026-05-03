#!/usr/bin/env python3
"""
daemon-worktree-audit.py — Post-phase audit for daemon-spawned claude -p logs.

Parses a per-phase JSONL log (plan/impl/qa) and detects tool calls that
operate on absolute paths outside the worktree. This is an advisory soft
gate; it does NOT block phase completion. Writes a structured audit JSON to
<log_path>.audit.json so the daemon-monitor and forensic tooling can see
violations in-band.

Flagged patterns:
  - Write tool: file_path outside worktree (and outside allow-list /tmp etc.)
  - Edit tool: file_path outside worktree
  - Bash tool: command containing absolute paths outside worktree

Allow-listed prefixes (legitimate ephemeral or system paths):
  - /tmp/, /private/tmp/  — claude scratch + heredoc temp
  - /var/folders/, /private/var/folders/ — macOS user temp

Reads outside the worktree (Read tool) are NOT flagged — agents legitimately
read DEC files, framework adapters, etc. via absolute paths during planning.

Usage:
    daemon-worktree-audit.py \\
        --story-id <id> \\
        --phase <plan|impl|qa> \\
        --log-path /path/to/{id}.{phase}.log \\
        --worktree-path /path/to/{id}-workspace

Exit codes:
    0 — no violations
    1 — violations detected (advisory; daemon should NOT abort on this)
    2 — usage / IO error
"""

import sys
import json
import re
import argparse
import os.path


DEFAULT_ALLOWED_PREFIXES = (
    "/tmp/",
    "/private/tmp/",
    "/var/folders/",
    "/private/var/folders/",
    "/dev/",  # /dev/null, /dev/stdout, /dev/stderr, etc.
)

# Match an absolute path inside an arbitrary bash command. Conservative: must
# start with /, contain at least one further /, and consist of typical path
# chars. Avoids false positives on regex literals (which are usually quoted)
# but does not parse shell quoting — so a `grep '/foo/bar'` will be flagged.
# That's acceptable for an advisory audit; review the audit JSON for context.
_ABS_PATH_RE = re.compile(r"(?<![A-Za-z0-9_\-/.])(/[A-Za-z0-9_\-./~]+/[A-Za-z0-9_\-./~]*)")


def _normalize(path: str) -> str:
    """Best-effort canonical form. Doesn't resolve symlinks (worktree paths
    typically have a symlink ancestor — Dropbox folder, /Users link)."""
    try:
        return os.path.normpath(path)
    except Exception:
        return path


def is_within(path: str, base: str) -> bool:
    p = _normalize(path)
    b = _normalize(base)
    if not b.endswith("/"):
        b_with_sep = b + "/"
    else:
        b_with_sep = b
    return p == b or p.startswith(b_with_sep)


def is_allowed(path: str, worktree: str, allowed_prefixes=DEFAULT_ALLOWED_PREFIXES) -> bool:
    if is_within(path, worktree):
        return True
    for p in allowed_prefixes:
        if path.startswith(p):
            return True
    return False


def scan_log(log_path: str, worktree_path: str) -> list:
    violations = []
    try:
        f = open(log_path, "r")
    except OSError as e:
        print(f"[audit] cannot open log: {e}", file=sys.stderr)
        return violations

    with f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            try:
                d = json.loads(line)
            except Exception:
                continue
            if d.get("type") != "assistant":
                continue
            msg = d.get("message") or {}
            content = msg.get("content") or []
            if not isinstance(content, list):
                continue
            for c in content:
                if not isinstance(c, dict):
                    continue
                if c.get("type") != "tool_use":
                    continue
                tool_name = c.get("name", "")
                tool_input = c.get("input", {}) or {}

                if tool_name in ("Write", "Edit"):
                    fp = tool_input.get("file_path", "") or ""
                    if fp and not is_allowed(fp, worktree_path):
                        violations.append({
                            "tool": tool_name,
                            "field": "file_path",
                            "value": fp,
                        })
                elif tool_name == "Bash":
                    cmd = tool_input.get("command", "") or ""
                    seen_in_this_cmd = set()
                    for m in _ABS_PATH_RE.finditer(cmd):
                        path = m.group(1).rstrip(".,;:)'\"")
                        if path in seen_in_this_cmd:
                            continue
                        seen_in_this_cmd.add(path)
                        if not is_allowed(path, worktree_path):
                            violations.append({
                                "tool": "Bash",
                                "field": "command_path",
                                "value": path,
                                "command_excerpt": cmd[:160],
                            })
    return violations


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--story-id", required=True)
    ap.add_argument("--phase", required=True)
    ap.add_argument("--log-path", required=True)
    ap.add_argument("--worktree-path", required=True)
    args = ap.parse_args()

    violations = scan_log(args.log_path, args.worktree_path)
    audit = {
        "story_id": args.story_id,
        "phase": args.phase,
        "worktree_path": args.worktree_path,
        "verdict": "clean" if not violations else "violations_detected",
        "violation_count": len(violations),
        "violations": violations[:50],
    }
    audit_path = args.log_path + ".audit.json"
    try:
        with open(audit_path, "w") as f:
            json.dump(audit, f, indent=2)
    except OSError as e:
        print(f"[audit] cannot write audit file: {e}", file=sys.stderr)
        return 2

    if violations:
        print(
            f"[AUDIT] {args.story_id} phase={args.phase}: "
            f"{len(violations)} out-of-worktree path(s) detected; see {audit_path}",
            file=sys.stderr,
        )
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
