# HPA 설정

`templates/hpa.yaml`은 앱별 Pod 개수를 조정하는 `autoscaling/v2` 리소스다. 루트 `values.yaml`의 `autoscaling.enabled` 기본값은 `false`이므로 기존 12개 앱에는 HPA가 생성되지 않는다.

## 앱별 설정

`values/<릴리스>.yaml`에 다음처럼 추가한다. 아래 수치는 설정 예시이며 운영 용량을 확정한 값이 아니다.

```yaml
autoscaling:
  enabled: true
  minReplicas: 1
  maxReplicas: 3
  targetCPUUtilizationPercentage: 70
  behavior:
    scaleDown:
      stabilizationWindowSeconds: 300
```

CPU 목표는 `resources.requests.cpu` 대비 평균 사용률이다. CPU 요청이 `500m`일 때 `70`은 평균 `350m`에 해당한다. CPU 요청량을 바꾸면 같은 부하에서도 증감 기준이 바뀐다.

HPA를 활성화하면 Deployment의 `spec.replicas`를 렌더링하지 않는다. 이후 Pod 개수는 HPA가 관리하며 `replicaCount`는 사용하지 않는다. HPA를 비활성화하면 다시 `replicaCount`로 고정된다. 처음 전환할 때는 실제 Pod 수와 `minReplicas`를 확인하고 동기화한다.

## 활성화 전 확인

- Metrics API가 준비되어 있고 `kubectl top pods -n <namespace>`가 동작하는지 확인한다. 이 변경에는 Metrics Server 설치를 포함하지 않는다.
- 컨테이너의 CPU requests를 지정한다. 현재 역할 파일과 공통 values의 리소스 설정을 함께 확인한다.
- scheduler·consumer·배치 작업이 여러 Pod에서 중복 실행되어도 되는지 확인한다. WebSocket은 여러 Pod 사이의 메시지 전달과 연결 종료·재접속 처리를 확인한다.
- 해당 앱의 `nodeSelector`와 일치하는 노드 그룹에 용량이 있어야 한다. `maxReplicas`만 늘려도 노드 그룹 최대 크기가 늘어나지는 않는다.

## 검증과 반영

저장소 루트에서 앱별 파일을 지정하여 렌더링한다.

```sh
helm lint ./manifest/helm/star23-service -f ./manifest/helm/star23-service/values/chat-api.yaml
helm template chat-api ./manifest/helm/star23-service -n chat -f ./manifest/helm/star23-service/values/chat-api.yaml
```

앱별 설정을 main에 병합하면 기존 Argo CD Application이 변경을 자동 동기화한다. 적용 후 상태는 다음 명령으로 확인한다.

```sh
kubectl get hpa -n chat
kubectl describe hpa chat-api -n chat
```

노드 증감은 별도 [Cluster Autoscaler 설정](../cluster-autoscaler/README.md)으로 관리한다.

참고: [Kubernetes HPA 공식 문서](https://kubernetes.io/docs/concepts/workloads/autoscaling/horizontal-pod-autoscale/).
