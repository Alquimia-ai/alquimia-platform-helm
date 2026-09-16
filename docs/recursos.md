# Recursos por aplicación

Defaults de `chart/values.yaml`. Consumo = requests → limits del contenedor principal.

| Aplicación | Workload | Service | Almacenamiento | Consumo | SA |
|---|---|---|---|---|---|
| MinIO | Deployment `minio` | `minio-service` :9000 / :9090 | PVC `minio-pvc` 100Gi | 100m / 300Mi → 500m / 1Gi | `default` |
| Kafka | StatefulSet `kafka` + Job `kafka-init-topics` | `kafka` :9092 | PVC `data-kafka-0` 100Gi | 250m / 512Mi → 1 / 1Gi | `default` |
| PostgreSQL | StatefulSet `postgresql` | `postgresql` :5432 | PVC `postgresql-data` 200Gi | 500m / 1Gi → 2 / 2Gi | `default` |
| Redis | StatefulSet `redis` | `redis` :6379 | PVC `redis-data-redis-0` 25Gi | 100m / 256Mi → 1 / 1Gi | `default` |
| ORAS registry | StatefulSet `oras-registry` | `oras-registry` :5000 | PVC `registry-data-oras-registry-0` 10Gi | 100m / 128Mi → 1 / 512Mi | `default` |
| Vault | StatefulSet `vault` | `vault` :8200 / :8201 | PVC `data-vault-0` 10Gi | 50m / 128Mi → 1 / 512Mi | `default` |
| Vault unsealer | Deployment `vault-unsealer` | — | — | 10m / 32Mi → 200m / 64Mi | `vault-unsealer` |
| Runtime master | Deployment `alquimia-runtime-master` | `alquimia-runtime-master` :8080 | PVC `alquimia-registry-s3` 10Gi | 500m / 1Gi → 1 / 2Gi | `default` |
| Runtime workers | Deployment `alquimia-runtime-worker` ×3 | — | emptyDir | 500m / 1Gi → 1 / 2Gi (×3) | `default` |
| Studio | Deployment `alquimia-studio` | `alquimia-studio` :3000 + Route | PVC `alquimia-studio-data` 5Gi | 250m / 512Mi → 750m / 1Gi | `default` |
