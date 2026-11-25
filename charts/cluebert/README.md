# Cluebert Helm chart

Deploys Cluebert to the existing Kubernetes cluster: one pod, a ClusterIP
Service, a Traefik Ingress with a cert-manager Certificate, and a Job that
migrates the database on every install and upgrade.

**Always exactly one pod.** Games live only in the pod's memory (ADR 4), so
there is no `replicaCount` and no autoscaling, and the Deployment uses the
`Recreate` strategy. **Every upgrade ends the games in progress**, so
upgrade between game sessions. Boards are in Postgres and are kept.

## Before the first install

1. **An image.** The *Build image* workflow pushes
   `ghcr.io/ciroque/cluebert` when a PR is merged into main, or when run
   by hand. Its run summary shows the digest to deploy.
2. **A database.** Create an empty `cluebert` database (or the name you
   pass as `app.database.name`) on the cluster's Postgres. The migrate Job
   creates the tables but not the database:

   ```bash
   psql -h "$DB_HOST" -U "$DB_USERNAME" -c 'create database cluebert'
   ```

3. **A pull secret**, if the ghcr package is private: a
   `docker-registry` Secret named `ghcr-package-read` in the release's
   namespace (`imagePullSecrets` in `values.yaml`), as the sibling apps
   use.
4. **DNS** for the host name, pointing at the cluster's Traefik.

## Install or upgrade

```bash
source ~/.config/devenvs/prod-cluster-db.env
source ~/.config/devenvs/secret-key-bases.env

export DIGEST=<digest from the Build image run>

helm upgrade --install cluebert ./charts/cluebert \
  --set host=cluebert.example.com \
  --set image.digest="$DIGEST" \
  --set app.secretKeyBase="$CLUEBERT_SECRET_KEY_BASE" \
  --set app.database.hostname="$DB_HOST" \
  --set app.database.username="$DB_USERNAME" \
  --set app.database.password="$DB_PASSWORD" \
  --timeout 12m \
  -n cluebert \
  --create-namespace
```

Generate a secret key base once with `mix phx.gen.secret` and keep it with
the others (`CLUEBERT_SECRET_KEY_BASE` above is a suggested name). Changing
it later only drops open sessions and LiveView connections; there are no
accounts (ADR 10).

On a first install the migrate Job also imports `priv/boards/*.json` (the
Sampler board). Upgrades only migrate, so boards edited in the app are left
alone. Set `migrate.seedOnInstall=false` to skip it. `--timeout` must be
longer than the Job's 600s deadline.

## Status

```bash
kubectl -n cluebert rollout status deployment/cluebert
kubectl -n cluebert logs -l app.kubernetes.io/name=cluebert
kubectl -n cluebert get jobs,pods
```

## Running a release task by hand

```bash
kubectl -n cluebert exec deploy/cluebert -- /app/bin/cluebert eval "Cluebert.Release.migrate()"
kubectl -n cluebert exec deploy/cluebert -- /app/bin/cluebert eval "Cluebert.Release.seed()"
```

`seed` replaces the Sampler board, undoing edits made to it in the app.
Load other boards at `/boards/import` (ADR 9).

## Uninstall

```bash
helm uninstall cluebert -n cluebert
```

The database is not touched.

## Values

| Value | Description | Default |
| --- | --- | --- |
| `host` | Public host name: ingress rule, certificate and `PHX_HOST`. **Required** | `""` |
| `image.repository` | Image repository | `ghcr.io/ciroque/cluebert` |
| `image.digest` | Image digest (`sha256:...`). **Required** | `""` |
| `image.pullPolicy` | Image pull policy | `IfNotPresent` |
| `imagePullSecrets` | Pull secrets for a private package | `[{name: ghcr-package-read}]` |
| `ingress.enabled` | Create the Ingress (and Certificate) | `true` |
| `ingress.className` | Ingress class | `traefik` |
| `ingress.annotations` | Ingress annotations | Traefik `web,websecure` entrypoints |
| `ingress.tlsSecretName` | Secret the certificate is stored in | `cluebert-tls` |
| `certificate.enabled` | Create a cert-manager Certificate | `true` |
| `certificate.issuerName` | Issuer name | `letsencrypt-dns` |
| `certificate.issuerKind` | Issuer kind | `ClusterIssuer` |
| `app.secretKeyBase` | Phoenix secret key base. **Required** | `""` |
| `app.database.hostname` | Postgres host. **Required** | `""` |
| `app.database.port` | Postgres port | `5432` |
| `app.database.name` | Database name | `cluebert` |
| `app.database.username` | Database user. **Required** | `""` |
| `app.database.password` | Database password. **Required** | `""` |
| `app.poolSize` | Database connection pool size | `10` |
| `migrate.enabled` | Run the migrate Job on install and upgrade | `true` |
| `migrate.seedOnInstall` | Also seed the boards on a first install | `true` |
| `migrate.backoffLimit` | Retries after the migrate container fails | `1` |
| `migrate.activeDeadlineSeconds` | Kill the migrate Job after this many seconds | `600` |
| `service.type` / `service.port` | Service type and port | `ClusterIP` / `80` |
| `resources` | Pod resources | 100m–500m CPU, 256–512Mi memory |
| `podSecurityContext`, `securityContext` | Non-root uid 1000, no privilege escalation, no capabilities | |
| `nodeSelector`, `tolerations`, `affinity`, `podAnnotations` | Scheduling and annotations | empty |
