#!/usr/bin/env bash
# ==============================================================================
# 99-k8s-cleanup-phase3.sh
# 역할: 20-k8s-bootstrap-phase3.sh 적용 내용을 역순으로 완전 초기화
#
# 삭제 순서 (bootstrap 역순):
#   1. Argo CD Application 삭제
#   2. Argo repo secret 삭제
#   3. imagePullSecret / namespace (TARGET_NS) 삭제
#   4. Argo TLS CA configmap 삭제
#   5. Argo CD 삭제 (namespace 포함)
#   6. ingress-nginx 삭제 (helm)
#   7. MetalLB 삭제
#   8. .env 파일의 TARGET_NS 라인 제거 (bootstrap이 추가한 것만)
#
# ※ Helm / OS 패키지 자체는 제거하지 않습니다 (서버 전체 영향 방지)
#   Helm 제거가 필요하면 마지막 안내 메시지를 참고하세요.
# ==============================================================================
set -euo pipefail

say()  { echo -e "\033[0;32m$*\033[0m"; }
warn() { echo -e "\033[1;33m$*\033[0m"; }
err()  { echo -e "\033[0;31m$*\033[0m"; }

# ---------- env 로드 ----------
ENV_FILE="${1:-./.env.gitops-lab}"
if [[ ! -f "$ENV_FILE" ]]; then
  err "❌ env 파일 없음: $ENV_FILE"
  echo "   예) ./99-k8s-cleanup-phase3.sh ./.env.gitops-lab"
  exit 1
fi
# shellcheck disable=SC1090
source "$ENV_FILE"

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

# ---------- 기본값 ----------
: "${ARGO_NS:=argocd}"
: "${TARGET_NS:=boutique}"
: "${GITOPS_PROJECT:=}"
: "${GITOPS_REPO_URL:=}"

CTX="$(kubectl config current-context 2>/dev/null || true)"
echo "=================================================="
echo " Phase 3 CLEANUP (롤백)"
echo "=================================================="
warn " kubectl context : ${CTX:-<unknown>}"
warn " Argo NS         : ${ARGO_NS}"
warn " Target NS       : ${TARGET_NS}"
warn " GitOps Repo     : ${GITOPS_REPO_URL}"
warn ""
warn " ⚠️  이 스크립트는 phase3에서 생성된 모든 리소스를 삭제합니다."
warn " ⚠️  데이터 복구 불가 — 운영 클러스터에서는 각별히 주의하세요."
echo "=================================================="
read -rp "정말 삭제하겠습니까? (y/n) [기본 n]: " CONFIRM
CONFIRM="${CONFIRM:-n}"
[[ "$CONFIRM" =~ ^[Yy]$ ]] || { echo "취소"; exit 0; }

echo
# 개별 항목 선택
read -rp "① Argo CD Application 삭제할까요?     (y/N): " RM_APP;      RM_APP="${RM_APP:-N}"
read -rp "② Argo repo secret 삭제할까요?        (y/N): " RM_REPO;     RM_REPO="${RM_REPO:-N}"
read -rp "③ imagePullSecret + TARGET_NS 삭제?   (y/N): " RM_NS;       RM_NS="${RM_NS:-N}"
read -rp "④ Argo TLS CA configmap 삭제?         (y/N): " RM_TLS;      RM_TLS="${RM_TLS:-N}"
read -rp "⑤ Argo CD 전체 삭제 (NS 포함)?        (y/N): " RM_ARGO;     RM_ARGO="${RM_ARGO:-N}"
read -rp "⑥ ingress-nginx 삭제 (helm)?          (y/N): " RM_ING;      RM_ING="${RM_ING:-N}"
read -rp "⑦ MetalLB 삭제?                       (y/N): " RM_METALLB;  RM_METALLB="${RM_METALLB:-N}"
read -rp "⑧ .env TARGET_NS 라인 제거?           (y/N): " RM_ENV;      RM_ENV="${RM_ENV:-N}"

# Application 이름 / GitOps path (Application 삭제 시 필요)
APP_NAME="boutique-dev"
if [[ "$RM_APP" =~ ^[Yy]$ ]]; then
  read -rp "  삭제할 Application 이름 [기본 boutique-dev]: " APP_NAME
  APP_NAME="${APP_NAME:-boutique-dev}"
fi

