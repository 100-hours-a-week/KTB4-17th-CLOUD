# STAR23 v3 Argo CD 연결

prod와 staging은 각자 EKS 안의 기존 Argo CD를 사용한다. 각 환경의 Application 12개는 기존 Helm 릴리스 이름과 Namespace를 유지한다. prod 등록 진입점은 `argocd`, staging은 `argocd/staging`이다. 이 디렉터리를 저장하거나 커밋하는 것만으로 클러스터에 Argo CD가 설치되거나 Application이 등록되지는 않는다.

2026-11-10의 실제 설치 명령·결과·오류 해결과 앱 등록 기록은 [설치 및 앱 등록 기록](INSTALLATION.md)에 정리했다. Argo CD 설치와 Application 12개 생성은 확인됐고, 제공된 등록 직후 상태는 `Unknown / Healthy`여서 Git 동기화 완료는 추가 확인이 필요하다.

## 파일 구조

```text
argocd/
├─ bootstrap/values.yaml        # 공식 Argo CD 차트 설치값
├─ projects/star23-apps.yaml    # CLOUD 저장소와 앱 Namespace의 허용 범위
├─ applications/apps/*.yaml    # 앱 12개의 자동 동기화 설정
├─ kustomization.yaml          # prod Project와 Application 등록
├─ staging/                    # staging Project와 기존 이름의 Application 12개
└─ ci/                         # 별도 적용하는 Jenkins IAM/RBAC 연결 범위
```

앱 자체의 Deployment·Service·Ingress·ConfigMap·Secret 참조는 기존 `manifest/helm/star23-service`에서 관리한다. CA·ALB Controller·ESO·Terraform은 이 앱 프로젝트의 동기화 대상에 추가하지 않았다.

## 감시 대상과 동기화 정책

| 항목 | 설정 |
| --- | --- |
| Git 저장소 | `https://github.com/100-hours-a-week/KTB4-17th-CLOUD.git` |
| 감시 브랜치 | 배포 기준 브랜치 `main` |
| 차트 경로 | `manifest/helm/star23-service` |
| prod 값 파일 | 차트 기준 `values/<릴리스>.yaml` 하나 |
| staging 값 파일 | 차트 기준 `values/staging/<릴리스>.yaml` 하나 |
| 대상 클러스터 | Argo CD가 설치된 동일 EKS (`https://kubernetes.default.svc`) |
| 앱 Namespace | 기존 `user`, `chat`, `recommend`, `auth` |

- `automated.enabled: true`: Git과 렌더링 결과가 달라지면 자동 적용한다.
- `selfHeal: true`: 직접 수정한 관리 대상 리소스도 Git 설정으로 복구한다.
- `prune: true`: Git의 렌더링 결과에서 제거된 관리 대상 리소스는 삭제한다.
- `allowEmpty: false`: 앱 전체가 빈 리소스 집합이 되는 자동 삭제는 허용하지 않는다.
- `FailOnSharedResource=true`: 다른 Argo CD Application이 이미 관리하는 리소스이면 동기화를 실패시킨다.

공통 `values.yaml`이나 템플릿 변경은 영향을 받는 여러 앱에 반영된다. 역할 파일 하나만 바꾸면 해당 설정을 사용하는 앱의 변경사항이 반영된다. `terraform/`이나 앱 소스 저장소 변경을 직접 감시하는 구성은 아니다. Git 변경은 Argo CD의 감지 주기 또는 webhook 이후 반영된다.

차트·values·Argo CD 설정을 `main`에 병합한 뒤 초기 등록 명령을 실행한다. 기능 브랜치에 푸시하거나 PR을 생성하는 것만으로는 배포되지 않으며, `main`에 병합된 변경을 감지한다. 이미 Application을 등록했다면 아래 `kubectl apply -k argocd`를 다시 실행해 감시 브랜치 변경을 반영한다. Application·Project 연결 설정 자체도 이 명령으로 관리한다. 이 구성에는 Application들을 다시 관리하는 부모 Application을 추가하지 않았다.

## 최초 설치와 연결

재구축할 때는 먼저 파일을 감시 브랜치에 커밋·푸시한다. 아래 명령은 실제 설치·등록을 수행한다. 앱 Namespace와 ESO·ALB Controller는 기존 구성을 사용한다. Argo CD 추가 실행에 필요한 general 노드 용량은 설치 전에 확인한다. 이미 설치된 환경에서는 [설치 기록](INSTALLATION.md)의 확인 명령으로 현재 상태부터 점검한다.

저장소 루트에서 현재 접속 대상 확인:

```sh
kubectl config current-context
```

대상은 `arn:aws:eks:ap-northeast-2:975779326240:cluster/star-EKS-v3`다.

Argo CD 자체 설치 (공식 Helm 차트 버전 고정):

```sh
helm upgrade --install argocd argo-cd \
  --repo https://argoproj.github.io/argo-helm \
  --version 10.17.1 \
  --namespace argocd --create-namespace \
  -f argocd/bootstrap/values.yaml \
  --wait
```

확인한 차트 `10.17.1`은 Argo CD `v3.6.1`을 사용한다. `application.resourceTrackingMethod: annotation`으로 기존 Pod·Service의 instance 라벨을 보존한다. 서버는 ClusterIP이며 외부 Ingress는 생성하지 않는다.

