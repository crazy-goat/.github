# Contributing

Thanks for helping! This is the default guide for all `crazy-goat` repositories.
A repository may add its own commands in `AGENTS.md` or `README.md`.

## Language

Write everything in **English**: code, comments, commit messages, documentation,
issues, pull requests. Translations of documents may live next to the originals
(for example `README.pl.md`). Test data and locale strings may contain any language.

## Find something to work on

- [`good first issue`](https://github.com/search?q=org%3Acrazy-goat+label%3A%22good+first+issue%22+state%3Aopen&type=issues):
  small, clear tasks. Each has a **Where to start** section.
- [`help wanted`](https://github.com/search?q=org%3Acrazy-goat+label%3A%22help+wanted%22+state%3Aopen&type=issues):
  bigger tasks where help is welcome.
- Comment on the issue before you start, so nobody works on it twice.
- For a new idea, open an issue first and describe the problem.

## Build and test

See the `README.md` and `AGENTS.md` of the repository. All tests and linters
must pass before you open a pull request.

## Branches and commits

- Branch from the default branch: `feat/issue-<N>-<short-slug>`,
  `fix/issue-<N>-<short-slug>`, `docs/...`, `chore/...`.
- Use [Conventional Commits](https://www.conventionalcommits.org/):
  `feat: add X`, `fix: handle Y`, `docs: ...`, `test: ...`, `chore: ...`.
- Keep a pull request focused on one issue.

## Pull requests

1. Open the PR against the default branch. Use `Closes #<N>` in the description.
2. Add an entry under `[Unreleased]` in `CHANGELOG.md` for every user-visible change.
3. Update the documentation and add tests.
4. Wait for CI (`ci-ok`) to pass. PRs are merged with **squash**; the PR title
   becomes the commit message, so make it a Conventional Commit.

If you are a first-time contributor, a maintainer must approve the first CI run.

## Found a problem on the way?

Open a separate issue instead of fixing it in the same PR. Small and clear
problems are welcome as `good first issue`.

The full process is described in `docs/workflow.md` of each repository
(template: [standard/workflow.md](https://github.com/crazy-goat/.github/blob/main/standard/workflow.md)).
