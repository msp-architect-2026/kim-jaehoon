#!/usr/bin/env bash
# ==============================================================================
# 30-setup-app-repo.sh
# 역할: Google Online Boutique 소스를 clone → app-repo(GitLab)에 push
# 실행 위취 ex: Master Node (192.168.10.113)
# 전제 조건:
#   - .env.gitops-lab 파일이 동일 디렉터리에 존재 (10-k8s-bootstrap-phase3.sh 생성)
#   - install-ca-all.sh 실행 완료 (OS CA 신뢰 등록됨)
#   - git, curl 설치됨
# ==============================================================================
set -euo pipefail

say()  { echo -e "\033[0;32m$*\033[0m"; }
warn() { echo -e "\033[1;33m$*\033[0m"; }
err()  { echo -e "\033[0;31m$*\033[0m"; }
need() { command -v "$1" >/dev/null 2>&1 || { err "❌ '$1' 필요. 설치 후 재실행하세요."; exit 1; }; }

need git
need curl

# ---------- env 로드 ----------
ENV_FILE="${1:-./.env.gitops-lab}"
if [[ ! -f "$ENV_FILE" ]]; then
  err "❌ env 파일 없음: $ENV_FILE"
  echo "   사용법: ./30-setup-app-repo.sh ./.env.gitops-lab"
  exit 1
fi
# shellcheck disable=SC1090
source "$ENV_FILE"

