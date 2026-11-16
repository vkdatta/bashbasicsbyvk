# bashbasicsbyvk_gitpush.sh - Git Push, a function of the app (Infinity Stones, 4).
# It runs INSIDE the app (no process of its own), so the hint row, cc, the typed commands, u / q and every menu are the app's own.
# The body runs in a subshell (_inf_sub, bashbasicsbyvk_infinity_run.sh): its `exit` / `die` / `set -e` / `trap EXIT` end only the tool.
# Questions go through _bvk_yn / _bvk_menu / _bvk_read directly: there is no second copy of any menu.

bvk_gitpush() { _inf_sub "-Eeo pipefail" _gp_body "$@"; }

_gp_body() {
TARGET="${1:-$(pwd)}"
DEFAULT_COMMIT_MESSAGE="Codebase Updated"

TMP_DIR=""
SWAP_BACKUP=""

# Helpers

    die() {
    echo "ERROR: $*" >&2
    _mc_unwind && exit 42                  # q was typed somewhere below: close up to the main loop (the runner turns 42 into _bvk_quit)
    exit 1
    }

    warn() {
    echo "WARNING: $*"
    }

    _gp_info() {
    echo "INFO: $*"
    }

    ok() {
    echo "OK: $*"
    }

    cleanup() {
    # Temporary staging only.
    # Never automatically delete SWAP_BACKUP here.
    if [[ -n "${TMP_DIR:-}" && -d "$TMP_DIR" ]]; then
        rm -rf -- "$TMP_DIR"
    fi
    }

trap cleanup EXIT

# Shared "type this 6-digit number" gate (also used when deleting locked items): a function of the app (action_confirm_key).
declare -F action_confirm_key >/dev/null ||
    die "bashbasicsbyvk_action_confirm_key.sh not found - cannot ask for confirmation."

# Requirements: git and the GitHub CLI (gh) come from the central dependency registry
# (feature gitpush, bashbasicsbyvk_deps.list): a missing one gets the Installer menu, not a private installer.

_dep_need -c "Pushing to GitHub" gitpush || die "git and the GitHub CLI (gh) are required."
hash -r 2>/dev/null || true

# Resolve target

[[ -d "$TARGET" ]] ||
    die "Target directory does not exist: $TARGET"

TARGET="$(cd "$TARGET" && pwd -P)"

# GitHub authentication

if ! gh auth status --active --hostname github.com >/dev/null 2>&1; then
    die "GitHub CLI is not authenticated.

Run:

  gh auth login"
fi

gh auth setup-git --hostname github.com >/dev/null 2>&1 ||
    die "Could not configure Git to use GitHub CLI credentials."

GH_USER="$(gh api user --jq '.login')" ||
    die "Could not determine GitHub username."

[[ -n "$GH_USER" ]] ||
    die "GitHub username is empty."

# Repository identity

    update_repo_identity() {
    REPO_NAME="$(basename "$TARGET")"

    [[ -n "$REPO_NAME" ]] ||
        die "Could not determine repository name."

    [[ "$REPO_NAME" =~ ^[A-Za-z0-9._-]+$ ]] ||
        die "Invalid GitHub repository name: $REPO_NAME"

    REPO_FULL="$GH_USER/$REPO_NAME"
    REMOTE_URL="https://github.com/$REPO_FULL.git"
    }

update_repo_identity

# Git identity

    check_git_identity() {
    local name
    local email

    name="$(git config user.name 2>/dev/null || true)"
    email="$(git config user.email 2>/dev/null || true)"

    [[ -n "$name" && -n "$email" ]] ||
        die "Git user.name and user.email must be configured.

Run:

  git config --global user.name \"Your Name\"
  git config --global user.email \"you@example.com\""
    }

# Confirmation

# Asks whether the new GitHub repository is private (default) or public; sets VISIBILITY for  gh repo create.
# A yes/no question has NO default: it asks again until the answer is y or n (a bare Enter is not an answer).  Sets ANS to y | n.
    ask_yn() {   # ask_yn "Question?" [-b]   -b: u = one question back (returns 4, ANS empty); without it every non-answer ends the tool
    local ans=""
    # THE app's yes/no menu: the same layout, hint row, cc and commands as every menu of the app
    if _bvk_yn ans "$1" -t "Git push" -i "🚀"; then
        case "$ans" in
            y) ANS=y; return 0 ;;
            n) ANS=n; return 0 ;;
        esac
    fi
    if [ "${2:-}" = -b ] && _bvk_back; then ANS=""; return 4; fi
    die "No answer."
    }

    ask_repo_visibility() {
    ask_yn "Make repository private?"; private_answer="$ANS"

    case "$private_answer" in
        n)
            VISIBILITY="--public"
            ;;
        *)
            VISIBILITY="--private"
            ;;
    esac
    }

    confirm_action() {
    local description="$1"

    action_confirm_key "$description" ||
        die "Confirmation failed."
    }

