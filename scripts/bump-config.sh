#!/usr/bin/env bash
# Writes version lines into a configuration repository.
#   dev:  direct commit to main of release-poc-config-dev (no review: DEV is for fast feedback)
#   test: ONE collecting pull request in release-poc-config-test (branch bump/next)
# Concurrent callers (many app repositories at the same time) are handled by retrying the push.
# usage: bump-config.sh <dev|test> <changes-file> <source text>
# env:   GH_TOKEN (bot token), BOT_SLUG, OWNER
set -euo pipefail
env=$1 changes=$(realpath "$2") source=$3
repo="${OWNER}/release-poc-config-${env}"
bot_id=$(gh api "/users/${BOT_SLUG}%5Bbot%5D" -q .id)
summary=${GITHUB_STEP_SUMMARY:-/dev/null}

apply_changes() {
  while IFS= read -r line; do
    [ -z "${line// }" ] && continue
    key=$(echo "$line" | sed -E 's/^[[:space:]]*([a-z0-9_]+)[[:space:]]*=.*/\1/')
    if grep -qE "^${key}[[:space:]]*=" terraform/versions.tfvars; then
      sed -i -E "s#^${key}[[:space:]]*=.*#${line}#" terraform/versions.tfvars
    else
      echo "$line" >> terraform/versions.tfvars
    fi
  done < "$changes"
}

work=$(mktemp -d)
if [ "$env" = dev ]; then
  for attempt in 1 2 3 4 5; do
    rm -rf "$work/cfg"; git clone -q "https://x-access-token:${GH_TOKEN}@github.com/${repo}.git" "$work/cfg"
    cd "$work/cfg"
    git config user.name "${BOT_SLUG}[bot]"; git config user.email "${bot_id}+${BOT_SLUG}[bot]@users.noreply.github.com"
    apply_changes
    git diff --quiet && { echo "dev already has these versions" | tee -a "$summary"; exit 0; }
    git commit -q -am "${source}"
    if git push -q origin main; then echo "dev updated: ${source}" | tee -a "$summary"; exit 0; fi
    cd /; sleep $((attempt * 3))
  done
  echo "::error::could not update dev"; exit 1
fi

branch="bump/next"
# Never overwrite someone else's lines: build on an open (unmerged) bump/next branch; reset only a branch
# that is already fully merged, and then only with --force-with-lease. Every push is retried on rejection.
done_ok=0
for attempt in 1 2 3 4 5 6; do
  rm -rf "$work/cfg"; git clone -q "https://x-access-token:${GH_TOKEN}@github.com/${repo}.git" "$work/cfg"
  cd "$work/cfg"
  git config user.name "${BOT_SLUG}[bot]"; git config user.email "${bot_id}+${BOT_SLUG}[bot]@users.noreply.github.com"
  push_args=()
  if remote_sha=$(git rev-parse -q --verify "origin/$branch"); then
    if git merge-base --is-ancestor "origin/$branch" origin/main; then
      git switch -q -c "$branch" origin/main                     # stale (already merged): start fresh
      push_args=(--force-with-lease="$branch:$remote_sha")
    else
      git switch -q -c "$branch" "origin/$branch"                # open work of others: add to it
    fi
  else
    git switch -q -c "$branch" origin/main                       # first one: create it (fails if someone was faster)
  fi
  apply_changes
  git diff --quiet && { echo "Nothing new."; done_ok=1; break; }
  git commit -q -am "${source}"
  git push -q "${push_args[@]}" origin "$branch" && { done_ok=1; break; }
  echo "push rejected (another release was faster), retry ${attempt}"; cd /; sleep $((attempt * 2 + RANDOM % 3))
done
[ "$done_ok" = 1 ] || { echo "::error::could not write the collecting pull request after 6 tries"; exit 1; }
diffs=$(git diff origin/main -- terraform/versions.tfvars | sed -n 's/^+\([a-z].*\)/- `\1`/p')
n=$(echo "$diffs" | grep -c '_tag' || true)
title="test: ${n} new version(s)"
body="Collecting pull request of the release bot. Every release adds its lines here (version and image digest), until you merge.

New compared with TEST today:
${diffs}

After the merge the bot tags this configuration and deploys it to TEST. If TEST succeeds, the bot updates the pull requests for prod-a and prod-b."
open_pr=$(gh pr list --repo "$repo" --head "$branch" --state open --json number -q '.[0].number // empty')
if [ -z "$open_pr" ] && url=$(gh pr create --repo "$repo" --head "$branch" --base main --title "$title" --body "$body" 2>/dev/null); then
  verb=opened
else
  open_pr=$(gh pr list --repo "$repo" --head "$branch" --state open --json number -q '.[0].number // empty')
  gh pr edit "$open_pr" --repo "$repo" --title "$title" --body "$body" >/dev/null
  url=$(gh pr view "$open_pr" --repo "$repo" --json url -q .url); verb=updated
fi
echo "Collecting pull request ${verb}: ${url}" | tee -a "$summary"
