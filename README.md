# crazy-goat/.github

Shared community health files and the repository standard for the
[crazy-goat](https://github.com/crazy-goat) organization.

GitHub uses `CONTRIBUTING.md`, `SECURITY.md`, `ISSUE_TEMPLATE/` and
`pull_request_template.md` from this repository as **defaults** for every
repository that does not have its own copy.

Everything in this repository, and in every repository of the organization, is
written in **English**: code, comments, commits, docs, issues, PRs, labels,
milestones and release notes. Polish is allowed only for separate document
translations, UTF-8 test data and locale UI strings.

## Contents

| Path | Purpose |
|---|---|
| `CONTRIBUTING.md`, `SECURITY.md` | Default contributor and security policy |
| `ISSUE_TEMPLATE/`, `pull_request_template.md` | Default issue forms and PR template |
| `.github/workflows/release.yml` | Reusable workflow: GitHub Release from the CHANGELOG |
| `standard/labels.json` | The one label list |
| `standard/settings.json` | Repository settings (squash only, ...) |
| `standard/ruleset.json` | Ruleset for the default branch (requires `ci-ok`) |
| `standard/workflow.md` | Template for `docs/workflow.md` |
| `standard/release-workflow.md` | Template for `docs/release-workflow.md` |
| `standard/pick-issue.sh` | Shared script, copied to `bin/pick-issue.sh` in every repository |
| `standard/renames/<repo>.tsv` | Per-repository label migration map |
| `bin/sync.sh` | Applies the standard to repositories with `gh api` |

## Applying the standard

The organization is on the GitHub Free plan, so organization-wide rulesets are
not available. `bin/sync.sh` applies the standard to each repository instead.
Always start with a dry run:

```bash
bin/sync.sh --dry-run the-consoomer          # show what would change
bin/sync.sh the-consoomer                    # labels + settings
bin/sync.sh --ruleset the-consoomer          # also the ruleset (needs a `ci-ok` job)
bin/sync.sh --dry-run --all                  # all supported repositories
```

Requirements: `gh` (logged in with admin rights on the repositories) and `jq`.

## Reusable release workflow

In a repository, create `.github/workflows/release.yml`:

```yaml
name: Release
on:
  push:
    tags: ['v*']
jobs:
  release:
    permissions:
      contents: write
    uses: crazy-goat/.github/.github/workflows/release.yml@main
```

It creates the GitHub Release with the notes of the matching `CHANGELOG.md`
section and fails when the section is missing or empty.

## Shared script: `bin/pick-issue.sh`

`standard/pick-issue.sh` is the single source of truth. Every repository carries an
identical copy in `bin/pick-issue.sh` (added together with `docs/workflow.md`).
Do not edit the copies. Change the file here and copy it again:

```bash
cp standard/pick-issue.sh ../<repo>/bin/pick-issue.sh
```

It works in any language stack (bash + `gh` only) and detects the repository from
the current directory.
