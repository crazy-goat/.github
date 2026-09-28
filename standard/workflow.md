# Workflow: issue → branch → implementation → review → PR → CI → merge

This is the development process of every `crazy-goat` repository. Project
commands (build, lint, tests) live in [`AGENTS.md`](../AGENTS.md) and are not
repeated here. The process is the same for humans and for coding agents.

Everything is written in **English**: code, comments, commits, docs, issues, PRs.

## Rules in short

- One issue = one branch = one pull request.
- Work is driven by the **lowest open milestone** (`vX.Y.Z`).
- Every open issue has one `type:*` and one `priority:*` label.
- Merge with **squash** only, and only when CI (`ci-ok`) is green.
- Update `CHANGELOG.md` in every PR that changes user-visible behaviour.

## 1. Pick an issue

```bash
gh api repos/{owner}/{repo}/milestones --jq '[.[] | select(.state=="open")] | sort_by(.title) | .[0].title'
gh issue list --milestone "<lowest milestone>" --state open --limit 100 \
  --json number,title,labels
```

- `gh issue list` returns 30 items by default. Always pass `--limit 100` or more.
- Pick by priority: `priority:critical` → `high` → `medium` → `low`.
- Skip issues with `status:blocked` or `status:needs-info`.
- **Release gate:** if the lowest milestone has no open issues, stop. Cut the
  release first (see [release-workflow.md](release-workflow.md)), then pick again.
  Do not take issues from a higher milestone.
- Read the issue, including **Where to start** and **Definition of done**.

## 2. Create a branch

Always start from an up-to-date default branch:

```bash
git switch <default-branch> && git pull --ff-only
git switch -c <type>/issue-<N>-<short-slug>     # feat/, fix/, docs/, refactor/, test/, chore/
```

## 3. Implement

- Make the smallest correct change that satisfies the Definition of done.
- Add or update tests. A bug fix starts with a test that fails.
- Run the checks from `AGENTS.md` until they pass.
- Commit with [Conventional Commits](https://www.conventionalcommits.org/):
  `fix: handle empty response (#42)`.
- Update `CHANGELOG.md` under `[Unreleased]` (Added / Changed / Fixed / ...).

## 4. Review

Review your own diff before opening the PR. A second pair of eyes — a
teammate or a separate review agent with a fresh context — is better.

Check: correctness, error handling, missing tests, outdated docs, unrelated
changes, leftovers (debug code, commented-out code), and that everything is in
English. Fix the findings and review again until there are none.

### Findings outside the task

When you notice a problem that is **not part of this issue**, do not fix it in
the same PR. Open a new issue, in English, with a `type:*` and a `priority:*` label:

| The problem is... | Add label |
|---|---|
| small and clear, a newcomer can fix it | `good first issue` |
| bigger, but not urgent | `help wanted` |

A `good first issue` must have the **Where to start** section filled in (files
to change, the command that runs the tests) and a **Definition of done**.
Without them the label does not help anybody.

Assign the new issue to a milestone (usually the next one).

## 5. Open the pull request

```bash
git push -u origin HEAD
gh pr create --fill --body "Closes #<N>"
```

- The PR title is a Conventional Commit. With squash merge it becomes the
  commit message on the default branch.
- Use the PR template. Put `Closes #<N>` in the description.
- Keep the PR focused. Refactorings and unrelated fixes go to separate PRs.

## 6. CI

```bash
gh pr checks --watch
```

- The required check is `ci-ok`. It passes only when all CI jobs pass.
- If CI fails, read the log (`gh run view --log-failed`), fix the cause and push.
  Do not disable or skip a check to make it green.
- PRs from first-time contributors need a maintainer to approve the workflow run.

## 7. Merge

```bash
gh pr merge --squash --delete-branch
```

Then update the local repository and check that the issue was closed:

```bash
git switch <default-branch> && git pull --ff-only
gh issue view <N> --json state
```

When the merge empties the milestone, go to
[release-workflow.md](release-workflow.md).

## Checklist

- [ ] Issue has `type:*`, `priority:*` and a milestone
- [ ] Branch name is `<type>/issue-<N>-<slug>`
- [ ] Tests added, all checks pass locally
- [ ] `CHANGELOG.md` updated
- [ ] Docs updated
- [ ] Findings outside the task became separate issues
- [ ] PR title is a Conventional Commit and the description has `Closes #<N>`
- [ ] `ci-ok` is green, PR merged with squash
- [ ] Local branch deleted, worktrees cleaned up
