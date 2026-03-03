#!/usr/bin/env bash
# ==============================================================================
# 31-setup-gitops-repo.sh  (v2 — 로컬 파일 방식)
#
# 역할: gitops-repo에 Kustomize base/overlays 구조 생성 + Argo CD가 바라볼 구조 완성
# 실행 위치: Master Node (k8s-master)
# 전제 조건: .env.gitops-lab 파일 존재, 30-setup-app-repo.sh 완료
#
# ──────────────────────────────────────────────────────────────────────────────
# [v1 → v2 핵심 변경]
#   v1: base/kustomization.yaml 이 내 GitHub raw URL 을 원격 참조
#       → 문제: Argo CD가 GitHub 파일을 직접 추적 못 함
#              GitHub 수정 → GitLab → 클러스터 반영 경로가 불명확
#              리소스 requests/limits 수정 후 Sync 해도 반영 안 되는 현상 발생
#
#   v2: Google Online Boutique 공식 레포에서 kubernetes-manifests/*.yaml 을 직접 clone
#       → 수정된 파일을 gitops-repo/apps/boutique/base/ 에 로컬로 저장
#       → base/kustomization.yaml 이 ./adservice.yaml 등 로컬 파일만 참조
#       → GitHub 참조 완전 제거 (단순화)
#       → 이후 리소스 수정: base/*.yaml 파일 직접 편집 → commit → push → Argo CD Sync
#
# 생성되는 구조:
#   apps/boutique/
#     base/
#       adservice.yaml
#       cartservice.yaml
#       ... (10개 서비스, loadgenerator 제외)
#       kustomization.yaml  ← 로컬 파일만 참조
#     overlays/
#       dev/
#         kustomization.yaml  ← CI가 이미지 태그를 업데이트하는 파일
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

