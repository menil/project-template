# AI Decision Record: Isolate sync-agent-ignore to Template Repository

## Context & Goal
Previously, `sync-agent-ignore.sh` resided at `template/scripts/sync-agent-ignore.sh` with a root symlink at `scripts/sync-agent-ignore.sh`. When downstream repositories were scaffolded from `project-template` via Copier, Copier faithfully reproduced `scripts/sync-agent-ignore.sh`, tasks in `template/Justfile` (`sync-agent-ignore` and `check-agent-ignore-sync`), and an extraneous dependency on `jq` in `template/shell.nix.jinja`.

Downstream repositories do not need this maintenance machinery: they simply need a clean project scaffold with pre-configured `.claude/settings.json` deny rules matching the template's standard `.agentignore`. Scaffolding an unnecessary `scripts/` directory and forcing child projects to carry `jq` and custom agent-ignore sync recipes created unwanted toolchain leakage and maintenance overhead.

The goal was to isolate `sync-agent-ignore.sh` strictly to the template repository as developer maintenance tooling, ensuring child repositories remain clean, minimal, and fast to validate.

## Architecture & Key Decisions

1. **Move Script Out of `template/` to Root `scripts/`**:
   - Converted `scripts/sync-agent-ignore.sh` from a symlink into a standalone executable regular file (mode `100755`).
   - Completely deleted `template/scripts/sync-agent-ignore.sh`. Because Copier renders from `template/`, this cleanly prevents the creation of any `scripts/` directory in child projects.

2. **Template Setting Synchronization via Root Symlink**:
   - In `project-template`, `.claude/settings.json` is a symlink pointing to `../template/.claude/settings.json`.
   - Running `scripts/sync-agent-ignore.sh` in the root repository updates `.claude/settings.json` via standard shell redirection (`> .claude/settings.json`), which follows the symlink and mutates `template/.claude/settings.json` in place without breaking the symlink.
   - The root `Justfile` continues to validate synchronization via `check-agent-ignore-sync` during `just validate`, ensuring shipped template defaults never drift.

3. **Prune Downstream Tasks and Dependencies**:
   - Removed `sync-agent-ignore` and `check-agent-ignore-sync` recipes from `template/Justfile`.
   - Simplified `template/Justfile` recipes: `format` now runs without prerequisites, and `validate: lint`.
   - Removed `jq` from `template/shell.nix.jinja`, keeping downstream Nix shell environments lightweight.

4. **Script Hardening & Edge-Case Resilience**:
   - Added CLI argument validation using `case "${1:-}" in` supporting `--check`, `-h|--help`, and rejecting unrecognized arguments to avoid accidental file mutation.
   - Added guarded handling for empty `deny` arrays (`if [[ ${#deny[@]} -eq 0 ]]`) to prevent Bash 3.2 `set -u` unbound array crashes on macOS and to ensure valid JSON output (`"deny": []`).
   - Added regex-based line filtering (`^[[:space:]]*(#|$)`) and native parameter expansion trimming to ignore blank lines and indented comments cleanly.
   - Protected script directory traversal with `CDPATH='' cd -- "$(dirname "${BASH_SOURCE[0]}")/.."`.

5. **Downstream Documentation Alignment**:
   - Updated `template/README.md.jinja` to clarify that `.claude/settings.json` is pre-configured and static; downstream developers who add custom paths to `.agentignore` should add corresponding `Read(...)` deny rules directly to `.claude/settings.json` or pull template updates via `copier update`.

6. **Expanded Test Assertions**:
   - Added positive assertion `test -f "$TMPDIR/rendered-default/.claude/settings.json"` in `Justfile`'s `test-template`.
   - Added negative assertion `test ! -d "$TMPDIR/rendered-default/scripts"` and `test ! -d "$TMPDIR/dry-run-app/scripts"`.
   - Added verification that `scripts/sync-agent-ignore.sh` is an executable non-symlink file.

## Alternatives Considered & Rejected

1. **Retaining `sync-agent-ignore.sh` in Deployed Projects**:
   - *Rejected*: Deployed repositories should not carry template maintenance infrastructure or extra Nix dependencies (`jq`) that have no bearing on the child project's runtime or development lifecycle.
2. **Symlinking `.claude/settings.json` Directly to `.agentignore`**:
   - *Rejected*: Claude Code has no native support for `.gitignore`-syntax ignore files (`.claudeignore` does not exist); it requires JSON with `Read(...)` permissions in `settings.json`.
3. **Dynamic Template Generation of `settings.json` via Jinja (`.claude/settings.json.jinja`)**:
   - *Rejected*: Generating complex JSON deny rules from `.agentignore` within Copier templates adds Jinja parsing complexity and increases scaffold time. Shipping a static, pre-synchronized JSON file verified by CI in the root template is simpler, faster, and more reliable.
