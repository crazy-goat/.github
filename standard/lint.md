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

A repository that builds a PHP extension can end up with a build of that extension
installed on a contributor's machine: a leftover `make install`, a release install, an
`extension=` line in `php.ini`, or an `.ini` in the scan directory. It then loads into
**every** `php` on that machine. PHPStan and Rector run *inside* a PHP process, so the
lint result depends on what that process has loaded and not only on the working tree —
a local run and CI can disagree with no commit in between.

**How** a loaded extension changes things differs per repository, so find out which
case is yours before changing anything. None of the three PHP extensions below has a
class-name collision — none of them shadows a class the working tree defines. One of
them can change a lint result, and one is only reached at runtime.

- **The library extends a class only the extension defines.** `ScanMePHP`:
  `src/NativeEncoder.php` declares `NativeEncoder extends NativeEncoderCore`, and
  `NativeEncoderCore` is defined *only* by `php-ext/native_encoder.c` — and only inside
  `if (extension_loaded('scanmeqr'))`, with a pure-PHP `else` branch. The dependency
  runs the other way round: `php-ext/composer.json` says the extension "exposes only
  `NativeEncoderCore`, which builds a `CrazyGoat\ScanMePHP\Matrix` and therefore needs
  the library loaded". The lint result is unaffected, because `phpstan.neon` excludes
  `src/NativeEncoder.php` from analysis. What is machine-dependent here is the
  **runtime**: which of the two implementations exists depends on what is loaded.
