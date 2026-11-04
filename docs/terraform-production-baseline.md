# 운영 Terraform 소스 기준선 — #11

> 이 문서는 #11 당시의 역사적 증거다. #5의 현재 모듈 구조, private ONE-OFF 제안과
> manifest 기반 검증 방법은 [서비스 모듈 문서](terraform-service-modules.md)를 따른다.
> 아래 tracked migration 파일 설명과 예전 무제한 import/forget 검사 방법은 현재 실행 지침이 아니다.

2026-11-03, `main`의 `392dadb`를 기준으로 실제 AWS 운영 구성과 소스를
대조했다. V1 EC2는 dev, V2 ECS는 prod다. 환경 디렉터리 재구성(#5), staging
복원, EIP 정리(#12)는 포함하지 않는다. 원본 미커밋 저장소는 읽기만 했고,
그곳의 오래된 MySQL 전용 모듈 대신 최신 main의 MySQL·PostgreSQL을 유지했다.

## 관리 범위와 소유권

| 루트 / 기존 S3 key | 관리 범위 | 확인한 serial |
| --- | --- | --- |
| `terraform/prod` / `prod/terraform.tfstate` | 운영 network, ALB, 두 RDS, ECS, 기존 공유 storage/CDN의 import 제안 | 29 |
| `terraform/prod/cloudwatch-loki` / `prod/cloudwatch-loki/terraform.tfstate` | 기존 Lambda, IAM, 전용 SG·Loki ingress, 로그 구독 | 4 |

두 백엔드의 버킷은 기존 `star23-tfstate-975779326240`이다. Loki는 상위 루트에
추가하지 않았다. 원본 ECS 로그 그룹은 ECS 모듈 소유이며, Loki 루트는 data로
조회하고 구독만 관리한다. 기존 Loki EC2·SG의 다른 규칙은 소유하지 않는다.
관련 모니터링 소스 전체나 배포 산출물은 가져오지 않았다.

운영 MySQL `star23-v2-prod-mysql` (`db-X2EDA56PDOYXTSMH2RGQZ6J7YU`)과
PostgreSQL `star23-v2-prod-postgres` (`db-AHSDB5A3WKWXTJWQZJCJBZIMN4`)은
동일 주소·ID를 유지하며 최종 plan에서 각각 `no-op`이다. DB 모듈과 기존
`moved_network.tf`, `moved_application.tf`, `imports.tf`는 변경하지 않았다.

ALB는 기존 HTTP→HTTPS redirect, HTTPS 기본 BE 대상 그룹, WS 대상 그룹을
유지한다. timeout은 120초다. 실제 우선순위 1 규칙은
`/api/v1/chat-rooms`, `/api/v1/chat-rooms/*`, `/internal/v1/ai-practice/**`,
`/ws/chat`을 기존 WS 대상 그룹으로 전달한다. 과거 `/ws`·`/ws/*` 규칙이나
별도 AI practice 규칙을 재생성하지 않는다. DB SG의 현재 Name 태그와 기존
다른 SG 규칙을 유지하고, WS→AI TCP 8000은 기존 규칙을 참조한다.

CloudFront `E3LYSMQO2T1UT`는 공유 리소스다. aliases
`star23sharp.com`, `dev.star23sharp.com`, `api.star23sharp.com`,
`grafana.star23sharp.com`, `stag.star23sharp.com`을 모두 유지한다.
origin은 운영 ALB, S3 REST, S3 website, 기존 `api.byul23.shop`의 4개다.
기본 S3 behavior와 `/api/*`, `/ws/*`, `/api`, `/ws`의 순서·메서드·캐시 및
origin request policy·TLS/timeout·현재 인증서·WAF·OAC 연결을 유지한다.
API 두 경로의 `star23-stag-api-origin-router`, 기본 경로의
`star23-spa-routing` Function은 외부 소유 리소스로 연결만 보존한다.
Function 이름의 `stag`나 공유 alias는 staging ECS 복원을 뜻하지 않는다.

ECS 서비스의 실제 배포 리비전은 기존 CI/CD 소유권과
`ignore_changes = [task_definition]`을 유지한다. Terraform이 추적하는
bootstrap 태스크 정의를 CI 최신 리비전으로 교체하지 않았다. AI 서비스의
현재 circuit breaker 설정과 기존 IAM 정책을 복원했다. CI AI 리비전이
추가로 사용하는 기존 Secrets Manager 권한은
`ai_additional_execution_secret_arns`로 보존하며, bootstrap 태스크의
시크릿 목록을 변경해 새 태스크 정의를 만들지 않는다. WS 정의에는 현재
hostPort와 빈 컨테이너 목록 표현을 복원했다.

## 미실행 import / 주소 정합성 제안

2026-11-03 S3의 원격 state 5개를 다시 조회했다. 다음 7개 대상은 managed
리소스로 등록되어 있지 않았다. data 참조는 managed 소유권으로 세지 않았다.
staging state는 소유권 확인을 위해 읽었으며 변경하지 않았다.

| 대상 주소 | 기존 AWS 대상 |
| --- | --- |
| `module.cdn.aws_cloudfront_distribution.fe` | `E3LYSMQO2T1UT` |
| `module.storage.aws_ecr_repository.be` | `star23/be` |
| `module.storage.aws_ecr_repository.ai` | `star23/ai` |
| `module.storage.aws_s3_bucket.fe` | 기존 FE 배포 버킷 |
| `module.storage.aws_s3_bucket.image` | `star23-images` |
| `module.network.aws_vpc_security_group_ingress_rule.ai_from_ws` | `sgr-0030fb498843e37b8` |
| `module.alb.aws_lb_listener_rule.chat_routes` | 실제 priority-1 규칙 ID suffix `a1bcba60b2a96fb8` |

기존 ALB state의 `ws` (`f8cd5cf50f103400`)와 `ws_ai_practice`
(`0abaf0678dd25457`)는 현재 live 규칙 ID와 다르다. 새 live 규칙에는 새 주소를
사용하고, 이전 두 주소는 `removed { lifecycle { destroy = false } }`로
해제하는 제안을 남겼다. 과거 root→module moved 이력은 보존한다.

이 PR은 선언만 제출한다. 향후 별도 승인된 state 정합성 작업에서 최신 소유권과
전체 plan을 다시 확인하고 선언적 import/forget을 함께 검토해야 한다. 이
작업에서는 imperative import, state mv/rm, apply를 실행하지 않았다.

## 검증 결과

Terraform 1.16.4, AWS provider 6.71.0으로 두 루트를 검증했으며 provider 선택을
각 루트의 lock 파일에 기록했다. 읽기 전용 AWS identity는 계정
`975779326240`, IAM user `noel`, 리전 `ap-northeast-2`로 확인했다.

| 전체 refresh plan | AWS create | update | delete | replace | import 제안 | forget 제안 |
| --- | --- | --- | --- | --- | --- | --- |
| 운영 루트 | 0 | 0 | 0 | 0 | 7 | 2 |
| CloudWatch→Loki 루트 | 0 | 0 | 0 | 0 | 0 | 0 |

두 JSON plan의 `complete=true`, `errored=false`와 전체 resource actions를
검사했다. targeted plan이나 refresh 생략은 사용하지 않았다. Loki는
`No changes`, 운영 루트는 `7 to import, 0 to add, 0 to change, 0 to destroy`
이며 두 forget은 AWS 삭제가 아니다. 검증 후 두 원격 state의 내용과 serial이
최초 조회와 동일한 것도 확인했다. AWS·DNS·IAM·state 쓰기와 merge는 없었다.

최초 운영 plan의 오래된 로컬 입력은 그대로 사용하면 변경을 제안했다.
비공개 입력을 실제 SSM 값, 현재 태스크 수, Terraform이 추적하는 WS/AI
태스크 설정 및 현재 AI IAM 권한과 대조해 보정한 뒤 전체 plan을 다시 실행했다.
필수 ephemeral `be_secret_values`는 state가 가리키는 기존 Secret version을
읽어 비공개 파일에만 보관했다. placeholder로 검증하지 않았다.
무변경 결과는 이 검증 시점의 실제 입력에 한정되며 저장소 기본값만으로
재현된다고 주장하지 않는다. 입력·raw state·raw plan·JSON·ZIP은 공개하지 않는다.

## 재검증 방법

아래 환경 변수에는 기존 운영 입력과 시크릿, 최신 live 보정 입력 및 저장소
밖의 권한 제한 artifact 디렉터리 경로를 지정한다. 값이나 raw plan을 터미널,
PR, CI 공개 로그에 출력하지 않는다. 백엔드는 변경하지 않는다.

```bash
umask 077
terraform -chdir=terraform/prod init -input=false -lockfile=readonly
terraform -chdir=terraform/prod/cloudwatch-loki init -input=false -lockfile=readonly
terraform/prod/cloudwatch-loki/fetch-package.sh
terraform fmt -check -recursive terraform
terraform -chdir=terraform/prod validate
terraform -chdir=terraform/prod/cloudwatch-loki validate
python3 -m unittest discover -s tests -v

terraform -chdir=terraform/prod plan -lock=false -input=false \
  -var-file="$BASELINE_PROD_INPUTS" -var-file="$BASELINE_RUNTIME_INPUTS" \
  -var-file="$BASELINE_CURRENT_INPUTS" \
  -out="$BASELINE_ARTIFACTS/production.tfplan" > "$BASELINE_ARTIFACTS/production.log" 2>&1
terraform -chdir=terraform/prod/cloudwatch-loki plan -lock=false -input=false \
  -out="$BASELINE_ARTIFACTS/loki.tfplan" > "$BASELINE_ARTIFACTS/loki.log" 2>&1
terraform -chdir=terraform/prod show -json "$BASELINE_ARTIFACTS/production.tfplan" > "$BASELINE_ARTIFACTS/production.json"
terraform -chdir=terraform/prod/cloudwatch-loki show -json "$BASELINE_ARTIFACTS/loki.tfplan" > "$BASELINE_ARTIFACTS/loki.json"
python3 scripts/check_readonly_plan.py "$BASELINE_ARTIFACTS/production.json"
python3 scripts/check_readonly_plan.py "$BASELINE_ARTIFACTS/loki.json"
```

검사기는 import/no-op/read/forget만 허용하며 create/update/delete 및 양방향
replacement, incomplete/errored/deferred plan을 실패시킨다. 테스트 7개는 이
판정과 비공개 값 비출력을 검증한다. plan 자체가 실패하면 JSON 검사를 통과한
것으로 간주하지 않는다. 권한이나 필수 입력이 막히거나 AWS 변경 제안이
남으면 PR을 draft로 유지하고 #11을 닫지 않는다. Route53 목록 권한은 기존
조사에서 거부됐으며 확대하지 않았다. DNS 변경은 요구하거나 실행하지 않는다.
