# Dependabot

Every repository has Dependabot turned on.

- **Settings** (`bin/sync.sh` applies them): Dependabot alerts and Dependabot security
  updates are on.
- **`.github/dependabot.yml`**: weekly version updates for every package manager in the
  repository (every `go.mod`, `composer.json`, `package.json`, Dockerfile directory that
  is maintained, and `github-actions` at `/`). Vendored or example code that is not
  maintained is left out.
- Labels: only `dependencies` (from `labels.json`). Commit prefix `chore(deps)`, and
  `ci(deps)` for `github-actions`.
- Dependabot PRs go through the same `ci-ok` check. Workflows must not block
  `dependabot[bot]` (for example through an actor check).

Example:

```yaml
version: 2
updates:
  - package-ecosystem: composer
    directory: "/"
    schedule:
      interval: weekly
    labels:
      - dependencies
    commit-message:
      prefix: "chore(deps)"
  - package-ecosystem: github-actions
    directory: "/"
    schedule:
      interval: weekly
    labels:
      - dependencies
    commit-message:
      prefix: "ci(deps)"
```
