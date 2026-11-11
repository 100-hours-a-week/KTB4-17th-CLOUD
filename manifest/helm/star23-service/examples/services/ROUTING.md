# Public routing decisions and QA deployment status

All BE roles run the full Spring image. All AI roles, including `image-worker`, run the full FastAPI image. These entries record the agreed destination. `user-api`, `onboarding-api`, `recommend-api`, `auth-api`, `chat-api`, and `chat-socket` have enabled QA Ingresses.

| Incoming path or caller | Destination | Evidence or implementation note |
| --- | --- | --- |
| `GET /api/v1/chat-rooms` | `chat-socket` | Chat room list controller; `APP_CHAT_RUNTIME_ENABLED=true` on this release. |
| `GET/POST /api/v1/chat-rooms/{chatRoomId}/messages` | `chat-socket` | Both read/send controllers are in the full Spring image. |
| `POST /api/v1/chat-rooms/{chatRoomId}/read` | `chat-socket` | Marks messages as read and updates the unread count. |
| `POST /api/v1/chat-rooms/{chatRoomId}/leave` | `chat-socket` | Leaves/ends a chat room, including after delegation. |
| `GET/POST /api/v1/chat-rooms/{chatRoomId}/delegations` and subpaths | `chat-socket` | AI chat-end draft, confirmation, progress, and retry; BE calls `chat-ai-cleanup` internally. |
| `GET /api/v1/chat-rooms/{chatRoomId}/images/{fileId}/access-url` | `chat-socket` | Authorizes access to an image message and returns a temporary URL. |
| `/ws/chat` | `chat-socket` | WebSocket endpoint. |
| `/api/v1/ai-practice/**` | `chat-api` | Spring practice HTTP API; its outbox publisher runs on `chat-socket` and calls `chat-ai-practice`. |
| `/api/v1/ai-simulations/**` | `chat-api` | Spring simulation HTTP API; calls `chat-ai-simulation` internally. |
| `GET/PUT /api/v1/users/me/profile` | `onboarding-api` | Both controllers exist in every full Spring image. |
| `/api/v1/notifications` and subpaths | `user-api` | Includes `/stream`; enable delivery consumer on every `user-api` Pod before routing SSE here. |
| BE `AI_KAKAO_BASE_URL` + `/ai/api/v2/persona-extraction/conversation` | `onboarding-persona-ai.user.svc.cluster.local:8000` | Reflected in `onboarding-api.values.yaml`. |
| BE `AI_PERSONA_BASE_URL` + `/ai/api/v1/persona/...` | `onboarding-persona-ai.user.svc.cluster.local:8000` | Reflected in `onboarding-api.values.yaml`. |
| BE chat-delegation `AI_CHAT_DELEGATION_BASE_URL` + `/ai/api/v1/chat_end/...` | `chat-ai-cleanup.chat.svc.cluster.local:8000` | Configured on the `chat-socket` release overlay. |
| BE `AI_PRACTICE_BASE_URL` + `/ai/api/v2/practice/...` | `chat-ai-practice.chat.svc.cluster.local:8000` for other BE roles; `image-worker.user.svc.cluster.local:8000` for `onboarding-api` | The current image shares this base URL with profile-trust. Both targets run the full FastAPI image. |
| BE `AI_SIMULATION_BASE_URL` + `/ai/api/v2/simulation` | `chat-ai-simulation.chat.svc.cluster.local:8000` | Set in `backend.values.yaml`; full FastAPI image. |
| BE `/ai/api/v1/profile-trust/photos/primary/frontal-check` and `synthetic-check` | Helm target: `image-worker.user.svc.cluster.local:8000` from `onboarding-api` | The deployed BE image reads `AI_PRACTICE_BASE_URL`. The overlay now overrides it, but the live release requires a Helm upgrade. |
| BE `/ai/api/v1/profile-trust/verifications/challenges` and `complete` | Helm target: `image-worker.user.svc.cluster.local:8000` from `onboarding-api` | Uses the same role-specific override after a Helm upgrade. |

## Public controller path families in Helm

