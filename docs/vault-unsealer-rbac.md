# vault-unsealer RBAC

When Argo CD is not allowed to create ServiceAccounts, the ServiceAccount is created ahead of time and the chart only references it.

In `chart/values.yaml`:

```yaml
vault:
  autoUnseal: true
  serviceAccount:
    create: false
    name: vault-unsealer
```

With `create: false` the chart skips the ServiceAccount. The Deployment uses `serviceAccountName` with the given name. Argo CD applies the Role and RoleBinding, or they can be applied with the manifest below.

## Apply

Replace `NAMESPACE` with the `namespace` value in `values.yaml`. The default is `alquimia-platform`.

If `vault.keysSecret` changes, update the Role's `resourceNames`.

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

## What it allows

| Resource | Verbs | Reason |
|---|---|---|
| `secrets` | `create` | Create `vault-keys` and `alquimia-vault` during init |
| `secrets` (`vault-keys`, `alquimia-vault`) | `get`, `update`, `patch` | Read the keys, store the root token, and update the unseal keys |

The permission is limited to the installation namespace.
