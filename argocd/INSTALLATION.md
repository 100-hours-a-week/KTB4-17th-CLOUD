# STAR23 EKS Argo CD 설치 및 앱 등록 기록

2026-11-10에 로컬 Mac의 CLOUD 저장소에서 실행한 Argo CD 설치·검증·앱 등록 과정을 정리한다. Argo CD는 기존 EKS 안에서 실행하며, 별도 전용 EC2를 생성하지 않았다.

설치와 앱 등록은 완료됐다. 마지막으로 제공된 실행 결과에서 앱 12개는 모두 `Unknown / Healthy`였으므로, **Git 비교와 배포 동기화 완료는 별도로 확인해야 한다.**

## 설치 환경

| 항목 | 값 |
| --- | --- |
| 실행 위치 | 로컬 Mac 터미널, CLOUD 저장소 루트 |
| 저장소 경로 | `/Users/garyeong/IdeaProjects/KTB4-17th-CLOUD` |
| 대상 EKS | `star-EKS-v3` |
| AWS 리전 | `ap-northeast-2` |
| Argo CD Namespace | `argocd` |
| Helm 릴리스 | `argocd` |
| 공식 Helm 차트 | `argo-cd`, 버전 `10.17.1` |
| Argo CD 버전 | `v3.6.1` |
| 설치 values | `argocd/bootstrap/values.yaml` |
| 앱 감시 브랜치 | `main` |
| UI 공개 방식 | ClusterIP, 로컬 port-forward |

## 1. 저장소와 클러스터 확인

```sh
cd /Users/garyeong/IdeaProjects/KTB4-17th-CLOUD
kubectl config current-context
```

대상 컨텍스트:

```text
arn:aws:eks:ap-northeast-2:975779326240:cluster/star-EKS-v3
```

명령은 로컬에서 실행하지만, kubeconfig에 지정된 EKS API로 전달돼 클러스터에 적용된다. 앱 차트와 역할별 values는 감시 브랜치인 `main`에 반영돼 있어야 한다.

## 2. Argo CD 자체 설치

저장소 루트에서 다음 명령을 실행했다. 복사할 때 줄바꿈 연결 문제가 없도록 한 줄 명령을 사용한다.

```sh
helm upgrade --install argocd argo-cd --repo https://argoproj.github.io/argo-helm --version 10.17.1 --namespace argocd --create-namespace -f argocd/bootstrap/values.yaml --wait
```

주요 옵션:

| 옵션 | 역할 |
| --- | --- |
| `upgrade --install` | 릴리스가 없으면 설치하고, 있으면 갱신 |
| `--repo` | 공식 Argo Helm 차트 저장소 |
| `--version 10.17.1` | 사용할 차트 버전 고정 |
| `--namespace argocd --create-namespace` | 설치 Namespace 지정 및 생성 |
| `-f argocd/bootstrap/values.yaml` | 저장소의 설치 설정 적용 |
| `--wait` | Helm이 관리하는 대상 리소스의 준비 상태 대기 |

확인한 설치 결과:

```text
Release "argocd" does not exist. Installing it now.
NAME: argocd
LAST DEPLOYED: Tue Nov 10 23:10:24 2026
NAMESPACE: argocd
STATUS: deployed
REVISION: 1
DESCRIPTION: Install complete
```

설치 시각은 KST 기준이다. 이 성공 결과는 Argo CD 자체 설치에 대한 것이며, 앱 12개의 Git 동기화 완료를 의미하지는 않는다.

## 3. CRD 등록 확인

`Application`과 `AppProject`는 Argo CD가 설치하는 사용자 정의 리소스다. 이 종류를 Kubernetes가 인식하려면 CRD가 먼저 등록돼 있어야 한다.

```sh
kubectl get crd applications.argoproj.io appprojects.argoproj.io
```

확인한 결과:

