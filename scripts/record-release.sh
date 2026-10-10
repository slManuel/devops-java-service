#!/usr/bin/env sh
set -eu
set +x
umask 077
commit=$(git rev-parse HEAD)
tree=$(git rev-parse 'HEAD^{tree}')
printf '%s' "$IMAGE" | grep -Eq '^ghcr\.io/slmanuel/devops-java-service@sha256:[0-9a-f]{64}$'
case "$BRANCH_NAME:$TARGET_ENVIRONMENT" in
  develop:development)
    jq -n --arg image "$IMAGE" --arg commit "$commit" --arg tree "$tree" '{schema:1,image:$image,source_commit:$commit,source_tree:$tree}' > release.json
    ;;
  qa:qa|main:production)
    jq -e --arg image "$IMAGE" --arg tree "$tree" '.image == $image and .source_tree == $tree' release.json >/dev/null
    ;;
  *) echo 'Unexpected branch/environment' >&2; exit 1 ;;
esac
jq --arg target "$TARGET_ENVIRONMENT" --arg commit "$commit" --arg job "$JOB_NAME" --arg build "$BUILD_NUMBER" '
  .validated_environment=$target | .validated_commit=$commit | .validated_job=$job | .validated_build_number=$build
' release.json > release.next.json
mv release.next.json release.json
