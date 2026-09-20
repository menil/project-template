# Project Task Runner

# List available recipes
default:
    @just --list

# Format code and configuration files
format: sync-agent-ignore
    @echo "No formatter configured yet. Customize this recipe in the Justfile!"

# Run code and markdown linting checks
lint:
    @echo "No linter configured yet. Customize this recipe in the Justfile!"

# Regenerate .claude/settings.json's Read-deny rules from .agentignore
sync-agent-ignore:
    @scripts/sync-agent-ignore.sh

# Check that .claude/settings.json is in sync with .agentignore
check-agent-ignore-sync:
    @scripts/sync-agent-ignore.sh --check

# Test Copier template generation and verification
test-template:
    #!/usr/bin/env bash
    set -euo pipefail
    echo "Testing Copier template generation..."
    TMPDIR=$(mktemp -d)
    trap 'rm -rf "$TMPDIR"' EXIT

    # 1. Verify root developer tooling files are symlinks to template/
    failed=0
    for symlink in .agentignore .envrc .githooks/commit-msg .githooks/pre-commit scripts/sync-agent-ignore.sh .claude/settings.json; do
      if [[ ! -L "$symlink" ]]; then
        echo "error: root file '$symlink' is not a symlink to template/" >&2
        failed=1
      fi
    done
    if [[ "$failed" -ne 0 ]]; then
      exit 1
    fi
    diff -u .gitignore template/.gitignore

    # 2. Test default template rendering (enable_pr_reviews=true)
    copier copy --defaults --trust . "$TMPDIR/rendered-default"
    test -f "$TMPDIR/rendered-default/README.md"
    test -f "$TMPDIR/rendered-default/shell.nix"
    test -f "$TMPDIR/rendered-default/.github/workflows/pr-review.yml"
    test ! -f "$TMPDIR/rendered-default/copier.yml"
    test ! -f "$TMPDIR/rendered-default/scripts/create-project.sh"
    test ! -d "$TMPDIR/rendered-default/.beads"

    # Verify rendered project passes its own validation suite
    (cd "$TMPDIR/rendered-default" && just validate)

    # 3. Test template rendering with PR reviews disabled (enable_pr_reviews=false)
    copier copy --defaults --trust -d enable_pr_reviews=false -d project_name="Custom CLI App" . "$TMPDIR/rendered-no-pr"
    test -f "$TMPDIR/rendered-no-pr/README.md"
    test ! -f "$TMPDIR/rendered-no-pr/.github/workflows/pr-review.yml"

    # 4. Test scaffolding script dry run
    ./scripts/create-project.sh --dry-run --defaults --template . "$TMPDIR/dry-run-app"
    test -f "$TMPDIR/dry-run-app/README.md"

    echo "✅ Copier template verification passed."

# Run all local checks (tests, format checks, lints)
validate: check-agent-ignore-sync lint test-template
