#!/usr/bin/env bash
# ==============================================================================
# 31-setup-gitops-repo.sh
# 역할: gitops-repo에 Kustomize base/overlays 구조 생성 + Argo CD가 바라볼 구조 완성
# 실행 위치: Mini PC (192.168.10.47)
# 전제 조건: .env.gitops-lab 파일 존재, 30-setup-app-repo.sh 완료
#
# 생성되는 구조:
#   apps/boutique/
#     base/
#       kustomization.yaml   ← 원본 이미지 정의 (upstream 주소 기준)
#       [각 서비스 deployment/service yaml]
#     overlays/
#       dev/
#         kustomization.yaml ← CI가 태그를 업데이트하는 파일
# ==============================================================================
set -euo pipefail

say()  { echo -e "\033[0;32m$*\033[0m"; }
warn() { echo -e "\033[1;33m$*\033[0m"; }
err()  { echo -e "\033[0;31m$*\033[0m"; }
need() { command -v "$1" >/dev/null 2>&1 || { err "❌ '$1' 필요"; exit 1; }; }

need git
need curl

# ---------- env 로드 ----------
ENV_FILE="${1:-./.env.gitops-lab}"
[[ -f "$ENV_FILE" ]] || { err "❌ env 파일 없음: $ENV_FILE"; exit 1; }
# shellcheck disable=SC1090
source "$ENV_FILE"

: "${GITLAB_URL:?}"
: "${GITLAB_CA_CERT:?}"
: "${GITOPS_PUSH_USER:?}"
: "${GITOPS_PUSH_TOKEN:?}"
: "${GROUP:?}"

GITOPS_PROJECT="${GITOPS_PROJECT:-gitops-repo}"
GITOPS_REPO_URL="${GITLAB_URL}/${GROUP}/${GITOPS_PROJECT}.git"
REGISTRY_HOSTPORT="${REGISTRY_HOSTPORT:?REGISTRY_HOSTPORT가 env에 없습니다}"

# loadgenerator 제외 10개
BOUTIQUE_SERVICES="adservice cartservice checkoutservice currencyservice emailservice frontend paymentservice productcatalogservice recommendationservice shippingservice"

# 구글 원본 레지스트리 prefix (kustomize images.name 에서 사용되는 원본 이름)
UPSTREAM_REGISTRY="us-central1-docker.pkg.dev/google-samples/microservices-demo"

# CI가 push할 우리 레지스트리 prefix
# CI_REGISTRY_IMAGE = REGISTRY_HOSTPORT/GROUP/APP_PROJECT
APP_PROJECT="${APP_PROJECT:-app-repo}"
OUR_REGISTRY="${REGISTRY_HOSTPORT}/${GROUP}/${APP_PROJECT}"

WORK_DIR="/tmp/gitops-setup-$$"

echo "=================================================="
echo " Step 2. gitops-repo Kustomize 구조 생성"
echo "=================================================="
warn "  GitLab URL    : ${GITLAB_URL}"
warn "  gitops-repo   : ${GROUP}/${GITOPS_PROJECT}"
warn "  Registry      : ${OUR_REGISTRY}"
echo ""
read -rp "계속할까요? (y/n) [기본 n]: " OK
OK="${OK:-n}"
[[ "$OK" =~ ^[Yy]$ ]] || { echo "취소"; exit 0; }

[[ -f "$GITLAB_CA_CERT" ]] || { err "❌ CA 파일 없음: $GITLAB_CA_CERT"; exit 1; }

export GIT_SSL_CAINFO="$GITLAB_CA_CERT"
git config --global http.sslCAInfo "$GITLAB_CA_CERT"

rm -rf "$WORK_DIR"
mkdir -p "$WORK_DIR"
trap 'rm -rf "$WORK_DIR"' EXIT
cd "$WORK_DIR"

# ---------- gitops-repo clone (이미 내용 있을 수 있음 → 멱등) ----------
AUTH_URL="$(echo "$GITOPS_REPO_URL" | sed "s#https://#https://${GITOPS_PUSH_USER}:${GITOPS_PUSH_TOKEN}@#")"

say "\n[1/4] gitops-repo clone 중..."
# 빈 repo여도 에러 없이 처리
git clone "$AUTH_URL" gitops 2>/dev/null || {
  warn "  clone 실패 → 빈 repo로 초기화"
  mkdir gitops
  cd gitops
  git init -b main
  git remote add origin "$AUTH_URL"
  cd "$WORK_DIR"
}
cd gitops

# git 설정
git config user.name "gitlab-ci-setup"
git config user.email "setup@local"

# main 브랜치 보장
git checkout main 2>/dev/null || git checkout -b main

# ---------- base 디렉터리 구성 ----------
say "\n[2/4] Kustomize base 구성 중..."
mkdir -p apps/boutique/base
mkdir -p apps/boutique/overlays/dev

