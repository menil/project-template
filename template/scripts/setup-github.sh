#!/usr/bin/env bash
# One-time GitHub setup for the issue automation: turns on the repository setting that
# lets workflows open pull requests, and creates the two labels a person applies
# (ready-to-implement and no-agent). Idempotent.
#
# Run by `just setup-github`, by scripts/create-project.sh once it has created the
# repository, and once per clone by .envrc (with --auto). It needs `gh`, logged in as an
# admin of the repository. Without that it does nothing; with --auto it also says nothing.
#
# Note that the setting is one switch, "Allow GitHub Actions to create and approve pull
# requests": it also lets workflows in the repository approve pull requests. The actions
# used here never do. See the README before relying on required reviews.
#
# Set SKIP_SETUP_GITHUB=1 to stop the automatic run.
set -euo pipefail

auto=false
[[ "${1:-}" == "--auto" ]] && auto=true

say() { echo "setup-github: $*"; }
# Anything that only means "not now" is silent when run automatically.
skip() {
  if [[ "$auto" == false ]]; then say "$*"; fi
  exit 0
}

[[ -f .github/workflows/implement-issue.yml ]] || skip "this project does not use the issue automation; nothing to do."
git rev-parse --git-dir > /dev/null 2>&1 || skip "this is not a git repository."

marker="$(git rev-parse --git-path setup-github-done)"
if [[ "$auto" == true ]]; then
  [[ -z "${SKIP_SETUP_GITHUB:-}" ]] || exit 0
  [[ ! -e "$marker" ]] || exit 0
fi

command -v gh > /dev/null 2>&1 || skip "gh is not installed."
gh auth token > /dev/null 2>&1 || skip "gh is not logged in (run: gh auth login)."
git remote get-url origin > /dev/null 2>&1 || skip "there is no origin remote yet."
repo="$(gh repo view --json nameWithOwner --jq .nameWithOwner 2> /dev/null)" \
  || skip "could not reach GitHub, or origin is not a GitHub repository."
admin="$(gh api "repos/$repo" --jq .permissions.admin 2> /dev/null)" \
  || skip "could not read the permissions on $repo."

if [[ "$admin" != true ]]; then
  # Not an admin: nothing here can work, so do not ask again on every entry.
  echo "no-admin" > "$marker"
  skip "you are not an admin of $repo, so it was not set up; an admin can run: just setup-github"
fi

# Keep the repository's default token permissions as they are; the PUT sets both fields.
current="$(gh api "repos/$repo/actions/permissions/workflow" --jq .default_workflow_permissions 2> /dev/null)" || current="read"
case "$current" in read | write) ;; *) current="read" ;; esac

gh api -X PUT "repos/$repo/actions/permissions/workflow" \
  -f default_workflow_permissions="$current" -F can_approve_pull_request_reviews=true > /dev/null
gh label create ready-to-implement --color 0e8a16 --force \
  --description "Ask the agent to assess and implement this issue" > /dev/null
gh label create no-agent --color 6e7781 --force \
  --description "Keep the agent off this issue" > /dev/null

echo "done" > "$marker"
say "set up $repo: workflows may now open pull requests (this also lets them approve pull requests; see the README),"
say "and the labels ready-to-implement and no-agent exist. Still to do: gh secret set CLAUDE_CODE_OAUTH_TOKEN"
