#!/usr/bin/env bash
set -euo pipefail

say(){ echo -e "\033[0;32m$*\033[0m"; }
warn(){ echo -e "\033[1;33m$*\033[0m"; }
err(){ echo -e "\033[0;31m$*\033[0m"; }

echo "=================================================="
echo " 🗑️  OS 및 Containerd CA 인증서 신뢰 등록 취소"
echo "=================================================="

# ---------------------------------------------------------
# [인자 처리] 커맨드라인 인자 → 없으면 대화형 질의
# ---------------------------------------------------------
# 사용법 안내
# ./uninstall-ca.sh <레지스트리_HOST:PORT>
# 예) ./uninstall-ca.sh <GITLAB_IP>:5050
#     ./uninstall-ca.sh <GITLAB_IP>:5050
#
# .env 파일 연동 시:
#   source .env.gitops-lab
#   ./uninstall-ca.sh "${REGISTRY_HOSTPORT}"

REGISTRY_HOSTPORT="${1:-}"

# 레지스트리 주소 질의
if [[ -z "$REGISTRY_HOSTPORT" ]]; then
  echo
  echo "Q1) 취소할 GitLab Container Registry 주소를 입력하세요."
  echo "    - install-ca.sh 실행 시 입력했던 값과 동일하게 입력해야 합니다."
  echo "    - 형식: HOST:PORT (스킴 없이 입력)"
  echo "    - 예) <GITLAB_IP>:5050"
  echo "    - 예) <GITLAB_IP>:5050"
  echo "    ⚠️  http:// 또는 https:// 를 앞에 붙이면 안 됩니다."
  read -rp "    Registry HOST:PORT: " REGISTRY_HOSTPORT
fi

# ---------------------------------------------------------
# [입력값 검증]
# ---------------------------------------------------------
if [[ -z "$REGISTRY_HOSTPORT" ]]; then
  err "❌ Registry 주소가 입력되지 않았습니다."
  exit 1
fi

