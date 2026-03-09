#!/bin/bash

# ==============================================================================
# Kubernetes 마스터 노드 초기화 스크립트 (Master Only)
# 특징: IP 자동 감지, Calico CNI 설치, Join 명령어 파일 저장
# ==============================================================================

set -euo pipefail

echo "=================================================="
echo " 🚀 Kubernetes Master Node 초기화 시작 (Calico)"
echo "=================================================="

# --- 0. 실행 전 체크 ---
if ! systemctl is-active --quiet containerd; then
    echo "❌ Error: containerd가 실행 중이 아닙니다."
    echo "   sudo systemctl enable --now containerd 명령어를 먼저 실행하세요."
    exit 1
fi

# --- 1. IP 주소 및 CIDR 설정 ---
DETECTED_IP=$(ip route get 8.8.8.8 | grep -oP 'src \K\S+')
echo ""
echo "Detected IP: $DETECTED_IP"
read -t 10 -p "▶ API Server IP 확인 [Enter 입력 시 $DETECTED_IP 사용]: " MASTER_IP || MASTER_IP=$DETECTED_IP
MASTER_IP=${MASTER_IP:-$DETECTED_IP}

DEFAULT_CIDR="10.244.0.0/16"
echo ""
read -t 10 -p "▶ Pod Network CIDR 확인 [Enter 입력 시 $DEFAULT_CIDR 사용]: " POD_CIDR || POD_CIDR=$DEFAULT_CIDR
POD_CIDR=${POD_CIDR:-$DEFAULT_CIDR}

echo ""
echo "--------------------------------------------------"
echo " 🎯 설정 확인:"
echo "   - Master IP : $MASTER_IP"
echo "   - Pod CIDR  : $POD_CIDR"
echo "--------------------------------------------------"
read -p "위 설정으로 초기화를 진행하시겠습니까? (y/n) " CONFIRM
if [[ "$CONFIRM" != "y" ]]; then
    echo "취소되었습니다."
    exit 1
fi

# --- 2. Kubeadm 초기화 ---
echo ""
echo "[1/5] 필수 이미지 다운로드 중..."
sudo kubeadm config images pull

echo ""
echo "[2/5] Master Node 초기화 중..."
sudo kubeadm init \
  --apiserver-advertise-address="$MASTER_IP" \
  --pod-network-cidr="$POD_CIDR" | tee kubeadm-init.log

# --- 3. Kubectl 설정 ---
echo ""
echo "[3/5] kubectl 설정 파일 복사 중..."
mkdir -p "$HOME/.kube"
sudo cp -f /etc/kubernetes/admin.conf "$HOME/.kube/config"
sudo chown "$(id -u):$(id -g)" "$HOME/.kube/config"

# --- [수정] API 서버 Ready 대기 ---
# kubeadm init 직후 API 서버가 완전히 뜨기 전에 kubectl 호출하면 실패함
# 느린 VM 환경에서 특히 필요
echo ""
echo "⏳ API 서버 준비 대기 중..."
WAIT_RETRY=0
until kubectl get nodes >/dev/null 2>&1; do
    WAIT_RETRY=$((WAIT_RETRY + 1))
    if [ $WAIT_RETRY -ge 20 ]; then
        echo "❌ API 서버가 60초 내에 준비되지 않았습니다."
        exit 1
    fi
    echo "   대기 중... (${WAIT_RETRY}/20)"
    sleep 3
done
echo "✅ API 서버 준비 완료"

# --- 4. Calico CNI 설치 ---
echo ""
echo "[4/5] Calico CNI 플러그인 설치 중..."

# Tigera Operator 설치
kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/v3.27.0/manifests/tigera-operator.yaml

# [수정] Operator Pod Ready 대기 (CRD 등록 전에 custom-resources 적용하면 실패)
echo "⏳ Tigera Operator 준비 대기 중..."
kubectl wait --for=condition=Ready pod \
    -l app=tigera-operator \
    -n tigera-operator \
    --timeout=120s

# Custom Resources 다운로드
curl -fsSL https://raw.githubusercontent.com/projectcalico/calico/v3.27.0/manifests/custom-resources.yaml -o custom-resources.yaml

# CIDR 설정 변경
if [ "$POD_CIDR" != "192.168.0.0/16" ]; then
    echo "Info: Calico 설정을 사용자 지정 CIDR($POD_CIDR)로 변경합니다."
    sed -i "s|192.168.0.0/16|$POD_CIDR|g" custom-resources.yaml
fi

kubectl apply -f custom-resources.yaml
rm custom-resources.yaml

# --- 5. Join 명령어 추출 및 저장 ---
echo ""
echo "[5/5] 워커 노드 Join 명령어 생성 중..."

JOIN_CMD=$(sudo kubeadm token create --print-join-command 2>/dev/null)

if [ -n "$JOIN_CMD" ]; then
    echo "$JOIN_CMD" > join_command.sh
    chmod +x join_command.sh
    echo "✅ Join 명령어가 'join_command.sh' 파일로 저장되었습니다!"
else
    echo "⚠️ Join 명령어 추출 실패. 위 로그에서 직접 복사하세요."
fi

echo ""
echo "=================================================="
echo " 🎉 Master Node 초기화 완료!"
echo "=================================================="
echo "1. 노드 상태 확인: kubectl get nodes"
echo "   (Ready 상태가 될 때까지 1~2분 소요)"
echo ""
echo "2. 워커 노드 추가 방법:"
echo "   파일 확인: cat join_command.sh"
echo "   (이 내용을 워커 노드에서 복사 붙여넣기 하세요)"
echo "=================================================="
