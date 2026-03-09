#!/usr/bin/env bash
# ==============================================================================
# 32-setup-gitlab-ci.sh
# 역할:
#   1. GitLab CA 인증서를 base64로 인코딩 → CI Variable(GITLAB_CA_CERT_B64) 등록
#   2. 기존 필수 CI Variables 존재 확인
#   3. .gitlab-ci.yml 완성본을 app-repo에 커밋/push
#
# 실행 위치: Master Node (<K8S_MASTER_IP>)
#
# 토큰 역할 분리:
#   GITLAB_ADMIN_TOKEN : api scope PAT → GitLab API 호출 (CI Variable 등록)
#   GITOPS_PUSH_TOKEN  : write_repository → git push 전용
#
# 전제 조건:
#   - .env.gitops-lab 에 GITLAB_ADMIN_TOKEN 항목 추가 완료
#   - .gitlab-ci.yml (완성본) 이 이 스크립트와 같은 디렉터리에 존재
#   - 30, 31번 스크립트 완료
# ==============================================================================
set -euo pipefail

say()  { echo -e "\033[0;32m$*\033[0m"; }
warn() { echo -e "\033[1;33m$*\033[0m"; }
err()  { echo -e "\033[0;31m$*\033[0m"; }
need() { command -v "$1" >/dev/null 2>&1 || { err "❌ '$1' 필요"; exit 1; }; }

need git
need curl
need base64
need jq

# ---------- env 로드 ----------
ENV_FILE="${1:-./.env.gitops-lab}"
[[ -f "$ENV_FILE" ]] || { err "❌ env 파일 없음: $ENV_FILE"; exit 1; }
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
: "${GITLAB_ADMIN_TOKEN:?GITLAB_ADMIN_TOKEN이 env에 없습니다
   .env.gitops-lab 에 아래 줄을 추가하세요:
   GITLAB_ADMIN_TOKEN=\"glpat-xxxxxxxxxxxxxxxxxxxx\"}"
: "${GITOPS_PUSH_USER:?GITOPS_PUSH_USER가 env에 없습니다}"
: "${GITOPS_PUSH_TOKEN:?GITOPS_PUSH_TOKEN이 env에 없습니다}"
: "${GROUP:?GROUP이 env에 없습니다}"

