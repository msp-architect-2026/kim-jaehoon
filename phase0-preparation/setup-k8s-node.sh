#!/bin/bash

# ==============================================================================
# Kubernetes Node Setup (통합 버전 - Dynamic IP / Bridged Mode Support)
# OS: Ubuntu 24.04 LTS / 22.04 LTS
# 기능: 브릿지 모드 DHCP 환경 지원, 완전한 노드 초기 설정
# ==============================================================================

set -e

# --- 변수 설정 ---
K8S_VERSION="1.29"

# 색상 변수
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}==================================================${NC}"
echo -e "${GREEN} 🚀 Kubernetes Node Setup (Bridged Mode)${NC}"
echo -e "${GREEN}    v${K8S_VERSION} - 통합 설정 스크립트${NC}"
echo -e "${GREEN}==================================================${NC}"

# --- 0. Root 권한 체크 ---
if [ "$EUID" -ne 0 ]; then
  echo -e "${RED}❌ Root 권한으로 실행해야 합니다. (sudo ./스크립트이름.sh)${NC}"
  exit 1
fi

# --- 1. Sudoers 설정 (실습 편의성) ---
echo -e "\n${YELLOW}[1/10] Sudoers 설정...${NC}"
if [ -n "$SUDO_USER" ]; then
    echo "$SUDO_USER ALL=(ALL) NOPASSWD:ALL" | sudo tee /etc/sudoers.d/$SUDO_USER > /dev/null
    echo "✅ $SUDO_USER에 대한 sudoers 설정 완료"
fi

# --- 2. 동적 IP 감지 및 호스트네임 설정 ---
echo -e "\n${YELLOW}[2/10] 네트워크 설정 확인 및 호스트네임 설정...${NC}"

# 현재 외부와 통신 가능한 실제 IP 감지
CURRENT_IP=$(ip route get 8.8.8.8 | awk -F"src " 'NR==1{split($2,a," ");print a[1]}')

echo "▶ 현재 감지된 IP: $CURRENT_IP (브릿지 모드)"
echo ""
echo "이 노드의 역할은 무엇입니까?"
echo "  1) Master Node (k8s-master)"
echo "  2) Worker Node 1 (k8s-worker1)"
echo "  3) Worker Node 2 (k8s-worker2)"
echo "  4) 직접 입력 (Custom)"
read -p "선택 > " ROLE_CHOICE

case $ROLE_CHOICE in
    1) MY_HOSTNAME="k8s-master" ;;
    2) MY_HOSTNAME="k8s-worker1" ;;
    3) MY_HOSTNAME="k8s-worker2" ;;
    4) read -p "사용할 호스트네임 입력: " MY_HOSTNAME ;;
    *) echo -e "${RED}잘못된 선택입니다.${NC}"; exit 1 ;;
esac

# 호스트네임 적용
sudo hostnamectl set-hostname "$MY_HOSTNAME"
echo -e "${GREEN}✅ 호스트네임 변경 완료: $MY_HOSTNAME${NC}"

# Machine-ID 리셋 (골든 이미지 복제 시 필수)
if [ -f /etc/machine-id ]; then
    sudo rm -f /etc/machine-id
    sudo dbus-uuidgen --ensure=/etc/machine-id
    sudo systemd-machine-id-setup
    echo "✅ Machine-ID 리셋 완료"
fi

# --- 3. /etc/hosts 파일 대화형 구성 ---
echo -e "\n${YELLOW}[3/10] 클러스터 노드 정보 입력 (/etc/hosts 구성)${NC}"
echo "⚠️ 브릿지 모드이므로 각 노드의 IP를 확인하여 입력해주세요."
echo "   (모든 노드가 서로 통신하려면 정확해야 합니다)"
echo ""

# 사용자 입력 받기
read -p "마스터 노드(k8s-master)의 IP는? : " MASTER_IP
read -p "워커1 노드(k8s-worker1)의 IP는? : " WORKER1_IP
read -p "워커2 노드(k8s-worker2)의 IP는? : " WORKER2_IP

# /etc/hosts 파일 설정
echo "" | sudo tee -a /etc/hosts
echo "# Kubernetes Cluster Nodes" | sudo tee -a /etc/hosts
echo "$MASTER_IP k8s-master" | sudo tee -a /etc/hosts
echo "$WORKER1_IP k8s-worker1" | sudo tee -a /etc/hosts
echo "$WORKER2_IP k8s-worker2" | sudo tee -a /etc/hosts

echo -e "${GREEN}✅ /etc/hosts 설정 완료!${NC}"
cat /etc/hosts | grep k8s

# --- 4. 패키지 업데이트 및 필수 도구 설치 ---
echo -e "\n${YELLOW}[4/10] 시스템 업데이트 및 필수 패키지 설치...${NC}"
sudo apt update
sudo apt install -y ca-certificates curl wget vim git net-tools tree htop openssh-server gnupg lsb-release

# VirtualBox Guest Utils 설치 (클립보드 공유 등)
echo "VirtualBox Guest Utilities 설치 중..."
sudo apt install -y virtualbox-guest-utils virtualbox-guest-x11 build-essential dkms
echo -e "${GREEN}✅ 필수 패키지 설치 완료${NC}"

