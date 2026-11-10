# Public routing decisions and QA deployment status

All BE roles run the full Spring image. All AI roles, including `image-worker`, run the full FastAPI image. These entries record the agreed destination. `user-api`, `onboarding-api`, `recommend-api`, and `auth-api` have enabled QA Ingresses. Chat Ingresses remain disabled because the live chat runtime is disabled.

| Incoming path or caller | Destination | Evidence or implementation note |
| --- | --- | --- |
| `GET /api/v1/chat-rooms` | `chat-api` | Chat room list controller; enable `APP_CHAT_RUNTIME_ENABLED=true` on this release before deployment. |
| `GET/POST /api/v1/chat-rooms/{chatRoomId}/messages` | `chat-socket` | Both read/send controllers are in the full Spring image. |
| `POST /api/v1/chat-rooms/{chatRoomId}/read` | `chat-socket` | Marks messages as read and updates the unread count. |
| `POST /api/v1/chat-rooms/{chatRoomId}/leave` | `chat-socket` | Leaves/ends a chat room, including after delegation. |
| `GET/POST /api/v1/chat-rooms/{chatRoomId}/delegations` and subpaths | `chat-socket` | AI chat-end draft, confirmation, progress, and retry; BE calls `chat-ai-cleanup` internally. |
| `GET /api/v1/chat-rooms/{chatRoomId}/images/{fileId}/access-url` | `chat-socket` | Authorizes access to an image message and returns a temporary URL. |
| `/ws/chat` | `chat-socket` | WebSocket endpoint. |
| `GET/PUT /api/v1/users/me/profile` | `onboarding-api` | Both controllers exist in every full Spring image. |
| `/api/v1/notifications` and subpaths | `user-api` | Includes `/stream`; enable delivery consumer on every `user-api` Pod before routing SSE here. |
| BE `AI_KAKAO_BASE_URL` + `/ai/api/v2/persona-extraction/conversation` | `onboarding-persona-ai.user.svc.cluster.local:8000` | Reflected in `onboarding-api.values.yaml`. |
| BE `AI_PERSONA_BASE_URL` + `/ai/api/v1/persona/...` | `onboarding-persona-ai.user.svc.cluster.local:8000` | Reflected in `onboarding-api.values.yaml`. |
| BE chat-delegation `AI_CHAT_DELEGATION_BASE_URL` + `/ai/api/v1/chat_end/...` | `chat-ai-cleanup.chat.svc.cluster.local:8000` | Configured on the `chat-socket` release overlay. |
| BE `AI_PRACTICE_BASE_URL` + `/ai/api/v2/practice/...` | `chat-ai-practice.chat.svc.cluster.local:8000` | Set in `backend.values.yaml`; full FastAPI image. |
| BE `AI_SIMULATION_BASE_URL` + `/ai/api/v2/simulation` | `chat-ai-simulation.chat.svc.cluster.local:8000` | Set in `backend.values.yaml`; full FastAPI image. |
| BE `/ai/api/v1/profile-trust/photos/primary/frontal-check` and `synthetic-check` | Intended: `image-worker.user.svc.cluster.local:8000` | Current v2 BE image ignores `AI_PROFILE_TRUST_BASE_URL` and uses `AI_PRACTICE_BASE_URL`; this split is not active. |
| BE `/ai/api/v1/profile-trust/verifications/challenges` and `complete` | Intended: `image-worker.user.svc.cluster.local:8000` | Same current-image limitation; keep these routes on the same full AI app until a BE image update. |

## Public controller path families in Helm

| Role | Public paths | Current EKS state |
| --- | --- | --- |
| `user-api` | `/api/v1/notifications/**`, `/api/v1/users/me/blocks/**`, exact `/api/v1/users/me`, `/api/v1/users/{userId}/profile`, `/api/v1/registration/**`, `/api/v1/files/**` | 1 Ready Pod; Ingress enabled |
| `onboarding-api` | exact `/api/v1/users/me/profile`, profile images, onboarding, face verifications, primary photo check, persona, nicknames, activity regions | 1 Ready Pod; all listed Ingress paths enabled |
| `chat-api` | exact `/api/v1/chat-rooms`, `/api/v1/ai-practice/**`, `/api/v1/ai-simulations/**` | 1 Ready Pod; Ingress disabled; QA override keeps chat runtime off |
| `chat-socket` | `/ws/chat` and chat message/read/leave/delegation/image paths | 1 Ready Pod; Ingress disabled; QA override keeps chat runtime off |
| `recommend-api` | likes, recommendation batches, passes, preferences | 1 Ready Pod; Ingress enabled |
| `auth-api` | `/api/v1/auth/**` | 1 Ready Pod; Ingress enabled |

`/internal/**` and the uncommitted `/api/v1/internal/staging/**` controller are not exposed. The broad `/api/v1/files/**` route follows the more specific onboarding primary-photo-check route because both Ingresses use order 1 and `user/onboarding-api` sorts before `user/user-api`; AWS listener priorities were checked after enabling onboarding.

## Remaining routes and checks

- The chart accepts multiple `ingress.paths` per release. Four public BE roles are active on the v3 QA ALB; `chat-api` and `chat-socket` remain disabled until their runtime and Kafka consumer-group isolation are validated. Chat-room IDs use ALB wildcard paths with `pathType: ImplementationSpecific`; the list route uses `Exact` so it does not take nested paths.
- The existing fallback rule currently matches `api.star23sharp.com`, while v3 application Ingresses match `v3.star23sharp.com`. `user-api` has the v3-specific SSE consumer group and existing production delivery topic; creation and outbox relay remain disabled on that release. The QA chat override disables chat runtime in `chat-api` and `chat-socket` because the current BE image hardcodes the v2 Kafka relay consumer group; isolate the group before enabling chat traffic. Unguarded scheduled jobs still run in each full BE copy.
- The FE calls `GET /api/v1/popular-profiles`, but no matching controller exists in the inspected BE source. Ingress alone cannot implement this endpoint; keep it out of the public routing until the API contract is resolved.
- The local BE working tree has `AI_PROFILE_TRUST_BASE_URL` separate from `AI_PRACTICE_BASE_URL`, but the current v2 BE image does not. The example records the future `image-worker` destination; `onboarding-face-certify-ai` has no caller in this routing.
- To use the split, rebuild the BE image from the updated source and deploy that same new image to v2 and v3 as required by the migration plan. Until then, profile-trust calls follow `AI_PRACTICE_BASE_URL`.

## Internal AI practice callback recommendation

`POST /internal/v1/ai-practice/events` is a BE callback controller enabled by `APP_CHAT_RUNTIME_ENABLED=true`. If an AI worker starts sending these callbacks, target `http://chat-socket.chat.svc.cluster.local:8080/internal/v1/ai-practice/events` directly through the ClusterIP Service. Keep `/internal/**` out of public ALB Ingress. Set the same nonempty `AI_PRACTICE_CALLBACK_SECRET` in the BE Pod and `X-AI-Callback-Secret` in the AI request, sourced from a Kubernetes Secret. The current AI source does not send this callback, so no callback URL is configured yet.
