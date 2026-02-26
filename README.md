# 🏗️ On-Prem GitOps Microservices Platform

> Google Online Boutique 기반 MSA K8s 운영 자동화 및 관측성(Observability) 통합 파이프라인

## 🎯 Project Overview
온프레미스(kubeadm) 환경에서 코드 푸시부터 배포, 모니터링, 알림(Slack)까지 이어지는 GitOps 기반 운영 플랫폼입니다. 수동 개입을 최소화하고 상태를 선언적으로 관리(Self-Heal)하여 인프라의 신뢰성을 높였습니다.

## 🛠️ Tech Stack
<div align="left">
  <img src="https://img.shields.io/badge/kubernetes-326CE5?style=for-the-badge&logo=kubernetes&logoColor=white">
  <img src="https://img.shields.io/badge/gitlab-FC6D26?style=for-the-badge&logo=gitlab&logoColor=white">
  <img src="https://img.shields.io/badge/argo%20cd-EF7B4D?style=for-the-badge&logo=argo&logoColor=white">
  <img src="https://img.shields.io/badge/prometheus-E6522C?style=for-the-badge&logo=prometheus&logoColor=white">
  <img src="https://img.shields.io/badge/grafana-F46800?style=for-the-badge&logo=grafana&logoColor=white">
</div>

## 💻 Live Action
![Demo](./docs/images/online-boutique-home.png)

---

## 🗺️ Master Architecture Blueprint


> 플랫폼 서버(CI/CD Hub)와 Kubernetes 클러스터(Runtime)를 분리하여 설계한 통합 데이터 흐름도입니다.

[![Master Architecture](./docs/images/mainarchitecture.png)](./docs/images/mainarchitecture.png)

### 📌 Core Features
* **Automated CI/CD:** GitLab CI를 통한 이미지 빌드 및 Argo CD 기반의 선언적(Declarative) 배포
* **Traffic Routing:** MetalLB와 Ingress-NGINX를 통한 최적화된 외부 트래픽 인입 경로 제공
* **Observability:** Prometheus, Loki, Promtail을 활용한 중앙 집중식 모니터링 및 Slack 알림 연동

---
## 🧱 Environment

**DevOps Platform Server**: GitLab · Registry · Runner · Grafana  
**Kubernetes Cluster**: 1 Control Plane + 2 Worker (VM)  
**OS**: Ubuntu 22.04 LTS · **Runtime**: containerd · **K8s**: kubeadm (v1.xx)  
**Networking**: MetalLB(L2) → Ingress-NGINX(L7)  
**Observability**: Prometheus · Loki · Grafana Alerting → **Slack(Webhook)**

## 📚 Documentation & Deep Dive

아키텍처 설계 배경, 컴포넌트별 세부 구성, 트러블슈팅 기록 등 상세한 엔지니어링 문서는 Wiki에서 제공합니다.

* [🏠 Wiki Home](https://github.com/msp-architect-2026/kim-jaehoon/wiki)
* [🖥️ Infrastructure Architecture](https://github.com/msp-architect-2026/kim-jaehoon/wiki/Infrastructure-Architecture)
* [📦 Application Architecture](https://github.com/msp-architect-2026/kim-jaehoon/wiki/Application-Architecture)
