#!/usr/bin/env sh
set -eu
set +x
umask 077
pipeline_dir=${PIPELINE_DIR:-/run/pipeline}
target=${TARGET_ENVIRONMENT:-development}
case "$target" in development|qa|production) ;; *) echo 'Unknown target environment' >&2; exit 1;; esac
: "${KUBECONFIG:?Environment kubeconfig credential required}"
: "${IMAGE:?Immutable image required}"
if [ "${LOCAL_DEMO_LEGACY:-false}" = true ]; then
  [ "$target" = development ] || exit 1
else
  printf '%s' "$IMAGE" | grep -Eq '^ghcr\.io/slmanuel/devops-java-service@sha256:[0-9a-f]{64}$' || { echo 'Expected approved immutable GHCR digest' >&2; exit 1; }
fi
[ "$(kubectl config current-context)" = "$target" ] || { echo "Wrong kubeconfig context" >&2; exit 1; }
work="$pipeline_dir/$target"
mkdir -p "$work"
# Lecturas fallidas no se confunden con una primera instalación.
kubectl -n "$target" get deployment devops-java-service --ignore-not-found -o json > "$work/previous-deployment.json"
kubectl -n "$target" get secret pipeline-env --ignore-not-found -o json > "$work/previous-secret.json"
: > "$work/deploy-started"
test -s "$pipeline_dir/DEMO_MESSAGE"
kubectl -n "$target" create secret generic pipeline-env --from-file="DEMO_MESSAGE=$pipeline_dir/DEMO_MESSAGE" --dry-run=client -o yaml > "$work/candidate-secret.yaml"
kubectl -n "$target" apply -f "$work/candidate-secret.yaml"
# El mismo Deployment base y digest; solo cambia el namespace del clúster destino.
kubectl set image --local -f k8s/deployment.yaml app="$IMAGE" -o json > "$work/candidate-base.json"
jq --arg ns "$target" '.metadata.namespace=$ns' "$work/candidate-base.json" > "$work/candidate-deployment.json"
kubectl -n "$target" apply -f "$work/candidate-deployment.json"
kubectl -n "$target" rollout status deployment/devops-java-service --timeout=180s
ready=$(kubectl -n "$target" get deployment devops-java-service -o jsonpath='{.status.readyReplicas}')
[ "$ready" = 2 ]
rm "$work/deploy-started"
printf '%s\n' 'Deployment ready: two replicas; environment secret values omitted.'
