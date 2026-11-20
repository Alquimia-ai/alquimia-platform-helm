# vault-unsealer RBAC (SA + Role + RoleBinding)

When Argo CD **cannot create ServiceAccounts**, create the SA out of band (or apply this manifest) and let the chart **only reference it**.

In `chart/values.yaml`:

```yaml
vault:
  autoUnseal: true
  serviceAccount:
    create: false
    name: vault-unsealer
```

With `create: false` the chart does not create the SA. The Deployment uses `serviceAccountName` with the `name` above. Argo still applies the Role and RoleBinding, unless those are also created by hand with the YAML below.

## Apply

Replace `NAMESPACE` with the same value as `namespace` in `values.yaml` (default `alquimia-platform`).

If `vault.keysSecret` changes, also update the Role's `resourceNames`.

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
| `secrets` | `create` | Create `vault-keys` and `alquimia-vault` on the first init |
| `secrets` (`vault-keys`, `alquimia-vault`) | `get`, `update`, `patch` | Read the keys, store the root token, and update the unseal keys |

The unsealer does not need permissions outside this namespace.
