# Alquimia — installation (Argo CD + Sealed Secrets)

Helm chart for a single namespace. Argo CD applies the chart; Sealed Secrets decrypts the credentials **in the cluster**. Each customer seals with the key of **their** controller.

## Requirements

- Cluster (OpenShift/ROSA) with **Argo CD** and the **Sealed Secrets controller** already installed
- `oc` or `kubectl` pointed at that cluster
- `kubeseal` (CLI)
- A Git repo Argo can clone

```bash
curl -OL "https://github.com/bitnami/sealed-secrets/releases/download/v0.40.0/kubeseal-0.40.0-linux-amd64.tar.gz"
tar -xzf kubeseal-0.40.0-linux-amd64.tar.gz kubeseal
sudo install -m 755 kubeseal /usr/local/bin/kubeseal
```

## 1. Namespace

In `chart/values.yaml` set the destination Project, for example `alquimia-platform`.

It must match `spec.destination.namespace` in `argocd/application.yaml`.

If the Project **already exists**, the chart does not overwrite it.

Optional: `appsDomain` (the cluster `apps.*` domain) or `studio.host`. If Argo cannot read the cluster Ingress, set `appsDomain` so Studio gets the correct public URL.

## 2. Secrets (plaintext, local only)

```bash
./chart/scripts/seal-secrets.sh
```

Copies `chart/secrets/example/` → `chart/secrets/local/`. Fill in the `CHANGE_ME` values (MinIO, Postgres, Studio, API token, Docker Hub pull secret, and so on).

Pull secret: `chart/secrets/local/alquimia-dockerhub-pull/.dockerconfigjson`.

**Do not commit** `chart/secrets/local/` or `sealed-cert.pem`.

There is no need to create `alquimia-vault` or `vault-keys`: the unsealer writes them in the cluster.

If Argo **cannot create ServiceAccounts**, set `vault.serviceAccount.create: false` and apply the SA (and, if needed, the Role and RoleBinding) from [docs/vault-unsealer-rbac.md](docs/vault-unsealer-rbac.md) out of band. The Deployment references the existing SA.

## 3. Seal with the cluster key

Adjust the controller namespace and name if they are different in this cluster:

```bash
export NAMESPACE=alquimia-platform   # the same value as values.yaml

kubeseal --fetch-cert \
  --controller-namespace sealed-secrets \
  --controller-name sealed-secrets \
  > sealed-cert.pem

./chart/scripts/seal-secrets.sh sealed-cert.pem
```

That writes `chart/values-sealed.yaml` (encrypted for **this** namespace and **this** cert). Commit that file.

If the namespace changes, seal again.

## 4. Argo CD

Edit `argocd/application.yaml`:

- `repoURL` and `targetRevision`
- `metadata.namespace`: where Argo lives (`argocd` or `openshift-gitops`)
- `destination.namespace`: the same value as `chart/values.yaml`

Leave `valueFiles: values.yaml` + `values-sealed.yaml` and the `ignoreDifferences` for `alquimia-vault` / `vault-keys`.

```bash
oc apply -f argocd/application.yaml
```

Argo syncs on its own. There is no need to run `helm upgrade` on the cluster.

## 5. After the first sync

1. Wait for Vault (the unsealer runs init + unseal).
2. **Back up** the `vault-keys` secret. If it is lost and the Vault PVC remains, there is no way to unseal.
3. Studio is at `https://alquimia-studio.<appsDomain>` (or the host that was set).

## What the chart includes

| Component | Resources |
|---|---|
| Infra | MinIO, Kafka (KRaft), PostgreSQL, Redis, ORAS registry, Vault |
| Runtime | ConfigMap, master, workers (SA `default` + pull secret on the pod) |
| Studio | Deployment, Service, Route |

Resource and usage table: [docs/resources.md](docs/resources.md).

`nodeAffinity` is optional in `values.yaml`.
