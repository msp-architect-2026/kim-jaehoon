# GitOps Repository — Online Boutique (v2 로컬 파일 방식)

## 구조

```
apps/boutique/
  base/
    adservice.yaml          ← Google Online Boutique 원본 매니페스트 (로컬 저장)
    cartservice.yaml
    ... (10개 서비스)
    kustomization.yaml      ← 로컬 파일 참조 (./adservice.yaml 등)
  overlays/
    dev/
      kustomization.yaml    ← CI가 이미지 태그를 자동 업데이트
```

## v2 변경 사유

- v1: base/kustomization.yaml 이 GitHub raw URL 참조
  - 문제: Argo CD가 GitHub 파일을 직접 추적 불가
  - 문제: 리소스 수정 후 Sync 해도 반영 안 되는 현상
- v2: Google Online Boutique kubernetes-manifests/ 를 직접 clone → 로컬 저장
  - 장점: Argo CD가 이 레포 안의 파일만 추적 (단순 명확)
  - 장점: 파일 수정 → commit → push → Sync 으로 즉시 반영

## 리소스(requests/limits) 수정 방법

```bash
# 1. gitops-repo clone
git clone <gitops-repo-url>
cd gitops-repo

# 2. 원하는 서비스 YAML 편집
vi apps/boutique/base/adservice.yaml
# resources.requests.cpu / memory 값 수정

# 3. commit & push
git add apps/boutique/base/adservice.yaml
git commit -m "fix: adservice 리소스 limits 조정"
git push

# 4. Argo CD Sync
# UI: Sync 버튼 클릭
# 또는 auto-sync 켜져 있으면 자동 반영
```

## 이미지 태그 업데이트 흐름

```
app-repo 코드 push
  → GitLab CI 빌드
  → Registry push
  → gitops-repo overlays/dev/kustomization.yaml 태그 업데이트 (CI 자동)
  → Argo CD auto-sync → K8s rolling update
```

## 주의사항

- `overlays/dev/kustomization.yaml`의 `images[].newTag`는 CI가 자동 관리합니다.
- 수동으로 수정하지 마세요.
- 리소스 수정은 `base/*.yaml` 파일을 직접 편집하세요.
