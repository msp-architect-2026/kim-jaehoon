#!/usr/bin/env bash
set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

say(){  echo -e "${GREEN}$*${NC}"; }
warn(){ echo -e "${YELLOW}$*${NC}"; }
err(){  echo -e "${RED}$*${NC}"; }

if [[ "${EUID}" -ne 0 ]]; then
  err "❌ Root 권한 필요 (sudo ./cleanup_gitlab_https.sh [envfile])"
  exit 1
fi

# --- env 로드(설치 스크립트와 동일하게 맞춤) ---
ENV_FILE="${1:-./.env.gitlab-https}"
if [[ -f "$ENV_FILE" ]]; then
  # shellcheck disable=SC1090
  source "$ENV_FILE"
  say "✅ env 로드: $ENV_FILE"
else
  warn "⚠️ env 파일 없음: $ENV_FILE (기본값/질문으로 진행)"
fi

# 설치 스크립트 기본값과 동일
GITLAB_HOME="${GITLAB_HOME:-/home/gitlab}"
RUNNER_HOME="${RUNNER_HOME:-/home/gitlab-runner}"
REGISTRY_PORT="${REGISTRY_PORT:-5050}"

# 설치 과정에서 쓰는 host/ip 정보는 cleanup에선 선택사항
HOST_IP="${HOST_IP:-}"
EXTERNAL_HOST="${EXTERNAL_HOST:-}"

echo -e "${RED}==================================================${NC}"
echo -e "${RED} 🚨 GitLab 전체 삭제 및 시스템 복구 (HTTPS/CA 대응)${NC}"
echo -e "${RED}==================================================${NC}"

warn "\n⚠️  경고: 다음 항목이 모두 삭제/정리될 수 있습니다."
echo "   - GitLab/Runner 컨테이너 및 데이터 (${GITLAB_HOME}, ${RUNNER_HOME})"
echo "   - Docker certs.d 레지스트리 CA 디렉토리(선택)"
echo "   - OS trust anchors의 gitlab-local-ca.crt(선택)"
echo "   - (선택) /etc/docker/daemon.json 백업 후 제거/복구"
echo "   - (선택) Swap 파일 (/swapfile)"
echo ""
read -rp "진행하시겠습니까? (y/n): " CONFIRM
[[ "$CONFIRM" =~ ^[Yy]$ ]] || { echo "취소됨."; exit 0; }

# 1) compose down (있으면) + 컨테이너 삭제
warn "\n[1/8] GitLab/Runner 컨테이너 정리..."
if [[ -f "${GITLAB_HOME}/docker-compose.yml" ]]; then
  (cd "${GITLAB_HOME}" && docker compose down || true)
fi
if [[ -f "${RUNNER_HOME}/docker-compose.yml" ]]; then
  (cd "${RUNNER_HOME}" && docker compose down || true)
fi

# 컨테이너 이름 고정인 경우도 처리
docker stop gitlab gitlab-runner 2>/dev/null || true
docker rm   gitlab gitlab-runner 2>/dev/null || true
say "✅ 컨테이너 정리 완료"

# 2) 데이터 폴더 삭제
warn "\n[2/8] 데이터 폴더 삭제..."
rm -rf "${GITLAB_HOME}" "${RUNNER_HOME}"
say "✅ 데이터 폴더 삭제 완료"

# 3) Docker certs.d 정리
warn "\n[3/8] Docker certs.d(Registry CA) 정리..."
if [[ -d /etc/docker/certs.d ]]; then
  echo "현재 certs.d 항목:"
  ls -1 /etc/docker/certs.d || true
  echo ""

  read -rp "  ▶ 레지스트리 포트는 무엇입니까? [기본 ${REGISTRY_PORT}]: " REGP
  REGP="${REGP:-$REGISTRY_PORT}"

  read -rp "  ▶ /etc/docker/certs.d/*:${REGP} 를 삭제할까요? (y/n) [기본 y]: " DEL_WILDCARD
  DEL_WILDCARD="${DEL_WILDCARD:-y}"
  if [[ "$DEL_WILDCARD" =~ ^[Yy]$ ]]; then
    find /etc/docker/certs.d -maxdepth 1 -type d -name "*:${REGP}" -print -exec rm -rf {} \; || true
    say "✅ certs.d *:${REGP} 정리 완료"
  else
    warn "⏭ wildcard 삭제 스킵"
  fi

  # host/ip가 env에 있으면 해당 디렉토리도 직접 제거(더 정확)
  if [[ -n "${EXTERNAL_HOST}" ]]; then
    rm -rf "/etc/docker/certs.d/${EXTERNAL_HOST}:${REGP}" 2>/dev/null || true
  fi
  if [[ -n "${HOST_IP}" ]]; then
    rm -rf "/etc/docker/certs.d/${HOST_IP}:${REGP}" 2>/dev/null || true
  fi

  systemctl restart docker 2>/dev/null || true
  say "✅ Docker 재시작 완료"
