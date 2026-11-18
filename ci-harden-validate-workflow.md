# AI Decision Record: Harden the validate workflow and pin nixpkgs

## Context & Goal
`pr-code-review-action` recently got a CI workflow. Its first CI run failed
because the floating `nixos-unstable` channel shipped a newer ruff than local
development used, which enabled many more lint rules by default. The
template's `validate.yml` had the same floating channel, plus read-write
default token permissions, no timeout, no concurrency control and a stale
`actions/checkout@v4` (the root copy had been bumped to v7 by Dependabot; the
template copy never was). Every generated project inherits these files, so the
template is where they matter most.

Goal: give new projects a reproducible, least-privilege `validate` workflow
and make sure the template's own copy cannot silently fall behind again.

## Architecture & Key Decisions
- **Pin nixpkgs inside `shell.nix` and `shell.nix.jinja`** with `fetchTarball`
  (full commit URL plus sha256), and drop `nix_path` from the workflow. The
  pin lives in the shell file, not the workflow, so local development and CI
  read the same source of truth. The revision is the channel build local
  development already used, so it is a known-good, Hydra-built revision.
- **Harden `validate.yml`:** `permissions: contents: read`, no persisted
  checkout credentials, cancel superseded PR runs, `timeout-minutes: 15`,
  checkout v7. Pushes to main use the commit SHA as the concurrency group so
  every commit that lands is validated and none is replaced in the queue.
- **Dependabot `/template` entry.** Dependabot's github-actions scan of `/`
  only reads the root workflows, which is exactly how template checkout stayed
  on v4. A second entry for `/template` fixes that.
- **Guards in `test-template`** for the new duplication: root and template
  `validate.yml` must be identical; the pin (revision and hash) must match in
  both shell files; and the rendered `shell.nix` is evaluated with
  `nix-instantiate`, because `just validate` in the test runs in the already
  active root shell and would never evaluate it. Verified by hand that a changed
  hash is detected and a wrong hash fails with Nix's hash-mismatch error.
- **Bump instructions in comments and the template README** (compute the hash
  with `nix-prefetch-url --unpack`), because nothing automates bumping.
- **One commit:** dropping `nix_path` only works with the pin, so splitting
  would leave a commit that fails CI.

## Alternatives Considered & Rejected
- **Symlink the root `validate.yml` to the template copy:** GitHub Actions does
  not reliably load symlinked workflow files; a test-enforced identical copy
  is the safer option.
- **`flake.nix` + `flake.lock`:** the only form Dependabot could bump
  natively, but it changes the whole workflow (`nix develop`, `.envrc`, hooks,
  CI, docs) for what is a small problem here.
- **npins or niv:** adds a tool and a JSON file and moves the duplication
  without Dependabot support.
- **A single shared `nixpkgs-pin.nix` imported by both shells:** does not work
  because `template/` is rendered into generated projects, which need their own
  copy.
- **Merging the two Dependabot entries with `directories:`:** suggested in
  review, left out because the option is unverified and two entries work.
- **A `just bump-nixpkgs` recipe:** would automate refreshing both files, but it
  is extra surface; documenting the manual bump is proportionate for now.
- **Leaving the floating channel:** rejected; it caused the failing CI that
  prompted this change.

## Known follow-ups and risks
- The pin goes stale in every generated project until bumped by hand.
- Existing projects running `copier update` must take the `shell.nix` and
  `validate.yml` changes together (the workflow no longer sets `nix_path`).
- The template's `pr-review.yml` still uses `menil/pr-code-review-action@main`
  until release tags exist.
- The template's own CI has not yet run on GitHub with the pin (notably whether
  `copier` and the other tools are cached for this revision).
