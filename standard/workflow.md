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
- **Nothing found on the way is lost.** Every problem outside the task becomes a follow-up
  issue (see [step 8](#8-follow-up-findings)), never a silent fix in the same PR and never
  just a comment.

## 1. Pick an issue

```bash
bin/pick-issue.sh                 # top 5 of the lowest open milestone
bin/pick-issue.sh --top=10        # more candidates
bin/pick-issue.sh --milestone=v1.2.0
bin/pick-issue.sh --json          # machine-readable, for agents
```

The script needs only `gh`. It finds the **lowest open milestone**, scores its
open issues from labels, title, age and comment count (it never reads issue
bodies, so it is cheap for an agent), and prints the top candidates with the
score breakdown. You still make the final pick. Blocked issues
(`status:blocked`, `status:needs-info`) are ranked last.

- **Release gate:** when the lowest milestone has no open issues left, the script
  exits with code **3** and prints `RELEASE NEEDED`. Stop. Cut the release first
  (see [release-workflow.md](release-workflow.md)), then run the script again.
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

Write down every problem you notice that is **not part of this issue**: a bug, a weak
spot, missing tests, outdated docs, duplicated code. Do not fix it in this PR. Keep a
short list (file, line, what is wrong, suggested fix) and turn it into issues in
[step 8](#8-follow-up-findings). Coders and reviewers, human or agent, must report
such findings in their result.

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

Then do [step 8](#8-follow-up-findings). When the merge empties the milestone, go to
[release-workflow.md](release-workflow.md) afterwards.

## 8. Follow-up findings

Run this step **after every merge**, and do not skip it for small PRs. It turns
everything found during the work into tracked issues.

1. Collect the findings: the list from step 3 and step 4, plus a **post-merge review**
   of the merged change (a review agent with a fresh context, or a teammate). Ask it
   only for follow-ups: regressions, incomplete fixes, new risks, gaps.
2. **Check for duplicates first**, for each finding:

   ```bash
   gh issue list --state all --search "<keywords>" --json number,title,state \
     --jq '.[] | "#\(.number): \(.title) [\(.state)]"'
   ```

   - An open issue already covers it: add a comment with the link to the merged PR.
   - A closed issue covers it and the problem is back: open a new issue and link the old one.
   - Nothing covers it: continue with step 3.
3. Create the issue, in English:

   ```bash
   gh issue create --title "<what is wrong>" --milestone "<milestone>" \
     --label "type:bug" --label "priority:medium" --label "good first issue" \
     --body-file finding.md
   ```

   The body follows the issue form: **Description** (what, where as `file:line`, impact,
   link to the merged PR), **Where to start**, **Definition of done**.
4. Labels and milestone:

   | The finding is... | Labels |
   |---|---|
   | small and clear, a newcomer can fix it | `type:*`, `priority:*`, `good first issue` |
   | bigger, but not urgent | `type:*`, `priority:*`, `help wanted` |
   | urgent (data loss, security, crash) | `priority:critical`, milestone = the lowest open one |
   | needs a decision or more information | `status:needs-info` |

   Put it in the lowest open milestone when it must ship with the current release,
   otherwise in the next one. A `good first issue` without **Where to start** does not
   help anybody, so fill it in.
5. Report the numbers of the created and updated issues in the final message of the task.

## Checklist

- [ ] Issue picked with `bin/pick-issue.sh`; it has `type:*`, `priority:*` and a milestone
- [ ] Branch name is `<type>/issue-<N>-<slug>`
- [ ] Tests added, all checks pass locally
- [ ] `CHANGELOG.md` updated
- [ ] Docs updated
- [ ] Findings from the work and from the post-merge review became issues (duplicates checked)
- [ ] PR title is a Conventional Commit and the description has `Closes #<N>`
- [ ] `ci-ok` is green, PR merged with squash
- [ ] Local branch deleted, worktrees cleaned up
