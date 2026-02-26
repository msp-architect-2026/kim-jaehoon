#!/usr/bin/env bash
set -euo pipefail

# 대상 레지스트리 주소
REGISTRY_HOSTPORT="192.168.10.47:5050"
CA_SRC="${1:-./ca.crt}"

# 1. CA 파일 존재 여부 확인
if [[ ! -f "$CA_SRC" ]]; then
  echo "❌ CA 파일 없음: $CA_SRC"
  exit 1
fi

echo "=================================================="
echo " 🚀 OS 및 Containerd CA 인증서 통합 신뢰 등록"
echo "=================================================="

# ---------------------------------------------------------
# [Step 1] OS 레벨 인증서 신뢰 등록 (Ubuntu/Debian)
# ---------------------------------------------------------
echo -e "\n[1/2] OS 레벨 인증서 등록 중..."
# Ubuntu의 공용 CA 저장소로 복사
sudo cp -f "$CA_SRC" /usr/local/share/ca-certificates/gitlab-ca.crt
# OS 인증서 목록 업데이트
sudo update-ca-certificates
echo "✅ OS 인증서 등록 완료 (curl, git 등에서 신뢰됨)"

# ---------------------------------------------------------
# [Step 2] Containerd 런타임 인증서 신뢰 등록
# ---------------------------------------------------------
echo -e "\n[2/2] Containerd 런타임 인증서 등록 중..."

# config.toml 파일 보장
if [[ ! -f /etc/containerd/config.toml ]]; then
  sudo containerd config default | sudo tee /etc/containerd/config.toml >/dev/null
fi

# config_path 활성화 (오류가 있던 awk 구문을 안전하게 수정)
if grep -q 'plugins."io.containerd.grpc.v1.cri".registry' /etc/containerd/config.toml; then
  if grep -q 'config_path\s*=\s*"/etc/containerd/certs.d"' /etc/containerd/config.toml; then
    : # 이미 설정되어 있으면 패스
  else
    if grep -q 'config_path\s*=' /etc/containerd/config.toml; then
      sudo sed -i 's#^\(\s*config_path\s*=\s*\)".*"#\1"/etc/containerd/certs.d"#' /etc/containerd/config.toml || true
    else
      # 플러그인 섹션 바로 아래에 정확한 문법으로 config_path 삽입
      sudo awk '
        {print}
        $0 ~ /\[plugins\."io\.containerd\.grpc\.v1\.cri"\.registry\]/ {
          print "  config_path = \"/etc/containerd/certs.d\""
        }
      ' /etc/containerd/config.toml | sudo tee /etc/containerd/config.toml.tmp >/dev/null
      sudo mv /etc/containerd/config.toml.tmp /etc/containerd/config.toml
    fi
  fi
else
  # 레지스트리 섹션 자체가 없으면 하단에 추가
  cat <<EOT | sudo tee -a /etc/containerd/config.toml >/dev/null

[plugins."io.containerd.grpc.v1.cri".registry]
  config_path = "/etc/containerd/certs.d"
EOT
fi

# 레지스트리 전용 인증서 디렉토리 생성 및 복사
sudo mkdir -p "/etc/containerd/certs.d/${REGISTRY_HOSTPORT}"
sudo cp -f "$CA_SRC" "/etc/containerd/certs.d/${REGISTRY_HOSTPORT}/ca.crt"

# hosts.toml 파일 생성
sudo tee "/etc/containerd/certs.d/${REGISTRY_HOSTPORT}/hosts.toml" >/dev/null <<EOT
server = "https://${REGISTRY_HOSTPORT}"

[host."https://${REGISTRY_HOSTPORT}"]
  capabilities = ["pull", "resolve", "push"]
  ca = "ca.crt"
EOT

# 설정 적용을 위해 Containerd 데몬 재시작
sudo systemctl restart containerd
echo "✅ containerd trust 등록 완료: /etc/containerd/certs.d/${REGISTRY_HOSTPORT}/"

echo -e "\n=================================================="
echo " 🎉 모든 신뢰 등록이 성공적으로 완료되었습니다!"
echo " 🔍 검증 방법: curl -v https://192.168.10.47"
echo "=================================================="
