#!/usr/bin/env bash
# Runs template/scripts/setup-github.sh against a throwaway git repository and a fake `gh`
# that records every call, and checks what it does and, as important, what it refuses to do.
# shellcheck disable=SC2030,SC2031  # per-test environment is set in deliberate subshells
set -euo pipefail

SCRIPT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/template/scripts/setup-github.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
failures=0

fail() { echo "FAIL: $*" >&2; failures=$((failures + 1)); }
expect() { # expect <description> <condition...>
  local description="$1"; shift
  if ! "$@"; then fail "$description"; fi
}

mkdir -p "$TMP/bin"
cat > "$TMP/bin/gh" <<'FAKE'
#!/usr/bin/env bash
# A fake gh. It logs the call, then answers from FAKE_* variables.
echo "$*" >> "$FAKE_LOG"
case "$*" in
  "auth token") [[ "${FAKE_AUTH:-ok}" == ok ]] && echo token || exit 1 ;;
  "repo view --json nameWithOwner --jq .nameWithOwner") [[ "${FAKE_NET:-ok}" == ok ]] && echo "owner/repo" || exit 1 ;;
  "api repos/owner/repo --jq .permissions.admin") echo "${FAKE_ADMIN:-true}" ;;
  "api repos/owner/repo/actions/permissions/workflow --jq .default_workflow_permissions") echo "${FAKE_DEFAULT:-read}" ;;
  "api -X PUT repos/owner/repo/actions/permissions/workflow "*) ;;
  "label create "*) ;;
  *) echo "unexpected gh call: $*" >&2; exit 1 ;;
esac
FAKE
chmod +x "$TMP/bin/gh"

# A fresh project: a git repo with an origin and the implementation workflow.
new_project() {
  local dir="$TMP/project-$1"
  mkdir -p "$dir/.github/workflows"
  : > "$dir/.github/workflows/implement-issue.yml"
  git -C "$dir" init -q -b main
  git -C "$dir" remote add origin https://github.com/owner/repo.git
  echo "$dir"
}

# run <dir> [args...]: runs the script there with the fake gh, returns its output and log.
run() {
  local dir="$1"; shift
  : > "$TMP/gh.log"
  (cd "$dir" && PATH="$TMP/bin:$PATH" FAKE_LOG="$TMP/gh.log" bash "$SCRIPT" "$@" 2>&1) || true
}
calls() { cat "$TMP/gh.log"; }
never() { ! grep -qE "$1" "$TMP/gh.log"; }
changed_github() { calls | grep -qE '^(api -X PUT|label create)'; }
marker_of() { git -C "$1" rev-parse --path-format=absolute --git-path setup-github-done; }

# 1. A project that does not use the issue automation is left alone, in either mode.
dir="$(new_project plain)"; rm "$dir/.github/workflows/implement-issue.yml"
out="$(run "$dir" --auto)"
expect "no workflow, auto: silent" test -z "$out"
expect "no workflow, auto: no gh call at all" test ! -s "$TMP/gh.log"
out="$(run "$dir")"
expect "no workflow, manual: says why" grep -q "does not use the issue automation" <<< "$out"
expect "no workflow, manual: no gh call at all" test ! -s "$TMP/gh.log"

# 2. The happy path: the setting, both labels, and a marker.
dir="$(new_project happy)"
out="$(run "$dir" --auto)"
expect "sets the setting" grep -q 'api -X PUT repos/owner/repo/actions/permissions/workflow -f default_workflow_permissions=read -F can_approve_pull_request_reviews=true' "$TMP/gh.log"
expect "creates ready-to-implement" grep -q 'label create ready-to-implement --color 0e8a16 --force' "$TMP/gh.log"
expect "creates no-agent" grep -q 'label create no-agent --color 6e7781 --force' "$TMP/gh.log"
expect "leaves a marker" test -e "$(marker_of "$dir")"
expect "says what it did" grep -q "set up owner/repo" <<< "$out"
expect "says it also lets workflows approve" grep -q "approve pull requests" <<< "$out"

