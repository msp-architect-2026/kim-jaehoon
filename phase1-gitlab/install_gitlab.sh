#!/bin/bash

# ==============================================================================
# GitLab & Runner & Registry 올인원 설치 스크립트 (Final Version)
# OS: Rocky Linux 8/9
# 기능:
#   1. OS 필수 설정 (방화벽, SELinux, Timezone)
#   2. Swap 메모리 4GB 자동 추가 (OOM 튕김 방지 - GitLab은 메모리를 많이 먹음)
#   3. Docker 설치 및 Insecure Registry 자동 설정 (HTTP 레지스트리 사용을 위해)
#   4. GitLab + Container Registry (포트 5050) 자동 구성
# ==============================================================================

set -e  # 스크립트 실행 중 에러(반환값 0이 아님)가 발생하면 즉시 실행을 중단합니다.

# --- 0. 변수 설정 ---
# 설치 경로 및 사용할 이미지 버전, 포트 등을 정의합니다.
GITLAB_HOME="/home/gitlab"               # GitLab 데이터 저장 경로
RUNNER_HOME="/home/gitlab-runner"        # Runner 설정 저장 경로
GITLAB_IMAGE="gitlab/gitlab-ee:16.1.0-ee.0" # 사용할 GitLab 도커 이미지 (Enterprise Edition)
RUNNER_IMAGE="gitlab/gitlab-runner:alpine"  # 사용할 Runner 도커 이미지 (경량화된 Alpine 버전)
SSH_PORT=8022                            # 호스트의 22번 포트와 충돌 방지를 위해 GitLab SSH 포트 변경

echo "=================================================="
echo " 🚀 GitLab Full 패키지 설치 시작 (Rocky Linux)"
echo "=================================================="

# --- 1. OS 기본 설정 ---
echo ""
echo "[1/9] 시스템 업데이트 및 필수 도구 설치..."
# 패키지 매니저(dnf)를 최신 상태로 업데이트하고 필수 유틸리티를 설치합니다.
sudo dnf -y update
sudo dnf -y install curl vim git net-tools unzip tar dnf-plugins-core
# 서버 시간을 한국 표준시(KST)로 설정합니다. 로그 시간 확인에 중요합니다.
sudo timedatectl set-timezone Asia/Seoul

# --- 2. 방화벽 및 SELinux 해제 ---
echo ""
echo "[2/9] 보안 설정 완화 (방화벽/SELinux)..."
# firewalld(방화벽)가 실행 중이면 끄고, 재부팅 시 자동 실행되지 않도록 비활성화합니다.
# (실습 환경 통신 원활화를 위함, 운영 환경에서는 포트만 개방하는 것이 좋습니다.)
if systemctl list-unit-files | grep -q firewalld; then
    sudo systemctl stop firewalld
    sudo systemctl disable firewalld
fi
# 현재 세션에서 SELinux를 Permissive 모드로 변경합니다. (보안 정책 완화)
sudo setenforce 0 || true
# 재부팅 후에도 SELinux가 Permissive 모드로 유지되도록 설정 파일을 수정합니다.
sudo sed -i 's/^SELINUX=enforcing/SELINUX=permissive/' /etc/selinux/config

# --- 3. Swap 메모리 추가 (중요!) ---
echo ""
echo "[3/9] 가상 메모리(Swap) 4GB 확인 및 추가..."
# GitLab은 권장 메모리가 4GB 이상입니다. 물리 메모리가 부족할 경우 프로세스가 죽는 것을 방지하기 위해 스왑 파일을 생성합니다.
if [ ! -f /swapfile ]; then
    sudo fallocate -l 4G /swapfile          # 4GB 크기의 빈 파일 생성
    sudo chmod 600 /swapfile                # 보안을 위해 루트 사용자만 읽고 쓸 수 있게 권한 설정
    sudo mkswap /swapfile                   # 해당 파일을 스왑 공간으로 포맷
    sudo swapon /swapfile                   # 스왑 공간 활성화
    echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab # 재부팅 시 자동 마운트 등록
    sudo sysctl -w vm.swappiness=10         # 스왑 사용 빈도를 낮춤 (물리 메모리 우선 사용)
    echo "vm.swappiness = 10" | sudo tee -a /etc/sysctl.conf # 영구 적용
    echo "    -> Swap 4GB 생성 완료!"
else
    echo "    -> 이미 Swap 파일이 존재합니다. 건너뜁니다."
fi

