# Configuración del cliente

Los dominios de este documento son de ejemplo. Reemplazar `acme.example` por el dominio del cliente. No commitear contraseñas: van en un values aparte que no se sube al repo, o en `chart/values-sealed.yaml` generado en el cluster.

## Dominios

| Uso | Valor de ejemplo | Dónde |
|---|---|---|
| API del runtime | `api.acme.example` | `runtime.host` con `runtime.exposure: ingress` o `route` |
| Studio | `studio.acme.example` | `studio.host`. También es el único origen CORS (`ALLOWED_ORIGINS`) |
| Keycloak | `https://auth.acme.example` | `keycloak.existing.url` si Keycloak ya existe. Si `keycloak.enabled: true`, `keycloak.host` |
| Registry público de OCI | `registry.acme.example` | `registry.public.host` y `studio.config.EXTERNAL_REGISTRY_URL` (tienen que coincidir) |
| Dominio SPIFFE | `acme.example` | `runtime.zeroTrust.trustDomain` |

En el Ingress o la Route, el certificado TLS lo pone el cluster (anotación del balanceador, secret TLS o el dominio `apps` de OpenShift). El chart no pide certificados a una CA.

Ejemplo de overlay, sin secretos:

```yaml
runtime:
  exposure: ingress
  host: api.acme.example
  zeroTrust:
    trustDomain: acme.example
  cosign:
    publicKey: |
      -----BEGIN PUBLIC KEY-----
      reemplazar por el PEM de cosign.pub
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

`runtime.ingress.annotations` y `studio.ingress.annotations` dependen del ingress del cluster. En la documentación del chart hay un ejemplo comentado para AWS Load Balancer Controller; el ARN del certificado lo completa el cliente.

## Secretos

`secrets.backend`:

- `sealed`: Argo aplica `values-sealed.yaml`. Cada cliente sella con el certificado de **su** controller y **su** namespace. Ver el README.
- `helm`: el chart crea los Secret desde el values. Ese archivo no se commitea.

Completar, según el backend: Postgres, MinIO, token de API, pull secret de las imágenes, Keycloak (`clientSecret` y `adminClientSecret`), Studio (`nextAuthSecret`) y el registry local (`registry.htpasswd` y `registry.dockerconfig`).

El unsealer escribe `vault-keys` (unseal key y root token). Hay que respaldarlo fuera del cluster. Si se pierde y el disco de Vault sigue, no se puede volver a abrir.

Con Zero Trust el runtime no usa un token estático de Vault. Entra con Kubernetes auth.

## Registry y firmas

`registry.mode: local` despliega `oras-registry` en el namespace y es el registry por defecto del runtime. `registry.tls: true` lo deja en HTTPS. El chart genera la CA, la reutiliza en los upgrades y el runtime la confía.

`registry.public` es un segundo registry, de solo lectura, para los OCI públicos (agents y brains). Hacen falta usuario y contraseña (en Harbor, una robot account). Esos dos valores no van al repo.

Los OCI que el runtime baja tienen que estar firmados con la privada que corresponde a `runtime.cosign.publicKey`. La política es `required`. Sin esa clave pública, o con artefactos sin firma, el pull falla. La privada no se guarda en el chart: la usa quien publica.

Proyectos por defecto: `agents` y `brains`. Tienen que ser los mismos en Studio (`EXTERNAL_REGISTRY_*_PROJECT`) y en el runtime. El chart copia los de Studio al runtime para que no se desfasen.

Firmar un tag, sin subir la firma a un transparency log público:

```bash
cosign sign --key cosign.key --use-signing-config=false --tlog-upload=false \
  registry.acme.example/brains/<nombre>:latest
```

## Keycloak

Realm, client id y secretos son del cliente. El client del runtime necesita un service account que pueda leer usuarios del realm. Studio redirige a `https://<studio.host>`.

`KEYCLOAK_CALLBACK_URI` queda vacío hasta que el cliente defina la URL de callback (`keycloak.runtimeAuth.callbackUri`).

## Zero Trust

`runtime.zeroTrust.enabled: true` activa Keycloak en el runtime, el socket SPIFFE y la firma OCI. `spire.enabled: true` instala SPIRE en el namespace `spire`.

`tlsEnforce` queda en `false`. Redis, Postgres, Kafka, MinIO, Vault y Qdrant hablan en claro dentro del cluster. No activar TLS de Redis ni de Kafka hasta una imagen de runtime que lo soporte: en la imagen actual Redis con TLS se cae al primer comando, y Kafka exige los certificados por archivo (`KAFKA_SSL_*_FILE`), no por el contenido del certificado.

## Qdrant

Es obligatorio. El chart despliega el StatefulSet y el Secret `alquimia-qdrant` (`QDRANT_URL` y API key). `qdrant.enabled: false` hace fallar el render.

## Vault

El unsealer habilita Kubernetes auth, el mount JWT (OIDC de SPIRE) y KV v2 en `secret/`. `VAULT_MOUNT_POINT` es `secret`. Lo que se haya escrito en `cubbyhole` no se ve desde ese mount.

## Lo que el chart deja apagado a propósito

| Tema | Motivo |
|---|---|
| `TLS_ENFORCE` | Los backends del chart siguen en claro |
| Collector OpenTelemetry | `otel.enabled: false` hasta que exista un endpoint |
| Cifrado en reposo (`ENCRYPTION_KEY`, `ALQUIMIA_REGISTRY_KEY`) | Hay que generar las claves una vez y respaldarlas fuera del cluster. Vacío: no se crea el Secret |
| `CHANNEL_NOTIFICATION_SECRET` | Tiene que coincidir con lo que firman los conectores de canal |
| `embeddings.yaml` | Depende del proveedor de embeddings del cliente |
| NetworkPolicy | No se incluyen. Un default-deny sin las reglas del entorno corta el Ingress |
| Alta disponibilidad | Kafka, Vault, Postgres, Redis, Qdrant y el registry local son de una réplica |
