#!/usr/bin/env bash
set -euo pipefail

say(){ echo -e "\033[0;32m$*\033[0m"; }
warn(){ echo -e "\033[1;33m$*\033[0m"; }
err(){ echo -e "\033[0;31m$*\033[0m"; }

need(){ command -v "$1" >/dev/null 2>&1 || { err "❌ '$1' 필요"; exit 1; }; }
need kubectl
need curl
need base64
need sed
need awk

# ---------- env ----------
ENV_FILE="${1:-./.env.gitops-lab}"
if [[ ! -f "$ENV_FILE" ]]; then
  err "❌ env 파일 없음: $ENV_FILE"
  echo "   예) ./20-k8s-bootstrap-phase3-https.sh ./.env.gitops-lab"
  exit 1
fi
# shellcheck disable=SC1090
source "$ENV_FILE"

# ---------- safety checks for env ----------
: "${REGISTRY_HOSTPORT:=}"
: "${GITOPS_REPO_URL:=}"
: "${GITLAB_CA_CERT:=}"   # (선택) GitLab bootstrap에서 저장해둔 CA 경로

if [[ -z "$REGISTRY_HOSTPORT" ]]; then
  err "❌ REGISTRY_HOSTPORT env가 비어있음(.env.gitops-lab 확인)"
  exit 1
