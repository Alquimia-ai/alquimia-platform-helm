#!/bin/sh
# Init + unseal continuo para GitOps. Sin {{ para no romper Helm.
set -u

VAULT_ADDR="${VAULT_ADDR:-http://vault:8200}"
NS="${POD_NAMESPACE:?POD_NAMESPACE required}"
KEYS_SECRET="${KEYS_SECRET:-vault-keys}"
TOKEN_SECRET="${TOKEN_SECRET:-alquimia-vault}"
SHARES="${KEY_SHARES:-1}"
THRESHOLD="${KEY_THRESHOLD:-1}"
SA_TOKEN_PATH=/var/run/secrets/kubernetes.io/serviceaccount/token
CACERT=/var/run/secrets/kubernetes.io/serviceaccount/ca.crt
K8S="https://kubernetes.default.svc/api/v1/namespaces/${NS}"
SA_TOKEN=""
AUTH_HDR=""

refresh_sa_hdr() {
  SA_TOKEN=$(cat "$SA_TOKEN_PATH")
  AUTH_HDR="Authorization: Bearer ${SA_TOKEN}"
}
refresh_sa_hdr

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
  if [ "${WRITE_TOKEN_SECRET:-true}" = "true" ]; then
    upsert_secret "$TOKEN_SECRET" "$token_post" "$token_patch"
    log "keys persistidas en ${KEYS_SECRET}; token en ${TOKEN_SECRET}"
  else
    log "keys persistidas en ${KEYS_SECRET}"
  fi
}