# ── base/kustomization.yaml ──
# Online Boutique의 원본 쿠버네티스 매니페스트를 원격 참조
# 로컬에 yaml을 복사하지 않고, upstream raw URL을 resource로 지정 (경량 관리)
cat > apps/boutique/base/kustomization.yaml <<EOF
# ==============================================================================
# base/kustomization.yaml
# 역할: Online Boutique 원본 매니페스트를 upstream에서 참조
#       이미지 이름은 여기서 정의 (원본 → 우리 레지스트리로 교체 기반)
# ⚠️  이 파일을 직접 수정하지 마세요.
#     태그 업데이트는 overlays/dev/kustomization.yaml에서만 합니다.
# ==============================================================================
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

# upstream 공식 매니페스트를 직접 참조
resources:
  - https://raw.githubusercontent.com/GoogleCloudPlatform/microservices-demo/main/release/kubernetes-manifests.yaml

# loadgenerator는 배포에서 제외
patches:
  - patch: |-
      \$patch: delete
      apiVersion: apps/v1
      kind: Deployment
      metadata:
        name: loadgenerator
    target:
      kind: Deployment
      name: loadgenerator
  - patch: |-
      \$patch: delete
      apiVersion: v1
      kind: Service
      metadata:
        name: loadgenerator
    target:
      kind: Service
      name: loadgenerator
EOF

say "  ✅ base/kustomization.yaml 생성"

# ── overlays/dev/kustomization.yaml ──
# CI 파이프라인이 이 파일의 images[].newTag 를 업데이트함
say "\n[3/4] Kustomize overlay(dev) 구성 중..."

# images 블록 동적 생성
IMAGES_BLOCK=""
for svc in $BOUTIQUE_SERVICES; do
  IMAGES_BLOCK="${IMAGES_BLOCK}
  - name: ${UPSTREAM_REGISTRY}/${svc}
    newName: ${OUR_REGISTRY}/${svc}
    newTag: latest"
done

cat > apps/boutique/overlays/dev/kustomization.yaml <<EOF
# ==============================================================================
# overlays/dev/kustomization.yaml
# 역할: dev 환경 배포 설정
#       CI 파이프라인이 images[].newTag 를 CI_COMMIT_SHORT_SHA 로 자동 업데이트
#
# ⚠️  images[].newTag 는 CI가 자동으로 관리합니다. 수동으로 수정하지 마세요.
# ==============================================================================
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

namespace: demo

resources:
  - ../../base

# ---------------------------------------------------------------------------
# 이미지 교체 테이블
# name    : upstream 원본 이미지 이름 (CI의 UPSTREAM_PREFIX와 반드시 일치)
# newName : 우리 GitLab Registry 경로
# newTag  : CI_COMMIT_SHORT_SHA (CI 파이프라인이 자동 갱신)
# ---------------------------------------------------------------------------
images:
${IMAGES_BLOCK}
EOF

say "  ✅ overlays/dev/kustomization.yaml 생성 (10개 서비스)"

# ---------- README ----------
cat > README.md <<'EOF'
# GitOps Repository — Online Boutique

## 구조

```
apps/boutique/
  base/                        # upstream 원본 매니페스트 참조
    kustomization.yaml
  overlays/
    dev/                       # Argo CD가 바라보는 경로
      kustomization.yaml       # ← CI가 이미지 태그를 자동 업데이트
```

## 이미지 태그 업데이트 흐름

```
app-repo 코드 push
  → GitLab CI 빌드
  → Registry push
  → gitops-repo overlays/dev/kustomization.yaml 태그 업데이트
  → Argo CD auto-sync → K8s rolling update
```

## 주의사항

- `overlays/dev/kustomization.yaml`의 `images[].newTag`는 CI가 자동 관리합니다.
- 수동으로 수정하지 마세요. 수정이 필요하면 app-repo에 커밋하세요.
EOF

# ---------- .gitignore ----------
cat > .gitignore <<'EOF'
*.env
*.env.*
.env.gitops-lab
EOF

# ---------- push ----------
say "\n[4/4] gitops-repo push 중..."
git add -A
git status

# 변경 없으면 스킵
if git diff --cached --quiet; then
  warn "  변경 없음 → push 스킵 (이미 최신 상태)"
else
  git commit -m "feat: init Kustomize base/overlays structure for Online Boutique

- base: upstream kubernetes-manifests.yaml 참조
- overlays/dev: 10개 서비스 이미지 교체 테이블 초기화
- loadgenerator 제외 (Deployment/Service 패치로 삭제)
- CI 파이프라인이 images[].newTag 자동 갱신

Setup: 31-setup-gitops-repo.sh"

  git push -u origin main
fi

say "\n✅ gitops-repo 구성 완료!"

echo ""
echo "=================================================="
echo " 🎉 Step 2 완료: gitops-repo Kustomize 구조 생성"
echo "=================================================="
echo "  GitLab URL  : ${GITLAB_URL}/${GROUP}/${GITOPS_PROJECT}"
echo "  Argo CD path: apps/boutique/overlays/dev"
echo "  서비스 수   : 10개 (loadgenerator 제외)"
echo ""
echo "  → 다음 단계: ./32-setup-gitlab-ci.sh 실행"
echo "              .gitlab-ci.yml 완성본을 app-repo에 push"
echo "=================================================="

