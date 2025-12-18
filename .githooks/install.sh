#!/usr/bin/env bash
# Install git hooks for this repository
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"

cd "$REPO_ROOT"

echo "Configuring git hooks path..."
git config core.hooksPath .githooks

echo "✓ Git hooks installed"
echo ""
echo "Hooks enabled:"
echo "  - pre-commit: shellcheck + shfmt validation"
echo "  - commit-msg: commit message format validation"