```text
NAME                       SCOPE        VERSIONS            CREATED AT
applications.argoproj.io   Namespaced   v1alpha1(storage)   2026-11-10T14:10:43Z
appprojects.argoproj.io    Namespaced   v1alpha1(storage)   2026-11-10T14:10:43Z
```

CRD 생성 시각의 `Z`는 UTC이며, 위 시각은 KST `2026-11-10 23:10:43`이다.

## 4. Argo CD Pod 상태 확인

```sh
kubectl get pods -n argocd
```

제공된 실행 결과에서 아래 7개 구성요소의 Pod가 모두 `1/1 Running`, 재시작 `0`이었다.

| 구성요소 | Ready | 상태 | 재시작 |
| --- | --- | --- | --- |
| application-controller | 1/1 | Running | 0 |
| applicationset-controller | 1/1 | Running | 0 |
| dex-server | 1/1 | Running | 0 |
| notifications-controller | 1/1 | Running | 0 |
| redis | 1/1 | Running | 0 |
| repo-server | 1/1 | Running | 0 |
| server | 1/1 | Running | 0 |

Pod 이름 뒤의 해시는 재배포 시 달라질 수 있다. 현재 상태를 확인할 때는 위 명령을 다시 실행한다.

## 5. Project와 앱 12개 등록

Argo CD 설치와 CRD 확인 후 다음 명령을 실행했다.

```sh
kubectl apply -k argocd
```

`argocd/kustomization.yaml`을 읽어 다음 리소스를 생성했다.

- AppProject: `star23-apps`
- Application 12개: `auth-api`, `chat-ai-cleanup`, `chat-ai-practice`, `chat-ai-simulation`, `chat-api`, `chat-socket`, `image-worker`, `onboarding-api`, `onboarding-face-certify-ai`, `onboarding-persona-ai`, `recommend-api`, `user-api`

실행 결과는 AppProject와 각 Application 모두 `created`였다. Application 객체는 `argocd` Namespace에 저장되며, 실제 앱은 각 Application의 `destination.namespace`에 따라 기존 `user`, `chat`, `recommend`, `auth` Namespace에 배포된다.

## 6. 앱 등록 직후 상태와 동기화 확인

```sh
kubectl get applications -n argocd
```

제공된 등록 직후 결과:

```text
NAME                         SYNC STATUS   HEALTH STATUS
auth-api                     Unknown       Healthy
chat-ai-cleanup              Unknown       Healthy
chat-ai-practice             Unknown       Healthy
chat-ai-simulation           Unknown       Healthy
chat-api                     Unknown       Healthy
chat-socket                  Unknown       Healthy
image-worker                 Unknown       Healthy
onboarding-api               Unknown       Healthy
onboarding-face-certify-ai   Unknown       Healthy
onboarding-persona-ai        Unknown       Healthy
recommend-api                Unknown       Healthy
user-api                     Unknown       Healthy
```

`Healthy`는 리소스 건강 상태이고, `SYNC STATUS`는 Git의 원하는 설정과 클러스터 상태의 비교 결과다. **`Unknown / Healthy`만으로 자동 배포 연결이 검증됐다고 판단하지 않는다.** 정상 동기화 여부는 이후 `Synced / Healthy`와 실제 적용 revision을 확인한다.

상태를 계속 확인하려면:

```sh
kubectl get applications -n argocd -w
```

`Unknown`이 지속되면 대표 앱의 조건과 오류를 확인한다.

```sh
kubectl describe application user-api -n argocd
kubectl get application user-api -n argocd -o jsonpath='{range .status.conditions[*]}{.type}{": "}{.message}{"\n"}{end}'
kubectl get application user-api -n argocd -o jsonpath='{.status.sync.revision}{"\n"}'
```

오류 메시지를 기준으로 Git 읽기 권한, `main`의 존재, `manifest/helm/star23-service` 및 `values/<릴리스>.yaml` 경로, 차트 렌더링 실패 여부를 확인한다. 제공된 출력에는 원인 메시지가 없으므로 특정 원인으로 단정하지 않는다.

