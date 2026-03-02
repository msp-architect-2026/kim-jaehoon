#!/usr/bin/env bash
# ==============================================================================
# 31-setup-gitops-repo.sh
# 역할: gitops-repo에 Kustomize base/overlays 구조 생성 + Argo CD가 바라볼 구조 완성
# 실행 위치: Master Node (k8s-master)
# 전제 조건: .env.gitops-lab 파일 존재, 30-setup-app-repo.sh 완료
#
# 생성되는 구조:
#   apps/boutique/
#     base/
#       adservice.yaml / cartservice.yaml ... (서비스별 직접 작성)
#       kustomization.yaml         ← 로컬 파일 참조 + loadgenerator 제외
#     overlays/
#       dev/
#         kustomization.yaml       ← CI가 태그를 업데이트하는 파일
#
# 변경 이력:
#   - upstream URL 참조 방식 → 내 GitHub 레포 URL 참조 방식으로 전환
#     이유: 포트폴리오 증빙 (yaml 파일이 내 GitHub에 직접 존재)
#           yaml 수정 이력이 내 GitHub commit log에 남음
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
# → source 직후 .env 파일 위치 기준으로 절대 경로 변환하여 방어
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

# ==============================================================================
# [장애 ② 수정] TARGET_NS — 20-k8s-bootstrap-phase3.sh가 저장한 값 사용
# .env에 없을 경우 기본값 boutique 사용 (하위 호환)
# ==============================================================================
TARGET_NS="${TARGET_NS:-boutique}"
say "✅ 배포 대상 namespace: ${TARGET_NS}"

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
warn "  CA 인증서     : ${GITLAB_CA_CERT}"
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

# ==============================================================================
# base/kustomization.yaml
# 역할: 내 GitHub 레포에 직접 관리하는 서비스별 yaml 파일 참조
#
# 소스: github.com/msp-architect-2026/kim-jaehoon (devops-lab-infra 브랜치)
# 경로: phase4-gitops-setup/gitops/base/
#
# yaml 수정 방법:
#   → 내 GitHub의 phase4-gitops-setup/gitops/base/*.yaml 직접 수정
#   → commit & push → Argo CD sync 시 자동 반영
# ==============================================================================

GITHUB_BASE_URL="https://raw.githubusercontent.com/msp-architect-2026/kim-jaehoon/devops-lab-infra/phase4-gitops-setup/gitops/base"

cat > apps/boutique/base/kustomization.yaml <<EOF
# ==============================================================================
# base/kustomization.yaml
# 역할: 내 GitHub 레포의 서비스별 yaml 파일을 원격 참조
#
# 출처: github.com/msp-architect-2026/kim-jaehoon (devops-lab-infra)
# 경로: phase4-gitops-setup/gitops/base/
#
# ⚠️  yaml 수정은 내 GitHub 레포에서 직접 합니다.
#     스크립트 재실행 불필요 — GitHub 수정 후 Argo CD가 자동 반영합니다.
# ==============================================================================
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

resources:
  - ${GITHUB_BASE_URL}/adservice.yaml
  - ${GITHUB_BASE_URL}/cartservice.yaml
  - ${GITHUB_BASE_URL}/checkoutservice.yaml
  - ${GITHUB_BASE_URL}/currencyservice.yaml
  - ${GITHUB_BASE_URL}/emailservice.yaml
  - ${GITHUB_BASE_URL}/frontend.yaml
  - ${GITHUB_BASE_URL}/paymentservice.yaml
  - ${GITHUB_BASE_URL}/productcatalogservice.yaml
  - ${GITHUB_BASE_URL}/recommendationservice.yaml
  - ${GITHUB_BASE_URL}/shippingservice.yaml
EOF

say "  ✅ base/kustomization.yaml 생성 (내 GitHub URL 참조)"

# ── overlays/dev/kustomization.yaml ──
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

# [장애 ② 수정] namespace: demo 하드코딩 제거
# 20-k8s-bootstrap-phase3.sh Q4에서 입력한 TARGET_NS 값으로 동적 주입
namespace: ${TARGET_NS}

