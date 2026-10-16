# Cosign

El runtime verifica la firma de cada artefacto OCI que obtiene y, si el overlay trae la clave privada, también firma lo que publica. La clave pública vive en el ConfigMap `alquimia-cosign`. La privada, cuando se indica, vive en el Secret `alquimia-cosign-key`. Ninguna de las dos forma parte del repositorio: se suministran en el archivo de values de la instalación.

Con `runtime.zeroTrust.enabled: true` la política queda en `ALQUIMIA_OCI_SIGNATURE_POLICY=required` (`runtime.zeroTrust.signaturePolicy`). Sin Zero Trust la política queda en `off` y el runtime no exige firma.

## Solo verificación (pull)

Alcanza con `runtime.cosign.publicKey`. El chart monta ese PEM en `/etc/alquimia/cosign/cosign.pub` y define `ALQUIMIA_OCI_COSIGN_PUBKEY` con esa ruta. Cada artefacto tiene que estar firmado con la clave privada correspondiente. Si falta la clave pública, o el artefacto no tiene firma, la descarga falla.

No hace falta `privateKey` ni `password`. `ALQUIMIA_OCI_COSIGN_KEY` y `COSIGN_PASSWORD` no se inyectan.

```yaml
runtime:
  cosign:
    publicKey: |
      -----BEGIN PUBLIC KEY-----
      PEM de cosign.pub
      -----END PUBLIC KEY-----
```

## Verificación y firma (pull y push)

Para que el runtime firme al publicar, el mismo bloque incluye el PEM privado y la passphrase:

```yaml
runtime:
  cosign:
    publicKey: |
      -----BEGIN PUBLIC KEY-----
      PEM de cosign.pub
      -----END PUBLIC KEY-----
    privateKey: |
      -----BEGIN ENCRYPTED SIGSTORE PRIVATE KEY-----
      PEM de cosign.key
      -----END ENCRYPTED SIGSTORE PRIVATE KEY-----
    password: ""
```

El chart guarda el PEM en el Secret `alquimia-cosign-key`, lo monta junto a la clave pública y deja estas variables en el master y en los workers:

| Variable | Valor |
|---|---|
| `ALQUIMIA_OCI_COSIGN_PUBKEY` | `/etc/alquimia/cosign/cosign.pub` |
| `ALQUIMIA_OCI_COSIGN_KEY` | `/etc/alquimia/cosign/cosign.key` |
| `COSIGN_PASSWORD` | el valor de `runtime.cosign.password` |

`ALQUIMIA_OCI_COSIGN_KEY` es la ruta del archivo, igual que `ALQUIMIA_OCI_COSIGN_PUBKEY`. El PEM se escribe en `privateKey`, no en la variable.

`COSIGN_PASSWORD` es la passphrase con la que se generó `cosign.key`. Si esa passphrase está vacía, el overlay lleva `password: ""`. El Secret queda con `COSIGN_PASSWORD` vacío. No se rellena con un texto, un espacio ni un valor por defecto. Cosign usa esa variable para no pedir la passphrase en modo interactivo; si la clave no tiene passphrase y la variable no existe, la firma falla.

Con `privateKey` vacío el runtime solo verifica. No se crea el Secret y no se define `ALQUIMIA_OCI_COSIGN_KEY`.

Las credenciales de push al registry (`registry.dockerconfig` o `registry.public`) son distintas de la clave de cosign. Autentican contra el registry; no firman el artefacto.

## Firma fuera del cluster

La publicación puede firmar el tag antes de que el runtime lo obtenga. En ese caso el cluster solo necesita `publicKey`. La passphrase, si existe, se usa en ese comando y no entra al chart:

```bash
cosign sign --key cosign.key --use-signing-config=false --tlog-upload=false \
  registry.acme.example/brains/<nombre>:latest
```

`ALQUIMIA_OCI_COSIGN_TLOG_UPLOAD` queda en `false`: la firma no se publica en un transparency log público. `ALQUIMIA_OCI_COSIGN_HOME` queda en `/tmp/cosign`.
