#!/usr/bin/env sh
set -eu
set +x
umask 077
mkdir -p /run/pipeline
target=${TARGET_ENVIRONMENT:-development}
case "$target" in development|qa|production) ;; *) echo 'Unknown target environment' >&2; exit 1;; esac
role="jenkins-$target"
secret_path="kv/data/environments/$target/app"
# Compatibilidad explícita de la demo histórica detenida, solo en development.
if [ "${LOCAL_DEMO_LEGACY:-false}" = true ]; then
  [ "$target" = development ] || exit 1
  role=jenkins
  secret_path=kv/data/demo/app
fi
VAULT_ADDR=https://vault.vault.svc.cluster.local:8200
login=$(jq -cn --arg role "$role" --rawfile jwt /var/run/vault/token '{role:$role,jwt:($jwt|rtrimstr("\n"))}' | curl --fail --silent --show-error --cacert /etc/vault-ca/ca.crt --header 'Content-Type: application/json' --data-binary @- "$VAULT_ADDR/v1/auth/deployment/login")
token=$(printf '%s' "$login" | jq -er '.auth.client_token')
unset login
[ -n "$token" ]
revoke() {
  printf 'header = "X-Vault-Token: %s"\n' "$token" | curl --config - --silent --show-error --cacert /etc/vault-ca/ca.crt --request POST "$VAULT_ADDR/v1/auth/token/revoke-self" --output /dev/null || true
}
trap revoke EXIT HUP INT TERM
payload=$(printf 'header = "X-Vault-Token: %s"\n' "$token" | curl --config - --fail --silent --show-error --cacert /etc/vault-ca/ca.crt "$VAULT_ADDR/v1/$secret_path")
printf '%s' "$payload" | jq -ej '.data.data.DEMO_MESSAGE | select(type=="string" and length>0)' > /run/pipeline/DEMO_MESSAGE
unset payload
test -s /run/pipeline/DEMO_MESSAGE
printf '%s\n' 'Vault authentication succeeded; demo variable obtained; value omitted.'
