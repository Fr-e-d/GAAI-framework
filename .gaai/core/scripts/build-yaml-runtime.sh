#!/usr/bin/env bash
# build-yaml-runtime.sh — offline, digest-verified, deterministic builder for the
# vendored pure-Python YAML runtime.
#
# The builder is offline by construction: it never downloads, installs, updates or
# invokes a package manager, and it has no fallback that could acquire anything. Its
# only input is a locally supplied source distribution whose exact SHA-256 is pinned
# below, plus the upstream release timestamp the operator transcribes from the trusted
# upstream release record (an offline builder cannot read a release date out of the
# source distribution itself — that metadata does not exist in the archive).
#
# Usage:
#   GAAI_YAML_PYTHON=<abs path to the pinned builder CPython> \
#   bash .gaai/core/scripts/build-yaml-runtime.sh \
#     --sdist <abs-path-to-source-distribution> \
#     --release-timestamp <ISO-8601-UTC> \
#     --out .gaai/core/vendor/pyyaml/6.0.3 \
#     [--check]
#
# All three of --sdist, --release-timestamp and --out are mandatory. A missing or
# malformed value is a typed failure; nothing is defaulted, inferred or taken from the
# current clock.
#
# --check rebuilds into a private temporary directory and byte-compares all three
# outputs (archive, licence and manifest) against the checked-in tuple, exiting
# non-zero on any difference.
#
# Exit codes:
#   0 — outputs written (or --check found the tuple byte-identical)
#   1 — usage error
#   2 — interpreter attestation failed
#   3 — source-distribution verification or extraction failed
#   4 — output write/verification failed, or --check found a difference

set -euo pipefail

_yr_die() { printf '[build-yaml-runtime] %s\n' "$1" >&2; exit "${2:-1}"; }

SDIST=""
RELEASE_TIMESTAMP=""
OUT_DIR=""
BUILD_MODE="build"

while [ "$#" -gt 0 ]; do
  case "$1" in
    --sdist)
      [ "$#" -ge 2 ] || _yr_die "--sdist requires a value" 1
      SDIST="$2"; shift 2 ;;
    --release-timestamp)
      [ "$#" -ge 2 ] || _yr_die "--release-timestamp requires a value" 1
      RELEASE_TIMESTAMP="$2"; shift 2 ;;
    --out)
      [ "$#" -ge 2 ] || _yr_die "--out requires a value" 1
      OUT_DIR="$2"; shift 2 ;;
    --check)
      BUILD_MODE="check"; shift ;;
    *)
      _yr_die "unknown option: $1" 1 ;;
  esac
done

[ -n "$SDIST" ] || _yr_die "--sdist is mandatory" 1
[ -n "$RELEASE_TIMESTAMP" ] || _yr_die "--release-timestamp is mandatory" 1
[ -n "$OUT_DIR" ] || _yr_die "--out is mandatory" 1

