# AI Decision Record: Migrate project-template to Copier & Scaffolding Script

## Context & Goal
GitHub's native template-repository mechanism ("Use this template") copies every tracked file verbatim into downstream repos without an exclusion manifest. Template maintenance files (such as sync scripts, root test harnesses, and CI meta-workflows) leaked into all downstream projects. Additionally, GitHub native templates do not support upstream updates once cloned.

The objective was to migrate the repository templating mechanism to [Copier](https://copier.readthedocs.io/) to enable clean template file exclusions, parameterized project scaffolding, upstream template updates (`copier update`), and provide a one-command CLI workflow for project creation.

## Architecture & Key Decisions
1. **Subdirectory Isolation (`_subdirectory: template`)**:
   - The downstream payload lives in `template/`, completely segregating it from the root meta-repository orchestration files (`copier.yml`, `scripts/create-project.sh`, root `Justfile`, `shell.nix`).
   - Development artifacts (`.beads/`, `.beads.gate.lock`, `create-project.sh`) are cleanly excluded from generated projects.
2. **Selective Jinja Rendering**:
   - Only dynamic files use the `.jinja` suffix (`README.md.jinja`, `shell.nix.jinja`), preserving syntax highlighting, static linting, and reducing 3-way merge conflict risk during `copier update`.
   - Conditional exclusion for `.github/workflows/pr-review.yml` when `enable_pr_reviews` is toggled off.
3. **Scaffolding CLI Script (`scripts/create-project.sh`)**:
   - Automates the full setup flow: parameter parsing / prompt collection, Copier rendering, Git initialization on `main`, initial conventional commit, and GitHub repo creation & push via `gh repo create`.
4. **Validation & Test Harness**:
   - Added `test-template` recipe to `Justfile` and wired it into `validate` (enforced locally in pre-commit and in CI via `.github/workflows/validate.yml`), ensuring template rendering and CLI dry-run are continuously verified.

## Alternatives Considered & Rejected
- **GitHub Actions Self-Cleanup Workflow**: Evaluated and rejected because it triggers on every branch/tag creation forever, causes false positives on genuine forks, requires elevated write permissions, and pushes an unreviewed destructive commit to brand-new repos.
- **Cookiecutter + Cruft**: Evaluated and rejected due to rigid directory structures (`{{cookiecutter.slug}}/`) and the need for external tooling (`cruft`) to support updates, whereas Copier supports native 3-way merge updates (`copier update`) and clean subdirectory layouts out of the box.