- **The extension's names live in a separate namespace and the analysis reads a stub.**
  `ladybug-php`: `ext/` registers seven classes under `Ladybug\Ext\` while the library is
  `Ladybug\`, and `phpstan.neon` analyses `src/` against
  `stubs/ladybug-ext.stub.php`, which declares those seven classes plus the 21 global
  `ladybug_*` functions. Nothing collides, but the loaded extension **hides what the
  stub omits**. That last part is measured and recorded in that repository's
  `AGENTS.md`: drop `Result` from the stub, or `ladybug_version()`, and PHPStan reports
  "class not found" / "function not found" with no extension and nothing at all with it,
  so a stub that has fallen behind the extension passes locally and fails in CI. Change
  a signature the stub *already* declares and the stub still wins; only missing entries
  are hidden. (`ladybug-php` #139 tracks keeping the two in agreement.)
- **The extension is reached only at runtime.** `php-zvec`: `php-ext/` registers 15
  types (12 classes, 3 interfaces) in the **global** namespace while `src/` is
  `CrazyGoat\ZVec\`. PHPStan and Rector parse `src/` and never run the guard; what
  breaks is the **test suite**, at `src/ZVec.php:9`, which returns early when
  `extension_loaded('zvec')` so the barrel file never loads the FFI-only classes
  (`php-zvec` #188).

A genuine collision — the extension defining the same class name the library defines in
`src/`, so the analysis silently runs against the installed build instead — would be the
worst case of all, because it moves findings onto code nobody touched. Check for it, by
comparing the classes `php-ext` registers with the `src/` namespace in `composer.json`,
before assuming your repository behaves like the three above.

### Isolating the tools, when a repository needs it

Not with `php -n`. It looks right and it is not, for two separate reasons (`php-zvec`
#259 and `ladybug-php`'s `AGENTS.md` both record both):

- it drops the whole ini scan directory, so on a `setup-php` image PHPStan loses `Phar`
  and Rector loses `PhpToken` and **both fail to start**, with `Class "Phar" not found`
  and `Class "PhpToken" not found` — which is how the first push of `php-zvec` #259
  failed `lint`;
- and it does not reach the processes PHPStan starts for itself. PHPStan restarts with
  `PHP_BINARY -d …` and spawns parallel workers, neither carrying `-n`, so those
  processes load `php.ini` again.

Use an **environment variable** instead, because those are inherited:

- `PHPRC` for an extension enabled in `php.ini`. Point it at an ini generated per run.
- `PHP_INI_SCAN_DIR` for an extension enabled as a file in the scan directory: point it
  at a copy of that directory with the extension's `.ini` left out, so everything else
  stays available.

Replacing `php.ini` takes its settings with it, so carry them into the generated ini:
**`extension_dir`** (a Homebrew/pecl setup sets it in `php.ini` while the `conf.d`
entries name their extension without a path, so without it those extensions fail to
load), **`memory_limit`** (otherwise the built-in 128M applies), and **FFI** where the
analysis would otherwise have none. `php-zvec`'s `bin/lint.sh` does all of that in one
`php_analysis` helper; ask for FFI in the CI `lint` job as well (`extensions: ffi`).
Note the residual gap this leaves: an `extension=` line in `php.ini` no longer reaches
the tools, one in a `conf.d` file still would.

When a lint run disagrees with CI, `php -m` under the same ini settings is the first
thing to check — run any other way it answers a different question.

A loaded extension is invisible in the command line, so document the requirement in
`AGENTS.md` too: the test suite needs the same treatment as the linters. Say there which
of the cases above applies, and do not claim the isolation fixed a wrong result unless
you can point at one — isolating the tools removes a machine dependency, it does not by
itself prove anything was wrong before.

## PHP tool versions: `composer.lock` (proposed — needs Piotr's sign-off)

**Status: proposed, not agreed.** This section records one option with its reasoning.
It is not the standard until Piotr decides, and a repository that already does
something else is not wrong yet.

The standard rollout left one question open: several PHP libraries gitignore
`composer.lock`, so Rector / PHPStan / PHP-CS-Fixer versions float in CI and a tool
release can turn `lint` red without a commit. `ScanMePHP` #251 carries the question.
It is worse than theory: in `fdb-php` and `rabbit-stream` the job that needs the dev
tools runs `composer install`, and with no lock file Composer 2 turns that into a full
update against packagist and says so:

```
No composer.lock file present. Updating dependencies to latest instead of
installing from lock file. See https://getcomposer.org/install for more information.
```

It has the concrete loss: in `ScanMePHP` a newer Rector (2.6.6) reported
`FlipNegatedTernaryInstanceofRector` in code nobody had changed.

### Proposal: commit `composer.lock`, and keep a caret range in `require-dev`

Drop `composer.lock` from `.gitignore` and commit it. Do **not** pin the tools to an
exact version in `require-dev` — keep `^` or `~` there.

The two options are not really alternatives; they do different jobs.

- The **range** in `require-dev` is the compatibility claim: "this code works with
  PHPStan 2.x".
- The **lock file** is reproducibility: "CI installs these exact bytes". Only the
  lock freezes transitive dependencies.

Dependabot updates exact pins as happily as ranges, so the range is not there to make
Dependabot work: `piper-php` #6 took an exact `"phpstan/phpstan": "2.1.45"` to `2.2.16`
and `fdb-php` #134 took an exact `"rector/rector": "2.6.3"` to `2.6.7`.

### Why the lock, and not exact pins

A lock file and exact pins both stop the tool versions from floating, but they do not
close the same gap, and the difference is what this proposal is actually about.

Exact pins name only the packages someone remembered. Every other dependency still
resolves fresh on every run, so a `require-dev` full of exact versions still leaves
everything it did not name free to move — the transitive trees, and any tool that was
not pinned in the first place.

Two honest caveats, because they cut the other way:

- The Rector/PHPStan breakage was between two **direct** dev dependencies, so exact
  pins *would* have caught it. `fdb-php` is green on exactly that basis. It is not
  evidence against pins in general.
- Rector is not a good example of a moving transitive: its own `composer.json`
  requires only `php` and `phpstan/phpstan` (2.6.7 requires `php ^7.4|^8.0` and
  `phpstan/phpstan ^2.2.14`, nothing else) and ships the rest **bundled** inside the
  package, which is why `vendor/rector/rector/vendor/illuminate/...` shows up in the
  stack trace. `php-cs-fixer` and `phpunit` are the dependencies that actually drift.

That is the whole case for the lock: not the one incident, but every future release
of the other dev tools, pinned without a human editing a version number each time.

A committed lock is never read by anyone who installs the library as a dependency —
Composer resolves that consumer's own tree from their `require` ranges. So the lock
cannot change what a consumer gets. It does change what the library's **own tests**
run against, and that is the cost that decides the question for a library: a locked
`composer install` in CI stops exercising the newest versions the `require` ranges
hand to users, so a breaking upstream release is found by a consumer rather than by
this repository. The usual mitigation is a second CI job that runs the tests against a
freshly resolved tree (`composer update`, and `composer update --prefer-lowest` for
the floor), which keeps the lock as the fast, reproducible default and still tests the
edges.

### The trade-off, stated

|                                 | commit the lock    | exact pins in `require-dev` |
|---------------------------------|--------------------|-----------------------------|
| direct dev tools frozen         | yes                | yes                         |
| transitive dev deps frozen      | yes                | no                          |
| `composer install` repeatable   | yes                | no                          |
| Dependabot still opens PRs      | yes                | yes                         |
| diff size                       | large, lock churn  | tiny                        |
| conflicts on parallel branches  | possible           | none                        |
| **tests run only against the locked tree** | **yes** | no              |

That last row is the one that matters for a library and it is the strongest argument
against the lock. Both columns have a cost, and a decision-maker should see both.

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
