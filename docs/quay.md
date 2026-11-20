# Quay

El chart no instala Quay. Con `registry.mode: remote` el runtime publica y lee en un Quay que ya existe, y deja de desplegar el registry local (`oras-registry`). La integración se contrastó con Quay 3.18.

El hostname de esta guía es de referencia. Sustituir `registry.acme.example` por el del entorno. El token del robot no forma parte del repositorio.

## Qué tiene que existir en Quay

Dos organizaciones, con los mismos nombres que usa el chart:

| Organización | Parámetro | Variable del runtime |
|---|---|---|
| `agents` | `studio.config.EXTERNAL_REGISTRY_AGENTS_PROJECT` | `ALQUIMIA_OCI_NAMESPACE_AGENTSPACES` |
| `brains` | `studio.config.EXTERNAL_REGISTRY_BRAINS_PROJECT` | `ALQUIMIA_OCI_NAMESPACE_BRAINS` |

El chart copia esos dos valores de Studio al ConfigMap `alquimia-config`. Si se renombran, hay que cambiarlos en Studio: el runtime no tiene un parámetro propio.

Cada publish escribe el artefacto en su repositorio (`agents/probe`) y, con el índice activo, una entrada en el ancla del namespace (`agents/index` o `brains/index`). Esas anclas las crea el runtime. No son artefactos de usuario. Studio lista el catálogo leyendo el ancla, no con `/v2/_catalog`.

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

`registry.host` queda en `ALQUIMIA_OCI_REGISTRY_DEFAULT`. `studio.config.EXTERNAL_REGISTRY_URL` y `registry.public.host` llevan el mismo hostname: es el que Studio muestra al usuario.

`registry.host` va sin esquema y sin ruta. `https://registry.acme.example` no es un host válido para el chart.

Con HTTPS, `plainHttp` e `insecure` quedan en `false`. El chart no emite una CA para un registry remoto: Quay presenta su propio certificado y el runtime lo verifica.

## Robot account

El runtime autentica con una robot account. El usuario de Quay tiene la forma `<organización>+<nombre>`, por ejemplo `agents+runtime`. La contraseña es el token del robot.

Un robot nace en una organización. Para publicar también en la otra, se agrega ese mismo robot a un team de la segunda. El chart guarda una sola credencial por hostname: un segundo robot contra el mismo Quay no entra en el Secret.

Permisos mínimos en cada organización:

| Dónde | Rol | Para qué alcanza |
|---|---|---|
| Team de la organización | `creator` | Crear repositorios. Quay deja al robot como admin de los que él crea, incluidas las anclas `agents/index` y `brains/index` |
| Repositorio que ya existía y creó otro usuario | `write` | Push y pull de ese repositorio. `creator` no abre los repos privados ajenos |

`owner` de la organización no hace falta.

## Credencial en el chart

El Secret se llama `alquimia-registry-config`, tipo `kubernetes.io/dockerconfigjson`. El master y los workers montan la clave `.dockerconfigjson` en `/var/docker-config/config.json` y definen `DOCKER_CONFIG=/var/docker-config`. ORAS lee ese archivo.

### `secrets.backend: helm`

```yaml
registry:
  dockerconfig:
    username: agents+runtime
    password: token-del-robot
```

Ese usuario y esa contraseña son los que quedan para `registry.host`. Si `registry.public.host` es otro hostname y trae usuario y contraseña, el chart agrega una segunda entrada. Si es el mismo hostname, permanece la de `registry.dockerconfig`.

Sin usuario o sin contraseña en `registry.dockerconfig`, el chart crea el Secret con `{"auths":{}}`. ORAS llama a Quay sin credencial.

### `secrets.backend: sealed`

El chart no arma este Secret desde `registry.dockerconfig`. Hay que dejar el JSON en `chart/secrets/local/alquimia-registry-config/.dockerconfigjson` y sellarlo con `chart/scripts/seal-secrets.sh`. La clave del host es el mismo valor que `registry.host`:

```json
{
  "auths": {
    "registry.acme.example": {
      "username": "agents+runtime",
      "password": "token-del-robot"
    }
  }
}
```

`chart/secrets/local/` no se commitea. Si ese SealedSecret no está y tampoco hay usuario y contraseña de helm, el chart igual crea `alquimia-registry-config` vacío.

## Índice

`runtime.config.ALQUIMIA_OCI_INDEX_ENABLED` sale en `true`. Después de un push correcto, el runtime adjunta la entrada al ancla del namespace. Con `false` el artefacto queda en su repositorio y el catálogo no lo muestra.

`ALQUIMIA_OCI_REFERRERS_FALLBACK` sale en `error`. El attach exige la API nativa de referrers de OCI 1.1 (`GET /v2/<namespace>/index/referrers/<digest>`). Quay 3.18 la expone. Si esa sonda falla, el artefacto sigue publicado y la entrada del índice no: el runtime lo deja en el log y no reescribe el tag mutable de ORAS. `warn` hace ese attach igual y puede perder entradas cuando dos publish corren a la vez.

## Quay en HTTP

Solo cuando el Ingress de Quay no termina TLS:

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

La imagen ignora `ORAS_PLAIN_HTTP` si `ALQUIMIA_OCI_DEV_MODE` no es `true`. Con `plainHttp: true` el chart deja pasar el valor de `runtime.config.ALQUIMIA_OCI_DEV_MODE`; el default de ese valor es `false`, así que hay que ponerlo en `true`. Con HTTPS el chart fuerza `ALQUIMIA_OCI_DEV_MODE=false`.

`insecure: true` salta la verificación TLS. No sustituye a `plainHttp`.

## Qué revisar si no aparece nada en Quay

El push del artefacto y el attach al índice son dos pasos. Un repo `agents/probe` vacío puede existir sin tags: alguien lo creó, o el runtime lo creó, y el push del manifiesto no llegó.

| Síntoma | Causa |
|---|---|
| `HEAD /v2/...` responde 401 y el Secret tiene `{"auths":{}}` | ORAS no tiene usuario. Falta el robot en `alquimia-registry-config`, o el host del JSON no es exactamente `registry.host` |
| 401 con el robot cargado, sobre un repo que creó otro usuario | El team está en `creator` y ese repo no le pertenece. Hace falta rol `write` en el repositorio |
| El tag del artefacto existe y `agents/index` sigue vacío | `ALQUIMIA_OCI_INDEX_ENABLED` está en `false`, o la sonda de referrers falló con `ALQUIMIA_OCI_REFERRERS_FALLBACK=error` |
| `oras discover .../agents/index:v1` responde `not found` | El ancla todavía no se escribió. Es el estado anterior al primer publish con el índice activo |
