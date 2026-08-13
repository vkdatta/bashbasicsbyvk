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
        printf '%s\n' "1. Version Files"
        printf '%s\n' "2. Reset Versioning"
        printf '%s\n' "q. Quit"
        printf '\n'

        local choice
        read -r -p "Select an option: " choice

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

SKIP_DIRS = {
    ".git",
    ".svn",
    ".hg",
    "__pycache__",
    "node_modules",
}

VERSION_RE = re.compile(
    r"^(.*)_v([0-9]+)(\.[^.]*)$"
)

QUOTED_RE = re.compile(
    r"""(["'`])([^"'`\r\n]*)\1"""
)

PATH_RE = re.compile(
    r"""(?<![\w$])((?:\.{0,2}/|/)[A-Za-z0-9_@.\-~/\\]+)(?![\w$])"""
)


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

        dirnames[:] = [
            name
            for name in dirnames
            if name not in SKIP_DIRS
        ]

        for filename in filenames:
            path = (current / filename).resolve()

            if not inside(path, BOUNDARY):
                continue

            if SCRIPT_PATH is not None and path == SCRIPT_PATH:
                continue

            result.append(path)

    return sorted(set(result))


def collect_target_files():
    return [
        path
        for path in collect_files(TARGET)
        if inside(path, TARGET)
    ]


def is_binary(path):
    try:
        data = path.read_bytes()[:8192]
    except OSError:
        return True

    return b"\x00" in data


def split_reference(reference):
    value = reference.strip()

    if not value:
        return None

    if value.startswith((
        "http://",
        "https://",
        "ftp://",
        "ftps://",
        "data:",
        "mailto:",
        "javascript:",
        "#",
    )):
        return None

    value = value.split("?", 1)[0]
    value = value.split("#", 1)[0]

    if not value:
        return None

    return value


def resolve_reference(reference, source):
    value = split_reference(reference)

    if value is None:
        return []

    if value.startswith("/"):
        return [Path(value).resolve()]

    result = []

    candidate = (source.parent / value).resolve()

    if inside(candidate, BOUNDARY):
        result.append(candidate)

    return result


def resolve_bare_reference(reference, source):
    value = split_reference(reference)

    if value is None:
        return []

    if "/" in value or "\\" in value:
        return []

    candidate = (source.parent / value).resolve()

    if inside(candidate, BOUNDARY):
        return [candidate]

    return []


def relative_reference(old_path, new_path, source, original):
    if original.startswith("/"):
        return str(new_path)

    result = os.path.relpath(
        new_path,
        start=source.parent
    ).replace(os.sep, "/")

    if original.startswith("./") and not result.startswith("."):
        result = "./" + result

    return result


def update_file(source, mapping):
    if is_binary(source):
        return False

    try:
        text = source.read_text(
            encoding="utf-8"
        )
    except (
        OSError,
        UnicodeDecodeError,
    ):
        return False

    original = text

    def quoted_replace(match):
        quote = match.group(1)
        reference = match.group(2)

        candidates = resolve_reference(
            reference,
            source
        )

        if not candidates:
            candidates = resolve_bare_reference(
                reference,
                source
            )

        for candidate in candidates:
            if candidate in mapping:
                return (
                    quote
                    + relative_reference(
                        candidate,
                        mapping[candidate],
                        source,
                        reference
                    )
                    + quote
                )

        return match.group(0)

    text = QUOTED_RE.sub(
        quoted_replace,
        text
    )

    def path_replace(match):
        reference = match.group(1)

        for candidate in resolve_reference(
            reference,
            source
        ):
            if candidate in mapping:
                return relative_reference(
                    candidate,
                    mapping[candidate],
                    source,
                    reference
                )

        return reference

    text = PATH_RE.sub(
        path_replace,
        text
    )

    if text == original:
        return False

    temporary = source.with_name(
        f".{source.name}.bvk-versioning-{os.getpid()}"
    )

    try:
        temporary.write_text(
            text,
            encoding="utf-8",
            newline=""
        )

        os.replace(
            temporary,
            source
        )

    finally:
        if temporary.exists():
            temporary.unlink()

    return True


all_files = collect_files(BOUNDARY)
target_files = collect_target_files()

candidates = [
    path
    for path in target_files
    if not VERSION_RE.match(path.name)
]

if not candidates:
    print()
    print("No unversioned files found in TARGET.")
    sys.exit(0)

reserved = set(all_files)

plan = []

for old_path in candidates:
    number = 1

    while True:
        new_name = (
            f"{old_path.stem}_v{number}"
            f"{old_path.suffix}"
        )

        new_path = (
            old_path.parent / new_name
        ).resolve()

        if new_path not in reserved:
            break

        number += 1

    reserved.add(new_path)

    plan.append(
        (
            old_path,
            new_path
        )
    )

