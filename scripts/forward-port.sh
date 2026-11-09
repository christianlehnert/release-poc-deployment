#!/usr/bin/env bash
# Cherry-picks new commits of a release branch onto main and opens the pull request.
# Runs inside a checkout of the application repository (fetch-depth 0, bot token).
# usage: forward-port.sh <before-sha> <after-sha> <release-branch>
# env:   GH_TOKEN, BOT_SLUG
set -euo pipefail
before=$1 after=$2 source=$3
summary=${GITHUB_STEP_SUMMARY:-/dev/null}
bot_id=$(gh api "/users/${BOT_SLUG}%5Bbot%5D" -q .id)
git config user.name "${BOT_SLUG}[bot]"
git config user.email "${bot_id}+${BOT_SLUG}[bot]@users.noreply.github.com"
if [ "$before" = "0000000000000000000000000000000000000000" ]; then echo "New release branch, nothing to forward-port."; exit 0; fi
mapfile -t commits < <(git rev-list --reverse --no-merges --cherry-pick --right-only "origin/main...${after}" \
  | while read -r c; do git merge-base --is-ancestor "$c" "$before" || echo "$c"; done)
[ ${#commits[@]} -eq 0 ] && { echo "Nothing new for main."; exit 0; }
branch="forward-port/${source//\//-}-${after::7}"
git switch -q -c "$branch" origin/main
conflict=""
for c in "${commits[@]}"; do
  if ! git cherry-pick -x "$c" >/dev/null 2>&1; then
    files=$(git diff --name-only --diff-filter=U | tr '\n' ' ')
    conflict="${conflict}- \`${c::7}\` $(git log -1 --format=%s "$c"): conflict in ${files}\n"
    git cherry-pick --abort
  fi
done
list=$(for c in "${commits[@]}"; do echo "- \`${c::7}\` $(git log -1 --format=%s "$c")"; done)
if [ -z "$conflict" ]; then
  git push -q origin "$branch"
  url=$(gh pr create --head "$branch" --base main --title "Forward-port ${source} to main (${#commits[@]} commit(s))" \
    --body "$(printf 'These commits were merged into `%s` and are not in `main` yet:\n\n%s\n\nCherry-picked without conflict. Review and merge, so the next release from main keeps the fix.' "$source" "$list")")
else
  git commit -q --allow-empty -m "Forward-port ${source}: needs manual resolution"
  git push -q origin "$branch"
  url=$(gh pr create --draft --head "$branch" --base main --title "Forward-port ${source} to main: conflict, needs a hand" \
    --body "$(printf 'Commits from `%s` that could not be applied to `main` automatically:\n\n%b\nResolve on this branch: `git cherry-pick -x <commit>`, fix the files, push.' "$source" "$conflict")")
fi
echo "Forward-port pull request: ${url}" | tee -a "$summary"
