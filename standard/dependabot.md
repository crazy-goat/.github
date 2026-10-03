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
- `phpstan/phpstan` and `rector/rector` belong in one group, because their versions
  are not independently selectable (see below). **No repository has this group yet.**

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

A red Dependabot PR is not just noise: it stays open and is rebuilt, so the bump
cannot land until someone fixes the PR. What is observed on `rabbit-stream` #573 is
three runs on 2026-10-02 for the same target version on three different head SHAs
(`37a1074`, `9ef8654`, `0b2ca3c`), never replaced by a new pull request. Grouping means
a PHPStan bump arrives with the Rector bump it needs, in one PR that can be reviewed on
its own terms.

### The rule that follows

**Floor:** PHPStan 2.2.6 or newer will not run on a Rector below 2.5.8. Nothing is
broken below 2.2.6 — Rector 2.5.7 is fine on PHPStan 2.2.5 — so do not raise Rector on
a repository that is not already on 2.2.6.

**Verified:** on PHPStan 2.2.16 the versions shown to work are Rector **2.6.3**
(`fdb-php` `master`, green, "All checks passed") and **2.6.7** (run 37048347861).
2.5.8 is only the floor that avoids the fatal; it is not the combination anyone here
runs. 2.6.5 added PHPStan 2.2.10 scope support but is not shown to run 2.2.16.

### Rollout

Adding the group is the fix, and as of 2026-10-03 no repository has it — checked in all
17.

**What already happened, on 2026-10-03, and is why the group is worth adding anyway.**
Three Dependabot pull requests were stuck for exactly this reason. All three are now
**closed**, each superseded by a hand-made pull request that moved both tools at once —
which is what the group would have produced:

| Closed, unmerged | Superseded by | What it took |
|---|---|---|
| `fdb-php` #134 (rector 2.6.3 → 2.6.7) | #136 | one line: `IfToNullCoalescingAssignRector` wants `??=` at `tests/Integration/RebootWorkerTest.php:113` |
| `rabbit-stream` #573 (`phpstan` `~2.1.0` → `~2.1.0 \|\| ~2.2.0`) | #582 | three `method.alreadyNarrowedType` findings, plus removing a now-redundant property initializer |
| `piper-php` #6 (`phpstan` 2.1.45 → 2.2.16) | #24 | nothing: 25 releases of Rector rules and `--dry-run` was empty |

So the group is not needed to unblock those three — they are done. It is needed so the
*next* phpstan bump arrives with a rector bump that can actually run next to it, instead
of against whatever rector happens to be pinned.

Note that a group changes what Dependabot opens on its **next** run. It does not absorb
an already-open single-dependency pull request, and `@dependabot rebase` does not help
either: `piper-php` #6 was rebuilt and re-run three times (head SHAs `26b558f`, `2fe528c`,
`af3b855`, all failing), the last after an explicit rebase on 2026-10-03, and stayed red.
The blocker was a version pin in `composer.json`, never the base branch.

### What the group does *not* do

It does not make a PR green. A new Rector rule or a new PHPStan check can still need a
code change, and then the grouped pull request is where that change lands — which is
exactly what the three pull requests above needed:

- The `fdb-php` case was the smallest: Rector 2.6.7 runs cleanly next to PHPStan 2.2.16
  and reported one finding, `IfToNullCoalescingAssignRector` (added in 2.6.4), while
  PHPStan reported `[OK] No errors`.
- `rabbit-stream` also carried three PHPStan 2.2.16 findings with nothing to do with
  Rector: `method.alreadyNarrowedType` in `tests/Buffer/ReadBufferTest.php:441`,
  `tests/Client/MessageTest.php:38` and `tests/E2E/SubscribeFilterE2ETest.php:106`.

A grouped bump can also be larger than the single bump it replaces. `piper-php`'s
`rector.php` has no `->withSkip()` at all and analyses four paths (`src`, `examples`,
`bin`, `tests`) with the `DEAD_CODE`, `CODE_QUALITY`, `TYPE_DECLARATION`,
`PRIVATIZATION` and `EARLY_RETURN` sets, so taking Rector from 2.3.9 to 2.6.7 crosses
**25 releases over three minor bumps** (2.4 → 2.6) and every rule added on the way
applies to all four paths. Expect more than one changed file, and budget for a fix pass
and a review of the diff — not for a version-line edit.

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
