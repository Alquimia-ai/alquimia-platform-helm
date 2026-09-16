#!/bin/sh
# Init + unseal continuo para GitOps. Sin {{ para no romper Helm.
set -u

VAULT_ADDR="${VAULT_ADDR:-http://vault:8200}"
NS="${POD_NAMESPACE:?POD_NAMESPACE required}"
KEYS_SECRET="${KEYS_SECRET:-vault-keys}"
TOKEN_SECRET="${TOKEN_SECRET:-alquimia-vault}"
SHARES="${KEY_SHARES:-1}"
THRESHOLD="${KEY_THRESHOLD:-1}"
SA_TOKEN=$(cat /var/run/secrets/kubernetes.io/serviceaccount/token)
CACERT=/var/run/secrets/kubernetes.io/serviceaccount/ca.crt
K8S="https://kubernetes.default.svc/api/v1/namespaces/${NS}"
AUTH_HDR="Authorization: Bearer ${SA_TOKEN}"

UNSEAL_KEY=""
ROOT_TOKEN=""

log() {
  echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) $*"
}

b64enc() {
  printf '%s' "$1" | base64 | tr -d '\n'
}

health_code() {
  curl -sS -o /dev/null -w "%{http_code}" "$VAULT_ADDR/v1/sys/health?standbyok=true" 2>/dev/null || printf '000'
}

wait_api() {
  code="$(health_code)"
  while [ "$code" = "000" ]; do
    log "esperando API de Vault..."
    sleep 5
    code="$(health_code)"
  done
}

extract_json_string() {
  # extrae el valor de una clave JSON string; JSON compacto o pretty
  key="$1"
  file="$2"
  tr -d '\n' < "$file" | sed -n "s/.*\"${key}\": *\"\\([^\"]*\\)\".*/\\1/p"
}

load_keys() {
  UNSEAL_KEY=""
  ROOT_TOKEN=""
  code=$(curl -sS -o /tmp/keys.json -w "%{http_code}" -H "$AUTH_HDR" --cacert "$CACERT" "$K8S/secrets/${KEYS_SECRET}" || printf '000')
  if [ "$code" != "200" ]; then
    return 1
  fi
  raw_key=$(extract_json_string unseal-key /tmp/keys.json)
  raw_tok=$(extract_json_string root-token /tmp/keys.json)
  if [ -z "$raw_key" ] || [ -z "$raw_tok" ]; then
    return 1
  fi
  UNSEAL_KEY=$(printf '%s' "$raw_key" | base64 -d)
  ROOT_TOKEN=$(printf '%s' "$raw_tok" | base64 -d)
  [ -n "$UNSEAL_KEY" ] && [ -n "$ROOT_TOKEN" ]
}

upsert_secret() {
  name="$1"
  post_body="$2"
  patch_body="$3"
  code=$(curl -sS -o /tmp/k8s.post -w "%{http_code}" -X POST -H "$AUTH_HDR" -H "Content-Type: application/json" \
    --cacert "$CACERT" -d "$post_body" "$K8S/secrets" || printf '000')
  if [ "$code" = "201" ]; then
    return 0
  fi
  if [ "$code" = "409" ] || [ "$code" = "200" ]; then
    curl -sS -o /tmp/k8s.patch -X PATCH -H "$AUTH_HDR" -H "Content-Type: application/merge-patch+json" \
      --cacert "$CACERT" -d "$patch_body" "$K8S/secrets/${name}" || true
  fi
}

save_keys() {
  key="$1"
  token="$2"
  key_b64=$(b64enc "$key")
  tok_b64=$(b64enc "$token")
  keys_post="{\"apiVersion\":\"v1\",\"kind\":\"Secret\",\"metadata\":{\"name\":\"${KEYS_SECRET}\",\"namespace\":\"${NS}\",\"labels\":{\"app\":\"vault-unsealer\"},\"annotations\":{\"argocd.argoproj.io/sync-options\":\"Prune=false\"}},\"type\":\"Opaque\",\"data\":{\"unseal-key\":\"${key_b64}\",\"root-token\":\"${tok_b64}\"}}"
  keys_patch="{\"data\":{\"unseal-key\":\"${key_b64}\",\"root-token\":\"${tok_b64}\"}}"
  token_post="{\"apiVersion\":\"v1\",\"kind\":\"Secret\",\"metadata\":{\"name\":\"${TOKEN_SECRET}\",\"namespace\":\"${NS}\"},\"type\":\"Opaque\",\"data\":{\"VAULT_TOKEN\":\"${tok_b64}\"}}"
  token_patch="{\"data\":{\"VAULT_TOKEN\":\"${tok_b64}\"}}"
  upsert_secret "$KEYS_SECRET" "$keys_post" "$keys_patch"
  upsert_secret "$TOKEN_SECRET" "$token_post" "$token_patch"
  log "keys persistidas en ${KEYS_SECRET}; token en ${TOKEN_SECRET}"
}

do_init() {
  log "inicializando Vault (shares=${SHARES} threshold=${THRESHOLD})"
  curl -sS -X PUT -H "Content-Type: application/json" \
    -d "{\"secret_shares\":${SHARES},\"secret_threshold\":${THRESHOLD}}" \
    "$VAULT_ADDR/v1/sys/init" > /tmp/init.json
  KEY=$(extract_json_string keys /tmp/init.json)
  if [ -z "$KEY" ]; then
    # keys es un array: "keys":["valor"]
    KEY=$(tr -d '\n' < /tmp/init.json | sed -n 's/.*"keys":\["\([^"]*\)"\].*/\1/p')
  fi
  TOKEN=$(extract_json_string root_token /tmp/init.json)
  if [ -z "$KEY" ] || [ -z "$TOKEN" ]; then
    log "no se pudo parsear init: $(cat /tmp/init.json)"
    return 1
  fi
  save_keys "$KEY" "$TOKEN"
  UNSEAL_KEY="$KEY"
  ROOT_TOKEN="$TOKEN"
}

do_unseal() {
  if [ -z "$UNSEAL_KEY" ]; then
    if ! load_keys; then
      log "no hay unseal key en ${KEYS_SECRET}; no se puede unsealar"
      return 1
    fi
  fi
  curl -sS -X PUT -H "Content-Type: application/json" \
    -d "{\"key\":\"${UNSEAL_KEY}\"}" \
    "$VAULT_ADDR/v1/sys/unseal" > /tmp/unseal.json || true
  log "unseal enviado"
}

while true; do
  wait_api
  code="$(health_code)"
  log "vault health=${code}"
  case "$code" in
    200|429|472|473)
      if load_keys; then
        save_keys "$UNSEAL_KEY" "$ROOT_TOKEN"
      fi
      ;;
    501)
      do_init || true
      do_unseal || true
      ;;
    503)
      do_unseal || true
      ;;
    *)
      log "codigo de health inesperado"
      ;;
  esac
  sleep 10
done
