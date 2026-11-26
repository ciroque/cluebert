# 11. Deployed with Helm to the existing cluster, as exactly one pod

Date: 2026-11-25

## Status

Accepted. Implemented in `charts/cluebert`, `Dockerfile` and
`.github/workflows/build-image.yml` (step 9 of the build plan).

## Context

Cluebert needs to run somewhere other than a laptop. There is already a
Kubernetes cluster with Traefik, cert-manager and a Postgres server, and two
Phoenix apps deployed to it from Helm charts in their own repos
(`exertrax_fitness_ng` and `my_temple_journal`), with images on ghcr.

Games live only in the memory of one BEAM node (ADR 4), are addressed
through a local `Registry`, and are kept in sync over a local `PubSub`.
Kubernetes' defaults assume the opposite: several interchangeable
replicas, and rolling updates that run old and new pods side by side.

## Decision

**Deploy the way the sibling apps do.** A multi-stage Alpine `Dockerfile`
builds a release. A GitHub workflow pushes it to `ghcr.io/ciroque/cluebert`
when a PR is merged into main. A Helm chart in `charts/cluebert` deploys
it by image digest, with a Traefik Ingress, a cert-manager Certificate, a
Secret for credentials passed with `--set`, and a Job that migrates the
database before each upgrade (and after the first install).

**Exactly one pod, always.** The chart has no `replicaCount` and no
autoscaler. The Deployment runs one replica with the `Recreate` strategy,
so the old pod is gone before the new one starts. With two pods, a game
would exist on only one of them, and a host screen and player screen could
connect to different pods.

**Probes don't depend on the database.** Liveness and readiness use
`/health`, which never queries Postgres. A database outage should not
restart the pod and end every game in it.

**The app doesn't connect as `postgres`.** `charts/cluebert/sql/create_roles.sql`,
run once by an admin, creates the database and a `clueberth_rw` role that
owns it, which the app and the migrate Job use, plus a read-only
`clueberth_r` role for people and tools. Roles are server-wide and need a
superuser to create, so this is not an Ecto migration.

**Seed once.** A first install imports the boards in `priv/boards/`.
Upgrades only migrate, so boards edited in the app are not overwritten.

## Consequences

- Every upgrade ends the games in progress. Deploy between game sessions.
  Boards are in Postgres and survive.
- There is a short outage on every upgrade while the new pod starts.
- The app can't scale beyond one node. That is fine for one room per game
  and a handful of games at once. Running more pods would need games to be
  found across nodes (for example clustering with `dns_cluster`, which is
  already a dependency, plus a distributed registry), or ADR 4 to change.
- The app is reachable through the ingress with no access control (ADR 10).
- Image signing and scanning, which the sibling apps do with cosign and
  Trivy, are not set up yet; they need a cosign key in the repo's secrets.