print()
print("VERSIONING PLAN")
print("=" * 80)
print()

for old_path, new_path in plan:
    print(f"OLD : {old_path}")
    print(f"NEW : {new_path}")
    print()

print("=" * 80)
print(f"TARGET files to rename: {len(plan)}")
print(f"REFERENCE search root:  {BOUNDARY}")
print()

answer = input(
    "Proceed? [y/N]: "
).strip().lower()

if answer != "y":
    print("Cancelled.")
    sys.exit(0)

mapping = {
    old.resolve(): new.resolve()
    for old, new in plan
}

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
    if not inside(old_path, TARGET):
        print()
        print("ABORTED.")
        print("Attempted rename outside TARGET:")
        print(f"  {old_path}")
        sys.exit(2)

    if not inside(new_path, TARGET):
        print()
        print("ABORTED.")
        print("Attempted destination outside TARGET:")
        print(f"  {new_path}")
        sys.exit(2)

    if not old_path.exists():
        print()
        print("ABORTED.")
        print("Source disappeared:")
        print(f"  {old_path}")
        sys.exit(2)

    if new_path.exists():
        print()
        print("ABORTED.")
        print("Destination exists:")
        print(f"  {new_path}")
        sys.exit(2)

    old_path.rename(new_path)

    renamed.append(
        (
            old_path,
            new_path
        )
    )

    print(f"{old_path}")
    print(f"  -> {new_path}")

print()
print("VERIFYING...")
print()

errors = []

for old_path, new_path in renamed:
    if old_path.exists():
        errors.append(
            f"Old path still exists: {old_path}"
        )

    if not new_path.exists():
        errors.append(
            f"New path missing: {new_path}"
        )

    if not inside(new_path, TARGET):
        errors.append(
            f"New path escaped TARGET: {new_path}"
        )

if errors:
    print("VERIFICATION FAILED")
    print()

    for error in errors:
        print(f"  {error}")

    sys.exit(2)

print("Versioning completed successfully.")
print()
print(f"Renamed files      : {len(renamed)}")
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

SKIP_DIRS = {
    ".git",
    ".svn",
    ".hg",
    "__pycache__",
    "node_modules",
}

VERSION_RE = re.compile(
    r"^(.*)_v([0-9]+)(\.[^.]*)$"
)

QUOTED_RE = re.compile(
    r"""(["'`])([^"'`\r\n]*)\1"""
)

PATH_RE = re.compile(
    r"""(?<![\w$])((?:\.{0,2}/|/)[A-Za-z0-9_@.\-~/\\]+)(?![\w$])"""
)


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

        dirnames[:] = [
            name
            for name in dirnames
            if name not in SKIP_DIRS
        ]

        for filename in filenames:
            path = (current / filename).resolve()

            if not inside(path, BOUNDARY):
                continue

            if SCRIPT_PATH is not None and path == SCRIPT_PATH:
                continue

            result.append(path)

    return sorted(set(result))


def is_binary(path):
    try:
        data = path.read_bytes()[:8192]
    except OSError:
        return True

    return b"\x00" in data


def base_path(path):
    match = VERSION_RE.match(path.name)

    if not match:
        return None

    return (
        path.parent
        / f"{match.group(1)}{match.group(3)}"
    ).resolve()


def resolve_reference(reference, source):
    value = reference.strip()

    if not value:
        return []

    if value.startswith((
        "http://",
        "https://",
        "ftp://",
        "ftps://",
        "data:",
        "mailto:",
        "javascript:",
        "#",
    )):
        return []

    value = value.split("?", 1)[0]
    value = value.split("#", 1)[0]

    if not value:
        return []

    if value.startswith("/"):
        candidate = Path(value).resolve()
    else:
        candidate = (
            source.parent / value
        ).resolve()

    if inside(candidate, BOUNDARY):
        return [candidate]

    return []


def replacement(old_path, new_path, source, original):
    if original.startswith("/"):
        return str(new_path)

    result = os.path.relpath(
        new_path,
        start=source.parent
    ).replace(os.sep, "/")

    if original.startswith("./") and not result.startswith("."):
        result = "./" + result

    return result