## 7. UI 접속과 최초 로그인

서버 Service는 ClusterIP이므로 로컬 포트포워딩으로 접속한다.

```sh
kubectl -n argocd port-forward service/argocd-server 8080:443
```

명령을 실행한 터미널을 유지하고 브라우저에서 `https://localhost:8080`에 접속한다. 현재 설치는 서버 TLS를 사용하므로 HTTPS 주소를 사용한다. 기본 자체 서명 인증서에 대한 브라우저 경고가 표시될 수 있다.

- 최초 로그인 사용자: `admin`
- 초기 비밀번호 확인:

```sh
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d
```

비밀번호는 로컬에서 확인해 로그인에 사용하며 문서나 Git에 기록하지 않는다. 로그인 후 초기 비밀번호를 변경하고, 변경 및 재로그인을 확인한 뒤 초기 비밀번호 Secret을 정리한다.

```sh
kubectl -n argocd delete secret argocd-initial-admin-secret
```

UI 접속·로그인·비밀번호 변경·초기 Secret 삭제는 이번에 제공된 실행 기록에 포함되지 않은 후속 절차다. [공식 접속·로그인 안내](https://argo-cd.readthedocs.io/en/stable/getting_started/).

## 8. 설치 중 발생한 오류와 해결

### CRD 설치 전 앱 등록

```text
no matches for kind "Application" in version "argoproj.io/v1alpha1"
no matches for kind "AppProject" in version "argoproj.io/v1alpha1"
ensure CRDs are installed first
```

Argo CD 설치 전에 `kubectl apply -k argocd`를 실행해서 발생했다. Argo CD를 Helm으로 먼저 설치하고 CRD 등록을 확인한 뒤 앱 등록 명령을 실행해 해결했다. `kubectl apply -k argocd` 자체는 Argo CD 설치 명령이 아니다.

### 여러 줄 명령의 역슬래시 뒤 공백

```text
Error: "helm upgrade" requires 2 arguments
zsh: command not found: --repo
```

줄 끝의 역슬래시 뒤에 공백이 있으면 다음 줄이 연결되지 않아 옵션들이 별도 명령으로 실행된다. 위 설치 단계의 한 줄 명령을 사용해 해결했다. 여러 줄로 작성한다면 역슬래시가 각 줄의 마지막 문자여야 한다.

## 9. 이후 변경 반영 방식

```text
main에 Helm 차트·역할별 values 변경 병합
→ EKS 안의 Argo CD가 Git 변경 감지
→ 차트 렌더링 및 실제 리소스와 비교
→ 자동 동기화
```

앱 등록 후에는 차트·values를 변경할 때마다 로컬에서 Helm 배포 명령을 실행할 필요가 없다. 로컬 PC가 꺼져 있어도 클러스터 안의 Argo CD는 계속 실행된다.

현재 구성은 부모 Application을 사용하지 않으므로, `argocd/applications/`의 연결 설정이나 AppProject를 변경할 때는 `kubectl apply -k argocd`로 갱신한다. 앱 코드의 새 이미지를 배포하려면 CI가 ECR에 이미지를 푸시한 뒤 CLOUD values의 `image.digest`도 갱신해야 한다. [연결 구조·자동 동기화 정책·CI 역할](README.md).

## 기록 시점의 완료 범위

| 항목 | 확인 결과 |
| --- | --- |
| Argo CD Helm 설치 | `deployed`, revision 1 |
| Application·AppProject CRD | 등록 완료 |
| Argo CD Pod | 7개 모두 Ready / Running |
| AppProject | 1개 생성 완료 |
| Application | 12개 생성 완료 |
| 앱 Git 비교·동기화 | 등록 직후 `Unknown`; 완료 확인 필요 |
| UI 로그인·초기 비밀번호 변경 | 제공된 실행 기록에 없음 |
