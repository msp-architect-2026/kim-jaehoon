#!/usr/bin/env bash
set -euo pipefail

need(){ command -v "$1" >/dev/null 2>&1 || { echo "❌ '$1' 필요" >&2; exit 1; }; }
need curl
need jq
need awk
need sed
need ip

# logs -> stderr
say(){  echo -e "\033[0;32m$*\033[0m" >&2; }
warn(){ echo -e "\033[1;33m$*\033[0m" >&2; }
err(){  echo -e "\033[0;31m$*\033[0m" >&2; }

urlenc(){ jq -rn --arg v "$1" '$v|@uri'; }

# curl helper (TLS 옵션 반영)
curl_json(){
  local method="$1"; shift
  local url="$1"; shift
  local data="${1:-}"
  local out http body
  if [[ -n "$data" ]]; then
    out="$(curl -sS "${TLS[@]}" -X "$method" "${HDR[@]}" -H "Content-Type: application/json" -d "$data" -w "\n%{http_code}" "$url" || true)"
  else
    out="$(curl -sS "${TLS[@]}" -X "$method" "${HDR[@]}" -w "\n%{http_code}" "$url" || true)"
  fi
  http="$(echo "$out" | tail -n1)"
  body="$(echo "$out" | sed '$d')"
  if [[ ! "$http" =~ ^2 ]]; then
    err "❌ API 실패: $method $url (HTTP $http)"
    err "---- body ----"
    echo "$body" >&2
    err "------------"
    return 1
  fi
  echo "$body"
}

# CI variable upsert (최종 실패는 실패로 처리)
set_ci_var_safe(){
  local proj_id="$1" key="$2" val="$3" masked="${4:-false}" protected="${5:-false}"
  local key_enc
  key_enc="$(urlenc "$key")"

  if curl -fsS "${TLS[@]}" "${HDR[@]}" "$API/projects/$proj_id/variables/$key_enc" >/dev/null 2>&1; then
    say "🔁 CI 변수 업데이트: $key (masked=$masked)"
    if ! curl -fsS "${TLS[@]}" "${HDR[@]}" -X PUT "$API/projects/$proj_id/variables/$key_enc" \
      --data-urlencode "value=$val" \
      --data-urlencode "masked=$masked" \
      --data-urlencode "protected=$protected" >/dev/null 2>&1; then
      warn "⚠️ 변수 업데이트 실패: $key -> masked=false 재시도"
      curl -fsS "${TLS[@]}" "${HDR[@]}" -X PUT "$API/projects/$proj_id/variables/$key_enc" \
        --data-urlencode "value=$val" \
        --data-urlencode "masked=false" \
        --data-urlencode "protected=$protected" >/dev/null 2>&1 \
        || { err "❌ CI 변수 업데이트 최종 실패: $key"; return 1; }
    fi
  else
    say "➕ CI 변수 생성: $key (masked=$masked)"
    if ! curl -fsS "${TLS[@]}" "${HDR[@]}" -X POST "$API/projects/$proj_id/variables" \
      --data-urlencode "key=$key" \
      --data-urlencode "value=$val" \
      --data-urlencode "masked=$masked" \
      --data-urlencode "protected=$protected" >/dev/null 2>&1; then
      warn "⚠️ 변수 생성 실패: $key -> masked=false 재시도"
      curl -fsS "${TLS[@]}" "${HDR[@]}" -X POST "$API/projects/$proj_id/variables" \
        --data-urlencode "key=$key" \
        --data-urlencode "value=$val" \
        --data-urlencode "masked=false" \
        --data-urlencode "protected=$protected" >/dev/null 2>&1 \
        || { err "❌ CI 변수 생성 최종 실패: $key"; return 1; }
    fi
  fi
}

ensure_project(){
  local full="$1" name="$2" nsid="$3"
  if curl -fsS "${TLS[@]}" "${HDR[@]}" "$API/projects/$(urlenc "$full")" >/dev/null 2>&1; then
    say "✅ 프로젝트 존재: $full"
  else
    say "➕ 프로젝트 생성: $full"
    curl -fsS "${TLS[@]}" "${HDR[@]}" -X POST "$API/projects" \
      --data-urlencode "name=$name" \
      --data-urlencode "path=$name" \
      --data-urlencode "namespace_id=$nsid" >/dev/null
    say "✅ 생성 완료: $full"
  fi
}

get_project_id(){
  local full="$1"
  curl -fsS "${TLS[@]}" "${HDR[@]}" "$API/projects/$(urlenc "$full")" | jq -r '.id'
}

