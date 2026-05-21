# upgraded-disco

Kubernetes infrastructure for **[mlclogistica.app](https://mlclogistica.app)**.

## Structure

- `k8s/` — manifests applied to the cluster
  - `db.yaml` — Postgres StatefulSet and headless Service
  - `migrations.yaml` — Job that runs database migrations using the `curly-spoon` image
  - `secret.yaml` — dev credentials (not applied in production)

## Workflows

- **Integration** (`integration.yaml`) — runs on every push; spins up a k3s cluster, applies all manifests, waits for the database to be ready, and waits for migrations to complete
- **Deployment** (`deployment.yaml`) — runs on version tags (`v*.*.*`); applies manifests to the production cluster using `KUBECONFIG` from repository secrets, then publishes a GitHub Release

## Usage

### Local

```bash
kubectl apply -f k8s/
kubectl rollout status statefulset/db --timeout=120s
kubectl wait job/migrations --for=condition=complete --timeout=120s
```

### Releases

Deployment is triggered by pushing a signed version tag:

```bash
git tag -m "v1.0.0" v1.0.0
git push origin v1.0.0
```

Signing happens automatically — `tag.gpgsign = true` and `gpg.format = ssh` are set in the repo's git config.

## Scripts

Helper scripts for setting up a development environment on a new machine:

- `scripts/config-helix.sh` — configures the Helix editor for this project's stack

### Prerequisites

Production deployments require a `KUBECONFIG` secret set in the repository settings containing a valid kubeconfig for the target cluster. On a k3s VM, obtain it with:

```bash
sudo cp /etc/rancher/k3s/k3s.yaml ~/.kube/config
sudo chown $USER ~/.kube/config
cat ~/.kube/config
```
