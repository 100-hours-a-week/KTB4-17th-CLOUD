# STAR23 애플리케이션 Helm 차트

현재 AWS EKS `star-EKS-v3`에 배포된 설정을 기본 배포 기준으로 관리한다. 2026-11-10에 12개 앱의 Helm computed values, 배포 매니페스트와 실제 Kubernetes 리소스를 읽어 `values/`에 반영했다. 이 파일 변경으로 AWS에 배포하지는 않았다.

## 기본 배포 설정

```text
star23-service/
├─ Chart.yaml              # 차트 정보 (Helm 3, apiVersion: v2)
├─ values.yaml             # 공통 기본값
├─ values/
│  ├─ README.md            # 릴리스·Namespace·확인한 revision 목록
│  ├─ user-api.yaml        # 현재 User API 배포값
│  ├─ chat-socket.yaml     # 현재 Chat Socket 배포값
│  └─ ...                  # 12개 역할별 기본 설정
├─ templates/              # Deployment·Service·Ingress 등의 공통 틀
└─ examples/               # 이전 공통·역할·Secret·QA 조합 참고 자료
```

기본값 적용 순서는 **루트 `values.yaml` → `values/<릴리스>.yaml` 하나**다. Spring과 FastAPI는 이미지·포트·리소스·Secret 참조가 다르므로 역할 파일을 반드시 지정한다. 역할 파일에는 공통 기본값과 다른 항목을 넣고, 그 안에 기존 QA 리소스 조정·실행 플래그·Secret 참조도 함께 포함했다. `examples/`나 `qa-*.values.yaml`을 추가로 적용하지 않는다.

저장소 루트에서 렌더링과 검증:

```sh
helm lint ./manifest/helm/star23-service \
  -f ./manifest/helm/star23-service/values/user-api.yaml
helm template user-api ./manifest/helm/star23-service -n user \
  -f ./manifest/helm/star23-service/values/user-api.yaml
```

변경 검토 후 실제 배포할 때 사용할 명령:

```sh
helm upgrade --install user-api ./manifest/helm/star23-service \
  --namespace user --create-namespace --reset-values \
  -f ./manifest/helm/star23-service/values/user-api.yaml
```

`--reset-values`로 이전 릴리스에 남은 QA 오버레이와 `--set` 값을 다시 합치지 않고 저장소의 현재 기본값을 사용한다. 기존 릴리스 이름과 Namespace는 [values 목록](values/README.md)을 따른다. Argo CD 연결 파일은 [argocd/](../../../argocd/README.md)에 있다. Argo CD 관리로 전환한 앱은 위 Helm 배포 명령 대신 Git의 차트·역할별 values 변경으로 배포한다.

## 현재 기본값의 범위

- 앱 12개는 각각 Pod 1개다. Spring은 동일한 BE 이미지, FastAPI는 동일한 AI 이미지를 역할별로 재사용한다. 코드·백그라운드 작업의 완전한 분리를 뜻하지 않는다.
- `user-api`, `onboarding-api`, `recommend-api`, `auth-api`, `chat-api`, `chat-socket`의 v3 Ingress는 활성화돼 있다. AI 역할은 내부 ClusterIP만 사용한다.
- `chat-api`와 `chat-socket`의 CPU 요청은 `500m`이다. Image Worker와 Face AI는 CPU 노드에서 `750m/1250Mi`를 요청하고 `1 CPU/2Gi`를 제한값으로 사용한다. 이는 현재 배포 규모이며 부하 검증을 마친 운영 용량이라는 뜻은 아니다.
- `chat-api`의 chat runtime은 꺼져 있고, `chat-socket`은 켜져 있다. Chat Socket의 readiness/liveness probe는 현재 배포와 동일하게 꺼져 있다.
- RDS·Kafka·Redis·Secret은 기존 v2 운영 자원을 공유한다. Spring 프로필과 환경 라벨은 `prod`이며, 별도로 격리된 QA 데이터 환경이 아니다.
- HPA·CronJob·GPU/vLLM·Istio는 이 차트에 추가하지 않았다. 기존 CA·ESO·ALB Controller는 클러스터 공통 구성으로 별도 관리한다.

## 설정과 Secret

`configMap.data`는 비밀 없는 앱 환경설정이다. 차트는 ConfigMap을 `envFrom`으로 주입하고 설정 내용의 체크섬으로 Deployment 갱신을 유도한다.

`externalSecret.data`에는 Secrets Manager ARN·SSM Parameter Store 경로·조회할 키만 저장한다. ESO가 이 참조를 읽어 Kubernetes Secret을 만들고 Pod에 주입한다. 비밀번호·토큰·Redis 인증 URL 같은 실제 비밀값은 values나 Git에 넣지 않는다. Secret 갱신은 실행 중인 환경변수에 자동 반영되지 않으므로 별도 Pod 재시작 절차가 필요하다.

기존 ESO 설치 및 IAM·Pod Identity 참고 자료는 [Secret 연동 문서](examples/secrets/README.md), 라우팅의 역할과 제약은 [라우팅 문서](examples/services/ROUTING.md)에 남아 있다. 현재 기본 배포값의 기준은 `values/`다.
