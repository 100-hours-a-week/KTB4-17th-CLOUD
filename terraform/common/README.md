# 공통 인프라

V1·V2·V3가 함께 사용하는 CloudFront 1개, S3 버킷 2개, ECR 저장소 2개를 소유한다. backend는 `common/terraform.tfstate`이며 버전별 인프라와 따로 실행한다. 공통 자원에는 `prevent_destroy`를 둔다.

| 모듈 | 관리 대상 |
| --- | --- |
| `cdn` | 기존 CloudFront 배포, 도메인·원본·라우팅·외부 WAF/Function/OAC/인증서 연결 |
| `storage` | 이미지·프런트엔드 S3 버킷, BE·AI ECR 저장소 |

파일 업로드, 컨테이너 이미지 게시, CloudFront Function 프로그램은 외부 배포가 관리한다. 현재 코드에 없는 버킷 정책·인증서·WAF·OAC의 소유권까지 가져오지는 않는다.

버전별 루트는 공통 자원을 다시 선언하지 않고 이 state의 출력을 참조한다. V2의 `common.tf`는 이미지 버킷 ARN과 ECR URL을 읽으며 기존 `deployment_infrastructure` 출력 계약을 유지한다. 프런트 배포는 `frontend_bucket_name`, `cloudfront_distribution_id`를 사용할 수 있다. 다른 출력은 `image_bucket_name`, `image_bucket_arn`, `be_repository_url`, `ai_repository_url`이다.

2026-11-09 기존 prod state에서 공통 자원 5개의 소유권을 이 state로 옮겼다. 실제 자원은 생성·수정·삭제하지 않았고 ID를 유지했다. 읽기 전용 계획에서 발견된 기존 `v3.star23sharp.com` 도메인과 WS 라우팅 함수 연결도 코드에 보존했다. 이관 완료 후 일회성 이관 선언은 남기지 않는다.

```sh
terraform -chdir=terraform/common init -input=false -lockfile=readonly
terraform -chdir=terraform/common validate
terraform -chdir=terraform/common plan -input=false -lock-timeout=60s
```

버전을 철거하기 전 CloudFront의 API/WS 원본이 남아 있는 버전을 향하는지 확인한다. 버전별 destroy가 공통 자원을 삭제하지 않더라도 원본 서버를 제거하면 해당 요청은 처리할 수 없다.
