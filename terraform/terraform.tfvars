acm_certificate_arn = "arn:aws:acm:ap-northeast-2:975779326240:certificate/13083ecf-f79a-4b35-b17f-5e134d1eb6b8"

be_image_tag        = "v1.1.1"
be_cpu_architecture = "X86_64" # ARM64 이미지라면 ARM64로 변경
be_desired_count    = 2

# DB 주소 등 앱이 요구하는 일반 환경변수. 실제 앱의 변수 이름을 사용한다.
be_environment = {}

# 비밀번호 등은 기존 Secrets Manager/SSM의 ARN으로 전달한다.
# 예: DB_PASSWORD = "arn:aws:ssm:ap-northeast-2:975779326240:parameter/star23/prod/db-password"
be_secrets = {}

# 위 시크릿이 고객 관리 KMS 키로 암호화된 경우 해당 키 ARN을 입력한다.
be_secret_kms_key_arns = []

# Service는 task_definition 변경을 무시하므로 CI/CD가 새 리비전을 배포해야 한다.
# 이 파일/Task Definition의 CPU, 메모리, 환경변수 등을 수정해도 실행 중인 태스크에는
# 자동 반영되지 않는다. 변경한 설정을 CI/CD의 Task Definition에도 반영하고 배포한다.


# -----
# 이미지 값은 최초 생성용이다. 실제 저장소에 존재하는 git SHA 태그/이미지 URI를 입력한다.
# 이후 CI/CD 배포마다 이 값을 바꿀 필요는 없다.

# 아래 WS 저장소 이름은 예시다. 실제 WebSocket 이미지의 전체 URI로 바꾼다.
ws_image_uri        = "975779326240.dkr.ecr.ap-northeast-2.amazonaws.com/replace-with-ws-repository:replace-with-existing-git-sha"
ws_cpu_architecture = "X86_64"
ws_desired_count    = 2

# AI는 기존 star23/ai ECR을 사용한다.
ai_image_tag        = "replace-with-existing-ai-git-sha"
ai_cpu_architecture = "X86_64"
ai_desired_count    = 2

# 포트와 헬스체크 경로는 예시다. 실제 앱 설정과 일치하도록 반드시 바꾼다.
# 두 앱 모두 0.0.0.0:<port>에서 수신하고, 헬스체크는 인증 없이 HTTP 200을 반환해야 한다.
# WS의 헬스체크는 WebSocket handshake가 아닌 일반 HTTP 엔드포인트다.
# ALB는 /ws, /ws/*를 WS로 전달하며 경로를 제거하지 않는다.
ws_port              = 8080
ws_health_check_path = "/health"
ai_port              = 8000
ai_health_check_path = "/health"

# DB 주소 등 일반 환경변수. 실제 앱이 사용하는 변수 이름을 넣는다.
# BE에서 AI를 호출할 주소는 http://ai:<ai_port> (위 예시에서는 http://ai:8000)이다.
# 이 주소는 Service Connect가 설정된 BE 태스크 안에서 사용한다.
ws_environment = {}
ai_environment = {}

# 비밀번호 등은 기존 Secrets Manager/SSM의 ARN으로 전달한다.
# 예: DB_PASSWORD = "arn:aws:ssm:ap-northeast-2:975779326240:parameter/star23/prod/db-password"
ws_secrets = {}
ai_secrets = {}

# 위 시크릿이 고객 관리 KMS 키로 암호화된 경우 해당 키 ARN을 입력한다.
ws_secret_kms_key_arns = []
ai_secret_kms_key_arns = []

# WS/AI가 DB에 직접 접근할 때만 mysql/postgres를 추가한다. DB 리소스는 생성하지 않는다.
# 예: ai_database_access = ["postgres"]
ws_database_access = []
ai_database_access = []

# AI 요청의 Service Connect 제한 시간. 긴 추론 요청에 맞춰 조정한다. 0은 제한 해제다.
ai_request_timeout_seconds = 120

# AI 컨테이너 헬스체크는 이미지 안의 python3와 Python 표준 라이브러리를 사용한다.
# 각 Task는 현재 1 vCPU / 2 GiB로 시작한다. BE/AI는 이 안에서 Service Connect 프록시도 실행한다.
# 이후 CI/CD가 Task Definition의 named port를 유지해야 한다. AI의 이름은 ai-http다.
#
# Service는 task_definition 변경을 무시하므로 CI/CD가 새 리비전을 배포해야 한다.
# Task Definition의 CPU, 메모리, 환경변수 등을 수정해도 실행 중인 태스크에는 자동 반영되지 않는다.
# 변경한 설정을 CI/CD의 Task Definition에도 반영하고 배포한다.
#
# Cloud Map 네임스페이스 생성 권한은 Terraform 실행 계정에 필요하다.
# AmazonECS_FullAccess에 이를 추가할 경우 cloud-map-terraform-policy.json 예제를 참고한다.
