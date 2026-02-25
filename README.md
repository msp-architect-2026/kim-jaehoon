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

## 🗺️ Architecture & Workflow

### Application Flow
![Application Flow](./docs/images/app_flow.png)

### K8s Node Roles
![K8s Node Roles](./docs/images/k8s-node-roles.png)

### CI/CD & GitOps Platform
![CI/CD & GitOps](./docs/images/cicd-gitops-platform.png)

---

## 📚 Documentation
상세 구축 가이드, 아키텍처 설계 배경 및 트러블슈팅 기록은 Wiki에서 관리합니다.
- [🏠 Wiki Home](https://github.com/msp-architect-2026/kim-jaehoon/wiki)
