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

## When the project is itself a PHP extension

A repository that builds a PHP extension can end up with an older build of that
same extension installed on a contributor's machine (a leftover `make install`, a
packaged release, an `extension=` line in a `php.ini`). The loaded extension
defines the very class names that also live under `src/`, and PHP resolves those
to the loaded extension's classes.

PHPStan and Rector run *inside* a PHP process, so they see what that process has
loaded, not only what is on disk: the analysis and the refactors are then run
against classes the working tree never provided, and findings point at code the
diff did not touch (or the class under `src/` is simply not found). The same
shadowing breaks the test suite, usually with a `Class "..." not found` for a
class that is right there in `src/`.

Run PHPStan and Rector with the project's own extension **not** loaded —
`php -n vendor/bin/phpstan analyse`, the same for Rector, or an ini that does not
load it — and keep that in `bin/lint.sh`, so humans, agents and CI all get the
same view. `-n` ignores every `php.ini`, so check that the extensions the project
genuinely needs are still available (many are compiled in, some are not). A
loaded extension is invisible in the command line, so document the requirement in
`AGENTS.md` too — the tests need the same treatment as the linters.

## PHP tool versions: `composer.lock` (proposed — needs Piotr's sign-off)

**Status: proposed, not agreed.** This section records one option with its reasoning.
It is not the standard until Piotr decides, and a repository that already does
something else is not wrong yet.

The standard rollout left one question open: several PHP libraries gitignore
`composer.lock`, so Rector / PHPStan / PHP-CS-Fixer versions float in CI and a tool
release can turn `lint` red without a commit. No repository is wrong for that yet;
`ScanMePHP` #251 carries the question. It is worse than theory: in `fdb-php` and
`rabbit-stream` the job that needs the dev tools runs `composer install`, and with no
lock file Composer 2 turns that into a full update against packagist and says so:

```
No composer.lock file present. Updating dependencies to latest instead of
installing from lock file.
```

`ScanMePHP` #251 has the concrete loss: a newer Rector (2.6.6) reported
`FlipNegatedTernaryInstanceofRector` in code nobody had changed.

### Proposal: commit `composer.lock`, and keep a caret range in `require-dev`

Drop `composer.lock` from `.gitignore` and commit it. Do **not** pin the tools to an
exact version in `require-dev` — keep `^` or `~` there.

The two options are not really alternatives; they do different jobs.

- The **range** in `require-dev` is the compatibility claim: "this code works with
  PHPStan 2.x". Dependabot needs a range it is allowed to widen.
- The **lock file** is reproducibility: "CI installs these exact bytes". Only the
  lock freezes transitive dependencies.

### Why the lock, and not exact pins

A lock file and exact pins both stop the tool versions from floating, but they do not
close the same gap, and the difference is what this proposal is actually about.

Exact pins name only the packages someone remembered. Every other dependency still
resolves fresh on every run, so a `require-dev` full of exact versions still pulls a
moving `php-cs-fixer`, `phpunit`, and their transitive trees.

Two honest caveats, because they cut the other way:

- The Rector/PHPStan breakage was between two **direct** dev dependencies, so exact
  pins *would* have caught it. `fdb-php` is green on exactly that basis. It is not
  evidence against pins in general.
- Rector is not a good example of a moving transitive: its own `composer.json`
  requires only `php` and `phpstan/phpstan` and ships the rest **bundled** inside the
  package (`vendor/rector/rector/vendor/illuminate/...` shows up in the stack trace).
  `php-cs-fixer` and `phpunit` are the dependencies that actually drift.

That is the whole case for the lock: not the one incident, but every future release
of the other dev tools, pinned without a human editing a version number each time.

The usual "a library must not commit a lock file" advice does not apply here. That
advice exists so an *application* stays reproducible without shipping its users'
resolved versions; a library has no lock of its own to keep, and a committed lock in
one is never read by anyone who installs it as a dependency. It costs consumers
nothing and only pins our own CI.

### The trade-off, stated

|                                 | commit the lock    | exact pins in `require-dev` |
|---------------------------------|--------------------|-----------------------------|
| direct dev tools frozen         | yes                | yes                         |
| transitive dev deps frozen      | yes                | no                          |
| `composer install` repeatable   | yes                | no                          |
| Dependabot still opens PRs      | yes                | yes                         |
| diff size                       | large, lock churn  | tiny                        |
| conflicts on parallel branches  | possible           | none                        |

The honest cost is conflicts in a large `composer.lock` when two branches add
different dependencies. That is a normal conflict in a file whose meaning is obvious,
and it is cheaper than a red `lint` nobody can reproduce.

### What the repositories already show

- `piper-php`, `IsItDark` and `workerman-bundle` already commit `composer.lock`.
- Committing it does **not** silence Dependabot: `piper-php` #6 is a
  `chore(deps): bump phpstan/phpstan from 2.1.45 to 2.2.16` PR that changes
  `composer.json` *and* `composer.lock`.
- `go-mesi` does it on purpose and wrote the reason into its `.gitignore`:
  "composer.lock is tracked on purpose: dependabot's composer ecosystem needs it to
  open security-update PRs for the worker".
- `fdb-php` is the counter-example in miniature. It pins `phpstan/phpstan` to exactly
  `2.2.16` and `rector/rector` to exactly `2.6.3` and still gitignores the lock. Its
  `master` is green today, so exact pins are not worthless — but they hold only
  because someone hand-edited two numbers, and nothing keeps them in step with the
  transitive tree.

### If exact pins is the decision instead

Keep the lock ignored, pin every dev tool exactly, and file a follow-up per tool
release. Cheaper per bump, tiny diffs, but it leaves the transitive hole open and
needs a human every time. If that is the call, rewrite this section rather than
deleting it.

### Related

The lock freezes whatever pair is currently installed; it does not pick a compatible
one. Rector and PHPStan must also move **together** — see `dependabot.md`.

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

The Composer tools need the same treatment. They arrive through `composer install`
rather than from the image, so how to pin them is a separate open question — see the
proposed section above, which is not agreed yet.

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