| Role | Public paths | Current EKS state |
| --- | --- | --- |
| `user-api` | `/api/v1/notifications/**`, `/api/v1/users/me/blocks/**`, exact `/api/v1/users/me`, `/api/v1/users/{userId}/profile`, `/api/v1/registration/**`, `/api/v1/files/**` | 1 Ready Pod; Ingress enabled |
| `onboarding-api` | exact `/api/v1/users/me/profile`, profile images, onboarding, face verifications, primary photo check, persona, nicknames, activity regions | 1 Ready Pod; all listed Ingress paths enabled |
| `chat-api` | prefix `/api/v1/ai-practice`, prefix `/api/v1/ai-simulations` | 1 Ready Pod; AI HTTP Ingress enabled; chat runtime disabled |
| `chat-socket` | prefix `/api/v1/chat-rooms`, exact `/ws/chat` | 1 Ready Pod; chat REST and WebSocket Ingress enabled; chat runtime enabled |
| `recommend-api` | likes, recommendation batches, passes, preferences, exact `/api/v1/popular-profiles` | 1 Ready Pod; Ingress enabled |
| `auth-api` | `/api/v1/auth/**` | 1 Ready Pod; Ingress enabled |

`/internal/**` and the uncommitted `/api/v1/internal/staging/**` controller are not exposed. The broad `/api/v1/files/**` route follows the more specific onboarding primary-photo-check route because both Ingresses use order 1 and `user/onboarding-api` sorts before `user/user-api`; AWS listener priorities were checked after enabling onboarding.

## Remaining routes and checks

- The chart accepts multiple `ingress.paths` per release. Six public BE roles have Ingress on the v3 QA ALB. `chat-socket` routes all `/api/v1/chat-rooms` REST subpaths with `Prefix` and `/ws/chat` with `Exact`; `chat-api` routes the AI practice and simulation HTTP path families. The v3 chat runtime joins the same Kafka group as v2 WS and uses the same WS Redis endpoint; monitor shared outbox and delegation jobs during QA. The practice outbox publisher on `chat-socket` has `AI_PRACTICE_BASE_URL` configured.
- The existing fallback rule currently matches `api.star23sharp.com`, while v3 application Ingresses match `v3.star23sharp.com`. `user-api` has the v3-specific SSE consumer group and existing production delivery topic; creation and outbox relay remain disabled on that release. The QA chat override disables chat runtime in `chat-api`; `chat-socket` explicitly enables it and shares the v2 Kafka relay consumer group. Unguarded scheduled jobs still run in each full BE copy.
- The FE calls `GET /api/v1/popular-profiles`. The local BE checkout does not contain this controller, but the BE image currently running in EKS contains `PopularProfileController` with `@GetMapping` at `/api/v1/popular-profiles`. The exact path is now routed to `recommend-api`; reconcile the local checkout with the deployed image source before future image builds.
- The deployed BE image does not read `AI_PROFILE_TRUST_BASE_URL`; profile-trust follows `AI_PRACTICE_BASE_URL`. The Helm overlay for `onboarding-api` overrides that existing variable to `image-worker`, while other BE roles retain `chat-ai-practice`. This is a chart change until `onboarding-api` is upgraded. Afterward, a practice call originating in `onboarding-api` also reaches `image-worker`, because the image cannot separate the two base URLs. `onboarding-face-certify-ai` has no caller in this routing.
- Notification delivery remains blocked upstream of the v3 SSE route. On 2026-11-09, the shared MySQL DB had 47 `notification_request_outbox` rows in `PENDING` (39 `LIKE`, 8 `MATCH`) and no recently created notifications. The DB session uses UTC, while the BE JDBC URL declares `serverTimezone=Asia/Seoul`; a read-only parameter-binding check showed this URL sends UTC `Timestamp` values nine hours ahead. The relay compares `next_attempt_at` to `UTC_TIMESTAMP(6)`, so none of those rows were due. The v3 `user-api` notification Ingress, list requests, and SSE registration are working. Do not change the DB-wide time zone or release the pending rows until a targeted correction and the user-facing backlog policy are approved.

## Internal AI practice callback recommendation

`POST /internal/v1/ai-practice/events` is a BE callback controller enabled by `APP_CHAT_RUNTIME_ENABLED=true`. If an AI worker starts sending these callbacks, target `http://chat-socket.chat.svc.cluster.local:8080/internal/v1/ai-practice/events` directly through the ClusterIP Service. Keep `/internal/**` out of public ALB Ingress. Set the same nonempty `AI_PRACTICE_CALLBACK_SECRET` in the BE Pod and `X-AI-Callback-Secret` in the AI request, sourced from a Kubernetes Secret. The current AI source does not send this callback, so no callback URL is configured yet.
