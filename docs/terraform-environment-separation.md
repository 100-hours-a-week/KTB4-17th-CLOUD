# dev/prod 환경별 모듈과 최종 검증 (#5 / draft PR #14)

`terraform/dev`는 현재 V1 EC2, `terraform/prod`는 현재 V2 ECS를 소유하는 별도 소스다. 공유 `terraform/modules`, `terraform/environments`, 실행 가능한 옛 `terraform/*.tf`는 없다. 운영 cluster/BE/WS/AI는 직접 리소스를 소유하며 wrapper를 추가하지 않았다. `terraform/prod/cloudwatch-loki`는 독립 루트로 `./forwarder`를 참조한다.

| 루트 | 동일 bucket의 key | 현재 상태 |
| --- | --- | --- |
| `terraform/dev` | `dev/terraform.tfstate` | 원격 object 없음, 코드와 private import-only preview만 준비 |
| `terraform/prod` | `prod/terraform.tfstate` | 기존 key/lineage/serial 유지, 전환 미실행 |
| `terraform/prod/cloudwatch-loki` | `prod/cloudwatch-loki/terraform.tfstate` | 기존 독립 key/lineage/serial 유지 |

Bucket은 `star23-tfstate-975779326240`, region은 `ap-northeast-2`, caller는 계정 `975779326240`의 IAM `noel`로 재확인했다. 최종 디렉터리·network 하위 모듈·SG 소유권 이동을 반영한 새 full-refresh plan에서 기존 137개 ID와 no-op을 대조했다. 따라서 MySQL·PostgreSQL, ALB idle120/chat route, 공유 CDN 전체 구성, Secret/version→AI task→healthy AI service→BE service 및 기존 CI task revision 소유권은 유지한다.

## 실제 dev 편입 제안과 소유권 경계

2026-11-04 live EC2 inventory에서 Name/Environment, 실행 상태, V1 subnet/SG 연결을 확인했다. 모든 5개 원격 state의 managed ID와 대조하여 아래 3개 ID의 기존 소유자가 없음을 확인했다. 데이터 호스트는 Environment 태그가 없으므로 `star23-data-dev` 이름과 dev 전용 data/SSH SG 연결을 함께 근거로 삼았다. AMI, type, private IP, subnet, SG 연결, instance profile, IMDSv2, root EBS 설정/태그는 실제 조회값이며 ignore_changes를 추가하지 않았다. root EBS는 EC2 중첩 설정이며 별도 volume 중복 편입은 없다.

| 정확한 제안 주소 | 실제 기존 ID | 근거 |
| --- | --- | --- |
| `module.ec2.aws_instance.app` | `i-00ff61dd2bb2a319d` | running, Environment=dev, Name=star23-app-dev |
| `module.database.aws_instance.data` | `i-0bf3533411fffb33c` | running, Name=star23-data-dev, dev data/SSH SG |
| `module.ec2.aws_instance.messaging` | `i-0dc411e6fe68020e6` | running, Environment=dev, Name=star23-kafka,redis-dev |

아래는 이번 dev state 소유권에서 명시적으로 제외한다. EC2가 기존 subnet/SG/profile ID를 참조해도 그 객체나 규칙의 소유권을 편입하지 않는다.

| 제외/외부 자원 | 근거와 남은 범위 |
| --- | --- |
| V1 `vpc-0c203bd23ce77e200`, subnet, route table | dev·monitoring·retired staging 혼재. VPC 전체의 dev 소유권은 입증되지 않았다. 소비자·소유권 분리 검토 후 granular 편입을 별도 제안해야 한다. |
| V1↔V2 peering, V1 return routes, `v1_database_from_ecs` ingress | 기존 prod 소유. dev에서 중복 import하거나 authoritative rule collection으로 덮지 않는다. |
| dev SG `sg-0208d71a531ef25b9`, `sg-099a8e5296eb61681`, `sg-0477fb590a93b0686` | EC2 연결만 유지. 그룹·각 ingress/egress 규칙과 다른 소비자의 독점 소유권은 이번 EC2 편입으로 확정하지 않았다. 후속 조사에서 규칙별 manifest와 기존 prod grant 보존 검증이 필요하다. |
| `sg-09e811079dfd1491b` | retired staging state의 `legacy_app_staging` 및 규칙 소유권을 확인했다. dev가 아니다. |
| 모니터링 `i-00ed093810ec34b7d`, Loki SG `sg-050a922ebf3986caf` | 모니터링 호스트는 prod Loki 목적지. Loki SG와 egress는 독립 Loki state 소유다. |
| GPU `i-061ce3e648c927f1d` / `sg-0be838c38b3ab54b5` | 재조회 시 존재, stopped, Task=codex-dev-gpu-smoke. 지속 운영 dev workload라는 근거가 없어 제외. 재사용/종료 정책과 지속 소유자를 별도로 확정해야 한다. |
| app-dev EIP `eipalloc-0edfa3e3d42cb878c` | 실제 app 인스턴스/ENI 연결은 확인했으나 allocation의 독립 생명주기·운영 소유권은 이번 EC2 범위에서 확정하지 않는다. 후속 allocation별 ownership proposal 필요. EIP association은 변경하지 않았다. |
| 미연결 EIP 및 기타 NAT EIP | #12 cleanup 범위. 편입·해제하지 않는다. |
| 공유 CloudFront `E3LYSMQO2T1UT`, FE/image S3, BE/AI ECR | prod 단독 소유 유지. dev alias로 dev 소유권을 추론하지 않는다. |
| 기존 EC2 IAM profile/role, key pair, guest DB/app 데이터·user data 운영 | 기존 참조만 유지. IAM 공유 소비자/정책 및 guest 운영의 편입은 별도 소유권·보안 검토 필요. |
| V2 bastion 및 retired staging/buffered/chat-message-sqs | dev 3대의 범위 밖. 기존 state를 dev로 재해석하지 않는다. |