# --- 5. Swap 비활성화 (영구 적용) ---
echo -e "\n${YELLOW}[5/10] Swap 비활성화...${NC}"
sudo swapoff -a
# /etc/fstab에서 swap 라인 주석 처리
sudo sed -i '/\sswap\s/s/^#\?/#/' /etc/fstab
echo -e "${GREEN}✅ Swap off 완료${NC}"

# --- 6. 방화벽 해제 ---
echo -e "\n${YELLOW}[6/10] 방화벽(UFW) 비활성화...${NC}"
sudo ufw disable
echo -e "${GREEN}✅ UFW Disabled${NC}"

# --- 7. 커널 모듈 로드 및 네트워크 파라미터 설정 ---
echo -e "\n${YELLOW}[7/10] 커널 모듈 및 네트워크 파라미터 설정...${NC}"

# 커널 모듈 설정
cat <<EOF | sudo tee /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF

sudo modprobe overlay
sudo modprobe br_netfilter

# 네트워크 파라미터 설정 (브릿지 통신 허용)
cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF

sudo sysctl --system
echo -e "${GREEN}✅ 커널 설정 완료${NC}"

# --- 8. Timezone 설정 ---
echo -e "\n${YELLOW}[8/10] Timezone(Asia/Seoul) 설정...${NC}"
sudo timedatectl set-timezone Asia/Seoul
echo -e "${GREEN}✅ Timezone 설정 완료${NC}"

# --- 9. Containerd (런타임) 설치 및 설정 ---
echo -e "\n${YELLOW}[9/10] Containerd 설치 및 설정...${NC}"
sudo apt install -y containerd

# 기본 설정 파일 생성
sudo mkdir -p /etc/containerd
sudo containerd config default | sudo tee /etc/containerd/config.toml >/dev/null

# SystemdCgroup = true 로 변경 (K8s 필수 설정)
sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml

# 재시작 및 활성화
sudo systemctl restart containerd
sudo systemctl enable containerd
echo -e "${GREEN}✅ Containerd 설정 완료 (SystemdCgroup=true)${NC}"

# --- 10. Kubernetes 패키지 설치 (kubeadm, kubelet, kubectl) ---
echo -e "\n${YELLOW}[10/10] Kubernetes v${K8S_VERSION} 패키지 설치...${NC}"
sudo mkdir -p -m 755 /etc/apt/keyrings

# 기존 키링 정리 (재설치 시 오류 방지)
[ -f /etc/apt/keyrings/kubernetes-apt-keyring.gpg ] && sudo rm /etc/apt/keyrings/kubernetes-apt-keyring.gpg

# GPG 키 다운로드
curl -fsSL https://pkgs.k8s.io/core:/stable:/v${K8S_VERSION}/deb/Release.key | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg

# 레포지토리 추가
echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v${K8S_VERSION}/deb/ /" | sudo tee /etc/apt/sources.list.d/kubernetes.list >/dev/null

# 설치
sudo apt update
sudo apt install -y kubelet kubeadm kubectl

# 버전 고정 (자동 업데이트 방지)
sudo apt-mark hold kubelet kubeadm kubectl
echo -e "${GREEN}✅ Kubernetes 패키지 설치 완료${NC}"

# --- 최종 상태 출력 ---
echo -e "\n${GREEN}==================================================${NC}"
echo -e "${GREEN} 🎉 모든 설정이 완료되었습니다!${NC}"
echo -e "${GREEN}==================================================${NC}"

echo -e "\n📋 설정된 클러스터 정보:"
echo -e "   - 현재 노드: ${GREEN}$MY_HOSTNAME${NC} (IP: $CURRENT_IP)"
echo -e "   - Master : $MASTER_IP"
echo -e "   - Worker1: $WORKER1_IP"
echo -e "   - Worker2: $WORKER2_IP"

echo -e "\n🔍 상태 점검:"
echo -e "   - Swap: $(free -h | grep Swap | awk '{print $2}') ${GREEN}(0B여야 함)${NC}"
echo -e "   - UFW: $(sudo ufw status | grep Status)"
echo -e "   - Containerd: ${GREEN}$(systemctl is-active containerd)${NC}"
echo -e "   - Kubeadm Version: ${GREEN}$(kubeadm version -o short)${NC}"
echo -e "   - Timezone: ${GREEN}$(timedatectl | grep "Time zone" | awk '{print $3}')${NC}"

echo -e "\n${YELLOW}==================================================${NC}"
echo -e "${YELLOW}📌 다음 단계:${NC}"
echo -e "${YELLOW}==================================================${NC}"
echo -e "👉 ${GREEN}마스터 노드${NC}라면:"
echo -e "   sudo kubeadm init --pod-network-cidr=10.244.0.0/16 --apiserver-advertise-address=$MASTER_IP"
echo -e ""
echo -e "👉 ${GREEN}워커 노드${NC}라면:"
echo -e "   마스터 노드에서 'kubeadm join' 명령어를 받아 실행하세요."
echo -e "${YELLOW}==================================================${NC}"

echo ""
read -p "지금 재부팅 하시겠습니까? (y/n): " REBOOT_YN
if [ "$REBOOT_YN" == "y" ] || [ "$REBOOT_YN" == "Y" ]; then
    echo -e "${GREEN}재부팅을 시작합니다...${NC}"
    sudo reboot
else
    echo -e "${YELLOW}재부팅을 건너뜁니다. 변경사항 적용을 위해 나중에 재부팅해주세요.${NC}"
fi