# ── Self-contained pinned-interpreter assertion ──────────────────────────────
# The builder runs before the invocation boundary library exists in a fresh tree,
# so it must not source it — that ordering would be circular. It therefore carries
# its own exact assertion, and GAAI_YAML_PYTHON is mandatory here: the builder has
# no discovery mode and no fallback.
_YR_BUILDER_PY="${GAAI_YAML_PYTHON:-}"
[ -n "$_YR_BUILDER_PY" ] || _yr_die "GAAI_YAML_PYTHON is mandatory for the builder" 2
case "$_YR_BUILDER_PY" in
  /*) ;;
  *) _yr_die "GAAI_YAML_PYTHON must be an absolute path" 2 ;;
esac
[ -f "$_YR_BUILDER_PY" ] || _yr_die "GAAI_YAML_PYTHON is not a regular file" 2
[ -x "$_YR_BUILDER_PY" ] || _yr_die "GAAI_YAML_PYTHON is not executable" 2

_YR_BUILDER_SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
_YR_BUILDER_SELF="$_YR_BUILDER_SELF_DIR/$(basename "${BASH_SOURCE[0]}")"

read -r -d '' _YR_BUILD_PROGRAM <<'PYEOF' || true
import hashlib
import json
import os
import platform
import re
import stat
import sys
import tarfile
import tempfile
import zipfile

# ── Pinned facts about the exact upstream artefact this builder accepts ──────
UPSTREAM_NAME = "PyYAML"
UPSTREAM_VERSION = "6.0.3"
UPSTREAM_LICENSE = "MIT"
# Recorded provenance metadata. It is never fetched, resolved or contacted by any
# code path here; the builder performs no network access of any kind.
UPSTREAM_CANONICAL_SOURCE_URL = (
    "https://files.pythonhosted.org/packages/05/8e/"
    "961c0007c59b8dd7729d542c61a4d537767a59645b82a0b521206e1e25c2/"
    "pyyaml-6.0.3.tar.gz"
)
UPSTREAM_SOURCE_FILENAME = "pyyaml-6.0.3.tar.gz"
UPSTREAM_SDIST_SHA256 = (
    "d76623373421df22fb4cf8817020cbb7ef15c725b9d5e45f17e189bfc384190f"
)
# Factual upstream compatibility metadata only. It never lowers the Framework
# support boundary declared immediately below.
UPSTREAM_REQUIRES_PYTHON = ">=3.8"
FRAMEWORK_SUPPORTED_MINORS = ["3.12", "3.13", "3.14"]
FRAMEWORK_SUPPORT_BOUNDARY_NOTE = (
    "Upstream compatibility metadata never lowers this allowlist."
)
BUILDER_CPYTHON = "3.12.11"

# Repository-relative constants. They are deliberately independent of --out so two
# rebuilds into two different private roots produce a byte-identical manifest.
ARCHIVE_NAME = "pyyaml-runtime.pyz"
LICENCE_NAME = "LICENSE"
MANIFEST_NAME = "PROVENANCE.json"
VENDOR_REL = ".gaai/core/vendor/pyyaml/6.0.3"
BUILDER_REL = ".gaai/core/scripts/build-yaml-runtime.sh"
OUTPUT_REL = VENDOR_REL + "/" + ARCHIVE_NAME
LICENCE_REL = VENDOR_REL + "/" + LICENCE_NAME
REBUILD_COMMAND = (
    "bash .gaai/core/scripts/build-yaml-runtime.sh"
    " --sdist <local sdist>"
    " --release-timestamp <recorded upstream release timestamp>"
    " --out .gaai/core/vendor/pyyaml/6.0.3"
)
EXCLUDED_CLASSES = [
    "native-extension", "bytecode", "symlink", "hardlink", "device",
    "test", "documentation",
]
ZIP_EPOCH = (1980, 1, 1, 0, 0, 0)
ZIP_EPOCH_LABEL = "1980-01-01T00:00:00Z"
EXACT_FILE_MODE = 0o644
REJECTED_SUFFIXES = (".pyc", ".pyo", ".so", ".pyd", ".dylib", ".c", ".h", ".pyx")
TIMESTAMP_RE = re.compile(r"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,9})?Z$")


def die(code, message):
    sys.stderr.write("[build-yaml-runtime] %s\n" % message)
    raise SystemExit(code)


def sha256_bytes(data):
    return hashlib.sha256(data).hexdigest()


def real_executing_image():
    """The image the kernel actually loaded, never sys.executable.

    sys.executable is derived from argv[0], so an argv[0]-preserving re-exec
    leaves it equal to the declared path. Resolving the true image is what makes
    the binding meaningful.
    """
    if sys.platform == "darwin":
        import ctypes

        libc = ctypes.CDLL(None)
        get_path = libc._NSGetExecutablePath
        size = ctypes.c_uint32(1024)
        buf = ctypes.create_string_buffer(size.value)
        rc = get_path(buf, ctypes.byref(size))
        if rc != 0:
            # Documented "buffer too small": retry once against a hard bound.
            if size.value <= 0 or size.value > 65536:
                return None
            buf = ctypes.create_string_buffer(size.value)
            if get_path(buf, ctypes.byref(size)) != 0:
                return None
        raw = buf.value
        if not raw:
            return None
        return os.path.realpath(os.fsdecode(raw))
    try:
        return os.path.realpath(os.readlink("/proc/self/exe"))
    except OSError:
        return None


def framework_root(path):
    parts = os.path.realpath(path).split(os.sep)
    for index, part in enumerate(parts):
        if part == "Python.framework" and index + 2 < len(parts) \
                and parts[index + 1] == "Versions":
            return os.sep.join(parts[:index + 3])
    return None


def native_magic(path):
    try:
        with open(path, "rb") as handle:
            head = handle.read(4)
    except OSError:
        return False
    return head in (
        b"\x7fELF",
        b"\xcf\xfa\xed\xfe",
        b"\xca\xfe\xba\xbe", b"\xca\xfe\xba\xbf",
    )


def assert_pinned_interpreter(declared):
    if sys.implementation.name != "cpython":
        die(2, "builder interpreter is not CPython")
    if platform.python_version() != BUILDER_CPYTHON:
        die(2, "builder interpreter is not the pinned version")
    if sys.version_info.releaselevel != "final":
        die(2, "builder interpreter is not a final release")
    image = real_executing_image()
    if image is None:
        die(2, "builder executing image could not be resolved")
    declared_real = os.path.realpath(declared)
    if image != declared_real:
        # A genuine framework build splits the launcher and the real image under
        # one versioned framework root; nothing else is admitted.
        root = framework_root(declared_real)
        if (sys.platform != "darwin" or root is None
                or framework_root(image) != root
                or not os.path.isfile(image)
                or os.path.islink(image)
                or not native_magic(image)):
            die(2, "builder executing image does not match the declared path")
    if sys.prefix != sys.base_prefix:
        die(2, "builder interpreter runs inside a virtual environment")
    for entry in sys.path:
        base = os.path.basename(entry.rstrip(os.sep))
        if base in ("site-packages", "dist-packages"):
            die(2, "builder interpreter carries a third-party path entry")
    if "yaml" in sys.modules:
        die(2, "builder interpreter preloaded a yaml module")


def read_sdist(path):
    """Open once, no-follow, verify from the retained descriptor, extract from it."""
    try:
        fd = os.open(path, os.O_RDONLY | getattr(os, "O_NOFOLLOW", 0))
    except OSError:
        die(3, "source distribution could not be opened")
    try:
        info = os.fstat(fd)
        if not stat.S_ISREG(info.st_mode):
            die(3, "source distribution is not a regular file")
        if info.st_uid not in (os.geteuid(), 0):
            die(3, "source distribution has an unexpected owner")
        if stat.S_IMODE(info.st_mode) != EXACT_FILE_MODE:
            die(3, "source distribution mode is not exactly 0644")
        declared_size = info.st_size
        chunks = []
        while True:
            chunk = os.read(fd, 1 << 20)
            if not chunk:
                break
            chunks.append(chunk)
        data = b"".join(chunks)
        if len(data) != declared_size:
            die(3, "source distribution read short of its declared size")
        if sha256_bytes(data) != UPSTREAM_SDIST_SHA256:
            die(3, "source distribution digest does not match the pinned value")
        os.lseek(fd, 0, 0)
        handle = os.fdopen(fd, "rb")
        fd = None
        return data, handle
    finally:
        if fd is not None:
            os.close(fd)


def select_members(archive):
    members = archive.getmembers()
    if not members:
        die(3, "source distribution contains no members")
    tops = set()
    for member in members:
        name = member.name
        if name.startswith("/") or ".." in name.split("/"):
            die(3, "source distribution member escapes its root")
        if member.issym() or member.islnk() or member.isdev():
            die(3, "source distribution member is a link or device")
        tops.add(name.split("/", 1)[0])
    if len(tops) != 1:
        die(3, "source distribution has no single top-level directory")
    top = tops.pop()
    expected = "%s-%s" % (UPSTREAM_NAME, UPSTREAM_VERSION)
    if top.lower() != expected.lower():
        die(3, "source distribution top-level directory is unexpected")

    package_prefix = "%s/lib/yaml/" % top
    licence_path = "%s/%s" % (top, LICENCE_NAME)
    selected = []
    licence_member = None
    for member in members:
        if member.name == licence_path:
            licence_member = member
            continue
        if not member.name.startswith(package_prefix):
            continue
        leaf = member.name[len(package_prefix):]
        if "/" in leaf:
            continue
        if leaf.endswith(REJECTED_SUFFIXES):
            die(3, "source distribution selection contains an excluded class")
        if not leaf.endswith(".py"):
            continue
        selected.append(member)
    if licence_member is None:
        die(3, "source distribution carries no licence file")
    if not selected:
        die(3, "source distribution carries no pure-Python package members")
    for member in selected + [licence_member]:
        if not member.isfile():
            die(3, "selected member is not a regular file")
        if member.mode & 0o7133:
            die(3, "selected member %s has mode %s" % (member.name, oct(member.mode)))
    selected.sort(key=lambda item: item.name)
    return top, selected, licence_member


def build_archive(archive_path, package_prefix_len, selected, extract):
    entries = []
    seen = set()
    with zipfile.ZipFile(archive_path, "w", compression=zipfile.ZIP_STORED) as zf:
        zf.comment = b""
        for member in selected:
            arcname = "yaml/" + member.name[package_prefix_len:]
            if arcname in seen:
                die(3, "duplicate member name in the selection")
            seen.add(arcname)
            payload = extract(member)
            info = zipfile.ZipInfo(arcname, date_time=ZIP_EPOCH)
            info.create_system = 3
            info.external_attr = EXACT_FILE_MODE << 16
            info.compress_type = zipfile.ZIP_STORED
            info.extra = b""
            info.comment = b""
            zf.writestr(info, payload)
            entries.append({
                "path": arcname,
                "size_bytes": len(payload),
                "mode": "0644",
                "sha256": sha256_bytes(payload),
            })
    entries.sort(key=lambda item: item["path"])
    return entries


def write_exact(path, payload):
    """Write, then re-verify mode and size on the retained write descriptor."""
    fd = os.open(
        path,
        os.O_WRONLY | os.O_CREAT | os.O_TRUNC | getattr(os, "O_NOFOLLOW", 0),
        EXACT_FILE_MODE,
    )
    try:
        view = memoryview(payload)
        while view:
            written = os.write(fd, view)
            if written <= 0:
                die(4, "short write while materializing an output")
            view = view[written:]
        os.fsync(fd)
        os.fchmod(fd, EXACT_FILE_MODE)
        info = os.fstat(fd)
        if not stat.S_ISREG(info.st_mode):
            die(4, "output is not a regular file after write")
        if stat.S_IMODE(info.st_mode) != EXACT_FILE_MODE:
            die(4, "output mode is not exactly 0644 after write")
        if info.st_size != len(payload):
            die(4, "output size does not match the written payload")
    finally:
        os.close(fd)


def read_exact(path):
    try:
        with open(path, "rb") as handle:
            return handle.read()
    except OSError:
        die(4, "an expected artefact could not be read")


def produce(sdist_path, release_timestamp, out_dir, builder_path):
    data, handle = read_sdist(sdist_path)
    try:
        try:
            archive = tarfile.open(fileobj=handle, mode="r:*")
        except tarfile.TarError:
            die(3, "source distribution is not a readable archive")
        with archive:
            top, selected, licence_member = select_members(archive)
            package_prefix_len = len("%s/lib/yaml/" % top)

            def extract(member):
                stream = archive.extractfile(member)
                if stream is None:
                    die(3, "selected member could not be extracted")
                with stream:
                    return stream.read()

            licence_bytes = extract(licence_member)
            os.makedirs(out_dir, exist_ok=True)
            archive_path = os.path.join(out_dir, ARCHIVE_NAME)
            licence_path = os.path.join(out_dir, LICENCE_NAME)
            manifest_path = os.path.join(out_dir, MANIFEST_NAME)
            if os.path.lexists(archive_path):
                os.unlink(archive_path)
            entries = build_archive(
                archive_path, package_prefix_len, selected, extract,
            )
    finally:
        handle.close()

    archive_bytes = read_exact(archive_path)
    # Re-materialize the archive through the exact-mode writer so every output of
    # this builder carries the same verified mode contract.
    write_exact(archive_path, archive_bytes)
    write_exact(licence_path, licence_bytes)

    builder_bytes = read_exact(builder_path)
    manifest = {
        "schema_version": "1.0.0",
        "upstream": {
            "name": UPSTREAM_NAME,
            "version": UPSTREAM_VERSION,
            "license": UPSTREAM_LICENSE,
            "canonical_source_url": UPSTREAM_CANONICAL_SOURCE_URL,
            "source_filename": UPSTREAM_SOURCE_FILENAME,
            "sdist_sha256": UPSTREAM_SDIST_SHA256,
            "sdist_size_bytes": len(data),
            "release_timestamp": release_timestamp,
            "requires_python": UPSTREAM_REQUIRES_PYTHON,
        },
        "framework": {
            "supported_cpython_minors": list(FRAMEWORK_SUPPORTED_MINORS),
            "support_boundary_note": FRAMEWORK_SUPPORT_BOUNDARY_NOTE,
            "builder_cpython": BUILDER_CPYTHON,
        },
        "licence": {
            "path": LICENCE_REL,
            "sha256": sha256_bytes(licence_bytes),
            "size_bytes": len(licence_bytes),
            "mode": "0644",
        },
        "builder": {
            "path": BUILDER_REL,
            "sha256": sha256_bytes(builder_bytes),
            "size_bytes": len(builder_bytes),
            "mode": "0755",
        },
        "archive": {
            "format": "zip",
            "compression": "stored",
            "member_order": "sorted-by-name",
            "member_timestamp": ZIP_EPOCH_LABEL,
            "member_mode": "0644",
            "members": entries,
            "excluded_classes": list(EXCLUDED_CLASSES),
        },
        "output": {
            "path": OUTPUT_REL,
            "size_bytes": len(archive_bytes),
            "sha256": sha256_bytes(archive_bytes),
            "mode": "0644",
        },
        "rebuild": {
            "command": REBUILD_COMMAND,
            "network_required": False,
        },
    }
    manifest_bytes = (
        json.dumps(
            manifest, sort_keys=True, indent=2, separators=(",", ": "),
            ensure_ascii=True,
        ) + "\n"
    ).encode("ascii")
    write_exact(manifest_path, manifest_bytes)
    return {
        ARCHIVE_NAME: (archive_path, archive_bytes),
        LICENCE_NAME: (licence_path, licence_bytes),
        MANIFEST_NAME: (manifest_path, manifest_bytes),
    }


def main():
    declared = sys.argv[1]
    sdist_path = sys.argv[2]
    release_timestamp = sys.argv[3]
    out_dir = sys.argv[4]
    mode = sys.argv[5]
    builder_path = sys.argv[6]

    assert_pinned_interpreter(declared)

    if not TIMESTAMP_RE.match(release_timestamp):
        die(1, "release timestamp is malformed")

    if mode == "check":
        with tempfile.TemporaryDirectory(prefix="gaai-yaml-runtime-check-") as tmp:
            produced = produce(sdist_path, release_timestamp, tmp, builder_path)
            differences = []
            for name, (_path, payload) in sorted(produced.items()):
                current = os.path.join(out_dir, name)
                try:
                    with open(current, "rb") as handle:
                        existing = handle.read()
                except OSError:
                    differences.append(name)
                    continue
                if existing != payload:
                    differences.append(name)
            if differences:
                die(4, "rebuild differs for: %s" % ", ".join(differences))
        sys.stdout.write("check ok\n")
        return

    produced = produce(sdist_path, release_timestamp, out_dir, builder_path)
    for name, (path, payload) in sorted(produced.items()):
        sys.stdout.write(
            "%s %d %s\n" % (path, len(payload), sha256_bytes(payload))
        )


main()
PYEOF

# Exactly one interpreter process performs the whole build: attestation, source
# verification, extraction and output materialization.
"$_YR_BUILDER_PY" -I -S -B -c "$_YR_BUILD_PROGRAM" \
  "$_YR_BUILDER_PY" "$SDIST" "$RELEASE_TIMESTAMP" "$OUT_DIR" "$BUILD_MODE" \
  "$_YR_BUILDER_SELF"
