# Lint contract (`bin/lint.sh`)

Every repository has `bin/lint.sh`. The name and the behaviour are the same everywhere;
the tools inside depend on the project.

## Behaviour

- `bin/lint.sh` only checks. It runs every step, even after one fails, and exits
  non-zero if any step failed.
- `bin/lint.sh --fix` runs formatters and auto-fixers (for example `phpcbf`,
  `php-cs-fixer fix`, `rector process`, `gofmt -w`) and then checks again.
- It covers every language in the repository: static analysis, linter and formatter
  check for each one, plus `shellcheck` on shell scripts and `hadolint` on Dockerfiles
  when the repository has them.
- It needs only the tools that `bin/worktree-setup.sh` (or the CI setup step) installs.
  A missing tool is a failure, not a skip.

## CI

The `lint` job in the tests workflow does setup (language runtime, `composer install`,
tool installation) and then runs only `bin/lint.sh`. It is gated on
`needs.changes.outputs.code == 'true'` and required by `ci-ok`.

Composer scripts and Make targets (`composer lint`, `make lint`) call `bin/lint.sh`,
so humans, agents and CI run the same checks.

## Template

```bash
#!/usr/bin/env bash
# Run all static analysis, linters and formatter checks. --fix applies fixes first.
set -uo pipefail
cd "$(dirname "$0")/.."

FIX=0
[ "${1:-}" = "--fix" ] && FIX=1
failed=()

step() {
    local name="$1"; shift
    echo "==> $name"
    "$@" || failed+=("$name")
}

if [ "$FIX" = 1 ]; then
    vendor/bin/rector process
    vendor/bin/php-cs-fixer fix
fi

step "php-cs-fixer" vendor/bin/php-cs-fixer fix --dry-run --diff
step "rector" vendor/bin/rector process --dry-run
step "phpstan" vendor/bin/phpstan analyse --no-progress
step "shellcheck" bash -c 'git ls-files -z "*.sh" | xargs -0 -r shellcheck'

if [ "${#failed[@]}" -gt 0 ]; then
    echo "Failed: ${failed[*]}" >&2
    exit 1
fi
echo "All checks passed."
```
