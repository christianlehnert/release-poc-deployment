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
open_pr=$(gh pr list --repo "$repo" --head "$branch" --state open --json number -q '.[0].number // empty')
for attempt in 1 2 3 4 5; do
  rm -rf "$work/cfg"; git clone -q "https://x-access-token:${GH_TOKEN}@github.com/${repo}.git" "$work/cfg"
  cd "$work/cfg"
  git config user.name "${BOT_SLUG}[bot]"; git config user.email "${bot_id}+${BOT_SLUG}[bot]@users.noreply.github.com"
  if [ -n "$open_pr" ] && git ls-remote --exit-code --heads origin "$branch" >/dev/null; then
    git switch -q -c "$branch" "origin/$branch"
  else
    git switch -q -c "$branch" origin/main
  fi
  apply_changes
  git diff --quiet && { echo "Nothing new."; exit 0; }
  git commit -q -am "${source}"
  if [ -n "$open_pr" ]; then args=(); else args=(--force); fi
  git push -q "${args[@]}" origin "$branch" && break
  echo "push rejected, retry ${attempt}"; cd /; sleep $((attempt * 3))
  open_pr=$(gh pr list --repo "$repo" --head "$branch" --state open --json number -q '.[0].number // empty')
done
diffs=$(git diff origin/main -- terraform/versions.tfvars | sed -n 's/^+\([a-z].*\)/- `\1`/p')
n=$(echo "$diffs" | grep -c '_tag' || true)
title="test: ${n} new version(s)"
body="Collecting pull request of the release bot. Every release adds its lines here (version and image digest), until you merge.

New compared with TEST today:
${diffs}

After the merge the bot tags this configuration and deploys it to TEST. If TEST succeeds, the bot updates the pull requests for prod-a and prod-b."
if [ -n "$open_pr" ]; then
  gh pr edit "$open_pr" --repo "$repo" --title "$title" --body "$body" >/dev/null
  url=$(gh pr view "$open_pr" --repo "$repo" --json url -q .url); verb=updated
else
  url=$(gh pr create --repo "$repo" --head "$branch" --base main --title "$title" --body "$body"); verb=opened
fi
echo "Collecting pull request ${verb}: ${url}" | tee -a "$summary"
