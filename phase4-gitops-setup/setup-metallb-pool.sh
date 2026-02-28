#!/usr/bin/env bash
set -euo pipefail

say(){ echo -e "\033[0;32m$*\033[0m"; }
warn(){ echo -e "\033[1;33m$*\033[0m"; }
err(){ echo -e "\033[0;31m$*\033[0m"; }

echo "=================================================="
echo " MetalLB IP Pool 할당 및 Ingress VIP 연동 테스트"
echo " (학원 네트워크 충돌 방지 Ping 검증 포함)"
echo "=================================================="

# 1. MetalLB 설치 상태 확인 (Phase 3에서 설치되었다고 가정)
say "🔎 MetalLB 파드 기동 상태 확인 중..."

METALLB_VERSION="v0.14.3"

# controller / speaker / webhook-server 3종 모두 체크
if kubectl -n metallb-system rollout status deploy/controller     --timeout=120s >/dev/null 2>&1 && \
   kubectl -n metallb-system rollout status ds/speaker            --timeout=120s >/dev/null 2>&1 && \
   kubectl -n metallb-system rollout status deploy/webhook-server --timeout=120s >/dev/null 2>&1; then
  say "✅ MetalLB 정상 동작 확인 완료 (controller + speaker + webhook-server)"
else
  warn "⚠️ MetalLB 컴포넌트가 준비되지 않았습니다. 매니페스트를 재배포합니다."
  kubectl apply -f "https://raw.githubusercontent.com/metallb/metallb/${METALLB_VERSION}/config/manifests/metallb-native.yaml" >/dev/null
  say "⏳ MetalLB controller rollout 대기(최대 3분)..."
  kubectl -n metallb-system rollout status deploy/controller     --timeout=180s
  say "⏳ MetalLB speaker rollout 대기(최대 3분)..."
  kubectl -n metallb-system rollout status ds/speaker            --timeout=180s
  say "⏳ MetalLB webhook-server rollout 대기(최대 3분)..."
  kubectl -n metallb-system rollout status deploy/webhook-server --timeout=180s
  say "⏳ MetalLB webhook 소켓 준비 대기(10초)..."
  sleep 10
  say "✅ MetalLB 재배포 및 기동 완료 (${METALLB_VERSION})"
fi

# 2. IP 충돌 검사 및 IP Pool 입력 로직
echo
warn "--------------------------------------------------"
warn " 🚀 MetalLB IP Pool 선정 (학원망 보호)"
warn "--------------------------------------------------"

while true; do
  read -rp "▶ 사용할 IP 대역을 입력하세요 (예: 192.168.10.200-192.168.10.220): " IP_RANGE

  # 입력 형식 검증
  if [[ ! "$IP_RANGE" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+-[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    err "❌ 입력 형식이 올바르지 않습니다. 다시 입력해주세요."
    continue
  fi

  START_IP="${IP_RANGE%-*}"
  END_IP="${IP_RANGE#*-}"

  # IP 주소를 정수로 변환하는 함수
  ip2int() {
    local a b c d
    IFS=. read -r a b c d <<< "$1"
    echo $(( (a << 24) + (b << 16) + (c << 8) + d ))
  }
  # 정수를 다시 IP 주소로 변환하는 함수
  int2ip() {
    local ui32=$1
    local a=$(( (ui32 >> 24) & 0xff ))
    local b=$(( (ui32 >> 16) & 0xff ))
    local c=$(( (ui32 >>  8) & 0xff ))
    local d=$(( ui32 & 0xff ))
    echo "$a.$b.$c.$d"
  }

  start_int=$(ip2int "$START_IP")
  end_int=$(ip2int "$END_IP")

  if (( start_int > end_int )); then
    err "❌ 시작 IP가 종료 IP보다 큽니다. 다시 입력해주세요."
    continue
  fi

  say "\n🔎 IP 충돌 검사 시작 ($START_IP ~ $END_IP) ..."
  CONFLICT=false

  for (( i=start_int; i<=end_int; i++ )); do
    current_ip=$(int2ip "$i")
    echo -n "   - $current_ip 검사 중... "

    # Ping 1회 전송, 타임아웃 1초
    if ping -c 1 -W 1 "$current_ip" >/dev/null 2>&1; then
      err "[경고] 응답 있음! (누군가 사용 중)"
      CONFLICT=true
      break
    else
      say "[안전] 사용 가능"
    fi
  done

  if [ "$CONFLICT" = true ]; then
    warn "\n⚠️ 해당 대역에는 이미 사용 중인 IP가 포함되어 있습니다."
    warn "네트워크 마비를 막기 위해 다른 대역을 선택해주세요."
    echo "--------------------------------------------------"
    continue
  else
    say "\n✅ 충돌 없음! 입력하신 대역($IP_RANGE)을 MetalLB IP Pool로 확정합니다."
    break
  fi
done

# 3. IP Pool 및 L2Advertisement CRD 생성
say "\n[3/4] 검증된 IP Pool 매니페스트(CRD) 적용 중..."
cat <<EOF | kubectl apply -f - >/dev/null
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: pool-l2
  namespace: metallb-system
spec:
  addresses:
  - ${IP_RANGE}
---
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata:
  name: l2adv
  namespace: metallb-system
spec:
  ipAddressPools:
  - pool-l2
EOF
say "✅ IP Pool 생성 완료"

# 4. Ingress VIP 할당 검증 및 테스트
say "\n[4/4] Ingress Controller VIP 할당 대기 및 검증"
echo "⏳ MetalLB가 Ingress에 IP를 부여할 때까지 대기합니다(최대 30초)..."

VIP=""
for i in {1..10}; do
  VIP="$(kubectl -n ingress-nginx get svc ingress-nginx-controller -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || true)"
  if [[ -n "$VIP" ]]; then
    break
  fi
  sleep 3
done

if [[ -z "$VIP" ]]; then
  err "❌ Ingress Controller가 IP를 할당받지 못했습니다. 설정 확인이 필요합니다."
  kubectl -n ingress-nginx get svc ingress-nginx-controller
  exit 1
fi

say "🎉 성공! Ingress Controller에 외부 VIP가 할당되었습니다: ${VIP}"

echo
warn "--------------------------------------------------"
warn " 🌐 최종 라우팅 테스트 (curl)"
warn "--------------------------------------------------"
echo "명령어: curl -sS -H \"Host: boutique.local\" http://${VIP}/"
# 실제 앱이 없으므로 404가 뜨는 것이 정상 동작임을 안내
echo "※ 아직 애플리케이션(파드)이 배포되지 않았으므로 '404 Not Found'가 뜨는 것이 완벽히 정상입니다."
echo

curl -sS -H "Host: boutique.local" "http://${VIP}/" | head -n 10 || true

echo
say "=================================================="
say " 모든 인프라 네트워크 기반 설정이 완료되었습니다!"
say " 이제 Argo CD를 통해 애플리케이션을 배포할 준비가 끝났습니다."
say "=================================================="
