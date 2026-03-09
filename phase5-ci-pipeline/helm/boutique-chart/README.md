# Boutique Helm Chart

Kustomize → Helm 전환 차트입니다.

## 디렉토리 구조

```
boutique-chart/
├── Chart.yaml
├── values.yaml              # 전체 기본값 (모든 서비스 정의)
├── values-dev.yaml          # dev 환경 오버라이드
├── values-prod.yaml         # prod 환경 오버라이드
├── argocd-application.yaml  # ArgoCD Application 매니페스트
└── templates/
    ├── _helpers.tpl         # 공통 헬퍼 함수
    ├── deployment.yaml      # 모든 서비스 Deployment (루프)
    ├── service.yaml         # 모든 서비스 Service (루프)
    ├── serviceaccount.yaml  # 모든 서비스 SA (루프)
    ├── hpa.yaml             # HPA (enabled: true인 서비스만)
    ├── ingress.yaml         # Ingress
    └── network-policy.yaml  # 전체 NetworkPolicy
```

## 주요 변경 사항 (Kustomize → Helm)

| 항목 | 기존 Kustomize | Helm |
|------|---------------|------|
| 이미지 태그 관리 | overlays/dev/kustomization.yaml의 newTag | values.yaml의 services.<name>.image.tag |
| 환경 분리 | overlays/dev/ | values-dev.yaml / values-prod.yaml |
| 토폴로지 분산 | 미적용 | topologySpreadConstraints 기본 활성화 |

## CI 파이프라인 수정

기존에 `kustomization.yaml`의 `newTag`를 업데이트하던 CI 스크립트를 변경합니다.

### 기존 (Kustomize)
```bash
cd apps/boutique/overlays/dev
kustomize edit set image adservice=192.168.10.47:5050/root/app-repo/adservice:$CI_COMMIT_SHORT_SHA
```

### 변경 후 (Helm)
```bash
# yq 사용
yq e ".services.${SERVICE_NAME}.image.tag = \"${CI_COMMIT_SHORT_SHA}\"" \
  -i apps/boutique/helm/values.yaml

# 또는 sed 사용
sed -i "s/\(name: ${SERVICE_NAME}\)/\1/" apps/boutique/helm/values.yaml
# → 더 안전한 방법은 yq 권장
```

## 로컬 테스트

```bash
# 템플릿 렌더링 확인 (실제 배포 안 함)
helm template boutique ./boutique-chart -f values-dev.yaml

# 문법 검사
helm lint ./boutique-chart

# dry-run 배포
helm install boutique ./boutique-chart -f values-dev.yaml --dry-run

# 실제 배포
helm install boutique ./boutique-chart -f values-dev.yaml -n boutique --create-namespace

# 업그레이드
helm upgrade boutique ./boutique-chart -f values-dev.yaml -n boutique

# 롤백
helm rollback boutique 1 -n boutique
```

## 자주 쓰는 설정 변경

```bash
# 특정 서비스 이미지 태그만 변경
helm upgrade boutique ./boutique-chart \
  --set services.frontend.image.tag=abc1234 -n boutique

# NetworkPolicy 비활성화 (디버깅 시)
helm upgrade boutique ./boutique-chart \
  --set networkPolicy.enabled=false -n boutique

# 토폴로지 분산 끄기
helm upgrade boutique ./boutique-chart \
  --set topologySpreadConstraints.enabled=false -n boutique
```
