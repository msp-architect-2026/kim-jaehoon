#!/usr/bin/env bash

# ==============================================================================
# Kubernetes Node Setup (Ubuntu Server 기준 / Bridged DHCP 지원)
# OS: Ubuntu 24.04 LTS / 22.04 LTS
# 목적: 노드 공통 초기설정 + containerd + kubeadm/kubelet/kubectl 설치
# 전제:
#  - VM 복제 안 함  → machine-id 리셋 제거
#  - sudoers 설정 안 함 → NOPASSWD 제거
#  - 방화벽은 일단 해제하고 진행 → UFW disable/stop/disable 포함
#  - CNI: Calico (Tigera Operator) 사용 예정
# ==============================================================================

set -euo pipefail

# --- 변수 설정 ---
K8S_VERSION="1.29"                 # pkgs.k8s.io stable minor
POD_CIDR_DEFAULT="10.244.0.0/16"   # kubeadm init 안내용 (Tigera Operator IPPool CIDR과 맞추기)

# 색상 변수
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

say(){ echo -e "${GREEN}$*${NC}"; }
warn(){ echo -e "${YELLOW}$*${NC}"; }
err(){ echo -e "${RED}$*${NC}"; }

echo -e "${GREEN}==================================================${NC}"
echo -e "${GREEN} 🚀 Kubernetes Node Setup (Ubuntu Server / Bridged)${NC}"
echo -e "${GREEN}    Kubernetes v${K8S_VERSION} - Node Bootstrap${NC}"
echo -e "${GREEN}==================================================${NC}"

# --- 0. Root 권한 체크 ---
if [ "${EUID}" -ne 0 ]; then
  err "❌ Root 권한으로 실행해야 합니다. (sudo ./node-setup.sh)"
  exit 1
fi

# --- 1/10. 동적 IP 감지 + 호스트네임 설정 ---
echo -e "\n${YELLOW}[1/10] 네트워크 확인 및 호스트네임 설정...${NC}"

CURRENT_IP="$(ip route get 8.8.8.8 2>/dev/null | awk -F"src " 'NR==1{split($2,a," ");print a[1]}')"
if [[ -z "${CURRENT_IP}" ]]; then
  DEFAULT_IF="$(ip route | awk '/default/ {print $5; exit}')"
  CURRENT_IP="$(ip -4 addr show "${DEFAULT_IF}" | awk '/inet / {print $2}' | cut -d/ -f1 | head -n1)"
fi

echo "▶ 감지된 현재 IP: ${CURRENT_IP}"
echo ""
read -rp "이 노드의 호스트네임을 입력하세요 (예: master, k8s-master 등): " MY_HOSTNAME

hostnamectl set-hostname "${MY_HOSTNAME}"
say "✅ 호스트네임 변경 완료: ${MY_HOSTNAME}"

# --- 2/10. /etc/hosts 구성(중복 방지) ---
echo -e "\n${YELLOW}[2/10] 클러스터 노드 정보 입력 (/etc/hosts 구성)...${NC}"
echo "⚠️ 브릿지 모드이므로 각 노드 IP와 호스트네임을 직접 입력하세요."
echo ""

read -rp "마스터 노드 IP: " MASTER_IP
read -rp "마스터 노드 호스트네임: " MASTER_HOSTNAME

read -rp "워커1 노드 IP: " WORKER1_IP
read -rp "워커1 노드 호스트네임: " WORKER1_HOSTNAME

read -rp "워커2 노드 IP: " WORKER2_IP
read -rp "워커2 노드 호스트네임: " WORKER2_HOSTNAME

# localhost 라인이 없으면 최상단에 보강(혹시 깨진 환경 대비)
if ! grep -qE '^\s*127\.0\.0\.1\s+localhost\b' /etc/hosts; then
  tmp="$(mktemp)"
  {
    echo "127.0.0.1 localhost"
    cat /etc/hosts
  } > "${tmp}"
  cat "${tmp}" > /etc/hosts
  rm -f "${tmp}"