# 3. Once automatically: a second automatic run makes no gh call.
out="$(run "$dir" --auto)"
expect "second auto run: silent" test -z "$out"
expect "second auto run: no gh call" test ! -s "$TMP/gh.log"

# 4. A manual run still works after that, and does it again (idempotent).
out="$(run "$dir")"
expect "manual run after the marker: applies again" changed_github

# 5. The repository's default token permissions are kept, not forced to read.
dir="$(new_project write-default)"
(export FAKE_DEFAULT=write; run "$dir" --auto > /dev/null)
expect "keeps a write default" grep -q 'default_workflow_permissions=write' "$TMP/gh.log"
dir="$(new_project odd-default)"
(export FAKE_DEFAULT=banana; run "$dir" --auto > /dev/null)
expect "an odd default falls back to read" grep -q 'default_workflow_permissions=read' "$TMP/gh.log"

# 6. What it must not do without the right to.
dir="$(new_project no-admin)"
out="$(FAKE_ADMIN=false run "$dir" --auto)"
expect "not admin: changes nothing" never '^(api -X PUT|label create)'
expect "not admin, auto: silent" test -z "$out"
expect "not admin: remembers, so it does not ask again" test -e "$(marker_of "$dir")"
out="$(FAKE_ADMIN=false run "$dir")"
expect "not admin, manual: says so" grep -q "not an admin" <<< "$out"
expect "not admin, manual: still changes nothing" never '^(api -X PUT|label create)'

dir="$(new_project logged-out)"
out="$(FAKE_AUTH=no run "$dir" --auto)"
expect "not logged in: no change" never '^(api |label )'
expect "not logged in: no marker, so it tries again later" test ! -e "$(marker_of "$dir")"
expect "not logged in, auto: silent" test -z "$out"
out="$(FAKE_AUTH=no run "$dir")"
expect "not logged in, manual: says how to log in" grep -q "gh auth login" <<< "$out"

dir="$(new_project offline)"
(export FAKE_NET=down; run "$dir" --auto > /dev/null)
expect "offline: no change" never '^(api |label )'
expect "offline: no marker, so it tries again later" test ! -e "$(marker_of "$dir")"

dir="$(new_project no-origin)"; git -C "$dir" remote remove origin
out="$(run "$dir")"
expect "no origin: says so" grep -q "no origin" <<< "$out"
expect "no origin: no gh call that could change anything" never '^(api |label |repo )'

dir="$(new_project not-a-repo)"; rm -rf "$dir/.git"
out="$(run "$dir")"
expect "not a git repository: says so" grep -q "not a git repository" <<< "$out"

# 7. The opt-out.
dir="$(new_project opt-out)"
(export SKIP_SETUP_GITHUB=1; run "$dir" --auto > /dev/null)
expect "SKIP_SETUP_GITHUB: no gh call" test ! -s "$TMP/gh.log"
expect "SKIP_SETUP_GITHUB: no marker" test ! -e "$(marker_of "$dir")"
(export SKIP_SETUP_GITHUB=1; run "$dir" > /dev/null)
expect "SKIP_SETUP_GITHUB does not stop a manual run" changed_github

# 8. A failing call never leaves a marker (a half-done setup is run again).
dir="$(new_project fails-midway)"
mkdir -p "$TMP/bin-failing"
cat > "$TMP/bin-failing/gh" <<'FAKE'
#!/usr/bin/env bash
# Like the fake gh, but creating the first label fails.
case "$*" in
  "label create ready-to-implement"*) echo "$*" >> "$FAKE_LOG"; exit 1 ;;
esac
exec "$REAL_GH" "$@"
FAKE
chmod +x "$TMP/bin-failing/gh"
: > "$TMP/gh.log"
(cd "$dir" && PATH="$TMP/bin-failing:$PATH" REAL_GH="$TMP/bin/gh" FAKE_LOG="$TMP/gh.log" bash "$SCRIPT" --auto > /dev/null 2>&1) || true
expect "a failed call leaves no marker" test ! -e "$(marker_of "$dir")"

if [[ "$failures" -ne 0 ]]; then
  echo "$failures check(s) failed" >&2
  exit 1
fi
echo "setup-github: all checks passed"
