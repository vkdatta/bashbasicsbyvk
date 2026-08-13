version_manager() {
    local TARGET
    local BOUNDARY
    local SCRIPT_PATH

    if [[ -z "${path:-}" ]]; then
        printf '%s\n' "ERROR: File manager target path variable 'path' is not available."
        return 1
    fi

    if [[ -z "${BVK_FILEMANAGER_BOUNDARY:-}" ]]; then
        printf '%s\n' "ERROR: File manager boundary is not available."
        printf '%s\n' "The file manager must export BVK_FILEMANAGER_BOUNDARY."
        return 1
    fi

    TARGET="$(realpath -e -- "$path" 2>/dev/null)" || {
        printf '%s\n' "ERROR: Cannot resolve file manager target:"
        printf '  %s\n' "$path"
        return 1
    }

    BOUNDARY="$(realpath -e -- "$BVK_FILEMANAGER_BOUNDARY" 2>/dev/null)" || {
        printf '%s\n' "ERROR: Cannot resolve file manager boundary:"
        printf '  %s\n' "$BVK_FILEMANAGER_BOUNDARY"
        return 1
    }

    if [[ ! -d "$TARGET" ]]; then
        printf '%s\n' "ERROR: File manager target is not a directory:"
        printf '  %s\n' "$TARGET"
        return 1
    fi

    if [[ ! -d "$BOUNDARY" ]]; then
        printf '%s\n' "ERROR: File manager boundary is not a directory:"
        printf '  %s\n' "$BOUNDARY"
        return 1
    fi

    case "$TARGET" in
        "$BOUNDARY"|"$BOUNDARY"/*)
            ;;
        *)
            printf '%s\n' "ERROR: Target is outside the file manager boundary."
            printf '  Boundary: %s\n' "$BOUNDARY"
            printf '  Target:   %s\n' "$TARGET"
            return 1
            ;;
    esac

    SCRIPT_PATH=""

    if [[ -n "${BASH_SOURCE[0]:-}" ]]; then
        SCRIPT_PATH="$(realpath -e -- "${BASH_SOURCE[0]}" 2>/dev/null || true)"
    fi

    if ! command -v python3 >/dev/null 2>&1; then
        printf '%s\n' "ERROR: python3 is required."
        return 1
    fi

    while true; do
        clear

        printf '%s\n' "=========================================="
        printf '%s\n' "         FILE VERSIONING MANAGER"
        printf '%s\n' "=========================================="
        printf '\n'
        printf 'Boundary:\n  %s\n' "$BOUNDARY"
        printf '\n'
        printf 'Target:\n  %s\n' "$TARGET"
        printf '\n'
        printf '%s\n' "─────────────────────────────"
        printf '%s\n' "1. Version Files"
        printf '%s\n' "2. Reset Versioning"
        printf '%s\n' "─────────────────────────────"
        printf '%s\n' "q. Quit"
        printf '\n'

        local choice
        read -r -p "Select an option: " choice </dev/tty || return 0

        case "$choice" in
            1)
                python3 - "$BOUNDARY" "$TARGET" "$SCRIPT_PATH" <<'PY'
import os
import re
import sys
from pathlib import Path

BOUNDARY = Path(sys.argv[1]).resolve()
TARGET = Path(sys.argv[2]).resolve()
SCRIPT_PATH = Path(sys.argv[3]).resolve() if sys.argv[3] else None

SKIP_DIRS = {".git", ".svn", ".hg", "__pycache__", "node_modules"}

VERSION_RE = re.compile(r"^(.*)_v([0-9]+)(\.[^.]*)$")

QUOTED_RE = re.compile(r"""(["'`])([^"'`\r\n]*)\1""")
PATH_RE = re.compile(r"""(?<![\w$])((?:\.{0,2}/|/)[A-Za-z0-9_@.\-~/\\]+)(?![\w$])""")


def inside(path, root):
    try:
        path.resolve().relative_to(root.resolve())
        return True
    except ValueError:
        return False


def collect_files(root):
    result = []
    for dirpath, dirnames, filenames in os.walk(root):
        current = Path(dirpath).resolve()
        dirnames[:] = [name for name in dirnames if name not in SKIP_DIRS]
        for filename in filenames:
            item = (current / filename).resolve()
            if not inside(item, BOUNDARY):
                continue
            if SCRIPT_PATH is not None and item == SCRIPT_PATH:
                continue
            result.append(item)
    return sorted(set(result))


def is_binary(path):
    try:
        return b"\x00" in path.read_bytes()[:8192]
    except OSError:
        return True


def split_reference(reference):
    value = reference.strip()
    if not value or value.startswith(("http://", "https://", "ftp://", "ftps://", "data:", "mailto:", "javascript:", "#")):
        return None
    value = value.split("?", 1)[0]
    value = value.split("#", 1)[0]
    return value or None


def resolve_reference(reference, source):
    value = split_reference(reference)
    if value is None:
        return []
    candidate = Path(value).resolve() if value.startswith("/") else (source.parent / value).resolve()
    return [candidate] if inside(candidate, BOUNDARY) else []


def relative_reference(old_path, new_path, source, original):
    if original.startswith("/"):
        return str(new_path)
    result = os.path.relpath(new_path, start=source.parent).replace(os.sep, "/")
    if original.startswith("./") and not result.startswith("."):
        result = "./" + result
    return result


def update_file(source, mapping):
    if is_binary(source):
        return False
    try:
        text = source.read_text(encoding="utf-8")
    except (OSError, UnicodeDecodeError):
        return False
    original = text

    def quoted_replace(match):
        quote = match.group(1)
        reference = match.group(2)
        for candidate in resolve_reference(reference, source):
            if candidate in mapping:
                return quote + relative_reference(candidate, mapping[candidate], source, reference) + quote
        return match.group(0)

    text = QUOTED_RE.sub(quoted_replace, text)

    def path_replace(match):
        reference = match.group(1)
        for candidate in resolve_reference(reference, source):
            if candidate in mapping:
                return relative_reference(candidate, mapping[candidate], source, reference)
        return reference

    text = PATH_RE.sub(path_replace, text)

    if text == original:
        return False

    temporary = source.with_name(f".{source.name}.bvk-versioning-{os.getpid()}")
    try:
        temporary.write_text(text, encoding="utf-8", newline="")
        os.replace(temporary, source)
    finally:
        if temporary.exists():
            temporary.unlink()
    return True


all_files = collect_files(BOUNDARY)
target_files = [item for item in all_files if inside(item, TARGET)]

existing = set(all_files)
unversioned = {}
versioned = {}

for item in target_files:
    match = VERSION_RE.match(item.name)
    if match:
        base = (item.parent / f"{match.group(1)}{match.group(3)}").resolve()
        versioned.setdefault(base, []).append((int(match.group(2)), item))
    else:
        unversioned[item.resolve()] = item.resolve()

collision_groups = []
plan = []

for base, versions in sorted(versioned.items(), key=lambda x: str(x[0])):
    versions.sort(key=lambda x: x[0])

    if base in unversioned:
        collision_groups.append({
            "base": base,
            "base_exists": True,
            "versions": [item for _, item in versions],
            "reason": "Both the unversioned base file and one or more versioned files exist."
        })
        continue

    latest_number, latest_path = versions[-1]
    next_number = latest_number + 1
    while True:
        candidate = (latest_path.parent / f"{base.stem}_v{next_number}{base.suffix}").resolve()
        if candidate not in existing:
            break
        next_number += 1
    plan.append((latest_path, candidate))
    existing.add(candidate)

for base in sorted(unversioned):
    candidate = (base.parent / f"{base.stem}_v1{base.suffix}").resolve()
    if candidate in existing:
        collision_groups.append({
            "base": base,
            "base_exists": True,
            "versions": [item for _, item in sorted(versioned.get(base, []))],
            "reason": "The first version destination already exists."
        })
        continue
    plan.append((base, candidate))
    existing.add(candidate)

print()
print("VERSIONING PLAN")
print("=" * 80)
print()

if plan:
    for old_path, new_path in plan:
        print(f"OLD : {old_path}")
        print(f"NEW : {new_path}")
        print()
else:
    print("No files are eligible for versioning.")
    print()

if collision_groups:
    print("COLLISIONS DETECTED")
    print("-" * 80)
    for collision in collision_groups:
        print(f"BASE : {collision['base']}")
        print(f"REASON: {collision['reason']}")
        if collision["versions"]:
            print("VERSIONS:")
            for item in collision["versions"]:
                print(f"  {item}")
        print()
    print("Colliding file chains will not be modified.")
    print()

print("=" * 80)
print(f"TARGET files to rename: {len(plan)}")
print(f"Collisions skipped:     {len(collision_groups)}")
print(f"REFERENCE search root:  {BOUNDARY}")
print()

if not plan:
    if collision_groups:
        print("No files were changed because only collision states were found.")
    sys.exit(0)

try:
    with open("/dev/tty", "r", encoding="utf-8") as tty:
        print("Proceed? [y/N]: ", end="", flush=True)
        answer = tty.readline().strip().lower()
except OSError:
    print("ERROR: Unable to read confirmation from terminal.")
    sys.exit(1)

if answer != "y":
    print("Cancelled.")
    sys.exit(0)

mapping = {old.resolve(): new.resolve() for old, new in plan}

print()
print("Scanning references throughout boundary...")
print()

reference_changes = []

for source in all_files:
    if update_file(source, mapping):
        reference_changes.append(source)
        print(f"UPDATED: {source}")

for old_path, new_path in plan:
    if new_path.exists():
        print()
        print("ABORTED.")
        print("A destination appeared after reference processing:")
        print(f"  {new_path}")
        sys.exit(2)

print()
print("Renaming TARGET files...")
print()

renamed = []

for old_path, new_path in plan:
    if not inside(old_path, TARGET) or not inside(new_path, TARGET):
        print()
        print("ABORTED.")
        print("A rename escaped TARGET.")
        sys.exit(2)
    if not old_path.exists() or new_path.exists():
        print()
        print("ABORTED.")
        print(f"Source or destination state changed: {old_path} -> {new_path}")
        sys.exit(2)
    old_path.rename(new_path)
    renamed.append((old_path, new_path))
    print(f"{old_path}")
    print(f"  -> {new_path}")

print()
print("VERIFYING...")
print()

errors = []

for old_path, new_path in renamed:
    if old_path.exists():
        errors.append(f"Old path still exists: {old_path}")
    if not new_path.exists():
        errors.append(f"New path missing: {new_path}")

if errors:
    print("VERIFICATION FAILED")
    for error in errors:
        print(f"  {error}")
    sys.exit(2)

print("Versioning completed successfully.")
print()
print(f"Renamed files      : {len(renamed)}")
print(f"Collisions skipped : {len(collision_groups)}")
print(f"Files with changes : {len(reference_changes)}")
print(f"Reference boundary : {BOUNDARY}")
print(f"Rename target      : {TARGET}")

PY
                ;;

            2)
                python3 - "$BOUNDARY" "$TARGET" "$SCRIPT_PATH" <<'PY'
import os
import re
import sys
from pathlib import Path

BOUNDARY = Path(sys.argv[1]).resolve()
TARGET = Path(sys.argv[2]).resolve()
SCRIPT_PATH = Path(sys.argv[3]).resolve() if sys.argv[3] else None

SKIP_DIRS = {".git", ".svn", ".hg", "__pycache__", "node_modules"}

VERSION_RE = re.compile(r"^(.*)_v([0-9]+)(\.[^.]*)$")

QUOTED_RE = re.compile(r"""(["'`])([^"'`\r\n]*)\1""")
PATH_RE = re.compile(r"""(?<![\w$])((?:\.{0,2}/|/)[A-Za-z0-9_@.\-~/\\]+)(?![\w$])""")


def inside(path, root):
    try:
        path.resolve().relative_to(root.resolve())
        return True
    except ValueError:
        return False


def collect_files(root):
    result = []
    for dirpath, dirnames, filenames in os.walk(root):
        current = Path(dirpath).resolve()
        dirnames[:] = [name for name in dirnames if name not in SKIP_DIRS]
        for filename in filenames:
            item = (current / filename).resolve()
            if not inside(item, BOUNDARY):
                continue
            if SCRIPT_PATH is not None and item == SCRIPT_PATH:
                continue
            result.append(item)
    return sorted(set(result))


def is_binary(path):
    try:
        return b"\x00" in path.read_bytes()[:8192]
    except OSError:
        return True


def resolve_reference(reference, source):
    value = reference.strip()
    if not value or value.startswith(("http://", "https://", "ftp://", "ftps://", "data:", "mailto:", "javascript:", "#")):
        return []
    value = value.split("?", 1)[0].split("#", 1)[0]
    if not value:
        return []
    candidate = Path(value).resolve() if value.startswith("/") else (source.parent / value).resolve()
    return [candidate] if inside(candidate, BOUNDARY) else []


def relative_reference(new_path, source, original):
    if original.startswith("/"):
        return str(new_path)
    result = os.path.relpath(new_path, start=source.parent).replace(os.sep, "/")
    if original.startswith("./") and not result.startswith("."):
        result = "./" + result
    return result


def update_file(source, mapping):
    if is_binary(source):
        return False
    try:
        text = source.read_text(encoding="utf-8")
    except (OSError, UnicodeDecodeError):
        return False
    original = text

    def quoted_replace(match):
        quote = match.group(1)
        reference = match.group(2)
        for candidate in resolve_reference(reference, source):
            if candidate in mapping:
                return quote + relative_reference(mapping[candidate], source, reference) + quote
        return match.group(0)

    text = QUOTED_RE.sub(quoted_replace, text)

    def path_replace(match):
        reference = match.group(1)
        for candidate in resolve_reference(reference, source):
            if candidate in mapping:
                return relative_reference(mapping[candidate], source, reference)
        return reference

    text = PATH_RE.sub(path_replace, text)

    if text == original:
        return False

    temporary = source.with_name(f".{source.name}.bvk-reset-{os.getpid()}")
    try:
        temporary.write_text(text, encoding="utf-8", newline="")
        os.replace(temporary, source)
    finally:
        if temporary.exists():
            temporary.unlink()
    return True


all_files = collect_files(BOUNDARY)
target_files = [item for item in all_files if inside(item, TARGET)]

unversioned = {item.resolve() for item in target_files if not VERSION_RE.match(item.name)}
chains = {}

for item in target_files:
    match = VERSION_RE.match(item.name)
    if not match:
        continue
    base = (item.parent / f"{match.group(1)}{match.group(3)}").resolve()
    chains.setdefault(base, []).append((int(match.group(2)), item))

plan = []
collision_groups = []

for base, versions in sorted(chains.items(), key=lambda x: str(x[0])):
    versions.sort(key=lambda x: x[0])
    latest_number, latest_path = versions[-1]

    if base in unversioned:
        collision_groups.append({
            "base": base,
            "latest": latest_path,
            "reason": "The unversioned base file already exists."
        })
        continue

    plan.append((latest_path, base))

print()
print("RESET PLAN")
print("=" * 80)
print()

for old_path, new_path in plan:
    print(f"OLD : {old_path}")
    print(f"NEW : {new_path}")
    print()

if collision_groups:
    print("COLLISIONS DETECTED")
    print("-" * 80)
    for collision in collision_groups:
        print(f"BASE   : {collision['base']}")
        print(f"LATEST : {collision['latest']}")
        print(f"REASON : {collision['reason']}")
        print()
    print("Colliding chains will not be modified.")
    print()

print("=" * 80)
print(f"TARGET files to reset: {len(plan)}")
print(f"Collisions skipped:    {len(collision_groups)}")
print(f"REFERENCE search root: {BOUNDARY}")
print()

if not plan:
    if collision_groups:
        print("No files were reset because collision states were found.")
    else:
        print("No versioned files found in TARGET.")
    sys.exit(0)

try:
    with open("/dev/tty", "r", encoding="utf-8") as tty:
        print("Proceed? [y/N]: ", end="", flush=True)
        answer = tty.readline().strip().lower()
except OSError:
    print("ERROR: Unable to read confirmation from terminal.")
    sys.exit(1)

if answer != "y":
    print("Cancelled.")
    sys.exit(0)

mapping = {old.resolve(): new.resolve() for old, new in plan}

print()
print("Scanning references throughout boundary...")
print()

reference_changes = []

for source in all_files:
    if update_file(source, mapping):
        reference_changes.append(source)
        print(f"UPDATED: {source}")

for old_path, new_path in plan:
    if new_path.exists():
        print()
        print("ABORTED.")
        print("A destination appeared after reference processing:")
        print(f"  {new_path}")
        sys.exit(2)

print()
print("Resetting TARGET files...")
print()

renamed = []

for old_path, new_path in plan:
    if not inside(old_path, TARGET) or not inside(new_path, TARGET):
        print()
        print("ABORTED.")
        print("A reset escaped TARGET.")
        sys.exit(2)
    if not old_path.exists() or new_path.exists():
        print()
        print("ABORTED.")
        print(f"Source or destination state changed: {old_path} -> {new_path}")
        sys.exit(2)
    old_path.rename(new_path)
    renamed.append((old_path, new_path))
    print(f"{old_path}")
    print(f"  -> {new_path}")

print()
print("VERIFYING...")
print()

errors = []

for old_path, new_path in renamed:
    if old_path.exists():
        errors.append(f"Old path still exists: {old_path}")
    if not new_path.exists():
        errors.append(f"New path missing: {new_path}")

if errors:
    print("VERIFICATION FAILED")
    for error in errors:
        print(f"  {error}")
    sys.exit(2)

print("Reset completed successfully.")
print()
print(f"Reset files        : {len(renamed)}")
print(f"Collisions skipped : {len(collision_groups)}")
print(f"Files with changes : {len(reference_changes)}")
print(f"Reference boundary : {BOUNDARY}")
print(f"Reset target       : {TARGET}")

PY
                ;;

            q|Q)
                return 0
                ;;

            *)
                printf '%s\n' "Invalid option."
                sleep 1
                ;;
        esac

        printf '\n'
        read -r -p "Press Enter to return to menu..." _ </dev/tty || return 0
    done
}
