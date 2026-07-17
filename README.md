# upgraded-disco

Kubernetes infrastructure for a small, single-node k3s stack: a public-facing frontend and API sitting behind Traefik's Gateway API and OAuth2 Proxy, a background worker, and Postgres underneath.

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

## Cluster bootstrap

A fresh node needs a few one-time steps before it can accept deploys. None of this re-runs automatically on every deploy — see [Workflows](#workflows) for what actually happens on each push/tag.

1. **Install k3s**, pinning the TLS certificate's Subject Alternative Names to the node's external IP. Without this, `kubectl` from outside the VM — including CI/CD — can't validate the API server's certificate and every remote connection fails:

   ```bash
   curl -sfL https://get.k3s.io | sh -s - --tls-san <EXTERNAL_IP>
   ```

2. **Install the Gateway API CRDs and Traefik's Gateway RBAC.** These teach the cluster what a `Gateway`/`HTTPRoute` object even is, and grant Traefik permission to watch them. Kept as manual, documented steps rather than folded into CD — they pull from external URLs, and a transient fetch failure shouldn't be able to block a production deploy that has nothing to do with them:

   ```bash
   kubectl apply -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.5.1/standard-install.yaml
   kubectl apply -f https://raw.githubusercontent.com/traefik/traefik/v3.7/docs/content/reference/dynamic-configuration/kubernetes-gateway-rbac.yml
   ```

3. **Apply the real secret** (see [Secret](#secret) below). `k8s/secret.yaml` is a dev-only placeholder — it is never what actually gets applied to a real cluster, so this step can't be skipped in favor of just applying `k8s/` wholesale:

   ```bash
   kubectl apply -f <your-real-secret.yaml>
   ```

4. **Push a version tag.** From here, CD takes over — see [Workflows](#workflows) below.

To pull the kubeconfig off the node itself (e.g. for local access, or to populate the `KUBECONFIG` GitHub secret — remember to point its `server:` field at the external IP, not `127.0.0.1`):

```bash
sudo cp /etc/rancher/k3s/k3s.yaml ~/.kube/config
sudo chown $USER ~/.kube/config
```

## Workflows

**Integration** (`integration.yaml`) — runs on every branch push. Spins up a throwaway local k3s cluster, runs the same CRD/RBAC bootstrap steps as above, applies all of `k8s/` including the dev placeholder secret (fine here, since this cluster is disposable), and verifies the cluster accepts every manifest. This only proves the YAML is valid and gets accepted by the API server — it does not wait for pods to become healthy or exercise any real traffic.

**Deployment** (`deployment.yaml`) — runs on version tags (`v*.*.*`), against the real cluster via the `KUBECONFIG` secret. Removes `k8s/secret.yaml` before applying, so the placeholder never touches production (the real secret is expected to already exist from the bootstrap step above), applies everything else in `k8s/`, prunes leftover `Succeeded` and `Failed` pods from the previous deploy, then publishes a GitHub Release with auto-generated notes.

## Secret

`k8s/secret.yaml` is a placeholder for local development only — it is deleted before every production apply and is never the source of real credentials. The following keys must exist in the cluster's `secret` object:

| Key | Description |
|---|---|
| `POSTGRES_PASSWORD` | Postgres password |
| `CRM_CLIENT_ID` | CRM OAuth2 client ID |
| `CRM_CLIENT_SECRET` | CRM OAuth2 client secret |
| `OAUTH2_PROXY_CLIENT_ID` | Entra ID Application (client) ID |
| `OAUTH2_PROXY_CLIENT_SECRET` | Entra ID client secret value |
| `OAUTH2_PROXY_COOKIE_SECRET` | Random 32-byte key — `openssl rand -base64 32` |

To read an existing value (e.g. when migrating to a new cluster):

```bash
kubectl get secret secret -o jsonpath='{.data.KEY_NAME}' | base64 -d
```

**A note on encoding, learned the hard way:** when writing a value into a secret, use `stringData` with the plain value — not `data`, which expects an already-base64-encoded string. Kubernetes does not double-decode. Pasting an already-encoded value (say, copied straight from a `data` field, or from `kubectl get secret -o yaml`) into a `stringData` field, or into `--from-literal`, silently encodes it *again*. The apply succeeds without error and the secret looks fine — every consumer of that credential then fails downstream, in ways that rarely point back at encoding at all.

## Releases

Deployment is triggered by pushing an annotated version tag:

```bash
git tag -m "v1.0.0" v1.0.0
git push origin v1.0.0
```

Signing is configured automatically — `tag.gpgsign = true` and `gpg.format = ssh` are set in the repo's git config.
