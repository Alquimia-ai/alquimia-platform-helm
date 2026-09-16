#!/usr/bin/env bash
# Cifra chart/secrets/local/* con kubeseal y escribe chart/values-sealed.yaml
# Uso:
#   export NAMESPACE=alquimia-platform
#   # cert del controller (una vez, con acceso al cluster):
#   kubeseal --fetch-cert --controller-namespace sealed-secrets --controller-name sealed-secrets > sealed-cert.pem
#   ./chart/scripts/seal-secrets.sh sealed-cert.pem
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
CHART="${ROOT}/chart"
EXAMPLE="${CHART}/secrets/example"
LOCAL="${CHART}/secrets/local"
OUT="${CHART}/values-sealed.yaml"
NS="${NAMESPACE:-alquimia-platform}"
CERT="${1:-}"

if ! command -v kubeseal >/dev/null 2>&1; then
  echo "kubeseal no esta en PATH" >&2
  exit 1
fi

if [ ! -d "${LOCAL}" ]; then
  mkdir -p "${LOCAL}"
  cp -R "${EXAMPLE}/." "${LOCAL}/"
  echo "Copiado secrets/example -> secrets/local. Completa los valores y vuelve a ejecutar."
  exit 0
fi

seal_raw() {
  local name="$1" key="$2" file="$3"
  if [ -n "${CERT}" ]; then
    kubeseal --raw --namespace "${NS}" --name "${name}" --cert "${CERT}" --from-file="${file}"
  else
    kubeseal --raw --namespace "${NS}" --name "${name}" --from-file="${file}"
  fi
}

# Valores derivados del namespace (mismo criterio que el chart)
mkdir -p "${LOCAL}/alquimia-redis" "${LOCAL}/alquimia-postgres" "${LOCAL}/alquimia-s3"
printf 'redis://redis.%s.svc.cluster.local:6379/0' "${NS}" > "${LOCAL}/alquimia-redis/REDIS_URL"
printf 'postgresql.%s.svc.cluster.local' "${NS}" > "${LOCAL}/alquimia-postgres/POSTGRES_HOST"
printf 'http://minio-service.%s.svc.cluster.local:9000' "${NS}" > "${LOCAL}/alquimia-s3/BLOB_S3_ENDPOINT_URL"

{
  echo "# Generado por chart/scripts/seal-secrets.sh (namespace=${NS})"
  echo "sealedSecrets:"
  for dir in "${LOCAL}"/*; do
    [ -d "${dir}" ] || continue
    name="$(basename "${dir}")"
    case "${name}" in
      alquimia-vault|vault-keys) echo "  # omitido ${name} (lo gestiona vault-unsealer)" >&2; continue ;;
    esac
    type="Opaque"
    if [ -f "${dir}/.dockerconfigjson" ]; then
      type="kubernetes.io/dockerconfigjson"
    fi
    echo "  ${name}:"
    echo "    type: ${type}"
    echo "    encryptedData:"
    for file in "${dir}"/* "${dir}/.dockerconfigjson"; do
      [ -f "${file}" ] || continue
      key="$(basename "${file}")"
      enc="$(seal_raw "${name}" "${key}" "${file}")"
      echo "      \"${key}\": \"${enc}\""
    done
  done
} > "${OUT}"

echo "Escrito ${OUT}. Commitear values-sealed.yaml; no commitear secrets/local."
