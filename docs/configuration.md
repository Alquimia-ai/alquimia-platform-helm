# Configuration

The hostnames in this guide are examples. Replace `acme.example` with the environment's domain. Credentials are not part of the chart: they are supplied in a private values file or in `chart/values-sealed.yaml`, generated for the installation's namespace and Sealed Secrets certificate.

## Domains

| Use | Example value | Parameter |
|---|---|---|
| Runtime API | `api.acme.example` | `runtime.host`, with `runtime.exposure` set to `ingress` or `route` |
| Studio | `studio.acme.example` | `studio.host`. It is also the only origin allowed in `ALLOWED_ORIGINS` |
| Keycloak | `https://auth.acme.example` | `keycloak.existing.url` when Keycloak is already installed. With `keycloak.enabled: true`, `keycloak.host` |
| Public OCI registry | `registry.acme.example` | `registry.public.host` and `studio.config.EXTERNAL_REGISTRY_URL`. Both values must match |
| SPIFFE domain | `acme.example` | `runtime.zeroTrust.trustDomain` |

The Ingress or Route TLS certificate comes from the cluster: a load balancer annotation, a TLS Secret, or the OpenShift `apps` domain. The chart does not request certificates.

Example overlay, without credentials:

```yaml
runtime:
  exposure: ingress
  host: api.acme.example
  zeroTrust:
    trustDomain: acme.example
  cosign:
    publicKey: |
      -----BEGIN PUBLIC KEY-----
      PEM from cosign.pub
      -----END PUBLIC KEY-----

studio:
  exposure: ingress
  host: studio.acme.example
  config:
    EXTERNAL_REGISTRY_URL: registry.acme.example
    EXTERNAL_REGISTRY_AGENTS_PROJECT: agents
    EXTERNAL_REGISTRY_BRAINS_PROJECT: brains

keycloak:
  enabled: false
  existing:
    url: https://auth.acme.example
  realm: production

registry:
  public:
    host: registry.acme.example
```

`runtime.ingress.annotations` and `studio.ingress.annotations` depend on the cluster's Ingress controller. `chart/values.yaml` includes a commented example for the AWS Load Balancer Controller. The certificate ARN is the one for the account where this is deployed.

## Secrets

`secrets.backend` accepts two modes:

- `sealed`. Argo CD applies `values-sealed.yaml`. Sealing uses the Sealed Secrets controller certificate and the installation namespace. The procedure is in the README.
- `helm`. The chart creates Secrets from the installation's values file. That file stays outside the repository.

Depending on the chosen mode, the installation sets the credentials for PostgreSQL, MinIO, the API token, the image pull secret, Keycloak (`clientSecret` and `adminClientSecret`), Studio (`nextAuthSecret`), and the local registry (`registry.htpasswd` and `registry.dockerconfig`).

The unsealer stores the unseal key and the root token in the `vault-keys` Secret. Keep a copy outside the cluster. If that Secret is lost and the Vault volume remains, Vault cannot be unsealed again.

With Zero Trust the runtime does not use a static token. Authentication to Vault is Kubernetes auth.

## Registry and signatures

With `registry.mode: local` the chart deploys `oras-registry` in the installation namespace. That service is the runtime's default registry. `registry.tls: true` publishes the local registry over HTTPS. The chart issues the CA, keeps it across upgrades, and the runtime uses it to verify the certificate.

With `registry.mode: remote` the runtime uses `registry.host`. A certificate signed by an internal CA is mounted with `registry.ca` on the runtime and the workers. See [quay.md](quay.md).

`registry.public` is a second, read-only registry for public OCI artifacts (projects `agents` and `brains`). It requires a username and password. On Harbor, a robot account. Those credentials are not included in the repository.

To use Quay as a remote registry, with a robot account and the OCI index, see [quay.md](quay.md).

The signature policy is `required`. Every artifact the runtime fetches must be signed with the private key that matches `runtime.cosign.publicKey`. Details of the public key, the private key, and `COSIGN_PASSWORD` are in [cosign.md](cosign.md).

The default projects are `agents` and `brains`. Studio (`EXTERNAL_REGISTRY_*_PROJECT`) and the runtime must use the same names. The chart copies Studio's values to the runtime.

## Keycloak

`keycloak.enabled: true` deploys Keycloak in the installation namespace, on the chart's PostgreSQL. A Keycloak that already exists, the runtime and Studio clients, and a private CA are in [keycloak.md](keycloak.md).

## OpenShift

`openshift: false` sets `fsGroup: 1000` on the runtime, the workers, Kafka, and Qdrant, and `fsGroup: 999` on PostgreSQL. PostgreSQL also adds `CHOWN`, `DAC_OVERRIDE`, `FOWNER`, `SETUID`, and `SETGID` so the image can start as root, chown its data directory, and drop to `postgres`.

`openshift: true` is the restricted-v2 profile. The chart does not set `fsGroup` or `runAsUser`. The master and the workers also omit `supplementalGroups: [1000]`. PostgreSQL drops every capability, sets `runAsNonRoot: true`, and stays on `images.postgres`. OpenShift assigns the UID and the fsGroup from the namespace range, and that image runs as that UID.

A volume PostgreSQL already initialized as uid 999 with mode `0700` is not writable by the new UID. A new install is. An existing data directory needs its owner fixed once.

## Zero Trust

`runtime.zeroTrust.enabled: true` turns on Keycloak in the runtime, the SPIFFE socket, and OCI signature verification. `spire.enabled: true` installs SPIRE in the `spire` namespace.

`tlsEnforce` stays `false`. Redis, PostgreSQL, Kafka, the MinIO this chart installs, Vault, and Qdrant talk without TLS inside the cluster. The current runtime image does not support TLS for Redis: the connection fails on the first command. Kafka only accepts certificates through `KAFKA_SSL_*_FILE`, not as certificate content in a variable.

## MinIO

`minio.enabled: true` deploys MinIO in the installation namespace. The runtime and rclone use `http://minio-service.<namespace>.svc.cluster.local:9000`. A MinIO that already exists, its access key, and a private CA are in [minio.md](minio.md).

## Qdrant

Qdrant is a required component. The chart creates the StatefulSet and the `alquimia-qdrant` Secret, with `QDRANT_URL` and the API key. `qdrant.enabled: false` stops the Helm render.

## Vault

The unsealer enables Kubernetes authentication, the JWT mount against SPIRE's OIDC, and the KV v2 engine at `secret/`. `VAULT_MOUNT_POINT` is `secret`. Data written to `cubbyhole` is not visible from that mount: `cubbyhole` is isolated per token.

## Values that stay disabled

| Parameter | Behavior |
|---|---|
| `TLS_ENFORCE` | Stays disabled. The backends this chart installs do not terminate TLS |
| OpenTelemetry | `otel.enabled: false` until `otel.endpoint` points at a collector |
| Encryption at rest (`ENCRYPTION_KEY`, `ALQUIMIA_REGISTRY_KEY`) | Keys are generated once and kept outside the cluster. If they are empty, the chart does not create the Secret |
| `CHANNEL_NOTIFICATION_SECRET` | Must match the secret the channel connectors sign with |
| `embeddings.yaml` | Requires the installation's embeddings provider |
| NetworkPolicy | The chart does not define them. A default-deny policy without ingress rules breaks Ingress |
| High availability | Kafka, Vault, PostgreSQL, Redis, Qdrant, and the local registry deploy with one replica |
