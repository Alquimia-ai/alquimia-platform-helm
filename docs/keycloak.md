# Keycloak

The runtime and Studio authenticate against Keycloak. The hostname in this guide is an example. Replace `auth.acme.example` with the environment's. Client secrets are not part of the repository.

Two deployments:

- `keycloak.enabled: true` deploys Keycloak in the installation namespace. It uses the chart's PostgreSQL. There is no Keycloak Operator.
- `keycloak.enabled: false` deploys nothing. `keycloak.existing.url` or `keycloak.existing.service` is the Keycloak that already exists.

`keycloak.enabled: true` together with `existing.url` or `existing.service` fails the render.

The chart writes the URL to the ConfigMap `keycloak-config` (`KEYCLOAK_URL`, `KEYCLOAK_REALM`, `KEYCLOAK_ISSUER`). The issuer is `<url>/realms/<realm>`. The default realm is `alquimia`.

## Chart Keycloak

```yaml
keycloak:
  enabled: true
  realm: alquimia
  host: auth.acme.example
  exposure: ingress
  auth:
    username: admin
    password: admin-password
```

`host` empty uses `keycloak.<appsDomain>`. `exposure` is `route` (OpenShift) or `ingress`. The runtime calls `https://<host>` when `host` is set, and `http://keycloak.<namespace>.svc.cluster.local:8080` when it is empty.

`keycloak.auth` is the bootstrap admin of that server (`KC_BOOTSTRAP_ADMIN_USERNAME`, `KC_BOOTSTRAP_ADMIN_PASSWORD` in the Secret `keycloak-secret`). It is created when `secrets.backend` is `helm`. With `secrets.backend: sealed`, those two files live in `chart/secrets/local/keycloak-secret/`. Seal them with `chart/scripts/seal-secrets.sh`. `chart/secrets/local/` is not committed.

`keycloak.enabled: true` requires `postgresql.enabled: true`.

## Remote Keycloak

`existing.url` takes priority over `existing.service`.

```yaml
keycloak:
  enabled: false
  existing:
    url: https://auth.acme.example
  realm: alquimia
```

The URL keeps its scheme. A trailing slash is stripped where the runtime reads `KEYCLOAK_SERVER_URL`.

A Service that already exists in the cluster, called over HTTP:

```yaml
keycloak:
  enabled: false
  existing:
    service: keycloak
    namespace: identity
    port: 8080
```

The chart calls `http://keycloak.identity.svc.cluster.local:8080`. `existing.service` without `existing.namespace` fails the render. `existing.secretName` is copied into `keycloak-config` as `KEYCLOAK_SECRET`. The chart does not mount that Secret.

The realm, the runtime client, and the Studio client belong to that Keycloak. The chart does not create them. The runtime client needs a service account that can read realm users.

## Who uses it

`runtime.zeroTrust.enabled: true` or `keycloak.runtimeAuth.enabled: true` sets `AUTH_PROVIDER=keycloak` on the runtime. Otherwise the runtime stays on `api_token`.

```yaml
keycloak:
  runtimeAuth:
    enabled: true
    clientId: alquimia-runtime
    clientSecret: runtime-client-secret
    adminClientSecret: admin-client-secret
    callbackUri: https://api.acme.example/callback
  studioAuth:
    enabled: true
    clientId: alquimia-studio
    clientSecret: studio-client-secret
```

| Value | Where it is written |
|---|---|
| `runtimeAuth.clientId` | `KEYCLOAK_CLIENT_ID` in `alquimia-config` |
| `runtimeAuth.clientSecret` | `KEYCLOAK_CLIENT_SECRET` in the Secret `alquimia-keycloak` |
| `runtimeAuth.adminClientSecret` | `KEYCLOAK_ADMIN_CLIENT_SECRET` in that same Secret, when it is set |
| `runtimeAuth.callbackUri` | `KEYCLOAK_CALLBACK_URI`, when it is set. Empty until the installation sets it |
| `studioAuth.clientId` | `KEYCLOAK_CLIENT_ID` and `AUTH_KEYCLOAK_ID` in `alquimia-studio-config` |
| `studioAuth.clientSecret` | `KEYCLOAK_CLIENT_SECRET` and `AUTH_KEYCLOAK_SECRET` in `alquimia-studio-secrets` |

`studioAuth.enabled: true` sets Studio `AUTH_STRATEGY=keycloak` and `KEYCLOAK_ISSUER` / `AUTH_KEYCLOAK_ISSUER`. Studio redirects to `https://<studio.host>`. `studioAuth.enabled` requires `studio.enabled`. `runtimeAuth.enabled` requires `runtime.enabled`.

With zero trust, `KEYCLOAK_ACCEPTED_AUDIENCES` comes from `runtime.zeroTrust.acceptedAudiences` and `KEYCLOAK_ROLE_SOURCE_CLIENTS` from `runtime.zeroTrust.roleSourceClients`. Without zero trust, the audience is `keycloak.acceptedAudiences` (default `alquimia-runtime`).

### `secrets.backend: helm`

`runtimeAuth.clientSecret`, `runtimeAuth.adminClientSecret`, and `studioAuth.clientSecret` are the values above. The chart writes the Secrets. That values file stays outside the repository.

### `secrets.backend: sealed`

The chart does not build these Secrets from values. Put one value per file and seal with `chart/scripts/seal-secrets.sh`:

| Directory | File |
|---|---|
| `chart/secrets/local/alquimia-keycloak/` | `KEYCLOAK_CLIENT_SECRET` |
| `chart/secrets/local/alquimia-keycloak/` | `KEYCLOAK_ADMIN_CLIENT_SECRET`, when the admin client is used |
| `chart/secrets/local/alquimia-studio-secrets/` | `KEYCLOAK_CLIENT_SECRET` |

The example layout is under `chart/secrets/example/`. `KEYCLOAK_ADMIN_CLIENT_SECRET` is not in the example. Add that file in the same directory when the runtime needs the admin client.

## Private CA

`keycloak.ca` mounts an extra CA when Keycloak is remote and `existing.url` is `https://`. The runtime appends the PEM to `/etc/ssl/cert.pem` and reads the bundle through `SSL_CERT_FILE`, `REQUESTS_CA_BUNDLE`, and `CURL_CA_BUNDLE`. The image CAs stay in the bundle, and a registry or MinIO CA configured the same way is appended to the same file. Studio reads the Keycloak PEM through `NODE_EXTRA_CA_CERTS`, so the CA of the image stays in use there too.

Paste the PEM. The chart writes it to the ConfigMap `alquimia-keycloak-ca`, key `ca.crt`:

```yaml
keycloak:
  enabled: false
  existing:
    url: https://auth.acme.example
  ca:
    bundle: |
      -----BEGIN CERTIFICATE-----
      ...
      -----END CERTIFICATE-----
```

Or mount a Secret that already exists in the installation namespace. `existingSecretKey` defaults to `ca.crt`:

```yaml
keycloak:
  enabled: false
  existing:
    url: https://auth.acme.example
  ca:
    existingSecret: keycloak-internal-ca
    existingSecretKey: ca.crt
```

Set `bundle` or `existingSecret`, not both. `keycloak.ca` requires `keycloak.enabled: false` and an `existing.url` that starts with `https://`. `existing.service` is HTTP, so a CA does not apply to it.
