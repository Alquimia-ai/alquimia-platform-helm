# RBAC de vault-unsealer

Cuando Argo CD no tiene permiso para crear ServiceAccounts, el ServiceAccount se crea de forma previa y el chart solo lo referencia.

En `chart/values.yaml`:

```yaml
vault:
  autoUnseal: true
  serviceAccount:
    create: false
    name: vault-unsealer
```

Con `create: false` el chart omite el ServiceAccount. El Deployment utiliza `serviceAccountName` con el nombre indicado. Role y RoleBinding los aplica Argo CD, o pueden aplicarse con el manifiesto siguiente.

## Aplicación

Sustituir `NAMESPACE` por el valor de `namespace` en `values.yaml`. El valor por defecto es `alquimia-platform`.

Si `vault.keysSecret` cambia, actualizar `resourceNames` del Role.

```bash
oc apply -f - <<'EOF'
apiVersion: v1
kind: ServiceAccount
metadata:
  name: vault-unsealer
  namespace: NAMESPACE
  labels:
    app: vault-unsealer
---
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: vault-unsealer
  namespace: NAMESPACE
  labels:
    app: vault-unsealer
rules:
  - apiGroups: [""]
    resources: ["secrets"]
    verbs: ["create"]
  - apiGroups: [""]
    resources: ["secrets"]
    resourceNames:
      - vault-keys
      - alquimia-vault
    verbs: ["get", "update", "patch"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: vault-unsealer
  namespace: NAMESPACE
  labels:
    app: vault-unsealer
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: Role
  name: vault-unsealer
subjects:
  - kind: ServiceAccount
    name: vault-unsealer
    namespace: NAMESPACE
EOF
```

## Qué permite

| Recurso | Verbos | Motivo |
|---|---|---|
| `secrets` | `create` | Crear `vault-keys` y `alquimia-vault` durante el init |
| `secrets` (`vault-keys`, `alquimia-vault`) | `get`, `update`, `patch` | Leer las claves, persistir el root token y actualizar las unseal keys |

El permiso queda limitado al namespace de la instalación.
