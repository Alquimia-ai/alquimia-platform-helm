# Quay

The chart does not install Quay. With `registry.mode: remote` the runtime publishes to and reads from a Quay that already exists, and stops deploying the local registry (`oras-registry`). The integration was checked against Quay 3.18.

The hostname in this guide is an example. Replace `registry.acme.example` with the environment's. The robot token is not part of the repository.

## What must already exist in Quay

Two organizations, with the same names the chart uses:

| Organization | Parameter | Runtime variable |
|---|---|---|
| `agents` | `studio.config.EXTERNAL_REGISTRY_AGENTS_PROJECT` | `ALQUIMIA_OCI_NAMESPACE_AGENTSPACES` |
| `brains` | `studio.config.EXTERNAL_REGISTRY_BRAINS_PROJECT` | `ALQUIMIA_OCI_NAMESPACE_BRAINS` |

The chart copies those two Studio values into the `alquimia-config` ConfigMap. If they are renamed, change them in Studio: the runtime has no parameter of its own.

Each publish writes the artifact to its repository (`agents/probe`) and, with the index enabled, an entry on the namespace anchor (`agents/index` or `brains/index`). The runtime creates those anchors. They are not user artifacts. Studio lists the catalog by reading the anchor, not with `/v2/_catalog`.

## Overlay

```yaml
registry:
  enabled: true
  mode: remote
  host: registry.acme.example
  plainHttp: false
  insecure: false
  public:
    host: registry.acme.example

studio:
  config:
    EXTERNAL_REGISTRY_URL: registry.acme.example
    EXTERNAL_REGISTRY_AGENTS_PROJECT: agents
    EXTERNAL_REGISTRY_BRAINS_PROJECT: brains
```

`registry.host` is written to `ALQUIMIA_OCI_REGISTRY_DEFAULT`. `studio.config.EXTERNAL_REGISTRY_URL` and `registry.public.host` carry the same hostname: that is the one Studio shows the user.

`registry.host` has no scheme and no path. `https://registry.acme.example` is not a valid host for the chart.

With HTTPS, `plainHttp` and `insecure` stay `false`. Quay presents its own certificate and the runtime verifies it against the trust store of the image. When that certificate is signed by an internal CA, set `registry.ca` (see below).

## Private CA

`registry.ca` mounts an extra CA on the runtime and the workers. An init container appends the PEM to `/etc/ssl/cert.pem` and the containers read the result through `SSL_CERT_FILE`, `REQUESTS_CA_BUNDLE`, and `CURL_CA_BUNDLE`. The image CAs stay in the bundle, so a public `registry.public.host` still verifies. `plainHttp` and `insecure` stay `false`.

Paste the PEM. The chart writes it to the ConfigMap `alquimia-registry-ca`, key `ca.crt`:

```yaml
registry:
  mode: remote
  host: registry.acme.example
  plainHttp: false
  insecure: false
  ca:
    bundle: |
      -----BEGIN CERTIFICATE-----
      ...
      -----END CERTIFICATE-----
```

Or mount a Secret that already exists in the installation namespace. `existingSecretKey` defaults to `ca.crt`:

```yaml
registry:
  mode: remote
  host: registry.acme.example
  plainHttp: false
  insecure: false
  ca:
    existingSecret: quay-internal-ca
    existingSecretKey: ca.crt
```

Set `bundle` or `existingSecret`, not both. `registry.ca` requires `registry.mode: remote`. The local registry keeps the CA it issues in `oras-registry-tls`.

## Robot account

The runtime authenticates with a robot account. The Quay username has the form `<organization>+<name>`, for example `agents+runtime`. The password is the robot token.

A robot is created in one organization. To publish to the other as well, add that same robot to a team in the second organization. The chart stores one credential per hostname: a second robot against the same Quay does not fit in the Secret.

Minimum permissions in each organization:

