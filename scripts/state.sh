#!/usr/bin/env bash
# The branch deploy-state stands in for the real infrastructure and the remote Terraform state.
# Layout: state/<environment>/<module>.tfstate, versions.tfvars, features.tfvars, config_tag
#   state.sh get <environment>                          -> ./state/<environment>/*
#   state.sh put <environment> <config_tag> <cfg-dir>   -> commit to deploy-state
set -euo pipefail
cmd=$1 env=$2
ws=${GITHUB_WORKSPACE:-$PWD}

case $cmd in
  get)
    mkdir -p "$ws/state/$env"
    if git -C "$ws" fetch -q --depth 1 origin deploy-state 2>/dev/null; then
      for f in $(git -C "$ws" ls-tree --name-only FETCH_HEAD "state/$env/" 2>/dev/null); do
        git -C "$ws" show "FETCH_HEAD:$f" > "$ws/$f"
      done
    fi
    echo "State of $env: $(ls "$ws/state/$env" 2>/dev/null | tr '\n' ' ')"
    ;;
  put)
    tag=$3 cfg=$4
    tmp=$(mktemp -d)
    cp "$ws"/state/"$env"/*.tfstate "$tmp/" 2>/dev/null || true
    cp "$cfg/versions.tfvars" "$tmp/versions.tfvars"
    [ -f "$cfg/features.tfvars" ] && cp "$cfg/features.tfvars" "$tmp/features.tfvars"
    echo "$tag" > "$tmp/config_tag"
    work=$(mktemp -d)
    git -C "$ws" config user.name "github-actions[bot]"
    git -C "$ws" config user.email "41898282+github-actions[bot]@users.noreply.github.com"
    for i in 1 2 3 4 5; do
      rm -rf "$work"; mkdir -p "$work"
      if git -C "$ws" fetch -q origin deploy-state 2>/dev/null; then
        git -C "$ws" worktree add -q -f --detach "$work" FETCH_HEAD
      else
        git -C "$ws" worktree add -q -f --orphan -b "deploy-state-new-$$" "$work"
      fi
      mkdir -p "$work/state/$env"
      cp "$tmp"/* "$work/state/$env/"
      git -C "$work" add state
      git -C "$work" commit -q -m "$env: $tag (run ${GITHUB_RUN_ID:-local})" || { echo "nothing to save"; exit 0; }
      if git -C "$work" push -q origin HEAD:refs/heads/deploy-state; then
        echo "State of $env saved ($tag)"; exit 0
      fi
      git -C "$ws" worktree remove -f "$work"
      sleep $((i * 2))
    done
    echo "::error::Could not save the state" && exit 1
    ;;
esac
