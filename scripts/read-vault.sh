#!/usr/bin/env sh
set -eu
set +x
umask 077
mkdir -p /run/pipeline
VAULT_ADDR=https://vault.vault.svc.cluster.local:8200
login=$(jq -cn --arg role jenkins --rawfile jwt /var/run/vault/token '{role:$role,jwt:($jwt|rtrimstr("\n"))}' | curl --fail --silent --show-error --cacert /etc/vault-ca/ca.crt --header 'Content-Type: application/json' --data-binary @- "$VAULT_ADDR/v1/auth/deployment/login")
token=$(printf '%s' "$login" | jq -er '.auth.client_token')
unset login
revoke() {
  printf 'header = "X-Vault-Token: %s"\n' "$token" | curl --config - --silent --show-error --cacert /etc/vault-ca/ca.crt --request POST "$VAULT_ADDR/v1/auth/token/revoke-self" --output /dev/null || true
}
trap revoke EXIT HUP INT TERM
printf 'header = "X-Vault-Token: %s"\n' "$token" | curl --config - --fail --silent --show-error --cacert /etc/vault-ca/ca.crt "$VAULT_ADDR/v1/kv/data/demo/app" | jq -ej '.data.data.DEMO_MESSAGE | select(type=="string" and length>0)' > /run/pipeline/DEMO_MESSAGE
printf '%s\n' 'Vault authentication succeeded; demo variable obtained; value omitted.'
