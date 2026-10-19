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

Arguments:
  <project-name-or-path>  Target directory or project name. When executed from
                          within the template repository, bare project names are
                          resolved as sibling directories (e.g. ../<name>) to
                          prevent creating nested git repositories. Targets inside
                          the template repository are disallowed.

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

# Pre-flight check: verify template source does not contain nested git repositories.
# Why: When Copier clones a template from a local Git repository, Git treats any nested directory
# containing a '.git' directory as an unregistered gitlink/submodule. This triggers fatal errors
# during cloning ('fatal: No url found for submodule path in .gitmodules').
# We check [[ -e "$TEMPLATE_SRC/.git" ]] to support regular repos, git worktrees, and submodules.
if [[ -e "$TEMPLATE_SRC/.git" ]]; then
  NESTED_GIT_REPOS="$(find "$TEMPLATE_SRC" \( -path "${TEMPLATE_SRC%/}/.git" -o -name ".direnv" -o -name ".venv" -o -name "node_modules" \) -prune -o -mindepth 2 -name ".git" -print 2>/dev/null || true)"
  if [[ -n "$NESTED_GIT_REPOS" ]]; then
    echo "Error: Nested git repositories found inside template source ($TEMPLATE_SRC):" >&2
    echo "$NESTED_GIT_REPOS" >&2
    echo "Nested git repositories cause Copier submodule errors during cloning." >&2
    echo "Please remove or move them outside the template repository before scaffolding." >&2
    exit 1
  fi
fi

# Strip trailing slashes from TARGET (handles tab-completion e.g. 'my-project/')
TARGET="${TARGET%/}"
if [[ -z "$TARGET" ]]; then
  echo "Error: Project target cannot be empty." >&2
  exit 1
fi

CURRENT_DIR="$(pwd -P)"
TEMPLATE_REAL_DIR="$(cd "$DEFAULT_TEMPLATE_DIR" && pwd -P)"

# If TARGET is a bare project name (contains no '/', and is not '.' or '..') and current directory
# is within the template repo, resolve it as a sibling directory outside the template repository.
# Why: Scaffolding a standalone Git repository inside the template directory creates an embedded
# git repository that corrupts the template's Git index and Copier cloning. Sibling resolution matches
# developer expectations (placing downstream projects alongside the template in the parent workspace)
# without requiring manual "../" path prefixes.
if [[ "$TARGET" != *"/"* && "$TARGET" != "." && "$TARGET" != ".." && ( "$CURRENT_DIR" == "$TEMPLATE_REAL_DIR" || "$CURRENT_DIR" == $TEMPLATE_REAL_DIR/* ) ]]; then
  TARGET="$(dirname "$TEMPLATE_REAL_DIR")/$TARGET"
fi

# Pre-validate target containment BEFORE creating any directories on disk.
# Why: Creating directories with 'mkdir -p' prior to validation leaves orphaned intermediate
# directories inside the template repository if validation fails on a multi-level path (e.g. './nested/dir').
# We walk up to the deepest existing ancestor to determine canonical placement without filesystem mutations.
EXISTING_ANCESTOR="$TARGET"
while [[ ! -d "$EXISTING_ANCESTOR" && "$EXISTING_ANCESTOR" != "/" && "$EXISTING_ANCESTOR" != "." ]]; do
  PARENT_DIR="$(dirname "$EXISTING_ANCESTOR")"
  [[ "$PARENT_DIR" == "$EXISTING_ANCESTOR" ]] && break
  EXISTING_ANCESTOR="$PARENT_DIR"
done
ANCESTOR_REAL="$(cd "$EXISTING_ANCESTOR" 2>/dev/null && pwd -P || true)"

FORBIDDEN_DIRS=("$TEMPLATE_REAL_DIR")
if [[ -d "$TEMPLATE_SRC" ]]; then
  TEMPLATE_SRC_REAL="$(cd "$TEMPLATE_SRC" 2>/dev/null && pwd -P || true)"
  [[ -n "$TEMPLATE_SRC_REAL" && "$TEMPLATE_SRC_REAL" != "$TEMPLATE_REAL_DIR" ]] && FORBIDDEN_DIRS+=("$TEMPLATE_SRC_REAL")
fi

for forbidden in "${FORBIDDEN_DIRS[@]}"; do
  if [[ -n "$ANCESTOR_REAL" && ( "$ANCESTOR_REAL" == "$forbidden" || "$ANCESTOR_REAL" == $forbidden/* ) ]]; then
    echo "Error: Target directory cannot be inside the template repository ($forbidden)." >&2
    echo "Please specify a destination outside the template repository (e.g. '../$(basename "$TARGET")')." >&2
    exit 1
  fi
done

# Safe to create target directory now that pre-validation has succeeded
TARGET_PATH="$(mkdir -p "$TARGET" && cd "$TARGET" && pwd -P)"
DIR_NAME="$(basename "$TARGET_PATH")"

# Fallback post-creation check to ensure no edge-case path resolved inside the forbidden directories
for forbidden in "${FORBIDDEN_DIRS[@]}"; do
  if [[ "$TARGET_PATH" == "$forbidden" || "$TARGET_PATH" == $forbidden/* ]]; then
    rmdir "$TARGET_PATH" 2>/dev/null || true
    echo "Error: Target directory cannot be inside the template repository ($forbidden)." >&2
    echo "Please specify a destination outside the template repository (e.g. '../$DIR_NAME')." >&2
    exit 1
  fi
done

# Sanitize directory name into a valid GitHub repo slug (lowercase, alphanumerics and dashes)
REPO_SLUG="$(echo "$DIR_NAME" | tr '[:upper:]' '[:lower:]' | tr ' _' '--' | tr -cd 'a-z0-9.-')"
if [[ -z "$REPO_SLUG" ]]; then
  echo "Error: Project directory name '$DIR_NAME' cannot be converted into a valid GitHub repository slug." >&2
  exit 1
fi

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