# --- 4. Docker 설치 ---
echo ""
echo "[4/9] Docker 엔진 설치..."
# Docker 공식 리포지토리를 dnf 설정에 추가합니다.
sudo dnf config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
# Docker 엔진, CLI, containerd 및 플러그인들을 설치합니다.
sudo dnf -y install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
# Docker 서비스를 시작하고 부팅 시 자동 실행되도록 설정합니다.
sudo systemctl start docker
sudo systemctl enable docker
# 현재 사용자를 docker 그룹에 추가하여 sudo 없이 docker 명령어를 쓸 수 있게 합니다.
# (스크립트 실행 중에는 바로 적용되지 않고 재로그인해야 적용됩니다.)
sudo usermod -aG docker $USER || true

# --- 5. 네트워크 IP 감지 ---
echo ""
echo "[5/9] 네트워크 IP 자동 감지..."
# 구글 DNS(8.8.8.8)로 나가는 경로를 확인하여 현재 서버의 대표 IP를 추출합니다.
DETECTED_IP=$(ip route get 8.8.8.8 | awk -F"src " 'NR==1{split($2,a," ");print a[1]}')

echo "    감지된 IP: $DETECTED_IP"
# IP 감지 실패 시 사용자에게 직접 입력을 요청합니다.
if [ -z "$DETECTED_IP" ]; then
    read -p "    ▶ IP 감지 실패. 사용할 IP를 입력하세요: " HOST_IP
else
    # 10초 내에 입력이 없으면 감지된 IP를 기본값으로 사용합니다.
    read -t 10 -p "    ▶ IP 확인 [Enter 입력 시 $DETECTED_IP 사용]: " HOST_IP || HOST_IP=$DETECTED_IP
fi
# HOST_IP 변수가 비어있다면 감지된 IP를 할당합니다.
HOST_IP=${HOST_IP:-$DETECTED_IP}
EXTERNAL_URL="http://$HOST_IP"

echo "    -> GitLab URL    : $EXTERNAL_URL"
echo "    -> Registry URL : http://$HOST_IP:5050"

# --- 6. Docker Insecure Registry 설정 ---
echo ""
echo "[6/9] Docker 레지스트리 보안 예외 등록..."
# 기본적으로 Docker는 HTTPS 레지스트리만 허용합니다.
# 우리가 구축할 레지스트리는 HTTP(5050포트)를 사용하므로 'insecure-registries' 목록에 추가해야 합니다.
cat <<EOF | sudo tee /etc/docker/daemon.json
{
  "insecure-registries": ["$HOST_IP:5050"]
}
EOF
# 설정 변경 사항을 적용하기 위해 Docker 데몬을 재시작합니다.
sudo systemctl restart docker
echo "    -> Docker 재시작 완료."

# --- 7. docker-compose.yml 생성 (레지스트리 포함) ---
echo ""
echo "[7/9] 설정 파일 생성 (Registry 포함)..."
# GitLab과 Runner가 사용할 디렉토리를 생성합니다.
sudo mkdir -p $GITLAB_HOME/{config,data,logs}
sudo mkdir -p $RUNNER_HOME/config

# GitLab용 docker-compose.yml 파일을 생성합니다.
cat <<EOF | sudo tee $GITLAB_HOME/docker-compose.yml > /dev/null
version: '3.6'
services:
  gitlab:
    image: $GITLAB_IMAGE
    container_name: gitlab
    restart: always                # 컨테이너가 죽거나 재부팅 시 자동 재시작
    hostname: '$HOST_IP'           # 컨테이너 내부 호스트네임 설정
    ports:
      - "80:80"                    # 웹 접속용 (HTTP)
      - "443:443"                  # HTTPS용 (인증서 설정 필요, 여기선 포트만 열어둠)
      - "$SSH_PORT:22"             # Git SSH 접속용 (호스트 8022 -> 컨테이너 22)
      - "5050:5050"                # 컨테이너 레지스트리용 포트
    environment:
      GITLAB_OMNIBUS_CONFIG: |
        external_url '$EXTERNAL_URL'             # GitLab 접속 URL 설정
        gitlab_rails['gitlab_shell_ssh_port'] = $SSH_PORT # SSH 클론 시 표시될 포트 번호
        
        # Container Registry 설정 (자동화)
        registry_external_url 'http://$HOST_IP:5050'  # 레지스트리 외부 접속 주소
        registry_nginx['listen_port'] = 5050          # Nginx가 수신할 레지스트리 포트
        registry_nginx['listen_https'] = false        # HTTP 사용 (SSL 미사용)
        registry['enable'] = true                     # 레지스트리 기능 활성화
        
        # 메모리 최적화 (저사양 환경을 위한 설정)
        puma['worker_processes'] = 0                  # Puma 워커 프로세스 최소화 (메모리 절약)
        sidekiq['max_concurrency'] = 10               # 백그라운드 작업 동시 실행 수 제한
    volumes:
      - $GITLAB_HOME/config:/etc/gitlab           # 설정 파일 영구 저장
      - $GITLAB_HOME/logs:/var/log/gitlab         # 로그 파일 영구 저장
      - $GITLAB_HOME/data:/var/opt/gitlab         # 데이터(리포지토리 등) 영구 저장
    shm_size: '256m'                              # 공유 메모리 크기 설정 (부족 시 에러 방지)