echo
warn "--------------- 삭제 대상 확인 ---------------"
[[ "$RM_APP"     =~ ^[Yy]$ ]] && warn " ① Application     : ${APP_NAME} (ns=${ARGO_NS})"
[[ "$RM_REPO"    =~ ^[Yy]$ ]] && warn " ② repo secret     : repo-${GITOPS_PROJECT} (ns=${ARGO_NS})"
[[ "$RM_NS"      =~ ^[Yy]$ ]] && warn " ③ imagePullSecret + namespace : ${TARGET_NS}"
[[ "$RM_TLS"     =~ ^[Yy]$ ]] && warn " ④ TLS CA configmap: argocd-tls-certs-cm (ns=${ARGO_NS})"
[[ "$RM_ARGO"    =~ ^[Yy]$ ]] && warn " ⑤ Argo CD          : namespace ${ARGO_NS} 전체"
[[ "$RM_ING"     =~ ^[Yy]$ ]] && warn " ⑥ ingress-nginx    : helm release + ns ingress-nginx"
[[ "$RM_METALLB" =~ ^[Yy]$ ]] && warn " ⑦ MetalLB          : namespace metallb-system 전체"
[[ "$RM_ENV"     =~ ^[Yy]$ ]] && warn " ⑧ .env TARGET_NS   : ${ENV_FILE}"
warn "----------------------------------------------"
read -rp "진행할까요? (y/n) [기본 n]: " GO
GO="${GO:-n}"
[[ "$GO" =~ ^[Yy]$ ]] || { echo "취소"; exit 0; }

echo

# ==============================================================================
# ① Argo CD Application 삭제
# ==============================================================================
if [[ "$RM_APP" =~ ^[Yy]$ ]]; then
  say "[1/8] Argo CD Application 삭제: ${APP_NAME}"
  if kubectl -n "$ARGO_NS" get application "$APP_NAME" >/dev/null 2>&1; then
    # --cascade=foreground → 하위 리소스까지 함께 삭제 (Argo finalizer 처리)
    kubectl -n "$ARGO_NS" patch application "$APP_NAME" \
      -p '{"metadata":{"finalizers":[]}}' \
      --type=merge >/dev/null 2>&1 || true
    kubectl -n "$ARGO_NS" delete application "$APP_NAME" --ignore-not-found >/dev/null
    say "✅ Application 삭제 완료: ${APP_NAME}"
  else
    warn "⏭ Application 없음 (이미 삭제됨)"
  fi
else
  warn "⏭ Application 삭제 스킵"
fi

# ==============================================================================
# ② Argo repo secret 삭제
# ==============================================================================
if [[ "$RM_REPO" =~ ^[Yy]$ ]]; then
  say "[2/8] Argo repo secret 삭제"
  if [[ -n "${GITOPS_PROJECT:-}" ]]; then
    SECRET_NAME="repo-${GITOPS_PROJECT}"
    kubectl -n "$ARGO_NS" delete secret "$SECRET_NAME" --ignore-not-found >/dev/null
    say "✅ repo secret 삭제: ${SECRET_NAME}"
  else
    warn "⚠️  GITOPS_PROJECT 미설정 → 스킵"
  fi
else
  warn "⏭ repo secret 삭제 스킵"
fi

# ==============================================================================
# ③ imagePullSecret + TARGET_NS 삭제
# ==============================================================================
if [[ "$RM_NS" =~ ^[Yy]$ ]]; then
  say "[3/8] imagePullSecret 삭제 및 namespace ${TARGET_NS} 삭제"
  kubectl -n "$TARGET_NS" delete secret gitlab-regcred --ignore-not-found >/dev/null 2>&1 || true
  say "  → gitlab-regcred 삭제"

  # SA imagePullSecrets 패치 원복 (빈 배열)
  kubectl -n "$TARGET_NS" patch serviceaccount default \
    -p '{"imagePullSecrets":[]}' >/dev/null 2>&1 || true
  say "  → default SA imagePullSecrets 초기화"

  # namespace 삭제 (포함된 리소스 전체 제거됨)
  if kubectl get ns "$TARGET_NS" >/dev/null 2>&1; then
    kubectl delete ns "$TARGET_NS" --ignore-not-found >/dev/null
    say "✅ namespace 삭제 완료: ${TARGET_NS}"
    # Terminating stuck 방지: 대기
    echo -n "   namespace 종료 대기 중"
    for i in $(seq 1 60); do
      kubectl get ns "$TARGET_NS" >/dev/null 2>&1 || break
      echo -n "."
      sleep 3
    done
    echo
    kubectl get ns "$TARGET_NS" >/dev/null 2>&1 && warn "⚠️  namespace가 아직 Terminating. 수동 확인 필요" || say "✅ namespace 완전 삭제"
  else
    warn "⏭ namespace 없음: ${TARGET_NS}"
  fi
else
  warn "⏭ namespace 삭제 스킵"
fi

# ==============================================================================
# ④ Argo TLS CA configmap 삭제
# ==============================================================================
if [[ "$RM_TLS" =~ ^[Yy]$ ]]; then
  say "[4/8] Argo TLS CA configmap 삭제"
  kubectl -n "$ARGO_NS" delete configmap argocd-tls-certs-cm --ignore-not-found >/dev/null
  say "✅ argocd-tls-certs-cm 삭제 완료"
