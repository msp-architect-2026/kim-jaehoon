#!/usr/bin/env bash
# ==============================================================================
# 20-k8s-bootstrap-phase3.sh
# 역할: K8s 클러스터 Phase 3 부트스트랩
#   - (옵션) Helm 설치
#   - (옵션) ingress-nginx 설치 (NodePort / LoadBalancer 선택)
#             └─ LoadBalancer 선택 시 MetalLB 자동 설치 (전제조건)
#   - (옵션) Argo CD 설치
#   - (옵션) Argo CD NodePort 노출
#   - namespace + imagePullSecret 생성
#   - (옵션) Argo repo secret 생성
#   - (옵션) Argo TLS CA 등록
#   - (옵션) Argo Application 생성
#
# 멱등성 보장: 몇 번 실행해도 동일한 결과
# ==============================================================================
set -euo pipefail

say()  { echo -e "\033[0;32m$*\033[0m"; }
warn() { echo -e "\033[1;33m$*\033[0m"; }
err()  { echo -e "\033[0;31m$*\033[0m"; }
need() { command -v "$1" >/dev/null 2>&1 || { err "❌ '$1' 필요"; exit 1; }; }

need kubectl
need curl
need base64
need sed
need awk

# ---------- env 로드 ----------
ENV_FILE="${1:-./.env.gitops-lab}"
if [[ ! -f "$ENV_FILE" ]]; then
  err "❌ env 파일 없음: $ENV_FILE"
  echo "   예) ./20-k8s-bootstrap-phase3.sh ./.env.gitops-lab"
  exit 1
fi
# shellcheck disable=SC1090
source "$ENV_FILE"

# ---------- env 검증 ----------
: "${REGISTRY_HOSTPORT:=}"
: "${GITOPS_REPO_URL:=}"
: "${GITLAB_CA_CERT:=}"

if [[ -z "$REGISTRY_HOSTPORT" ]]; then
  err "❌ REGISTRY_HOSTPORT env가 비어있음"
  exit 1