EOF

# Runner용 docker-compose.yml 파일을 생성합니다.
cat <<EOF | sudo tee $RUNNER_HOME/docker-compose.yml > /dev/null
version: '3.6'
services:
  gitlab-runner:
    image: $RUNNER_IMAGE
    container_name: gitlab-runner
    restart: always
    volumes:
      - $RUNNER_HOME/config:/etc/gitlab-runner    # Runner 설정 파일 저장
      - /var/run/docker.sock:/var/run/docker.sock # 호스트의 Docker 데몬을 Runner가 제어할 수 있게 공유 (Docker-in-Docker 방식)
EOF

# 생성된 디렉토리의 소유권을 현재 사용자로 변경합니다.
sudo chown -R $USER:$USER $GITLAB_HOME $RUNNER_HOME

# --- 8. 컨테이너 실행 ---
echo ""
echo "[8/9] GitLab 서비스 시작 (최대 5~10분 소요)..."

# docker compose 명령어 버전을 확인하여 적절한 명령어를 선택합니다. (v2: docker compose, v1: docker-compose)
DOCKER_COMPOSE_CMD="docker compose"
if ! docker compose version > /dev/null 2>&1; then DOCKER_COMPOSE_CMD="docker-compose"; fi

# GitLab 컨테이너 실행
cd $GITLAB_HOME
sudo $DOCKER_COMPOSE_CMD up -d

# GitLab이 완전히 뜰 때까지 Health Check 루프를 돕니다.
RETRIES=0
MAX_RETRIES=60 # 10초 * 60회 = 최대 10분 대기
until curl -s -o /dev/null -w "%{http_code}" $EXTERNAL_URL/users/sign_in | grep -q "200"; do
    if [ $RETRIES -ge $MAX_RETRIES ]; then
        echo "❌ 시간 초과. 로그 확인: sudo docker logs -f gitlab"
        exit 1
    fi
    printf "." # 대기 중임을 표시
    sleep 10
    RETRIES=$((RETRIES+1))
done
echo " ✅ GitLab 정상 구동!"

# --- 9. 비밀번호 및 Runner 실행 ---
echo ""
echo "[9/9] 마무리 설정..."
sleep 5 # 초기 비밀번호 파일 생성 대기

INIT_PASS=""
# 초기 루트 비밀번호를 파일에서 추출합니다.
if [ -f $GITLAB_HOME/config/initial_root_password ]; then
    INIT_PASS=$(sudo grep "Password:" $GITLAB_HOME/config/initial_root_password | awk '{print $2}')
else
    # 파일이 호스트에 아직 동기화되지 않았다면 컨테이너 내부에서 직접 읽어옵니다.
    INIT_PASS=$(sudo docker exec gitlab grep "Password:" /etc/gitlab/initial_root_password 2>/dev/null | awk '{print $2}' || echo "확인불가")
fi

# Runner 컨테이너 실행
cd $RUNNER_HOME
sudo $DOCKER_COMPOSE_CMD up -d

echo ""
echo "=================================================="
echo " 🎉 설치 완료! (모든 기능 활성화됨)"
echo "=================================================="
echo " 1. GitLab 주소    : $EXTERNAL_URL"
echo " 2. Registry 주소 : $HOST_IP:5050"
echo " 3. 관리자 ID      : root"
echo " 4. 초기 비밀번호 : $INIT_PASS"
echo ""
echo " [Runner 등록 명령어 (복사해서 사용)]"
echo " --------------------------------------------------"
# 사용자가 직접 실행해야 할 Runner 등록 명령어를 출력합니다.
# <토큰입력> 부분은 GitLab 웹 UI (Admin Area -> CI/CD -> Runners)에서 확인 후 채워넣어야 합니다.
echo "sudo docker exec -it gitlab-runner gitlab-runner register \\"
echo "  --non-interactive \\"               # 인터랙티브 모드 끄기 (자동 등록)
echo "  --url $EXTERNAL_URL \\"             # GitLab 주소
echo "  --token <토큰입력> \\"               # 등록 토큰 (웹에서 확인 필요)
echo "  --executor docker \\"               # 실행 환경 (Docker)
echo "  --docker-image alpine:latest \\"    # 기본 도커 이미지
echo "  --description 'docker-runner' \\"   # 러너 설명
echo "  --docker-network-mode host \\"      # 호스트 네트워크 모드 사용 (통신 문제 최소화)
echo "  --docker-volumes /var/run/docker.sock:/var/run/docker.sock" # Docker 소켓 공유
echo " --------------------------------------------------"