def update_file(source, mapping):
    if is_binary(source):
        return False

    try:
        text = source.read_text(
            encoding="utf-8"
        )
    except (
        OSError,
        UnicodeDecodeError,
    ):
        return False

    original = text

    def quoted_replace(match):
        quote = match.group(1)
        reference = match.group(2)

        for candidate in resolve_reference(
            reference,
            source
        ):
            if candidate in mapping:
                return (
                    quote
                    + replacement(
                        candidate,
                        mapping[candidate],
                        source,
                        reference
                    )
                    + quote
                )

        return match.group(0)

    text = QUOTED_RE.sub(
        quoted_replace,
        text
    )

    def path_replace(match):
        reference = match.group(1)

        for candidate in resolve_reference(
            reference,
            source
        ):
            if candidate in mapping:
                return replacement(
                    candidate,
                    mapping[candidate],
                    source,
                    reference
                )

        return reference

    text = PATH_RE.sub(
        path_replace,
        text
    )

    if text == original:
        return False

    temporary = source.with_name(
        f".{source.name}.bvk-reset-{os.getpid()}"
    )

    try:
        temporary.write_text(
            text,
            encoding="utf-8",
            newline=""
        )

        os.replace(
            temporary,
            source
        )

    finally:
        if temporary.exists():
            temporary.unlink()

    return True


all_files = collect_files(BOUNDARY)

target_files = [
    path
    for path in all_files
    if inside(path, TARGET)
]

groups = {}

for path in target_files:
    match = VERSION_RE.match(path.name)

    if not match:
        continue

    base = base_path(path)

    if base is None:
        continue

    groups.setdefault(base, []).append(path)

if not groups:
    print()
    print("No versioned files found in TARGET.")
    sys.exit(0)

safe_plan = []
blocked = []

for base, versions in sorted(
    groups.items(),
    key=lambda item: str(item[0])
):
    versions.sort(
        key=lambda p: int(
            VERSION_RE.match(p.name).group(2)
        )
    )

    if base.exists():
        blocked.append(
            (
                base,
                versions,
                "base file already exists"
            )
        )
        continue

    if len(versions) != 1:
        blocked.append(
            (
                base,
                versions,
                "multiple versions exist and cannot be safely collapsed"
            )
        )
        continue

    safe_plan.append(
        (
            versions[0],
            base
        )
    )

print()
print("RESET PLAN")
print("=" * 80)
print()

for old_path, new_path in safe_plan:
    print(f"OLD : {old_path}")
    print(f"NEW : {new_path}")
    print()

if blocked:
    print("BLOCKED")
    print("-" * 80)
    print()

    for base, versions, reason in blocked:
        print(f"BASE   : {base}")
        print(f"REASON : {reason}")

        for version in versions:
            print(f"VERSION: {version}")

        print()

print("=" * 80)
print(f"Files to reset : {len(safe_plan)}")
print(f"Blocked groups : {len(blocked)}")
print()

if not safe_plan:
    print("Nothing can be safely reset.")
    sys.exit(0)

answer = input(
    "Proceed? [y/N]: "
).strip().lower()

if answer != "y":
    print("Cancelled.")
    sys.exit(0)

mapping = {
    old.resolve(): new.resolve()
    for old, new in safe_plan
}

print()
print("Scanning references throughout boundary...")
print()

reference_changes = []

for source in all_files:
    if update_file(source, mapping):
        reference_changes.append(source)
        print(f"UPDATED: {source}")

for old_path, new_path in safe_plan:
    if new_path.exists():
        print()
        print("ABORTED.")
        print("Destination appeared:")
        print(f"  {new_path}")
        sys.exit(2)

print()
print("Resetting TARGET files...")
print()

renamed = []

for old_path, new_path in safe_plan:
    if not inside(old_path, TARGET):
        print()
        print("ABORTED.")
        print("Source outside TARGET:")
        print(f"  {old_path}")
        sys.exit(2)

    if not inside(new_path, TARGET):
        print()
        print("ABORTED.")
        print("Destination outside TARGET:")
        print(f"  {new_path}")
        sys.exit(2)

    if not old_path.exists():
        print()
        print("ABORTED.")
        print("Source disappeared:")
        print(f"  {old_path}")
        sys.exit(2)

    if new_path.exists():
        print()
        print("ABORTED.")
        print("Destination exists:")
        print(f"  {new_path}")
        sys.exit(2)

    old_path.rename(new_path)

    renamed.append(
        (
            old_path,
            new_path
        )
    )

    print(f"{old_path}")
    print(f"  -> {new_path}")

print()
print("VERIFYING...")
print()

errors = []

for old_path, new_path in renamed:
    if old_path.exists():
        errors.append(
            f"Old path still exists: {old_path}"
        )

    if not new_path.exists():
        errors.append(
            f"New path missing: {new_path}"
        )

if errors:
    print("VERIFICATION FAILED")
    print()

    for error in errors:
        print(f"  {error}")

    sys.exit(2)

print("Reset completed successfully.")
print()
print(f"Reset files        : {len(renamed)}")
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
        read -r -p "Press Enter to return to menu..." _
    done
}