fi
if [[ "$REGISTRY_HOSTPORT" =~ ^https?:// ]]; then
  err "❌ REGISTRY_HOSTPORT에는 스킴(https://)을 넣으면 안 됩니다: $REGISTRY_HOSTPORT"
  echo "   ✅ 예: 192.168.10.47:5050"
  exit 1
fi

if [[ -z "$GITOPS_REPO_URL" ]]; then
  err "❌ GITOPS_REPO_URL env가 비어있음(.env.gitops-lab 확인)"
  exit 1
fi
if [[ "$GITOPS_REPO_URL" =~ ^http:// ]]; then
  warn "⚠️ GITOPS_REPO_URL이 http:// 입니다. GitLab이 HTTPS면 https:// 로 바꾸는 게 보통 맞습니다."
fi

# ---------- kubectl preflight (sudo/루트로 실행해도 최대한 살아남기) ----------
kube_ok() { kubectl get nodes >/dev/null 2>&1; }

if ! kube_ok; then
  if [[ -f /etc/kubernetes/admin.conf ]]; then
    warn "⚠️ kubectl 연결 실패 → /etc/kubernetes/admin.conf로 재시도(KUBECONFIG 설정)"
    export KUBECONFIG=/etc/kubernetes/admin.conf
  fi
fi

if ! kube_ok; then
  err "❌ kubectl이 클러스터에 연결되지 않음"
  echo "   - 현재 사용자 kubeconfig 확인"
  echo "   - 또는 root로 실행 중이면: export KUBECONFIG=/etc/kubernetes/admin.conf"
  exit 1
fi

CTX="$(kubectl config current-context 2>/dev/null || true)"
echo "=================================================="
echo " Phase 3 Bootstrap (Ingress-NGINX + Argo CD) + GitLab HTTPS(사설 CA) 대응"
echo " - (옵션) Helm 설치"
echo " - (옵션) ingress-nginx 설치(Helm, LoadBalancer)   # MetalLB 사용 시 권장"
echo " - Argo CD 설치(SSA)/NodePort 노출/초기 비번 출력"
echo " - app namespace + registry pull secret + SA patch"
echo " - (옵션) Argo repo credential secret"
echo " - (옵션) Argo TLS CA 등록(argocd-tls-certs-cm) + repo-server restart"
echo " - (옵션) Argo Application apply"
echo "=================================================="
warn "현재 kubectl context: ${CTX:-<unknown>}"
warn "⚠️ 컨텍스트가 틀리면 사고납니다."
read -rp "계속할까요? (y/n) [기본 n]: " OK
OK="${OK:-n}"
[[ "$OK" =~ ^[Yy]$ ]] || { echo "취소"; exit 0; }

echo
read -rp "Q0-1) Helm 설치할까요? (y/N): " DO_HELM
DO_HELM="${DO_HELM:-N}"

# ✅ 문구 수정: NodePort → LoadBalancer
read -rp "Q0-2) ingress-nginx 설치할까요? (Helm, LoadBalancer) (y/N): " DO_ING
DO_ING="${DO_ING:-N}"

read -rp "Q1) Argo CD namespace [기본 argocd]: " ARGO_NS
ARGO_NS="${ARGO_NS:-argocd}"

read -rp "Q2) Argo CD 설치할까요? (SSA로 apply) (y/N): " DO_ARGO
DO_ARGO="${DO_ARGO:-N}"

read -rp "Q3) Argo CD UI를 NodePort로 노출할까요? (y/N): " DO_NODEPORT
DO_NODEPORT="${DO_NODEPORT:-N}"

read -rp "Q4) 배포(namespace) [기본 demo]: " TARGET_NS
TARGET_NS="${TARGET_NS:-demo}"

read -rp "Q5) Argo Application까지 만들까요? (y/N): " DO_APP
DO_APP="${DO_APP:-N}"

APP_NAME="demo-dev"
GITOPS_PATH="apps/demo/overlays/dev"
if [[ "$DO_APP" =~ ^[Yy]$ ]]; then
  read -rp "Q5-1) Application 이름 [기본 demo-dev]: " APP_NAME
  APP_NAME="${APP_NAME:-demo-dev}"
  read -rp "Q5-2) GitOps path [기본 apps/demo/overlays/dev]: " GITOPS_PATH
  GITOPS_PATH="${GITOPS_PATH:-apps/demo/overlays/dev}"
fi

# --- (옵션) Argo TLS CA 등록 여부 ---
DO_ARGO_TLS="N"
if [[ "$GITOPS_REPO_URL" =~ ^https:// ]]; then
  if [[ -z "${GITLAB_CA_CERT:-}" ]]; then
    read -rp "Q5-3) (권장) GitLab CA 인증서 경로(Argo TLS 등록용) [엔터=스킵]: " GITLAB_CA_CERT
    GITLAB_CA_CERT="${GITLAB_CA_CERT:-}"
  fi

  if [[ -n "${GITLAB_CA_CERT:-}" ]]; then
    read -rp "Q5-4) (권장) Argo(repo-server)에 GitLab CA 등록할까요? (y/N): " DO_ARGO_TLS
    DO_ARGO_TLS="${DO_ARGO_TLS:-N}"
  fi
else
  warn "⚠️ GITOPS_REPO_URL이 https://가 아니라서 Argo TLS CA 등록은 스킵됩니다."
fi

echo
warn "-------------------- 확인 --------------------"
warn " GitLab Registry : ${REGISTRY_HOSTPORT:-<empty>}"
warn " GitOps Repo URL : ${GITOPS_REPO_URL:-<empty>}"
warn " Argo NS         : $ARGO_NS"
warn " Install ArgoCD  : $DO_ARGO"
warn " NodePort expose : $DO_NODEPORT"
warn " Install ingress : $DO_ING (LoadBalancer)"
warn " Target NS       : $TARGET_NS"
warn " Argo TLS CA     : $DO_ARGO_TLS (CA=${GITLAB_CA_CERT:-<none>})"
warn " Make App        : $DO_APP"
warn " App Name        : $APP_NAME"
warn " GitOps Path     : $GITOPS_PATH"
warn "--------------------------------------------"
read -rp "진행할까요? (y/n) [기본 n]: " CONFIRM
CONFIRM="${CONFIRM:-n}"
[[ "$CONFIRM" =~ ^[Yy]$ ]] || { echo "취소"; exit 0; }

# ---------- (옵션) Helm 설치 ----------
if [[ "$DO_HELM" =~ ^[Yy]$ ]]; then
  if command -v helm >/dev/null 2>&1; then
    say "✅ Helm 이미 설치됨: $(helm version --short 2>/dev/null || true)"
  else
    warn "➕ Helm 설치(get-helm-3)"
    if command -v sudo >/dev/null 2>&1; then
      curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | sudo bash
    else
      curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
    fi
    say "✅ Helm 설치 완료: $(helm version --short 2>/dev/null || true)"
  fi
else
  warn "⏭ Helm 설치 스킵"
fi

# ---------- (옵션) ingress-nginx 설치 ----------
if [[ "$DO_ING" =~ ^[Yy]$ ]]; then
  need helm
  say "[1/7] ingress-nginx 설치(LoadBalancer / MetalLB)"
  helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx >/dev/null 2>&1 || true
  helm repo update >/dev/null 2>&1 || true

  helm upgrade --install ingress-nginx ingress-nginx/ingress-nginx \
    -n ingress-nginx --create-namespace \
    --set controller.service.type=LoadBalancer >/dev/null

  say "✅ ingress-nginx 설치 완료. Service 확인:"
  kubectl -n ingress-nginx get svc ingress-nginx-controller || true
else
  warn "⏭ ingress-nginx 설치 스킵"
fi

# ---------- Argo CD namespace 상태 확인 ----------
ns_phase="$(kubectl get ns "$ARGO_NS" -o jsonpath='{.status.phase}' 2>/dev/null || true)"
if [[ "$ns_phase" == "Terminating" ]]; then
  err "❌ namespace '$ARGO_NS' 가 Terminating 상태입니다."
  echo "   이 상태에서 설치하면 'forbidden: namespace is being terminated' 로 터집니다."
  echo "   먼저 namespace 삭제가 완전히 끝나도록 정리/복구 후 다시 실행하세요."
  exit 1
fi

# ---------- Argo CD 설치 (SSA) ----------
if [[ "$DO_ARGO" =~ ^[Yy]$ ]]; then
  say "[2/7] Argo CD 설치(SSA) namespace=${ARGO_NS}"
  kubectl get ns "$ARGO_NS" >/dev/null 2>&1 || kubectl create ns "$ARGO_NS" >/dev/null

  ARGO_MANIFEST="https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml"

  # SSA로 적용(어노테이션 too long 방지)
  kubectl apply --server-side --force-conflicts -n "$ARGO_NS" -f "$ARGO_MANIFEST" >/dev/null

  say "⏳ ArgoCD rollout 대기(최대 15분)"
  kubectl -n "$ARGO_NS" rollout status deploy/argocd-server --timeout=900s || true
  kubectl -n "$ARGO_NS" rollout status deploy/argocd-repo-server --timeout=900s || true
  kubectl -n "$ARGO_NS" rollout status deploy/argocd-redis --timeout=900s || true
  kubectl -n "$ARGO_NS" rollout status deploy/argocd-applicationset-controller --timeout=900s || true

  say "✅ ArgoCD apply 완료(상태 확인 권장)"
else
  warn "⏭ Argo CD 설치 스킵(이미 설치돼있다고 가정)"
  kubectl get ns "$ARGO_NS" >/dev/null 2>&1 || { err "❌ Argo NS($ARGO_NS) 없음. Q2에서 y로 설치하거나 먼저 설치하세요."; exit 1; }
fi

# ---------- NodePort 노출 + 초기 비번 ----------
if [[ "$DO_NODEPORT" =~ ^[Yy]$ ]]; then
  say "[3/7] argocd-server Service를 NodePort로 변경"
  kubectl -n "$ARGO_NS" patch svc argocd-server -p '{"spec":{"type":"NodePort"}}' >/dev/null || true

  NODEPORT_HTTPS="$(kubectl -n "$ARGO_NS" get svc argocd-server -o jsonpath='{.spec.ports[?(@.name=="https")].nodePort}' 2>/dev/null || true)"
  NODEPORT_HTTP="$(kubectl -n "$ARGO_NS" get svc argocd-server -o jsonpath='{.spec.ports[?(@.name=="http")].nodePort}' 2>/dev/null || true)"
  say "✅ NodePort http=${NODEPORT_HTTP:-?} / https=${NODEPORT_HTTPS:-?}"

  if kubectl -n "$ARGO_NS" get secret argocd-initial-admin-secret >/dev/null 2>&1; then
    PASS="$(kubectl -n "$ARGO_NS" get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d)"
    warn "초기 admin 비밀번호: $PASS"
    warn "※ 로그인 후 비밀번호 변경 권장"
  else
    warn "⚠️ initial secret이 없음(이미 변경/삭제되었을 수 있음)"
  fi
else
  warn "⏭ NodePort 노출 스킵"
fi

# ---------- (권장) Argo repo-server에 GitLab CA 등록 (HTTPS self-signed 대응) ----------
if [[ "$DO_ARGO_TLS" =~ ^[Yy]$ ]]; then
  if [[ -z "${GITLAB_CA_CERT:-}" || ! -f "${GITLAB_CA_CERT}" ]]; then
    err "❌ CA 파일을 찾을 수 없음: ${GITLAB_CA_CERT:-<empty>}"
    echo "   - .env.gitops-lab의 GITLAB_CA_CERT 경로 확인"
    echo "   - 또는 이 스크립트 실행 머신에 CA 파일이 있어야 함"
    exit 1
  fi

  # repo URL에서 host만 추출(포트 제거) → ConfigMap key 규칙(콜론 불가) 대응
  _hostport="$(echo "$GITOPS_REPO_URL" | sed -E 's#^https?://##' | sed -E 's#/.*##')"
  GITLAB_HOST_FOR_ARGO="${_hostport%%:*}"

  say "[추가] Argo TLS CA 등록: argocd-tls-certs-cm (key=${GITLAB_HOST_FOR_ARGO})"
  kubectl -n "$ARGO_NS" create configmap argocd-tls-certs-cm \
    --from-file="${GITLAB_HOST_FOR_ARGO}=${GITLAB_CA_CERT}" \
    --dry-run=client -o yaml | kubectl apply -f - >/dev/null

  kubectl -n "$ARGO_NS" rollout restart deploy/argocd-repo-server >/dev/null || true
  say "✅ Argo repo-server 재시작 완료(CA 반영)"
else
  warn "⏭ Argo TLS CA 등록 스킵(HTTPS self-signed면 이후 x509로 터질 수 있음)"
fi

# ---------- app namespace + registry pull secret ----------
say "[4/7] 배포 namespace 생성/확인: $TARGET_NS"
kubectl get ns "$TARGET_NS" >/dev/null 2>&1 || kubectl create ns "$TARGET_NS" >/dev/null

say "[5/7] imagePullSecret 생성/갱신: gitlab-regcred"
: "${REGISTRY_PULL_USER:?REGISTRY_PULL_USER env가 비어있음}"
: "${REGISTRY_PULL_TOKEN:?REGISTRY_PULL_TOKEN env가 비어있음}"

kubectl -n "$TARGET_NS" delete secret gitlab-regcred --ignore-not-found >/dev/null 2>&1 || true
kubectl -n "$TARGET_NS" create secret docker-registry gitlab-regcred \
  --docker-server="$REGISTRY_HOSTPORT" \
  --docker-username="$REGISTRY_PULL_USER" \
  --docker-password="$REGISTRY_PULL_TOKEN" \
  --docker-email="none@example.com" >/dev/null

kubectl -n "$TARGET_NS" patch serviceaccount default \
  -p '{"imagePullSecrets":[{"name":"gitlab-regcred"}]}' >/dev/null || true

say "✅ secret/SA 확인:"
kubectl -n "$TARGET_NS" get secret gitlab-regcred >/dev/null
kubectl -n "$TARGET_NS" get sa default -o yaml | sed -n '/imagePullSecrets/,+3p' || true

# ---------- (옵션) Argo repo secret ----------
echo
read -rp "Q6) Argo가 private gitops-repo 접근하도록 repo secret 만들까요? (y/N): " DO_REPO
DO_REPO="${DO_REPO:-N}"

if [[ "$DO_REPO" =~ ^[Yy]$ ]]; then
  say "[6/7] Argo repo secret 생성"
  : "${GITOPS_PROJECT:?GITOPS_PROJECT env가 비어있음}"
  : "${ARGO_GITOPS_READ_USER:?ARGO_GITOPS_READ_USER env가 비어있음}"
  : "${ARGO_GITOPS_READ_TOKEN:?ARGO_GITOPS_READ_TOKEN env가 비어있음}"

  SECRET_NAME="repo-${GITOPS_PROJECT}"
  kubectl -n "$ARGO_NS" delete secret "$SECRET_NAME" --ignore-not-found >/dev/null 2>&1 || true

  kubectl -n "$ARGO_NS" create secret generic "$SECRET_NAME" \
    --from-literal=type=git \
    --from-literal=url="$GITOPS_REPO_URL" \
    --from-literal=username="$ARGO_GITOPS_READ_USER" \
    --from-literal=password="$ARGO_GITOPS_READ_TOKEN" \
    --dry-run=client -o yaml | kubectl apply -f - >/dev/null

  kubectl -n "$ARGO_NS" label secret "$SECRET_NAME" argocd.argoproj.io/secret-type=repository --overwrite >/dev/null
  say "✅ repo secret 적용 완료: $SECRET_NAME"
else
  warn "⏭ repo secret 스킵"
fi

# ---------- (옵션) Application apply ----------
if [[ "$DO_APP" =~ ^[Yy]$ ]]; then
  say "[7/7] Argo Application apply"
  TMP="/tmp/${APP_NAME}.yaml"
  cat > "$TMP" <<YAML
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: ${APP_NAME}
  namespace: ${ARGO_NS}
spec:
  project: default
  source:
    repoURL: "${GITOPS_REPO_URL}"
    targetRevision: main
    path: ${GITOPS_PATH}
  destination:
    server: "https://kubernetes.default.svc"
    namespace: ${TARGET_NS}
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
YAML
  kubectl apply -f "$TMP"
  say "🎉 Application 생성/갱신 완료: ${APP_NAME}"
else
  warn "⏭ Application 스킵"
fi

echo
say "끝! 지금 확인하면 좋은 것들:"
echo "  kubectl -n ${ARGO_NS} get pods -o wide"
echo "  kubectl -n ${ARGO_NS} get svc"
echo "  kubectl -n ${ARGO_NS} get applications 2>/dev/null || true"
echo "  kubectl -n ${ARGO_NS} get events --sort-by=.metadata.creationTimestamp | tail -n 30"
echo
warn "⚠️ (중요) Registry가 self-signed HTTPS면, 각 K8s 노드(containerd/docker)가 CA를 신뢰해야 image pull이 성공합니다."
warn "    → 이 스크립트(kubectl)만으로는 해결되지 않을 수 있음(노드 OS/런타임 설정 필요)"