if [[ "$REGISTRY_HOSTPORT" =~ ^https?:// ]]; then
  err "❌ REGISTRY_HOSTPORT에 스킴(http/https)을 포함하면 안 됩니다."
  echo "   ✅ 올바른 형식 예: <GITLAB_IP>:5050"
  exit 1
fi

REGISTRY_HOST="${REGISTRY_HOSTPORT%%:*}"
CERTS_DIR="/etc/containerd/certs.d/${REGISTRY_HOSTPORT}"
OS_CA="/usr/local/share/ca-certificates/gitlab-ca.crt"
CONFIG_TOML="/etc/containerd/config.toml"

echo
warn "-------------------- 확인 --------------------"
warn " Registry 주소    : ${REGISTRY_HOSTPORT}"
warn " 삭제 대상 1      : ${OS_CA}"
warn " 삭제 대상 2      : ${CERTS_DIR}/"
warn " 수정 대상        : ${CONFIG_TOML} (config_path 항목 제거)"
warn "--------------------------------------------"
warn "⚠️  이 작업은 해당 레지스트리에 대한 모든 CA 신뢰 설정을 제거합니다."
read -rp "진행할까요? (y/n) [기본 n]: " CONFIRM
CONFIRM="${CONFIRM:-n}"
[[ "$CONFIRM" =~ ^[Yy]$ ]] || { echo "취소"; exit 0; }

# ---------------------------------------------------------
# [Step 1] OS 레벨 인증서 신뢰 제거
# ---------------------------------------------------------
echo -e "\n[1/3] OS 레벨 인증서 제거 중..."

if [[ -f "$OS_CA" ]]; then
  sudo rm -f "$OS_CA"
  say "  ✅ 삭제 완료: ${OS_CA}"
else
  warn "  ⏭ 대상 없음 (이미 삭제됨): ${OS_CA}"
fi

# 삭제 후 OS 인증서 목록 재갱신 (멱등: 파일 없어도 안전하게 실행됨)
sudo update-ca-certificates --fresh >/dev/null 2>&1 || sudo update-ca-certificates >/dev/null 2>&1 || true
say "✅ OS 인증서 목록 재갱신 완료"

# ---------------------------------------------------------
# [Step 2] Containerd certs.d 디렉토리 제거
# ---------------------------------------------------------
echo -e "\n[2/3] Containerd 인증서 디렉토리 제거 중..."

if [[ -d "$CERTS_DIR" ]]; then
  sudo rm -rf "$CERTS_DIR"
  say "  ✅ 삭제 완료: ${CERTS_DIR}/"
else
  warn "  ⏭ 대상 없음 (이미 삭제됨): ${CERTS_DIR}/"
fi

# ---------------------------------------------------------
# [Step 3] config.toml에서 config_path 및 빈 registry 섹션 제거
# ---------------------------------------------------------
echo -e "\n[3/3] containerd config.toml 복원 중..."

if [[ ! -f "$CONFIG_TOML" ]]; then
  warn "  ⏭ config.toml 없음 - 스킵"
else
  # config_path = "/etc/containerd/certs.d" 라인이 있을 때만 처리
  if grep -qE '^\s*config_path\s*=\s*"/etc/containerd/certs.d"' "$CONFIG_TOML"; then

    # config.toml 백업
    sudo cp -f "$CONFIG_TOML" "${CONFIG_TOML}.bak.$(date +%Y%m%d%H%M%S)"
    say "  📋 config.toml 백업 완료"

    # 1단계: config_path 라인 제거
    sudo sed -i '/^\s*config_path\s*=\s*"\/etc\/containerd\/certs\.d"/d' "$CONFIG_TOML"
    say "  ✅ config_path 라인 제거 완료"

    # 2단계: registry 섹션이 비어있으면(다른 키가 없으면) 섹션 헤더도 제거
    # 섹션 헤더 다음 줄이 비어있거나 다음 섹션이면 헤더만 있는 빈 섹션으로 판단
    if grep -qE '^\[plugins\."io\.containerd\.grpc\.v1\.cri"\.registry\]' "$CONFIG_TOML"; then
      # 섹션 헤더 바로 다음에 실질적인 키(= 포함 라인)가 없는 경우 헤더 제거
      SECTION_LINE=$(grep -nE '^\[plugins\."io\.containerd\.grpc\.v1\.cri"\.registry\]' "$CONFIG_TOML" | cut -d: -f1 | head -n1)
      NEXT_KEY=$(awk "NR>${SECTION_LINE} && /^\s*[a-zA-Z_].*=/{print; exit}" "$CONFIG_TOML" || true)
      NEXT_SECTION=$(awk "NR>${SECTION_LINE} && /^\[/{print; exit}" "$CONFIG_TOML" || true)

      if [[ -z "$NEXT_KEY" ]] || \
         { [[ -n "$NEXT_SECTION" ]] && [[ -z "$NEXT_KEY" ]]; }; then
        sudo sed -i '/^\[plugins\."io\.containerd\.grpc\.v1\.cri"\.registry\]/d' "$CONFIG_TOML"
        say "  ✅ 빈 registry 섹션 헤더 제거 완료"
      else
        warn "  ℹ️  registry 섹션에 다른 키가 있어 섹션 헤더는 유지합니다."
      fi
    fi

  else
    warn "  ⏭ config_path 항목 없음 - config.toml 수정 스킵 (이미 복원됨)"
  fi
fi

# Containerd 재시작으로 설정 반영
sudo systemctl restart containerd
say "✅ containerd 재시작 완료"

# ---------------------------------------------------------
# [최종 결과 출력]
# ---------------------------------------------------------
echo -e "\n=================================================="
say " 🎉 CA 신뢰 등록 취소가 완료되었습니다!"
echo "=================================================="
echo
echo "  🔍 취소 결과 검증 방법:"
echo "    # OS 인증서 제거 확인"
echo "    ls /usr/local/share/ca-certificates/gitlab-ca.crt 2>/dev/null || echo '✅ 삭제됨'"
echo
echo "    # containerd certs.d 제거 확인"
echo "    ls ${CERTS_DIR} 2>/dev/null || echo '✅ 삭제됨'"
echo
echo "    # curl 신뢰 거부 확인 (CA 제거 후 실패해야 정상)"
echo "    curl -v https://${REGISTRY_HOST} 2>&1 | grep -i 'certificate'"
echo "=================================================="