create_deploy_token(){
  local proj_id="$1" name="$2" scopes_csv="$3" expires_at="$4"
  warn "➕ Deploy Token 생성: $name"
  local payload
  if [[ -n "$expires_at" ]]; then
    payload="$(jq -n --arg name "$name" --arg scopes "$scopes_csv" --arg exp "$expires_at" \
      '{name:$name, expires_at:$exp, scopes: ($scopes|split(",")|map(gsub("^\\s+|\\s+$";"")))}')"
  else
    payload="$(jq -n --arg name "$name" --arg scopes "$scopes_csv" \
      '{name:$name, scopes: ($scopes|split(",")|map(gsub("^\\s+|\\s+$";"")))}')"
  fi
  curl_json POST "$API/projects/$proj_id/deploy_tokens" "$payload"
}

create_project_access_token(){
  local proj_id="$1" name="$2" scopes_csv="$3" access_level="${4:-40}" expires_at="$5"
  warn "➕ Project Access Token 생성: $name"
  local payload
  if [[ -n "$expires_at" ]]; then
    payload="$(jq -n --arg name "$name" --arg scopes "$scopes_csv" --argjson al "$access_level" --arg exp "$expires_at" \
      '{name:$name, expires_at:$exp, scopes: ($scopes|split(",")|map(gsub("^\\s+|\\s+$";""))), access_level:$al}')"
  else
    payload="$(jq -n --arg name "$name" --arg scopes "$scopes_csv" --argjson al "$access_level" \
      '{name:$name, scopes: ($scopes|split(",")|map(gsub("^\\s+|\\s+$";""))), access_level:$al}')"
  fi
  curl_json POST "$API/projects/$proj_id/access_tokens" "$payload"
}

lookup_project_access_token_username(){
  local proj_id="$1" token_name="$2"
  local list
  list="$(curl_json GET "$API/projects/$proj_id/access_tokens" "" 2>/dev/null || true)"
  [[ -n "$list" ]] || return 1
  echo "$list" | jq -r --arg n "$token_name" '.[] | select(.name==$n) | .username' | head -n1
}

