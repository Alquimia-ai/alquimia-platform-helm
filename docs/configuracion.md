# Configuración

Los nombres de host de esta guía son de referencia. Sustituir `acme.example` por el dominio del entorno. Las credenciales no forman parte del chart: se suministran en un archivo de values privado o en `chart/values-sealed.yaml`, generado para el namespace y el certificado de Sealed Secrets de la instalación.

## Dominios

| Uso | Valor de referencia | Parámetro |
|---|---|---|
| API del runtime | `api.acme.example` | `runtime.host`, con `runtime.exposure` en `ingress` o `route` |
| Studio | `studio.acme.example` | `studio.host`. Es además el único origen permitido en `ALLOWED_ORIGINS` |
| Keycloak | `https://auth.acme.example` | `keycloak.existing.url` cuando Keycloak ya está instalado. Con `keycloak.enabled: true`, `keycloak.host` |
| Registry OCI público | `registry.acme.example` | `registry.public.host` y `studio.config.EXTERNAL_REGISTRY_URL`. Ambos valores deben coincidir |
| Dominio SPIFFE | `acme.example` | `runtime.zeroTrust.trustDomain` |

El certificado TLS del Ingress o de la Route lo aporta el cluster: anotación del balanceador, Secret TLS o el dominio `apps` de OpenShift. El chart no solicita certificados.

Ejemplo de overlay, sin credenciales:

```yaml
runtime:
  exposure: ingress
  host: api.acme.example
  zeroTrust:
    trustDomain: acme.example
  cosign:
    publicKey: |
      -----BEGIN PUBLIC KEY-----
      PEM de cosign.pub
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

`runtime.ingress.annotations` y `studio.ingress.annotations` dependen del controlador de Ingress del cluster. `chart/values.yaml` incluye un ejemplo comentado para AWS Load Balancer Controller. El ARN del certificado corresponde al de la cuenta donde se despliega.

## Secretos

`secrets.backend` admite dos modos:

- `sealed`. Argo CD aplica `values-sealed.yaml`. El sellado usa el certificado del controller de Sealed Secrets y el namespace de la instalación. El procedimiento está en el README.
- `helm`. El chart crea los Secret a partir del archivo de values de la instalación. Ese archivo permanece fuera del repositorio.

Según el modo elegido, la instalación define las credenciales de PostgreSQL, MinIO, el token de API, el pull secret de las imágenes, Keycloak (`clientSecret` y `adminClientSecret`), Studio (`nextAuthSecret`) y el registry local (`registry.htpasswd` y `registry.dockerconfig`).

El unsealer persiste la unseal key y el root token en el Secret `vault-keys`. Conviene conservar una copia fuera del cluster. Si ese Secret se pierde y el volumen de Vault permanece, Vault no puede volver a abrirse.

Con Zero Trust el runtime no utiliza un token estático. La autenticación contra Vault es Kubernetes auth.

## Registry y firmas

Con `registry.mode: local` el chart despliega `oras-registry` en el namespace de la instalación. Ese servicio es el registry por defecto del runtime. `registry.tls: true` publica el registry local por HTTPS. El chart emite la CA, la conserva entre upgrades y el runtime la utiliza para verificar el certificado.

`registry.public` es un segundo registry, de lectura, para los artefactos OCI públicos (proyectos `agents` y `brains`). Requiere usuario y contraseña. En Harbor, una robot account. Esas credenciales no se incluyen en el repositorio.

La política de firma es `required`. Cada artefacto que el runtime obtiene debe estar firmado con la clave privada correspondiente a `runtime.cosign.publicKey`. Sin esa clave pública, o si el artefacto no tiene firma, la descarga falla. La clave privada no reside en el chart: permanece en el proceso de publicación.

Los proyectos por defecto son `agents` y `brains`. Studio (`EXTERNAL_REGISTRY_*_PROJECT`) y el runtime deben usar los mismos nombres. El chart copia los valores de Studio al runtime.

Ejemplo de firma de un tag, sin publicar la firma en un transparency log público:

```bash
cosign sign --key cosign.key --use-signing-config=false --tlog-upload=false \
  registry.acme.example/brains/<nombre>:latest
```

## Keycloak

El realm, el identificador de client y los secretos pertenecen a la instalación. El client del runtime requiere un service account con permiso de lectura de usuarios del realm. Studio redirige a `https://<studio.host>`.

`KEYCLOAK_CALLBACK_URI` permanece vacío hasta que la instalación defina la URL de callback en `keycloak.runtimeAuth.callbackUri`.

## Zero Trust

`runtime.zeroTrust.enabled: true` activa Keycloak en el runtime, el socket SPIFFE y la verificación de firma OCI. `spire.enabled: true` instala SPIRE en el namespace `spire`.

`tlsEnforce` permanece en `false`. Redis, PostgreSQL, Kafka, MinIO, Vault y Qdrant se comunican sin TLS dentro del cluster. La imagen de runtime actual no admite TLS en Redis: la conexión falla en el primer comando. Kafka solo acepta los certificados mediante `KAFKA_SSL_*_FILE`, no como contenido del certificado en una variable.

## Qdrant

Qdrant es un componente obligatorio. El chart crea el StatefulSet y el Secret `alquimia-qdrant`, con `QDRANT_URL` y la API key. `qdrant.enabled: false` detiene el render de Helm.

## Vault

El unsealer habilita la autenticación Kubernetes, el mount JWT contra el OIDC de SPIRE y el motor KV v2 en `secret/`. `VAULT_MOUNT_POINT` es `secret`. Los datos escritos en `cubbyhole` no son visibles desde ese mount: `cubbyhole` está aislado por token.

## Valores que permanecen desactivados

| Parámetro | Comportamiento |
|---|---|
| `TLS_ENFORCE` | Permanece desactivado. Los backends que instala el chart no terminan TLS |
| OpenTelemetry | `otel.enabled: false` hasta que `otel.endpoint` apunte a un collector |
| Cifrado en reposo (`ENCRYPTION_KEY`, `ALQUIMIA_REGISTRY_KEY`) | Las claves se generan una vez y se conservan fuera del cluster. Si están vacías, el chart no crea el Secret |
| `CHANNEL_NOTIFICATION_SECRET` | Debe coincidir con el secreto con el que firman los conectores de canal |
| `embeddings.yaml` | Requiere el proveedor de embeddings de la instalación |
| NetworkPolicy | El chart no las define. Una política default-deny sin reglas de ingreso interrumpe el Ingress |
| Alta disponibilidad | Kafka, Vault, PostgreSQL, Redis, Qdrant y el registry local se despliegan con una réplica |