fi

# 기존 k8s 클러스터 엔트리 제거 (변수 기반 동적 패턴 - 중복 방지)
tmp="$(mktemp)"
awk -v h1="${MASTER_HOSTNAME}" \
    -v h2="${WORKER1_HOSTNAME}" \
    -v h3="${WORKER2_HOSTNAME}" \
'
  $0 ~ "(^|[[:space:]])"h1"([[:space:]]|$)" { next }
  $0 ~ "(^|[[:space:]])"h2"([[:space:]]|$)" { next }
  $0 ~ "(^|[[:space:]])"h3"([[:space:]]|$)" { next }
  /^# Kubernetes Cluster Nodes$/ { next }
  { print }
' /etc/hosts > "${tmp}"

cat >> "${tmp}" <<EOF

# Kubernetes Cluster Nodes
${MASTER_IP} ${MASTER_HOSTNAME}
${WORKER1_IP} ${WORKER1_HOSTNAME}
${WORKER2_IP} ${WORKER2_HOSTNAME}
EOF

cat "${tmp}" > /etc/hosts
rm -f "${tmp}"

say "✅ /etc/hosts 설정 완료!"
grep -E "${MASTER_HOSTNAME}|${WORKER1_HOSTNAME}|${WORKER2_HOSTNAME}" /etc/hosts || true

# --- 3/10. 패키지 업데이트 및 필수 도구 설치(서버 기준) ---
echo -e "\n${YELLOW}[3/10] 시스템 업데이트 및 필수 패키지 설치...${NC}"
apt-get update -y
apt-get install -y \
  ca-certificates curl wget vim git \
  net-tools tree htop openssh-server \
  gnupg lsb-release \
  conntrack socat ebtables ipset

say "✅ 필수 패키지 설치 완료"

# --- 4/10. Swap 비활성화(영구) ---
echo -e "\n${YELLOW}[4/10] Swap 비활성화...${NC}"
swapoff -a || true
# /etc/fstab에서 swap 라인 주석 처리
sed -i '/\sswap\s/s/^#\?/#/' /etc/fstab
say "✅ Swap off 완료"

# --- 5/10. 방화벽(UFW) 비활성화(진행 우선) ---
echo -e "\n${YELLOW}[5/10] 방화벽(UFW) 비활성화...${NC}"
if command -v ufw >/dev/null 2>&1; then
  ufw disable || true
fi
systemctl stop ufw 2>/dev/null || true
systemctl disable ufw 2>/dev/null || true
say "✅ UFW Disabled (stop/disable 포함)"

# --- 6/10. 커널 모듈 로드 및 네트워크 파라미터 설정 ---
echo -e "\n${YELLOW}[6/10] 커널 모듈 및 네트워크 파라미터 설정...${NC}"
cat > /etc/modules-load.d/k8s.conf <<'EOF'
overlay
br_netfilter
EOF

modprobe overlay || true
modprobe br_netfilter || true

cat > /etc/sysctl.d/k8s.conf <<'EOF'
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF

sysctl --system >/dev/null
say "✅ 커널/네트워크 설정 완료"

# --- 7/10. Timezone 설정 ---
echo -e "\n${YELLOW}[7/10] Timezone(Asia/Seoul) 설정...${NC}"
timedatectl set-timezone Asia/Seoul
say "✅ Timezone 설정 완료"

# --- 8/10. Containerd 설치 및 설정 ---
echo -e "\n${YELLOW}[8/10] Containerd 설치 및 설정...${NC}"
apt-get install -y containerd

mkdir -p /etc/containerd
containerd config default > /etc/containerd/config.toml

# SystemdCgroup = true (K8s 권장)
sed -i -E 's/^(\s*SystemdCgroup\s*=\s*)false/\1true/' /etc/containerd/config.toml

systemctl restart containerd
systemctl enable containerd
say "✅ Containerd 설정 완료 (SystemdCgroup=true)"

