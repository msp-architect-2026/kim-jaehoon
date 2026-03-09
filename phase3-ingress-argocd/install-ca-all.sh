#!/usr/bin/env bash
set -euo pipefail

say(){ echo -e "\033[0;32m$*\033[0m"; }
warn(){ echo -e "\033[1;33m$*\033[0m"; }
err(){ echo -e "\033[0;31m$*\033[0m"; }

echo "=================================================="
echo " 🚀 OS 및 Containerd CA 인증서 통합 신뢰 등록"
echo "=================================================="

# ---------------------------------------------------------
# [인자 처리] 커맨드라인 인자 → 없으면 대화형 질의
# ---------------------------------------------------------
# 사용법 안내
# ./install-ca.sh <CA_파일_경로> <레지스트리_HOST:PORT>
# 예) ./install-ca.sh ./ca.crt <GITLAB_IP>:5050
#     ./install-ca.sh /home/gitlab/config/ssl/ca.crt <GITLAB_IP>:5050

CA_SRC="${1:-}"
REGISTRY_HOSTPORT="${2:-}"

# CA 파일 경로 질의
if [[ -z "$CA_SRC" ]]; then
  echo
  echo "Q1) CA 인증서 파일 경로를 입력하세요."
  echo "    - GitLab 자체 서명 인증서의 CA 파일 경로입니다."
  echo "    - 예) ./ca.crt"
  echo "    - 예) /home/gitlab/config/ssl/ca.crt"
  read -rp "    CA 파일 경로 [기본: ./ca.crt]: " CA_SRC
  CA_SRC="${CA_SRC:-./ca.crt}"
fi

# 레지스트리 주소 질의
if [[ -z "$REGISTRY_HOSTPORT" ]]; then
  echo
  echo "Q2) GitLab Container Registry 주소를 입력하세요."
  echo "    - 형식: HOST:PORT (스킴 없이 입력)"
  echo "    - 예) <GITLAB_IP>:5050"
  echo "    - 예) <GITLAB_IP>:5050"
  echo "    ⚠️  http:// 또는 https:// 를 앞에 붙이면 안 됩니다."
  read -rp "    Registry HOST:PORT: " REGISTRY_HOSTPORT
fi

# ---------------------------------------------------------
# [입력값 검증]
# ---------------------------------------------------------
# CA 파일 존재 여부 확인
if [[ ! -f "$CA_SRC" ]]; then
  err "❌ CA 파일 없음: $CA_SRC"
  exit 1
fi

# 레지스트리 주소 빈값 체크
if [[ -z "$REGISTRY_HOSTPORT" ]]; then
  err "❌ Registry 주소가 입력되지 않았습니다."
  exit 1
fi

# 스킴 포함 여부 체크 (http://, https:// 입력 방지)
if [[ "$REGISTRY_HOSTPORT" =~ ^https?:// ]]; then
  err "❌ REGISTRY_HOSTPORT에 스킴(http/https)을 포함하면 안 됩니다."
  echo "   ✅ 올바른 형식 예: <GITLAB_IP>:5050"
  exit 1
fi

# HOST만 추출 (검증 메시지 출력용)
REGISTRY_HOST="${REGISTRY_HOSTPORT%%:*}"

echo
warn "-------------------- 확인 --------------------"
warn " CA 파일          : ${CA_SRC}"
warn " Registry 주소    : ${REGISTRY_HOSTPORT}"
warn "--------------------------------------------"
read -rp "진행할까요? (y/n) [기본 n]: " CONFIRM
CONFIRM="${CONFIRM:-n}"
[[ "$CONFIRM" =~ ^[Yy]$ ]] || { echo "취소"; exit 0; }

# ---------------------------------------------------------
# [Step 1] OS 레벨 인증서 신뢰 등록 (Ubuntu/Debian)
# ---------------------------------------------------------
echo -e "\n[1/2] OS 레벨 인증서 등록 중..."
sudo cp -f "$CA_SRC" /usr/local/share/ca-certificates/gitlab-ca.crt
sudo update-ca-certificates
say "✅ OS 인증서 등록 완료 (curl, git 등에서 신뢰됨)"

# ---------------------------------------------------------
# [Step 2] Containerd 런타임 인증서 신뢰 등록
# ---------------------------------------------------------
echo -e "\n[2/2] Containerd 런타임 인증서 등록 중..."

# config.toml 파일 보장
if [[ ! -f /etc/containerd/config.toml ]]; then
  sudo containerd config default | sudo tee /etc/containerd/config.toml >/dev/null
fi

# config_path 활성화
if grep -q 'plugins."io.containerd.grpc.v1.cri".registry' /etc/containerd/config.toml; then
  if grep -q 'config_path\s*=\s*"/etc/containerd/certs.d"' /etc/containerd/config.toml; then
    : # 이미 설정되어 있으면 패스
  else
    if grep -q 'config_path\s*=' /etc/containerd/config.toml; then
      sudo sed -i 's#^\(\s*config_path\s*=\s*\)".*"#\1"/etc/containerd/certs.d"#' /etc/containerd/config.toml || true
    else
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
say "✅ containerd trust 등록 완료: /etc/containerd/certs.d/${REGISTRY_HOSTPORT}/"

echo -e "\n=================================================="
say " 🎉 모든 신뢰 등록이 성공적으로 완료되었습니다!"
echo " 🔍 검증 방법: curl -v https://${REGISTRY_HOST}"
echo "=================================================="
