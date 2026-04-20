#!/bin/bash
set -euo pipefail

# Create a git worktree for Nex with submodule + libghostty + xcodeproj ready to build.
#
# Usage:
#   scripts/new-worktree.sh <branch> [path]
#
# Examples:
#   scripts/new-worktree.sh feat/new-thing              # -> ../nex-feat-new-thing (new branch)
#   scripts/new-worktree.sh feat/new-thing ../nex-wip   # custom path
#   scripts/new-worktree.sh main ../nex-main            # existing branch, checked out separately

if [ $# -lt 1 ] || [ $# -gt 2 ]; then
    echo "Usage: $0 <branch> [path]" >&2
    exit 1
fi

BRANCH="$1"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MAIN_REPO="$(cd "$SCRIPT_DIR/.." && pwd)"

# Must be run from the primary worktree. Worktrees-of-worktrees work in git but
# confuse submodule setup, so keep it simple.
if [ "$(git -C "$MAIN_REPO" rev-parse --is-inside-work-tree 2>/dev/null)" != "true" ]; then
    echo "Error: $MAIN_REPO is not a git repo" >&2
    exit 1
fi
if [ "$(git -C "$MAIN_REPO" rev-parse --git-common-dir)" != "$(git -C "$MAIN_REPO" rev-parse --git-dir)" ]; then
    echo "Error: run this from the primary checkout at $MAIN_REPO, not from a worktree" >&2
    exit 1
fi

# Default path: sibling dir named nex-<branch-with-slashes-as-dashes>
if [ $# -eq 2 ]; then
    WORKTREE_PATH="$2"
else
    SAFE_BRANCH="${BRANCH//\//-}"
    WORKTREE_PATH="$MAIN_REPO/../nex-$SAFE_BRANCH"
fi

# Normalize to absolute
WORKTREE_PATH="$(cd "$(dirname "$WORKTREE_PATH")" && pwd)/$(basename "$WORKTREE_PATH")"

if [ -e "$WORKTREE_PATH" ]; then
    echo "Error: $WORKTREE_PATH already exists" >&2
    exit 1
fi

echo "==> Creating worktree at $WORKTREE_PATH"
if git -C "$MAIN_REPO" show-ref --verify --quiet "refs/heads/$BRANCH"; then
    git -C "$MAIN_REPO" worktree add "$WORKTREE_PATH" "$BRANCH"
else
    git -C "$MAIN_REPO" worktree add -b "$BRANCH" "$WORKTREE_PATH"
fi

echo "==> Initializing ghostty submodule"
git -C "$WORKTREE_PATH" submodule update --init --recursive

echo "==> Linking lib/libghostty.a from main checkout"
SRC_LIB="$MAIN_REPO/lib/libghostty.a"
if [ -f "$SRC_LIB" ]; then
    mkdir -p "$WORKTREE_PATH/lib"
    ln -sf "$SRC_LIB" "$WORKTREE_PATH/lib/libghostty.a"
    echo "    linked $WORKTREE_PATH/lib/libghostty.a -> $SRC_LIB"
else
    echo "    (skipped: $SRC_LIB does not exist yet; build it in the main checkout first)"
fi

echo "==> Generating Xcode project"
if command -v xcodegen >/dev/null 2>&1; then
    (cd "$WORKTREE_PATH" && xcodegen generate --spec project.yml)
else
    echo "    (skipped: xcodegen not on PATH)"
fi

cat <<EOF

Done. Next steps:
    cd $WORKTREE_PATH

Build with a worktree-local DerivedData so it does not clash with other checkouts:
    xcodebuild -scheme Nex -destination 'platform=macOS' -skipMacroValidation \\
      -derivedDataPath build/DerivedData build

Clean up when finished:
    git -C $MAIN_REPO worktree remove $WORKTREE_PATH
EOF
