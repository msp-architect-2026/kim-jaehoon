
#!/usr/bin/env bash
set -euo pipefail

need(){ command -v "$1" >/dev/null 2>&1 || { echo "❌ '$1' 필요" >&2; exit 1; }; }
need curl
need jq

# logs -> stderr
say(){  echo -e "\033[0;32m$*\033[0m" >&2; }
warn(){ echo -e "\033[1;33m$*\033[0m" >&2; }
err(){  echo -e "\033[0;31m$*\033[0m" >&2; }

urlenc(){ jq -rn --arg v "$1" '$v|@uri'; }

# curl helper
curl_json(){
  local method="$1"; shift
  local url="$1"; shift
  local data="${1:-}"
  local out http body
  if [[ -n "$data" ]]; then
    out="$(curl -sS -X "$method" "${HDR[@]}" -H "Content-Type: application/json" -d "$data" -w "\n%{http_code}" "$url" || true)"
  else
    out="$(curl -sS -X "$method" "${HDR[@]}" -w "\n%{http_code}" "$url" || true)"
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

# CI variable upsert
set_ci_var_safe(){
  local proj_id="$1" key="$2" val="$3" masked="${4:-false}" protected="${5:-false}"
  local key_enc
  key_enc="$(urlenc "$key")"

  if curl -fsS "${HDR[@]}" "$API/projects/$proj_id/variables/$key_enc" >/dev/null 2>&1; then
    say "🔁 CI 변수 업데이트: $key (masked=$masked)"
    if ! curl -fsS "${HDR[@]}" -X PUT "$API/projects/$proj_id/variables/$key_enc" \
      --data-urlencode "value=$val" \
      --data-urlencode "masked=$masked" \
      --data-urlencode "protected=$protected" >/dev/null 2>&1; then
      warn "⚠️ 변수 업데이트 실패: $key -> masked=false 재시도"
      curl -fsS "${HDR[@]}" -X PUT "$API/projects/$proj_id/variables/$key_enc" \
        --data-urlencode "value=$val" \
        --data-urlencode "masked=false" \
        --data-urlencode "protected=$protected" >/dev/null 2>&1 || return 0
    fi
  else
    say "➕ CI 변수 생성: $key (masked=$masked)"
    if ! curl -fsS "${HDR[@]}" -X POST "$API/projects/$proj_id/variables" \
      --data-urlencode "key=$key" \
      --data-urlencode "value=$val" \
      --data-urlencode "masked=$masked" \
      --data-urlencode "protected=$protected" >/dev/null 2>&1; then
      warn "⚠️ 변수 생성 실패: $key -> masked=false 재시도"
      curl -fsS "${HDR[@]}" -X POST "$API/projects/$proj_id/variables" \
        --data-urlencode "key=$key" \
        --data-urlencode "value=$val" \
        --data-urlencode "masked=false" \
        --data-urlencode "protected=$protected" >/dev/null 2>&1 || return 0
    fi
  fi
}

ensure_project(){
  local full="$1" name="$2" nsid="$3"
  if curl -fsS "${HDR[@]}" "$API/projects/$(urlenc "$full")" >/dev/null 2>&1; then
    say "✅ 프로젝트 존재: $full"
  else
    say "➕ 프로젝트 생성: $full"
    curl -fsS "${HDR[@]}" -X POST "$API/projects" \
      --data-urlencode "name=$name" \
      --data-urlencode "path=$name" \
      --data-urlencode "namespace_id=$nsid" >/dev/null
    say "✅ 생성 완료: $full"
  fi
}

get_project_id(){
  local full="$1"
  curl -fsS "${HDR[@]}" "$API/projects/$(urlenc "$full")" | jq -r '.id'
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
echo " GitLab Bootstrap (SAFE)"
echo "=================================================="

# --- 설정 입력 (기본값 수정됨) ---
read -rp "Q1) GitLab URL [기본: http://192.168.10.47]: " GITLAB_URL
GITLAB_URL="${GITLAB_URL:-http://192.168.10.47}"
GITLAB_URL="${GITLAB_URL%/}"

echo
echo "Q2) GitLab API 토큰(PAT) (User Settings -> Access Tokens, scope: api)"
read -rsp "    Token(숨김): " GITLAB_ADMIN_TOKEN
echo

read -rp "Q3) Namespace(그룹/유저) [기본: root]: " NS
NS="${NS:-root}"

read -rp "Q4) app 프로젝트명 [기본: app-repo]: " APP_PROJECT
APP_PROJECT="${APP_PROJECT:-app-repo}"

read -rp "Q5) gitops 프로젝트명 [기본: gitops-repo]: " GITOPS_PROJECT
GITOPS_PROJECT="${GITOPS_PROJECT:-gitops-repo}"

REG_PORT="5050"
OUT=".env.gitops-lab"
PREFIX="gitops-lab"
EXPIRES_DAYS="30"

EXPIRES_AT=""
if date -d "+${EXPIRES_DAYS} days" >/dev/null 2>&1; then
  EXPIRES_AT="$(date -d "+${EXPIRES_DAYS} days" +%F)"
fi

echo
warn "-------------------- 확인 --------------------"
warn " GitLab URL    : $GITLAB_URL"
warn " Namespace     : $NS"
warn " app project   : $APP_PROJECT"
warn " gitops project: $GITOPS_PROJECT"
warn "--------------------------------------------"
read -rp "진행할까요? (y/n) [기본 n]: " CONFIRM
CONFIRM="${CONFIRM:-n}"
[[ "$CONFIRM" =~ ^[Yy]$ ]] || { echo "취소" >&2; exit 0; }

API="$GITLAB_URL/api/v4"
HDR=(-H "PRIVATE-TOKEN: $GITLAB_ADMIN_TOKEN")

say "🔎 GitLab API 연결 확인..."
curl -fsS "${HDR[@]}" "$API/version" >/dev/null
say "✅ API OK"

say "🔎 namespace_id 조회: $NS"
NS_JSON="$(curl -fsS "${HDR[@]}" "$API/namespaces?search=$(urlenc "$NS")")"
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

GITLAB_HOST="$(echo "$GITLAB_URL" | sed -E 's#^https?://##' | sed -E 's#/.*##')"
REGISTRY_HOSTPORT="$GITLAB_HOST:$REG_PORT"
GITOPS_REPO_URL="$GITLAB_URL/$GITOPS_FULL.git"

say "=================================================="
say "토큰 3종 생성 중..."
TS="$(date +%Y%m%d%H%M%S)"

# 1. K8s Pull Token
REG_NAME="${PREFIX}-k8s-pull-${TS}"
REG_PULL_JSON="$(create_deploy_token "$APP_ID" "$REG_NAME" "read_registry" "$EXPIRES_AT")"
REGISTRY_PULL_USER="$(echo "$REG_PULL_JSON" | jq -r '.username')"
REGISTRY_PULL_TOKEN="$(echo "$REG_PULL_JSON" | jq -r '.token')"

# 2. ArgoCD Read Token
ARGO_NAME="${PREFIX}-argocd-read-${TS}"
ARGO_READ_JSON="$(create_deploy_token "$GITOPS_ID" "$ARGO_NAME" "read_repository" "$EXPIRES_AT")"
ARGO_GITOPS_READ_USER="$(echo "$ARGO_READ_JSON" | jq -r '.username')"
ARGO_GITOPS_READ_TOKEN="$(echo "$ARGO_READ_JSON" | jq -r '.token')"

# 3. CI Push Token
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

set_ci_var_safe "$APP_ID" "GITOPS_PUSH_USER"  "$GITOPS_PUSH_USER"  false false
set_ci_var_safe "$APP_ID" "GITOPS_PUSH_TOKEN" "$GITOPS_PUSH_TOKEN" true  false
set_ci_var_safe "$APP_ID" "GITOPS_REPO_URL"   "$GITOPS_REPO_URL"   false false

cat > "$OUT" <<ENV
# Generated by repo_Auto.sh
GITLAB_URL="$GITLAB_URL"
GITLAB_HOST="$GITLAB_HOST"
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
