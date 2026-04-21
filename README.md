# upgraded-disco

Kubernetes infrastructure for the upgraded-disco project.

## Structure

- `k8s/` — manifests applied to the cluster
  - `db.yaml` — Postgres StatefulSet and headless Service
  - `secret.yaml` — dev credentials (not applied in production)

## Workflows

- **Integration** (`integration.yaml`) — runs on every push; spins up a k3s cluster, applies all manifests, and waits for the database to be ready
- **Deployment** (`deployment.yaml`) — runs on version tags (`v*.*.*`); applies manifests to the production cluster using `KUBECONFIG` from repository secrets, then publishes a GitHub Release

## Usage

### Local

```bash
kubectl apply -f k8s/
kubectl rollout status statefulset/db --timeout=120s
```

### Releases

Deployment is triggered by pushing a version tag:

```bash
git tag -s v1.0.0 -m "v1.0.0"
git push origin v1.0.0
```

### Prerequisites

Production deployments require a `KUBECONFIG` secret set in the repository settings containing a valid kubeconfig for the target cluster.
