# Project Template

A generic, modern project template pre-configured with developer tooling, Nix integration, and automated AI code reviews.

## Features

- 🤖 **Automated PR Reviews**: Integrated via `menil/pr-code-review-action` using OpenRouter (free tier by default).
- ❄️ **Nix Shell**: Pre-configured `shell.nix` for consistent, reproducible developer environments.
- ⚙️ **Modern Git Integration**: Sensible `.gitignore` rules for macOS, VS Code, and Nix.

---

## Getting Started

### 1. Create a Repository from this Template

Click the **"Use this template"** button on GitHub, or create it via the GitHub CLI:
```bash
gh repo create my-new-project --template menil/project-template --private --clone
```

### 2. Configure GitHub Secrets

For the automated PR code reviews to run successfully, navigate to your new repository's **Settings > Secrets and variables > Actions** and add the following two secrets:

1. **`OPENROUTER_API_KEY`**: Your OpenRouter API Key.
2. **`PAT_WITH_REPO_ACCESS`**: A GitHub Personal Access Token (PAT) with `repo` read access, which allows the runner to fetch the private review action repository.

---

## Development Environment

Activate the Nix developer shell:
```bash
nix-shell
```
