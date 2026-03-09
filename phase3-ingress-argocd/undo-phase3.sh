#!/usr/bin/env bash
set -euo pipefail

say(){ echo -e "\033[0;32m$*\033[0m"; }
warn(){ echo -e "\033[1;33m$*\033[0m"; }
err(){ echo -e "\033[0;31m$*\033[0m"; }

need(){ command -v "$1" >/dev/null 2>&1 || { err "❌ '$1' 필요"; exit 1; }; }
need kubectl

ARGO_NS="${ARGO_NS:-argocd}"
TARGET_NS="${TARGET_NS:-demo}"
INGRESS_NS="${INGRESS_NS:-ingress-nginx}"
METALLB_NS="${METALLB_NS:-metallb-system}"

CTX="$(kubectl config current-context 2>/dev/null || true)"

echo "=================================================="
echo " 🧨 Phase 3 Destroy / Cleanup (호환성 및 안전성 강화)"
echo "=================================================="
warn "현재 kubectl context: ${CTX:-<unknown>}"
warn "삭제 대상:"
warn " - TARGET_NS : ${TARGET_NS}"
warn " - ARGO_NS   : ${ARGO_NS}"
warn " - INGRESS_NS: ${INGRESS_NS}"
warn " - METALLB_NS: ${METALLB_NS}"
echo "=================================================="
read -rp "정말 삭제할까요? (y/n) [기본 n]: " OK
OK="${OK:-n}"
[[ "$OK" =~ ^[Yy]$ ]] || { echo "취소"; exit 0; }

echo

# ---------------------------------------------------------
# 1) Argo Application / argoproj CR finalizer 안전 제거
# ---------------------------------------------------------
if kubectl get ns "$ARGO_NS" >/dev/null 2>&1; then
  say "[1/6] Argo CD CR(Application 등) 정리 + finalizer 강제 제거"

  if kubectl api-resources --api-group=argoproj.io -o name >/dev/null 2>&1; then
    for r in applications.argoproj.io appprojects.argoproj.io applicationsets.argoproj.io; do
      if kubectl get "$r" -A >/dev/null 2>&1; then
        warn " - $r: finalizer 제거 후 전체 삭제 진행"
        kubectl get "$r" -A -o name \
          | xargs -r -I{} kubectl patch {} --type=merge -p '{"metadata":{"finalizers":[]}}' >/dev/null 2>&1 || true
        kubectl delete "$r" --all -A --ignore-not-found=true >/dev/null 2>&1 || true
      fi
    done
  fi
else
  warn "[1/6] ARGO_NS(${ARGO_NS}) 없음 → Argo CR 정리 스킵"
fi

# ---------------------------------------------------------
# 2) Target namespace 삭제 (앱/ingress 등 함께 정리)
# ---------------------------------------------------------
say "[2/6] TARGET_NS(${TARGET_NS}) 삭제"
kubectl delete ns "$TARGET_NS" --ignore-not-found=true >/dev/null 2>&1 || true

# ---------------------------------------------------------
# 3) Argo CD uninstall (manifest) + namespace 삭제
# ---------------------------------------------------------
if kubectl get ns "$ARGO_NS" >/dev/null 2>&1; then
  say "[3/6] Argo CD uninstall(manifest) + namespace 삭제"
  ARGO_MANIFEST="https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml"
  kubectl delete -f "$ARGO_MANIFEST" --ignore-not-found=true >/dev/null 2>&1 || true
  kubectl delete ns "$ARGO_NS" --ignore-not-found=true >/dev/null 2>&1 || true
else
  warn "[3/6] ARGO_NS(${ARGO_NS}) 없음 → Argo uninstall 스킵"
fi

# ---------------------------------------------------------
# 4) Ingress-NGINX 제거 (helm 의존성 최소화)
# ---------------------------------------------------------
say "[4/6] Ingress-NGINX 제거"
if command -v helm >/dev/null 2>&1; then
  if helm status ingress-nginx -n "$INGRESS_NS" >/dev/null 2>&1; then
    helm uninstall ingress-nginx -n "$INGRESS_NS" >/dev/null 2>&1 || true
  fi
else
  warn " - helm 명령어 없음 → namespace 삭제로 강제 정리 시도"
fi
kubectl delete ns "$INGRESS_NS" --ignore-not-found=true >/dev/null 2>&1 || true

# ---------------------------------------------------------
# 5) MetalLB 제거: 리소스 전체 → manifest → ns → crd 정리
# ---------------------------------------------------------
say "[5/6] MetalLB 제거"
if kubectl api-resources --api-group=metallb.io -o name >/dev/null 2>&1; then
  while read -r r; do
    [[ -z "$r" ]] && continue
    kubectl delete "$r" --all -A --ignore-not-found=true >/dev/null 2>&1 || true
  done < <(kubectl api-resources --api-group=metallb.io -o name)
fi

METALLB_MANIFEST="https://raw.githubusercontent.com/metallb/metallb/v0.14.3/config/manifests/metallb-native.yaml"
kubectl delete -f "$METALLB_MANIFEST" --ignore-not-found=true >/dev/null 2>&1 || true
kubectl delete ns "$METALLB_NS" --ignore-not-found=true >/dev/null 2>&1 || true

kubectl get crd -o name 2>/dev/null | grep -E '(\.|/)metallb\.io' \
  | xargs -r kubectl delete --ignore-not-found=true >/dev/null 2>&1 || true

# ---------------------------------------------------------
# 6) Argo CD CRD 타겟팅 정리
# ---------------------------------------------------------
say "[6/6] Argo CD CRD 정확히 타겟팅하여 정리"
for crd in applications.argoproj.io appprojects.argoproj.io applicationsets.argoproj.io; do
  kubectl delete crd "$crd" --ignore-not-found=true >/dev/null 2>&1 || true
done

echo
say "=================================================="
say "✅ Cleanup 로직 실행 완료"
say "=================================================="
echo

# ---------------------------------------------------------
# 7) 🔍 최종 삭제 상태 검증 및 리포트 (체크리스트)
# ---------------------------------------------------------
warn "🔍 잔여 리소스 검증을 시작합니다. (아래 항목에 아무것도 출력되지 않아야 완벽한 삭제입니다)"
echo "--------------------------------------------------"

say "1. 잔여 네임스페이스 확인:"
kubectl get ns | grep -E 'argocd|ingress-nginx|metallb-system|demo' || echo " -> 깨끗함"
echo

say "2. 잔여 CRD(Custom Resource Definitions) 확인:"
kubectl get crd | grep -E 'applications\.argoproj\.io|appprojects\.argoproj\.io|applicationsets\.argoproj\.io|metallb\.io' || echo " -> 깨끗함"
echo

say "3. 잔여 ClusterRole / ClusterRoleBinding 확인:"
kubectl get clusterrole,clusterrolebinding | grep -E 'argocd|metallb|ingress' || echo " -> 깨끗함"
echo

say "4. 잔여 Webhook Configuration 확인:"
kubectl get validatingwebhookconfiguration,mutatingwebhookconfiguration | grep -E 'argocd|metallb|ingress' || echo " -> 깨끗함"
echo "--------------------------------------------------"
say "🎉 검증 완료! 출력된 잔여물이 없다면 완벽한 백지 상태입니다."
