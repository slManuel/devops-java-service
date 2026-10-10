#!/usr/bin/env sh
set -eu
set +x
umask 077
: "${KUBECONFIG:?development kubeconfig credential required}"
: "${IMAGE:?immutable image required}"
[ "$(kubectl config current-context)" = development ] || { echo "Wrong kubeconfig context" >&2; exit 1; }
# Authorization and current-version reads must succeed; AccessDenied is not treated as first deploy.
kubectl -n development get deployment devops-java-service --ignore-not-found -o json > /run/pipeline/previous-deployment.json
kubectl -n development get secret pipeline-env --ignore-not-found -o json > /run/pipeline/previous-secret.json
: > /run/pipeline/deploy-started
kubectl -n development create secret generic pipeline-env --from-file=DEMO_MESSAGE=/run/pipeline/DEMO_MESSAGE --dry-run=client -o yaml | kubectl -n development apply -f -
kubectl set image --local -f k8s/deployment.yaml app="$IMAGE" -o yaml | kubectl -n development apply -f -
kubectl -n development rollout status deployment/devops-java-service --timeout=180s
ready=$(kubectl -n development get deployment devops-java-service -o jsonpath='{.status.readyReplicas}')
[ "$ready" = 2 ]
printf '%s\n' 'Deployment ready: two replicas. Values omitted.'