| Where | Role | What it covers |
|---|---|---|
| Organization team | `creator` | Create repositories. Quay makes the robot admin of the ones it creates, including the `agents/index` and `brains/index` anchors |
| Repository that already existed and was created by another user | `write` | Push and pull of that repository. `creator` does not open other users' private repos |

Organization `owner` is not required.

## Credential in the chart

The Secret is named `alquimia-registry-config`, type `kubernetes.io/dockerconfigjson`. The master and the workers mount the `.dockerconfigjson` key at `/var/docker-config/config.json` and set `DOCKER_CONFIG=/var/docker-config`. ORAS reads that file.

### `secrets.backend: helm`

```yaml
registry:
  dockerconfig:
    username: agents+runtime
    password: robot-token
```

That username and password are the ones stored for `registry.host`. If `registry.public.host` is a different hostname and has a username and password, the chart adds a second entry. If it is the same hostname, the `registry.dockerconfig` entry stays.

Without a username or without a password in `registry.dockerconfig`, the chart creates the Secret with `{"auths":{}}`. ORAS calls Quay without a credential.

### `secrets.backend: sealed`

The chart does not build this Secret from `registry.dockerconfig`. Put the JSON in `chart/secrets/local/alquimia-registry-config/.dockerconfigjson` and seal it with `chart/scripts/seal-secrets.sh`. The host key is the same value as `registry.host`:

```json
{
  "auths": {
    "registry.acme.example": {
      "username": "agents+runtime",
      "password": "robot-token"
    }
  }
}
```

`chart/secrets/local/` is not committed. If that SealedSecret is missing and there is also no Helm username and password, the chart still creates an empty `alquimia-registry-config`.

## Index

`runtime.config.ALQUIMIA_OCI_INDEX_ENABLED` renders as `true`. After a successful push, the runtime attaches the entry to the namespace anchor. With `false` the artifact stays in its repository and the catalog does not show it.

`ALQUIMIA_OCI_REFERRERS_FALLBACK` renders as `error`. The attach requires the native OCI 1.1 referrers API (`GET /v2/<namespace>/index/referrers/<digest>`). Quay 3.18 exposes it. If that probe fails, the artifact stays published and the index entry does not: the runtime records it in the log and does not rewrite ORAS's mutable tag. `warn` still performs that attach and can drop entries when two publishes run at the same time.

## Quay over HTTP

Only when the Quay Ingress does not terminate TLS:

```yaml
registry:
  mode: remote
  host: registry.acme.example
  plainHttp: true
  insecure: false

runtime:
  config:
    ALQUIMIA_OCI_DEV_MODE: "true"
```

The image ignores `ORAS_PLAIN_HTTP` unless `ALQUIMIA_OCI_DEV_MODE` is `true`. With `plainHttp: true` the chart passes through `runtime.config.ALQUIMIA_OCI_DEV_MODE`; that value defaults to `false`, so it has to be set to `true`. With HTTPS the chart forces `ALQUIMIA_OCI_DEV_MODE=false`.

`insecure: true` skips TLS verification. It does not replace `plainHttp`.

## What to check if nothing shows up in Quay

The artifact push and the index attach are two steps. An empty `agents/probe` repo can exist without tags: someone created it, or the runtime created it, and the manifest push never arrived.

| Symptom | Cause |
|---|---|
| `HEAD /v2/...` returns 401 and the Secret has `{"auths":{}}` | ORAS has no username. The robot is missing from `alquimia-registry-config`, or the JSON host is not exactly `registry.host` |
| 401 with the robot loaded, on a repo another user created | The team is `creator` and that repo does not belong to it. The repository needs the `write` role |
| The artifact tag exists and `agents/index` is still empty | `ALQUIMIA_OCI_INDEX_ENABLED` is `false`, or the referrers probe failed with `ALQUIMIA_OCI_REFERRERS_FALLBACK=error` |
| `oras discover .../agents/index:v1` returns `not found` | The anchor has not been written yet. That is the state before the first publish with the index enabled |
