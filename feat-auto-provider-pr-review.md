# AI Decision Record: Automated Provider Fallback for PR Code Reviews

## Context & Goal
Previously, `project-template` configured the PR code review GitHub Actions workflow with a dynamic expression:
```yaml
provider: ${{ (secrets.ANTHROPIC_API_KEY || secrets.CLAUDE_CODE_OAUTH_TOKEN) && 'anthropic' || 'openrouter' }}
```

With `menil/pr-code-review-action` now supporting automated fallback across credentials and providers via `provider: auto`, this static ternary expression was counterproductive:
1. Setting `provider: anthropic` explicitly instructed the action to only attempt Anthropic credentials (`CLAUDE_CODE_OAUTH_TOKEN` followed by `ANTHROPIC_API_KEY`), completely isolating Anthropic and bypassing OpenRouter.
2. If a repository configured a `CLAUDE_CODE_OAUTH_TOKEN` that expired, depleted its credit balance (HTTP 400 credit balance), or hit rate limits / server errors (401, 403, 429, 5xx), the review action failed immediately instead of gracefully falling back to `OPENROUTER_API_KEY`.
3. Downstream repositories created from the template inherited this limitation.

The goal is to update `project-template` and its Copier template to use `provider: auto` explicitly, enabling seamless, resilient review execution with automatic fallback from Claude Code tokens to OpenRouter.

## Architecture & Key Decisions

1. **Explicit `provider: auto` in CI Workflows**:
   - Updated both `.github/workflows/pr-review.yml` (for `project-template` itself) and `template/.github/workflows/pr-review.yml` (for downstream projects scaffolded via Copier) to pass `provider: 'auto'`.
   - Updated explanatory comments to clarify that `auto` mode prioritizes Claude (Claude Code OAuth token first, then billed API key) and automatically falls back to OpenRouter upon encountering token authentication, credit exhaustion, or 5xx server errors.

2. **Documentation & Scaffolding Guidance**:
   - Updated `README.md` and `template/README.md.jinja` to document the automated fallback capability and describe `OPENROUTER_API_KEY` as an automated fallback or primary provider.
   - Updated post-scaffolding instructions in `scripts/create-project.sh` to mention configuring `ANTHROPIC_API_KEY` (or `CLAUDE_CODE_OAUTH_TOKEN`) and/or `OPENROUTER_API_KEY`.

3. **Validation & Template Verification**:
   - Verified that `nix-shell --run "just validate"` runs successfully, checking agent-ignore synchronization, running Copier dry-run scaffolding, and validating the generated template.