# --- 9/10. Kubernetes 패키지 설치 (kubeadm, kubelet, kubectl) ---
echo -e "\n${YELLOW}[9/10] Kubernetes v${K8S_VERSION} 패키지 설치...${NC}"
mkdir -p -m 755 /etc/apt/keyrings

# 키링 정리(재실행 안전)
rm -f /etc/apt/keyrings/kubernetes-apt-keyring.gpg || true

curl -fsSL "https://pkgs.k8s.io/core:/stable:/v${K8S_VERSION}/deb/Release.key" \
  | gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg

echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v${K8S_VERSION}/deb/ /" \
  > /etc/apt/sources.list.d/kubernetes.list

apt-get update -y
apt-get install -y kubelet kubeadm kubectl
apt-mark hold kubelet kubeadm kubectl
say "✅ Kubernetes 패키지 설치 완료 (hold 적용)"

# --- 10/10. 최종 상태 출력 ---
echo -e "\n${YELLOW}[10/10] 최종 상태 점검...${NC}"

TZ="$(timedatectl show -p Timezone --value 2>/dev/null || echo unknown)"
CTR_STATE="$(systemctl is-active containerd 2>/dev/null || echo unknown)"
KADM_VER="$(kubeadm version -o short 2>/dev/null || echo unknown)"

if swapon --show --noheadings 2>/dev/null | grep -q .; then
  SWAP_STATE="ON (비활성화 필요)"
else
  SWAP_STATE="OFF"
fi

echo -e "\n${GREEN}==================================================${NC}"
echo -e "${GREEN} 🎉 모든 설정이 완료되었습니다!${NC}"
echo -e "${GREEN}==================================================${NC}"

echo -e "\n📋 설정된 클러스터 정보:"
echo -e "   - 현재 노드: ${GREEN}${MY_HOSTNAME}${NC} (IP: ${CURRENT_IP})"
echo -e "   - Master : ${MASTER_IP} (${MASTER_HOSTNAME})"
echo -e "   - Worker1: ${WORKER1_IP} (${WORKER1_HOSTNAME})"
echo -e "   - Worker2: ${WORKER2_IP} (${WORKER2_HOSTNAME})"

echo -e "\n🔍 상태 점검:"
echo -e "   - Swap: ${GREEN}${SWAP_STATE}${NC}"
echo -e "   - UFW: ${GREEN}Disabled${NC}"
echo -e "   - Containerd: ${GREEN}${CTR_STATE}${NC}"
echo -e "   - Kubeadm Version: ${GREEN}${KADM_VER}${NC}"
echo -e "   - Timezone: ${GREEN}${TZ}${NC}"

echo -e "\n${YELLOW}==================================================${NC}"
echo -e "${YELLOW}📌 다음 단계 (Calico: Tigera Operator)${NC}"
echo -e "${YELLOW}==================================================${NC}"

echo -e "👉 ${GREEN}마스터 노드${NC}라면:"
echo -e "   # Pod CIDR은 Tigera Operator에서 만들 IPPool CIDR과 '반드시' 일치시키세요."
echo -e "   POD_CIDR=${POD_CIDR_DEFAULT}"
echo -e "   kubeadm init --pod-network-cidr=\${POD_CIDR} --apiserver-advertise-address=${MASTER_IP}"
echo -e ""
echo -e "👉 ${GREEN}워커 노드${NC}라면:"
echo -e "   마스터에서 출력된 'kubeadm join ...' 명령어를 그대로 실행하세요."
echo -e "${YELLOW}==================================================${NC}"

echo ""
read -rp "지금 재부팅 하시겠습니까? (y/n): " REBOOT_YN
if [[ "${REBOOT_YN}" == "y" || "${REBOOT_YN}" == "Y" ]]; then
  say "재부팅을 시작합니다..."
  reboot
else
  warn "재부팅을 건너뜁니다. 변경사항 적용을 위해 나중에 재부팅해주세요."
fi