# GitHub repository existence
#
# IMPORTANT:
# A failed `gh repo view` is NOT automatically treated as
# "repository does not exist".
#
# 404 = nonexistent
# anything else = abort

    github_repo_exists() {
    local response
    local status_line

    if response="$(
        gh repo view "$REPO_FULL" \
            --json name \
            --jq '.name' \
            2>/dev/null
    )"; then

        [[ -n "$response" ]] ||
            die "GitHub returned an empty repository response."

        return 0
    fi

    # `gh repo view` failed.
    # Ask GitHub directly so we can distinguish 404 from
    # authentication, permission, API, network, or server errors.

    response="$(
        gh api "repos/$REPO_FULL" \
            --include \
            --silent \
            2>/dev/null || true
    )"

    status_line="$(
        printf '%s\n' "$response" |
            grep -m1 -E '^HTTP/[0-9.]+ [0-9]{3}([[:space:]]|$)' ||
            true
    )"

    if [[ "$status_line" =~ ^HTTP/[0-9.]+[[:space:]]404([[:space:]]|$) ]]; then
        return 1
    fi

    if [[ -n "$status_line" ]]; then
        die "Could not determine whether GitHub repository exists.

GitHub response:
  $status_line

No repository was created."
    fi

    die "Could not contact GitHub to determine whether repository exists.

No repository was created."
    }

# GitHub repository metadata

    get_repo_metadata() {
    gh repo view "$REPO_FULL" \
        --json isEmpty,defaultBranchRef,url \
        --jq '[.isEmpty, (.defaultBranchRef.name // ""), .url] | @tsv'
    }

# Current branch

    get_current_branch() {
    local branch

    branch="$(git branch --show-current 2>/dev/null || true)"

    if [[ -z "$branch" ]]; then
        branch="$(git symbolic-ref --short HEAD 2>/dev/null || true)"
    fi

    [[ -n "$branch" ]] ||
        die "Could not determine the current Git branch."

    printf '%s\n' "$branch"
    }

# Ensure repository root

    ensure_git_root() {
    local root
    local answer

    root="$(git -C "$TARGET" rev-parse --show-toplevel 2>/dev/null || true)"

    [[ -n "$root" ]] ||
        die "Could not determine Git repository root."

    root="$(cd "$root" && pwd -P)"

    if [[ "$root" != "$TARGET" ]]; then

        echo
        warn "Target is inside an existing Git repository."
        echo
        echo "Git root:"
        echo "  $root"
        echo
        echo "Target:"
        echo "  $TARGET"
        echo

        ask_yn "Use the Git repository root instead?"; answer="$ANS"

        case "$answer" in
            y)
                TARGET="$root"

                # TARGET changed.
                # Recalculate GitHub repository identity.
                update_repo_identity
                ;;
            *)
                die "Target is not the Git repository root."
                ;;
        esac
    fi
    }

# Ensure origin

    ensure_origin() {
    if git remote get-url origin >/dev/null 2>&1; then
        _gp_info "Origin already exists:"
        echo "  $(git remote get-url origin)"
        return 0
    fi

    git remote add origin "$REMOTE_URL"

    ok "Origin added:"
    echo "  $REMOTE_URL"
    }

# Version selection

    select_version() {   # a STEP of create_commit: 0 answered (VERSION set) · 1 u (back) · 3 q / no answer
    local choice=""

    echo
    # THE app's choice menu: u = back, q = quit; a bare Enter takes the highlighted default
    if ! _bvk_menu choice -q "Select version bump type:" -t "Version bump" -d 1 -- \
        "1:Patch  (#patch)" "2:Minor  (#minor)" "3:Major  (#major)" "4:None   (skip the version tag)"; then
        _bvk_back && return 1
        return 3
    fi

    case "$choice" in
        2)
            VERSION="#minor"
            ;;
        3)
            VERSION="#major"
            ;;
        4)
            VERSION=""
            ;;
        1|"")
            VERSION="#patch"
            ;;
        *)
            warn "Invalid option. Defaulting to #patch."
            VERSION="#patch"
            ;;
    esac
    return 0
    }