resources:
  - ../../base

# ---------------------------------------------------------------------------
# [장애 ③ 수정] imagePullSecrets 전체 Deployment에 주입
# 20-k8s-bootstrap-phase3.sh가 생성한 gitlab-regcred secret을 참조
# 프라이빗 레지스트리(GitLab)에서 이미지를 pull하기 위한 인증 정보
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
  # [MetalLB IP 충돌 수정] frontend-external Service 타입 변경
  # upstream 원본: Type=LoadBalancer → MetalLB IP 추가 소모 발생
  # 설계 의도: 외부 진입점은 Ingress-Nginx 단일 VIP로 통일
  #   외부 → MetalLB VIP → Ingress-Nginx → frontend(ClusterIP) → Pod
  # ClusterIP로 변경하여 VIP를 Ingress-Nginx 전용으로 확보
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
# name    : upstream 원본 이미지 이름 (CI의 UPSTREAM_PREFIX와 반드시 일치)
# newName : 우리 GitLab Registry 경로
# newTag  : CI_COMMIT_SHORT_SHA (CI 파이프라인이 자동 갱신)
# ---------------------------------------------------------------------------
images:
${IMAGES_BLOCK}
EOF

say "  ✅ overlays/dev/kustomization.yaml 생성 (10개 서비스)"

# ---------- README + .gitignore ----------
say "\n[4/4] gitops-repo push 중..."
cat > README.md <<'EOF'
# GitOps Repository — Online Boutique

## 구조

```
apps/boutique/
  base/
    adservice.yaml / cartservice.yaml ...  ← 서비스별 직접 작성 (11개)
    kustomization.yaml         ← 로컬 파일 참조 + loadgenerator 제외
  overlays/
    dev/                       ← Argo CD가 바라보는 경로
      kustomization.yaml       ← CI가 이미지 태그를 자동 업데이트
```

## 설계 원칙

- `base/*.yaml` : 서비스별 독립 파일 (직접 수정 금지, 재실행으로 재생성)
- `overlays/dev/kustomization.yaml` : 환경별 커스터마이징만 선언
  - namespace 주입
  - imagePullSecrets 주입 (gitlab-regcred)
  - frontend-external → ClusterIP 변환
  - 이미지 교체 (우리 Registry + CI SHA 태그)

## 버전 업그레이드 방법

```bash
# 새 버전으로 재실행
./31-setup-gitops-repo.sh .env.gitops-lab
# 버전 입력 시 새 태그 입력 (예: v0.11.0)
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
say "\n✅ gitops-repo push 준비 완료. push 중..."
git add -A
git status

# 변경 없으면 스킵
if git diff --cached --quiet; then
  warn "  변경 없음 → push 스킵 (이미 최신 상태)"
else
  git commit -m "feat: Kustomize structure with GitHub-hosted yaml references

- base: 내 GitHub 레포 yaml 파일을 raw URL로 참조
  (github.com/msp-architect-2026/kim-jaehoon/devops-lab-infra)
- overlays/dev: namespace, imagePullSecrets, frontend-external 설정
- yaml 수정은 GitHub에서 직접 → commit → Argo CD 자동 반영

Setup: 31-setup-gitops-repo.sh"

  git push -u origin main
fi

say "\n✅ gitops-repo 구성 완료!"

echo ""
echo "=================================================="
echo " 🎉 Step 2 완료: gitops-repo Kustomize 구조 생성"
echo "=================================================="
echo "  GitLab URL    : ${GITLAB_URL}/${GROUP}/${GITOPS_PROJECT}"
echo "  Argo CD path  : apps/boutique/overlays/dev"
echo "  base 구조   : 내 GitHub raw URL 참조 (10개 서비스)"
echo "  서비스 수      : 10개 (loadgenerator 제외)"
echo ""
echo "  → 다음 단계: ./32-setup-gitlab-ci.sh 실행"
echo "              .gitlab-ci.yml 완성본을 app-repo에 push"
echo "=================================================="