fi
if [[ "$REGISTRY_HOSTPORT" =~ ^https?:// ]]; then
  err "❌ REGISTRY_HOSTPORT에 스킴 불가: $REGISTRY_HOSTPORT"
  echo "   ✅ 예: 192.168.10.47:5050"
  exit 1
fi
if [[ -z "$GITOPS_REPO_URL" ]]; then
  err "❌ GITOPS_REPO_URL env가 비어있음"
  exit 1
fi
if [[ "$GITOPS_REPO_URL" =~ ^http:// ]]; then
  warn "⚠️  GITOPS_REPO_URL이 http:// 입니다. HTTPS 권장"
fi

# ---------- kubectl 연결 확인 ----------
kube_ok() { kubectl get nodes >/dev/null 2>&1; }
if ! kube_ok; then
  if [[ -f /etc/kubernetes/admin.conf ]]; then
    warn "⚠️  kubectl 연결 실패 → /etc/kubernetes/admin.conf 시도"
    export KUBECONFIG=/etc/kubernetes/admin.conf
  fi
fi
if ! kube_ok; then
  err "❌ kubectl이 클러스터에 연결되지 않음"
  exit 1
fi

CTX="$(kubectl config current-context 2>/dev/null || true)"
echo "=================================================="
echo " Phase 3 Bootstrap"
echo "=================================================="
warn " kubectl context: ${CTX:-<unknown>}"
warn " ⚠️  컨텍스트가 틀리면 사고납니다."
read -rp "계속할까요? (y/n) [기본 n]: " OK
OK="${OK:-n}"
[[ "$OK" =~ ^[Yy]$ ]] || { echo "취소"; exit 0; }

echo
read -rp "Q0-1) Helm 설치할까요? (y/N): "          DO_HELM;     DO_HELM="${DO_HELM:-N}"
read -rp "Q0-2) ingress-nginx 설치할까요? (y/N): " DO_ING;      DO_ING="${DO_ING:-N}"

# ---------- ingress-nginx Service 타입 선택 ----------
ING_SVC_TYPE="NodePort"
if [[ "$DO_ING" =~ ^[Yy]$ ]]; then
  echo
  echo "  ingress-nginx Service 타입을 선택하세요."
  echo "    1) NodePort     - 외부 LB 없이 노드IP:NodePort로 직접 접근"
  echo "    2) LoadBalancer - MetalLB 등 외부 LB 환경에서 EXTERNAL-IP 자동 할당"
  read -rp "  선택 [기본 1]: " ING_SVC_CHOICE
  ING_SVC_CHOICE="${ING_SVC_CHOICE:-1}"
  case "$ING_SVC_CHOICE" in
    1) ING_SVC_TYPE="NodePort"     ;;
    2) ING_SVC_TYPE="LoadBalancer" ;;
    *) warn "⚠️  잘못된 선택 → 기본값 NodePort 사용"; ING_SVC_TYPE="NodePort" ;;
  esac
  say "  ✅ ingress-nginx Service 타입: ${ING_SVC_TYPE}"
  echo
fi

read -rp "Q1)   Argo CD namespace [기본 argocd]: "        ARGO_NS;     ARGO_NS="${ARGO_NS:-argocd}"
read -rp "Q2)   Argo CD 설치할까요? (y/N): "              DO_ARGO;     DO_ARGO="${DO_ARGO:-N}"
read -rp "Q3)   Argo CD UI NodePort 노출할까요? (y/N): "  DO_NODEPORT; DO_NODEPORT="${DO_NODEPORT:-N}"

read -rp "Q4)   배포 namespace [기본 boutique]: " TARGET_NS
TARGET_NS="${TARGET_NS:-boutique}"

read -rp "Q5)   Argo Application 생성할까요? (y/N): " DO_APP
DO_APP="${DO_APP:-N}"

APP_NAME="boutique-dev"
GITOPS_PATH="apps/boutique/overlays/dev"
if [[ "$DO_APP" =~ ^[Yy]$ ]]; then
  read -rp "Q5-1) Application 이름 [기본 boutique-dev]: "            APP_NAME;    APP_NAME="${APP_NAME:-boutique-dev}"
  read -rp "Q5-2) GitOps path [기본 apps/boutique/overlays/dev]: " GITOPS_PATH; GITOPS_PATH="${GITOPS_PATH:-apps/boutique/overlays/dev}"
fi

# Argo TLS CA 등록 여부
DO_ARGO_TLS="N"
if [[ "$GITOPS_REPO_URL" =~ ^https:// ]]; then
  if [[ -z "${GITLAB_CA_CERT:-}" ]]; then
    read -rp "Q5-3) GitLab CA 인증서 경로 [엔터=스킵]: " GITLAB_CA_CERT
    GITLAB_CA_CERT="${GITLAB_CA_CERT:-}"
  fi
  if [[ -n "${GITLAB_CA_CERT:-}" ]]; then
    read -rp "Q5-4) Argo repo-server에 GitLab CA 등록할까요? (y/N): " DO_ARGO_TLS
    DO_ARGO_TLS="${DO_ARGO_TLS:-N}"
  fi
else
  warn "⚠️  GITOPS_REPO_URL이 https:// 아님 → Argo TLS CA 등록 스킵"
fi

read -rp "Q6)   Argo repo secret 생성할까요? (y/N): " DO_REPO
DO_REPO="${DO_REPO:-N}"

echo
warn "-------------------- 확인 --------------------"
warn " GitLab Registry  : ${REGISTRY_HOSTPORT}"
warn " GitOps Repo URL  : ${GITOPS_REPO_URL}"
warn " Argo NS          : ${ARGO_NS}"
warn " Install ArgoCD   : ${DO_ARGO}"
warn " NodePort expose  : ${DO_NODEPORT}"
warn " Install ingress  : ${DO_ING}"
if [[ "$DO_ING" =~ ^[Yy]$ ]]; then
warn " Ingress SVC Type : ${ING_SVC_TYPE}"
  if [[ "$ING_SVC_TYPE" == "LoadBalancer" ]]; then
warn " Install MetalLB  : Y (LoadBalancer 선택 시 자동)"
  fi
fi
warn " Target NS        : ${TARGET_NS}"
warn " Argo TLS CA      : ${DO_ARGO_TLS} (CA=${GITLAB_CA_CERT:-<none>})"
warn " Repo Secret      : ${DO_REPO}"
warn " Make App         : ${DO_APP}"
warn " App Name         : ${APP_NAME}"
warn " GitOps Path      : ${GITOPS_PATH}"
warn "--------------------------------------------"
read -rp "진행할까요? (y/n) [기본 n]: " CONFIRM
CONFIRM="${CONFIRM:-n}"
[[ "$CONFIRM" =~ ^[Yy]$ ]] || { echo "취소"; exit 0; }

# ---------- Helm 설치 ----------
if [[ "$DO_HELM" =~ ^[Yy]$ ]]; then
  if command -v helm >/dev/null 2>&1; then
    say "✅ Helm 이미 설치됨: $(helm version --short 2>/dev/null || true)"
  else
    warn "➕ Helm 설치 중..."
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

# ---------- MetalLB 설치 (LoadBalancer 선택 시 전제조건) ----------
if [[ "$DO_ING" =~ ^[Yy]$ && "$ING_SVC_TYPE" == "LoadBalancer" ]]; then
  say "[1-pre] MetalLB 설치 (LoadBalancer 모드 전제조건)"
  METALLB_VERSION="v0.14.3"

  # 이미 설치된 경우 스킵
  if kubectl -n metallb-system get deploy controller >/dev/null 2>&1; then
    say "✅ MetalLB 이미 설치됨 (스킵)"
  else
    warn "➕ MetalLB ${METALLB_VERSION} 설치 중..."
    kubectl apply -f "https://raw.githubusercontent.com/metallb/metallb/${METALLB_VERSION}/config/manifests/metallb-native.yaml" >/dev/null
    say "⏳ MetalLB controller rollout 대기(최대 3분)..."
    kubectl -n metallb-system rollout status deploy/controller --timeout=180s
    say "⏳ MetalLB speaker rollout 대기(최대 3분)..."
    kubectl -n metallb-system rollout status ds/speaker --timeout=180s
    say "⏳ MetalLB webhook-server rollout 대기(최대 3분)..."
    kubectl -n metallb-system rollout status deploy/webhook-server --timeout=180s
    say "⏳ MetalLB webhook 소켓 준비 대기(10초)..."
    sleep 10
    say "✅ MetalLB 설치 완료 (${METALLB_VERSION})"
  fi
  echo
fi

# ---------- ingress-nginx 설치 ----------
if [[ "$DO_ING" =~ ^[Yy]$ ]]; then
  need helm
  say "[1/7] ingress-nginx 설치 (Service 타입: ${ING_SVC_TYPE})"
  helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx >/dev/null 2>&1 || true
  helm repo update >/dev/null 2>&1 || true
  helm upgrade --install ingress-nginx ingress-nginx/ingress-nginx \
    -n ingress-nginx --create-namespace \
    --set controller.service.type="${ING_SVC_TYPE}" >/dev/null
  say "✅ ingress-nginx 설치 완료 (type=${ING_SVC_TYPE})"
  kubectl -n ingress-nginx get svc ingress-nginx-controller || true
else
  warn "⏭ ingress-nginx 설치 스킵"
fi

# ---------- Argo CD namespace 상태 확인 ----------
ns_phase="$(kubectl get ns "$ARGO_NS" -o jsonpath='{.status.phase}' 2>/dev/null || true)"
if [[ "$ns_phase" == "Terminating" ]]; then
  err "❌ namespace '$ARGO_NS' 가 Terminating 상태 → 완전히 삭제 후 재실행"
  exit 1
fi

# ---------- Argo CD 설치 ----------
if [[ "$DO_ARGO" =~ ^[Yy]$ ]]; then
  say "[2/7] Argo CD 설치(SSA) namespace=${ARGO_NS}"
  kubectl get ns "$ARGO_NS" >/dev/null 2>&1 || kubectl create ns "$ARGO_NS" >/dev/null
  ARGO_MANIFEST="https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml"
  kubectl apply --server-side --force-conflicts -n "$ARGO_NS" -f "$ARGO_MANIFEST" >/dev/null
  say "⏳ Argo CD rollout 대기(최대 15분)..."
  kubectl -n "$ARGO_NS" rollout status deploy/argocd-server                    --timeout=900s || true
  kubectl -n "$ARGO_NS" rollout status deploy/argocd-repo-server               --timeout=900s || true
  kubectl -n "$ARGO_NS" rollout status deploy/argocd-redis                     --timeout=900s || true
  kubectl -n "$ARGO_NS" rollout status deploy/argocd-applicationset-controller --timeout=900s || true
  say "✅ Argo CD 설치 완료"
else
  warn "⏭ Argo CD 설치 스킵"
  kubectl get ns "$ARGO_NS" >/dev/null 2>&1 || {
    err "❌ Argo NS($ARGO_NS) 없음. Q2에서 y로 설치하세요."
    exit 1
  }
fi

# ---------- NodePort 노출 ----------
if [[ "$DO_NODEPORT" =~ ^[Yy]$ ]]; then
  say "[3/7] argocd-server NodePort 노출"
  kubectl -n "$ARGO_NS" patch svc argocd-server \
    -p '{"spec":{"type":"NodePort"}}' >/dev/null || true
  NODEPORT_HTTPS="$(kubectl -n "$ARGO_NS" get svc argocd-server \
    -o jsonpath='{.spec.ports[?(@.name=="https")].nodePort}' 2>/dev/null || true)"
  NODEPORT_HTTP="$(kubectl -n "$ARGO_NS" get svc argocd-server \
    -o jsonpath='{.spec.ports[?(@.name=="http")].nodePort}' 2>/dev/null || true)"
  say "✅ NodePort http=${NODEPORT_HTTP:-?} / https=${NODEPORT_HTTPS:-?}"
  if kubectl -n "$ARGO_NS" get secret argocd-initial-admin-secret >/dev/null 2>&1; then
    PASS="$(kubectl -n "$ARGO_NS" get secret argocd-initial-admin-secret \
      -o jsonpath='{.data.password}' | base64 -d)"
    warn "초기 admin 비밀번호: $PASS"
    warn "※ 로그인 후 비밀번호 변경 권장"
  else
    warn "⚠️  initial secret 없음 (이미 변경/삭제됨)"
  fi
else
  warn "⏭ NodePort 노출 스킵"
fi

# ---------- Argo TLS CA 등록 ----------
if [[ "$DO_ARGO_TLS" =~ ^[Yy]$ ]]; then
  if [[ -z "${GITLAB_CA_CERT:-}" || ! -f "${GITLAB_CA_CERT}" ]]; then
    err "❌ CA 파일 없음: ${GITLAB_CA_CERT:-<empty>}"
    exit 1
  fi
  _hostport="$(echo "$GITOPS_REPO_URL" | sed -E 's#^https?://##' | sed -E 's#/.*##')"
  GITLAB_HOST_FOR_ARGO="${_hostport%%:*}"
  say "[추가] Argo TLS CA 등록 (key=${GITLAB_HOST_FOR_ARGO})"
  kubectl -n "$ARGO_NS" create configmap argocd-tls-certs-cm \
    --from-file="${GITLAB_HOST_FOR_ARGO}=${GITLAB_CA_CERT}" \
    --dry-run=client -o yaml | kubectl apply -f - >/dev/null
  kubectl -n "$ARGO_NS" rollout restart deploy/argocd-repo-server >/dev/null || true
  say "✅ Argo TLS CA 등록 완료"
else
  warn "⏭ Argo TLS CA 등록 스킵"
fi

# ---------- namespace + imagePullSecret ----------
say "[4/7] namespace 생성/확인: ${TARGET_NS}"
kubectl get ns "$TARGET_NS" >/dev/null 2>&1 || kubectl create ns "$TARGET_NS" >/dev/null

say "[5/7] imagePullSecret 생성/갱신: gitlab-regcred"
: "${REGISTRY_PULL_USER:?REGISTRY_PULL_USER env 없음}"
: "${REGISTRY_PULL_TOKEN:?REGISTRY_PULL_TOKEN env 없음}"
kubectl -n "$TARGET_NS" delete secret gitlab-regcred --ignore-not-found >/dev/null 2>&1 || true
kubectl -n "$TARGET_NS" create secret docker-registry gitlab-regcred \
  --docker-server="$REGISTRY_HOSTPORT" \
  --docker-username="$REGISTRY_PULL_USER" \
  --docker-password="$REGISTRY_PULL_TOKEN" \
  --docker-email="none@example.com" >/dev/null
say "✅ gitlab-regcred 생성 완료"

kubectl -n "$TARGET_NS" patch serviceaccount default \
  -p '{"imagePullSecrets":[{"name":"gitlab-regcred"}]}' >/dev/null || true
say "✅ default SA imagePullSecrets 패치 완료"
say "   ℹ️  나머지 SA는 kustomization.yaml patches 블록으로 Argo CD sync 시 자동 적용됩니다."

# ---------- Argo repo secret ----------
if [[ "$DO_REPO" =~ ^[Yy]$ ]]; then
  say "[6/7] Argo repo secret 생성"
  : "${GITOPS_PROJECT:?GITOPS_PROJECT env 없음}"
  : "${ARGO_GITOPS_READ_USER:?ARGO_GITOPS_READ_USER env 없음}"
  : "${ARGO_GITOPS_READ_TOKEN:?ARGO_GITOPS_READ_TOKEN env 없음}"
  SECRET_NAME="repo-${GITOPS_PROJECT}"
  kubectl -n "$ARGO_NS" delete secret "$SECRET_NAME" --ignore-not-found >/dev/null 2>&1 || true
  kubectl -n "$ARGO_NS" create secret generic "$SECRET_NAME" \
    --from-literal=type=git \
    --from-literal=url="$GITOPS_REPO_URL" \
    --from-literal=username="$ARGO_GITOPS_READ_USER" \
    --from-literal=password="$ARGO_GITOPS_READ_TOKEN" \
    --dry-run=client -o yaml | kubectl apply -f - >/dev/null
  kubectl -n "$ARGO_NS" label secret "$SECRET_NAME" \
    argocd.argoproj.io/secret-type=repository --overwrite >/dev/null
  say "✅ repo secret 완료: ${SECRET_NAME}"
else
  warn "⏭ repo secret 스킵"
fi

# ---------- Argo Application ----------
if [[ "$DO_APP" =~ ^[Yy]$ ]]; then
  say "[7/7] Argo Application 생성/갱신: ${APP_NAME}"
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
  kubectl apply -f "$TMP" >/dev/null
  say "🎉 Application 생성/갱신 완료: ${APP_NAME}"
else
  warn "⏭ Application 생성 스킵"
fi

echo
say "=================================================="
say " 완료!"
say "=================================================="
echo "  kubectl -n ${ARGO_NS} get pods"
echo "  kubectl -n ${ARGO_NS} get applications"
echo "  kubectl -n ${TARGET_NS} get pods"
echo
warn "⚠️  Registry self-signed HTTPS면 각 K8s 노드에 CA trust 등록 필요"
warn "    → install-ca-all.sh 실행 여부 확인"
