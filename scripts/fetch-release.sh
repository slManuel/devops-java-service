#!/usr/bin/env sh
# Read-only access to a successful sibling-branch Jenkins build; no rebuild.
set -eu
set +x
umask 077
: "${SOURCE_BUILD_NUMBER:?Choose a validated source build}"
: "${PROMOTION_USER:?Read-only Jenkins promotion user required}"
: "${PROMOTION_TOKEN:?Read-only Jenkins API token required}"
case "$SOURCE_BUILD_NUMBER" in ''|*[!0-9]*|0*) echo 'Invalid source build number' >&2; exit 1;; esac
case "$BRANCH_NAME" in
  qa) source_branch=develop; source_environment=development; target=qa ;;
  main) source_branch=qa; source_environment=qa; target=production ;;
  *) echo 'Promotions only run on qa/main' >&2; exit 1 ;;
esac
[ "$TARGET_ENVIRONMENT" = "$target" ] || exit 1
case "$BUILD_URL" in */job/"$BRANCH_NAME"/"$BUILD_NUMBER"/) ;; *) echo 'Unexpected Jenkins build URL' >&2; exit 1;; esac
current_job_url=${BUILD_URL%/"$BUILD_NUMBER"/}
project_url=${current_job_url%/job/"$BRANCH_NAME"}
source_url="$project_url/job/$source_branch/$SOURCE_BUILD_NUMBER"
source_job="${JOB_NAME%/*}/$source_branch"
auth=$(printf '%s:%s' "$PROMOTION_USER" "$PROMOTION_TOKEN" | base64 | tr -d '\n')
fetch() {
  printf 'header = "Authorization: Basic %s"\n' "$auth" | curl --config - --fail --silent --show-error "$1"
}
status=$(fetch "$source_url/api/json?tree=result,building")
printf '%s' "$status" | jq -e '.result == "SUCCESS" and .building == false' >/dev/null
fetch "$source_url/artifact/release.json" > release.json
unset auth status
tree=$(git rev-parse 'HEAD^{tree}')
jq -e --arg tree "$tree" --arg expected "$source_environment" --arg job "$source_job" --arg build "$SOURCE_BUILD_NUMBER" '
  .schema == 1 and .source_tree == $tree and .validated_environment == $expected
  and .validated_job == $job and .validated_build_number == $build
  and (.source_commit | test("^[0-9a-f]{40}$"))
  and (.image | test("^ghcr\\.io/slmanuel/devops-java-service@sha256:[0-9a-f]{64}$"))
' release.json >/dev/null
printf '%s\n' 'Successful source build, source Git tree and immutable digest verified.'
