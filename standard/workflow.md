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
- **Nothing found on the way is lost.** The coder and the reviewer write down every
  problem they notice, and at the end a verification review checks which of them are
  real and not yet tracked, and they become issues (see [step 8](#8-follow-up-findings)).

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

**Coder output contract.** Whoever implements the change (a person, or a coder agent) always
reports: (1) the changed files, (2) the biggest problem met on the way, and (3) every bug or
weak spot noticed, **including ones outside this issue's scope**, each with `file:line` and a
suggested fix. Items (2) and (3) go into the findings file (see below), not only into the chat.

## 4. Review

Review your own diff before opening the PR. A second pair of eyes — a
teammate or a separate review agent with a fresh context — is better.

Check: correctness, error handling, missing tests, outdated docs, unrelated
changes, leftovers (debug code, commented-out code), and that everything is in
English. Fix the findings and review again until there are none.

### The findings file

Coder and reviewer append their findings to a scratch file that is **not committed** and
survives a compacted chat:

```bash
$(git rev-parse --git-dir)/findings.md
```

One entry per finding: role (`coder` / `review`), `file:line`, what is wrong, severity, and
whether it is in scope. Do not fix out-of-scope findings in this PR; they are handled in
[step 8](#8-follow-up-findings).

Every review round reads the file first. For each earlier finding it says: still present,
fixed, or not a real finding (with evidence). **Every finding gets an answer**, including
nits: fixed, deliberately not fixed (say why), or not real. Silence is not an answer. A
finding first seen in round 2 or later escaped round 1, which usually means a check is
missing, so prefer adding a test over only fixing the line.

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

Run this step **after every merge**, also for small PRs. It turns the findings collected
during the work into tracked issues, without duplicates.

1. **Collect** the candidates from the findings file (coder and review entries), plus the
   biggest problem the coder reported. Skip findings that were already fixed in this PR.
2. **Verify each candidate with a read-only review** (a review agent with a fresh context,
   or a teammate). It must not edit files and must not create, edit or close issues. For
   every candidate it confirms:
   1. **The finding is real.** Read the cited lines on the current default branch and check
      that the behaviour occurs and is reachable. Skip it when it is by design and documented.
   2. **It is not tracked yet.** Search open **and** closed issues. `gh` lists only 30 items by
      default, so always pass a limit:

      ```bash
      gh issue list --state open   --limit 200 --json number,title,labels
      gh issue list --state closed --limit 200 --json number,title,labels
      gh search issues --repo {owner}/{repo} --limit 50 "<keywords>"
      ```

      Overlapping scope counts as tracked. Check issues named in `CHANGELOG.md` explicitly.
   3. **A recommendation:** (a) create a new issue, with a proposed title and labels;
      (b) skip, already tracked (cite the number; the finding can add a comment there);
      (c) skip, not real or by design.
3. **Ask the maintainer** "Create GitHub issue(s) for these findings?" and show the
   verified list. Creating issues is visible to everybody, so do not do it silently unless
   the maintainer allowed it in advance. If they decline, record the outcome and finish.
4. **Create one issue per finding**, in English, with a `type:*` and a `priority:*` label
   and a milestone:

   ```bash
   gh issue create --title "<what is wrong>" --milestone "<milestone>" \
     --label "type:bug" --label "priority:medium" --label "good first issue" \
     --body-file finding.md
   ```

   The body follows the issue form: **Description** (what, where as `file:line`, impact, link
   to the merged PR), **Where to start**, **Definition of done**.

   | The finding is... | Labels |
   |---|---|
   | small and clear, a newcomer can fix it | `type:*`, `priority:*`, `good first issue` |
   | bigger, but not urgent | `type:*`, `priority:*`, `help wanted` |
   | urgent (data loss, security, crash) | `priority:critical`, the lowest open milestone |
   | needs a decision or more information | `status:needs-info` |

   Use the lowest open milestone when it must ship with the current release, otherwise the
   next one. A `good first issue` without **Where to start** helps nobody, so fill it in.
5. **Report** the numbers of the created and commented issues in the final message.
6. If an automated check could have caught the defect, prefer adding the check (test,
   linter rule) over only writing an issue.

## Checklist

- [ ] Issue picked with `bin/pick-issue.sh`; it has `type:*`, `priority:*` and a milestone
- [ ] Branch name is `<type>/issue-<N>-<slug>`
- [ ] Tests added, all checks pass locally
- [ ] `CHANGELOG.md` updated
- [ ] Docs updated
- [ ] Coder and review findings are in the findings file, every finding answered
- [ ] After the merge: candidates verified (real, not tracked), issues created after approval
- [ ] PR title is a Conventional Commit and the description has `Closes #<N>`
- [ ] `ci-ok` is green, PR merged with squash
- [ ] Local branch deleted, worktrees cleaned up
