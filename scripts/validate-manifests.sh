#!/usr/bin/env sh
set -eu
mkdir -p build/manifests
kubectl kustomize environments/development > build/manifests/development.yaml
kubectl kustomize environments/qa > build/manifests/qa.yaml
kubectl kustomize environments/production > build/manifests/production.yaml
docker run --pull=never --rm -v "$PWD:/work:ro" ghcr.io/yannh/kubeconform:v0.8.0 -strict -summary -kubernetes-version 1.36.0 -schema-location default -schema-location '/work/schemas/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json' /work/build/manifests
