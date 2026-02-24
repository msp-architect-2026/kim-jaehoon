## 프로젝트 소개
온프레미스 환경에서 kubeadm 기반 Kubernetes 클러스터를 구성하고,  
GitLab CI + Container Registry로 이미지를 빌드/푸시한 뒤,  
Argo CD가 Git 변경사항을 감지해 자동 Sync / Self-heal로 배포 상태를 유지하도록 구축했습니다.  
또한 Prometheus/Loki/Grafana + Alertmanager→Slack으로 관측/알림까지 운영 흐름으로 연결했습니다.

## 내가 만든 것 (Role & Contribution)
- GitLab CI로 이미지 빌드/푸시 파이프라인 구성 (**Commit SHA 기반 immutable tag**)
- CI가 `gitops-repo`의 이미지 태그를 자동 갱신하도록 설계/구현 (**배포 선언 상태 업데이트 자동화**)
- Argo CD **Auto Sync + Self-heal**로 Git 상태 기반 배포 일관성 유지
- Prometheus/Loki/Grafana + Alertmanager→Slack 연동으로 **장애 인지/알림 흐름** 구성

## Evidence (Screenshots)
- 증빙 모음: `Wiki/Evidence` (GitLab Pipeline / Argo Sync / Grafana / Slack 알림)

## 아키텍처
![Architecture](./docs/images/architecture.drawio.png)

## Wiki (상세 문서)
구축 절차, 운영 Runbook, 트러블슈팅, 검증/증빙 스크린샷 등 상세 내용은 Wiki에서 관리합니다.
- Wiki Home: https://github.com/msp-architect-2026/kim-jaehoon/wiki
- Troubleshooting Log: https://github.com/msp-architect-2026/kim-jaehoon/wiki/TroubleshootingLog
