🏗️ On-Prem GitOps Microservices Platform
(Google Online Boutique on Kubernetes 기반 MSA 운영 자동화)
프로젝트 한줄 요약
온프레미스 kubeadm Kubernetes 클러스터 위에 GitLab CI, Argo CD, 모니터링 스택을 연동해 Google Online Boutique MSA를 GitOps 방식으로 자동 배포·운영하는 플랫폼입니다.

주요 특징
kubeadm 기반 온프렘 Kubernetes 클러스터 구성 및 GitLab Runner 연동

GitLab CI → Container Registry → Argo CD로 이어지는 풀 GitOps 배포 파이프라인

Argo CD 자동 Sync / Self-heal로 선언적 상태 유지, 롤백·이력 추적

Prometheus / Loki / Grafana / Alertmanager → Slack 연동으로 관측·알림 자동화

장애 상황별 Runbook과 실제 Troubleshooting 로그를 Wiki에 정리

본인 역할
전체 아키텍처 설계 및 인프라 구축 (Kubernetes 클러스터, 네트워크, 스토리지)

GitLab CI 파이프라인 작성 및 이미지 빌드·배포 자동화 구성

Argo CD 애플리케이션 구조 설계, Git 리포지토리 구조 정의

모니터링/로깅 스택 통합 및 Slack 알림 룰 구성

운영 중 발생한 이슈 진단 및 해결, Runbook·Troubleshooting 문서화

빠른 시작 (Quick Start)
사전 요구사항:

Kubernetes 1.xx 이상, kubectl, Helm, GitLab 인스턴스, Container Registry 접근 권한

레포지토리 클론

bash
git clone https://github.com/msp-architect-2026/kim-jaehoon.git
cd kim-jaehoon
기본 설정 값 수정

bash
cp config/example.values.yaml config/values.yaml
# GitLab/Registry/Slack Webhook 등 환경에 맞게 수정
클러스터에 기본 리소스 배포

bash
make bootstrap   # 또는 ./scripts/bootstrap.sh
Argo CD에서 Git 리포지토리를 등록하고 애플리케이션 Sync

(실제 명령어/스크립트 이름에 맞춰 수정하면 돼.)

아키텍처
온프렘 K8s 클러스터에 CI 파이프라인(좌측)과 GitOps/관측 플로우(중앙·우측)가 연결된 전체 운영 흐름입니다.

Wiki (상세 문서)
구축 절차, 운영 Runbook, 트러블슈팅, 검증/증빙 스크린샷 등 상세 내용은 Wiki에서 관리합니다.

Wiki Home: https://github.com/msp-architect-2026/kim-jaehoon/wiki

Troubleshooting Log: https://github.com/msp-architect-2026/kim-jaehoon/wiki/TroubleshootingLog

