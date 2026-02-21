#!/bin/bash
set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${RED}==================================================${NC}"
echo -e "${RED} 🚨 GitLab 전체 삭제 및 시스템 복구 (HTTPS/CA 대응)${NC}"
echo -e "${RED}==================================================${NC}"

if [ "$EUID" -ne 0 ]; then
  echo -e "${RED}❌ Root 권한 필요 (sudo ./cleanup_v3.sh)${NC}"
  exit 1
fi

echo -e "\n${YELLOW}⚠️  경고: 다음 항목이 모두 삭제/정리될 수 있습니다.${NC}"
echo "   - GitLab/Runner 컨테이너 및 데이터 (/home/gitlab, /home/gitlab-runner)"
echo "   - Docker certs.d 의 *:5050 CA 디렉토리(선택)"
echo "   - (선택) /etc/docker/daemon.json 백업 후 제거/복구"
echo "   - (선택) Swap 파일 (/swapfile)"
echo ""
read -p "진행하시겠습니까? (y/n): " CONFIRM
if [[ "$CONFIRM" != "y" && "$CONFIRM" != "Y" ]]; then
  echo "취소됨."
  exit 0
fi

# 1) 컨테이너 삭제
echo -e "\n${YELLOW}[1/7] 컨테이너 삭제...${NC}"
docker stop gitlab gitlab-runner 2>/dev/null || true
docker rm   gitlab gitlab-runner 2>/dev/null || true
echo "✅ 컨테이너 삭제 완료"

# (옵션) 혹시 compose 프로젝트가 남아있으면(컨테이너 이름 다를 때) 정리
# docker ps -a --format '{{.Names}}' | grep -E 'gitlab' && ...

# 2) 데이터 폴더 삭제
echo -e "\n${YELLOW}[2/7] 데이터 폴더 삭제...${NC}"
rm -rf /home/gitlab /home/gitlab-runner
echo "✅ 데이터 폴더 삭제 완료"

# 3) Docker certs.d 정리 (HTTPS 사설 CA 흔적)
echo -e "\n${YELLOW}[3/7] Docker certs.d(Registry CA) 정리...${NC}"
if [ -d /etc/docker/certs.d ]; then
  echo "현재 certs.d 항목:"
  ls -1 /etc/docker/certs.d || true
  echo ""
  read -p "  ▶ /etc/docker/certs.d/*:5050 디렉토리도 삭제할까요? (y/n) [기본 y]: " DEL_CERTS
  DEL_CERTS="${DEL_CERTS:-y}"
  if [[ "$DEL_CERTS" =~ ^[Yy]$ ]]; then
    # GitLab Registry 기본 포트(5050) 대상으로만 제거
    find /etc/docker/certs.d -maxdepth 1 -type d -name "*:5050" -print -exec rm -rf {} \; || true
    echo "✅ certs.d *:5050 정리 완료"
  else
    echo "⏭ certs.d 정리 스킵"
  fi
else
  echo "ℹ️  /etc/docker/certs.d 없음"
fi

# 4) Docker daemon.json 처리 (삭제 대신 백업 권장)
echo -e "\n${YELLOW}[4/7] Docker daemon.json 처리...${NC}"
if [ -f /etc/docker/daemon.json ]; then
  TS="$(date +%Y%m%d%H%M%S)"
  echo "daemon.json 발견. 백업 후 처리합니다: /etc/docker/daemon.json.bak.${TS}"
  cp -a /etc/docker/daemon.json "/etc/docker/daemon.json.bak.${TS}"

  read -p "  ▶ daemon.json을 삭제할까요? (y/n) [기본 n]: " DEL_DAEMON
  DEL_DAEMON="${DEL_DAEMON:-n}"
  if [[ "$DEL_DAEMON" =~ ^[Yy]$ ]]; then
    rm -f /etc/docker/daemon.json
    echo "✅ daemon.json 삭제 완료(백업 보관됨)"
  else
    echo "⏭ daemon.json 유지(백업만 생성)"
  fi

  systemctl restart docker || true
  echo "✅ Docker 재시작 완료"
else
  echo "ℹ️  daemon.json 파일이 없습니다."
fi

# 5) Swap 삭제 (선택)
echo -e "\n${YELLOW}[5/7] Swap 파일 삭제...${NC}"
if grep -q "/swapfile" /etc/fstab; then
  swapoff /swapfile 2>/dev/null || true
  sed -i '/\/swapfile/d' /etc/fstab
  rm -f /swapfile
  echo "✅ Swap 파일 삭제 및 fstab 복구 완료"
else
  echo "ℹ️  Swap 설정(/swapfile)이 발견되지 않았습니다."
fi

# 6) (선택) SELinux 복구 (Rocky에서 설치 스크립트가 permissive로 바꾼 경우)
echo -e "\n${YELLOW}[6/7] SELinux 설정 복구(선택)...${NC}"
if [ -f /etc/selinux/config ]; then
  echo "현재 SELinux 설정:"
  grep -E '^SELINUX=' /etc/selinux/config || true
  read -p "  ▶ SELinux를 enforcing으로 되돌릴까요? (y/n) [기본 n]: " DO_SELINUX
  DO_SELINUX="${DO_SELINUX:-n}"
  if [[ "$DO_SELINUX" =~ ^[Yy]$ ]]; then
    sed -i 's/^SELINUX=.*/SELINUX=enforcing/' /etc/selinux/config
    echo "✅ /etc/selinux/config 를 enforcing으로 변경(재부팅 시 적용)"
    # setenforce 1은 permissive->enforcing 전환이 막힐 수 있어 시도만
    setenforce 1 2>/dev/null || true
  else
    echo "⏭ SELinux 복구 스킵"
  fi
else
  echo "ℹ️  /etc/selinux/config 없음(SELinux 미사용 환경일 수 있음)"
fi

# 7) Docker 청소
echo -e "\n${YELLOW}[7/7] Docker 잔여 정리...${NC}"
docker network prune -f || true
docker volume prune -f || true
# 이미지까지 싹 지우려면 아래 주석 해제(주의!)
# docker image prune -a -f || true

echo -e "\n${GREEN}==================================================${NC}"
echo -e "${GREEN} ✨ 초기화 완료${NC}"
echo -e "${GREEN}==================================================${NC}"
