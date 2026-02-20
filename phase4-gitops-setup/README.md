🚀 On-Premise GitOps Lab: GitLab + Kubernetes + Argo CD
이 프로젝트는 **Mini PC(GitLab)**와 VM(Kubernetes Cluster) 환경에서 **GitOps 파이프라인(CI/CD)**을 자동으로 구축하는 자동화 스크립트 모음입니다.

복잡한 수동 설정 없이, 단 두 개의 스크립트 실행만으로 아래 아키텍처가 완성됩니다.

코드 스니펫
graph LR
    User[Developer] -->|Push Code| GitLab[GitLab Server\n(Mini PC)]
    GitLab -->|Build & Push Image| Registry[Container Registry]
    ArgoCD[Argo CD\n(K8s Cluster)] -->|Sync Manifest| GitLab
    ArgoCD -->|Deploy| K8s[Kubernetes Nodes]
    K8s -->|Pull Image| Registry
📋 사전 준비 (Prerequisites)
스크립트를 실행하기 전, 다음 환경이 구성되어 있어야 합니다.

1. 하드웨어 및 네트워크
GitLab Server (Mini PC): GitLab Omnibus가 설치되어 있고, 웹 접속이 가능해야 함. (IP 예: 192.168.10.47)

Kubernetes Cluster (VMs): Master 1대 + Worker N대로 구성된 클러스터 (kubeadm 기반).

네트워크: Master 노드에서 GitLab 서버로 ping 및 curl 통신이 가능해야 함.

2. 필수 도구 (Master Node)
스크립트 실행 위치인 Master Node에 아래 도구가 설치되어 있어야 합니다.

Bash
sudo apt install -y curl jq git  # Ubuntu/Debian
# 또는
sudo dnf install -y curl jq git  # Rocky/CentOS
3. GitLab Admin Token
GitLab에 root로 로그인 후, User Settings > Access Tokens에서 토큰을 생성해야 합니다.

Scopes: api 필수 선택.

생성된 토큰(glpat-...)을 복사해 두세요.

🛠️ 설치 가이드 (Installation)
모든 스크립트는 Kubernetes Master Node에서 실행하는 것을 권장합니다.

1️⃣ Phase 1: GitLab 초기화 및 토큰 발급 (repo_Auto.sh)
이 단계에서는 GitLab에 필요한 프로젝트(app-repo, gitops-repo)를 생성하고, CI/CD 및 Argo CD 연동에 필요한 3가지 핵심 토큰을 발급하여 .env 파일로 저장합니다.

실행 권한 부여 및 실행:

Bash
chmod +x repo_Auto.sh
./repo_Auto.sh
입력사항:

GitLab URL: (예: http://192.168.10.47)

GitLab Token: 위에서 발급받은 Admin Token 입력.

나머지는 기본값(Enter) 권장.

결과 확인:

실행이 완료되면 현재 디렉토리에 .env.gitops-lab 파일이 생성됩니다.

주의: 이 파일에는 민감한 토큰 정보가 들어있으므로 외부 유출에 주의하세요.

2️⃣ Phase 2: K8s 컴포넌트 설치 및 연동 (20-k8s-bootstrap-phase3.sh)
이 단계에서는 Kubernetes 클러스터에 Ingress-Nginx, Argo CD를 설치하고, Phase 1에서 생성된 토큰을 사용하여 **GitLab과의 인증(Secret)**을 자동으로 연결합니다.

실행 권한 부여 및 실행:

Bash
chmod +x 20-k8s-bootstrap-phase3.sh
./20-k8s-bootstrap-phase3.sh ./.env.gitops-lab
주요 질문 답변 가이드:

Helm 설치: y (필수)

ingress-nginx 설치: y (외부 접속용)

Argo CD 설치: y

NodePort 노출: y (웹 접속용)

Repo Secret 생성: y (GitLab 비공개 레포 접근용, 필수)

Application 생성: n (추천: 추후 코드 푸시 후 생성)

✅ 설치 확인 및 접속 (Verification)
설치가 완료되면 아래 정보를 통해 정상 동작을 확인합니다.

1. Pod 상태 확인
모든 Pod가 Running 상태여야 합니다.

Bash
kubectl get pods -n argocd
kubectl get pods -n ingress-nginx
2. Argo CD 접속 정보 확인
웹 브라우저 접속을 위한 포트와 초기 비밀번호를 확인합니다.

접속 주소 (HTTPS):

Bash
# HTTPS 포트 확인 (예: 30443)
kubectl -n argocd get svc argocd-server
👉 브라우저 주소창: https://<Master-Node-IP>:<PORT>

초기 비밀번호 (ID: admin):

Bash
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d && echo
3. 연동 상태 확인 (Secret)
GitLab과 연결된 Secret이 정상적으로 생성되었는지 확인합니다.

Bash
# Argo CD가 GitLab 레포를 읽기 위한 시크릿
kubectl get secret -n argocd -l argocd.argoproj.io/secret-type=repository

# K8s가 GitLab Registry에서 이미지를 당겨오기 위한 시크릿
kubectl get secret gitlab-regcred -n demo
🆘 트러블슈팅 (Troubleshooting)
Q. 스크립트 실행 중 curl: (7) Failed to connect 에러가 납니다.

A. Master Node에서 GitLab Server(Mini PC)로 핑이 가는지 확인하세요 (ping 192.168.10.47). 방화벽 문제일 수 있습니다.

Q. Argo CD에서 Sync Failed 또는 Target path does not exist 에러가 뜹니다.

A. 정상입니다. gitops-repo가 현재 비어있기 때문입니다. 코드를 Push하면 해결됩니다.

Q. kubectl 명령어가 안 먹힙니다.

A. Master Node의 root 계정이거나, ~/.kube/config 설정이 올바른지 확인하세요.
