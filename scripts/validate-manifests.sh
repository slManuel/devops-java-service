#!/usr/bin/env sh
set -eu
docker run --rm -v "$PWD:/work:ro" ghcr.io/yannh/kubeconform:v0.8.0 -strict -summary -kubernetes-version 1.36.0 -schema-location default -schema-location '/work/schemas/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json' /work/k8s
