# RBAC de vault-unsealer (SA + Role + RoleBinding)

Cuando Argo CD **no puede crear ServiceAccounts**, hay que crear el SA por consola (o aplicar este manifiesto) y dejar que el chart **solo lo referencie**.

En `chart/values.yaml`:

```yaml
vault:
  autoUnseal: true
  serviceAccount:
    create: false
    name: vault-unsealer
```

Con `create: false` el chart no crea el SA. El Deployment usa `serviceAccountName` con el `name` de arriba. Role y RoleBinding los sigue aplicando Argo, salvo que también los creen a mano con el YAML de abajo.

## Aplicar

Reemplazar `NAMESPACE` por el mismo valor que `namespace` en `values.yaml` (por defecto `alquimia-platform`).

Si cambian `vault.keysSecret`, actualizar también `resourceNames` del Role.

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
| `secrets` | `create` | Crear `vault-keys` y `alquimia-vault` en el primer init |
| `secrets` (`vault-keys`, `alquimia-vault`) | `get`, `update`, `patch` | Leer keys, guardar root token y actualizar unseal keys |

El unsealer no necesita permisos fuera de este namespace.
