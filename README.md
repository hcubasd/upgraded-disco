# upgraded-disco

Kubernetes infrastructure for the **[mlclogistica.app](https://mlclogistica.app)** dashboard project.

## Structure

```
k8s/
├── gateway.yaml                 — Traefik Gateway (HTTP, two listeners: dashboard + api subdomains)
├── traefik-gateway-config.yaml  — HelmChartConfig enabling Gateway API support in k3s's bundled Traefik
├── db.yaml                      — Postgres 18 StatefulSet + headless Service (2 Gi PVC)
├── migrations.yaml              — Job that runs schema migrations (curly-spoon image, golang-migrate)
├── crm_worker.yaml              — CronJob that syncs deals from the CRM every minute (improved-doodle image)
├── secret.yaml                  — dev credentials placeholder (never applied in production)
├── frontend/
│   ├── deployment.yaml   — Deployment + Service for the React dashboard (bookish-lamp image)
│   ├── http-route.yaml   — HTTPRoute: dashboard.mlclogistica.app → oauth2-proxy-frontend
│   └── oauth2-proxy.yaml — OAuth2 Proxy deployment protecting the frontend
└── api/
    ├── deployment.yaml   — Deployment + Service for the Go deals API (glowing-umbrella image)
    ├── http-route.yaml   — HTTPRoute: dashboard-api.mlclogistica.app → oauth2-proxy-api
    └── oauth2-proxy.yaml — OAuth2 Proxy deployment protecting the API
```

## Services

| Service | Image | URL |
|---|---|---|
| Frontend | `ghcr.io/hcubasd/bookish-lamp` | `dashboard.mlclogistica.app` |
| API | `hcdouat/glowing-umbrella` | `dashboard-api.mlclogistica.app` |
| CRM Worker | `hcdouat/improved-doodle` | — (CronJob, every minute) |
| Migrations | `ghcr.io/hcubasd/curly-spoon` | — (Job, runs on deploy) |
| Database | `postgres:18` | `db:5432` (cluster-internal) |

Both the frontend and API are protected by [OAuth2 Proxy](https://oauth2-proxy.github.io/oauth2-proxy/) using Microsoft Entra ID. Only `@mlclogistica.com.br` accounts are allowed through.

## Workflows

**Integration** (`integration.yaml`) — runs on every branch push. Spins up a local k3s cluster, installs Gateway API CRDs and Traefik RBAC, applies all manifests recursively, and verifies the cluster accepts them.

**Deployment** (`deployment.yaml`) — runs on version tags (`v*.*.*`). Removes `secret.yaml`, applies all manifests to the production cluster via `KUBECONFIG` secret, then publishes a GitHub Release with auto-generated notes.

## Secret

`secret.yaml` is a placeholder for local development only — it is deleted before production apply. The following keys must exist in the cluster `secret` object:

| Key | Description |
|---|---|
| `POSTGRES_PASSWORD` | Postgres password |
| `CRM_CLIENT_ID` | CRM OAuth2 client ID |
| `CRM_CLIENT_SECRET` | CRM OAuth2 client secret |
| `OAUTH2_PROXY_CLIENT_ID` | Entra ID Application (client) ID |
| `OAUTH2_PROXY_CLIENT_SECRET` | Entra ID client secret value |
| `OAUTH2_PROXY_COOKIE_SECRET` | Random 32-byte key — `openssl rand -base64 32` |

To read existing secret values from the cluster:

```bash
kubectl get secret secret -o go-template='{{range $k,$v := .data}}{{$k}}: {{$v | base64decode}}{{"\n"}}{{end}}'
```

## Releases

Deployment is triggered by pushing an annotated version tag:

```bash
git tag -m "v1.0.0" v1.0.0
git push origin v1.0.0
```

Signing is configured automatically — `tag.gpgsign = true` and `gpg.format = ssh` are set in the repo's git config.

## Local apply

```bash
kubectl apply -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.5.1/standard-install.yaml
kubectl apply -f https://raw.githubusercontent.com/traefik/traefik/v3.7/docs/content/reference/dynamic-configuration/kubernetes-gateway-rbac.yml
kubectl apply -Rf k8s/
```

To get the kubeconfig from a k3s node:

```bash
sudo cp /etc/rancher/k3s/k3s.yaml ~/.kube/config
sudo chown $USER ~/.kube/config
```
