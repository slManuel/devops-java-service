#!/usr/bin/env sh
set -eu
set +x
[ -f /run/pipeline/deploy-started ] || exit 0
[ "$(kubectl config current-context)" = development ] || exit 1
if [ ! -s /run/pipeline/previous-deployment.json ]; then
  echo 'Initial deployment has no previous revision; rollback unavailable.' >&2
  exit 1
fi
if [ -s /run/pipeline/previous-secret.json ]; then
  jq '{apiVersion,kind,metadata:{name:.metadata.name,namespace:.metadata.namespace},data,type}' /run/pipeline/previous-secret.json | kubectl -n development apply -f -
fi
jq '{apiVersion,kind,metadata:{name:.metadata.name,namespace:.metadata.namespace},spec}' /run/pipeline/previous-deployment.json | kubectl -n development apply -f -
kubectl -n development rollout status deployment/devops-java-service --timeout=180s
echo 'Previous Deployment specification and pipeline secret restored; values omitted.'
