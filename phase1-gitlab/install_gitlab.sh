#!/usr/bin/env bash
set -euo pipefail

say(){ echo -e "\033[0;32m$*\033[0m"; }
warn(){ echo -e "\033[1;33m$*\033[0m"; }
err(){ echo -e "\033[0;31m$*\033[0m"; }

need(){ command -v "$1" >/dev/null 2>&1 || { err "❌ '$1' 필요"; exit 1; }; }

as_root() {
  if [[ "${EUID:-$(id -u)}" -eq 0 ]]; then
    bash -lc "$*"
  elif command -v sudo >/dev/null 2>&1; then
    sudo bash -lc "$*"
  else
    err "❌ root 권한 필요(sudo 없음). root로 실행하세요."
    exit 1
  fi
}

is_ip() {
  [[ "$1" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]
}

# ---------- env ----------
ENV_FILE="${1:-./.env.gitlab-https}"
if [[ -f "$ENV_FILE" ]]; then
  # shellcheck disable=SC1090
  source "$ENV_FILE"
else
  warn "⚠️ env 파일 없음: $ENV_FILE (기본값/질문으로 진행)"
  warn "   예) ./10-gitlab-https-bootstrap.sh ./.env.gitlab-https"
fi

# ---------- defaults ----------
GITLAB_HOME="${GITLAB_HOME:-/home/gitlab}"
RUNNER_HOME="${RUNNER_HOME:-/home/gitlab-runner}"

# 버전은 env로 쉽게 바꾸게 해둠
GITLAB_IMAGE="${GITLAB_IMAGE:-gitlab/gitlab-ee:16.1.0-ee.0}"
RUNNER_IMAGE="${RUNNER_IMAGE:-gitlab/gitlab-runner:alpine}"

TIMEZONE="${TIMEZONE:-Asia/Seoul}"
SSH_PORT="${SSH_PORT:-8022}"
REGISTRY_PORT="${REGISTRY_PORT:-5050}"

SWAP_SIZE="${SWAP_SIZE:-4G}" # 옵션
CA_NAME="${CA_NAME:-GitLab-Local-CA}"
CA_DAYS="${CA_DAYS:-3650}"

# ---------- preflight ----------
need awk
need ip
need sed
need grep

echo "=================================================="
echo " GitLab HTTPS Bootstrap (GitLab + Registry + Runner)"
echo " OS: Rocky Linux 8/9"
echo " - Local CA 생성 + SAN 포함 서버 인증서 발급"
echo " - GitLab/Registry HTTPS 설정 + HTTP->HTTPS redirect"
echo " - Docker trust 등록(insecure-registry 제거)"
echo "=================================================="

warn "⚠️ 컨테이너/볼륨은 아래 경로에 생성됩니다:"
warn " - GitLab : $GITLAB_HOME"
warn " - Runner : $RUNNER_HOME"
read -rp "계속할까요? (y/n) [기본 n]: " OK
OK="${OK:-n}"
[[ "$OK" =~ ^[Yy]$ ]] || { echo "취소"; exit 0; }

echo
say "[0/9] 기본값 감지/입력"

DETECTED_IP="$(ip route get 8.8.8.8 2>/dev/null | awk -F'src ' 'NR==1{split($2,a," ");print a[1]}')"
DETECTED_IP="${DETECTED_IP:-127.0.0.1}"

read -r -p "Q1) GitLab 서버 IP [기본 $DETECTED_IP]: " HOST_IP
HOST_IP="${HOST_IP:-$DETECTED_IP}"

read -r -p "Q2) 외부 접속 Host(FQDN 또는 IP) [기본 $HOST_IP]: " EXTERNAL_HOST
EXTERNAL_HOST="${EXTERNAL_HOST:-$HOST_IP}"

read -r -p "Q3) Registry 포트 [기본 $REGISTRY_PORT]: " REGISTRY_PORT_IN
REGISTRY_PORT="${REGISTRY_PORT_IN:-$REGISTRY_PORT}"

read -r -p "Q4) SSH 포트(GitLab) [기본 $SSH_PORT]: " SSH_PORT_IN
SSH_PORT="${SSH_PORT_IN:-$SSH_PORT}"

read -r -p "Q5) firewalld 포트 오픈(80/443/${REGISTRY_PORT}/${SSH_PORT}) (y/N): " DO_FW
DO_FW="${DO_FW:-N}"

read -r -p "Q6) Swap ${SWAP_SIZE} 생성(메모리 적을 때 권장) (y/N): " DO_SWAP
DO_SWAP="${DO_SWAP:-N}"

read -r -p "Q7) GitLab Runner도 같이 설치/실행 (y/N): " DO_RUNNER
DO_RUNNER="${DO_RUNNER:-N}"

read -r -p "Q8) 다른 머신/쿠버노드에 배포할 CA 설치 헬퍼 스크립트 생성 (y/N): " DO_HELPER
DO_HELPER="${DO_HELPER:-N}"

REGISTRY_HOSTPORT="${EXTERNAL_HOST}:${REGISTRY_PORT}"

echo
warn "-------------------- 확인 --------------------"
warn " HOST_IP           : $HOST_IP"
warn " EXTERNAL_HOST     : $EXTERNAL_HOST"
warn " Registry Hostport : $REGISTRY_HOSTPORT"
warn " GitLab Image      : $GITLAB_IMAGE"
warn " Runner Image      : $RUNNER_IMAGE"
warn " SSH Port          : $SSH_PORT"
warn " Open Firewall     : $DO_FW"
warn " Make Swap         : $DO_SWAP ($SWAP_SIZE)"
warn " Install Runner    : $DO_RUNNER"
warn " Make Helper       : $DO_HELPER"
warn "--------------------------------------------"
read -rp "진행할까요? (y/n) [기본 n]: " CONFIRM
CONFIRM="${CONFIRM:-n}"
[[ "$CONFIRM" =~ ^[Yy]$ ]] || { echo "취소"; exit 0; }

# ---------- 1. OS update & tools ----------
say "[1/9] OS 업데이트 및 필수 도구 설치"
as_root "dnf -y update"
as_root "dnf -y install curl vim git net-tools unzip tar dnf-plugins-core openssl ca-certificates jq"
as_root "timedatectl set-timezone '${TIMEZONE}' || true"

# ---------- 2. SELinux ----------
say "[2/9] SELinux Permissive(랩 편의) 적용"
as_root "setenforce 0 || true"
as_root "sed -i 's/^SELINUX=enforcing/SELINUX=permissive/' /etc/selinux/config || true"

# ---------- 3. Swap (optional) ----------
if [[ "$DO_SWAP" =~ ^[Yy]$ ]]; then
  say "[3/9] Swap 생성: ${SWAP_SIZE}"
  as_root "if [[ ! -f /swapfile ]]; then
    fallocate -l '${SWAP_SIZE}' /swapfile
    chmod 600 /swapfile
    mkswap /swapfile
    swapon /swapfile
    echo '/swapfile none swap sw 0 0' >> /etc/fstab
    sysctl -w vm.swappiness=10
  else
    echo 'swapfile already exists -> skip'
  fi"
else
  warn "[3/9] Swap 스킵"
fi

# ---------- 4. Docker + compose plugin ----------
say "[4/9] Docker 엔진 + compose plugin 설치"
as_root "dnf config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo || true"
as_root "dnf -y install docker-ce docker-ce-cli containerd.io docker-compose-plugin"
as_root "systemctl enable --now docker"

# ---------- 5. CA + server cert ----------
say "[5/9] 로컬 CA 생성 + 서버 인증서(SAN) 발급"
SSL_DIR="${GITLAB_HOME}/config/ssl"
as_root "mkdir -p '${SSL_DIR}'"

CA_KEY="${SSL_DIR}/ca.key"
CA_CRT="${SSL_DIR}/ca.crt"
SVR_KEY="${SSL_DIR}/server.key"
SVR_CSR="${SSL_DIR}/server.csr"
SVR_CRT="${SSL_DIR}/server.crt"
SVR_EXT="${SSL_DIR}/server.ext"

# CA 생성(이미 있으면 재사용)
as_root "if [[ ! -f '${CA_KEY}' || ! -f '${CA_CRT}' ]]; then
  openssl genrsa -out '${CA_KEY}' 4096
  openssl req -x509 -new -nodes -key '${CA_KEY}' -sha256 -days '${CA_DAYS}' \
    -out '${CA_CRT}' -subj '/CN=${CA_NAME}'
else
  echo 'CA already exists -> reuse'
fi"

# SAN 구성 (DNS/IP)
ALT_DNS_LINE=""
ALT_IP_LINE="IP.1 = ${HOST_IP}"
if is_ip "$EXTERNAL_HOST"; then
  # 외부 호스트가 IP면 IP로도 넣고(중복 방지)
  if [[ "$EXTERNAL_HOST" != "$HOST_IP" ]]; then
    ALT_IP_LINE=$'IP.1 = '"${HOST_IP}"$'\nIP.2 = '"${EXTERNAL_HOST}"
  fi
else
  ALT_DNS_LINE="DNS.1 = ${EXTERNAL_HOST}"
  # 혹시 hosts 파일로 IP 접속도 할 수 있으니 IP도 포함
fi

# server.ext 작성
as_root "cat > '${SVR_EXT}' <<EOF
authorityKeyIdentifier=keyid,issuer
basicConstraints=CA:FALSE
keyUsage = digitalSignature, keyEncipherment
extendedKeyUsage = serverAuth
subjectAltName = @alt_names

[alt_names]
${ALT_DNS_LINE}
${ALT_IP_LINE}
EOF"

# 서버 키/CSR/서명(매번 새로 발급해도 되지만, 재실행 시 재사용하도록)
as_root "if [[ ! -f '${SVR_KEY}' ]]; then
  openssl genrsa -out '${SVR_KEY}' 2048
fi"

as_root "openssl req -new -key '${SVR_KEY}' -out '${SVR_CSR}' -subj '/CN=${EXTERNAL_HOST}'"
as_root "openssl x509 -req -in '${SVR_CSR}' -CA '${CA_CRT}' -CAkey '${CA_KEY}' -CAcreateserial \
  -out '${SVR_CRT}' -days '${CA_DAYS}' -sha256 -extfile '${SVR_EXT}'"

# OS trust 등록(이 서버에서 curl/git 등이 self-signed로 안 터지게)
say " - OS CA trust 등록"
as_root "cp -f '${CA_CRT}' /etc/pki/ca-trust/source/anchors/gitlab-local-ca.crt && update-ca-trust || true"

# Docker trust: 레지스트리 호스트명:포트 기준으로 등록
say " - Docker trust(/etc/docker/certs.d/${REGISTRY_HOSTPORT}/ca.crt)"
as_root "mkdir -p '/etc/docker/certs.d/${REGISTRY_HOSTPORT}'"
as_root "cp -f '${CA_CRT}' '/etc/docker/certs.d/${REGISTRY_HOSTPORT}/ca.crt'"
as_root "systemctl restart docker"

# ---------- 6. GitLab docker-compose.yml ----------
say "[6/9] GitLab docker-compose.yml 생성 및 HTTPS 설정"
as_root "mkdir -p '${GITLAB_HOME}/data' '${GITLAB_HOME}/logs' '${GITLAB_HOME}/config'"

# GitLab에서 ssl 파일은 /etc/gitlab/ssl 아래로 들어감(볼륨: config)
as_root "cat > '${GITLAB_HOME}/docker-compose.yml' <<EOF
version: '3.6'
services:
  gitlab:
    image: ${GITLAB_IMAGE}
    container_name: gitlab
    restart: always
    hostname: '${EXTERNAL_HOST}'
    ports:
      - '80:80'
      - '443:443'
      - '${SSH_PORT}:22'
      - '${REGISTRY_PORT}:${REGISTRY_PORT}'
    environment:
      GITLAB_OMNIBUS_CONFIG: |
        external_url 'https://${EXTERNAL_HOST}'
        gitlab_rails['time_zone'] = '${TIMEZONE}'
        letsencrypt['enable'] = false

        # SSH 포트
        gitlab_rails['gitlab_shell_ssh_port'] = ${SSH_PORT}

        # Nginx SSL
        nginx['redirect_http_to_https'] = true
        nginx['ssl_certificate'] = \"/etc/gitlab/ssl/server.crt\"
        nginx['ssl_certificate_key'] = \"/etc/gitlab/ssl/server.key\"

        # Container Registry
        registry_external_url 'https://${EXTERNAL_HOST}:${REGISTRY_PORT}'
        gitlab_rails['registry_enabled'] = true
        registry['enable'] = true
        gitlab_rails['registry_host'] = '${EXTERNAL_HOST}'
        gitlab_rails['registry_port'] = ${REGISTRY_PORT}
        registry['storage_delete_enabled'] = true

        # Registry Nginx SSL
        registry_nginx['enable'] = true
        registry_nginx['listen_port'] = ${REGISTRY_PORT}
        registry_nginx['listen_https'] = true
        registry_nginx['ssl_certificate'] = \"/etc/gitlab/ssl/server.crt\"
        registry_nginx['ssl_certificate_key'] = \"/etc/gitlab/ssl/server.key\"

        # 리소스 절약(랩)
        puma['worker_processes'] = 0
        sidekiq['max_concurrency'] = 10
    volumes:
      - '${GITLAB_HOME}/config:/etc/gitlab'
      - '${GITLAB_HOME}/logs:/var/log/gitlab'
      - '${GITLAB_HOME}/data:/var/opt/gitlab'
    shm_size: '256m'
EOF"

# ssl 파일을 /etc/gitlab/ssl 위치로 맞춤 (config 볼륨 내부)
say " - GitLab config 볼륨에 ssl 배치(/etc/gitlab/ssl)"
as_root "mkdir -p '${GITLAB_HOME}/config/ssl'"
# [수정됨] 이전에 오류를 일으켰던 cp -f 명령어 3줄을 안전하게 삭제했습니다.

# ---------- 7. Runner docker-compose.yml (optional) ----------
if [[ "$DO_RUNNER" =~ ^[Yy]$ ]]; then
  say "[7/9] GitLab Runner docker-compose.yml 생성"
  as_root "mkdir -p '${RUNNER_HOME}/config' '${RUNNER_HOME}/certs'"

  # Runner 컨테이너에 CA를 넣어둠(등록 시 --tls-ca-file로 사용)
  as_root "cp -f '${CA_CRT}' '${RUNNER_HOME}/certs/ca.crt'"

  as_root "cat > '${RUNNER_HOME}/docker-compose.yml' <<EOF
version: '3.6'
services:
  gitlab-runner:
    image: ${RUNNER_IMAGE}
    container_name: gitlab-runner
    restart: always
    volumes:
      - '${RUNNER_HOME}/config:/etc/gitlab-runner'
      - '${RUNNER_HOME}/certs:/etc/gitlab-runner/certs:ro'
      - '/var/run/docker.sock:/var/run/docker.sock'
EOF"
else
  warn "[7/9] Runner 스킵"
fi

# ---------- firewalld (optional) ----------
if [[ "$DO_FW" =~ ^[Yy]$ ]]; then
  say "[FW] firewalld 포트 오픈"
  as_root "systemctl enable --now firewalld || true"
  as_root "firewall-cmd --permanent --add-service=http || true"
  as_root "firewall-cmd --permanent --add-service=https || true"
  as_root "firewall-cmd --permanent --add-port='${REGISTRY_PORT}/tcp' || true"
  as_root "firewall-cmd --permanent --add-port='${SSH_PORT}/tcp' || true"
  as_root "firewall-cmd --reload || true"
else
  warn "[FW] firewalld 스킵"
fi

# ---------- 8. compose up + health ----------
say "[8/9] GitLab/Runner 기동"
as_root "cd '${GITLAB_HOME}' && docker compose up -d"

if [[ "$DO_RUNNER" =~ ^[Yy]$ ]]; then
  as_root "cd '${RUNNER_HOME}' && docker compose up -d"
fi

say "⏳ GitLab 부팅 대기 (로컬 체크: https://${HOST_IP})"
# GitLab이 302/200을 내면 살아난 것으로 봄
for i in {1..120}; do
  code="$(curl -k -s -o /dev/null -w '%{http_code}' "https://${HOST_IP}/users/sign_in" || true)"
  if [[ "$code" =~ ^(200|302)$ ]]; then
    say "✅ GitLab 접속 가능 (HTTP ${code})"
    break
  fi
  printf "."
  sleep 10
done
echo

# ---------- 9. output ----------
say "[9/9] 완료 정보 출력"
INIT_PASS=""
if as_root "docker exec gitlab test -f /etc/gitlab/initial_root_password" >/dev/null 2>&1; then
  INIT_PASS="$(as_root "docker exec gitlab grep 'Password:' /etc/gitlab/initial_root_password | awk '{print \$2}'" || true)"
fi

echo "=================================================="
echo " 🎉 GitLab HTTPS 구축 완료!"
echo "=================================================="
echo " 1) GitLab URL      : https://${EXTERNAL_HOST}"
echo " 2) Registry        : ${REGISTRY_HOSTPORT} (이미지: ${REGISTRY_HOSTPORT}/<group>/<project>:<tag>)"
echo " 3) SSH Port        : ${SSH_PORT}"
echo " 4) CA 인증서 경로  : ${CA_CRT}"
if [[ -n "${INIT_PASS}" ]]; then
  echo " 5) 초기 root 비번  : ${INIT_PASS}"
else
  echo " 5) 초기 root 비번  : (없음/만료/이미 변경됨)"
fi
echo
echo " [Runner 등록 예시]"
echo " docker exec -it gitlab-runner gitlab-runner register \\"
echo "   --url https://${EXTERNAL_HOST} \\"
echo "   --tls-ca-file /etc/gitlab-runner/certs/ca.crt \\"
echo "   --token <YOUR_TOKEN> --executor docker --docker-image alpine:latest"
echo "=================================================="

# ---------- helper script ----------
if [[ "$DO_HELPER" =~ ^[Yy]$ ]]; then
  say "헬퍼 스크립트 생성: ${GITLAB_HOME}/ca-distribute/"
  as_root "mkdir -p '${GITLAB_HOME}/ca-distribute'"
  as_root "cp -f '${CA_CRT}' '${GITLAB_HOME}/ca-distribute/ca.crt'"

  # docker용
  as_root "cat > '${GITLAB_HOME}/ca-distribute/install-ca-docker.sh' <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
REGISTRY_HOSTPORT=\"__REGISTRY_HOSTPORT__\"
CA_SRC=\"\${1:-./ca.crt}\"

if [[ ! -f \"\$CA_SRC\" ]]; then
  echo \"❌ CA 파일 없음: \$CA_SRC\"
  exit 1
fi

sudo mkdir -p \"/etc/docker/certs.d/\${REGISTRY_HOSTPORT}\"
sudo cp -f \"\$CA_SRC\" \"/etc/docker/certs.d/\${REGISTRY_HOSTPORT}/ca.crt\"
sudo systemctl restart docker
echo \"✅ Docker trust 등록 완료: /etc/docker/certs.d/\${REGISTRY_HOSTPORT}/ca.crt\"
EOF"
  as_root "sed -i \"s/__REGISTRY_HOSTPORT__/${REGISTRY_HOSTPORT}/g\" '${GITLAB_HOME}/ca-distribute/install-ca-docker.sh'"
  as_root "chmod +x '${GITLAB_HOME}/ca-distribute/install-ca-docker.sh'"

  # containerd용(쿠버 노드)
  as_root "cat > '${GITLAB_HOME}/ca-distribute/install-ca-containerd.sh' <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
REGISTRY_HOSTPORT=\"__REGISTRY_HOSTPORT__\"
CA_SRC=\"\${1:-./ca.crt}\"

if [[ ! -f \"\$CA_SRC\" ]]; then
  echo \"❌ CA 파일 없음: \$CA_SRC\"
  exit 1
fi

# config_path 보장(없으면 기본 config 생성)
if [[ ! -f /etc/containerd/config.toml ]]; then
  sudo containerd config default | sudo tee /etc/containerd/config.toml >/dev/null
fi

# containerd certs.d 경로 활성화
sudo sed -i 's#^\\s*config_path\\s*=\\s*\".*\"#  config_path = \"/etc/containerd/certs.d\"#' /etc/containerd/config.toml || true

sudo mkdir -p \"/etc/containerd/certs.d/\${REGISTRY_HOSTPORT}\"
sudo cp -f \"\$CA_SRC\" \"/etc/containerd/certs.d/\${REGISTRY_HOSTPORT}/ca.crt\"

sudo tee \"/etc/containerd/certs.d/\${REGISTRY_HOSTPORT}/hosts.toml\" >/dev/null <<EOT
server = \"https://\${REGISTRY_HOSTPORT}\"

[host.\"https://\${REGISTRY_HOSTPORT}\"]
  capabilities = [\"pull\", \"resolve\", \"push\"]
  ca = \"ca.crt\"
EOT

sudo systemctl restart containerd
echo \"✅ containerd trust 등록 완료: /etc/containerd/certs.d/\${REGISTRY_HOSTPORT}/\"
EOF"
  as_root "sed -i \"s/__REGISTRY_HOSTPORT__/${REGISTRY_HOSTPORT}/g\" '${GITLAB_HOME}/ca-distribute/install-ca-containerd.sh'"
  as_root "chmod +x '${GITLAB_HOME}/ca-distribute/install-ca-containerd.sh'"

  echo
  say "헬퍼 위치:"
  echo "  - ${GITLAB_HOME}/ca-distribute/ca.crt"
  echo "  - ${GITLAB_HOME}/ca-distribute/install-ca-docker.sh"
  echo "  - ${GITLAB_HOME}/ca-distribute/install-ca-containerd.sh"
fi