read_username(){
  local prompt="$1" def="$2"
  local u
  while true; do
    read -rp "$prompt" u
    u="${u:-$def}"
    if [[ "$u" =~ [[:space:]] || "$u" =~ [\;\|\&\`\<\>\$\\] ]]; then
      warn "⚠️ 특수문자/공백 불가"
      continue
    fi
    [[ ${#u} -ge 3 ]] && { echo "$u"; return 0; }
    warn "⚠️ 3글자 이상 입력하세요"
  done
}

echo "=================================================="
echo " GitLab Bootstrap (SAFE + HTTPS/CA 지원)"
echo "=================================================="

DETECTED_IP="$(ip route get 8.8.8.8 2>/dev/null | awk -F"src " 'NR==1{split($2,a," ");print a[1]}')"
DETECTED_IP="${DETECTED_IP:-<GITLAB_IP>}"

read -rp "Q1) GitLab URL [기본: https://${DETECTED_IP}]: " GITLAB_URL
GITLAB_URL="${GITLAB_URL:-https://${DETECTED_IP}}"
GITLAB_URL="${GITLAB_URL%/}"

echo
read -rp "Q1-1) GitLab CA 인증서 경로(권장, 예: /home/gitlab/config/ssl/ca.crt) [엔터=검증스킵(-k)]: " GITLAB_CA_CERT
GITLAB_CA_CERT="${GITLAB_CA_CERT:-}"

# ==============================================================================
# [방안 B 핵심 수정] CA 경로 → 절대 경로 변환
# 사용자가 ./ca.crt, ~/ca.crt 등 상대 경로를 입력해도
# .env 파일에는 항상 절대 경로로 저장
# 이후 스크립트가 cd로 디렉터리를 이동해도 경로를 잃지 않음
# ==============================================================================
if [[ -n "$GITLAB_CA_CERT" ]]; then
  if [[ ! -f "$GITLAB_CA_CERT" ]]; then
    err "❌ CA 파일 없음: $GITLAB_CA_CERT"
    exit 1
  fi
  GITLAB_CA_CERT="$(realpath "$GITLAB_CA_CERT")"
  say "✅ CA 경로 절대 경로 변환 완료: ${GITLAB_CA_CERT}"
fi

# ✅ redirect 대응: -L 항상 포함
TLS=(-L)
if [[ -n "$GITLAB_CA_CERT" ]]; then
  TLS+=("--cacert" "$GITLAB_CA_CERT")
else
  warn "⚠️ CA 경로 미지정 → curl은 -k(인증서 검증 스킵)로 동작합니다(랩용)."
  TLS+=(-k)
fi

echo
echo "Q2) GitLab API 토큰(PAT) (User Settings -> Access Tokens, scope: api)"
read -rsp "    Token(숨김): " GITLAB_ADMIN_TOKEN
echo
[[ -n "${GITLAB_ADMIN_TOKEN}" ]] || { err "❌ 토큰이 비어있음"; exit 1; }

read -rp "Q3) Namespace(그룹/유저) [기본: root]: " NS
NS="${NS:-root}"

read -rp "Q4) app 프로젝트명 [기본: app-repo]: " APP_PROJECT
APP_PROJECT="${APP_PROJECT:-app-repo}"

read -rp "Q5) gitops 프로젝트명 [기본: gitops-repo]: " GITOPS_PROJECT
GITOPS_PROJECT="${GITOPS_PROJECT:-gitops-repo}"

read -rp "Q5-1) Registry 포트 [기본: 5050]: " REG_PORT
REG_PORT="${REG_PORT:-5050}"

OUT=".env.gitops-lab"
PREFIX="gitops-lab"
EXPIRES_DAYS="30"

EXPIRES_AT=""
if date -d "+${EXPIRES_DAYS} days" >/dev/null 2>&1; then
  EXPIRES_AT="$(date -d "+${EXPIRES_DAYS} days" +%F)"
fi

echo
warn "-------------------- 확인 --------------------"
warn " GitLab URL     : $GITLAB_URL"
warn " CA cert        : ${GITLAB_CA_CERT:-<skip (-k)>}"
warn " Namespace      : $NS"
warn " app project    : $APP_PROJECT"
warn " gitops project : $GITOPS_PROJECT"
warn " Registry port  : $REG_PORT"
warn " .env output    : $OUT"
warn "--------------------------------------------"
read -rp "진행할까요? (y/n) [기본 n]: " CONFIRM
CONFIRM="${CONFIRM:-n}"
[[ "$CONFIRM" =~ ^[Yy]$ ]] || { echo "취소" >&2; exit 0; }

API="$GITLAB_URL/api/v4"
HDR=(-H "PRIVATE-TOKEN: $GITLAB_ADMIN_TOKEN")

say "🔎 GitLab API 연결 확인..."
ver_json="$(curl_json GET "$API/version")"
say "✅ API OK (version=$(echo "$ver_json" | jq -r '.version // "unknown"'))"

say "🔎 namespace_id 조회: $NS"
NS_JSON="$(curl -fsS "${TLS[@]}" "${HDR[@]}" "$API/namespaces?search=$(urlenc "$NS")")"
NS_ID="$(echo "$NS_JSON" | jq -r '.[] | select(.full_path=="'"$NS"'") | .id' | head -n1)"
if [[ -z "${NS_ID:-}" || "$NS_ID" == "null" ]]; then
  err "❌ namespace '$NS'를 못 찾음."
  exit 1
fi

APP_FULL="$NS/$APP_PROJECT"
GITOPS_FULL="$NS/$GITOPS_PROJECT"

ensure_project "$APP_FULL" "$APP_PROJECT" "$NS_ID"
ensure_project "$GITOPS_FULL" "$GITOPS_PROJECT" "$NS_ID"

APP_ID="$(get_project_id "$APP_FULL")"
GITOPS_ID="$(get_project_id "$GITOPS_FULL")"

GITLAB_HOSTPORT="$(echo "$GITLAB_URL" | sed -E 's#^https?://##' | sed -E 's#/.*##')"
GITLAB_HOST="${GITLAB_HOSTPORT%%:*}"

REGISTRY_HOSTPORT="$GITLAB_HOST:$REG_PORT"
GITOPS_REPO_URL="$GITLAB_URL/$GITOPS_FULL.git"

say "=================================================="
say "토큰 3종 생성 중..."
TS="$(date +%Y%m%d%H%M%S)"

REG_NAME="${PREFIX}-k8s-pull-${TS}"
REG_PULL_JSON="$(create_deploy_token "$APP_ID" "$REG_NAME" "read_registry" "$EXPIRES_AT")"
REGISTRY_PULL_USER="$(echo "$REG_PULL_JSON" | jq -r '.username')"
REGISTRY_PULL_TOKEN="$(echo "$REG_PULL_JSON" | jq -r '.token')"

ARGO_NAME="${PREFIX}-argocd-read-${TS}"
ARGO_READ_JSON="$(create_deploy_token "$GITOPS_ID" "$ARGO_NAME" "read_repository" "$EXPIRES_AT")"
ARGO_GITOPS_READ_USER="$(echo "$ARGO_READ_JSON" | jq -r '.username')"
ARGO_GITOPS_READ_TOKEN="$(echo "$ARGO_READ_JSON" | jq -r '.token')"

CI_NAME="${PREFIX}-ci-push-${TS}"
CI_PUSH_JSON="$(create_project_access_token "$GITOPS_ID" "$CI_NAME" "read_repository,write_repository" 40 "$EXPIRES_AT")"
GITOPS_PUSH_TOKEN="$(echo "$CI_PUSH_JSON" | jq -r '.token // empty')"
GITOPS_PUSH_USER="$(echo "$CI_PUSH_JSON" | jq -r '.username // empty')"

if [[ -z "${GITOPS_PUSH_USER:-}" || "$GITOPS_PUSH_USER" == "null" ]]; then
  GITOPS_PUSH_USER="$(lookup_project_access_token_username "$GITOPS_ID" "$CI_NAME" || true)"
fi
if [[ -z "${GITOPS_PUSH_USER:-}" || "$GITOPS_PUSH_USER" == "null" ]]; then
  DEF_USER="project_${GITOPS_ID}_bot"
  GITOPS_PUSH_USER="$(read_username "gitops-repo push용 username [엔터=${DEF_USER}]: " "$DEF_USER")"
fi

say "=================================================="
say "app-repo CI Variables 등록"
set_ci_var_safe "$APP_ID" "REGISTRY_HOSTPORT" "$REGISTRY_HOSTPORT" false false
set_ci_var_safe "$APP_ID" "GITOPS_PUSH_USER"  "$GITOPS_PUSH_USER"  false false
set_ci_var_safe "$APP_ID" "GITOPS_PUSH_TOKEN" "$GITOPS_PUSH_TOKEN" true  false
set_ci_var_safe "$APP_ID" "GITOPS_REPO_URL"   "$GITOPS_REPO_URL"   false false

# ✅ 시크릿 파일 안전하게 생성
# GITLAB_CA_CERT는 위에서 realpath로 절대 경로 변환 완료
umask 077
cat > "$OUT" <<ENV
# Generated by 10-k8s-bootstrap-phase3.sh
# ⚠️  GITLAB_CA_CERT는 절대 경로로 저장됨 (realpath 변환 적용)
#     이 파일을 수동 편집 시에도 반드시 절대 경로로 입력할 것
GITLAB_URL="$GITLAB_URL"
GITLAB_HOST="$GITLAB_HOST"
GITLAB_CA_CERT="$GITLAB_CA_CERT"
GROUP="$NS"
APP_PROJECT="$APP_PROJECT"
GITOPS_PROJECT="$GITOPS_PROJECT"
REGISTRY_HOSTPORT="$REGISTRY_HOSTPORT"
GITOPS_REPO_URL="$GITOPS_REPO_URL"

# (C) K8s pull
REGISTRY_PULL_USER="$REGISTRY_PULL_USER"
REGISTRY_PULL_TOKEN="$REGISTRY_PULL_TOKEN"

# (A) Argo read
ARGO_GITOPS_READ_USER="$ARGO_GITOPS_READ_USER"
ARGO_GITOPS_READ_TOKEN="$ARGO_GITOPS_READ_TOKEN"

# (B) CI push
GITOPS_PUSH_USER="$GITOPS_PUSH_USER"
GITOPS_PUSH_TOKEN="$GITOPS_PUSH_TOKEN"
ENV
chmod 600 "$OUT" 2>/dev/null || true

say "✅ 완료: $OUT 생성 (chmod 600 적용)"
say "   - GITLAB_CA_CERT 절대 경로 저장: ${GITLAB_CA_CERT:-<없음>}"
say "   - 다음 단계(Phase3)에서 이 env를 source 해서 사용하세요."
say "   - ⚠️ 이 파일은 토큰 포함(절대 커밋 금지). .gitignore에 추가 권장."
say "   - REGISTRY_HOSTPORT는 스킴 없이 host:port 형태입니다."
if [[ -n "$GITLAB_CA_CERT" ]]; then
  say "   - Argo/노드에서 TLS 신뢰 필요 시 이 CA를 사용하세요: $GITLAB_CA_CERT"
fi
