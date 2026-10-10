#!/usr/bin/env sh
set -eu
set +x
pipeline_dir=${PIPELINE_DIR:-/run/pipeline}
target=${TARGET_ENVIRONMENT:-development}
case "$target" in development|qa|production) ;; *) echo 'Unknown target environment' >&2; exit 1;; esac
work="$pipeline_dir/$target"
[ -f "$work/deploy-started" ] || exit 0
[ "$(kubectl config current-context)" = "$target" ] || exit 1
if [ ! -s "$work/previous-deployment.json" ]; then
  echo 'Initial deployment has no previous revision; rollback unavailable.' >&2
  exit 1
fi
if [ -s "$work/previous-secret.json" ]; then
  jq --arg ns "$target" -e '.metadata.namespace == $ns' "$work/previous-secret.json" >/dev/null
  jq '{apiVersion,kind,metadata:{name:.metadata.name,namespace:.metadata.namespace},data,type}' "$work/previous-secret.json" | kubectl -n "$target" apply -f -
else
  echo 'Previous secret unavailable; refusing incomplete rollback.' >&2
  exit 1
fi
jq --arg ns "$target" -e '.metadata.namespace == $ns' "$work/previous-deployment.json" >/dev/null
jq '{apiVersion,kind,metadata:{name:.metadata.name,namespace:.metadata.namespace},spec}' "$work/previous-deployment.json" | kubectl -n "$target" apply -f -
kubectl -n "$target" rollout status deployment/devops-java-service --timeout=180s
rm "$work/deploy-started"
echo 'Previous Deployment and environment secret restored; values omitted.'
