# Alquimia — chart de instalación

Chart Helm de un namespace para Kubernetes, OpenShift y EKS. Los dominios de esta guía son de ejemplo (`acme.example`): el cliente los reemplaza. Contraseñas y la clave privada de cosign no van en este repo.

Qué se despliega y cuánto pide: [docs/recursos.md](docs/recursos.md).

Qué hay que completar por cliente: [docs/configuracion.md](docs/configuracion.md).

## Requisitos

- Cluster con `kubectl` o `oc`
- Helm 3, o Argo CD
- Namespace creado antes del install (`helm --create-namespace` o uno que ya exista). El chart no lo administra: si el release lo posee, un upgrade posterior puede borrarlo
- Para secretos sellados: controller de Sealed Secrets y `kubeseal`
- Para Zero Trust: los privilegios de nodo que pide SPIRE (el runtime en sí queda restringido y usa el socket por CSI)

```bash
curl -OL "https://github.com/bitnami/sealed-secrets/releases/download/v0.40.0/kubeseal-0.40.0-linux-amd64.tar.gz"
tar -xzf kubeseal-0.40.0-linux-amd64.tar.gz kubeseal
sudo install -m 755 kubeseal /usr/local/bin/kubeseal
```

## Valores

`chart/values.yaml` es el perfil base, sin secretos. Encima va un values del cliente (no se commitea) o `chart/values-sealed.yaml`.

El namespace de ejemplo del chart es `alquimia-platform`. Tiene que coincidir con `spec.destination.namespace` de `argocd/application.yaml`.

Hosts de ejemplo:

| Superficie | Host |
|---|---|
| Runtime | `api.acme.example` |
| Studio | `studio.acme.example` |
| Keycloak existente | `https://auth.acme.example` |
| Registry público | `registry.acme.example` |
| Trust domain SPIFFE | `acme.example` |

## Instalación con Helm

```bash
helm upgrade --install alquimia chart \
  --namespace acme \
  --create-namespace \
  -f chart/values.yaml \
  -f values-cliente.yaml
```

`values-cliente.yaml` lleva los dominios, `secrets.backend: helm` y las contraseñas. No se sube al repo.

## Instalación con Argo CD y Sealed Secrets

1. Copiar `chart/secrets/example/` a `chart/secrets/local/` y completar los `CHANGE_ME`. El pull secret es `chart/secrets/local/alquimia-dockerhub-pull/.dockerconfigjson`.
2. No crear `alquimia-vault` ni `vault-keys`: los escribe el unsealer. No commitear `chart/secrets/local/` ni `sealed-cert.pem`.
3. Sellar con el certificado de **ese** cluster y **ese** namespace:

```bash
export NAMESPACE=acme

kubeseal --fetch-cert \
  --controller-namespace sealed-secrets \
  --controller-name sealed-secrets \
  > sealed-cert.pem

./chart/scripts/seal-secrets.sh sealed-cert.pem
```

Eso genera `chart/values-sealed.yaml`. Si cambia el namespace, hay que sellar de nuevo.

4. En `argocd/application.yaml`: `repoURL`, `targetRevision`, el namespace de Argo y `destination.namespace`. Dejar `valueFiles` en `values.yaml` más `values-sealed.yaml`.

```bash
kubectl apply -f argocd/application.yaml
```

El perfil Zero Trust sin Sealed Secrets usa `chart/values-zt.yaml` en lugar de `values-sealed.yaml`. Los Secret los crea Helm.

Si Argo no puede crear ServiceAccounts, ver [docs/vault-unsealer-rbac.md](docs/vault-unsealer-rbac.md).

## Después del primer sync

1. Esperar a que el unsealer deje Vault abierto.
2. Respaldar el Secret `vault-keys` fuera del cluster.
3. Studio responde en `https://studio.acme.example` (o en `https://alquimia-studio.<appsDomain>` si `studio.host` quedó vacío y la exposición es Route).
4. Con `keycloak.enabled: false`, Keycloak no se instala: `keycloak.existing.url` (por ejemplo `https://auth.acme.example`) queda en el ConfigMap `keycloak-config`.
5. `runtime.zeroTrust.enabled: false` deja el runtime con `API_TOKEN`, Kafka en claro y la firma OCI apagada. `true` usa Keycloak, SPIFFE y `ALQUIMIA_OCI_SIGNATURE_POLICY=required`. Los OCI públicos tienen que estar firmados con la clave de `runtime.cosign.publicKey`.
6. Qdrant es obligatorio. El chart lo despliega y apunta el runtime a ese servicio.

`nodeAffinity` es opcional. `otel.enabled` exporta al collector de `otel.endpoint`. `kyverno.enabled` (por defecto `false`) exige que Kyverno ya esté instalado.