## 최종 소스 전체 preview 증거

모든 plan은 full refresh, `-lock=false -input=false`, target/refresh 생략 없이 새로 실행했다. prod의 임시 moved/import/removed 선언과 실제 Secret 입력은 저장소 밖 0700 private 디렉터리에만 두었다. dev는 backend.tf를 제외한 최종 코드 사본에 임시 정확-ID import 선언을 넣고 **state 파일이 없는 private local backend**에서 plan했다. 원격 dev state는 여전히 없다. prod 정상 소스 자체가 현재 원격 state에 대해 no-op이라는 주장은 하지 않는다.

| preview | create | update | delete | replace | import | forget | move |
| --- | --- | --- | --- | --- | --- | --- | --- |
| prod | 0 | 0 | 0 | 0 | 7 | 2 | 121 |
| Loki | 0 | 0 | 0 | 0 | 0 | 0 | 0 |
| dev empty-private-state | 0 | 0 | 0 | 0 | 3 | 0 | 0 |

세 plan 모두 complete=true, errored=false, deferred 없음. prod 기존 ID 137개와 live BE/WS/AI desired count·CI task revision 3개를 보존했다. 전체 121 move/7 import/2 forget 주소와 정확한 ID는 [서비스 소유권 표](terraform-service-modules.md)에 있다. dev 세 주소/ID는 위 표의 집합과 정확히 일치한다.

`check_readonly_plan.py`는 exact manifest 없이 import를 허용하지 않으며 모든 write/replacement, ID 불일치·unknown ID, 누락·추가 주소, incomplete/deferred/errored 및 action invocation을 거부한다. 신규 회귀 검사는 dev의 부분/추가/GPU 편입, 잘못된/unknown ID, update/replacement를 거부한다. 프로젝트 명령 `python3 -m unittest discover -s tests`로 기존 검사와 환경/adoption·중첩 네트워크 검사, 총 27개가 통과했다. 세 root fmt/validate도 통과했다. provider cache가 전혀 없는 별도 clean 사본에서도 환경/adoption 3개 테스트를 통과했다. cache가 존재할 때만 symlink를 재사용하고 없으면 init이 설치한다.

최종 Terraform 소스 SHA256 집합 해시: `c8a22fca4e4de40d44f91d362f0569ba1e37704ac7cbd90b9431cbeec9a754f1`.
실제 prod graph SHA256: `04e7a8039ae2e34b8f1965e2960cc56a989e038807572b02f340d8ee439a9644`, edge 1024개. Secret 순서, 서비스별 traffic rule/outbound, ALB HTTP/HTTPS 선행 조건, 서비스 노드 한정 gate, cycle 부재를 실제 graph와 소스 변이 회귀 검사로 검증했다. `verify_environment_previews.py`는 모든 최종 소스를 private 사본/해시와 대조하고 새 plan을 exact manifest로 검사한다.

5개 원격 state는 전후 바이트·lineage·serial 모두 같다. serial: prod29, Loki4, staging53, buffered-migration4, chat-message-sqs13. dev key는 전후 list에서 존재하지 않는다. raw state/plan/tfvars/Secret/ZIP/.terraform은 Git이나 PR에 올리지 않는다.

## 운영자 재검증과 남은 승인 경계

저장소 루트에서 provider 준비 후 검사한다. dev backend를 초기화하지 않고 graph를 검사하는 회귀 테스트도 포함한다.

