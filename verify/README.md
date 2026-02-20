# verify/ - 검증 스크립트

## 역할
각 Phase 완료 후 **제대로 구축되었는지 자동 확인**

## 스크립트 목록 (예정)
- `verify-network.sh` - 네트워크 연결 확인
- `verify-k8s.sh` - K8s 클러스터 상태
- `verify-ingress.sh` - Ingress 동작 확인
- `verify-argocd.sh` - Argo CD 접속/repo 연결
- `verify-observability.sh` - Prometheus/Loki 수집

## 사용법
```bash
# Phase 2 끝나면
bash verify/verify-k8s.sh

# 전체 검증
make verify-all
```

## 검증 기준
- 네트워크: ping 응답
- K8s: 3 nodes Ready, CoreDNS Running
- Ingress: test pod 접근 가능
- Argo: UI 접속 + repo sync 성공
