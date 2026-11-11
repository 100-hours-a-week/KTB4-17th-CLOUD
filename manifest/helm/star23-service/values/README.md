# 현재 AWS 배포 기본값

2026-11-10에 `star-EKS-v3`에서 읽은 Helm computed values를 기준으로 한다. 루트 `values.yaml`과 이 폴더의 역할 파일 하나를 합치면 수집 시점의 해당 Helm 릴리스 매니페스트를 재현한다. 역할 파일은 공통 기본값과 다른 항목만 담는다.

## 릴리스 목록

| 파일 / 릴리스 | Namespace | 확인한 Helm revision |
| --- | --- | --- |
| `user-api.yaml` | `user` | 12 |
| `onboarding-api.yaml` | `user` | 7 |
| `onboarding-persona-ai.yaml` | `user` | 3 |
| `image-worker.yaml` | `user` | 3 |
| `onboarding-face-certify-ai.yaml` | `user` | 1 |
| `chat-api.yaml` | `chat` | 6 |
| `chat-socket.yaml` | `chat` | 7 |
| `chat-ai-practice.yaml` | `chat` | 1 |
| `chat-ai-simulation.yaml` | `chat` | 2 |
| `chat-ai-cleanup.yaml` | `chat` | 2 |
| `recommend-api.yaml` | `recommend` | 3 |
| `auth-api.yaml` | `auth` | 3 |

Helm revision은 이 기본값을 확인한 출처다. 다음 배포에서 Helm이 revision을 증가시키며, 위 번호를 배포 옵션으로 지정하지 않는다.

## 사용 방법

저장소 루트에서:

```sh
helm template chat-socket ./manifest/helm/star23-service -n chat \
  -f ./manifest/helm/star23-service/values/chat-socket.yaml
```

Argo CD로 전환하기 전 수동 Helm 설치·갱신 명령의 형식:

```sh
helm upgrade --install chat-socket ./manifest/helm/star23-service \
  --namespace chat --create-namespace --reset-values \
  -f ./manifest/helm/star23-service/values/chat-socket.yaml
```

현재 기본값에는 이미지 digest·ConfigMap·Secret 참조·Ingress 경로·역할별 리소스 조정이 모두 반영돼 있다. 기존 `examples/backend.values.yaml`, `examples/services/*`, `examples/secrets/*`, `qa-*.values.yaml`을 추가하거나 `--reuse-values`로 이전 설정을 다시 합치지 않는다.

Argo CD 관리로 전환한 앱은 Helm 명령을 병행하지 않고 이 폴더의 파일을 Git에서 수정한다. [Argo CD 연결과 CI 이미지 갱신 흐름](../../../../argocd/README.md)을 따른다.

## 변경할 위치

- 전체 역할에 적용할 기본값: 상위 `values.yaml`.
- 특정 역할의 이미지·환경변수·리소스·라우팅·Secret 참조: 해당 역할 파일.
- 실제 비밀번호·토큰: AWS Secrets Manager 또는 SSM SecureString. Git에는 참조만 저장한다.
- CA·노드그룹·IAM·Pod Identity 연결: 앱 values 밖의 클러스터·AWS 인프라 구성.

Chat Socket은 현재 배포에서 probe가 꺼져 있고 chat runtime이 켜져 있다. 이 상태를 그대로 저장했으며, probe 개선이나 consumer 격리 같은 동작 변경은 별도로 검증해야 한다. Recommend Batch와 vLLM은 현재 12개 앱 릴리스에 없으므로 임의로 추가하지 않았다.

검증: 역할 파일 하나씩으로 12개 모두 Helm lint를 통과했고, 렌더링 결과는 수집한 Helm 매니페스트와 78개 실제 리소스의 관리 대상 설정에 일치했다. API 서버가 추가하는 기본값·상태는 비교 대상에서 제외했다.
