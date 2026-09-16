# Alquimia — instalación (Argo CD + Sealed Secrets)

Chart Helm para un único namespace. Argo CD aplica el chart; Sealed Secrets descifra las credenciales **en el cluster**. Cada cliente sella con la llave de **su** controller.

## Requisitos

- Cluster (OpenShift/ROSA) con **Argo CD** y el **controller de Sealed Secrets** ya instalados
- `oc` o `kubectl` apuntando a ese cluster
- `kubeseal` (CLI)
- Repo Git que Argo pueda clonar

```bash
curl -OL "https://github.com/bitnami/sealed-secrets/releases/download/v0.40.0/kubeseal-0.40.0-linux-amd64.tar.gz"
tar -xzf kubeseal-0.40.0-linux-amd64.tar.gz kubeseal
sudo install -m 755 kubeseal /usr/local/bin/kubeseal
```

## 1. Namespace

En `chart/values.yaml` poner el Project destino, por ejemplo `alquimia-platform`.

Tiene que coincidir con `spec.destination.namespace` en `argocd/application.yaml`.

Si el Project **ya existe**, el chart no lo pisa.

Opcional: `appsDomain` (dominio `apps.*` del cluster) o `studio.host`. Si Argo no puede leer el Ingress del cluster, conviene setear `appsDomain` para que Studio tenga la URL pública correcta.

## 2. Secretos (en claro, solo local)

```bash
./chart/scripts/seal-secrets.sh
```

Copia `chart/secrets/example/` → `chart/secrets/local/`. Completar los `CHANGE_ME` (MinIO, Postgres, Studio, API token, pull secret de Docker Hub, etc.).

Pull secret: `chart/secrets/local/alquimia-dockerhub-pull/.dockerconfigjson`.

**No commitear** `chart/secrets/local/` ni `sealed-cert.pem`.

No hace falta crear `alquimia-vault` ni `vault-keys`: los escribe el unsealer en el cluster.

Si Argo **no puede crear ServiceAccounts**, poner `vault.serviceAccount.create: false` y aplicar el SA (y si hace falta Role + RoleBinding) de [docs/vault-unsealer-rbac.md](docs/vault-unsealer-rbac.md) por consola. El Deployment referencia el SA existente.

## 3. Sellar con la llave del cluster

Ajustar namespace/nombre del controller si en el cluster no es este:

```bash
export NAMESPACE=alquimia-platform   # el mismo que values.yaml

kubeseal --fetch-cert \
  --controller-namespace sealed-secrets \
  --controller-name sealed-secrets \
  > sealed-cert.pem

./chart/scripts/seal-secrets.sh sealed-cert.pem
```

Eso escribe `chart/values-sealed.yaml` (cifrado para **este** namespace y **este** cert). Commitear ese archivo.

Si cambian el namespace, hay que volver a sellar.

## 4. Argo CD

Editar `argocd/application.yaml`:

- `repoURL` y `targetRevision`
- `metadata.namespace`: donde vive Argo (`argocd` u `openshift-gitops`)
- `destination.namespace`: el mismo que `chart/values.yaml`

Dejar `valueFiles: values.yaml` + `values-sealed.yaml` y los `ignoreDifferences` de `alquimia-vault` / `vault-keys`.

```bash
oc apply -f argocd/application.yaml
```

Argo sincroniza solo. No hace falta `helm upgrade` en el cluster.

## 5. Después del primer sync

1. Esperar Vault (unsealer hace init + unseal).
2. **Respaldar** el secret `vault-keys`. Si se pierde y el PVC de Vault sigue, no hay forma de unsealar.
3. Studio queda en `https://alquimia-studio.<appsDomain>` (o el host que hayan puesto).

## Qué incluye el chart

| Componente | Recursos |
|---|---|
| Infra | MinIO, Kafka (KRaft), PostgreSQL, Redis, ORAS registry, Vault |
| Runtime | ConfigMap, master, workers (SA `default` + pull secret en el pod) |
| Studio | Deployment, Service, Route |

`nodeAffinity` es opcional en `values.yaml`.