비공개 Git 저장소라면 Argo CD의 Settings → Repositories에서 읽기 권한을 먼저 연결한다. 토큰·SSH 개인키는 Git에 저장하지 않는다.

Project와 앱 초기 등록:

```sh
kubectl kustomize argocd
kubectl apply -k argocd
kubectl get applications -n argocd
```

등록하면 자동 동기화가 시작된다. 각 Application의 Sync·Health 상태와 기존 리소스의 차이를 확인한다. AppProject는 앱 리소스 종류와 기존 4개 Namespace만 허용하므로, 신규 Namespace나 다른 리소스 종류를 추가할 때는 프로젝트 설정과 인프라 구성을 함께 갱신한다.

UI에 로컬로 접속하려면:

```sh
kubectl -n argocd port-forward svc/argocd-server 8080:443
```

브라우저에서 `https://localhost:8080`으로 접속한다. 이후 앱을 Argo CD로 관리하면 앱 배포·롤백은 Git 변경으로 수행한다. 기존 앱 Helm 릴리스 기록은 남지만 Argo CD는 `helm template`으로 렌더링한 리소스를 직접 동기화하므로, 과거 Helm 기록이 Argo CD의 최신 상태를 나타내지는 않는다. 전환한 앱에 Helm upgrade·rollback·uninstall을 병행하지 않는다.

## 앱 코드와 이미지 배포 흐름

```text
BE·AI 소스 저장소 변경
→ CI가 테스트·이미지 빌드
→ ECR에 푸시하고 새 image digest 확인
→ CLOUD의 해당 역할 values에서 image.digest 갱신
→ 감시 브랜치에 커밋·푸시 또는 PR 병합
→ Argo CD가 감지·동기화
→ Deployment의 이미지 변경으로 새 Pod 배포
```

이미지를 ECR에 푸시하는 것만으로 배포되지는 않는다. 현재 values는 digest로 이미지를 고정하므로 CLOUD의 digest도 갱신해야 한다. 현재 BE 이미지 하나를 6개 Spring 역할이 공유하고, AI 이미지 하나를 6개 FastAPI 역할이 공유한다. 같은 이미지를 유지하는 정책이면 각 그룹의 역할 파일을 한 변경에서 함께 갱신한다.

BE·AI Jenkins는 dev에서 staging values, main에서 prod values의 tag/digest만 갱신한다. 두 환경의 Argo CD는 CLOUD/main을 추적하며 각자의 로컬 클러스터에 적용한다. Jenkins는 각 환경 Argo Application을 읽어서 rollout 완료를 기다린다. [Jenkins 연결 범위](ci/README.md).

AI CI는 다섯 서비스만 함께 갱신하며 image-worker는 별도 관리한다. GitOps 코드 병합과 Jenkins credential·권한·자동 flag 활성화는 별도 단계다. 실제 자동배포 완료 여부는 Jenkins 배포 산출물로 확인한다.

## staging 기존 앱의 고정 커밋 해제

staging 전용 values를 CLOUD/main에 먼저 병합한다. 이 파일은 기존 staging의 이미지·리소스·ConfigMap·시크릿 참조·Ingress를 보존한다. 새 Argo CD를 만들거나 prod Argo에 원격 클러스터를 등록하지 않는다. staging context를 명시해 기존 12개 Application을 갱신한다.

```sh
kubectl --context arn:aws:eks:ap-northeast-2:975779326240:cluster/star-EKS-v3-staging kustomize argocd/staging
kubectl --context arn:aws:eks:ap-northeast-2:975779326240:cluster/star-EKS-v3-staging apply -k argocd/staging
```

기존 live Application의 `spec.source.helm.valuesObject`가 남으면 Git values보다 우선한다. 최초 전환 시 old source를 확인한 JSON Patch로 `spec.source` 전체를 staging manifest의 source로 교체해 inline override를 제거한다. `targetRevision: main`, staging valueFiles, 기존 releaseName이 최종 source에 있는지 확인한다. 그 후 위 Kustomize 설정을 유지한다. 두 등록 진입점을 반대 환경에 적용하지 않는다.

ConfigMap과 Pod template이 현재와 같으면 이 전환만으로 Pod 교체나 노드 증설이 발생하지 않는다. 새 이미지의 후속 rolling deploy에는 해당 노드 풀의 여유 용량 또는 승인된 Cluster Autoscaler 상한이 필요하다. HPA는 Pod 개수만 조절한다.

## 로컬 검증

```sh
kubectl kustomize argocd
helm template argocd argo-cd \
  --repo https://argoproj.github.io/argo-helm \
  --version 10.17.1 --namespace argocd \
  -f argocd/bootstrap/values.yaml
```

Application 12개는 각자 기존 차트와 역할 파일 하나를 사용한다. Secret 비밀값을 복사하지 않고 현재 ExternalSecret 참조를 유지한다. [현재 역할별 기본값](../manifest/helm/star23-service/values/README.md).

참고: [자동 동기화](https://argo-cd.readthedocs.io/en/stable/user-guide/auto_sync/), [Helm 연결](https://argo-cd.readthedocs.io/en/stable/user-guide/helm/), [AppProject](https://argo-cd.readthedocs.io/en/stable/user-guide/projects/), [공식 Argo CD Helm 차트](https://github.com/argoproj/argo-helm/tree/main/charts/argo-cd).
