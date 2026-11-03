# ALB

외부 요청을 BE와 WS ECS service로 전달한다.

- `main.tf`: Application Load Balancer
- `listeners.tf`: HTTP → HTTPS redirect, HTTPS listener, 우선순위 1 `chat_routes` 규칙
- `target_groups.tf`: BE/WS target group과 health check

루트에서 network 모듈의 subnet, VPC, security group을 연결한다.
출력 target group은 listener 연결이 끝난 후 ECS에서 사용하도록 의존성을 포함한다.

운영 idle timeout은 120초다. `chat_routes`는 `/api/v1/chat-rooms`,
`/api/v1/chat-rooms/*`, `/internal/v1/ai-practice/**`, `/ws/chat`을 기존 WS
대상 그룹으로 전달한다. `/ws`, `/ws/*` 규칙이나 별도 AI practice 규칙을
재생성하지 않는다. 루트 `reconcile_alb.tf`는 과거 두 주소를 `destroy=false`로
해제하고 실제 규칙 ID를 새 주소로 import하는 **미실행 제안**이다.
