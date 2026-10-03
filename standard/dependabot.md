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
- `phpstan/phpstan` and `rector/rector` are in one group (see below).

## Group: `php-static-analysis` (phpstan + rector)

**Do not remove this group.** It is not tidiness; it is a correctness requirement.

```yaml
groups:
  php-static-analysis:
    patterns:
      - phpstan/phpstan
      - rector/rector
```

Rector reaches into PHPStan's private API. Rector's `PrivatesAccessor` reads the
private `$container` property of `PHPStan\Parser\RichParser`, and PHPStan removed that
property in **2.2.6**. So **Rector below 2.5.8 fatals as soon as PHPStan reaches
2.2.6** (trace abridged; the first frame and the absolute paths are left out):

```
Fatal error: Uncaught Rector\Exception\Reflection\MissingPrivatePropertyException:
Property "$container" was not found in "PHPStan\Parser\RichParser" class
  in vendor/rector/rector/src/Util/Reflection/PrivatesAccessor.php:82
  #1 PHPStanContainerMemento.php(24)->getPrivateProperty()
  #2 PhpParser/Parser/RectorParser.php(32)->PHPStanContainerMemento::removeRichVisitors()
```

The same fatal hit two repositories in two days, both on PHPStan 2.2.16:
`rabbit-stream` #573 on 2026-10-02 (Rector `~2.4.0`, run 37011351319) and `piper-php`
#6 on 2026-10-03 (Rector 2.3.9, run 37104509394). Rector fixed it in **2.5.8**
(2026-07-27, "Bump to PHPStan ^2.2.6 and Fix its Container compatibility in
RichParser"), hardened it in 2.5.9 ("Wire `RichParser` node visitors via DI factory
instead of private property hack") and 2.6.5 ("Support PHPStan 2.2.10 scope
changes"), and 2.6.7 (2026-09-13) raised its own requirement to `phpstan ^2.2.14`.

So the two versions are **not independently selectable**. The important detail is that
the broken Rector versions *allowed* the bad PHPStan in their own constraints — 2.3.9
declares `phpstan ^2.1.40`, and 2.4.6 and 2.5.7 declare `^2.2.2`, all of which a
caret range happily resolves against PHPStan 2.2.16. Composer therefore **cannot**
catch the bad pair, and no pin in `composer.json` warns about it either. Letting
Dependabot pick each package on its own produced two PRs that could never go green.
The pair that works today is **rector 2.6.7 + phpstan 2.2.16** (proved by `fdb-php`
#134, run 37048347861: rector 2.6.7 starts and runs to the end of the dry run instead
of fatalling, and `==> phpstan` reports `[OK] No errors`; the job then fails only on
the `--dry-run` diff, see below).

A red Dependabot PR is not just noise: Dependabot keeps the same pull request open and
rebases it onto newer releases rather than opening a second one (rabbit-stream #573
was rerun three times on 2026-10-02, never replaced), so the bump cannot land until
someone fixes the PR. Grouping means a PHPStan bump arrives with the Rector bump it
needs, in one PR that can be reviewed on its own terms.

### The rule that follows

**Floor:** PHPStan 2.2.6 or newer will not run on a Rector below 2.5.8. Nothing is
broken below 2.2.6 — Rector 2.5.7 is fine on PHPStan 2.2.5 — so do not raise Rector on
a repository that is not already on 2.2.6.

**Verified:** on PHPStan 2.2.16 the versions shown to work are Rector **2.6.3**
(`fdb-php` `master`, green, "All checks passed") and **2.6.7** (run 37048347861).
2.5.8 is only the floor that avoids the fatal; it is not the combination anyone here
runs. 2.6.5 added PHPStan 2.2.10 scope support but is not shown to run 2.2.16.

### Rollout

Adding the group is the fix, and until a repository has it the rule above is not yet
applied anywhere. Three pull requests started this and are still open and red:
`piper-php` #6 (PHPStan 2.1.45 → 2.2.16 against Rector 2.3.9), `rabbit-stream` #573 and
`fdb-php` #134. Add the group first, then let Dependabot rebase them — that is what
turns each of them into a PR that can go green.

### What the group does *not* do

It does not make the PR green. A new Rector rule or a new PHPStan check can still
need a code change, and then the grouped PR is where that change lands. `fdb-php` #134
is exactly this: Rector 2.6.7 runs cleanly next to PHPStan 2.2.16 and fails only
because `IfToNullCoalescingAssignRector` (added in 2.6.4) wants one line changed in
`tests/Integration/RebootWorkerTest.php:113`. Grouping turns "two permanently red
PRs" into "one PR that needs a small fix".

### Why PHP-CS-Fixer is not in the group

There is no version coupling between `friendsofphp/php-cs-fixer` and PHPStan; it does
not read PHPStan's internals. Adding it would only make routine formatting bumps wait
on static-analysis bumps. Left out on purpose.

### Syntax notes

- `groups` sits **inside** the `composer` entry, not at the top level. Repeat it for
  every `composer` entry if a repository has more than one `directory`.
- `patterns` matches the dependency **name**, and both `patterns` and
  `exclude-patterns` support `*` as a wildcard. So `phpstan/*` is valid and is the
  better choice for a repository that also installs a PHPStan extension: it pulls
  `phpstan/phpstan-phpunit` and friends into the same PR (`elephas` and
  `the-consoomer` both install `phpstan/phpstan-phpunit`). Listing
  `phpstan/phpstan` and `rector/rector` is the minimum, not the whole story.
- A dependency matched by both `patterns` and `exclude-patterns` is **excluded** from
  the group. An ignored dependency gets no version-update pull request at all, so it
  cannot end up in this group either.
- Order matters between groups: a dependency matching more than one rule goes into the
  **first** group it matches.

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
    groups:
      php-static-analysis:
        patterns:
          - phpstan/phpstan
          - rector/rector
  - package-ecosystem: github-actions
    directory: "/"
    schedule:
      interval: weekly
    labels:
      - dependencies
    commit-message:
      prefix: "ci(deps)"
```