enable_kv() {
  # KV v2 en secret/. Cubbyhole es por token: master y worker no comparten lo escrito ahí.
  code=$(curl -sS -o /tmp/vault-kv-get.json -w "%{http_code}" \
    -H "X-Vault-Token: ${ROOT_TOKEN}" \
    "${VAULT_ADDR}/v1/sys/mounts/secret" || printf '000')
  if [ "$code" = "200" ] && grep -q '"version":"2"' /tmp/vault-kv-get.json; then
    return 0
  fi
  if [ "$code" = "200" ]; then
    log "el mount secret existe y no es kv v2"
    return 1
  fi
  code=$(vault_api POST /v1/sys/mounts/secret '{"type":"kv","options":{"version":"2"}}' /tmp/vault-kv.json)
  if [ "$code" = "204" ] || [ "$code" = "200" ]; then
    log "kv v2 montado en secret/"
    return 0
  fi
  log "kv v2 fallo http=${code}"
  cat /tmp/vault-kv.json 2>/dev/null || true
  return 1
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

json_escape() {
  sed 's/\\/\\\\/g; s/"/\\"/g' | awk 'BEGIN{ORS=""} {if (NR>1) printf "\\n"; printf "%s", $0}'
}

vault_api() {
  method="$1"
  path="$2"
  body="$3"
  outfile="$4"
  curl -sS -o "$outfile" -w "%{http_code}" -X "$method" \
    -H "X-Vault-Token: ${ROOT_TOKEN}" \
    -H "Content-Type: application/json" \
    -d "$body" \
    "${VAULT_ADDR}${path}" || printf '000'
}

write_runtime_policies() {
  cat > /tmp/policy-master.hcl <<'EOF'
path "secret/data/global/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}
path "secret/data/+/shared/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}
path "secret/data/+/local/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}
path "secret/metadata/global/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}
path "secret/metadata/+/shared/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}
path "secret/metadata/+/local/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}
path "database/creds/alquimia-runtime-master" {
  capabilities = ["read"]
}
path "sys/policies/acl/as-*" {
  capabilities = ["create", "read", "update", "delete", "list", "sudo"]
}
# hvac list_policies() hace GET /v1/sys/policy. El glob as-* no cubre ese listado.
path "sys/policy" {
  capabilities = ["read"]
}
# hvac create_or_update_policy() hace PUT /v1/sys/policy/<nombre>. Escribir
# políticas exige sudo.
path "sys/policy/as-*" {
  capabilities = ["create", "read", "update", "delete", "list", "sudo"]
}
path "auth/jwt/role" {
  capabilities = ["list"]
}
path "auth/jwt/role/as-*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}
path "auth/jwt/tidy/identity-grant" {
  capabilities = ["update"]
}
path "sys/leases/revoke-prefix/batch" {
  capabilities = ["update"]
}
EOF
  cat > /tmp/policy-worker.hcl <<'EOF'
path "secret/data/global/*" {
  capabilities = ["read"]
}
path "secret/metadata/global/*" {
  capabilities = ["list", "read"]
}
path "secret/data/+/*" {
  capabilities = ["read"]
}
path "secret/metadata/+/*" {
  capabilities = ["list", "read"]
}
path "database/creds/alquimia-runtime-worker" {
  capabilities = ["read"]
}
EOF
}

apply_runtime_policies() {
  write_runtime_policies
  for name in alquimia-runtime-master alquimia-runtime-worker; do
    if [ "$name" = "alquimia-runtime-master" ]; then
      policy_json=$(json_escape < /tmp/policy-master.hcl)
    else
      policy_json=$(json_escape < /tmp/policy-worker.hcl)
    fi
    code=$(vault_api PUT "/v1/sys/policies/acl/${name}" \
      "{\"policy\":\"${policy_json}\"}" \
      /tmp/vault-policy.json)
    if [ "$code" != "204" ] && [ "$code" != "200" ]; then
      log "policy ${name} fallo http=${code}"
      return 1
    fi
  done
}

refresh_k8s_reviewer() {
  # Vault guarda una copia del JWT. El del pod rota; si no se vuelve a
  # escribir, TokenReview falla y el login kubernetes responde permission denied.
  if [ -z "$ROOT_TOKEN" ] && ! load_keys; then
    log "kubernetes reviewer: no hay root token"
    return 1
  fi
  sum=$(cksum "$SA_TOKEN_PATH" | awk '{print $1}')
  if [ -f /tmp/k8s-reviewer.sum ] && [ "$(cat /tmp/k8s-reviewer.sum)" = "$sum" ]; then
    return 0
  fi
  reviewer=$(cat "$SA_TOKEN_PATH")
  ca_json=$(json_escape < "$CACERT")
  jwt_json=$(printf '%s' "$reviewer" | json_escape)
  code=$(vault_api POST /v1/auth/kubernetes/config \
    "{\"kubernetes_host\":\"https://kubernetes.default.svc\",\"kubernetes_ca_cert\":\"${ca_json}\",\"token_reviewer_jwt\":\"${jwt_json}\"}" \
    /tmp/vault-auth-config.json)
  if [ "$code" != "204" ] && [ "$code" != "200" ]; then
    log "kubernetes reviewer fallo http=${code}"
    return 1
  fi
  printf '%s' "$sum" > /tmp/k8s-reviewer.sum
  log "kubernetes reviewer actualizado"
}

configure_k8s_auth() {
  if [ "${CONFIGURE_K8S_AUTH:-false}" != "true" ]; then
    return 0
  fi
  if [ -f /tmp/k8s-auth.ok ]; then
    refresh_k8s_reviewer || true
    enable_kv || true
    apply_runtime_policies || true
    return 0
  fi
  if [ -z "$ROOT_TOKEN" ] && ! load_keys; then
    log "kubernetes auth: no hay root token"
    return 1
  fi

  code=$(vault_api POST /v1/sys/auth/kubernetes '{"type":"kubernetes"}' /tmp/vault-auth-enable.json)
  if [ "$code" != "204" ] && [ "$code" != "200" ] && [ "$code" != "400" ]; then
    log "kubernetes auth enable fallo http=${code}"
    return 1
  fi

  enable_kv || return 1
  refresh_k8s_reviewer || return 1

  code=$(vault_api POST /v1/sys/auth/jwt '{"type":"jwt"}' /tmp/vault-jwt-enable.json)
  if [ "$code" != "204" ] && [ "$code" != "200" ] && [ "$code" != "400" ]; then
    log "jwt auth enable fallo http=${code}"
    return 1
  fi
  if [ -n "${JWT_OIDC_DISCOVERY_URL:-}" ]; then
    issuer_json=$(printf '%s' "$JWT_OIDC_DISCOVERY_URL" | json_escape)
    code=$(vault_api POST /v1/auth/jwt/config \
      "{\"oidc_discovery_url\":\"${issuer_json}\",\"bound_issuer\":\"${issuer_json}\",\"jwt_supported_algs\":[\"RS256\",\"ES256\",\"ES384\"]}" \
      /tmp/vault-jwt-config.json)
    if [ "$code" != "204" ] && [ "$code" != "200" ]; then
      log "jwt auth config fallo http=${code}"
      cat /tmp/vault-jwt-config.json 2>/dev/null || true
      return 1
    fi
  fi

  apply_runtime_policies || return 1
  for name in alquimia-runtime-master alquimia-runtime-worker; do
    code=$(vault_api POST "/v1/auth/kubernetes/role/${name}" \
      "{\"bound_service_account_names\":\"alquimia-runtime-sa\",\"bound_service_account_namespaces\":\"${NS}\",\"policies\":\"${name}\",\"ttl\":\"1h\",\"audience\":\"vault\"}" \
      /tmp/vault-role.json)
    if [ "$code" != "204" ] && [ "$code" != "200" ]; then
      log "role ${name} fallo http=${code}"
      return 1
    fi
  done

  touch /tmp/k8s-auth.ok
  log "auth listo: kubernetes y jwt en ${NS}"
}

while true; do
  refresh_sa_hdr
  wait_api
  code="$(health_code)"
  log "vault health=${code}"
  case "$code" in
    200|429|472|473)
      if load_keys; then
        save_keys "$UNSEAL_KEY" "$ROOT_TOKEN"
        configure_k8s_auth || true
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
