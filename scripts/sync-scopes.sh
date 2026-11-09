#!/usr/bin/env bash
# Opens or updates one pull request per scope/** branch that merges main into it.
# Runs inside a checkout of the application repository (fetch-depth 0, bot token).
# env: GH_TOKEN, BOT_SLUG
set -euo pipefail
summary=${GITHUB_STEP_SUMMARY:-/dev/null}
bot_id=$(gh api "/users/${BOT_SLUG}%5Bbot%5D" -q .id)
git config user.name "${BOT_SLUG}[bot]"
git config user.email "${bot_id}+${BOT_SLUG}[bot]@users.noreply.github.com"
scopes=$(git for-each-ref --format='%(refname:lstrip=3)' 'refs/remotes/origin/scope/')
[ -z "$scopes" ] && { echo "No scope branches."; exit 0; }
for scope in $scopes; do
  if git merge-base --is-ancestor origin/main "origin/$scope"; then
    echo "- ${scope}: already contains main" >> "$summary"; continue
  fi
  branch="sync/main-into-${scope//\//-}"
  git switch -q -C "$branch" "origin/$scope"
  behind=$(git rev-list --count "origin/${scope}..origin/main")
  if git merge --no-ff -q -m "Sync main into ${scope}" origin/main >/dev/null 2>&1; then
    draft=(); title="Sync main into ${scope} (${behind} commit(s))"
    note="Merged without conflict. Review and merge, so ${scope} keeps the PROD fixes."
  else
    files=$(git diff --name-only --diff-filter=U | tr '\n' ' ')
    git merge --abort
    git commit -q --allow-empty -m "Sync main into ${scope}: needs manual resolution"
    draft=(--draft); title="Sync main into ${scope}: conflict, needs a hand"
    note="Conflict in: ${files}. Resolve on this branch: git merge origin/main, fix the files, push."
  fi
  git push -q --force origin "$branch"
  num=$(gh pr list --head "$branch" --state open --json number -q '.[0].number // empty')
  body="\`main\` has ${behind} commit(s) that \`${scope}\` does not have yet (PROD fixes, other work). ${note}"
  if [ -n "$num" ]; then
    gh pr edit "$num" --title "$title" --body "$body" >/dev/null; url=$(gh pr view "$num" --json url -q .url)
  else
    url=$(gh pr create "${draft[@]}" --head "$branch" --base "$scope" --title "$title" --body "$body")
  fi
  echo "- ${scope}: ${url}" >> "$summary"
done