# ==============================================================================
# [안전망] GITLAB_CA_CERT 상대 경로 → 절대 경로 변환
# ==============================================================================
if [[ -n "${GITLAB_CA_CERT:-}" && "${GITLAB_CA_CERT}" != /* ]]; then
  _env_dir="$(cd "$(dirname "$(realpath "$ENV_FILE")")" && pwd)"
  GITLAB_CA_CERT="$(realpath "${_env_dir}/${GITLAB_CA_CERT}")"
  warn "⚠️  GITLAB_CA_CERT 상대 경로 감지 → 절대 경로로 변환: ${GITLAB_CA_CERT}"
fi

# ---------- 필수 변수 검증 ----------
: "${GITLAB_URL:?GITLAB_URL이 env에 없습니다}"
: "${GITOPS_PUSH_USER:?GITOPS_PUSH_USER가 env에 없습니다}"
: "${GITOPS_PUSH_TOKEN:?GITOPS_PUSH_TOKEN이 env에 없습니다}"
: "${GROUP:?GROUP이 env에 없습니다}"
: "${GITLAB_ADMIN_TOKEN:?GITLAB_ADMIN_TOKEN이 env에 없습니다. .env.gitops-lab에 추가하세요}"

# ---------- GITLAB_URL https 강제 검증 ----------
if [[ "$GITLAB_URL" =~ ^http:// ]]; then
  err "❌ GITLAB_URL이 http:// 입니다: $GITLAB_URL"
  echo "   .env.gitops-lab 을 아래 명령어로 수정하세요:"
  echo "   sed -i 's|GITLAB_URL=\"http://|GITLAB_URL=\"https://|g' $ENV_FILE"
  echo "   sed -i 's|GITOPS_REPO_URL=\"http://|GITOPS_REPO_URL=\"https://|g' $ENV_FILE"
  exit 1
fi

# ---------- CA 파일 경로 결정 ----------
resolve_ca_cert() {
  local candidates=(
    "${GITLAB_CA_CERT:-}"
    "/usr/local/share/ca-certificates/gitlab-ca.crt"
    "/etc/ssl/certs/gitlab-ca.pem"
    "$HOME/ca.crt"
  )
  for path in "${candidates[@]}"; do
    if [[ -n "$path" ]]; then
      local abs_path
      abs_path="$(realpath "$path" 2>/dev/null || true)"
      if [[ -n "$abs_path" && -f "$abs_path" ]]; then
        echo "$abs_path"
        return 0
      fi
    fi
  done
  return 1
}

CA_CERT=""
if CA_CERT="$(resolve_ca_cert)"; then
  say "✅ CA 파일 확인: $CA_CERT"
else
  err "❌ CA 파일을 찾을 수 없습니다."
  echo ""
  echo "   해결 방법 (아래 중 하나):"
  echo "   1. install-ca-all.sh 실행 완료 여부 확인"
  echo "   2. Mini PC에서 직접 복사:"
  echo "      scp minipc@192.168.10.47:/home/gitlab/config/ssl/ca.crt ~/ca.crt"
  echo "   3. .env.gitops-lab에 아래 줄 추가:"
  echo "      GITLAB_CA_CERT=\"/경로/ca.crt\""
  exit 1
fi

# ---------- 고정 상수 ----------
APP_PROJECT="${APP_PROJECT:-app-repo}"
APP_REPO_URL="${GITLAB_URL}/${GROUP}/${APP_PROJECT}.git"

BOUTIQUE_UPSTREAM="https://github.com/msp-architect-2026/kim-jaehoon.git"
BOUTIQUE_BRANCH="devops-lab-infra"
BOUTIQUE_SRC_PATH="phase4-gitops-setup/app-source/src"

BOUTIQUE_SERVICES="adservice cartservice checkoutservice currencyservice emailservice frontend paymentservice productcatalogservice recommendationservice shippingservice"

WORK_DIR="/tmp/boutique-setup-$$"

echo "=================================================="
echo " Step 1. app-repo 구성 (Online Boutique 소스 push)"
echo " 실행 위치: Master Node (192.168.10.113)"
echo "=================================================="
warn "  GitLab URL   : ${GITLAB_URL}"
warn "  app-repo     : ${GROUP}/${APP_PROJECT}"
warn "  CA 파일      : ${CA_CERT}"
warn "  작업 디렉터리 : ${WORK_DIR}"
echo ""
read -rp "계속할까요? (y/n) [기본 n]: " OK
OK="${OK:-n}"
[[ "$OK" =~ ^[Yy]$ ]] || { echo "취소"; exit 0; }

# ---------- git SSL 설정 ----------
export GIT_SSL_CAINFO="$CA_CERT"
git config --global http.sslCAInfo "$CA_CERT"
say "✅ git SSL CA 설정 완료: ${CA_CERT}"

# ---------- GitLab 연결 사전 확인 ----------
say "🔎 GitLab 접속 확인 중..."
HTTP_CODE=$(curl --cacert "$CA_CERT" -sS -o /dev/null -w "%{http_code}" \
  "${GITLAB_URL}/users/sign_in" || true)
if [[ ! "$HTTP_CODE" =~ ^(200|302)$ ]]; then
  err "❌ GitLab 접속 실패 (HTTP ${HTTP_CODE})"
  echo "   URL: ${GITLAB_URL}"
  echo "   CA : ${CA_CERT}"
  exit 1
fi
say "✅ GitLab 접속 확인 완료 (HTTP ${HTTP_CODE})"

# ---------- 작업 디렉터리 준비 ----------
rm -rf "$WORK_DIR"
mkdir -p "$WORK_DIR"
trap 'rm -rf "$WORK_DIR"' EXIT

# ---------- 1. 내 GitHub에서 src/ sparse checkout ----------
say "\n[1/4] 내 GitHub에서 src/ 가져오는 중..."
say "     (sparse checkout — src/ 만 다운로드)"

git clone \
  --depth=1 \
  --filter=blob:none \
  --sparse \
  --branch "$BOUTIQUE_BRANCH" \
  "$BOUTIQUE_UPSTREAM" \
  "${WORK_DIR}/boutique"

cd "${WORK_DIR}/boutique"
git sparse-checkout set "$BOUTIQUE_SRC_PATH"
say "✅ sparse checkout 완료: ${BOUTIQUE_SRC_PATH}"

# ---------- 2. 불필요 파일 제거 + git 초기화 ----------
say "\n[2/4] loadgenerator/shoppingassistantservice 제거 및 git 초기화..."

cp -r "${BOUTIQUE_SRC_PATH}" /tmp/boutique-src-$$
cd "$WORK_DIR"
rm -rf boutique
mkdir boutique
cp -r /tmp/boutique-src-$$/* boutique/
rm -rf /tmp/boutique-src-$$
cd boutique

rm -rf loadgenerator shoppingassistantservice 2>/dev/null || true
say "  ✅ loadgenerator / shoppingassistantservice 제거"

git init -b main
git config user.name "gitlab-ci-setup"
git config user.email "setup@local"

# ---------- 3. 서비스 디렉터리 존재 검증 ----------
say "\n[3/4] 10개 서비스 소스 구조 검증..."
ALL_OK=true
for svc in $BOUTIQUE_SERVICES; do
  SVC_DIR="${svc}"
  if [[ ! -d "$SVC_DIR" ]]; then
    err "  ❌ 서비스 디렉터리 없음: ${SVC_DIR}"
    ALL_OK=false
    continue
  fi
  DOCKERFILE=$(find "$SVC_DIR" -type f -name "Dockerfile" | head -n1)
  if [[ -z "$DOCKERFILE" ]]; then
    err "  ❌ Dockerfile 없음: ${SVC_DIR}"
    ALL_OK=false
  else
    say "  ✅ ${svc} → ${DOCKERFILE}"
  fi
done

if [[ "$ALL_OK" != "true" ]]; then
  err "❌ 서비스 구조 검증 실패"
  exit 1
fi

# ---------- 4. .gitlab-ci.yml placeholder ----------
cat > .gitlab-ci.yml <<'EOF'
# 이 파일은 32-setup-gitlab-ci.sh 실행 후 완성본으로 교체됩니다.
stages:
  - build
  - gitops
EOF

# ---------- 5. app-repo push ----------
say "\n[4/4] app-repo push 중..."

GITLAB_HOST="$(echo "$GITLAB_URL" | sed -E 's#^https?://##' | sed -E 's#/.*##')"

# [수정] 토큰을 URL에 직접 삽입하지 않고 credential helper 사용
# → .git/config 및 로그에 토큰 노출 방지
git config --global credential.helper store
printf "https://root:%s@%s\n" "${GITLAB_ADMIN_TOKEN}" "${GITLAB_HOST}" \
  > ~/.git-credentials
chmod 600 ~/.git-credentials

git add -A
git commit -m "feat: initial Online Boutique source from my GitHub (loadgenerator excluded)"

git remote add origin "$APP_REPO_URL"
git push -u origin main --force

# push 완료 후 즉시 credential 제거
rm -f ~/.git-credentials
git config --global --unset credential.helper || true

say "\n✅ app-repo push 완료!"
echo ""
echo "=================================================="
echo " 🎉 Step 1 완료: app-repo 구성 성공"
echo "=================================================="
echo "  GitLab : ${GITLAB_URL}/${GROUP}/${APP_PROJECT}"
echo "  브랜치 : main"
echo "  서비스 : 10개 (loadgenerator 제외)"
echo ""
echo "  → 다음 단계: ./31-setup-gitops-repo.sh ./.env.gitops-lab"
echo "=================================================="
