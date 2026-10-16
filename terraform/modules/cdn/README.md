# CDN

프런트 정적 파일과 API·WebSocket 요청을 전달하는 CloudFront 설정이다.

## 파일

- `main.tf`: 기존 Distribution의 오리진·캐시 동작·인증서 연결.
- `variables.tf`: 프로젝트 이름 접두사.
- `outputs.tf`: Distribution ID.

## 관리 범위

기존 CloudFront Distribution 하나를 관리한다.
`/api/*`와 `/ws/*`의 오리진은 기존 `api.byul23.shop`을 유지한다.
S3 오리진 도메인도 기존 값을 유지한다.
WAF·CloudFront Function·OAC·ACM 인증서는 외부 ARN/ID를 참조한다.
이 모듈은 해당 외부 리소스를 생성하거나 관리하지 않는다.
프런트 S3 버킷은 `../storage`에서 관리한다.

## 연결

`name_prefix`는 Distribution의 Name 태그에 사용한다.
`distribution_id`는 프런트 배포 후 캐시 무효화에 사용할 수 있다.
기존 리소스의 import와 주소 이전 선언은 루트 모듈에 있다.
오리진·도메인 변경은 이름 변경과 별도로 검토한다.
