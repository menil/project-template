# AI Decision Record: Prevent Nested Scaffolding & Fix Target Resolution

## Context & Goal
When users executed `./scripts/create-project.sh <project-name>` from within the template repository (`project-template`), bare target arguments were resolved relative to `$PWD`, creating downstream projects directly inside the template repository (e.g. `~/workspace/project-template/wisprflow-muteme-ptt-bridge`).

This caused severe downstream issues:
1. When Copier clones a template repository that contains uncommitted or untracked changes, it runs `git add -A` into a temporary clone.
2. Any untracked directory containing `.git` (such as a previously scaffolded downstream repo like `sandbox`) is staged by Git as an unconfigured gitlink (submodule pointer mode `160000`) without an entry in `.gitmodules`.
3. Copier then runs `git submodule update --checkout --init --recursive --force`, which fails with `fatal: No url found for submodule path in .gitmodules`.
4. Additionally, edge-case arguments like `.` or `..` could potentially target and initialize parent workspaces or user home directories.

The objective was to ensure safe, predictable target path resolution that prevents template directory pollution, guards Copier against stray git submodules, and maintains a clean separation between the template repository and downstream projects.

## Architecture & Key Decisions
1. **Bare-Name Sibling Resolution**:
   - When executed within the template repository with a bare project name (excluding `.` and `..`), `create-project.sh` resolves the target to the template's sibling directory (`$(dirname "$TEMPLATE_REAL_DIR")/$TARGET`). This aligns with standard developer workflows where projects reside alongside each other within a workspace root (e.g. `~/workspace/`).
2. **Pure Pre-Validation Without Directory Mutation**:
   - Rather than creating directories prematurely with `mkdir -p` and attempting rollback on failure with `rmdir`, the script walks up to the deepest existing ancestor to validate canonical containment *before* modifying the filesystem. This prevents leaking intermediate orphan directories on invalid nested paths.
3. **Pre-Flight Nested Repository Scan**:
   - Added an upfront check before template cloning that detects nested `.git` repositories in `$TEMPLATE_SRC`.
   - Utilizes `-prune` on `.git`, `.direnv`, `.venv`, and `node_modules` to avoid traversing deep object graphs or virtual environments.
   - Uses `-e "$TEMPLATE_SRC/.git"` to support Git worktrees and submodules.
4. **Enhanced Test Assertions & Documentation**:
   - Added automated tests in `Justfile` (`test-template` recipe) asserting rejection of `.` and nested target paths, verifying that no disk artifacts are created, and asserting that the pre-flight scan catches nested `.git` folders.
   - Updated `README.md` and CLI `--help` to document sibling directory resolution.

## Alternatives Considered & Rejected
- **Post-Creation `rmdir` Rollback**:
  - Rejected because `rmdir` only deletes the leaf directory, leaving parent directories (e.g. `./nested` in `./nested/app`) orphaned on disk, and risks deleting pre-existing empty directories.
- **Ignoring Nested Git Repos in `.gitignore`**:
  - Rejected because `Justfile` enforces that root `.gitignore` matches `template/.gitignore`, and downstream projects should not inherit template-specific ignore rules. Moreover, `git add -A` inside Copier's temporary clone would still stumble on unignored nested gitlinks.
- **Strictly Rejecting Bare Target Names**:
  - Evaluated requiring users to explicitly pass `../<project-name>`. Rejected in favor of sibling auto-resolution because standard CLI UX for template generators allows passing a simple project name (e.g. `create-project.sh my-app`), and auto-resolving to a sibling directory prevents user errors while maintaining frictionless developer ergonomics.
