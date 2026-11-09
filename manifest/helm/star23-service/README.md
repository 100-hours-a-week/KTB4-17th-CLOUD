# STAR23 ECS → EKS migration chart

This chart runs one existing container image per Helm release. It does **not** split Spring Boot or FastAPI source code into new services. The starting point mirrors the three running ECS services:

| Release | ECS source | Image | Exposure |
| --- | --- | --- | --- |
| `backend` | `star23-be-service` | `star23/be` | ALB after cutover preparation |
| `websocket` | `star23-ws-service` | **the same `star23/be` image digest** | ALB path `/ws/chat` after validation |
| `ai` | `star23-ai-service` | `star23/ai` | internal ClusterIP only |

The 12 HTTP role examples under `examples/services/` run as separate Helm releases but reuse the unchanged full Spring Boot or FastAPI image within each language. This splits Pod placement and Service destinations, not the application code or its background jobs. Configure role-specific runtime flags and avoid duplicate schedulers/consumers before deploying these examples. Image digests, container ports, and health paths in `examples/` were read from the current ECS task definitions and source. They are examples, not a complete deployable configuration; see the inventory for batch and vLLM roles.

## Before deployment

1. Translate remaining optional ECS environment variables, Secrets Manager/SSM references, Service Connect names, and task-role permissions into EKS ConfigMaps, Kubernetes Secrets or External Secrets, DNS/Services, and Pod Identity. **Do not copy secret values into Git or Helm values.** The BE ConfigMap and Secret overlays are applied to the `user-api` and `auth-api` QA releases and have passed real Pod health checks.
2. Verify that the backend and WebSocket processes may run from the same image with different environment settings, including scheduled jobs and message consumers. A separate Deployment alone does not disable unwanted work.
3. Set `env` and `envFrom` for each release, verify the `/actuator/health` and `/health` probes, and confirm app-to-app URLs and database connectivity.
4. `user-api`, `onboarding-api`, `recommend-api`, and `auth-api` have healthy Pods and active QA Ingresses. `chat-api` and `chat-socket` Ingresses remain disabled while their runtime is off. The existing edge fallback Ingress still matches `api.star23sharp.com`.
5. The public controller path families are mapped in the six BE role overlays and `examples/services/ROUTING.md`. Only enable each remaining Ingress after its Pod and Service are healthy. Keep FastAPI and `/internal/**` internal. `v3.star23sharp.com` uses the existing CloudFront distribution; its origin router sends v3 Host with `api.star23sharp.com` SNI to the ALB. The ALB currently has only an `api.star23sharp.com` certificate, so direct ALB TLS for v3 Host is not supported; CloudFront-to-ALB works with the explicit existing certificate ARN on each QA Ingress.

Example rendering (no AWS changes):

```sh
helm lint ./helm/star23-service -f ./helm/star23-service/examples/backend.values.yaml
helm template backend ./helm/star23-service -n backend -f ./helm/star23-service/examples/backend.values.yaml
```

The chart defaults to one replica, a ClusterIP Service, and no Ingress. As of 2026-11-09, all 12 application role releases run one Ready Pod each on the existing general and CPU nodes; only four BE role Ingresses are enabled. A release should only receive traffic after its runtime configuration is validated. The chart intentionally does not create namespace policies, Secret objects, HPA, CronJobs, GPU Deployments, or Istio resources; those require their own configuration and migration checks.

## ConfigMap (initial Helm draft)

`templates/configmap.yaml` creates one non-secret ConfigMap per Helm release when `configMap.enabled=true`. The Deployment automatically imports it with `envFrom` and restarts on config changes. The BE and WebSocket example values now carry every required non-secret Spring variable from the current v2 ECS SSM parameters, including shared RDS and Kafka endpoints. Redis SecureString stays in the ExternalSecret mapping, not the ConfigMap. AI examples still contain only a few known non-secret settings. Role-specific runtime flags, optional ECS settings, and production routing still need review. Existing workspace Kustomize drafts under `manifests/configmap-prod/` contain a broader inventory with unresolved `TODO__...__` inputs; do not deploy those placeholders. AWS Secrets Manager data is not copied into a ConfigMap. The optional External Secrets Operator templates in `templates/secretstore.yaml`, `templates/secretstore-parameterstore.yaml`, and `templates/externalsecret.yaml` sync selected Secrets Manager and SSM SecureString keys into a Kubernetes Secret and inject it through `envFrom.secretRef`. See `examples/secrets/README.md` for required add-on and Pod Identity role setup. The QA releases reuse the existing v2 production RDS credentials as requested. The existing BE image has unguarded scheduled jobs, and the deployed image does not contain the local uncommitted `AI_PROFILE_TRUST_BASE_URL` change; do not assume one full-image Pod per role is isolated.
