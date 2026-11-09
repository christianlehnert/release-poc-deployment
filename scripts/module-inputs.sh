#!/usr/bin/env bash
# Builds the input of each Terraform module from the configuration repository.
#   versions.tfvars:  <name>_tag = "release/x.y.z"     -> apps.versions[<name>]
#                     db_<name>_schema = "x.y.z"       -> databases.schemas[<name>]
#   features.tfvars:  feature_<name> = true|false      -> apps.features[<name>]
# usage: module-inputs.sh <config-dir> <out-dir> <environment>
set -euo pipefail
cfg=$1 out=$2 env=$3
mkdir -p "$out"

kv() { # file regex -> "key<TAB>value" with quotes removed
  [ -f "$1" ] || return 0
  sed -nE "s/^[[:space:]]*($2)[[:space:]]*=[[:space:]]*\"?([^\"#[:space:]]+)\"?.*/\1\t\3/p" "$1"
}

kv "$cfg/terraform/versions.tfvars" '([a-z0-9_]+)_tag' \
  | awk -F'\t' '{sub(/_tag$/,"",$1); print $1"\t"$2}' \
  | jq -Rn --arg env "$env" '{environment:$env, versions:([inputs|split("\t")|{(.[0]):.[1]}]|add // {})}' \
  > "$out/apps.json"

kv "$cfg/terraform/versions.tfvars" 'db_([a-z0-9_]+)_schema' \
  | awk -F'\t' '{sub(/^db_/,"",$1); sub(/_schema$/,"",$1); print $1"\t"$2}' \
  | jq -Rn --arg env "$env" '{environment:$env, schemas:([inputs|split("\t")|{(.[0]):.[1]}]|add // {})}' \
  > "$out/databases.json"

kv "$cfg/terraform/features.tfvars" 'feature_([a-z0-9_]+)' \
  | awk -F'\t' '{sub(/^feature_/,"",$1); print $1"\t"$2}' \
  | jq -Rn '[inputs|split("\t")|{(.[0]):(.[1]=="true")}]|add // {}' > "$out/features.json"
jq --slurpfile f "$out/features.json" '. + {features:$f[0]}' "$out/apps.json" > "$out/apps.tmp" && mv "$out/apps.tmp" "$out/apps.json"
rm -f "$out/features.json"

jq -n --arg env "$env" '{environment:$env}' > "$out/infra.json"
