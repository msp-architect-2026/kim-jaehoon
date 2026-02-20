<<<<<<< HEAD
# Phase 0: 사전 준비

Kubernetes 클러스터 구축을 위한 VM 초기 설정

## 📋 준비 사항

- Ubuntu 24.04 LTS VM (Master 1대, Worker 2대)
- Root 또는 sudo 권한
- 인터넷 연결

## 🚀 빠른 시작

### 방법 1: GitHub에서 직접 다운로드 및 실행
```bash
# 스크립트 다운로드
wget https://raw.githubusercontent.com/YOUR_USERNAME/devops-lab-infra/main/phase0-preparation/setup-k8s-node.sh

# 실행 권한 부여
chmod +x setup-k8s-node.sh

# 실행
./setup-k8s-node.sh
```

### 방법 2: Git Clone 후 실행
```bash
# 저장소 클론
git clone https://github.com/YOUR_USERNAME/devops-lab-infra.git
cd devops-lab-infra/phase0-preparation

# 실행 권한 부여
chmod +x setup-k8s-node.sh

# 실행
./setup-k8s-node.sh
```

### 방법 3: 스크립트 내용 복사 붙여넣기 (PuTTY)

1. GitHub에서 `setup-k8s-node.sh` 파일 내용 복사
2. VM에 접속
3. 아래 명령 실행:
```bash
cat > setup-k8s-node.sh << 'EOF'
# [여기에 스크립트 내용 붙여넣기]
EOF

chmod +x setup-k8s-node.sh
./setup-k8s-node.sh
```

## 📦 설정 내용

이 스크립트는 다음 작업을 수행합니다:

1. **패키지 업데이트**
   - 최신 패키지 목록 갱신

2. **필수 도구 설치**
   - ca-certificates, curl, wget, vim, git
   - net-tools, tree, htop, openssh-server

3. **시스템 설정**
   - Timezone: Asia/Seoul
   - NTP 동기화 활성화
   - SSH 서비스 활성화

4. **Kubernetes 필수 설정**
   - Swap 비활성화
   - 커널 모듈 로드 (overlay, br_netfilter)
   - sysctl 네트워크 설정
   - 방화벽(UFW) 비활성화

5. **자동 확인**
   - 모든 설정 적용 여부 자동 검증

## ✅ 확인 사항

스크립트 실행 후 다음을 확인합니다:
```bash
# Timezone 확인
timedatectl | grep "Time zone"

# Swap 비활성화 확인
free -h | grep Swap

# 커널 모듈 확인
lsmod | grep -E 'overlay|br_netfilter'

# sysctl 설정 확인
sudo sysctl net.ipv4.ip_forward
```

## 🔄 모든 노드에 적용

Master, Worker 노드 **모두**에 이 스크립트를 실행해야 합니다.
```bash
# Master 노드
./setup-k8s-node.sh

# Worker 노드 1
./setup-k8s-node.sh

# Worker 노드 2
./setup-k8s-node.sh
```
=======
# Phase 0: 사전 준비

Kubernetes 클러스터 구축을 위한 VM 초기 설정

## 📋 준비 사항

- Ubuntu 24.04 LTS VM (Master 1대, Worker 2대)
- Root 또는 sudo 권한
- 인터넷 연결

## 🚀 빠른 시작

### 방법 1: GitHub에서 직접 다운로드 및 실행
```bash
# 스크립트 다운로드
wget https://raw.githubusercontent.com/YOUR_USERNAME/devops-lab-infra/main/phase0-preparation/setup-k8s-node.sh

# 실행 권한 부여
chmod +x setup-k8s-node.sh

# 실행
./setup-k8s-node.sh
```

### 방법 2: Git Clone 후 실행
```bash
# 저장소 클론
git clone https://github.com/YOUR_USERNAME/devops-lab-infra.git
cd devops-lab-infra/phase0-preparation

# 실행 권한 부여
chmod +x setup-k8s-node.sh

# 실행
./setup-k8s-node.sh
```

### 방법 3: 스크립트 내용 복사 붙여넣기 (PuTTY)

1. GitHub에서 `setup-k8s-node.sh` 파일 내용 복사
2. VM에 접속
3. 아래 명령 실행:
```bash
cat > setup-k8s-node.sh << 'EOF'
# [여기에 스크립트 내용 붙여넣기]
EOF

chmod +x setup-k8s-node.sh
./setup-k8s-node.sh
```

## 📦 설정 내용

이 스크립트는 다음 작업을 수행합니다:

1. **패키지 업데이트**
   - 최신 패키지 목록 갱신

2. **필수 도구 설치**
   - ca-certificates, curl, wget, vim, git
   - net-tools, tree, htop, openssh-server

3. **시스템 설정**
   - Timezone: Asia/Seoul
   - NTP 동기화 활성화
   - SSH 서비스 활성화
   -hosts 파일 수정
4. **Kubernetes 필수 설정**
   - Swap 비활성화
   - 커널 모듈 로드 (overlay, br_netfilter)
   - sysctl 네트워크 설정
   - 방화벽(UFW) 비활성화

5. **자동 확인**
   - 모든 설정 적용 여부 자동 검증

## ✅ 확인 사항

스크립트 실행 후 다음을 확인합니다:
```bash
# Timezone 확인
timedatectl | grep "Time zone"

# Swap 비활성화 확인
free -h | grep Swap

# 커널 모듈 확인
lsmod | grep -E 'overlay|br_netfilter'

# sysctl 설정 확인
sudo sysctl net.ipv4.ip_forward
```

## 🔄 모든 노드에 적용

Master, Worker 노드 **모두**에 이 스크립트를 실행해야 합니다.
```bash
# Master 노드
./setup-k8s-node.sh

# Worker 노드 1
./setup-k8s-node.sh

# Worker 노드 2
./setup-k8s-node.sh
```

## 📝 다음 단계

Phase 0 완료 후 다음 단계로 진행:
- [Phase 2: Kubernetes 클러스터 구축](../phase2-kubernetes/README.md)

>>>>>>> cbfb735c822c1bc9ba9e64690987c0faca82e926
