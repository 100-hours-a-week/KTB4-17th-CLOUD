# Cluster Autoscaler 설정

`values.yaml`은 `star-EKS-v3`에 이미 설치된 CA의 사용자 설정을 2026-11-11에 읽어 저장한 파일이다. 자체 차트를 복사하지 않고 공식 `cluster-autoscaler` 차트를 사용한다.

| 항목 | 기존 설치 기준 |
| --- | --- |
| Helm 저장소 | `https://kubernetes.github.io/autoscaler` |
| 차트 / 버전 | `cluster-autoscaler` / `9.60.0` |
| 앱 버전 | `1.37.0` |
| 릴리스 / Namespace | `cluster-autoscaler` / `kube-system` |
| ServiceAccount | `cluster-autoscaler` |
| IAM 연결 | 기존 `ClusterAutoscalerRole-star-EKS-v3` IRSA |

## 관리 범위

- 앱별 최소·최대 Pod 개수: [앱 HPA](../star23-service/AUTOSCALING.md).
- CA 클러스터 탐색·리소스·배치·실행 옵션: 이 폴더의 `values.yaml`.
- 노드 그룹의 `minSize`·`maxSize`, 인스턴스 유형·레이블·taint·탐색 태그: AWS EKS/ASG 인프라 설정. Terraform으로 관리한다면 기존 자원의 관리 여부와 import부터 확인한다.
- IAM Role 정책·신뢰 관계: AWS IAM 인프라 설정. 이 values는 기존 Role ARN을 참조하며 IAM Role을 생성하지 않는다.

`nodeSelector.workload-class: general`은 CA 자체의 실행 위치다. 앱 Pod가 배치될 노드 그룹은 앱의 nodeSelector/affinity, taint/toleration, 자원 요청량과 CA 탐색 설정에 따라 결정된다. 노드 그룹 최대 크기가 1이면 CA도 1대 이상으로 늘릴 수 없다. 이 변경에서 노드 그룹 크기는 수정하지 않았다.

## 렌더링 검증

저장소 루트에서 실행한다. 아래 명령은 설치하지 않는다.

```sh
helm template cluster-autoscaler cluster-autoscaler --repo https://kubernetes.github.io/autoscaler --version 9.60.0 --namespace kube-system -f manifest/helm/cluster-autoscaler/values.yaml
kubectl kustomize argocd
```

## Argo CD 연결

`argocd/applications/platform/cluster-autoscaler.yaml`은 공식 차트와 Git main의 이 values를 결합한다. `star23-platform` Project는 `kube-system`과 CA에 필요한 리소스 종류를 허용한다. 기존 앱 Project에는 클러스터 권한을 추가하지 않는다.

파일을 main에 반영한 뒤 기존 초기 등록 명령 `kubectl apply -k argocd`로 Project와 Application을 등록한다. **CA Application은 자동 동기화가 꺼져 있다.** 등록만으로 기존 CA를 변경하지 않으며, Git values 변경도 수동 동기화 전에는 반영되지 않는다.

최초 동기화 전 다음을 확인한다.

1. 기존 `helm get values cluster-autoscaler -n kube-system`과 이 파일, 기존 `helm get manifest`와 Argo CD 렌더링 결과를 비교한다. 릴리스 이름·리소스 이름·ServiceAccount·IAM ARN을 유지한다.
2. IRSA 권한·신뢰 관계, 노드 그룹의 자동 탐색 태그, 노드 그룹 최소·최대 크기를 확인한다. CA 버전은 EKS의 Kubernetes minor 버전과 맞춘다.
3. Argo CD에서 예상 변경을 검토한 뒤 수동 Sync한다. 다른 Argo CD Application이 소유한 리소스가 있으면 `FailOnSharedResource` 오류를 먼저 해결한다.

전환 후에는 CA에 Helm upgrade/rollback/uninstall을 병행하지 않는다. 이후 자동 동기화가 필요하면 이 Application의 `automated.enabled` 등 정책을 결정하여 변경하고 Application 정의를 다시 적용한다. 이 구성은 Application 정의 자체를 자동 관리하는 부모 Application을 포함하지 않는다.

이 변경은 로컬 파일 작성이며 AWS 적용·노드 증감·CA 관리 주체 전환을 수행하지 않는다.

참고: [AWS CA 운영 가이드](https://docs.aws.amazon.com/eks/latest/best-practices/cas.html), [공식 Helm 차트](https://github.com/kubernetes/autoscaler/tree/master/charts/cluster-autoscaler), [Argo CD 다중 소스](https://argo-cd.readthedocs.io/en/stable/user-guide/multiple_sources/).
