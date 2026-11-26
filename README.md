# Alquimia — installation chart

Helm chart for one namespace on Kubernetes, OpenShift, and EKS. The domains in this guide are examples (`acme.example`) and are replaced with the environment's own. Credentials and the cosign private key are not part of the repository.

What gets deployed and how much it requests: [docs/resources.md](docs/resources.md).

Installation parameters: [docs/configuration.md](docs/configuration.md).

OCI signing: [docs/cosign.md](docs/cosign.md).

Quay registry: [docs/quay.md](docs/quay.md).

MinIO, including a remote endpoint and a private CA: [docs/minio.md](docs/minio.md).

## Requirements

- Cluster with `kubectl` or `oc`
- Helm 3, or Argo CD
- Namespace created before install (`helm --create-namespace`, or one that already exists). The chart does not manage it: if the release owns it, a later upgrade can delete it
- For sealed secrets: Sealed Secrets controller and `kubeseal`
- For Zero Trust: the node privileges SPIRE requires (the runtime itself stays restricted and uses the socket through CSI)

```bash
curl -OL "https://github.com/bitnami/sealed-secrets/releases/download/v0.40.0/kubeseal-0.40.0-linux-amd64.tar.gz"
tar -xzf kubeseal-0.40.0-linux-amd64.tar.gz kubeseal
sudo install -m 755 kubeseal /usr/local/bin/kubeseal
```

## Values

`chart/values.yaml` is the base profile, without credentials. The installation combines it with a private values file or with `chart/values-sealed.yaml`.

The chart's example namespace is `alquimia-platform`. It must match `spec.destination.namespace` in `argocd/application.yaml`.

Example hosts:

| Surface | Host |
|---|---|
| Runtime | `api.acme.example` |
| Studio | `studio.acme.example` |
| Existing Keycloak | `https://auth.acme.example` |
| Public registry | `registry.acme.example` |
| SPIFFE trust domain | `acme.example` |

## Install with Helm

```bash
helm upgrade --install alquimia chart \
  --namespace acme \
  --create-namespace \
  -f chart/values.yaml \
  -f values-install.yaml
```

`values-install.yaml` sets the domains, `secrets.backend: helm`, and the credentials. It stays outside the repository.

## Install with Argo CD and Sealed Secrets

1. Copy `chart/secrets/example/` to `chart/secrets/local/` and fill in the `CHANGE_ME` values. The pull secret is `chart/secrets/local/alquimia-dockerhub-pull/.dockerconfigjson`.
2. Do not create `alquimia-vault` or `vault-keys`: the unsealer writes them. Do not commit `chart/secrets/local/` or `sealed-cert.pem`.
3. Seal with the certificate of **that** cluster and **that** namespace:

```bash
export NAMESPACE=acme

kubeseal --fetch-cert \
  --controller-namespace sealed-secrets \
  --controller-name sealed-secrets \
  > sealed-cert.pem

./chart/scripts/seal-secrets.sh sealed-cert.pem
```

That generates `chart/values-sealed.yaml`. If the namespace changes, seal again.

4. In `argocd/application.yaml`: `repoURL`, `targetRevision`, the Argo namespace, and `destination.namespace`. Leave `valueFiles` as `values.yaml` plus `values-sealed.yaml`.

```bash
kubectl apply -f argocd/application.yaml
```

The Zero Trust profile without Sealed Secrets uses `chart/values-zt.yaml` instead of `values-sealed.yaml`. Helm creates the Secrets.

If Argo cannot create ServiceAccounts, see [docs/vault-unsealer-rbac.md](docs/vault-unsealer-rbac.md).

## After the first sync

1. Wait until the unsealer leaves Vault unsealed.
2. Back up the `vault-keys` Secret outside the cluster.
3. Studio answers at `https://studio.acme.example` (or at `https://alquimia-studio.<appsDomain>` if `studio.host` was left empty and exposure is Route).
4. With `keycloak.enabled: false`, Keycloak is not installed: `keycloak.existing.url` (for example `https://auth.acme.example`) is written to the `keycloak-config` ConfigMap.
5. `runtime.zeroTrust.enabled: false` leaves the runtime on `API_TOKEN`, Kafka in the clear, and OCI signing off. `true` uses Keycloak, SPIFFE, and `ALQUIMIA_OCI_SIGNATURE_POLICY=required`. Public OCI artifacts must be signed with the key in `runtime.cosign.publicKey`.
6. Qdrant is required. The chart deploys it and points the runtime at that service.

`nodeAffinity` is optional. `otel.enabled` exports to the collector at `otel.endpoint`. `kyverno.enabled` (default `false`) requires Kyverno to already be installed.
