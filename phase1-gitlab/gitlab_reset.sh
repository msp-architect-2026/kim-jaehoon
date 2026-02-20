#!/bin/bash

# ==============================================================================
# GitLab & Runner 완전 삭제 스크립트 (시스템 설정 복구 포함)
# 기능:
#   1. Docker 컨테이너 및 데이터 삭제
#   2. Insecure Registry 설정 제거 (/etc/docker/daemon.json)
#   3. Swap 파일 삭제 및 /etc/fstab 복구
#   4. Docker 네트워크 및 이미지 정리
# ==============================================================================

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${RED}==================================================${NC}"
echo -e "${RED} 🚨 GitLab 전체 삭제 및 시스템 복구${NC}"
echo -e "${RED}==================================================${NC}"

if [ "$EUID" -ne 0 ]; then
  echo -e "${RED}❌ Root 권한 필요 (sudo ./cleanup_v2.sh)${NC}"
  exit 1
fi

echo -e "\n${YELLOW}⚠️  경고: 다음 항목이 모두 삭제됩니다.${NC}"
echo "   - GitLab/Runner 컨테이너 및 데이터 (/home/gitlab, /home/gitlab-runner)"
echo "   - Docker Insecure Registry 설정"
echo "   - Swap 파일 (/swapfile)"
echo ""
read -p "진행하시겠습니까? (y/n): " CONFIRM
if [[ "$CONFIRM" != "y" && "$CONFIRM" != "Y" ]]; then
    echo "취소됨."
    exit 0
fi

# 1. 컨테이너 삭제
echo -e "\n${YELLOW}[1/5] 컨테이너 삭제...${NC}"
sudo docker stop gitlab gitlab-runner || true
sudo docker rm gitlab gitlab-runner || true
echo "✅ 컨테이너 삭제 완료"

# 2. 데이터 폴더 삭제
echo -e "\n${YELLOW}[2/5] 데이터 폴더 삭제...${NC}"
sudo rm -rf /home/gitlab /home/gitlab-runner
echo "✅ 데이터 폴더 삭제 완료"

# 3. Docker 설정 복구 (daemon.json)
echo -e "\n${YELLOW}[3/5] Docker 설정 복구...${NC}"
if [ -f /etc/docker/daemon.json ]; then
    # insecure-registries 설정이 있으면 파일 삭제 (혹은 백업 후 수정)
    # 여기서는 깔끔하게 삭제하고 Docker 재시작
    sudo rm /etc/docker/daemon.json
    sudo systemctl restart docker
    echo "✅ /etc/docker/daemon.json 삭제 및 Docker 재시작 완료"
else
    echo "ℹ️  daemon.json 파일이 없습니다."
fi

# 4. Swap 삭제 (선택 사항)
echo -e "\n${YELLOW}[4/5] Swap 파일 삭제...${NC}"
if grep -q "/swapfile" /etc/fstab; then
    sudo swapoff /swapfile || true
    # /etc/fstab에서 /swapfile 라인 삭제
    sudo sed -i '/\/swapfile/d' /etc/fstab
    sudo rm -f /swapfile
    echo "✅ Swap 파일 삭제 및 fstab 복구 완료"
else
    echo "ℹ️  Swap 설정이 발견되지 않았습니다."
fi

# 5. Docker 청소
echo -e "\n${YELLOW}[5/5] Docker 잔여 파일 정리...${NC}"
sudo docker network prune -f
# 이미지는 굳이 안 지워도 되지만, 용량 확보를 위해 지우고 싶으면 주석 해제
# sudo docker rmi gitlab/gitlab-ee:16.1.0-ee.0 gitlab/gitlab-runner:alpine || true

echo -e "\n${GREEN}==================================================${NC}"
echo -e "${GREEN} ✨ 시스템이 초기화되었습니다.${NC}"
echo -e "${GREEN}==================================================${NC}"
