# Storage

BE·AI 컨테이너 이미지와 앱 파일을 보관하는 저장소다.

## 파일

- `main.tf`: BE·AI ECR 저장소.
- `s3.tf`: 이미지와 프런트 배포 파일용 S3 버킷.
- `outputs.tf`: ECS 이미지 경로와 BE의 S3 권한에 필요한 값.

## 관리 범위

기존 ECR 저장소 2개와 S3 버킷 2개를 관리한다.
이름·리전·암호화·이미지 태그 정책은 기존 설정을 유지한다.
ECR 이미지 빌드와 push, 프런트 파일 업로드는 CI/CD가 담당한다.
S3 버킷 정책·OAC·웹사이트 설정은 이 모듈에서 관리하지 않는다.
DB는 `../database`에서 관리한다.

## 연결

입력값은 없다. 현재 프로젝트의 기존 저장소를 그대로 표현한다.
`be_repository_url`과 `ai_repository_url`은 ECS 이미지 주소에 사용한다.
`image_bucket_arn`은 BE Task Role의 S3 접근 정책에 사용한다.
기존 리소스의 import와 주소 이전 선언은 루트 모듈에 있다.
