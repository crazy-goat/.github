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

## Minimum tools per language

Every language in a repository gets static analysis, a linter and a formatter check.
Levels may start low; raise them in small follow-up issues, never lower them.

| Language | Static analysis | Linter / refactoring | Formatter check |
|---|---|---|---|
| PHP | PHPStan (target level 8 or higher; a baseline only with a follow-up issue) | Rector (`--dry-run`) | PHP-CS-Fixer (`--dry-run`) |
| Go | `go vet` | golangci-lint v2 (default linters at least) | gofmt / goimports through golangci-lint formatters |
| C / C++ | clang-tidy | clang-tidy checks | clang-format (`--dry-run --Werror`) |
| JS / TS | TypeScript `tsc --noEmit` where TS is used | ESLint | Prettier (`--check`) |
| Python | ruff (or mypy for typed code) | ruff | ruff format (`--check`) |
| Shell | shellcheck | shellcheck | — |
| Dockerfile | hadolint | hadolint | — |

Vendored or generated code is excluded. PHP_CodeSniffer (phpcs) is replaced by
PHP-CS-Fixer when a repository is next touched.

## CI

The `lint` job in the tests workflow does setup (language runtime, `composer install`,
tool installation) and then runs only `bin/lint.sh`. It is gated on
`needs.changes.outputs.code == 'true'` and required by `ci-ok`.

Pin every tool version in CI. Do not use the `shellcheck` that the `ubuntu-latest`
image ships; an image update would break `lint` without a change in the repository.
Install release binaries instead, for example:

```yaml
- name: Install shellcheck and hadolint
  run: |
    mkdir -p "$HOME/.local/bin"
    curl -fsSL https://github.com/koalaman/shellcheck/releases/download/v0.11.0/shellcheck-v0.11.0.linux.x86_64.tar.xz \
      | tar -xJ --strip-components=1 -C "$HOME/.local/bin" shellcheck-v0.11.0/shellcheck
    curl -fsSL -o "$HOME/.local/bin/hadolint" https://github.com/hadolint/hadolint/releases/download/v2.12.0/hadolint-Linux-x86_64
    chmod +x "$HOME/.local/bin/hadolint"
    echo "$HOME/.local/bin" >> "$GITHUB_PATH"
```

clang-format comes from PyPI through `pipx` (`pip install --user` fails on PEP 668
images). The runner sets `PIPX_BIN_DIR` and ships its own `/usr/bin/clang-format`, so
pin the location and call the binary by full path once:

```yaml
- name: Install clang-format
  run: |
    mkdir -p "$HOME/.local/bin"
    PIPX_BIN_DIR="$HOME/.local/bin" pipx install clang-format==23.1.2
    "$HOME/.local/bin/clang-format" --version
    echo "$HOME/.local/bin" >> "$GITHUB_PATH"
```

hadolint 2.12 does not accept text after `# hadolint ignore=DLxxxx`; put the reason on
the line above.

Composer scripts and Make targets (`composer lint`, `make lint`) call `bin/lint.sh`,
so humans, agents and CI run the same checks.

## Template

```bash
#!/usr/bin/env bash
# Run all static analysis, linters and formatter checks. --fix applies fixes first.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1

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
