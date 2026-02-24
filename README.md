# 🏗️ On-Prem GitOps Microservices Platform
> **Google Online Boutique 기반 MSA K8s 운영 자동화 및 관측성(Observability) 통합 파이프라인**

## 🎯 Project Overview
온프레미스(kubeadm) 환경에서 코드 푸시부터 배포, 모니터링, 알림(Slack)까지 이어지는 GitOps 기반 운영 플랫폼입니다. 수동 개입을 최소화하고 상태를 선언적으로 관리(Self-Heal)하여 인프라의 신뢰성을 높였습니다.

## 💻 Live Action
![Demo](./docs/images/demo.gif)

## 🗺️ Architecture & Workflow
![Architecture Diagram](./docs/images/architecture.png) 

* **CI Pipeline:** GitLab CI ➔ Container Registry
* **CD Pipeline (GitOps):** Manifest Repository ➔ Argo CD ➔ Kubernetes
* **Observability:** Prometheus / Loki ➔ Grafana ➔ Alertmanager ➔ Slack

---

## 📚 Documentation
상세 구축 가이드, 아키텍처 설계 배경 및 트러블슈팅 기록은 Wiki에서 관리합니다.

* **[Wiki Home (구축 절차 및 Runbook)](https://github.com/msp-architect-2026/kim-jaehoon/wiki)**
* **[Engineering Decisions (도입 배경 및 의사결정)](위키링크를_여기에_넣으세요)**
* **[Troubleshooting Log (이슈 원인 분석 및 해결 과정)](https://github.com/msp-architect-2026/kim-jaehoon/wiki/TroubleshootingLog)**