# Commit

# The three questions of a commit, one step each (they share create_commit's locals):  version → message → "Create this commit?".
# Each returns 0 answered · 1 u (the question before) · 3 q / no / cancelled.
    _gc_s_version() { select_version; }
    _gc_s_message() {
    local _CE_SELECT=0                                  # the message typed before starts selected when u comes back here
    [ -n "$user_msg" ] && _CE_SELECT=1
    echo
    _mc_footer_std -b                                   # the footer every typed-line prompt of the app prints (u q h cc)
    _CM_BACKED=0
    if ! _bvk_read user_msg "Enter commit message [Default: $DEFAULT_COMMIT_MESSAGE]: " -m -i "$user_msg"; then
        [ "${_CM_BACKED:-0}" = 1 ] && return 1
        return 3
    fi
    return 0
    }
    _gc_s_confirm() {
    local rc=0
    final_msg="${user_msg:-$DEFAULT_COMMIT_MESSAGE}"
    if [[ -n "$VERSION" ]]; then
        if [[ "$final_msg" =~ (^|[[:space:]])#(patch|minor|major)([[:space:]]|$) ]]; then
            _gp_info "Commit message already contains a version tag."
        else
            final_msg="$final_msg $VERSION"
        fi
    fi

    echo
    echo "Commit message:"
    echo "  $final_msg"
    echo
    echo "Changes:"
    git status --short
    echo

    ask_yn "Create this commit?" -b || rc=$?
    case "$rc" in
        0) [[ "$ANS" == y ]] && return 0 || return 3 ;;
        4) return 1 ;;
    esac
    return 3
    }

    create_commit() {
    local user_msg=""
    local final_msg=""
    local rc=0

    # FIRST check for actual working-tree/index changes.
    # This must happen BEFORE asking for version bump or commit message.
    git add .

    if git diff --cached --quiet; then
        return 1
    fi

    check_git_identity

    _mc_steps _gc_s_version _gc_s_message _gc_s_confirm || rc=$?
    case "$rc" in
        0) ;;
        1) echo "Commit cancelled (back)."; exit 0 ;;
        2) exit 42 ;;                                       # q: close up to the main loop      # u on the FIRST question: out of the tool, back to the menu it was opened from
        *) die "Commit cancelled." ;;
    esac

    git commit -m "$final_msg" ||
        die "Git commit failed. No push was attempted."

    ok "Commit created."
    return 0
    }

# Push

    push_repository() {
    local branch="$1"
    local push_output
    local local_version
    local remote_version
    local remote_commit
    local remote_author
    local confirmation

    echo
    echo "============================================================"
    echo "Pushing"
    echo "============================================================"

    # Existing upstream:
    # Try the normal push first. If Git rejects it because the remote
    # contains work that is not local, inspect the divergence and offer
    # an explicit, high-friction force-push recovery.
    if git rev-parse --abbrev-ref --symbolic-full-name "@{u}" \
        >/dev/null 2>&1; then

        _gp_info "Upstream exists."
        _gp_info "Running normal git push."

        if push_output="$(git push 2>&1)"; then
            printf '%s\n' "$push_output"
            ok "Push completed."
            return 0
        fi

        printf '%s\n' "$push_output" >&2

        # A normal push can fail for many reasons. Only enter the
        # recovery flow for a genuine non-fast-forward/diverged branch.
        if ! git fetch origin "$branch"; then
            die "Push failed and the remote could not be fetched.

The local commit remains intact.
No force push was performed."
        fi

        if git merge-base --is-ancestor "origin/$branch" HEAD >/dev/null 2>&1; then
            die "Push failed, but the remote branch is not ahead of this local branch.

The failure does not appear to be a non-fast-forward divergence.
No force push was performed."
        fi

        if git merge-base --is-ancestor HEAD "origin/$branch" >/dev/null 2>&1; then
            die "Push failed because the remote branch is ahead of the local branch.

The local commit remains intact.
No force push was performed."
        fi

        # The branches have genuinely diverged.
        local_version="unknown"
        remote_version="unknown"

        if [[ -f package.json ]] && command -v node >/dev/null 2>&1; then
            local_version="$(node -p "require('./package.json').version" 2>/dev/null || echo unknown)"
        fi

        if git cat-file -e "origin/$branch:package.json" 2>/dev/null; then
            if command -v node >/dev/null 2>&1; then
                remote_version="$(git show "origin/$branch:package.json" | node -e 'let s=""; process.stdin.on("data",d=>s+=d).on("end",()=>{try{console.log(JSON.parse(s).version||"unknown")}catch(e){console.log("unknown")}})' 2>/dev/null || echo unknown)"
            fi
        fi

        remote_commit="$(git log -1 --format='%h' "origin/$branch")"
        remote_author="$(git log -1 --format='%an' "origin/$branch")"

        echo
        echo "🔴  GIT REMOTE DIVERGENCE DETECTED"
        echo
        echo "GitHub already has work that is not present locally."
        echo
        echo "Last remote commit: $remote_commit"
        echo "Last committed by:  $remote_author"
        echo "Remote version:      $remote_version"
        echo "Local version:       $local_version"
        echo
        echo "🔴  DANGER: Overriding the remote branch will replace the"
        echo "remote branch history with your local branch history."
        echo "Any remote-only commits will no longer be reachable from $branch"
        echo "unless they are preserved elsewhere."
        echo
        ask_yn "Do you want to override the remote with local version $local_version?"; confirmation="$ANS"

        case "$confirmation" in
            y)
                ;;
            *)
                die "Override cancelled.

