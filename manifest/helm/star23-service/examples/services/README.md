# 이전 역할별 설정 예제와 워크로드 목록

**현재 기본 배포는 [values/README.md](../../values/README.md)의 역할 파일 하나를 사용한다. 이 디렉터리는 이전 설정 조합의 참고 자료이며 새 기본값에 함께 적용하지 않는다.**

The chart already has `templates/service.yaml`. Each Helm release uses a separate `nameOverride`, so its Service selects only Pods from the same release (`app.kubernetes.io/instance`). These overlays specify service names and ports; they are **not complete deployable values**.

| Base values | Overlays | Container/Service port |
| --- | --- | --- |
| `backend.values.yaml` | `user-api`, `onboarding-api`, `chat-api`, `auth-api`, `recommend-api` | 8080 |
| `websocket.values.yaml` | `chat-socket` | 8080 |
| `ai.values.yaml` | `onboarding-persona-ai`, `image-worker`, `onboarding-face-certify-ai`, `chat-ai-practice`, `chat-ai-simulation`, `chat-ai-cleanup` | 8000 |

Example render (no deployment):

```sh
helm template user-api ./manifest/helm/star23-service -n user \
  -f ./manifest/helm/star23-service/values/user-api.yaml
```

현재 AWS 배포값은 `values/<릴리스>.yaml`에 통합했다. Chat CPU 축소, Image·Face AI의 CPU 노드 배치와 리소스 축소, Secret 참조를 이미 포함하므로 QA 오버레이나 `--reuse-values`는 필요하지 않다. 역할별 Pod 1개, BE Ingress 6개와 내부 AI Service를 현재 배포 기준으로 유지한다. Chat API runtime은 비활성화, Chat Socket runtime은 활성화 상태다. 전체 Spring·FastAPI 이미지의 복제이므로 scheduler·consumer의 완전한 역할 격리를 뜻하지 않는다.

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
