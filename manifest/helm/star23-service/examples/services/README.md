# Kubernetes design inventory and current Service examples

The chart already has `templates/service.yaml`. Each Helm release uses a separate `nameOverride`, so its Service selects only Pods from the same release (`app.kubernetes.io/instance`). These overlays specify service names and ports; they are **not complete deployable values**.

| Base values | Overlays | Container/Service port |
| --- | --- | --- |
| `backend.values.yaml` | `user-api`, `onboarding-api`, `chat-api`, `auth-api`, `recommend-api` | 8080 |
| `websocket.values.yaml` | `chat-socket` | 8080 |
| `ai.values.yaml` | `onboarding-persona-ai`, `image-worker`, `onboarding-face-certify-ai`, `chat-ai-practice`, `chat-ai-simulation`, `chat-ai-cleanup` | 8000 |

Example render (no deployment):

```sh
helm template user-api ./helm/star23-service -n user \
  -f ./helm/star23-service/examples/backend.values.yaml \
  -f ./helm/star23-service/examples/services/user-api.values.yaml
```

All 12 application roles are installed as one-Pod QA releases. The backend base example defaults to one replica. Each release runs the **whole BE or AI application**. The QA overrides `qa-chat-pod-only.values.yaml`, `qa-general-capacity.values.yaml`, and `qa-c4-ai-cohost.values.yaml` are applied to the relevant live releases; include them on later upgrades or use `--reuse-values`. The chat override disables the chat runtime to avoid joining the v2 Kafka relay consumer group. The general-capacity override reduces the CPU request of `chat-api` and `chat-socket` from 1 CPU to 500m each so the two additional AI roles fit on one general node. The c4 override reduces the image and face AI requests to 750m/1250Mi and limits to 1 CPU/2Gi per Pod, below the design's face-inference request. These values confirm only idle Pod startup and must be load-tested before traffic. `user-api`, `onboarding-api`, `recommend-api`, and `auth-api` have public QA Ingresses. Chat Ingresses remain disabled; AI roles have internal ClusterIP Services only. Namespace `user`, `chat`, `recommend`, and `auth` exist.

## Chapter 3: complete workload inventory

The design lists **14 workloads**, not 14 Kubernetes `Service` objects. This directory currently has example values for 12 HTTP role examples. Each example renders a `Deployment` and a `ClusterIP Service` when installed as a separate release. A Service selects all matching Pods of its release, not one Service per Pod.

| Namespace | Design workload | Planned Kubernetes workload | Kubernetes Service | Current chart example |
| --- | --- | --- | --- | --- |
| user | User API | Deployment | Yes; ALB target | `user-api` |
| user | Onboarding API | Deployment | Yes; ALB target | `onboarding-api` |
| user | Onboarding Persona AI | Deployment | Yes; internal HTTP | `onboarding-persona-ai` |
| user | Image Worker | Deployment | Yes; internal HTTP for this migration | `image-worker` |
| user | Onboarding Face Certify AI | Deployment | Yes; internal HTTP | `onboarding-face-certify-ai` |
| chat | Chat API | Deployment | Yes; ALB target | `chat-api` |
| chat | Chat Socket | Deployment | Yes; ALB target | `chat-socket` |
| chat | Chat AI Practice | Deployment | Yes; internal HTTP | `chat-ai-practice` |
| chat | Chat AI Simulation | Deployment | Yes; internal HTTP for this migration | `chat-ai-simulation` |
| chat | Chat AI CleanUp | Deployment | Yes; internal HTTP for this migration | `chat-ai-cleanup` |
| recommend | Recommend API | Deployment | Yes; ALB target | `recommend-api` |
| recommend | Recommend Batch | CronJob | No; scheduled Job | Missing; chart has no CronJob template |
| auth | Auth API | Deployment | Yes; ALB target | `auth-api` |
| llm | vLLM Model | Deployment | Yes, if hosted in EKS; internal inference endpoint | Missing; chart has no GPU runtime configuration |

The design's workload name containing “Service” does not itself require a Kubernetes `Service` object. A Service is needed when other Pods or the ALB must connect to a stable endpoint. Chat AI Simulation and CleanUp run on the single general node in this QA deployment; Image Worker and Face Certify share the existing c4.large CPU node. The Spot node group is scaled to zero. These are HTTP endpoints on full application copies, not queue consumers. Actual paths and caller URLs, duplicate scheduled/background tasks, batch schedule, and vLLM deployment location/image/GPU settings still need validation before enabling traffic. These 12 releases represent the non-vLLM, non-CronJob roles; they do not implement queue workers or prove role isolation.

The onboarding API example routes both `AI_PERSONA_BASE_URL` and `AI_KAKAO_BASE_URL` to `onboarding-persona-ai.user.svc.cluster.local:8000`; BE appends the existing `/ai/api/...` paths.
