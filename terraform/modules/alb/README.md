# ALB

외부 요청을 BE와 WS ECS service로 전달한다.

- `main.tf`: Application Load Balancer
- `listeners.tf`: HTTP → HTTPS redirect, HTTPS listener, `/ws` 경로 규칙
- `target_groups.tf`: BE/WS target group과 health check

루트에서 network 모듈의 subnet, VPC, security group을 연결한다.
출력 target group은 listener 연결이 끝난 후 ECS에서 사용하도록 의존성을 포함한다.
