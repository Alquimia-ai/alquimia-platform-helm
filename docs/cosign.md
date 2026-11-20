# Cosign

The runtime verifies the signature of every OCI artifact it fetches and, if the overlay includes the private key, also signs what it publishes. The public key lives in the `alquimia-cosign` ConfigMap. The private key, when provided, lives in the `alquimia-cosign-key` Secret. Neither is part of the repository: they are supplied in the installation's values file.

With `runtime.zeroTrust.enabled: true` the policy is `ALQUIMIA_OCI_SIGNATURE_POLICY=required` (`runtime.zeroTrust.signaturePolicy`). Without Zero Trust the policy is `off` and the runtime does not require a signature.

## Verification only (pull)

`runtime.cosign.publicKey` is enough. The chart mounts that PEM at `/etc/alquimia/cosign/cosign.pub` and sets `ALQUIMIA_OCI_COSIGN_PUBKEY` to that path. Every artifact must be signed with the matching private key. If the public key is missing, or the artifact has no signature, the download fails.

`privateKey` and `password` are not needed. `ALQUIMIA_OCI_COSIGN_KEY` and `COSIGN_PASSWORD` are not injected.

```yaml
runtime:
  cosign:
    publicKey: |
      -----BEGIN PUBLIC KEY-----
      PEM from cosign.pub
      -----END PUBLIC KEY-----
```

## Verification and signing (pull and push)

For the runtime to sign on publish, the same block includes the private PEM and the passphrase:

```yaml
runtime:
  cosign:
    publicKey: |
      -----BEGIN PUBLIC KEY-----
      PEM from cosign.pub
      -----END PUBLIC KEY-----
    privateKey: |
      -----BEGIN ENCRYPTED SIGSTORE PRIVATE KEY-----
      PEM from cosign.key
      -----END ENCRYPTED SIGSTORE PRIVATE KEY-----
    password: ""
```

The chart stores the PEM in the `alquimia-cosign-key` Secret, mounts it next to the public key, and sets these variables on the master and the workers:

| Variable | Value |
|---|---|
| `ALQUIMIA_OCI_COSIGN_PUBKEY` | `/etc/alquimia/cosign/cosign.pub` |
| `ALQUIMIA_OCI_COSIGN_KEY` | `/etc/alquimia/cosign/cosign.key` |
| `COSIGN_PASSWORD` | the value of `runtime.cosign.password` |

`ALQUIMIA_OCI_COSIGN_KEY` is the file path, the same as `ALQUIMIA_OCI_COSIGN_PUBKEY`. The PEM is written in `privateKey`, not in the variable.

`COSIGN_PASSWORD` is the passphrase `cosign.key` was generated with. If that passphrase is empty, the overlay uses `password: ""`. The Secret is left with an empty `COSIGN_PASSWORD`. Do not fill it with text, a space, or a default value. Cosign uses that variable so it does not prompt for the passphrase in interactive mode; if the key has no passphrase and the variable does not exist, signing fails.

With `privateKey` empty the runtime only verifies. The Secret is not created and `ALQUIMIA_OCI_COSIGN_KEY` is not set.

Push credentials for the registry (`registry.dockerconfig` or `registry.public`) are separate from the cosign key. They authenticate to the registry; they do not sign the artifact.

## Signing outside the cluster

Publishing can sign the tag before the runtime fetches it. In that case the cluster only needs `publicKey`. The passphrase, if there is one, is used in that command and does not enter the chart:

```bash
cosign sign --key cosign.key --use-signing-config=false --tlog-upload=false \
  registry.acme.example/brains/<name>:latest
```

`ALQUIMIA_OCI_COSIGN_TLOG_UPLOAD` stays `false`: the signature is not published to a public transparency log. `ALQUIMIA_OCI_COSIGN_HOME` stays `/tmp/cosign`.
