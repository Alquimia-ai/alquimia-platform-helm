# MinIO

The runtime stores blobs in MinIO and rclone keeps a copy of the on-disk registry in a second bucket. The hostname in this guide is an example. Replace `minio.acme.example` with the environment's. Access keys are not part of the repository.

Two deployments:

- `minio.enabled: true` deploys MinIO in the installation namespace. The Service is `minio-service` on port 9000, over HTTP.
- `minio.enabled: false` deploys nothing. `minio.endpoint` is the MinIO that already exists.

## Buckets

| Secret key | Default | What uses it |
|---|---|---|
| `BLOB_S3_BUCKET_NAME` | `alquimia-runtime-blob-storage` | Runtime blobs. The master init runs `rclone mkdir` on this bucket |
| `REGISTRY_S3_BUCKET_NAME` | `alquimia-runtime-registry-storage` | rclone sync of `/var/lib/alquimia/registry` |

`runtime.secrets.s3.provider` is `Minio`. `runtime.secrets.s3.region` is `us-east-1`. Both are written to `alquimia-s3`.

## Chart MinIO

```yaml
minio:
  enabled: true
  endpoint: ""
  auth:
    rootUser: minio
    rootPassword: root-password
```

`endpoint` stays empty. The chart writes `BLOB_S3_ENDPOINT_URL` as `http://minio-service.<namespace>.svc.cluster.local:9000` and `BLOB_S3_SECURE` as `false`.

`minio.auth` is the root user of that server. It is stored in the Secret `minio-secret` (`minio_root_user`, `minio_root_password`) and only when `secrets.backend` is `helm`. It is not the credential the runtime uses to connect.

With `secrets.backend: sealed`, the root user lives in `chart/secrets/local/minio-secret/` (`minio_root_user`, `minio_root_password`). Seal it with `chart/scripts/seal-secrets.sh`. `chart/secrets/local/` is not committed.

## Remote MinIO

```yaml
minio:
  enabled: false
  endpoint: https://minio.acme.example:9000
```

`minio.endpoint` has a scheme and no path. `minio.acme.example:9000` is not a valid endpoint. An `https://` endpoint sets `BLOB_S3_SECURE=true`. An `http://` endpoint sets it to `false`.

`minio.endpoint` and `minio.enabled: true` cannot be set together. With `secrets.backend: helm`, `minio.enabled: false` requires `minio.endpoint`. With `secrets.backend: sealed` and an empty `minio.endpoint`, the URL and `BLOB_S3_SECURE` stay the ones sealed in `alquimia-s3`. When `minio.endpoint` is set, that URL and the TLS flag override the sealed values on the runtime and on rclone. The access key and the secret key stay in the Secret.

## Credentials

The runtime and rclone read the Secret `alquimia-s3`. The runtime loads every key through `envFrom`. rclone maps `BLOB_S3_ACCESS_KEY` to `RCLONE_S3_ACCESS_KEY_ID` and `BLOB_S3_SECRET_KEY` to `RCLONE_S3_SECRET_ACCESS_KEY`.

### `secrets.backend: helm`

```yaml
runtime:
  secrets:
    s3:
      accessKey: access-key
      secretKey: secret-key
      bucketName: alquimia-runtime-blob-storage
      registryBucketName: alquimia-runtime-registry-storage
      provider: Minio
      region: us-east-1
```

The chart writes those values into `alquimia-s3`. `accessKey` becomes `BLOB_S3_ACCESS_KEY`. `secretKey` becomes `BLOB_S3_SECRET_KEY`. This values file stays outside the repository.

### `secrets.backend: sealed`

The chart does not build `alquimia-s3` from `runtime.secrets.s3`. Put one value per file in `chart/secrets/local/alquimia-s3/` and seal it with `chart/scripts/seal-secrets.sh`. The example layout is `chart/secrets/example/alquimia-s3/`:

| File | Secret key |
|---|---|
| `BLOB_S3_ACCESS_KEY` | Access key |
| `BLOB_S3_SECRET_KEY` | Secret key |
| `BLOB_S3_BUCKET_NAME` | Blob bucket |
| `REGISTRY_S3_BUCKET_NAME` | Registry bucket |
| `BLOB_S3_PROVIDER` | `Minio` |
| `BLOB_S3_REGION_NAME` | Region |
| `BLOB_S3_ENDPOINT_URL` | URL, used when `minio.endpoint` is empty |
| `BLOB_S3_SECURE` | `true` or `false`, used when `minio.endpoint` is empty |

## Private CA

`minio.ca` mounts an extra CA on the runtime and on every rclone container (the bucket init, the registry fetch, and the sync sidecar). An init container appends the PEM to `/etc/ssl/cert.pem`. The image CAs stay in the bundle, and a registry CA configured with `registry.ca` is appended to the same file.

The runtime reads the bundle through `SSL_CERT_FILE`, `REQUESTS_CA_BUNDLE`, `CURL_CA_BUNDLE`, and `AWS_CA_BUNDLE`. rclone reads it through `RCLONE_CA_CERT`.

Paste the PEM. The chart writes it to the ConfigMap `alquimia-minio-ca`, key `ca.crt`:

```yaml
minio:
  enabled: false
  endpoint: https://minio.acme.example:9000
  ca:
    bundle: |
      -----BEGIN CERTIFICATE-----
      ...
      -----END CERTIFICATE-----
```

Or mount a Secret that already exists in the installation namespace. `existingSecretKey` defaults to `ca.crt`:

```yaml
minio:
  enabled: false
  endpoint: https://minio.acme.example:9000
  ca:
    existingSecret: minio-internal-ca
    existingSecretKey: ca.crt
```

Set `bundle` or `existingSecret`, not both. `minio.ca` requires `minio.enabled: false` and HTTPS. With `secrets.backend: sealed` and an empty `minio.endpoint`, the URL sealed in `alquimia-s3` is `https://`.
