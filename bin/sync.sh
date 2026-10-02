#!/usr/bin/env bash
# Apply the crazy-goat repository standard (labels, settings, ruleset) with `gh api`.
set -euo pipefail

ORG="crazy-goat"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STD="$ROOT/standard"

DRY=0
DO_RULESET=0
ALL=0
REPOS=()

usage() {
    cat <<USAGE
Usage: bin/sync.sh [--dry-run] [--ruleset] (--all | <repo>...)

  --dry-run   only print what would change (read-only calls only)
  --ruleset   also create/update the 'default-branch' ruleset (requires a 'ci-ok' job,
              otherwise merges get blocked)
  --all       every repository from standard/repos.txt

Default scope: label migration, standard labels, repository settings.
Requires: gh (admin rights), jq.
USAGE
}

while [ $# -gt 0 ]; do
    case "$1" in
        --dry-run) DRY=1 ;;
        --ruleset) DO_RULESET=1 ;;
        --all) ALL=1 ;;
        -h|--help) usage; exit 0 ;;
        -*) echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
        *) REPOS+=("$1") ;;
    esac
    shift
done

command -v gh >/dev/null || { echo "gh is required" >&2; exit 2; }
command -v jq >/dev/null || { echo "jq is required" >&2; exit 2; }

if [ "$ALL" = 1 ]; then
    while IFS= read -r line; do
        [ -n "$line" ] && REPOS+=("$line")
    done < "$STD/repos.txt"
fi
[ "${#REPOS[@]}" -gt 0 ] || { usage >&2; exit 2; }

run() {
    if [ "$DRY" = 1 ]; then
        echo "  [dry-run] $*" >&2
    else
        "$@"
    fi
}

label_exists() {
    jq -e --arg n "$1" 'any(.[]; .name | ascii_downcase == ($n | ascii_downcase))' <<<"$LABELS" >/dev/null
}

sync_renames() {
    local repo="$1" file="$STD/renames/$1.tsv" old new
    [ -f "$file" ] || return 0
    echo "- label migration ($file)"
    while IFS=$'\t' read -r old new; do
        case "$old" in ''|'#'*) continue ;; esac
        label_exists "$old" || continue
        if [ "$new" = "-" ]; then
            run gh label delete "$old" -R "$ORG/$repo" --yes
            LABELS="$(jq --arg n "$old" 'map(select(.name != $n))' <<<"$LABELS")"
        elif label_exists "$new"; then
            local numbers n
            numbers="$(gh api --paginate "repos/$ORG/$repo/issues?labels=$(jq -rn --arg l "$old" '$l|@uri')&state=all&per_page=100" --jq '.[].number')"
            for n in $numbers; do
                run gh api -X POST "repos/$ORG/$repo/issues/$n/labels" -f "labels[]=$new" >/dev/null
            done
            run gh label delete "$old" -R "$ORG/$repo" --yes
            LABELS="$(jq --arg n "$old" 'map(select(.name != $n))' <<<"$LABELS")"
        else
            run gh label edit "$old" -R "$ORG/$repo" --name "$new"
            LABELS="$(jq --arg o "$old" --arg n "$new" 'map(if .name == $o then .name = $n else . end)' <<<"$LABELS")"
        fi
    done < "$file"
}

sync_labels() {
    local repo="$1" name color desc current
    echo "- standard labels"
    while IFS=$'\t' read -r name color desc; do
        if label_exists "$name"; then
            current="$(jq -r --arg n "$name" '.[] | select(.name | ascii_downcase == ($n | ascii_downcase)) | "\(.color)\t\(.description)"' <<<"$LABELS")"
            if [ "$current" != "$color"$'\t'"$desc" ]; then
                run gh label edit "$name" -R "$ORG/$repo" --name "$name" --color "$color" --description "$desc"
            fi
        else
            run gh label create "$name" -R "$ORG/$repo" --color "$color" --description "$desc"
        fi
    done < <(jq -r '.[] | [.name, .color, .description] | @tsv' "$STD/labels.json")
}

sync_settings() {
    local repo="$1" current diff
    echo "- repository settings"
    current="$(gh api "repos/$ORG/$repo")"
    diff="$(jq -r --slurpfile want "$STD/settings.json" '
        . as $cur | $want[0] | to_entries[]
        | select($cur[.key] != .value)
        | "\(.key): \($cur[.key]) -> \(.value)"' <<<"$current")"
    if [ -z "$diff" ]; then
        echo "  already up to date"
        return 0
    fi
    echo "  ${diff//$'\n'/$'\n'  }"
    run gh api -X PATCH "repos/$ORG/$repo" --input "$STD/settings.json" >/dev/null
}

# Workflows from fork pull requests wait for a maintainer's approval.
sync_fork_approval() {
    local repo="$1" want="all_external_contributors" current
    echo "- fork pull request approval"
    current="$(gh api "repos/$ORG/$repo/actions/permissions/fork-pr-contributor-approval" --jq .approval_policy)"
    if [ "$current" = "$want" ]; then
        echo "  already up to date"
        return 0
    fi
    echo "  approval_policy: $current -> $want"
    run gh api -X PUT "repos/$ORG/$repo/actions/permissions/fork-pr-contributor-approval" -f approval_policy="$want" >/dev/null
}

# Dependabot alerts and security updates are on everywhere (standard/dependabot.md).
sync_dependabot() {
    local repo="$1" fixes
    echo "- dependabot alerts and security updates"
    fixes="$(gh api "repos/$ORG/$repo/automated-security-fixes" --jq .enabled 2>/dev/null || echo false)"
    if [ "$fixes" = "true" ]; then
        echo "  already up to date"
        return 0
    fi
    echo "  security updates: $fixes -> true"
    run gh api -X PUT "repos/$ORG/$repo/vulnerability-alerts" >/dev/null
    run gh api -X PUT "repos/$ORG/$repo/automated-security-fixes" >/dev/null
}

sync_ruleset() {
    local repo="$1" id
    echo "- ruleset 'default-branch'"
    id="$(gh api "repos/$ORG/$repo/rulesets" --jq '.[] | select(.name == "default-branch") | .id' | head -n1)"
    if [ -n "$id" ]; then
        run gh api -X PUT "repos/$ORG/$repo/rulesets/$id" --input "$STD/ruleset.json" >/dev/null
    else
        run gh api -X POST "repos/$ORG/$repo/rulesets" --input "$STD/ruleset.json" >/dev/null
    fi
}

for repo in "${REPOS[@]}"; do
    echo "== $ORG/$repo"
    LABELS="$(gh label list -R "$ORG/$repo" --limit 500 --json name,color,description)"
    sync_renames "$repo"
    sync_labels "$repo"
    sync_settings "$repo"
    sync_fork_approval "$repo"
    sync_dependabot "$repo"
    if [ "$DO_RULESET" = 1 ]; then
        sync_ruleset "$repo"
    fi
done