The local commit remains intact.
No force push was performed."
                ;;
        esac

        if ! action_confirm_key "FINAL FORCE-PUSH CONFIRMATION" \
            "This is a destructive operation."; then
            die "Confirmation failed.

The local commit remains intact.
No force push was performed."
        fi

        echo
        echo "🔴  Force-pushing local $branch to origin/$branch..."

        if git push --force-with-lease origin "$branch"; then
            ok "Force push completed."
        else
            die "Force push failed.

The local commit remains intact.
No further push was attempted."
        fi

    else

        # No upstream:
        # dynamically use actual current branch.
        _gp_info "No upstream exists."
        _gp_info "Setting upstream for branch: $branch"

        if git push -u origin "$branch"; then
            ok "Push completed."
        else
            die "Initial push failed.

The local commit remains intact.
No force push was performed."
        fi
    fi
    }
# Copy project tree excluding .git

    copy_project_tree() {
    local source="$1"
    local destination="$2"
    local item

    if command -v rsync >/dev/null 2>&1; then

        rsync -a \
            --exclude=".git" \
            "$source/" \
            "$destination/"

    else

        shopt -s dotglob nullglob

        for item in "$source"/*; do
            [[ "$(basename "$item")" == ".git" ]] && continue
            cp -a -- "$item" "$destination/"
        done

        shopt -u dotglob nullglob
    fi
    }

# Replace working tree while preserving .git

    replace_working_tree() {
    local source="$1"
    local destination="$2"
    local item

    if command -v rsync >/dev/null 2>&1; then

        rsync -a \
            --delete \
            --exclude=".git" \
            "$source/" \
            "$destination/"

    else

        find "$destination" \
            -mindepth 1 \
            -maxdepth 1 \
            ! -name ".git" \
            -exec rm -rf -- {} +

        shopt -s dotglob nullglob

        for item in "$source"/*; do
            [[ "$(basename "$item")" == ".git" ]] && continue
            cp -a -- "$item" "$destination/"
        done

        shopt -u dotglob nullglob
    fi
    }

# Validate prepared recovery repository

    validate_prepared_repository() {
    local expected_branch="$1"
    local branch

    git rev-parse --is-inside-work-tree >/dev/null 2>&1 ||
        return 1

    git rev-parse HEAD >/dev/null 2>&1 ||
        return 1

    git remote get-url origin >/dev/null 2>&1 ||
        return 1

    branch="$(git branch --show-current 2>/dev/null || true)"

    [[ -n "$branch" ]] ||
        return 1

    [[ "$branch" == "$expected_branch" ]] ||
        return 1

    git status --short >/dev/null 2>&1 ||
        return 1

    return 0
    }

# Roll back recovery swap
#
# Called only after original TARGET has already been moved to
# SWAP_BACKUP.

    rollback_recovery() {
    local failure_reason="$1"

    warn "$failure_reason"
    warn "Attempting automatic rollback..."

    # If the replacement TARGET exists, remove it first.
    if [[ -e "$TARGET" ]]; then
        if ! rm -rf -- "$TARGET"; then
            die "CRITICAL: Could not remove failed recovered repository.

Original project remains at:

  $SWAP_BACKUP"
        fi
    fi

    # Restore original project.
    if [[ -e "$SWAP_BACKUP" ]]; then

        if mv -- "$SWAP_BACKUP" "$TARGET"; then
            SWAP_BACKUP=""
            ok "Original project was restored."
            return 0
        fi

        die "CRITICAL: Automatic rollback failed.

Original project is still located at:

  $SWAP_BACKUP"
    fi

    die "CRITICAL: Original project backup could not be found."
    }

# CASE 1
# Existing local Git repository

if git -C "$TARGET" rev-parse --is-inside-work-tree >/dev/null 2>&1; then

    _gp_info "Existing local Git repository detected."

    ensure_git_root
    cd "$TARGET"

    BRANCH="$(get_current_branch)"

    _gp_info "Current branch: $BRANCH"

    if git remote get-url origin >/dev/null 2>&1; then

        _gp_info "Origin:"
        echo "  $(git remote get-url origin)"

    else

        confirm_action \
            "No origin exists. The project will be connected to: $REPO_FULL"

        if github_repo_exists; then

            _gp_info "GitHub repository already exists."

            ensure_origin

        else

            echo
            echo "GitHub repository does not exist:"
            echo "  $REPO_FULL"
            echo

            ask_repo_visibility

            _gp_info "Creating GitHub repository..."

            gh repo create \
                "$REPO_FULL" \
                "$VISIBILITY" ||
                die "Could not create GitHub repository."

            ensure_origin

            ok "GitHub repository created."
        fi
    fi

# CASE 2 / CASE 3
# No local Git repository

else

    _gp_info "No local Git repository detected."

    cd "$TARGET"

    # GitHub repository exists

    if github_repo_exists; then

        _gp_info "GitHub repository exists: $REPO_FULL"

        REPO_INFO="$(get_repo_metadata)" ||
            die "Could not read GitHub repository metadata."

        IFS=$'\t' read -r IS_EMPTY DEFAULT_BRANCH GITHUB_URL <<< "$REPO_INFO"

        REMOTE_URL="$GITHUB_URL"

        [[ -n "$REMOTE_URL" ]] ||
            die "GitHub returned an empty repository URL."

        # CASE 3A
        # Existing GitHub history

        if [[ "$IS_EMPTY" != "true" ]]; then

            [[ -n "$DEFAULT_BRANCH" ]] ||
                die "GitHub repository has history but no default branch."

            _gp_info "GitHub repository contains history."
            _gp_info "Recovery branch: $DEFAULT_BRANCH"

            confirm_action \
                "GitHub history will be recovered and the current project tree will replace its working tree."

            # Same-filesystem staging.

            PARENT_DIR="$(dirname "$TARGET")"
            TARGET_NAME="$(basename "$TARGET")"

            TMP_DIR="$(
                mktemp -d \
                    "$PARENT_DIR/.${TARGET_NAME}.git-recovery.XXXXXX"
            )" ||
                die "Could not create recovery staging directory."

            CLONE_DIR="$TMP_DIR/repository"
            PROJECT_DIR="$TMP_DIR/current-project"

            mkdir -p "$PROJECT_DIR"

            # Preserve current project.

            copy_project_tree "$TARGET" "$PROJECT_DIR"

            # Recover GitHub repository.

            gh repo clone \
                "$REPO_FULL" \
                "$CLONE_DIR" \
                -- \
                --branch "$DEFAULT_BRANCH" ||
                die "Could not recover GitHub repository history."

            [[ -d "$CLONE_DIR/.git" ]] ||
                die "Recovered repository does not contain .git."

            # Replace only working tree.

            replace_working_tree "$PROJECT_DIR" "$CLONE_DIR"

            # Validate prepared repository BEFORE swap.

            cd "$CLONE_DIR"

            if ! validate_prepared_repository "$DEFAULT_BRANCH"; then
                die "Prepared recovery repository failed validation."
            fi

            _gp_info "Prepared repository passed validation."

            # SAFE DIRECTORY SWAP

            SWAP_BACKUP="$(
                mktemp -d \
                    "$PARENT_DIR/.${TARGET_NAME}.git-recovery-backup.XXXXXX"
            )" ||
                die "Could not create recovery backup path."

            # mktemp created an empty directory.
            # Remove it so TARGET can be renamed into that path.
            rmdir -- "$SWAP_BACKUP" ||
                die "Could not prepare recovery backup path."

            # Move original project to backup.

            mv -- "$TARGET" "$SWAP_BACKUP" ||
                die "Could not move the original project aside."

            # Move prepared repository into TARGET.
            #
            # Same parent + same filesystem = directory rename.

            if ! mv -- "$CLONE_DIR" "$TARGET"; then

                rollback_recovery \
                    "Repository replacement failed."

            fi

            # CRITICAL:
            # Validate AFTER the actual swap.
            # If anything is wrong, rollback automatically.

            cd "$TARGET"

            if ! validate_prepared_repository "$DEFAULT_BRANCH"; then

                rollback_recovery \
                    "Final recovered repository failed post-swap validation."

            fi

            BRANCH="$DEFAULT_BRANCH"
            ORIGIN="$(git remote get-url origin)"

            _gp_info "Recovered branch: $BRANCH"
            _gp_info "Recovered origin: $ORIGIN"

            ok "GitHub history recovered."
            ok "Project tree replaced successfully."

            # Only after successful final validation:
            # delete original project backup.

            rm -rf -- "$SWAP_BACKUP"
            SWAP_BACKUP=""

        # CASE 3B
        # Existing EMPTY GitHub repository

        else

            _gp_info "GitHub repository exists but is empty."

            confirm_action \
                "The empty GitHub repository will be connected to this project."

            git init

            BRANCH="$(get_current_branch)"

            _gp_info "Initialized branch: $BRANCH"

            git remote add origin "$REMOTE_URL"

            ok "Origin added."
        fi

    # CASE 2
    # Completely new project

    else

        _gp_info "No local Git repository and no GitHub repository found."

        confirm_action \
            "A new Git repository and GitHub repository will be created for: $REPO_FULL"

        echo

        ask_repo_visibility

        # Initialize locally first.

        git init

        BRANCH="$(get_current_branch)"

        _gp_info "Initialized branch: $BRANCH"

        # Create empty GitHub repository.

        _gp_info "Creating GitHub repository..."

        gh repo create \
            "$REPO_FULL" \
            "$VISIBILITY" ||
            die "Could not create GitHub repository."

        ensure_origin

        ok "GitHub repository created."
    fi
fi

# Final validation

cd "$TARGET"

git rev-parse --is-inside-work-tree >/dev/null 2>&1 ||
    die "Target is not a valid Git repository."

BRANCH="$(get_current_branch)"

git remote get-url origin >/dev/null 2>&1 ||
    die "No origin remote exists. Cannot push."

ORIGIN="$(git remote get-url origin)"

echo
echo "============================================================"
echo "Repository"
echo "============================================================"
echo "Path:   $TARGET"
echo "Branch: $BRANCH"
echo "Origin: $ORIGIN"
echo "============================================================"

# Commit / Push

# A clean working tree does NOT mean there is nothing to push.
# A previous push may have failed after a local commit was created.
# If so, create_commit returns 1 WITHOUT prompting for version/message,
# and we continue directly to push/recovery.

if create_commit; then
    _gp_info "New commit created. Proceeding to push."
else
    _gp_info "No new working-tree changes."

    if git rev-parse --abbrev-ref --symbolic-full-name "@{u}" >/dev/null 2>&1; then
        UNPUSHED_COUNT="$(git rev-list --count "@{u}..HEAD" 2>/dev/null || echo 0)"

        if [[ "$UNPUSHED_COUNT" -gt 0 ]]; then
            _gp_info "$UNPUSHED_COUNT unpushed local commit(s) detected."
            _gp_info "Skipping version and commit prompts."
            _gp_info "Proceeding directly to push/recovery."
        else
            _gp_info "No unpushed local commits."
            _gp_info "Nothing to push."
            exit 0
        fi
    else
        _gp_info "No upstream exists. Proceeding with initial push."
    fi
fi

# Push

push_repository "$BRANCH"

echo
echo "============================================================"
echo "DONE"
echo "============================================================"
echo "Repository: $REPO_FULL"
echo "Branch:     $BRANCH"
echo "============================================================"
}
