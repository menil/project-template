#!/usr/bin/env bash
# Scaffolds a new project using Copier, initializes a git repository,
# creates the initial commit, and publishes to GitHub via GitHub CLI.
#
# Usage:
#   scripts/create-project.sh [OPTIONS] <project-name-or-path>
#
# Options:
#   --public            Create a public GitHub repository (default is --private)
#   --private           Create a private GitHub repository (default)
#   --defaults          Use default values for all template questions
#   --template <path>   Template source path or git URL (default: this repo or gh:menil/project-template)
#   --dry-run           Render template without initializing git or creating GitHub repository
#   -h, --help          Show this help message

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEFAULT_TEMPLATE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

VISIBILITY="--private"
DRY_RUN=false
USE_DEFAULTS=false
TEMPLATE_SRC=""
TARGET=""
COPIER_EXTRA_ARGS=()

show_help() {
  cat << 'EOF'
Usage: create-project.sh [OPTIONS] <project-name-or-path>

Scaffold a new project from project-template using Copier and publish to GitHub.

Options:
  --public            Create a public GitHub repository (default is --private)
  --private           Create a private GitHub repository (default)
  --defaults          Use default values for all template questions
  --template <path>   Template source path or git URL
  --dry-run           Render template locally without creating Git/GitHub repo
  -h, --help          Show this help message

Examples:
  ./scripts/create-project.sh my-cool-app
  ./scripts/create-project.sh --public ~/workspace/my-oss-tool
  ./scripts/create-project.sh --defaults my-automated-service
EOF
}

# Parse CLI arguments
while [[ $# -gt 0 ]]; do
  case "$1" in
    --public)
      VISIBILITY="--public"
      shift
      ;;
    --private)
      VISIBILITY="--private"
      shift
      ;;
    --defaults)
      USE_DEFAULTS=true
      shift
      ;;
    --template)
      if [[ $# -lt 2 || -z "${2:-}" || "${2:-}" == -* ]]; then
        echo "Error: --template requires a path or git URL argument." >&2
        exit 1
      fi
      TEMPLATE_SRC="$2"
      shift 2
      ;;
    --dry-run)
      DRY_RUN=true
      shift
      ;;
    -h|--help)
      show_help
      exit 0
      ;;
    -*)
      echo "Error: Unknown option '$1'" >&2
      show_help
      exit 1
      ;;
    *)
      if [[ -z "$TARGET" ]]; then
        TARGET="$1"
      else
        echo "Error: Unexpected argument '$1'" >&2
        show_help
        exit 1
      fi
      shift
      ;;
  esac
done

# Prompt for target if not provided
if [[ -z "$TARGET" ]]; then
  read -rp "Enter target directory or project name: " TARGET
  if [[ -z "$TARGET" ]]; then
    echo "Error: Project target cannot be empty." >&2
    exit 1
  fi
fi

# Determine template source
if [[ -z "$TEMPLATE_SRC" ]]; then
  if [[ -f "$DEFAULT_TEMPLATE_DIR/copier.yml" ]]; then
    TEMPLATE_SRC="$DEFAULT_TEMPLATE_DIR"
  else
    TEMPLATE_SRC="gh:menil/project-template"
  fi
fi

# Check required binaries
if ! command -v copier >/dev/null 2>&1; then
  echo "Error: Required command 'copier' is not installed or not in PATH." >&2
  echo "Tip: Run inside 'nix-shell' or install copier via 'pipx install copier'." >&2
  exit 1
fi

if [[ "$DRY_RUN" == false ]]; then
  for cmd in git gh; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
      echo "Error: Required command '$cmd' is not installed or not in PATH." >&2
      exit 1
    fi
  done

  # Verify GitHub CLI authentication before doing work
  if ! gh auth status >/dev/null 2>&1; then
    echo "Error: GitHub CLI (gh) is not authenticated. Please run 'gh auth login' first." >&2
    exit 1
  fi
fi

# Resolve target path and project display/slug names
TARGET_PATH="$(mkdir -p "$TARGET" && cd "$TARGET" && pwd)"
DIR_NAME="$(basename "$TARGET_PATH")"
# Sanitize directory name into a valid GitHub repo slug (lowercase, alphanumerics and dashes)
REPO_SLUG="$(echo "$DIR_NAME" | tr '[:upper:]' '[:lower:]' | tr ' _' '--' | tr -cd 'a-z0-9.-')"

echo "=========================================="
echo "🚀 Scaffolding Project: $DIR_NAME"
echo "📦 GitHub Repo Slug:   $REPO_SLUG"
echo "📁 Destination:        $TARGET_PATH"
echo "📦 Template:           $TEMPLATE_SRC"
echo "🔒 Visibility:         $VISIBILITY"
echo "=========================================="

# Prepare copier options
if [[ "$USE_DEFAULTS" == true ]]; then
  COPIER_EXTRA_ARGS+=("--defaults" "-d" "project_name=$DIR_NAME")
fi

# Run Copier
echo ""
echo "⚙️  Running Copier..."
# Note: ${COPIER_EXTRA_ARGS[@]+"${COPIER_EXTRA_ARGS[@]}"} safely expands empty arrays
# without triggering 'unbound variable' errors under set -u on legacy bash versions (e.g. macOS default bash 3.2).
copier copy --trust ${COPIER_EXTRA_ARGS[@]+"${COPIER_EXTRA_ARGS[@]}"} "$TEMPLATE_SRC" "$TARGET_PATH"

if [[ "$DRY_RUN" == true ]]; then
  echo ""
  echo "✅ Dry run complete. Project files generated in $TARGET_PATH."
  exit 0
fi

# Enter target repository directory
cd "$TARGET_PATH"

# Initialize git repository if not already initialized
if [[ ! -d .git ]]; then
  echo ""
  echo "📦 Initializing Git repository on branch 'main'..."
  git init -b main
  git add .
  git commit -m "feat: initial commit from project template"
else
  echo ""
  echo "ℹ️  Existing Git repository detected; skipping git init."
fi

# Create remote GitHub repository and push
echo ""
echo "🌐 Creating GitHub repository ($REPO_SLUG with $VISIBILITY)..."
gh repo create "$REPO_SLUG" "$VISIBILITY" --source=. --push

echo ""
echo "=========================================="
echo "🎉 Project successfully created and published!"
echo ""
echo "Next steps:"
echo "  1. cd \"$TARGET_PATH\""
echo "  2. direnv allow  (or enter 'nix-shell')"
echo "  3. If PR reviews are enabled, configure OPENROUTER_API_KEY / ANTHROPIC_API_KEY in GitHub repository secrets"
echo "=========================================="