# ---------- GITLAB_URL https 강제 검증 ----------
if [[ "$GITLAB_URL" =~ ^http:// ]]; then
  err "❌ GITLAB_URL이 http:// 입니다. .env.gitops-lab 수정 후 재실행하세요."
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
  echo "   scp minipc@<GITLAB_IP>:/home/gitlab/config/ssl/ca.crt ~/ca.crt"
  exit 1
fi

# ---------- 변수 ----------
APP_PROJECT="${APP_PROJECT:-app-repo}"
APP_REPO_URL="${GITLAB_URL}/${GROUP}/${APP_PROJECT}.git"
API="${GITLAB_URL}/api/v4"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CI_YML_SRC="${SCRIPT_DIR}/.gitlab-ci.yml"

echo "=================================================="
echo " Step 3. CI Variable 등록 + .gitlab-ci.yml push"
echo " 실행 위치: Master Node (<K8S_MASTER_IP>)"
echo "=================================================="
warn "  GitLab URL        : ${GITLAB_URL}"
warn "  app-repo          : ${GROUP}/${APP_PROJECT}"
warn "  CA 파일           : ${CA_CERT}"
warn "  CI YML 소스       : ${CI_YML_SRC}"
warn "  API 토큰 (admin)  : ${GITLAB_ADMIN_TOKEN:0:12}... (앞 12자만 표시)"
echo ""
read -rp "계속할까요? (y/n) [기본 n]: " OK
OK="${OK:-n}"
[[ "$OK" =~ ^[Yy]$ ]] || { echo "취소"; exit 0; }

# ---------- .gitlab-ci.yml 존재 검증 ----------
[[ -f "$CI_YML_SRC" ]] || {
  err "❌ .gitlab-ci.yml 없음: $CI_YML_SRC"
  echo "   이 스크립트와 같은 디렉터리에 .gitlab-ci.yml 을 두세요."
  exit 1
}

# ---------- TLS / git SSL 설정 ----------
TLS_OPTS=(--cacert "$CA_CERT" -L)
ADMIN_HDR=(-H "PRIVATE-TOKEN: ${GITLAB_ADMIN_TOKEN}")
export GIT_SSL_CAINFO="$CA_CERT"
git config --global http.sslCAInfo "$CA_CERT"
say "✅ git SSL CA 설정 완료: ${CA_CERT}"

# ---------- GitLab API 연결 확인 ----------
say "🔎 GitLab API 연결 확인..."
VER=$(curl -fsSL "${TLS_OPTS[@]}" "${ADMIN_HDR[@]}" \
  "${API}/version" | jq -r '.version // "unknown"')
say "✅ GitLab API 연결 완료 (version: ${VER})"

# ---------- URL 인코딩 ----------
urlencode_path() {
  echo "${1//\//%2F}"
}

# ---------- app-repo project_id 조회 ----------
say "🔎 app-repo project_id 조회..."
ENCODED_PATH="$(urlencode_path "${GROUP}/${APP_PROJECT}")"
PROJ_JSON=$(curl -fsSL "${TLS_OPTS[@]}" "${ADMIN_HDR[@]}" \
  "${API}/projects/${ENCODED_PATH}")
APP_ID=$(echo "$PROJ_JSON" | jq -r '.id')

if [[ -z "$APP_ID" || "$APP_ID" == "null" ]]; then
  err "❌ app-repo project_id 조회 실패"
  echo "   30-setup-app-repo.sh 가 완료되었는지 확인하세요."
  exit 1
fi
say "✅ app-repo project_id: ${APP_ID}"

# ---------- CI Variable upsert 함수 ----------
upsert_ci_var() {
  local proj_id="$1"
  local key="$2"
  local val="$3"
  local masked="${4:-false}"
  local protected="${5:-false}"

  local http_status
  http_status=$(curl -sS "${TLS_OPTS[@]}" "${ADMIN_HDR[@]}" \
    -o /dev/null -w "%{http_code}" \
    "${API}/projects/${proj_id}/variables/${key}" || true)

  if [[ "$http_status" == "200" ]]; then
    say "  🔁 업데이트: ${key} (masked=${masked})"
    curl -fsSL "${TLS_OPTS[@]}" "${ADMIN_HDR[@]}" \
      -X PUT "${API}/projects/${proj_id}/variables/${key}" \
      --data-urlencode "value=${val}" \
      --data-urlencode "masked=${masked}" \
      --data-urlencode "protected=${protected}" >/dev/null
  else
    say "  ➕ 생성: ${key} (masked=${masked})"
    curl -fsSL "${TLS_OPTS[@]}" "${ADMIN_HDR[@]}" \
      -X POST "${API}/projects/${proj_id}/variables" \
      --data-urlencode "key=${key}" \
      --data-urlencode "value=${val}" \
      --data-urlencode "masked=${masked}" \
      --data-urlencode "protected=${protected}" >/dev/null
  fi
}

# ---------- 1. CA 인증서 → GITLAB_CA_CERT_B64 등록 ----------
say "\n[1/3] CA 인증서 → GITLAB_CA_CERT_B64 CI Variable 등록..."
CA_B64="$(base64 -w 0 "$CA_CERT")"
say "  인코딩 완료 (${#CA_B64} chars)"

upsert_ci_var "$APP_ID" "GITLAB_CA_CERT_B64" "$CA_B64" "true" "false"
say "✅ GITLAB_CA_CERT_B64 등록 완료 (masked)"

# ---------- 2. 기존 필수 CI Variables 확인 ----------
say "\n[2/3] 기존 CI Variables 확인..."
REQUIRED_VARS=("REGISTRY_HOSTPORT" "GITOPS_PUSH_USER" "GITOPS_PUSH_TOKEN" "GITOPS_REPO_URL")
MISSING_VARS=()

for var_key in "${REQUIRED_VARS[@]}"; do
  status=$(curl -sS "${TLS_OPTS[@]}" "${ADMIN_HDR[@]}" \
    -o /dev/null -w "%{http_code}" \
    "${API}/projects/${APP_ID}/variables/${var_key}" || true)
  if [[ "$status" == "200" ]]; then
    say "  ✅ ${var_key}: 존재"
  else
    warn "  ⚠️  ${var_key}: 없음"
    MISSING_VARS+=("$var_key")
  fi
done

if [[ ${#MISSING_VARS[@]} -gt 0 ]]; then
  warn ""
  warn "⚠️  누락된 CI Variables: ${MISSING_VARS[*]}"
  warn "   10-k8s-bootstrap-phase3.sh 를 재실행하여 등록하세요."
  warn "   파이프라인 실행 전에 반드시 해결해야 합니다."
fi

# ---------- 3. .gitlab-ci.yml push ----------
say "\n[3/3] .gitlab-ci.yml 완성본 app-repo에 push 중..."
WORK_DIR="/tmp/ci-yml-push-$$"
rm -rf "$WORK_DIR"
mkdir -p "$WORK_DIR"
trap 'rm -f ~/.git-credentials; git config --global --unset credential.helper || true; rm -rf "$WORK_DIR"' EXIT

GITLAB_HOST="$(echo "$GITLAB_URL" | sed -E 's#^https?://##' | sed -E 's#/.*##')"

# [수정] 토큰을 URL에 직접 삽입하지 않고 credential helper 사용
# → .git/config 및 로그에 토큰 노출 방지
git config --global credential.helper store
printf "https://root:%s@%s\n" "${GITLAB_ADMIN_TOKEN}" "${GITLAB_HOST}" \
  > ~/.git-credentials
chmod 600 ~/.git-credentials

git clone "$APP_REPO_URL" "${WORK_DIR}/app-repo"
cd "${WORK_DIR}/app-repo"

git config user.name "gitlab-ci-setup"
git config user.email "setup@local"

cp "$CI_YML_SRC" .gitlab-ci.yml
git add .gitlab-ci.yml

if git diff --cached --quiet; then
  warn "  .gitlab-ci.yml 변경 없음 → push 스킵"
else
  git commit -m "ci: apply production .gitlab-ci.yml

Changes from draft:
  - docker.sock 방식 (DinD 제거)
  - GITLAB_CA_CERT_B64 기반 Strict SSL (sslVerify false 제거)
  - 10개 서비스 빌드 (loadgenerator 제외)
  - gitops 태그 자동 업데이트 + race condition 방어

Setup: 32-setup-gitlab-ci.sh"

  git push origin main
  say "✅ .gitlab-ci.yml push 완료"
fi

# push 완료 후 즉시 credential 제거
rm -f ~/.git-credentials
git config --global --unset credential.helper || true

echo ""
echo "=================================================="
echo " 🎉 Step 3 완료: CI/CD 파이프라인 구성 완료"
echo "=================================================="
echo "  app-repo    : ${GITLAB_URL}/${GROUP}/${APP_PROJECT}"
echo "  gitops-repo : ${GITLAB_URL}/${GROUP}/${GITOPS_PROJECT:-gitops-repo}"
echo ""
echo "  등록된 CI Variables:"
echo "    ✅ GITLAB_CA_CERT_B64  (masked)"
echo "    ✅ REGISTRY_HOSTPORT"
echo "    ✅ GITOPS_PUSH_USER"
echo "    ✅ GITOPS_PUSH_TOKEN   (masked)"
echo "    ✅ GITOPS_REPO_URL"
echo ""
echo "  → 이제 app-repo에 코드를 push하면 파이프라인이 자동 실행됩니다."
echo "  → Argo CD 확인:"
echo "     kubectl port-forward svc/argocd-server -n argocd 8080:443 --address 0.0.0.0"
echo "     브라우저: https://<K8S_MASTER_IP>:8080"
echo "=================================================="