# ==============================================================================
# [안전망] GITLAB_CA_CERT 상대 경로 → 절대 경로 변환
# 이 스크립트는 내부에서 cd "$WORK_DIR" 으로 디렉터리를 이동하므로
# 상대 경로가 .env에 남아있으면 git push 시 SSL CA 오류 발생
# ==============================================================================
if [[ -n "${GITLAB_CA_CERT:-}" && "${GITLAB_CA_CERT}" != /* ]]; then
  _env_dir="$(cd "$(dirname "$(realpath "$ENV_FILE")")" && pwd)"
  GITLAB_CA_CERT="$(realpath "${_env_dir}/${GITLAB_CA_CERT}")"
  warn "⚠️  GITLAB_CA_CERT 상대 경로 감지 → 절대 경로로 변환: ${GITLAB_CA_CERT}"
fi

: "${GITLAB_URL:?}"
: "${GITLAB_CA_CERT:?}"
: "${GITOPS_PUSH_USER:?}"
: "${GITOPS_PUSH_TOKEN:?}"
: "${GROUP:?}"

GITOPS_PROJECT="${GITOPS_PROJECT:-gitops-repo}"
GITOPS_REPO_URL="${GITLAB_URL}/${GROUP}/${GITOPS_PROJECT}.git"
REGISTRY_HOSTPORT="${REGISTRY_HOSTPORT:?REGISTRY_HOSTPORT가 env에 없습니다}"

TARGET_NS="${TARGET_NS:-boutique}"
say "✅ 배포 대상 namespace: ${TARGET_NS}"

# loadgenerator 제외 10개
BOUTIQUE_SERVICES="adservice cartservice checkoutservice currencyservice emailservice frontend paymentservice productcatalogservice recommendationservice shippingservice"

# 구글 원본 레지스트리 prefix (kustomize images.name 에서 사용되는 원본 이름)
UPSTREAM_REGISTRY="us-central1-docker.pkg.dev/google-samples/microservices-demo"

APP_PROJECT="${APP_PROJECT:-app-repo}"
OUR_REGISTRY="${REGISTRY_HOSTPORT}/${GROUP}/${APP_PROJECT}"

# ==============================================================================
# [v2 신규] Google Online Boutique 공식 kubernetes-manifests 출처
# ==============================================================================
BOUTIQUE_K8S_REPO="https://github.com/GoogleCloudPlatform/microservices-demo.git"
BOUTIQUE_K8S_BRANCH="main"
BOUTIQUE_K8S_MANIFESTS_PATH="kubernetes-manifests"

WORK_DIR="/tmp/gitops-setup-$$"

echo "=================================================="
echo " Step 2. gitops-repo Kustomize 구조 생성 (v2 로컬 파일 방식)"
echo "=================================================="
warn "  GitLab URL    : ${GITLAB_URL}"
warn "  gitops-repo   : ${GROUP}/${GITOPS_PROJECT}"
warn "  Registry      : ${OUR_REGISTRY}"
warn "  CA 인증서     : ${GITLAB_CA_CERT}"
warn "  매니페스트 출처: ${BOUTIQUE_K8S_REPO} (kubernetes-manifests/)"
echo ""
warn "  [v2 변경] GitHub raw URL 참조 제거 → 로컬 YAML 파일 직접 저장"
warn "  이후 리소스 수정은 base/*.yaml 편집 후 commit+push → Argo CD Sync"
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

# ---------- gitops-repo clone ----------
AUTH_URL="$(echo "$GITOPS_REPO_URL" | sed "s#https://#https://${GITOPS_PUSH_USER}:${GITOPS_PUSH_TOKEN}@#")"

say "\n[1/5] gitops-repo clone 중..."
git clone "$AUTH_URL" gitops 2>/dev/null || {
  warn "  clone 실패 → 빈 repo로 초기화"
  mkdir gitops
  cd gitops
  git init -b main
  git remote add origin "$AUTH_URL"
  cd "$WORK_DIR"
}
cd gitops
git config user.name "gitlab-ci-setup"
git config user.email "setup@local"
git checkout main 2>/dev/null || git checkout -b main

# ==============================================================================
# [v2 신규] Google Online Boutique kubernetes-manifests clone
# sparse checkout 으로 kubernetes-manifests/ 만 가져옴
# ==============================================================================
say "\n[2/5] Google Online Boutique kubernetes-manifests clone 중..."
say "     출처: ${BOUTIQUE_K8S_REPO}"

git clone \
  --depth=1 \
  --filter=blob:none \
  --sparse \
  --branch "$BOUTIQUE_K8S_BRANCH" \
  "$BOUTIQUE_K8S_REPO" \
  "${WORK_DIR}/boutique-k8s"

cd "${WORK_DIR}/boutique-k8s"
git sparse-checkout set "$BOUTIQUE_K8S_MANIFESTS_PATH"

MANIFESTS_DIR="${WORK_DIR}/boutique-k8s/${BOUTIQUE_K8S_MANIFESTS_PATH}"
say "✅ kubernetes-manifests 다운로드 완료: ${MANIFESTS_DIR}"

# 디렉터리 확인
ls -la "$MANIFESTS_DIR"

cd "${WORK_DIR}/gitops"

# ---------- base 디렉터리 구성 ----------
say "\n[3/5] Kustomize base 구성 중 (로컬 YAML 파일 복사)..."
mkdir -p apps/boutique/base
mkdir -p apps/boutique/overlays/dev

# ==============================================================================
# [v2] 서비스별 YAML 파일을 base/ 에 로컬로 복사
#
# Google 원본 kubernetes-manifests/ 구조:
#   - adservice.yaml, cartservice.yaml ... (서비스별 Deployment + Service 포함)
#   - loadgenerator.yaml (제외)
#
# 복사 후 base/kustomization.yaml 은 ./adservice.yaml 등 로컬 파일만 참조
# → Argo CD가 gitops-repo 안의 파일을 직접 추적 가능
# → 리소스 수정: base/adservice.yaml 편집 → commit → push → Sync
# ==============================================================================
COPIED_SERVICES=""
MISSING_SERVICES=""

for svc in $BOUTIQUE_SERVICES; do
  SRC_YAML="${MANIFESTS_DIR}/${svc}.yaml"
  DST_YAML="apps/boutique/base/${svc}.yaml"

  if [[ -f "$SRC_YAML" ]]; then
    cp "$SRC_YAML" "$DST_YAML"
    say "  ✅ 복사: ${svc}.yaml"
    COPIED_SERVICES="${COPIED_SERVICES} ${svc}"
  else
    warn "  ⚠️  파일 없음: ${SRC_YAML} → 건너뜀"
    MISSING_SERVICES="${MISSING_SERVICES} ${svc}"
  fi
done

if [[ -n "$MISSING_SERVICES" ]]; then
  err "❌ 아래 서비스 YAML 파일을 찾지 못했습니다:${MISSING_SERVICES}"
  err "   Google 레포 구조가 변경되었을 수 있습니다."
  err "   ${MANIFESTS_DIR} 내 파일명을 확인하세요:"
  ls "$MANIFESTS_DIR"
  exit 1
fi

say "✅ 10개 서비스 YAML 복사 완료"

# ==============================================================================
# [v2] base/kustomization.yaml — 로컬 파일만 참조 (URL 제거)
#
# 이전(v1): resources 에 GitHub raw URL 기재
# 이후(v2): resources 에 ./adservice.yaml 등 로컬 경로 기재
#
# 리소스(requests/limits) 수정 방법:
#   1. gitops-repo를 로컬에 clone
#   2. apps/boutique/base/{서비스명}.yaml 편집
#   3. git commit && git push
#   4. Argo CD UI 에서 Sync (또는 auto-sync 대기)
# ==============================================================================
RESOURCES_BLOCK=""
for svc in $BOUTIQUE_SERVICES; do
  RESOURCES_BLOCK="${RESOURCES_BLOCK}  - ./${svc}.yaml\n"
done

printf "# ==============================================================================\n" > apps/boutique/base/kustomization.yaml
printf "# base/kustomization.yaml  (v2 — 로컬 파일 참조)\n" >> apps/boutique/base/kustomization.yaml
printf "#\n" >> apps/boutique/base/kustomization.yaml
printf "# 출처: Google Online Boutique kubernetes-manifests/ (직접 clone)\n" >> apps/boutique/base/kustomization.yaml
printf "#\n" >> apps/boutique/base/kustomization.yaml
printf "# 리소스(requests/limits) 수정 방법:\n" >> apps/boutique/base/kustomization.yaml
printf "#   1. 이 레포 clone\n" >> apps/boutique/base/kustomization.yaml
printf "#   2. apps/boutique/base/{서비스}.yaml 편집\n" >> apps/boutique/base/kustomization.yaml
printf "#   3. git commit && git push\n" >> apps/boutique/base/kustomization.yaml
printf "#   4. Argo CD Sync (또는 auto-sync 대기)\n" >> apps/boutique/base/kustomization.yaml
printf "# ==============================================================================\n" >> apps/boutique/base/kustomization.yaml
printf "apiVersion: kustomize.config.k8s.io/v1beta1\n" >> apps/boutique/base/kustomization.yaml
printf "kind: Kustomization\n\n" >> apps/boutique/base/kustomization.yaml
printf "resources:\n" >> apps/boutique/base/kustomization.yaml
printf "${RESOURCES_BLOCK}" >> apps/boutique/base/kustomization.yaml

say "  ✅ base/kustomization.yaml 생성 (로컬 파일 참조)"

# ---------- overlays/dev/kustomization.yaml ----------
say "\n[4/5] Kustomize overlay(dev) 구성 중..."

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

namespace: ${TARGET_NS}

resources:
  - ../../base

# ---------------------------------------------------------------------------
# imagePullSecrets 전체 Deployment에 주입
# ---------------------------------------------------------------------------
patches:
  - patch: |-
      apiVersion: apps/v1
      kind: Deployment
      metadata:
        name: not-used
      spec:
        template:
          spec:
            imagePullSecrets:
              - name: gitlab-regcred
    target:
      kind: Deployment

  # ---------------------------------------------------------------------------
  # frontend-external Service 타입 변경
  # LoadBalancer → ClusterIP (MetalLB IP 충돌 방지, Ingress-Nginx로 통일)
  # ---------------------------------------------------------------------------
  - patch: |-
      apiVersion: v1
      kind: Service
      metadata:
        name: frontend-external
      spec:
        type: ClusterIP
    target:
      kind: Service
      name: frontend-external

# ---------------------------------------------------------------------------
# 이미지 교체 테이블
# name    : upstream 원본 이미지 이름
# newName : 우리 GitLab Registry 경로
# newTag  : CI_COMMIT_SHORT_SHA (CI 파이프라인이 자동 갱신)
# ---------------------------------------------------------------------------
images:
${IMAGES_BLOCK}
EOF

say "  ✅ overlays/dev/kustomization.yaml 생성 (10개 서비스)"

# ---------- README ----------
cat > README.md <<'EOF'
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
EOF

cat > .gitignore <<'EOF'
*.env
*.env.*
.env.gitops-lab
EOF

# ---------- push ----------
say "\n[5/5] gitops-repo push 중..."
git add -A
git status

if git diff --cached --quiet; then
  warn "  변경 없음 → push 스킵 (이미 최신 상태)"
else
  git commit -m "feat: v2 로컬 YAML 방식으로 전환

변경 내용:
- base/: Google Online Boutique kubernetes-manifests 직접 clone → 로컬 저장
- base/kustomization.yaml: GitHub raw URL 참조 제거 → 로컬 파일 참조
- overlays/dev: namespace, imagePullSecrets, frontend-external, 이미지 교체 유지

배경:
- v1 GitHub URL 방식에서 리소스 수정 후 Argo CD Sync 미반영 문제 발생
- Argo CD가 gitops-repo 내부 파일만 추적하도록 단순화

Setup: 31-setup-gitops-repo.sh v2"

  git push -u origin main
fi

say "\n✅ gitops-repo 구성 완료! (v2 로컬 파일 방식)"

echo ""
echo "=================================================="
echo " 🎉 Step 2 완료: gitops-repo Kustomize 구조 생성 (v2)"
echo "=================================================="
echo "  GitLab URL    : ${GITLAB_URL}/${GROUP}/${GITOPS_PROJECT}"
echo "  Argo CD path  : apps/boutique/overlays/dev"
echo "  base 구조     : 로컬 YAML 파일 (10개 서비스)"
echo ""
echo "  [리소스 수정 방법]"
echo "  1. gitops-repo clone"
echo "  2. apps/boutique/base/{서비스}.yaml 편집"
echo "  3. git commit && git push"
echo "  4. Argo CD Sync"
echo ""
echo "  → 다음 단계: ./32-setup-gitlab-ci.sh 실행"
echo "=================================================="