else
  warn "⏭ TLS CA configmap 삭제 스킵"
fi

# ==============================================================================
# ⑤ Argo CD 전체 삭제
# ==============================================================================
if [[ "$RM_ARGO" =~ ^[Yy]$ ]]; then
  say "[5/8] Argo CD 삭제 (namespace=${ARGO_NS})"
  ARGO_MANIFEST="https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml"
  # manifest로 삭제 시도 (CRD 포함)
  kubectl delete --ignore-not-found -n "$ARGO_NS" -f "$ARGO_MANIFEST" >/dev/null 2>&1 || true
  # CRD 수동 삭제 (남아있을 경우 대비)
  for crd in \
    applications.argoproj.io \
    applicationsets.argoproj.io \
    appprojects.argoproj.io; do
    kubectl delete crd "$crd" --ignore-not-found >/dev/null 2>&1 || true
  done
  # namespace 삭제
  kubectl delete ns "$ARGO_NS" --ignore-not-found >/dev/null 2>&1 || true
  echo -n "   namespace 종료 대기 중"
  for i in $(seq 1 80); do
    kubectl get ns "$ARGO_NS" >/dev/null 2>&1 || break
    echo -n "."
    sleep 3
  done
  echo
  kubectl get ns "$ARGO_NS" >/dev/null 2>&1 && warn "⚠️  namespace Terminating stuck. 아래 명령으로 강제 삭제:
  kubectl get ns ${ARGO_NS} -o json | jq '.spec.finalizers=[]' | kubectl replace --raw /api/v1/namespaces/${ARGO_NS}/finalize -f -" \
    || say "✅ Argo CD 완전 삭제"
else
  warn "⏭ Argo CD 삭제 스킵"
fi

# ==============================================================================
# ⑥ ingress-nginx 삭제 (helm)
# ==============================================================================
if [[ "$RM_ING" =~ ^[Yy]$ ]]; then
  say "[6/8] ingress-nginx helm 삭제"
  if command -v helm >/dev/null 2>&1; then
    helm uninstall ingress-nginx -n ingress-nginx 2>/dev/null || warn "⚠️  helm release 없음 (이미 삭제됨)"
    kubectl delete ns ingress-nginx --ignore-not-found >/dev/null 2>&1 || true
    say "✅ ingress-nginx 삭제 완료"
  else
    warn "⚠️  helm 없음 → 수동 삭제 필요"
    echo "  kubectl delete ns ingress-nginx"
  fi
else
  warn "⏭ ingress-nginx 삭제 스킵"
fi

# ==============================================================================
# ⑦ MetalLB 삭제
# ==============================================================================
if [[ "$RM_METALLB" =~ ^[Yy]$ ]]; then
  say "[7/8] MetalLB 삭제"
  METALLB_VERSION="v0.14.3"
  kubectl delete --ignore-not-found \
    -f "https://raw.githubusercontent.com/metallb/metallb/${METALLB_VERSION}/config/manifests/metallb-native.yaml" \
    >/dev/null 2>&1 || true
  kubectl delete ns metallb-system --ignore-not-found >/dev/null 2>&1 || true
  say "✅ MetalLB 삭제 완료"
else
  warn "⏭ MetalLB 삭제 스킵"
fi

# ==============================================================================
# ⑧ .env 파일 TARGET_NS 라인 제거
# ==============================================================================
if [[ "$RM_ENV" =~ ^[Yy]$ ]]; then
  say "[8/8] .env 파일에서 TARGET_NS 관련 라인 제거: ${ENV_FILE}"
  # bootstrap이 추가한 3줄(주석, 빈줄 포함)을 삭제
  sed -i '/^# 배포 대상 namespace (setup_gitops_repo.sh와 공유)$/d' "$ENV_FILE"
  sed -i '/^TARGET_NS=/d' "$ENV_FILE"
  say "✅ .env TARGET_NS 제거 완료"
else
  warn "⏭ .env 수정 스킵"
fi

echo
say "=================================================="
say " 롤백 완료!"
say "=================================================="
echo
warn "※ Helm 바이너리 자체를 제거하려면:"
echo "   sudo rm -f /usr/local/bin/helm"
echo
warn "※ namespace가 Terminating stuck이면 강제 해제:"
echo "   NS=<namespace>"
echo '   kubectl get ns $NS -o json \'
echo '     | jq ".spec.finalizers=[]" \'
echo '     | kubectl replace --raw /api/v1/namespaces/$NS/finalize -f -'
echo
warn "※ MetalLB/ingress CRD가 남아있으면:"
echo "   kubectl get crd | grep -E 'metallb|nginx' | awk '{print \$1}' | xargs kubectl delete crd"