else
  warn "ℹ️  /etc/docker/certs.d 없음"
fi

# 4) OS trust anchor 제거 (설치 스크립트에서 추가한 것)
warn "\n[4/8] OS CA trust(anchor) 정리..."
ANCHOR="/etc/pki/ca-trust/source/anchors/gitlab-local-ca.crt"
if [[ -f "$ANCHOR" ]]; then
  echo "anchor 발견: $ANCHOR"
  read -rp "  ▶ 이 anchor를 삭제하고 update-ca-trust 할까요? (y/n) [기본 y]: " DEL_ANCHOR
  DEL_ANCHOR="${DEL_ANCHOR:-y}"
  if [[ "$DEL_ANCHOR" =~ ^[Yy]$ ]]; then
    rm -f "$ANCHOR"
    update-ca-trust 2>/dev/null || true
    say "✅ anchor 삭제 + update-ca-trust 완료"
  else
    warn "⏭ anchor 삭제 스킵"
  fi
else
  warn "ℹ️  anchor 없음: $ANCHOR"
fi

# 5) Docker daemon.json 처리(삭제 대신 백업 권장)
warn "\n[5/8] Docker daemon.json 처리..."
if [[ -f /etc/docker/daemon.json ]]; then
  TS="$(date +%Y%m%d%H%M%S)"
  say "daemon.json 발견. 백업: /etc/docker/daemon.json.bak.${TS}"
  cp -a /etc/docker/daemon.json "/etc/docker/daemon.json.bak.${TS}"

  read -rp "  ▶ daemon.json을 삭제할까요? (y/n) [기본 n]: " DEL_DAEMON
  DEL_DAEMON="${DEL_DAEMON:-n}"
  if [[ "$DEL_DAEMON" =~ ^[Yy]$ ]]; then
    rm -f /etc/docker/daemon.json
    say "✅ daemon.json 삭제 완료(백업 보관됨)"
  else
    warn "⏭ daemon.json 유지(백업만 생성)"
  fi

  systemctl restart docker 2>/dev/null || true
  say "✅ Docker 재시작 완료"
else
  warn "ℹ️  daemon.json 없음"
fi

# 6) Swap 삭제 (선택)
warn "\n[6/8] Swap 파일 삭제..."
if grep -q "/swapfile" /etc/fstab; then
  swapoff /swapfile 2>/dev/null || true
  sed -i '/\/swapfile/d' /etc/fstab
  rm -f /swapfile
  say "✅ Swap 파일 삭제 및 fstab 복구 완료"
else
  warn "ℹ️  Swap(/swapfile) 설정 없음"
fi

# 7) SELinux 복구 (선택)
warn "\n[7/8] SELinux 설정 복구(선택)..."
if [[ -f /etc/selinux/config ]]; then
  echo "현재 SELinux 설정:"
  grep -E '^SELINUX=' /etc/selinux/config || true
  read -rp "  ▶ SELinux를 enforcing으로 되돌릴까요? (y/n) [기본 n]: " DO_SELINUX
  DO_SELINUX="${DO_SELINUX:-n}"
  if [[ "$DO_SELINUX" =~ ^[Yy]$ ]]; then
    sed -i 's/^SELINUX=.*/SELINUX=enforcing/' /etc/selinux/config
    say "✅ /etc/selinux/config enforcing 변경(재부팅 시 적용)"
    setenforce 1 2>/dev/null || true
  else
    warn "⏭ SELinux 복구 스킵"
  fi
else
  warn "ℹ️  /etc/selinux/config 없음"
fi

# 8) Docker 잔여 정리
warn "\n[8/8] Docker 잔여 정리..."
docker network prune -f 2>/dev/null || true
docker volume prune -f 2>/dev/null || true
# docker image prune -a -f || true

echo -e "\n${GREEN}==================================================${NC}"
echo -e "${GREEN} ✨ 초기화 완료${NC}"
echo -e "${GREEN}==================================================${NC}"
