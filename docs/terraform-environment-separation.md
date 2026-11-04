# dev/prod 환경별 모듈과 state 전환 결과 (#5 / PR #14)

`terraform/dev`는 현재 V1 EC2, `terraform/prod`는 현재 V2 ECS를 소유하는 별도 소스다. 공유 `terraform/modules`, `terraform/environments`, 실행 가능한 옛 `terraform/*.tf`는 없다. 운영 cluster/BE/WS/AI는 직접 리소스를 소유하며 wrapper를 추가하지 않았다. `terraform/prod/cloudwatch-loki`는 독립 루트로 `./forwarder`를 참조한다.

| 루트 | 동일 bucket의 key | 현재 상태 |
| --- | --- | --- |
| `terraform/dev` | `dev/terraform.tfstate` | EC2 3대 편입 완료, serial 1 |
| `terraform/prod` | `prod/terraform.tfstate` | 기존 key/lineage 유지, 주소 정리 완료, serial 30 |
| `terraform/prod/cloudwatch-loki` | `prod/cloudwatch-loki/terraform.tfstate` | 기존 독립 key/lineage/serial 유지 |

Bucket은 `star23-tfstate-975779326240`, region은 `ap-northeast-2`, caller는 계정 `975779326240`의 IAM `noel`로 재확인했다. 최종 디렉터리·network 하위 모듈·SG 소유권 이동을 반영한 새 full-refresh plan에서 기존 137개 ID와 no-op을 대조했다. 따라서 MySQL·PostgreSQL, ALB idle120/chat route, 공유 CDN 전체 구성, Secret/version→AI task→healthy AI service→BE service 및 기존 CI task revision 소유권은 유지한다.

## 승인된 state 전환과 최종 무변경 검증

2026-11-04 사용자의 실행 승인 후 최신 소유권과 전체 plan을 다시 확인했다.
S3 versioning Enabled와 변경 전 5개 state의 VersionId·로컬 백업·SHA256을 보관하고,
실제 S3 backend/default workspace와 잠금 아래 검증한 saved plan만 순차 적용했다.

- prod: 121개 주소 이전, 기존 리소스 7개 편입, 사라진 ALB 규칙의 기록 2개 해제.
  기존 137개 ID를 유지한 총 144개 managed 객체와 serial 29→30, 동일 lineage를 확인했다.
- dev: 기존 app/data/messaging EC2 3대를 실제 `dev/terraform.tfstate`에 편입했다. serial 1이다.
- Loki 및 staging 계열 3개 state는 bytes·lineage·serial이 그대로다. EIP allocation/association 7개도 변경하지 않았다.

임시 선언은 active 사본에서 제거하고, 아래 실제 저장소 경로에서 full refresh plan을 다시 실행했다.
`-target`·refresh 생략·ignore_changes 추가로 차이를 숨기지 않았다.

| 실제 소스 루트 | 최종 plan 시각(KST) | detailed exit | create/update/delete/replace | import/forget/move |
| --- | --- | --- | --- | --- |
| `terraform/prod` | 2026-11-04 14:27:38 | 0 | 모두 0 | 모두 0 |
| `terraform/dev` | 2026-11-04 14:27:35 | 0 | 모두 0 | 모두 0 |
| `terraform/prod/cloudwatch-loki` | 2026-11-04 14:27:35 | 0 | 모두 0 | 모두 0 |

세 plan의 complete=true/errored=false와 output no-op, manifest 없는 guard 통과를 확인했다.
AWS 리소스를 생성·수정·삭제하지 않았으며 state와 그 잠금 객체만 썼다.

첫 post-import prod plan에서는 provider가 읽은 ALB `chat_routes`의 중복 top-level
`target_group_arn` 표현 때문에 update 1건이 나타나 적용하지 않았다. 같은 대상·weight·stickiness를
유지하는 기존 `forward` 블록만 남긴 뒤 위의 no-op을 확인했다. 실제 ALB 동작은 변경하지 않았다.
수정 후 fmt/세 루트 validate 및 전체 27개 회귀 테스트가 통과했다.

현재 TF 110개 소스 집합 SHA256: `21c367d55eb4740734cf27d2b6475fedc133306954b4c354d63329dd4924cc94`.
현재 실제 prod graph SHA256: `2d4a4d7bf3afc29f00aa132cf2aa72d5e9b7fe5528cc78dd52770e496881ec13`, 698 edges.
백업·실행 기록·최종 plan/graph 및 독립 감사는 저장소 밖 0700
`service-modules-private/state-transition-20261104/`에 보관한다. 아래 preview는 전환 전 기록이다.

## 실제 dev 관리 대상과 소유권 경계

2026-11-04 live EC2 inventory에서 Name/Environment, 실행 상태, V1 subnet/SG 연결을 확인했다. 모든 5개 원격 state의 managed ID와 대조하여 아래 3개 ID의 기존 소유자가 없음을 확인했다. 데이터 호스트는 Environment 태그가 없으므로 `star23-data-dev` 이름과 dev 전용 data/SSH SG 연결을 함께 근거로 삼았다. AMI, type, private IP, subnet, SG 연결, instance profile, IMDSv2, root EBS 설정/태그는 실제 조회값이며 ignore_changes를 추가하지 않았다. root EBS는 EC2 중첩 설정이며 별도 volume 중복 편입은 없다.

| 현재 관리 주소 | 실제 기존 ID | 근거 |
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

## 전환 전 소스 전체 preview 기록