```bash
terraform -chdir=terraform/dev init -backend=false -input=false -lockfile=readonly
terraform -chdir=terraform/prod init -input=false -lockfile=readonly
terraform -chdir=terraform/prod/cloudwatch-loki init -input=false -lockfile=readonly
terraform fmt -check -recursive terraform
terraform -chdir=terraform/dev validate
terraform -chdir=terraform/prod validate
terraform -chdir=terraform/prod/cloudwatch-loki validate
python3 -m unittest discover -s tests
```

Private preview 재생성은 최신 live ownership/state snapshot과 정확한 manifest를 먼저 준비한다. prod 사본은 기존 backend key를 보존하고 temporary reconciliation blocks만 추가한다. dev 사본은 backend.tf와 .terraform/state를 복사하지 않고 임시 import 선언만 추가한다. 실제 Secret은 출력 없이 private 입력으로만 전달한다.

```bash
terraform -chdir="$PRIVATE_PROD" plan -lock=false -input=false -var-file="$PRIVATE_INPUTS" -var-file="$PRIVATE_SECRETS" -out="$PRIVATE_PROD_PLAN"
terraform -chdir="$PRIVATE_DEV" init -backend=false -input=false -lockfile=readonly
terraform -chdir="$PRIVATE_DEV" plan -lock=false -input=false -out="$PRIVATE_DEV_PLAN"
terraform -chdir=terraform/prod/cloudwatch-loki plan -lock=false -input=false -out="$PRIVATE_LOKI_PLAN"
# 각 plan을 terraform show -json으로 private 파일에만 저장한 후:
python3 scripts/check_readonly_plan.py "$PRIVATE_PROD_JSON" --manifest "$PRIVATE_PROD_MANIFEST"
python3 scripts/check_readonly_plan.py "$PRIVATE_DEV_JSON" --manifest "$PRIVATE_DEV_MANIFEST"
python3 scripts/check_readonly_plan.py "$PRIVATE_LOKI_JSON"
python3 scripts/verify_environment_previews.py "$PRIVATE_EVIDENCE"
```

코드 준비 및 세 preview까지만 검증했다. 실제 prod state 전환, dev state adoption, EIP 정리, AWS/DNS/IAM 변경, issue 종료, PR merge는 실행하지 않았다. 기존 8개 published commit을 보존하고 같은 브랜치에 논리적 후속 commit만 추가한다. PR #14는 draft, Refs #5를 유지한다.

## 최종 디렉터리와 준비 순서

```text
terraform/
  dev/
    main.tf, connections.tf, backend.tf, providers.tf
    network/{vpc,subnet,routetable}/
    ec2/          # app + messaging EC2
    database/     # data EC2, 신규 RDS 아님
  prod/
    main.tf, connections.tf, backend.tf, providers.tf
    network/{vpc,subnet,routetable}/
    ecs/cluster/
    ecs/service/{be,ws,ai}/
    database/, alb/, storage/, cdn/
    cloudwatch-loki/forwarder/   # 독립 root의 기존 module.cloudwatch_loki 주소 유지
```

network 세 하위 디렉터리는 실제 resource/data 모듈이며 빈 디렉터리가 아니다.
dev network는 혼재 V1 VPC/subnet/route table을 data로만 조회하고 EC2 subnet 입력으로 연결한다.
prod network는 실제 VPC/IGW, subnet, route table/default route/association을 각 child에 둔다.
NAT와 peering/양방향 V1 route는 network 부모가 소유한다.
ALB와 DB SG 및 ECS 서비스 SG는 소비자 `security.tf`에 있다. prod `connections.tf`는
소비자별 SG 출력으로 교차 규칙만 연결하며 dev connections는 외부 legacy SG 참조를 연결한다.
ALB HTTP/HTTPS base rule 완료는 SG 출력 및 ALB resource까지, subnet 준비는 해당 소비자까지
전달한다. AI/BE/WS traffic rule은 service 노드만 기다리고 config/task/SG로 역전되지 않는다.
실제 graph 회귀 검사에는 새 중첩 network의 public/app/data 준비 경로와 두 RDS subnet group이 포함된다.

121 move는 이전 94개에 network child 이동 및 ALB/DB SG 소유권 이동 27개를 더한 집합이다.
체크포인트 `62cd3c861cf19983f6e2184d045df266572c4f18`과 그 이전 published 8개 커밋을 보존했다.
최종 proof는 저장소 밖 `service-modules-private/final-layout/`에 권한 제한하여 새로 생성했다.
이전 `environment-separation`/`network-readiness` plan이나 해시를 최종 증거로 재사용하지 않는다.