이 절은 실행 승인 전의 full-refresh preview 기록이다. 당시 `-lock=false -input=false`를 사용했고 target/refresh 생략은 없었다. prod 임시 선언과 실제 Secret 입력은 저장소 밖 0700 private 디렉터리에만 두었다. 당시 dev는 backend.tf를 제외한 빈 private local backend였으며 원격 dev state가 없었다. 실제 적용 전에는 S3 dev backend로 새 plan을 만들어 동일한 3개 import만 검증했다. 현재 무변경 결과는 위의 전환 완료 절을 따른다.

| preview | create | update | delete | replace | import | forget | move |
| --- | --- | --- | --- | --- | --- | --- | --- |
| prod | 0 | 0 | 0 | 0 | 7 | 2 | 121 |
| Loki | 0 | 0 | 0 | 0 | 0 | 0 | 0 |
| dev empty-private-state | 0 | 0 | 0 | 0 | 3 | 0 | 0 |

세 plan 모두 complete=true, errored=false, deferred 없음. prod 기존 ID 137개와 live BE/WS/AI desired count·CI task revision 3개를 보존했다. 전체 121 move/7 import/2 forget 주소와 정확한 ID는 [서비스 소유권 표](terraform-service-modules.md)에 있다. dev 세 주소/ID는 위 표의 집합과 정확히 일치한다.

`check_readonly_plan.py`는 exact manifest 없이 import를 허용하지 않으며 모든 write/replacement, ID 불일치·unknown ID, 누락·추가 주소, incomplete/deferred/errored 및 action invocation을 거부한다. 신규 회귀 검사는 dev의 부분/추가/GPU 편입, 잘못된/unknown ID, update/replacement를 거부한다. 프로젝트 명령 `python3 -m unittest discover -s tests`로 기존 검사와 환경/adoption·중첩 네트워크 검사, 총 27개가 통과했다. 세 root fmt/validate도 통과했다. provider cache가 전혀 없는 별도 clean 사본에서도 환경/adoption 3개 테스트를 통과했다. cache가 존재할 때만 symlink를 재사용하고 없으면 init이 설치한다.

전환 전 Terraform 소스 SHA256 집합 해시: `c8a22fca4e4de40d44f91d362f0569ba1e37704ac7cbd90b9431cbeec9a754f1`.
전환 전 prod graph SHA256: `04e7a8039ae2e34b8f1965e2960cc56a989e038807572b02f340d8ee439a9644`, edge 1024개. Secret 순서, 서비스별 traffic rule/outbound, ALB HTTP/HTTPS 선행 조건, 서비스 노드 한정 gate, cycle 부재를 실제 graph와 소스 변이 회귀 검사로 검증했다. `verify_environment_previews.py`는 이 전환 전 증거 전용 검사기이며, 적용 후의 일상 검증에는 사용하지 않는다.

당시 5개 원격 state는 전후 바이트·lineage·serial이 같았다. 당시 serial은 prod29, Loki4, staging53, buffered-migration4, chat-message-sqs13이며 dev key가 없었다. raw state/plan/tfvars/Secret/ZIP/.terraform은 Git이나 PR에 올리지 않는다.

## 운영자 일상 재검증

저장소 루트에서 실제 각 backend를 초기화하고 검사한다. Terraform 실행 입력과 Secret은 비공개 파일로 공급한다.

```bash
terraform -chdir=terraform/dev init -input=false -lockfile=readonly
terraform -chdir=terraform/prod init -input=false -lockfile=readonly
terraform -chdir=terraform/prod/cloudwatch-loki init -input=false -lockfile=readonly
terraform fmt -check -recursive terraform
terraform -chdir=terraform/dev validate
terraform -chdir=terraform/prod validate
terraform -chdir=terraform/prod/cloudwatch-loki validate
python3 -m unittest discover -s tests
```

이제 정상 소스에 import/moved/removed 선언을 추가하지 않는다. 기존 전환 plan을 재적용하지 않고 새 plan을 검토한다. `PRIVATE_ARTIFACTS`는 0700 비공개 디렉터리다. 세 plan 모두 detailed exit 0과 manifest 없는 guard 통과를 기대한다.

```bash
terraform -chdir=terraform/prod plan -input=false -lock-timeout=60s -detailed-exitcode \
  -var-file="$PROD_INPUTS" -var-file="$SECRET_RUNTIME_INPUTS" -out="$PRIVATE_ARTIFACTS/prod.tfplan"
terraform -chdir=terraform/dev plan -input=false -lock-timeout=60s -detailed-exitcode -out="$PRIVATE_ARTIFACTS/dev.tfplan"
terraform -chdir=terraform/prod/cloudwatch-loki plan -input=false -lock-timeout=60s -detailed-exitcode -out="$PRIVATE_ARTIFACTS/loki.tfplan"
# 각 plan을 terraform show -json으로 같은 private 디렉터리에 저장한 후:
python3 scripts/check_readonly_plan.py "$PRIVATE_ARTIFACTS/prod.json"
python3 scripts/check_readonly_plan.py "$PRIVATE_ARTIFACTS/dev.json"
python3 scripts/check_readonly_plan.py "$PRIVATE_ARTIFACTS/loki.json"
```

prod state 정리와 dev EC2 편입, 세 실제 루트의 최종 무변경 검증은 완료했다. 기존 8개 published commit을 보존하고 같은 PR에 목적별 커밋을 추가했다. PR #14는 이 무변경 결과를 merge 조건으로 사용한다. dev 공유 네트워크/SG/EIP/IAM의 추가 소유권 편입은 여전히 후속 범위이고 #5에서 추적한다. EIP 정리는 #12로 구분한다.

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
전환 전 proof는 `service-modules-private/final-layout/`, 실행과 정상 소스의 최종 proof는
`service-modules-private/state-transition-20261104/`에 구분해 보관한다.
